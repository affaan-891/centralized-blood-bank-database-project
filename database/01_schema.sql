-- ============================================================================
-- Project: Centralized Blood Bank & Emergency Donor Match Registry
-- Target RDBMS: MySQL 8.0+ / MariaDB 10.4+ (InnoDB Engine)
-- File: 01_schema.sql (Data Definition Language - DDL)
-- Specification: 3NF Relational Schema with Integrity Constraints & Indexes
-- Author: Principal Database Architect
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. Database Initialization
-- ----------------------------------------------------------------------------
CREATE DATABASE IF NOT EXISTS blood_bank_db
  CHARACTER SET utf8mb4
  COLLATE utf8mb4_unicode_ci;

USE blood_bank_db;

-- ----------------------------------------------------------------------------
-- 2. Drop Existing Tables in Reverse Dependency Order
-- ----------------------------------------------------------------------------
SET FOREIGN_KEY_CHECKS = 0;
DROP TABLE IF EXISTS blood_audit_logs;
DROP TABLE IF EXISTS transfusion_reservations;
DROP TABLE IF EXISTS blood_requests;
DROP TABLE IF EXISTS hospitals;
DROP TABLE IF EXISTS blood_units;
DROP TABLE IF EXISTS blood_donations;
DROP TABLE IF EXISTS donation_appointments;
DROP TABLE IF EXISTS donation_camps;
DROP TABLE IF EXISTS donors;
DROP TABLE IF EXISTS blood_compatibility;
DROP TABLE IF EXISTS blood_groups;
SET FOREIGN_KEY_CHECKS = 1;

-- ----------------------------------------------------------------------------
-- 3. Table Definitions (11 Relational Entities in 3NF)
-- ----------------------------------------------------------------------------

-- Table 1: blood_groups (Lookup table for ABO/Rh blood groups)
CREATE TABLE blood_groups (
    group_id INT AUTO_INCREMENT PRIMARY KEY,
    group_name ENUM('A+','A-','B+','B-','AB+','AB-','O+','O-') NOT NULL,
    rh_factor ENUM('+','-') NOT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT uq_blood_group_name UNIQUE (group_name)
) ENGINE=InnoDB;

-- Table 2: blood_compatibility (M:N self-relationship mapping ABO/Rh compatibility by component)
CREATE TABLE blood_compatibility (
    donor_group_id INT NOT NULL,
    recipient_group_id INT NOT NULL,
    component_type ENUM('Whole_Blood','RBC','Platelets','Plasma') NOT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (donor_group_id, recipient_group_id, component_type),
    CONSTRAINT fk_compat_donor
        FOREIGN KEY (donor_group_id) REFERENCES blood_groups(group_id)
        ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT fk_compat_recipient
        FOREIGN KEY (recipient_group_id) REFERENCES blood_groups(group_id)
        ON DELETE RESTRICT ON UPDATE CASCADE
) ENGINE=InnoDB;

-- Table 3: donors (Registered voluntary blood donors)
CREATE TABLE donors (
    donor_id INT AUTO_INCREMENT PRIMARY KEY,
    first_name VARCHAR(50) NOT NULL,
    last_name VARCHAR(50) NOT NULL,
    blood_group_id INT NOT NULL,
    gender ENUM('M','F','Other') NOT NULL,
    dob DATE NOT NULL,
    phone VARCHAR(20) NOT NULL,
    email VARCHAR(100) NOT NULL,
    city VARCHAR(50) NOT NULL,
    last_donation_date DATE NULL,
    eligibility_status ENUM('Eligible','Deferred_Temporary','Deferred_Permanent') NOT NULL DEFAULT 'Eligible',
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    CONSTRAINT uq_donor_phone UNIQUE (phone),
    CONSTRAINT uq_donor_email UNIQUE (email),
    CONSTRAINT fk_donor_blood_group
        FOREIGN KEY (blood_group_id) REFERENCES blood_groups(group_id)
        ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT chk_donor_dob CHECK (dob >= '1900-01-01')
) ENGINE=InnoDB;

-- Table 4: donation_camps (Mobile/stationary blood collection drives)
CREATE TABLE donation_camps (
    camp_id INT AUTO_INCREMENT PRIMARY KEY,
    camp_name VARCHAR(100) NOT NULL,
    organizer VARCHAR(100) NOT NULL,
    location_address VARCHAR(255) NOT NULL,
    city VARCHAR(50) NOT NULL,
    start_date DATE NOT NULL,
    end_date DATE NOT NULL,
    target_units INT NOT NULL DEFAULT 50,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT chk_camp_target CHECK (target_units > 0),
    CONSTRAINT chk_camp_dates CHECK (end_date >= start_date)
) ENGINE=InnoDB;

-- Table 5: donation_appointments (Scheduled donor visits)
CREATE TABLE donation_appointments (
    appointment_id INT AUTO_INCREMENT PRIMARY KEY,
    donor_id INT NOT NULL,
    camp_id INT NULL,
    scheduled_at DATETIME NOT NULL,
    status ENUM('Scheduled','Completed','Cancelled','NoShow') NOT NULL DEFAULT 'Scheduled',
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_appt_donor
        FOREIGN KEY (donor_id) REFERENCES donors(donor_id)
        ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT fk_appt_camp
        FOREIGN KEY (camp_id) REFERENCES donation_camps(camp_id)
        ON DELETE SET NULL ON UPDATE CASCADE
) ENGINE=InnoDB;

-- Table 6: blood_donations (Clinical phlebotomy collection events)
CREATE TABLE blood_donations (
    donation_id INT AUTO_INCREMENT PRIMARY KEY,
    donor_id INT NOT NULL,
    camp_id INT NULL,
    donation_date DATE NOT NULL,
    hemoglobin_level DECIMAL(3,1) NOT NULL,
    volume_ml INT NOT NULL,
    screening_status ENUM('Passed','Failed','Pending') NOT NULL DEFAULT 'Pending',
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT chk_donation_hemoglobin CHECK (hemoglobin_level >= 12.0),
    CONSTRAINT chk_donation_volume CHECK (volume_ml >= 350),
    CONSTRAINT fk_donation_donor
        FOREIGN KEY (donor_id) REFERENCES donors(donor_id)
        ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT fk_donation_camp
        FOREIGN KEY (camp_id) REFERENCES donation_camps(camp_id)
        ON DELETE SET NULL ON UPDATE CASCADE
) ENGINE=InnoDB;

-- Table 7: blood_units (Fractionated blood inventory items with shelf-life tracking)
CREATE TABLE blood_units (
    unit_id INT AUTO_INCREMENT PRIMARY KEY,
    donation_id INT NOT NULL,
    blood_group_id INT NOT NULL,
    component_type ENUM('Whole_Blood','RBC','Platelets','Plasma') NOT NULL,
    collection_date DATE NOT NULL,
    expiry_date DATE NOT NULL,
    storage_location VARCHAR(50) NOT NULL,
    status ENUM('Available','Reserved','Transfused','Expired','Quarantine') NOT NULL DEFAULT 'Quarantine',
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    CONSTRAINT fk_unit_donation
        FOREIGN KEY (donation_id) REFERENCES blood_donations(donation_id)
        ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT fk_unit_blood_group
        FOREIGN KEY (blood_group_id) REFERENCES blood_groups(group_id)
        ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT chk_unit_expiry CHECK (expiry_date >= collection_date)
) ENGINE=InnoDB;

-- Table 8: hospitals (Healthcare provider entities requesting blood supplies)
CREATE TABLE hospitals (
    hospital_id INT AUTO_INCREMENT PRIMARY KEY,
    hospital_name VARCHAR(100) NOT NULL,
    license_number VARCHAR(50) NOT NULL,
    emergency_contact VARCHAR(20) NOT NULL,
    address VARCHAR(255) NOT NULL,
    city VARCHAR(50) NOT NULL,
    tier ENUM('Government','Private_Tier1','Private_Tier2') NOT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT uq_hospital_license UNIQUE (license_number)
) ENGINE=InnoDB;

-- Table 9: blood_requests (Clinical requests for patient transfusions)
CREATE TABLE blood_requests (
    request_id INT AUTO_INCREMENT PRIMARY KEY,
    hospital_id INT NOT NULL,
    patient_name VARCHAR(100) NOT NULL,
    blood_group_id INT NOT NULL,
    component_type ENUM('Whole_Blood','RBC','Platelets','Plasma') NOT NULL,
    units_requested INT NOT NULL,
    urgency_level ENUM('Normal','Urgent','Critical') NOT NULL DEFAULT 'Normal',
    request_date DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    fulfillment_status ENUM('Pending','Partially_Fulfilled','Fulfilled','Cancelled') NOT NULL DEFAULT 'Pending',
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    CONSTRAINT chk_request_units CHECK (units_requested > 0),
    CONSTRAINT fk_req_hospital
        FOREIGN KEY (hospital_id) REFERENCES hospitals(hospital_id)
        ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT fk_req_blood_group
        FOREIGN KEY (blood_group_id) REFERENCES blood_groups(group_id)
        ON DELETE RESTRICT ON UPDATE CASCADE
) ENGINE=InnoDB;

-- Table 10: transfusion_reservations (Pessimistic allocation linking requests to units)
CREATE TABLE transfusion_reservations (
    reservation_id INT AUTO_INCREMENT PRIMARY KEY,
    request_id INT NOT NULL,
    unit_id INT NOT NULL,
    reserved_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    reservation_expiry DATETIME NOT NULL,
    status ENUM('Reserved','Transfused','Released') NOT NULL DEFAULT 'Reserved',
    CONSTRAINT uq_reservation_unit UNIQUE (unit_id),
    CONSTRAINT fk_res_request
        FOREIGN KEY (request_id) REFERENCES blood_requests(request_id)
        ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT fk_res_unit
        FOREIGN KEY (unit_id) REFERENCES blood_units(unit_id)
        ON DELETE RESTRICT ON UPDATE CASCADE
) ENGINE=InnoDB;

-- Table 11: blood_audit_logs (Immutable regulatory compliance audit trail)
CREATE TABLE blood_audit_logs (
    log_id INT AUTO_INCREMENT PRIMARY KEY,
    unit_id INT NOT NULL,
    action_type ENUM('COLLECTION','TESTING_PASSED','RESERVED','RELEASED','TRANSFUSED','DISCARDED_EXPIRED') NOT NULL,
    changed_by VARCHAR(100) NOT NULL,
    comments TEXT NULL,
    logged_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB;

-- ----------------------------------------------------------------------------
-- 4. Strategic Secondary Indexes for Query Optimization
-- ----------------------------------------------------------------------------
CREATE INDEX idx_donors_blood_group ON donors(blood_group_id);
CREATE INDEX idx_donors_city_status ON donors(city, eligibility_status);
CREATE INDEX idx_blood_units_status_expiry ON blood_units(status, component_type, expiry_date);
CREATE INDEX idx_blood_requests_status_urgency ON blood_requests(fulfillment_status, urgency_level);
CREATE INDEX idx_reservations_status_expiry ON transfusion_reservations(status, reservation_expiry);
CREATE INDEX idx_donations_donor_date ON blood_donations(donor_id, donation_date);
CREATE INDEX idx_audit_unit_action ON blood_audit_logs(unit_id, action_type);
