-- ============================================================================
-- Project: Centralized Blood Bank & Emergency Donor Match Registry
-- Target RDBMS: MySQL 8.0+ / MariaDB 10.4+ (InnoDB Engine)
-- File: 05_seed_data.sql (Realistic Clinical Dataset - DML)
-- Specification: Complete ABO/Rh compatibility, donors, camps, units, hospitals & requests
-- Author: Principal Database Architect
-- ============================================================================

USE blood_bank_db;

-- Disable foreign key checks for clean sequential truncation
SET FOREIGN_KEY_CHECKS = 0;
TRUNCATE TABLE blood_audit_logs;
TRUNCATE TABLE transfusion_reservations;
TRUNCATE TABLE blood_requests;
TRUNCATE TABLE hospitals;
TRUNCATE TABLE blood_units;
TRUNCATE TABLE blood_donations;
TRUNCATE TABLE donation_appointments;
TRUNCATE TABLE donation_camps;
TRUNCATE TABLE donors;
TRUNCATE TABLE blood_compatibility;
TRUNCATE TABLE blood_groups;
SET FOREIGN_KEY_CHECKS = 1;

-- ----------------------------------------------------------------------------
-- 1. Seed blood_groups (8 Standard ABO/Rh Antigens)
-- ----------------------------------------------------------------------------
INSERT INTO blood_groups (group_id, group_name, rh_factor) VALUES
(1, 'O-',  '-'),
(2, 'O+',  '+'),
(3, 'A-',  '-'),
(4, 'A+',  '+'),
(5, 'B-',  '-'),
(6, 'B+',  '+'),
(7, 'AB-', '-'),
(8, 'AB+', '+');

-- ----------------------------------------------------------------------------
-- 2. Seed blood_compatibility (Full Clinical Cross-Matching Matrix)
-- ----------------------------------------------------------------------------

-- Red Blood Cells (RBC) & Whole Blood Compatibility Matrix
-- O- is universal cellular donor; AB+ is universal cellular recipient
INSERT INTO blood_compatibility (donor_group_id, recipient_group_id, component_type) VALUES
-- Donor O- (1) can donate RBC/Whole_Blood to all recipients (1 to 8)
(1, 1, 'RBC'), (1, 2, 'RBC'), (1, 3, 'RBC'), (1, 4, 'RBC'), (1, 5, 'RBC'), (1, 6, 'RBC'), (1, 7, 'RBC'), (1, 8, 'RBC'),
(1, 1, 'Whole_Blood'), (1, 2, 'Whole_Blood'), (1, 3, 'Whole_Blood'), (1, 4, 'Whole_Blood'), (1, 5, 'Whole_Blood'), (1, 6, 'Whole_Blood'), (1, 7, 'Whole_Blood'), (1, 8, 'Whole_Blood'),

-- Donor O+ (2) can donate RBC/Whole_Blood to Rh+ recipients (2, 4, 6, 8)
(2, 2, 'RBC'), (2, 4, 'RBC'), (2, 6, 'RBC'), (2, 8, 'RBC'),
(2, 2, 'Whole_Blood'), (2, 4, 'Whole_Blood'), (2, 6, 'Whole_Blood'), (2, 8, 'Whole_Blood'),

-- Donor A- (3) can donate RBC/Whole_Blood to A and AB recipients (3, 4, 7, 8)
(3, 3, 'RBC'), (3, 4, 'RBC'), (3, 7, 'RBC'), (3, 8, 'RBC'),
(3, 3, 'Whole_Blood'), (3, 4, 'Whole_Blood'), (3, 7, 'Whole_Blood'), (3, 8, 'Whole_Blood'),

-- Donor A+ (4) can donate RBC/Whole_Blood to A+ and AB+ recipients (4, 8)
(4, 4, 'RBC'), (4, 8, 'RBC'),
(4, 4, 'Whole_Blood'), (4, 8, 'Whole_Blood'),

-- Donor B- (5) can donate RBC/Whole_Blood to B and AB recipients (5, 6, 7, 8)
(5, 5, 'RBC'), (5, 6, 'RBC'), (5, 7, 'RBC'), (5, 8, 'RBC'),
(5, 5, 'Whole_Blood'), (5, 6, 'Whole_Blood'), (5, 7, 'Whole_Blood'), (5, 8, 'Whole_Blood'),

-- Donor B+ (6) can donate RBC/Whole_Blood to B+ and AB+ recipients (6, 8)
(6, 6, 'RBC'), (6, 8, 'RBC'),
(6, 6, 'Whole_Blood'), (6, 8, 'Whole_Blood'),

-- Donor AB- (7) can donate RBC/Whole_Blood to AB recipients (7, 8)
(7, 7, 'RBC'), (7, 8, 'RBC'),
(7, 7, 'Whole_Blood'), (7, 8, 'Whole_Blood'),

-- Donor AB+ (8) can donate RBC/Whole_Blood only to AB+ recipients (8)
(8, 8, 'RBC'),
(8, 8, 'Whole_Blood');

-- Fresh Frozen Plasma (FFP) Compatibility Matrix
-- AB is universal plasma donor (no anti-A/anti-B antibodies); O is universal plasma recipient
INSERT INTO blood_compatibility (donor_group_id, recipient_group_id, component_type) VALUES
-- Donor AB- (7) and AB+ (8) can donate Plasma to all recipients (1 to 8)
(7, 1, 'Plasma'), (7, 2, 'Plasma'), (7, 3, 'Plasma'), (7, 4, 'Plasma'), (7, 5, 'Plasma'), (7, 6, 'Plasma'), (7, 7, 'Plasma'), (7, 8, 'Plasma'),
(8, 1, 'Plasma'), (8, 2, 'Plasma'), (8, 3, 'Plasma'), (8, 4, 'Plasma'), (8, 5, 'Plasma'), (8, 6, 'Plasma'), (8, 7, 'Plasma'), (8, 8, 'Plasma'),

-- Donor A- (3) and A+ (4) can donate Plasma to A and O recipients (1, 2, 3, 4)
(3, 1, 'Plasma'), (3, 2, 'Plasma'), (3, 3, 'Plasma'), (3, 4, 'Plasma'),
(4, 1, 'Plasma'), (4, 2, 'Plasma'), (4, 3, 'Plasma'), (4, 4, 'Plasma'),

-- Donor B- (5) and B+ (6) can donate Plasma to B and O recipients (1, 2, 5, 6)
(5, 1, 'Plasma'), (5, 2, 'Plasma'), (5, 5, 'Plasma'), (5, 6, 'Plasma'),
(6, 1, 'Plasma'), (6, 2, 'Plasma'), (6, 5, 'Plasma'), (6, 6, 'Plasma'),

-- Donor O- (1) and O+ (2) can donate Plasma only to O recipients (1, 2)
(1, 1, 'Plasma'), (1, 2, 'Plasma'),
(2, 1, 'Plasma'), (2, 2, 'Plasma');

-- Platelets Compatibility Matrix
-- AB is universal platelet donor; compatible or identical ABO preferred
INSERT INTO blood_compatibility (donor_group_id, recipient_group_id, component_type) VALUES
(1, 1, 'Platelets'), (1, 2, 'Platelets'),
(2, 2, 'Platelets'),
(3, 1, 'Platelets'), (3, 3, 'Platelets'), (3, 4, 'Platelets'),
(4, 4, 'Platelets'),
(5, 1, 'Platelets'), (5, 5, 'Platelets'), (5, 6, 'Platelets'),
(6, 6, 'Platelets'),
(7, 1, 'Platelets'), (7, 2, 'Platelets'), (7, 3, 'Platelets'), (7, 4, 'Platelets'), (7, 5, 'Platelets'), (7, 6, 'Platelets'), (7, 7, 'Platelets'), (7, 8, 'Platelets'),
(8, 1, 'Platelets'), (8, 2, 'Platelets'), (8, 3, 'Platelets'), (8, 4, 'Platelets'), (8, 5, 'Platelets'), (8, 6, 'Platelets'), (8, 7, 'Platelets'), (8, 8, 'Platelets');

-- ----------------------------------------------------------------------------
-- 3. Seed donors (15 Registered Donors with Diversity in Groups & Eligibility)
-- ----------------------------------------------------------------------------
INSERT INTO donors (donor_id, first_name, last_name, blood_group_id, gender, dob, phone, email, city, last_donation_date, eligibility_status) VALUES
(1,  'Zain',    'Ahmed',    1, 'M', '1995-04-12', '+92-300-1112233', 'zain.ahmed@example.com',    'Lahore',     NULL,         'Eligible'),           -- Universal O-
(2,  'Ayesha',  'Malik',    2, 'F', '1998-08-23', '+92-301-2223344', 'ayesha.malik@example.com',  'Lahore',     '2026-04-10', 'Eligible'),           -- O+ (113 days before Aug 01)
(3,  'Bilal',   'Khan',     4, 'M', '1992-11-05', '+92-302-3334455', 'bilal.khan@example.com',    'Karachi',    '2026-04-15', 'Eligible'),           -- A+ (117 days before Aug 10)
(4,  'Fatima',  'Noor',     6, 'F', '2000-01-30', '+92-303-4445566', 'fatima.noor@example.com',   'Islamabad',  '2026-04-01', 'Eligible'),           -- B+ (136 days before Aug 15)
(5,  'Hamza',   'Tariq',    8, 'M', '1994-07-19', '+92-304-5556677', 'hamza.tariq@example.com',   'Rawalpindi', '2026-03-20', 'Eligible'),           -- AB+ (153 days before Aug 20)
(6,  'Mariam',  'Siddiqui', 3, 'F', '1996-09-14', '+92-305-6667788', 'mariam.s@example.com',      'Lahore',     '2026-04-18', 'Eligible'),           -- A- (106 days before Aug 02)
(7,  'Usman',   'Raza',     5, 'M', '1991-03-08', '+92-306-7778899', 'usman.raza@example.com',    'Karachi',    '2026-04-25', 'Eligible'),           -- B- (108 days before Aug 11)
(8,  'Hina',    'Altaf',    7, 'F', '1999-12-11', '+92-307-8889900', 'hina.altaf@example.com',    'Islamabad',  '2026-02-14', 'Eligible'),           -- AB- (182 days before Aug 15)
(9,  'Omer',    'Farooq',   1, 'M', '1988-06-25', '+92-308-9990011', 'omer.f@example.com',        'Lahore',     '2025-10-10', 'Eligible'),           -- Universal O- (Long lapsed)
(10, 'Sana',    'Mir',      2, 'F', '1997-02-17', '+92-309-1122334', 'sana.mir@example.com',      'Rawalpindi', '2026-04-02', 'Eligible'),           -- O+ (140 days before Aug 20)
(11, 'Asad',    'Rehman',   4, 'M', '1993-10-09', '+92-310-2233445', 'asad.rehman@example.com',  'Karachi',    '2026-09-10', 'Deferred_Temporary'), -- Recent donation / Low Hb
(12, 'Zara',    'Sheikh',   6, 'F', '2001-05-22', '+92-311-3344556', 'zara.sheikh@example.com',  'Lahore',     '2025-12-01', 'Deferred_Permanent'), -- Medical condition
(13, 'Tariq',   'Jamil',    1, 'M', '1985-09-15', '+92-312-4455667', 'tariq.j@example.com',       'Peshawar',   NULL,         'Eligible'),           -- Universal O- (Never donated)
(14, 'Nida',    'Yasir',    4, 'F', '1994-04-03', '+92-313-5566778', 'nida.yasir@example.com',    'Karachi',    '2026-04-01', 'Eligible'),           -- A+ (133 days before Aug 12)
(15, 'Daniyal', 'Mustafa',  2, 'M', '1996-08-14', '+92-314-6677889', 'daniyal.m@example.com',    'Islamabad',  '2026-04-30', 'Eligible');           -- O+ (108 days before Aug 16)

-- ----------------------------------------------------------------------------
-- 4. Seed donation_camps (4 Regional Blood Drives)
-- ----------------------------------------------------------------------------
INSERT INTO donation_camps (camp_id, camp_name, organizer, location_address, city, start_date, end_date, target_units) VALUES
(1, 'LUMS Red Crescent Blood Drive',      'Pakistan Red Crescent Society', 'Sector U, DHA Phase 5',        'Lahore',     '2026-08-01', '2026-08-03', 150),
(2, 'Indus Hospital Community Mega Drive', 'Indus Hospital & Health Network', 'Korangi Crossing',          'Karachi',    '2026-08-10', '2026-08-12', 200),
(3, 'NUST Lifeline Donor Camp',           'Shaukat Khanum Memorial Trust',  'H-12 Main Campus',            'Islamabad',  '2026-08-15', '2026-08-16', 120),
(4, 'Rawalpindi Medical College Drive',   'Armed Forces Institute of Path', 'Tipu Road',                  'Rawalpindi', '2026-08-20', '2026-08-21', 100);

-- ----------------------------------------------------------------------------
-- 5. Seed donation_appointments (8 Scheduled Appointments)
-- ----------------------------------------------------------------------------
INSERT INTO donation_appointments (appointment_id, donor_id, camp_id, scheduled_at, status) VALUES
(1, 1,  1,    '2026-08-01 10:00:00', 'Completed'),
(2, 2,  1,    '2026-08-01 11:30:00', 'Completed'),
(3, 3,  2,    '2026-08-10 09:30:00', 'Completed'),
(4, 4,  3,    '2026-08-15 14:00:00', 'Completed'),
(5, 5,  4,    '2026-08-20 10:15:00', 'Completed'),
(6, 6,  1,    '2026-08-02 15:00:00', 'Completed'),
(7, 7,  2,    '2026-08-11 11:00:00', 'Completed'),
(8, 9,  NULL, '2026-09-25 10:00:00', 'Scheduled');

-- ----------------------------------------------------------------------------
-- 6. Seed blood_donations (12 Phlebotomy Collections)
-- Note: Trigger trg_validate_donor_interval_before_donation verifies 90 days interval
-- ----------------------------------------------------------------------------
INSERT INTO blood_donations (donation_id, donor_id, camp_id, donation_date, hemoglobin_level, volume_ml, screening_status) VALUES
(1,  1,  1,    '2026-08-01', 14.5, 450, 'Passed'),
(2,  2,  1,    '2026-08-01', 13.2, 450, 'Passed'),
(3,  3,  2,    '2026-08-10', 15.0, 500, 'Passed'),
(4,  4,  3,    '2026-08-15', 12.8, 450, 'Passed'),
(5,  5,  4,    '2026-08-20', 14.8, 500, 'Passed'),
(6,  6,  1,    '2026-08-02', 13.5, 450, 'Passed'),
(7,  7,  2,    '2026-08-11', 14.2, 450, 'Passed'),
(8,  8,  3,    '2026-08-15', 12.9, 450, 'Passed'),
(9,  9,  NULL, '2026-08-05', 15.5, 500, 'Passed'),
(10, 10, 4,    '2026-08-20', 13.0, 450, 'Passed'),
(11, 14, 2,    '2026-08-12', 12.2, 450, 'Failed'),  -- Viral reactive during serology
(12, 15, 3,    '2026-08-16', 14.1, 450, 'Pending'); -- Under serological screening

-- ----------------------------------------------------------------------------
-- 7. Seed blood_units (Fractionated Inventory with Automated Shelf-Life)
-- Note: Trigger trg_set_component_shelf_life_on_unit_creation calculates expiry_date.
-- We specify collection_date, component_type, storage_location, and status.
-- ----------------------------------------------------------------------------
INSERT INTO blood_units (unit_id, donation_id, blood_group_id, component_type, collection_date, expiry_date, storage_location, status) VALUES
-- Donation 1 (Donor 1: O-) -> Split into RBC, Platelets, Plasma
(1,  1, 1, 'RBC',         '2026-08-01', '2026-09-12', 'Cold Room A1 - Shelf 1', 'Available'),
(2,  1, 1, 'Platelets',   '2026-08-01', '2026-08-06', 'Agitator 1 - Bay A',    'Expired'),
(3,  1, 1, 'Plasma',      '2026-08-01', '2027-08-01', 'Deep Freezer F1',        'Available'),

-- Donation 2 (Donor 2: O+) -> Split into Whole_Blood
(4,  2, 2, 'Whole_Blood', '2026-08-01', '2026-09-05', 'Cold Room A1 - Shelf 2', 'Available'),

-- Donation 3 (Donor 3: A+) -> Split into RBC, Platelets, Plasma
(5,  3, 4, 'RBC',         '2026-08-10', '2026-09-21', 'Cold Room B2 - Shelf 1', 'Available'),
(6,  3, 4, 'Platelets',   '2026-08-10', '2026-08-15', 'Agitator 2 - Bay B',    'Expired'),
(7,  3, 4, 'Plasma',      '2026-08-10', '2027-08-10', 'Deep Freezer F2',        'Available'),

-- Donation 4 (Donor 4: B+) -> Split into RBC & Plasma
(8,  4, 6, 'RBC',         '2026-08-15', '2026-09-26', 'Cold Room B1 - Shelf 3', 'Available'),
(9,  4, 6, 'Plasma',      '2026-08-15', '2027-08-15', 'Deep Freezer F1',        'Available'),

-- Donation 5 (Donor 5: AB+) -> Split into RBC & Plasma (Universal Plasma)
(10, 5, 8, 'RBC',         '2026-08-20', '2026-10-01', 'Cold Room C1 - Shelf 1', 'Available'),
(11, 5, 8, 'Plasma',      '2026-08-20', '2027-08-20', 'Deep Freezer F3',        'Available'),

-- Donation 6 (Donor 6: A-) -> Split into RBC, Platelets, Plasma
(12, 6, 3, 'RBC',         '2026-08-02', '2026-09-13', 'Cold Room A2 - Shelf 4', 'Available'),
(13, 6, 3, 'Platelets',   '2026-08-02', '2026-08-07', 'Agitator 1 - Bay C',    'Expired'),
(14, 6, 3, 'Plasma',      '2026-08-02', '2027-08-02', 'Deep Freezer F2',        'Available'),

-- Donation 7 (Donor 7: B-) -> Split into RBC & Plasma
(15, 7, 5, 'RBC',         '2026-08-11', '2026-09-22', 'Cold Room B2 - Shelf 2', 'Available'),
(16, 7, 5, 'Plasma',      '2026-08-11', '2027-08-11', 'Deep Freezer F3',        'Available'),

-- Donation 8 (Donor 8: AB-) -> Split into RBC, Platelets, Plasma
(17, 8, 7, 'RBC',         '2026-08-15', '2026-09-26', 'Cold Room C2 - Shelf 1', 'Available'),
(18, 8, 7, 'Platelets',   '2026-08-15', '2026-08-20', 'Agitator 2 - Bay A',    'Expired'),
(19, 8, 7, 'Plasma',      '2026-08-15', '2027-08-15', 'Deep Freezer F1',        'Available'),

-- Donation 9 (Donor 9: O-) -> Recent donation (Sept) split into RBC & Platelets
(20, 9, 1, 'RBC',         '2026-09-18', '2026-10-30', 'Cold Room A1 - Shelf 5', 'Available'),
(21, 9, 1, 'Platelets',   '2026-09-18', '2026-09-23', 'Agitator 1 - Bay D',    'Available'), -- Fresh platelets
(22, 9, 1, 'Plasma',      '2026-09-18', '2027-09-18', 'Deep Freezer F2',        'Available'),

-- Donation 10 (Donor 10: O+) -> Recent donation (Sept) split into RBC & Platelets
(23, 10, 2, 'RBC',        '2026-09-19', '2026-10-31', 'Cold Room A2 - Shelf 1', 'Available'),
(24, 10, 2, 'Platelets',  '2026-09-19', '2026-09-24', 'Agitator 2 - Bay C',    'Available'), -- Fresh platelets

-- Donation 12 (Donor 15: O+) -> Quarantine units under testing
(25, 12, 2, 'RBC',        '2026-09-20', '2026-11-01', 'Quarantine Vault Q1',   'Quarantine');

-- ----------------------------------------------------------------------------
-- 8. Seed hospitals (5 Regional Hospitals Across Government and Private Tiers)
-- ----------------------------------------------------------------------------
INSERT INTO hospitals (hospital_id, hospital_name, license_number, emergency_contact, address, city, tier) VALUES
(1, 'Mayo Hospital Lahore',                'PB-LHR-GOV-0012', '+92-42-99211100', 'Hospital Road, Anarkali',          'Lahore',     'Government'),
(2, 'Shaukat Khanum Memorial Cancer Hosp', 'PB-LHR-PVT-0045', '+92-42-35905000', '7A Block R-3, Johar Town',         'Lahore',     'Private_Tier1'),
(3, 'Aga Khan University Hospital',        'SN-KHI-PVT-0089', '+92-21-34930051', 'Stadium Road, Bahadurabad',        'Karachi',    'Private_Tier1'),
(4, 'Pakistan Institute of Medical Sci',   'ICT-ISB-GOV-003', '+92-51-9261170',  'Sector G-8/3',                     'Islamabad',  'Government'),
(5, 'Holy Family Hospital Rawalpindi',     'PB-RWP-GOV-0071', '+92-51-9290321',  'Murree Road, Satellite Town',      'Rawalpindi', 'Government');

-- ----------------------------------------------------------------------------
-- 9. Seed blood_requests (8 Clinical Transfusion Requests)
-- ----------------------------------------------------------------------------
INSERT INTO blood_requests (request_id, hospital_id, patient_name, blood_group_id, component_type, units_requested, urgency_level, request_date, fulfillment_status) VALUES
(1, 1, 'Ahmed Bilal (Trauma ICU)',         1, 'RBC',         2, 'Critical', '2026-09-21 08:30:00', 'Pending'),
(2, 2, 'Saeeda Begum (Leukemia Onco)',      4, 'Platelets',   1, 'Urgent',   '2026-09-21 09:15:00', 'Pending'),
(3, 3, 'Farhan Qureshi (Cardiovascular)',  6, 'RBC',         2, 'Critical', '2026-09-21 10:00:00', 'Pending'),
(4, 4, 'Rubina Kausar (Gynecology ER)',    2, 'Whole_Blood', 1, 'Urgent',   '2026-09-21 10:45:00', 'Pending'),
(5, 5, 'Kamran Asif (Neurosurgery)',       8, 'Plasma',      2, 'Normal',   '2026-09-21 11:30:00', 'Pending'),
(6, 1, 'Zubair Shah (Orthopedic Surgery)', 3, 'RBC',         1, 'Normal',   '2026-09-20 14:00:00', 'Fulfilled'),
(7, 3, 'Mehak Naveed (Emergency Burn)',    7, 'Plasma',      1, 'Critical', '2026-09-20 16:30:00', 'Fulfilled'),
(8, 2, 'Noman Khalid (Pediatric Thalam)',  4, 'RBC',         2, 'Urgent',   '2026-09-21 12:00:00', 'Pending');

-- ----------------------------------------------------------------------------
-- 10. Seed transfusion_reservations & historical statuses
-- Fulfilling historical requests 6 and 7
-- ----------------------------------------------------------------------------
-- Request 6 reserved and transfused unit 12 (A- RBC)
INSERT INTO transfusion_reservations (reservation_id, request_id, unit_id, reserved_at, reservation_expiry, status) VALUES
(1, 6, 12, '2026-09-20 14:15:00', '2026-09-20 16:15:00', 'Transfused'),
(2, 7, 19, '2026-09-20 16:45:00', '2026-09-20 18:45:00', 'Transfused');

-- Update the corresponding units to 'Transfused'
UPDATE blood_units SET status = 'Transfused' WHERE unit_id IN (12, 19);

-- ----------------------------------------------------------------------------
-- 11. Additional Historical Regulatory Audit Logs
-- (Note: Initial COLLECTION was generated by trigger trg_log_unit_creation;
-- status updates generated TRANSFUSED logs via trg_log_unit_status_transitions)
-- ----------------------------------------------------------------------------
INSERT INTO blood_audit_logs (unit_id, action_type, changed_by, comments, logged_at) VALUES
(1,  'TESTING_PASSED',    'lab_technician_01', 'Completed HBsAg, HCV, HIV, Syphilis, and Malaria serology. All clear.', '2026-08-02 11:00:00'),
(2,  'DISCARDED_EXPIRED', 'inventory_clerk_02', 'Platelet 5-day shelf life exceeded. Safe bio-disposal logged.',        '2026-08-06 09:00:00'),
(12, 'RESERVED',          'sp_emergency_match', 'Emergency cross-match allocation for Request #6.',                       '2026-09-20 14:15:00'),
(19, 'RESERVED',          'sp_emergency_match', 'Emergency cross-match allocation for Request #7.',                       '2026-09-20 16:45:00');
