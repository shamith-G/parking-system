-- =====================================================================
-- SMART PARKING MANAGEMENT SYSTEM  |  DBMS Mini Project  |  MySQL 8.0+
-- Run the whole file top to bottom in MySQL Workbench / mysql CLI.
-- =====================================================================

DROP DATABASE IF EXISTS smart_parking;
CREATE DATABASE smart_parking;
USE smart_parking;

-- =====================================================================
-- STEP 1: TABLES  (7 entities, PK, FK, NOT NULL, UNIQUE, CHECK, DEFAULT)
-- =====================================================================

-- Entity 1: customer
CREATE TABLE customer (
    customer_id   INT AUTO_INCREMENT PRIMARY KEY,
    full_name     VARCHAR(100) NOT NULL,
    phone         VARCHAR(15)  NOT NULL UNIQUE,
    email         VARCHAR(100) UNIQUE,
    registered_on DATE NOT NULL DEFAULT (CURRENT_DATE)
);

-- Entity 2: vehicle   (Relationship 1: customer 1 --- N vehicle)
CREATE TABLE vehicle (
    vehicle_id   INT AUTO_INCREMENT PRIMARY KEY,
    customer_id  INT NOT NULL,
    plate_no     VARCHAR(15) NOT NULL UNIQUE,
    vehicle_type VARCHAR(10) NOT NULL DEFAULT 'Car',
    CONSTRAINT chk_vehicle_type CHECK (vehicle_type IN ('Bike','Car','SUV')),
    CONSTRAINT fk_vehicle_customer FOREIGN KEY (customer_id)
        REFERENCES customer(customer_id) ON DELETE CASCADE
);

-- Entity 3: parking_lot
CREATE TABLE parking_lot (
    lot_id     INT AUTO_INCREMENT PRIMARY KEY,
    lot_name   VARCHAR(100) NOT NULL UNIQUE,
    location   VARCHAR(150) NOT NULL,
    open_time  TIME NOT NULL DEFAULT '06:00:00',
    close_time TIME NOT NULL DEFAULT '22:00:00'
);

-- Entity 4: slot_type  (rate depends on type, not on slot -> keeps 3NF)
CREATE TABLE slot_type (
    type_id       INT AUTO_INCREMENT PRIMARY KEY,
    type_name     VARCHAR(10) NOT NULL UNIQUE,
    rate_per_hour DECIMAL(6,2) NOT NULL,
    CONSTRAINT chk_rate CHECK (rate_per_hour > 0)
);

-- Entity 5: parking_slot  (Relationships 2 & 3: lot 1---N slot, slot_type 1---N slot)
CREATE TABLE parking_slot (
    slot_id     INT AUTO_INCREMENT PRIMARY KEY,
    lot_id      INT NOT NULL,
    type_id     INT NOT NULL,
    slot_number VARCHAR(10) NOT NULL,
    status      VARCHAR(12) NOT NULL DEFAULT 'Available',
    CONSTRAINT chk_slot_status CHECK (status IN ('Available','Occupied','Maintenance')),
    CONSTRAINT uq_lot_slot UNIQUE (lot_id, slot_number),
    CONSTRAINT fk_slot_lot  FOREIGN KEY (lot_id)  REFERENCES parking_lot(lot_id),
    CONSTRAINT fk_slot_type FOREIGN KEY (type_id) REFERENCES slot_type(type_id)
);

-- Entity 6: parking_session  (Relationships 4 & 5: vehicle 1---N session, slot 1---N session)
CREATE TABLE parking_session (
    session_id INT AUTO_INCREMENT PRIMARY KEY,
    vehicle_id INT NOT NULL,
    slot_id    INT NOT NULL,
    entry_time DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    exit_time  DATETIME NULL,
    CONSTRAINT chk_times CHECK (exit_time IS NULL OR exit_time > entry_time),
    CONSTRAINT fk_session_vehicle FOREIGN KEY (vehicle_id) REFERENCES vehicle(vehicle_id),
    CONSTRAINT fk_session_slot    FOREIGN KEY (slot_id)    REFERENCES parking_slot(slot_id)
);

-- Entity 7: payment  (Relationship 6: session 1---1 payment)
CREATE TABLE payment (
    payment_id     INT AUTO_INCREMENT PRIMARY KEY,
    session_id     INT NOT NULL UNIQUE,
    amount         DECIMAL(8,2) NOT NULL,
    payment_mode   VARCHAR(10) NOT NULL DEFAULT 'Cash',
    payment_time   DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT chk_amount CHECK (amount >= 0),
    CONSTRAINT chk_mode   CHECK (payment_mode IN ('Cash','UPI','Card')),
    CONSTRAINT fk_payment_session FOREIGN KEY (session_id) REFERENCES parking_session(session_id)
);

-- =====================================================================
-- STEP 2: INSERT sample data
-- =====================================================================

INSERT INTO customer (full_name, phone, email) VALUES
('Arjun Rao',   '9876500001', 'arjun@mail.com'),
('Meera Nair',  '9876500002', 'meera@mail.com'),
('Rahul Verma', '9876500003', 'rahul@mail.com'),
('Sneha Iyer',  '9876500004', 'sneha@mail.com'),
('Kiran Patel', '9876500005', NULL);

INSERT INTO vehicle (customer_id, plate_no, vehicle_type) VALUES
(1, 'KA01AB1234', 'Car'),
(1, 'KA02CD5678', 'Bike'),
(2, 'KA03EF9012', 'SUV'),
(3, 'KA05GH3456', 'Car'),
(4, 'KA04IJ7890', 'Bike'),
(5, 'KA51KL1122', 'Car');

INSERT INTO parking_lot (lot_name, location) VALUES
('City Mall Parking', 'MG Road, Bengaluru'),
('Tech Park Parking', 'Whitefield, Bengaluru');

INSERT INTO slot_type (type_name, rate_per_hour) VALUES
('Bike', 10.00), ('Car', 30.00), ('SUV', 50.00);

INSERT INTO parking_slot (lot_id, type_id, slot_number, status) VALUES
(1, 2, 'A1', 'Available'),
(1, 2, 'A2', 'Available'),
(1, 1, 'A3', 'Available'),
(1, 3, 'A4', 'Occupied'),
(2, 2, 'B1', 'Available'),
(2, 2, 'B2', 'Available'),
(2, 1, 'B3', 'Available'),
(2, 3, 'B4', 'Available'),
(2, 1, 'B5', 'Available'),
(2, 2, 'B6', 'Maintenance');

INSERT INTO parking_session (vehicle_id, slot_id, entry_time, exit_time) VALUES
(1, 1, '2026-11-10 09:00:00', '2026-11-10 11:30:00'),
(2, 3, '2026-11-10 10:00:00', '2026-11-10 12:00:00'),
(3, 4, '2026-11-11 14:00:00', '2026-11-11 18:00:00'),
(4, 5, '2026-11-12 08:00:00', '2026-11-12 17:00:00'),
(5, 7, '2026-11-13 09:30:00', '2026-11-13 10:30:00'),
(6, 6, '2026-11-14 11:00:00', '2026-11-14 13:00:00'),
(1, 2, '2026-11-15 09:00:00', '2026-11-15 12:00:00'),
(3, 4, '2026-11-17 10:00:00', NULL);          -- still parked

INSERT INTO payment (session_id, amount, payment_mode, payment_time) VALUES
(1,  90.00, 'UPI',  '2026-11-10 11:30:00'),
(2,  20.00, 'Cash', '2026-11-10 12:00:00'),
(3, 200.00, 'Card', '2026-11-11 18:00:00'),
(4, 270.00, 'UPI',  '2026-11-12 17:00:00'),
(5,  10.00, 'Cash', '2026-11-13 10:30:00'),
(6,  60.00, 'UPI',  '2026-11-14 13:00:00'),
(7,  90.00, 'Card', '2026-11-15 12:00:00');

-- =====================================================================
-- STEP 7: VIEWS
-- =====================================================================

-- View 1: vehicles currently inside a lot
CREATE VIEW v_current_occupancy AS
SELECT s.session_id, v.plate_no, c.full_name, l.lot_name, ps.slot_number,
       s.entry_time,
       TIMESTAMPDIFF(MINUTE, s.entry_time, NOW()) AS minutes_parked
FROM parking_session s
JOIN vehicle      v  ON s.vehicle_id  = v.vehicle_id
JOIN customer     c  ON v.customer_id = c.customer_id
JOIN parking_slot ps ON s.slot_id     = ps.slot_id
JOIN parking_lot  l  ON ps.lot_id     = l.lot_id
WHERE s.exit_time IS NULL;

-- View 2: revenue per parking lot
CREATE VIEW v_lot_revenue AS
SELECT l.lot_id, l.lot_name,
       COUNT(p.payment_id)       AS paid_sessions,
       COALESCE(SUM(p.amount),0) AS total_revenue
FROM parking_lot l
LEFT JOIN parking_slot ps    ON l.lot_id = ps.lot_id
LEFT JOIN parking_session s  ON ps.slot_id = s.slot_id
LEFT JOIN payment p          ON s.session_id = p.session_id
GROUP BY l.lot_id, l.lot_name;

-- View 3: slot availability per lot
CREATE VIEW v_slot_availability AS
SELECT l.lot_name,
       COUNT(*)                          AS total_slots,
       SUM(ps.status = 'Available')      AS available,
       SUM(ps.status = 'Occupied')       AS occupied,
       SUM(ps.status = 'Maintenance')    AS under_maintenance
FROM parking_lot l
JOIN parking_slot ps ON l.lot_id = ps.lot_id
GROUP BY l.lot_name;
