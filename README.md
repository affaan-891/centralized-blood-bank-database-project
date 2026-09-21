# Centralized Blood Bank & Emergency Donor Match Registry

[![Database: MySQL 8.0+](https://img.shields.io/badge/MySQL-8.0%2B-blue.svg?logo=mysql&logoColor=white)](https://www.mysql.com/)
[![Engine: InnoDB](https://img.shields.io/badge/Engine-InnoDB-orange.svg)](https://dev.mysql.com/doc/refman/8.0/en/innodb-storage-engine.html)
[![Standard: 3NF Compliant](https://img.shields.io/badge/Normalization-3NF%20Compliant-brightgreen.svg)](#third-normal-form-3nf-guarantee)
[![ACID: Transactions](https://img.shields.io/badge/ACID-Guaranteed-purple.svg)](#stored-procedures--acid-transactions)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Domain: Healthcare DBMS](https://img.shields.io/badge/Domain-Healthcare%20DBMS-red.svg)](#overview)

> A production-grade, 3NF-normalized relational database management system designed for university computer science and software engineering students, DBMS lab submissions, and technical viva defense.

---

## Repository Structure

```
centralized-blood-bank-database-project/
├── database/
│   ├── 01_schema.sql               # DDL: 11 normalized tables, constraints, indexes
│   ├── 02_triggers.sql             # Triggers: 90-day deferral, shelf-life calculation, audit trail
│   ├── 03_procedures.sql           # ACID procedures (pessimistic matching, reclamation, shortage index)
│   ├── 04_views_and_queries.sql    # Analytical views & 5 complex viva exam queries
│   └── 05_seed_data.sql            # Realistic healthcare dataset (compatibility, donors, units, requests)
├── docs/
│   ├── ERD.md                     # Visual Mermaid ERD, Crow's foot cardinality, data dictionary
│   └── VIVA_QUESTIONS.md          # 10 in-depth viva examination questions with model answers
├── LICENSE                         # MIT Open Source License
└── README.md                       # Comprehensive project documentation
```

---

## Overview

In critical healthcare infrastructure, blood banks operate under strict physiological and regulatory constraints:
1. **Antigen Compatibility:** Transfusions must adhere to strict ABO/Rh immunological cross-matching rules that vary by blood component (Red Blood Cells vs Fresh Frozen Plasma vs Platelets).
2. **Perishable Shelf-Life:** Blood components possess radically divergent shelf lives ranging from 5 days (Platelets) to 365 days (Frozen Plasma).
3. **Emergency Triage Concurrency:** High-concurrency emergency requisitions require pessimistic locking (`SELECT ... FOR UPDATE`) to prevent double-allocation race conditions during trauma operations.
4. **Donor Health Protection:** Clinical deferral policies require a strict minimum 90-day interval between donations.
5. **Chain-of-Custody Auditing:** Regulatory bodies demand an immutable audit trail for every biological unit from phlebotomy to transfusion.

This repository provides an end-to-end, reproducible relational database meeting university DBMS course rubrics.

---

## Architectural Highlights

### 1. 11 Normalized Relational Entities (3NF)
- `blood_groups`: Primary antigen lookup table (`A+`, `A-`, `B+`, `B-`, `AB+`, `AB-`, `O+`, `O-`).
- `blood_compatibility`: M:N recursive associative entity defining compatibility matrices by component.
- `donors`: Demographic and clinical deferral registry.
- `donation_camps`: Mobile and hospital blood collection drives.
- `donation_appointments`: Scheduling coordination with status tracking.
- `blood_donations`: Clinical phlebotomy sessions with volume and hemoglobin checks.
- `blood_units`: Fractionated physical units with calculated expiry dates and location tracking.
- `hospitals`: Accredited healthcare provider registry with emergency contacts and tiers.
- `blood_requests`: Requisitions categorized by urgency level (`Normal`, `Urgent`, `Critical`).
- `transfusion_reservations`: Pessimistic allocation bridge with automated 2-hour locking windows.
- `blood_audit_logs`: Immutable chain-of-custody ledger.

### 2. Biological Shelf-Life State Machine

| Blood Component | Clinical Shelf-Life | Storage Condition | Storage Method |
|---|---|---|---|
| **Platelets** | **5 Days** | $20^\circ\text{C} - 24^\circ\text{C}$ | Continuous Agitator |
| **Whole Blood** | **35 Days** | $2^\circ\text{C} - 6^\circ\text{C}$ | CPDA-1 Refrigeration |
| **Red Blood Cells (RBC)** | **42 Days** | $2^\circ\text{C} - 6^\circ\text{C}$ | SAGM Additive Solution |
| **Fresh Frozen Plasma (FFP)** | **365 Days** | $-18^\circ\text{C}$ or colder | Deep Freezer Vault |

### 3. Cross-Matching Compatibility Logic

```
   RED BLOOD CELLS (RBC) & WHOLE BLOOD               FRESH FROZEN PLASMA (FFP)
   ===================================               =========================
          [ O- ] (Universal Donor)                     [ AB+ / AB- ] (Universal Donor)
          /    \                                                /           \
     [ A- ]    [ B- ]                                       [ A ]           [ B ]
       |         |                                              \           /
     [ A+ ]    [ B+ ]                                           [ O+, O- ] (Universal Recipient)
          \    /
         [ AB+ ] (Universal Recipient)
```

---

## Automated Triggers

1. **`trg_validate_donor_interval_before_donation`** (`BEFORE INSERT ON blood_donations`):
   Enforces a strict 90-day minimum inter-donation interval and checks that the donor's `eligibility_status` is `'Eligible'`. Violations raise `SIGNAL SQLSTATE '45000'`.
2. **`trg_set_component_shelf_life_on_unit_creation`** (`BEFORE INSERT ON blood_units`):
   Automatically computes `expiry_date` according to regulatory guidelines: Platelets (+5 days), RBC (+42 days), Whole Blood (+35 days), Plasma (+365 days).
3. **`trg_log_unit_status_transitions`** (`AFTER UPDATE ON blood_units`):
   Automatically inserts immutable audit records into `blood_audit_logs` whenever a unit's status changes (`Quarantine` $\to$ `Available` $\to$ `Reserved` $\to$ `Transfused` / `Released` / `Expired`).

---

## Stored Procedures & Functions

### 1. `sp_emergency_match_and_reserve`
- **Signature:** `(IN p_request_id INT, OUT p_units_allocated INT)`
- **Behavior:**
  - Opens an explicit ACID transaction with row-level pessimistic locking (`FOR UPDATE`).
  - Evaluates `blood_compatibility` to locate compatible donor blood groups for the requested component.
  - Prioritizes inventory using **FIFO shelf-life sorting** (`ORDER BY expiry_date ASC`) to prevent product expiration.
  - Inserts records into `transfusion_reservations` with a 2-hour clinical pickup expiration window (`NOW() + INTERVAL 2 HOUR`).
  - Automatically updates `blood_requests.fulfillment_status` to `'Fulfilled'` or `'Partially_Fulfilled'`.

### 2. `sp_release_expired_reservations`
- **Signature:** `(OUT p_released_count INT)`
- **Behavior:**
  - Identifies abandoned reservations where `reservation_expiry < NOW() AND status = 'Reserved'`.
  - Marks reservations as `'Released'` and returns units to `'Available'` inventory.
  - Re-evaluates parent requisition fulfillment status.

### 3. `fn_calculate_blood_group_shortage_index`
- **Signature:** `(p_blood_group_id INT, p_city VARCHAR(50)) RETURNS DECIMAL(5,2)`
- **Formula:**
  $$\text{Shortage Index} = \frac{\sum \text{Pending Units Requested}}{\text{Total Screened Available In-Stock Units}}$$
  - Returns `0.00` if demand is zero.
  - Returns `999.99` if on-hand stock is zero and demand is active (acute emergency deficit).

---

## Quickstart & Execution Guide

### Prerequisites
- MySQL 8.0+ or MariaDB 10.4+ (XAMPP / Standalone / Docker).
- MySQL Command-Line Client, MySQL Workbench, or phpMyAdmin.

### Execution via MySQL CLI
Run the modular SQL scripts in strict numerical sequence:

```bash
# 1. Clone repository
git clone https://github.com/affaan-891/centralized-blood-bank-database-project.git
cd centralized-blood-bank-database-project/database

# 2. Execute scripts in sequence
mysql -u root -p < 01_schema.sql
mysql -u root -p blood_bank_db < 02_triggers.sql
mysql -u root -p blood_bank_db < 03_procedures.sql
mysql -u root -p blood_bank_db < 05_seed_data.sql
mysql -u root -p blood_bank_db < 04_views_and_queries.sql
```

### Execution via MySQL Interactive Prompt
```sql
SOURCE /path/to/database/01_schema.sql;
SOURCE /path/to/database/02_triggers.sql;
SOURCE /path/to/database/03_procedures.sql;
SOURCE /path/to/database/05_seed_data.sql;
SOURCE /path/to/database/04_views_and_queries.sql;
```

---

## Verification & Test Runs

### Test 1: Trigger Deferral Policy Verification
Attempting to insert a donation for a donor who donated less than 90 days ago triggers an automated rollback:
```sql
-- Attempt invalid donation within 30 days of last donation
INSERT INTO blood_donations (donor_id, donation_date, hemoglobin_level, volume_ml)
VALUES (3, '2026-08-25', 14.5, 450);

-- Expected Output:
-- ERROR 1644 (45000): Donor deferral policy: Minimum 90 days required between donations or donor is not eligible.
```

### Test 2: Emergency Match Stored Procedure
```sql
USE blood_bank_db;

-- Execute emergency cross-match allocation for Request #1 (Trauma ICU)
CALL sp_emergency_match_and_reserve(1, @units_allocated);

-- Inspect results
SELECT @units_allocated AS allocated_count;
SELECT request_id, fulfillment_status FROM blood_requests WHERE request_id = 1;
SELECT * FROM transfusion_reservations WHERE request_id = 1;
```

### Test 3: Shortage Index Function
```sql
SELECT 
    bg.group_name,
    fn_calculate_blood_group_shortage_index(bg.group_id, 'Lahore') AS shortage_index_lahore,
    fn_calculate_blood_group_shortage_index(bg.group_id, NULL) AS shortage_index_national
FROM blood_groups bg;
```

### Test 4: Live Inventory Dashboard View
```sql
SELECT * FROM vw_live_blood_stock_summary;
```

| group_name | rh_factor | component_type | total_available_units | units_expiring_within_3_days | oldest_unit_expiry_date | freshest_collection_date |
|---|---|---|---|---|---|---|
| O- | - | RBC | 1 | 0 | 2026-10-30 | 2026-09-18 |
| O- | - | Platelets | 1 | 1 | 2026-09-23 | 2026-09-18 |
| O- | - | Plasma | 2 | 0 | 2027-08-01 | 2026-09-18 |
| O+ | + | RBC | 1 | 0 | 2026-10-31 | 2026-09-19 |
| O+ | + | Platelets | 1 | 1 | 2026-09-24 | 2026-09-19 |
| A+ | + | Plasma | 1 | 0 | 2027-08-10 | 2026-08-10 |

---

## Documentation Links

- **[Entity Relationship Diagram & Data Dictionary](docs/ERD.md)**: Full Crow's Foot ERD, entity definitions, constraints, and 3NF normalization proofs.
- **[Viva Voce Preparation Guide](docs/VIVA_QUESTIONS.md)**: 10 in-depth oral defense questions covering concurrency, transactions, and clinical state machines.

---

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
