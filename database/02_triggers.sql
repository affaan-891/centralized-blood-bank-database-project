-- ============================================================================
-- Project: Centralized Blood Bank & Emergency Donor Match Registry
-- Target RDBMS: MySQL 8.0+ / MariaDB 10.4+ (InnoDB Engine)
-- File: 02_triggers.sql (Business Rules & Automated Integrity Triggers)
-- Specification: Clinical donor deferrals, shelf-life calculation, and audit trail
-- Author: Principal Database Architect
-- ============================================================================

USE blood_bank_db;

-- ----------------------------------------------------------------------------
-- Drop Existing Triggers
-- ----------------------------------------------------------------------------
DROP TRIGGER IF EXISTS trg_validate_donor_interval_before_donation;
DROP TRIGGER IF EXISTS trg_update_donor_last_donation_date;
DROP TRIGGER IF EXISTS trg_set_component_shelf_life_on_unit_creation;
DROP TRIGGER IF EXISTS trg_log_unit_creation;
DROP TRIGGER IF EXISTS trg_log_unit_status_transitions;

DELIMITER //

-- ============================================================================
-- Trigger 1: trg_validate_donor_interval_before_donation
-- Event: BEFORE INSERT ON blood_donations
-- Purpose: Enforce clinical blood safety regulations:
--          1. Check donor's current eligibility_status == 'Eligible'
--          2. Enforce minimum 90-day (12-week) inter-donation interval
-- ============================================================================
CREATE TRIGGER trg_validate_donor_interval_before_donation
BEFORE INSERT ON blood_donations
FOR EACH ROW
BEGIN
    DECLARE v_donor_status ENUM('Eligible','Deferred_Temporary','Deferred_Permanent');
    DECLARE v_last_donation DATE;
    DECLARE v_days_since_last INT;

    -- Fetch current donor metadata
    SELECT eligibility_status, last_donation_date
      INTO v_donor_status, v_last_donation
      FROM donors
     WHERE donor_id = NEW.donor_id;

    -- Rule 1: Donor must be clinically marked as Eligible
    IF v_donor_status IS NULL OR v_donor_status <> 'Eligible' THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Donor deferral policy: Minimum 90 days required between donations or donor is not eligible.';
    END IF;

    -- Rule 2: Minimum 90 days must elapse between successive donations
    IF v_last_donation IS NOT NULL THEN
        SET v_days_since_last = DATEDIFF(NEW.donation_date, v_last_donation);
        IF v_days_since_last < 90 THEN
            SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Donor deferral policy: Minimum 90 days required between donations or donor is not eligible.';
        END IF;
    END IF;
END //

-- ============================================================================
-- Auxiliary Trigger: trg_update_donor_last_donation_date
-- Event: AFTER INSERT ON blood_donations
-- Purpose: Keep donors.last_donation_date synchronized without requiring
--          application-level dual-write logic.
-- ============================================================================
CREATE TRIGGER trg_update_donor_last_donation_date
AFTER INSERT ON blood_donations
FOR EACH ROW
BEGIN
    UPDATE donors
       SET last_donation_date = NEW.donation_date
     WHERE donor_id = NEW.donor_id;
END //

-- ============================================================================
-- Trigger 2: trg_set_component_shelf_life_on_unit_creation
-- Event: BEFORE INSERT ON blood_units
-- Purpose: Automatically calculate regulatory expiry dates based on blood component:
--          - Platelets: 5 days (room temperature with agitation)
--          - Red Blood Cells (RBC): 42 days (refrigerated with SAGM preservative)
--          - Whole Blood: 35 days (refrigerated CPDA-1 solution)
--          - Fresh Frozen Plasma (FFP): 365 days (frozen at -18C or colder)
-- ============================================================================
CREATE TRIGGER trg_set_component_shelf_life_on_unit_creation
BEFORE INSERT ON blood_units
FOR EACH ROW
BEGIN
    CASE NEW.component_type
        WHEN 'Platelets' THEN
            SET NEW.expiry_date = DATE_ADD(NEW.collection_date, INTERVAL 5 DAY);
        WHEN 'RBC' THEN
            SET NEW.expiry_date = DATE_ADD(NEW.collection_date, INTERVAL 42 DAY);
        WHEN 'Whole_Blood' THEN
            SET NEW.expiry_date = DATE_ADD(NEW.collection_date, INTERVAL 35 DAY);
        WHEN 'Plasma' THEN
            SET NEW.expiry_date = DATE_ADD(NEW.collection_date, INTERVAL 365 DAY);
        ELSE
            SET NEW.expiry_date = DATE_ADD(NEW.collection_date, INTERVAL 35 DAY);
    END CASE;
END //

-- ============================================================================
-- Auxiliary Trigger: trg_log_unit_creation
-- Event: AFTER INSERT ON blood_units
-- Purpose: Record the initial 'COLLECTION' entry in blood_audit_logs to satisfy
--          strict chain-of-custody compliance.
-- ============================================================================
CREATE TRIGGER trg_log_unit_creation
AFTER INSERT ON blood_units
FOR EACH ROW
BEGIN
    INSERT INTO blood_audit_logs (
        unit_id,
        action_type,
        changed_by,
        comments
    ) VALUES (
        NEW.unit_id,
        'COLLECTION',
        COALESCE(CURRENT_USER(), 'SYSTEM_APP'),
        CONCAT('Initial unit creation: Component ', NEW.component_type, ' into status ', NEW.status)
    );
END //

-- ============================================================================
-- Trigger 3: trg_log_unit_status_transitions
-- Event: AFTER UPDATE ON blood_units
-- Purpose: Maintain an immutable regulatory audit trail whenever a unit's status
--          transitions across its lifecycle (Quarantine -> Available -> Reserved
--          -> Transfused / Released / Expired).
-- ============================================================================
CREATE TRIGGER trg_log_unit_status_transitions
AFTER UPDATE ON blood_units
FOR EACH ROW
BEGIN
    DECLARE v_action ENUM('COLLECTION','TESTING_PASSED','RESERVED','RELEASED','TRANSFUSED','DISCARDED_EXPIRED');
    DECLARE v_comment TEXT;

    IF OLD.status <> NEW.status THEN
        -- Map status transition to standardized audit action
        IF OLD.status = 'Quarantine' AND NEW.status = 'Available' THEN
            SET v_action = 'TESTING_PASSED';
            SET v_comment = 'Infectious disease screening passed; unit released to inventory.';
        ELSEIF NEW.status = 'Reserved' THEN
            SET v_action = 'RESERVED';
            SET v_comment = CONCAT('Unit allocated from ', OLD.status, ' to Reserved state.');
        ELSEIF OLD.status = 'Reserved' AND NEW.status = 'Available' THEN
            SET v_action = 'RELEASED';
            SET v_comment = 'Transfusion reservation expired or cancelled; unit returned to available stock.';
        ELSEIF NEW.status = 'Transfused' THEN
            SET v_action = 'TRANSFUSED';
            SET v_comment = 'Unit successfully transfused to clinical recipient.';
        ELSEIF NEW.status = 'Expired' THEN
            SET v_action = 'DISCARDED_EXPIRED';
            SET v_comment = 'Shelf life exceeded; unit marked for clinical bio-hazard incineration.';
        ELSE
            SET v_action = 'RELEASED';
            SET v_comment = CONCAT('Status transitioned from ', OLD.status, ' to ', NEW.status, '.');
        END IF;

        INSERT INTO blood_audit_logs (
            unit_id,
            action_type,
            changed_by,
            comments
        ) VALUES (
            NEW.unit_id,
            v_action,
            COALESCE(CURRENT_USER(), 'SYSTEM_APP'),
            v_comment
        );
    END IF;
END //

DELIMITER ;
