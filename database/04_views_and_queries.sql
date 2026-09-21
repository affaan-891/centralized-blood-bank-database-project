-- ============================================================================
-- Project: Centralized Blood Bank & Emergency Donor Match Registry
-- Target RDBMS: MySQL 8.0+ / MariaDB 10.4+ (InnoDB Engine)
-- File: 04_views_and_queries.sql (Analytical Views & Viva Examination Queries)
-- Specification: Real-time inventory aggregates, hospital demand matrix & viva queries
-- Author: Principal Database Architect
-- ============================================================================

USE blood_bank_db;

-- ----------------------------------------------------------------------------
-- Drop Existing Views
-- ----------------------------------------------------------------------------
DROP VIEW IF EXISTS vw_live_blood_stock_summary;
DROP VIEW IF EXISTS vw_hospital_emergency_demand_matrix;

-- ============================================================================
-- View 1: vw_live_blood_stock_summary
-- Purpose: Real-time aggregated inventory dashboard reflecting clinically available,
--          screened blood units grouped by antigen (ABO/Rh) and component type.
--          Highlights perishable inventory expiring within 3 and 7-day alert windows.
-- ============================================================================
CREATE VIEW vw_live_blood_stock_summary AS
SELECT 
    bg.group_id,
    bg.group_name,
    bg.rh_factor,
    bu.component_type,
    COUNT(bu.unit_id) AS total_available_units,
    SUM(CASE 
        WHEN bu.expiry_date <= DATE_ADD(CURDATE(), INTERVAL 3 DAY) THEN 1 
        ELSE 0 
    END) AS units_expiring_within_3_days,
    SUM(CASE 
        WHEN bu.expiry_date <= DATE_ADD(CURDATE(), INTERVAL 7 DAY) THEN 1 
        ELSE 0 
    END) AS units_expiring_within_7_days,
    MIN(bu.expiry_date) AS oldest_unit_expiry_date,
    MAX(bu.collection_date) AS freshest_collection_date
FROM blood_groups bg
JOIN blood_units bu 
  ON bg.group_id = bu.blood_group_id
WHERE bu.status = 'Available'
  AND bu.expiry_date > CURDATE()
GROUP BY 
    bg.group_id,
    bg.group_name,
    bg.rh_factor,
    bu.component_type;

-- ============================================================================
-- View 2: vw_hospital_emergency_demand_matrix
-- Purpose: Strategic analytics reporting hospital transfusion request volume,
--          triage urgency stratification, demand fulfillment rate, and average
--          clinical turnaround fulfillment latency (in hours).
-- ============================================================================
CREATE VIEW vw_hospital_emergency_demand_matrix AS
SELECT 
    h.hospital_id,
    h.hospital_name,
    h.city,
    h.tier,
    COUNT(r.request_id) AS total_requests,
    SUM(CASE WHEN r.urgency_level = 'Critical' THEN 1 ELSE 0 END) AS critical_requests_count,
    COALESCE(SUM(r.units_requested), 0) AS total_units_requested,
    COALESCE(SUM(
        CASE 
            WHEN r.fulfillment_status = 'Fulfilled' THEN r.units_requested
            WHEN r.fulfillment_status = 'Partially_Fulfilled' THEN (
                SELECT COUNT(*) 
                FROM transfusion_reservations tr 
                WHERE tr.request_id = r.request_id 
                  AND tr.status IN ('Reserved', 'Transfused')
            )
            ELSE 0 
        END
    ), 0) AS total_units_allocated,
    ROUND(
        (COALESCE(SUM(
            CASE 
                WHEN r.fulfillment_status = 'Fulfilled' THEN r.units_requested
                ELSE 0 
            END
        ), 0) * 100.0) / NULLIF(SUM(r.units_requested), 0), 
        2
    ) AS fulfillment_rate_percentage,
    ROUND(AVG(
        TIMESTAMPDIFF(MINUTE, r.request_date, tr_first.first_reserved_at) / 60.0
    ), 2) AS avg_turnaround_hours
FROM hospitals h
LEFT JOIN blood_requests r 
  ON h.hospital_id = r.hospital_id
LEFT JOIN (
    SELECT request_id, MIN(reserved_at) AS first_reserved_at
    FROM transfusion_reservations
    GROUP BY request_id
) tr_first 
  ON r.request_id = tr_first.request_id
GROUP BY 
    h.hospital_id,
    h.hospital_name,
    h.city,
    h.tier;


-- ============================================================================
-- SECTION 2: FIVE COMPLEX VIVA-READY BENCHMARK QUERIES
-- ============================================================================

-- ----------------------------------------------------------------------------
-- Viva Query 1: INNER JOIN + LEFT JOIN with GROUP BY & HAVING
-- Business Intent: Detect critical blood group stock deficits where current
--                  available inventory falls below the hospital safety threshold
--                  of 5 units across all active components.
-- DBMS Concepts: Multi-table joins, outer joins preserving master catalog,
--                aggregation filtering via HAVING.
-- ----------------------------------------------------------------------------
SELECT 
    bg.group_name,
    bg.rh_factor,
    bc.component_type,
    COALESCE(COUNT(bu.unit_id), 0) AS available_stock_count,
    CASE 
        WHEN COALESCE(COUNT(bu.unit_id), 0) = 0 THEN 'CRITICAL DEPLETION'
        WHEN COALESCE(COUNT(bu.unit_id), 0) < 3 THEN 'HIGH DEFICIT'
        ELSE 'MODERATE DEFICIT'
    END AS stock_alert_level
FROM blood_groups bg
CROSS JOIN (
    SELECT DISTINCT component_type FROM blood_compatibility
) bc
LEFT JOIN blood_units bu 
  ON bg.group_id = bu.blood_group_id 
 AND bc.component_type = bu.component_type
 AND bu.status = 'Available'
 AND bu.expiry_date > CURDATE()
GROUP BY 
    bg.group_id,
    bg.group_name,
    bg.rh_factor,
    bc.component_type
HAVING available_stock_count < 5
ORDER BY available_stock_count ASC, bg.group_name ASC;

-- ----------------------------------------------------------------------------
-- Viva Query 2: Anti-Join using NOT EXISTS
-- Business Intent: Mobilize emergency voluntary donors by querying eligible
--                  Universal Red Cell Donors (O- negative) who have NOT donated
--                  or been scheduled in the last 180 days (or ever).
-- DBMS Concepts: Anti-join optimization, correlated subquery negation,
--                correlated index lookup vs LEFT JOIN / IS NULL.
-- ----------------------------------------------------------------------------
SELECT 
    d.donor_id,
    CONCAT(d.first_name, ' ', d.last_name) AS full_name,
    bg.group_name,
    d.phone,
    d.email,
    d.city,
    d.last_donation_date,
    COALESCE(DATEDIFF(CURDATE(), d.last_donation_date), 9999) AS days_since_last_donation
FROM donors d
JOIN blood_groups bg 
  ON d.blood_group_id = bg.group_id
WHERE bg.group_name = 'O-'
  AND d.eligibility_status = 'Eligible'
  AND NOT EXISTS (
      -- Exclude donors who donated in the last 180 days
      SELECT 1 
      FROM blood_donations bd 
      WHERE bd.donor_id = d.donor_id 
        AND bd.donation_date >= DATE_SUB(CURDATE(), INTERVAL 180 DAY)
  )
  AND NOT EXISTS (
      -- Exclude donors with pending upcoming appointments
      SELECT 1 
      FROM donation_appointments da 
      WHERE da.donor_id = d.donor_id 
        AND da.status = 'Scheduled' 
        AND da.scheduled_at >= NOW()
  )
ORDER BY days_since_last_donation DESC;

-- ----------------------------------------------------------------------------
-- Viva Query 3: Correlated Subquery with Mathematical Aggregation
-- Business Intent: Identify high-performing donation camps whose total blood volume
--                  collected strictly exceeded the regional city average for camps.
-- DBMS Concepts: Correlated subquery in WHERE clause, 2-tier aggregation,
--                cardinality estimation.
-- ----------------------------------------------------------------------------
SELECT 
    c.camp_id,
    c.camp_name,
    c.organizer,
    c.city,
    c.target_units,
    COUNT(bd.donation_id) AS total_donations_collected,
    COALESCE(SUM(bd.volume_ml), 0) AS total_volume_ml,
    ROUND(
        (SELECT AVG(city_camp_vol.camp_volume)
         FROM (
             SELECT c2.city, c2.camp_id, COALESCE(SUM(bd2.volume_ml), 0) AS camp_volume
             FROM donation_camps c2
             LEFT JOIN blood_donations bd2 ON c2.camp_id = bd2.camp_id
             GROUP BY c2.city, c2.camp_id
         ) city_camp_vol
         WHERE city_camp_vol.city = c.city), 
        2
    ) AS city_average_camp_volume_ml
FROM donation_camps c
LEFT JOIN blood_donations bd 
  ON c.camp_id = bd.camp_id
GROUP BY 
    c.camp_id, 
    c.camp_name, 
    c.organizer, 
    c.city, 
    c.target_units
HAVING total_volume_ml >= (
    SELECT AVG(city_camp_vol2.camp_volume)
    FROM (
        SELECT c3.city, c3.camp_id, COALESCE(SUM(bd3.volume_ml), 0) AS camp_volume
        FROM donation_camps c3
        LEFT JOIN blood_donations bd3 ON c3.camp_id = bd3.camp_id
        GROUP BY c3.city, c3.camp_id
    ) city_camp_vol2
    WHERE city_camp_vol2.city = c.city
)
ORDER BY total_volume_ml DESC;

-- ----------------------------------------------------------------------------
-- Viva Query 4: Analytical Window Function (DENSE_RANK() with PARTITION BY)
-- Business Intent: Rank available donor density per blood group within each
--                  metropolitan city to prioritize mobile recruitment drives.
-- DBMS Concepts: Modern SQL OLAP window functions, PARTITION BY vs GROUP BY,
--                handling ties with DENSE_RANK() vs RANK().
-- ----------------------------------------------------------------------------
SELECT 
    d.city,
    bg.group_name,
    COUNT(d.donor_id) AS registered_eligible_donors,
    DENSE_RANK() OVER (
        PARTITION BY d.city 
        ORDER BY COUNT(d.donor_id) DESC
    ) AS regional_scarcity_rank,
    ROUND(
        COUNT(d.donor_id) * 100.0 / SUM(COUNT(d.donor_id)) OVER (PARTITION BY d.city),
        2
    ) AS percentage_of_city_donor_pool
FROM donors d
JOIN blood_groups bg 
  ON d.blood_group_id = bg.group_id
WHERE d.eligibility_status = 'Eligible'
GROUP BY 
    d.city, 
    bg.group_id, 
    bg.group_name
ORDER BY 
    d.city ASC, 
    regional_scarcity_rank ASC;

-- ----------------------------------------------------------------------------
-- Viva Query 5: Execution Plan Analysis (EXPLAIN ANALYZE)
-- Business Intent: Evaluate query execution performance for emergency blood
--                  cross-matching compatibility lookups using composite indexes.
-- DBMS Concepts: B-Tree index scan vs Table scan, Hash Join execution,
--                actual time vs estimated cost, buffer pool hit ratio.
-- ----------------------------------------------------------------------------
EXPLAIN
SELECT 
    u.unit_id,
    u.component_type,
    bg_donor.group_name AS donor_blood_group,
    u.expiry_date,
    u.storage_location,
    u.status
FROM blood_units u
JOIN blood_groups bg_donor 
  ON u.blood_group_id = bg_donor.group_id
JOIN blood_compatibility bc 
  ON u.blood_group_id = bc.donor_group_id
JOIN blood_groups bg_recip 
  ON bc.recipient_group_id = bg_recip.group_id
WHERE bg_recip.group_name = 'A+'
  AND bc.component_type   = 'RBC'
  AND u.component_type    = 'RBC'
  AND u.status            = 'Available'
  AND u.expiry_date       > CURDATE()
ORDER BY u.expiry_date ASC;
