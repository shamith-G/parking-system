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
-- STEP 3: SELECT basics
-- =====================================================================
SELECT * FROM customer;
SELECT plate_no, vehicle_type FROM vehicle WHERE vehicle_type = 'Car' ORDER BY plate_no;
SELECT * FROM parking_slot WHERE status = 'Available';

-- =====================================================================
-- STEP 4: JOINS (3 different types)
-- =====================================================================

-- JOIN 1 (INNER JOIN, 5 tables): full session history
SELECT s.session_id, c.full_name, v.plate_no, l.lot_name, ps.slot_number,
       s.entry_time, s.exit_time
FROM parking_session s
INNER JOIN vehicle      v  ON s.vehicle_id  = v.vehicle_id
INNER JOIN customer     c  ON v.customer_id = c.customer_id
INNER JOIN parking_slot ps ON s.slot_id     = ps.slot_id
INNER JOIN parking_lot  l  ON ps.lot_id     = l.lot_id
ORDER BY s.entry_time;

-- JOIN 2 (LEFT JOIN): every slot, with how many times it has been used
SELECT l.lot_name, ps.slot_number, ps.status, COUNT(s.session_id) AS times_used
FROM parking_slot ps
LEFT JOIN parking_session s ON ps.slot_id = s.slot_id
JOIN parking_lot l          ON ps.lot_id  = l.lot_id
GROUP BY l.lot_name, ps.slot_number, ps.status
ORDER BY l.lot_name, ps.slot_number;

-- JOIN 3 (RIGHT JOIN): all sessions, with payment info (NULL = unpaid / not yet exited)
SELECT s.session_id, s.vehicle_id, p.amount, p.payment_mode
FROM payment p
RIGHT JOIN parking_session s ON p.session_id = s.session_id;

-- =====================================================================
-- STEP 5: AGGREGATE FUNCTIONS (COUNT, SUM, AVG, MIN, MAX)
-- =====================================================================
SELECT COUNT(*)          AS total_payments,
       SUM(amount)       AS total_revenue,
       AVG(amount)       AS average_payment,
       MIN(amount)       AS smallest_payment,
       MAX(amount)       AS largest_payment
FROM payment;

SELECT payment_mode, COUNT(*) AS num_payments, SUM(amount) AS total
FROM payment
GROUP BY payment_mode
HAVING SUM(amount) > 50;

-- =====================================================================
-- STEP 6: NESTED QUERIES (subqueries)
-- =====================================================================

-- Subquery 1: payments above the average payment
SELECT p.payment_id, p.session_id, p.amount
FROM payment p
WHERE p.amount > (SELECT AVG(amount) FROM payment);

-- Subquery 2: slots that have never been used
SELECT slot_id, slot_number
FROM parking_slot
WHERE slot_id NOT IN (SELECT slot_id FROM parking_session);

-- Subquery 3: customers who own a vehicle that is currently parked
SELECT full_name
FROM customer
WHERE customer_id IN (
    SELECT v.customer_id
    FROM vehicle v
    WHERE v.vehicle_id IN (SELECT vehicle_id FROM parking_session WHERE exit_time IS NULL)
);

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

SELECT * FROM v_current_occupancy;
SELECT * FROM v_lot_revenue;
SELECT * FROM v_slot_availability;

-- =====================================================================
-- STEP 8: REPORTS (meaningful, business-oriented)
-- =====================================================================

-- Report 1: Revenue by parking lot
SELECT lot_name, paid_sessions, total_revenue
FROM v_lot_revenue
ORDER BY total_revenue DESC;

-- Report 2: Top customers by total spending
SELECT c.full_name, COUNT(DISTINCT s.session_id) AS visits, SUM(p.amount) AS total_spent
FROM customer c
JOIN vehicle v          ON c.customer_id = v.customer_id
JOIN parking_session s  ON v.vehicle_id  = s.vehicle_id
JOIN payment p          ON s.session_id  = p.session_id
GROUP BY c.customer_id, c.full_name
ORDER BY total_spent DESC;

-- Report 3: Slot-type usage and revenue (which type earns the most)
SELECT st.type_name, COUNT(s.session_id) AS sessions, COALESCE(SUM(p.amount),0) AS revenue
FROM slot_type st
JOIN parking_slot ps         ON st.type_id = ps.type_id
LEFT JOIN parking_session s  ON ps.slot_id = s.slot_id
LEFT JOIN payment p          ON s.session_id = p.session_id
GROUP BY st.type_name
ORDER BY revenue DESC;

-- Report 4: Daily revenue
SELECT DATE(payment_time) AS day, COUNT(*) AS payments, SUM(amount) AS revenue
FROM payment
GROUP BY DATE(payment_time)
ORDER BY day;

-- Report 5: Availability snapshot (from view)
SELECT * FROM v_slot_availability;

-- =====================================================================
-- STEP 9: UPDATE and DELETE (run last, they change the data)
-- =====================================================================

-- Update 1: vehicle 3 exits -> close the session, free the slot
UPDATE parking_session SET exit_time = '2026-11-17 12:30:00' WHERE session_id = 8;
UPDATE parking_slot    SET status = 'Available'               WHERE slot_id = 4;

-- Insert the bill: 3 billable hours (150 min rounded up) x SUV rate
INSERT INTO payment (session_id, amount, payment_mode)
SELECT s.session_id,
       CEIL(TIMESTAMPDIFF(MINUTE, s.entry_time, s.exit_time) / 60) * st.rate_per_hour,
       'UPI'
FROM parking_session s
JOIN parking_slot ps ON s.slot_id = ps.slot_id
JOIN slot_type st    ON ps.type_id = st.type_id
WHERE s.session_id = 8;

-- Update 2: change a customer's phone number
UPDATE customer SET phone = '9999900005' WHERE customer_id = 5;

-- Update 3: raise SUV rate by 10%
UPDATE slot_type SET rate_per_hour = rate_per_hour * 1.10 WHERE type_name = 'SUV';

-- Delete demo: add a throw-away vehicle, then remove it
INSERT INTO vehicle (customer_id, plate_no, vehicle_type) VALUES (5, 'KA99ZZ0000', 'Bike');
DELETE FROM vehicle WHERE plate_no = 'KA99ZZ0000';

-- Delete 2: remove a slot that was never used (B5)
DELETE FROM parking_slot WHERE slot_number = 'B5' AND lot_id = 2;


SHOW TABLES;

SELECT * FROM customer ORDER BY customer_id DESC LIMIT 3;
SELECT * FROM parking_session ORDER BY session_id DESC LIMIT 3;
SELECT * FROM payment ORDER BY payment_id DESC LIMIT 3;
SELECT * FROM v_lot_revenue;
