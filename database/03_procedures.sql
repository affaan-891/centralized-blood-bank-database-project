-- ============================================================================
-- Project: Centralized Blood Bank & Emergency Donor Match Registry
-- Target RDBMS: MySQL 8.0+ / MariaDB 10.4+ (InnoDB Engine)
-- File: 03_procedures.sql (Procedures & Analytical Functions)
-- Specification: Pessimistic emergency matching, reservation reclamation, & shortage index
-- Author: Principal Database Architect
-- ============================================================================

USE blood_bank_db;

-- ----------------------------------------------------------------------------
-- Drop Existing Procedures & Functions
-- ----------------------------------------------------------------------------
DROP PROCEDURE IF EXISTS sp_emergency_match_and_reserve;
DROP PROCEDURE IF EXISTS sp_release_expired_reservations;
DROP FUNCTION IF EXISTS fn_calculate_blood_group_shortage_index;

DELIMITER //

-- ============================================================================
-- Procedure 1: sp_emergency_match_and_reserve
-- Purpose: Match and allocate blood units for an emergency or routine request
--          using clinical cross-matching compatibility, FIFO shelf-life prioritization
--          (oldest non-expired unit first), and pessimistic row-level locking.
-- Parameters:
--   IN  p_request_id        : Target blood request ID
--   OUT p_units_allocated   : Number of units successfully reserved in this transaction
-- ============================================================================
CREATE PROCEDURE sp_emergency_match_and_reserve (
    IN  p_request_id      INT,
    OUT p_units_allocated INT
)
proc_label: BEGIN
    -- Local variables
    DECLARE v_req_blood_group INT;
    DECLARE v_req_component   ENUM('Whole_Blood','RBC','Platelets','Plasma');
    DECLARE v_units_requested INT;
    DECLARE v_current_status  ENUM('Pending','Partially_Fulfilled','Fulfilled','Cancelled');
    DECLARE v_already_reserved INT DEFAULT 0;
    DECLARE v_units_needed    INT DEFAULT 0;
    DECLARE v_unit_id         INT;
    DECLARE v_done            INT DEFAULT FALSE;

    -- Cursor to select compatible, available blood units with pessimistic locking
    DECLARE cur_units CURSOR FOR
        SELECT u.unit_id
          FROM blood_units u
          JOIN blood_compatibility c
            ON u.blood_group_id = c.donor_group_id
         WHERE c.recipient_group_id = v_req_blood_group
           AND c.component_type     = v_req_component
           AND u.component_type     = v_req_component
           AND u.status             = 'Available'
           AND u.expiry_date        > CURDATE()
         ORDER BY u.expiry_date ASC
         FOR UPDATE;

    -- Cursor not found handler
    DECLARE CONTINUE HANDLER FOR NOT FOUND SET v_done = TRUE;

    -- SQL Exception Handler ensuring complete rollback
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        SET p_units_allocated = 0;
        RESIGNAL;
    END;

    -- Initialize output
    SET p_units_allocated = 0;

    -- Begin ACID Transaction
    START TRANSACTION;

    -- 1. Validate request and lock row
    SELECT blood_group_id, component_type, units_requested, fulfillment_status
      INTO v_req_blood_group, v_req_component, v_units_requested, v_current_status
      FROM blood_requests
     WHERE request_id = p_request_id
       FOR UPDATE;

    IF v_req_blood_group IS NULL THEN
        ROLLBACK;
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Emergency match error: Invalid request_id specified.';
    END IF;

    IF v_current_status IN ('Fulfilled', 'Cancelled') THEN
        ROLLBACK;
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Emergency match error: Request is already Fulfilled or Cancelled.';
    END IF;

    -- 2. Determine remaining deficit
    SELECT COUNT(*)
      INTO v_already_reserved
      FROM transfusion_reservations
     WHERE request_id = p_request_id
       AND status = 'Reserved';

    SET v_units_needed = v_units_requested - v_already_reserved;

    IF v_units_needed <= 0 THEN
        UPDATE blood_requests
           SET fulfillment_status = 'Fulfilled'
         WHERE request_id = p_request_id;
        COMMIT;
        LEAVE proc_label;
    END IF;

    -- 3. Open cursor and allocate units sequentially
    OPEN cur_units;

    allocation_loop: LOOP
        FETCH cur_units INTO v_unit_id;
        IF v_done OR p_units_allocated >= v_units_needed THEN
            LEAVE allocation_loop;
        END IF;

        -- Create transfusion reservation with 2-hour clinical pickup window
        INSERT INTO transfusion_reservations (
            request_id,
            unit_id,
            reserved_at,
            reservation_expiry,
            status
        ) VALUES (
            p_request_id,
            v_unit_id,
            NOW(),
            DATE_ADD(NOW(), INTERVAL 2 HOUR),
            'Reserved'
        );

        -- Update blood unit status (triggers audit log creation)
        UPDATE blood_units
           SET status = 'Reserved'
         WHERE unit_id = v_unit_id;

        SET p_units_allocated = p_units_allocated + 1;
    END LOOP allocation_loop;

    CLOSE cur_units;

    -- 4. Update parent request fulfillment status
    IF (v_already_reserved + p_units_allocated) >= v_units_requested THEN
        UPDATE blood_requests
           SET fulfillment_status = 'Fulfilled'
         WHERE request_id = p_request_id;
    ELSEIF (v_already_reserved + p_units_allocated) > 0 THEN
        UPDATE blood_requests
           SET fulfillment_status = 'Partially_Fulfilled'
         WHERE request_id = p_request_id;
    ELSE
        UPDATE blood_requests
           SET fulfillment_status = 'Pending'
         WHERE request_id = p_request_id;
    END IF;

    -- Commit transaction
    COMMIT;
END //


-- ============================================================================
-- Procedure 2: sp_release_expired_reservations
-- Purpose: Scheduled maintenance task to identify transfusion reservations where
--          reservation_expiry has elapsed without transfusion confirmation.
--          Returns quarantined units back to 'Available' stock and updates
--          corresponding blood requests.
-- Parameters:
--   OUT p_released_count : Number of units reclaimed back to inventory
-- ============================================================================
CREATE PROCEDURE sp_release_expired_reservations (
    OUT p_released_count INT
)
BEGIN
    DECLARE v_res_id INT;
    DECLARE v_unit_id INT;
    DECLARE v_req_id INT;
    DECLARE v_done INT DEFAULT FALSE;

    -- Cursor finding all expired active reservations
    DECLARE cur_expired CURSOR FOR
        SELECT reservation_id, unit_id, request_id
          FROM transfusion_reservations
         WHERE reservation_expiry < NOW()
           AND status = 'Reserved'
         FOR UPDATE;

    DECLARE CONTINUE HANDLER FOR NOT FOUND SET v_done = TRUE;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        SET p_released_count = 0;
        RESIGNAL;
    END;

    SET p_released_count = 0;

    START TRANSACTION;

    OPEN cur_expired;

    expired_loop: LOOP
        FETCH cur_expired INTO v_res_id, v_unit_id, v_req_id;
        IF v_done THEN
            LEAVE expired_loop;
        END IF;

        -- Mark reservation as Released
        UPDATE transfusion_reservations
           SET status = 'Released'
         WHERE reservation_id = v_res_id;

        -- Return blood unit to available stock (triggers audit trail)
        UPDATE blood_units
           SET status = 'Available'
         WHERE unit_id = v_unit_id;

        -- Recalculate request fulfillment status
        UPDATE blood_requests
           SET fulfillment_status = CASE
               WHEN (
                   SELECT COUNT(*)
                     FROM transfusion_reservations
                    WHERE request_id = v_req_id
                      AND status = 'Reserved'
               ) > 0 THEN 'Partially_Fulfilled'
               ELSE 'Pending'
           END
         WHERE request_id = v_req_id;

        SET p_released_count = p_released_count + 1;
    END LOOP expired_loop;

    CLOSE cur_expired;

    COMMIT;
END //


-- ============================================================================
-- Function: fn_calculate_blood_group_shortage_index
-- Purpose: Analytical metric computing demand-to-supply deficit ratio:
--          Shortage Index = (Pending Requested Units / Available In-Stock Units)
--          - Returns 0.00 if no pending requests exist.
--          - Returns 999.99 if available units == 0 but demand is active.
--          - Supports optional city-level filtering.
-- ============================================================================
CREATE FUNCTION fn_calculate_blood_group_shortage_index (
    p_blood_group_id INT,
    p_city           VARCHAR(50)
)
RETURNS DECIMAL(5,2)
DETERMINISTIC
READS SQL DATA
BEGIN
    DECLARE v_pending_units INT DEFAULT 0;
    DECLARE v_available_units INT DEFAULT 0;
    DECLARE v_index DECIMAL(5,2) DEFAULT 0.00;

    -- Calculate total pending / partially fulfilled units requested
    SELECT COALESCE(SUM(r.units_requested), 0)
      INTO v_pending_units
      FROM blood_requests r
      JOIN hospitals h ON r.hospital_id = h.hospital_id
     WHERE r.blood_group_id = p_blood_group_id
       AND r.fulfillment_status IN ('Pending', 'Partially_Fulfilled')
       AND (p_city IS NULL OR p_city = '' OR LOWER(h.city) = LOWER(p_city));

    -- Calculate total verified available units currently in stock
    SELECT COALESCE(COUNT(*), 0)
      INTO v_available_units
      FROM blood_units u
     WHERE u.blood_group_id = p_blood_group_id
       AND u.status = 'Available'
       AND u.expiry_date > CURDATE();

    -- Compute shortage index ratio
    IF v_available_units = 0 THEN
        IF v_pending_units = 0 THEN
            SET v_index = 0.00;
        ELSE
            SET v_index = 999.99; -- Extreme critical deficit
        END IF;
    ELSE
        SET v_index = ROUND(v_pending_units / v_available_units, 2);
    END IF;

    RETURN v_index;
END //

DELIMITER ;
