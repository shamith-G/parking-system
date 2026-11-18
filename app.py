"""
Smart Parking Management System - Flask front end + back end
Connects to the MySQL database `smart_parking` created by smart_parking.sql

Configure the connection with environment variables (defaults shown):
    DB_HOST=localhost  DB_PORT=3306  DB_USER=root  DB_PASSWORD=  DB_NAME=smart_parking
"""
import math
import os
from datetime import datetime, timedelta
from decimal import Decimal

import mysql.connector
from flask import Flask, flash, redirect, render_template, request, url_for
from mysql.connector import Error

app = Flask(__name__)
app.secret_key = os.environ.get("SECRET_KEY", "change-this-secret-key")

DB_CONFIG = {
    "host": os.environ.get("DB_HOST", "localhost"),
    "port": int(os.environ.get("DB_PORT", "3306")),
    "user": os.environ.get("DB_USER", "root"),
    "password": os.environ.get("DB_PASSWORD", ""),
    "database": os.environ.get("DB_NAME", "smart_parking"),
}

VEHICLE_TYPES = ["Bike", "Car", "SUV"]
SLOT_STATUSES = ["Available", "Occupied", "Maintenance"]
PAYMENT_MODES = ["Cash", "UPI", "Card"]


# ---------------------------------------------------------------- DB helpers
def get_conn():
    return mysql.connector.connect(**DB_CONFIG)


def query(sql, params=None, one=False):
    """Run a SELECT and return a list of dicts (or a single dict if one=True)."""
    conn = get_conn()
    try:
        cur = conn.cursor(dictionary=True)
        cur.execute(sql, params or ())
        rows = cur.fetchall()
        if one:
            return rows[0] if rows else None
        return rows
    finally:
        conn.close()


def execute(sql, params=None):
    """Run an INSERT / UPDATE / DELETE, commit, and return the affected row count."""
    conn = get_conn()
    try:
        cur = conn.cursor()
        cur.execute(sql, params or ())
        conn.commit()
        return cur.rowcount
    finally:
        conn.close()


def friendly_error(e):
    """Turn a MySQL error into a message a user can understand."""
    errno = getattr(e, "errno", None)
    if errno == 1062:
        return "That value already exists (phone, email, plate number or slot number must be unique)."
    if errno in (1451, 1217):
        return "Cannot delete this record because other records depend on it."
    if errno == 1452:
        return "The referenced record does not exist."
    if errno in (3819, 4025):
        return "A database rule (CHECK constraint) rejected that value."
    if errno == 1048:
        return "A required field was left empty."
    return f"Database error: {getattr(e, 'msg', e)}"


# ------------------------------------------------------- Template helpers
@app.template_filter("hue")
def hue_filter(text):
    """Stable colour (0-359) derived from a name, used for avatar circles."""
    return sum(ord(ch) for ch in str(text)) * 37 % 360


@app.template_filter("initials")
def initials_filter(text):
    parts = str(text).replace(".", " ").split()
    return "".join(p[0] for p in parts[:2]).upper() or "?"


@app.template_filter("money")
def money_filter(value):
    try:
        return f"{float(value):,.2f}"
    except (TypeError, ValueError):
        return value


@app.context_processor
def inject_globals():
    """Values every page needs: today's date and the live 'parked now' badge."""
    parked = 0
    try:
        row = query("SELECT COUNT(*) AS n FROM parking_session WHERE exit_time IS NULL", one=True)
        parked = row["n"] if row else 0
    except Error:
        pass
    return {"today": datetime.now(), "parked_badge": parked}


# ----------------------------------------------------------------- Dashboard
@app.route("/")
def dashboard():
    availability, occupancy, revenue, totals = [], [], [], None
    daily, recent, modes, slot_status = [], [], [], []
    try:
        availability = query("SELECT * FROM v_slot_availability")
        occupancy = query("SELECT * FROM v_current_occupancy ORDER BY entry_time")
        revenue = query("SELECT * FROM v_lot_revenue ORDER BY total_revenue DESC")
        totals = query(
            """SELECT
                 (SELECT COUNT(*) FROM parking_slot)                              AS total_slots,
                 (SELECT COUNT(*) FROM parking_slot WHERE status = 'Available')   AS available_slots,
                 (SELECT COUNT(*) FROM parking_session WHERE exit_time IS NULL)   AS parked_now,
                 (SELECT COUNT(*) FROM parking_session)                           AS total_sessions,
                 (SELECT COUNT(*) FROM customer)                                  AS total_customers,
                 (SELECT COALESCE(SUM(amount), 0) FROM payment)                   AS total_revenue,
                 (SELECT COALESCE(AVG(amount), 0) FROM payment)                   AS avg_payment""",
            one=True,
        )
        # Latest 7 days that have payments, oldest first (for the bar chart).
        daily = query(
            """SELECT day, revenue FROM (
                   SELECT DATE(payment_time) AS day, SUM(amount) AS revenue
                   FROM payment GROUP BY DATE(payment_time)
                   ORDER BY day DESC LIMIT 7
               ) t ORDER BY day"""
        )
        recent = query(
            """SELECT p.payment_id, v.plate_no, c.full_name, l.lot_name,
                      p.amount, p.payment_mode, p.payment_time
               FROM payment p
               JOIN parking_session s ON p.session_id  = s.session_id
               JOIN vehicle v         ON s.vehicle_id  = v.vehicle_id
               JOIN customer c        ON v.customer_id = c.customer_id
               JOIN parking_slot ps   ON s.slot_id     = ps.slot_id
               JOIN parking_lot l     ON ps.lot_id     = l.lot_id
               ORDER BY p.payment_time DESC, p.payment_id DESC LIMIT 5"""
        )
        modes = query(
            """SELECT payment_mode, COUNT(*) AS n, SUM(amount) AS total
               FROM payment GROUP BY payment_mode ORDER BY total DESC"""
        )
        slot_status = query(
            "SELECT status, COUNT(*) AS n FROM parking_slot GROUP BY status"
        )
    except Error as e:
        flash(friendly_error(e), "error")

    # Pre-compute chart geometry so the template stays simple.
    max_rev = max((float(d["revenue"]) for d in daily), default=0) or 1
    for d in daily:
        d["pct"] = round(float(d["revenue"]) / max_rev * 100)
    total_slots = sum(s["n"] for s in slot_status) or 1
    status_map = {s["status"]: s["n"] for s in slot_status}
    slot_bars = [
        {"label": label, "n": status_map.get(label, 0),
         "pct": round(status_map.get(label, 0) / total_slots * 100), "cls": cls}
        for label, cls in (("Available", "ok"), ("Occupied", "warn"), ("Maintenance", "mute"))
    ]
    total_paid = sum(float(m["total"]) for m in modes) or 1
    for m in modes:
        m["pct"] = round(float(m["total"]) / total_paid * 100)

    # Sparkline for the revenue tile (200 x 60 viewBox).
    spark_line = spark_area = ""
    if len(daily) >= 2:
        step = 200 / (len(daily) - 1)
        pts = [(round(i * step, 1), round(54 - d["pct"] / 100 * 46, 1)) for i, d in enumerate(daily)]
        spark_line = "M" + " L".join(f"{x},{y}" for x, y in pts)
        spark_area = spark_line + " L200,60 L0,60 Z"

    return render_template(
        "dashboard.html",
        availability=availability, occupancy=occupancy, revenue=revenue, totals=totals,
        daily=daily, recent=recent, modes=modes, slot_bars=slot_bars,
        spark_line=spark_line, spark_area=spark_area,
    )


# ----------------------------------------------------------------- Customers
@app.route("/customers", methods=["GET", "POST"])
def customers():
    if request.method == "POST":
        name = request.form.get("full_name", "").strip()
        phone = request.form.get("phone", "").strip()
        email = request.form.get("email", "").strip() or None
        if not name or not phone:
            flash("Name and phone are required.", "error")
        else:
            try:
                execute(
                    "INSERT INTO customer (full_name, phone, email) VALUES (%s, %s, %s)",
                    (name, phone, email),
                )
                flash(f"Customer '{name}' added.", "success")
            except Error as e:
                flash(friendly_error(e), "error")
        return redirect(url_for("customers"))

    rows = query(
        """SELECT c.customer_id, c.full_name, c.phone, c.email, c.registered_on,
                  COUNT(v.vehicle_id) AS vehicles
           FROM customer c LEFT JOIN vehicle v ON c.customer_id = v.customer_id
           GROUP BY c.customer_id, c.full_name, c.phone, c.email, c.registered_on
           ORDER BY c.customer_id"""
    )
    return render_template("customers.html", customers=rows)


@app.post("/customers/<int:customer_id>/update")
def update_customer(customer_id):
    name = request.form.get("full_name", "").strip()
    phone = request.form.get("phone", "").strip()
    email = request.form.get("email", "").strip() or None
    if not name or not phone:
        flash("Name and phone are required.", "error")
    else:
        try:
            execute(
                "UPDATE customer SET full_name=%s, phone=%s, email=%s WHERE customer_id=%s",
                (name, phone, email, customer_id),
            )
            flash("Customer updated.", "success")
        except Error as e:
            flash(friendly_error(e), "error")
    return redirect(url_for("customers"))


@app.post("/customers/<int:customer_id>/delete")
def delete_customer(customer_id):
    try:
        execute("DELETE FROM customer WHERE customer_id = %s", (customer_id,))
        flash("Customer deleted.", "success")
    except Error as e:
        flash(friendly_error(e), "error")
    return redirect(url_for("customers"))


# ------------------------------------------------------------------ Vehicles
@app.route("/vehicles", methods=["GET", "POST"])
def vehicles():
    if request.method == "POST":
        customer_id = request.form.get("customer_id", type=int)
        plate = request.form.get("plate_no", "").replace(" ", "").upper()
        vtype = request.form.get("vehicle_type", "Car")
        if not customer_id or not plate or vtype not in VEHICLE_TYPES:
            flash("Owner, plate number and a valid vehicle type are required.", "error")
        else:
            try:
                execute(
                    "INSERT INTO vehicle (customer_id, plate_no, vehicle_type) VALUES (%s, %s, %s)",
                    (customer_id, plate, vtype),
                )
                flash(f"Vehicle {plate} added.", "success")
            except Error as e:
                flash(friendly_error(e), "error")
        return redirect(url_for("vehicles"))

    rows = query(
        """SELECT v.vehicle_id, v.plate_no, v.vehicle_type, c.full_name AS owner, c.phone
           FROM vehicle v JOIN customer c ON v.customer_id = c.customer_id
           ORDER BY v.vehicle_id"""
    )
    owners = query("SELECT customer_id, full_name FROM customer ORDER BY full_name")
    return render_template("vehicles.html", vehicles=rows, owners=owners, types=VEHICLE_TYPES)


@app.post("/vehicles/<int:vehicle_id>/delete")
def delete_vehicle(vehicle_id):
    try:
        execute("DELETE FROM vehicle WHERE vehicle_id = %s", (vehicle_id,))
        flash("Vehicle deleted.", "success")
    except Error as e:
        flash(friendly_error(e), "error")
    return redirect(url_for("vehicles"))


# --------------------------------------------------------- Lots, slots, rates
@app.route("/slots", methods=["GET", "POST"])
def slots():
    if request.method == "POST":
        lot_id = request.form.get("lot_id", type=int)
        type_id = request.form.get("type_id", type=int)
        number = request.form.get("slot_number", "").strip().upper()
        if not lot_id or not type_id or not number:
            flash("Lot, slot type and slot number are required.", "error")
        else:
            try:
                execute(
                    "INSERT INTO parking_slot (lot_id, type_id, slot_number) VALUES (%s, %s, %s)",
                    (lot_id, type_id, number),
                )
                flash(f"Slot {number} added.", "success")
            except Error as e:
                flash(friendly_error(e), "error")
        return redirect(url_for("slots"))

    lot_filter = request.args.get("lot_id", type=int)
    sql = """SELECT ps.slot_id, l.lot_name, ps.slot_number, st.type_name,
                    st.rate_per_hour, ps.status
             FROM parking_slot ps
             JOIN parking_lot l  ON ps.lot_id  = l.lot_id
             JOIN slot_type  st  ON ps.type_id = st.type_id"""
    params = ()
    if lot_filter:
        sql += " WHERE ps.lot_id = %s"
        params = (lot_filter,)
    sql += " ORDER BY l.lot_name, ps.slot_number"

    return render_template(
        "slots.html",
        slots=query(sql, params),
        lots=query("SELECT lot_id, lot_name, location FROM parking_lot ORDER BY lot_name"),
        types=query("SELECT type_id, type_name, rate_per_hour FROM slot_type ORDER BY type_id"),
        lot_filter=lot_filter,
    )


@app.post("/slots/<int:slot_id>/status")
def set_slot_status(slot_id):
    status = request.form.get("status")
    if status not in ("Available", "Maintenance"):
        flash("Invalid status.", "error")
        return redirect(url_for("slots"))
    try:
        # A slot with a car in it can only be freed by checking the car out.
        changed = execute(
            "UPDATE parking_slot SET status = %s WHERE slot_id = %s AND status <> 'Occupied'",
            (status, slot_id),
        )
        if changed:
            flash(f"Slot marked {status}.", "success")
        else:
            flash("Occupied slots cannot be changed. Check the vehicle out first.", "error")
    except Error as e:
        flash(friendly_error(e), "error")
    return redirect(url_for("slots"))


@app.post("/slots/<int:slot_id>/delete")
def delete_slot(slot_id):
    try:
        execute("DELETE FROM parking_slot WHERE slot_id = %s", (slot_id,))
        flash("Slot deleted.", "success")
    except Error as e:
        flash(friendly_error(e), "error")
    return redirect(url_for("slots"))


@app.post("/lots/add")
def add_lot():
    name = request.form.get("lot_name", "").strip()
    location = request.form.get("location", "").strip()
    if not name or not location:
        flash("Lot name and location are required.", "error")
    else:
        try:
            execute("INSERT INTO parking_lot (lot_name, location) VALUES (%s, %s)", (name, location))
            flash(f"Parking lot '{name}' added.", "success")
        except Error as e:
            flash(friendly_error(e), "error")
    return redirect(url_for("slots"))


@app.post("/slot-types/<int:type_id>/rate")
def update_rate(type_id):
    try:
        rate = Decimal(request.form.get("rate_per_hour", ""))
        execute("UPDATE slot_type SET rate_per_hour = %s WHERE type_id = %s", (rate, type_id))
        flash("Hourly rate updated.", "success")
    except ArithmeticError:
        flash("Enter a valid number for the rate.", "error")
    except Error as e:
        flash(friendly_error(e), "error")
    return redirect(url_for("slots"))


# ------------------------------------------- Parking sessions (in / out / bill)
@app.route("/sessions")
def sessions():
    rows = query(
        """SELECT s.session_id, v.plate_no, v.vehicle_type, l.lot_name, ps.slot_number,
                  s.entry_time, s.exit_time, p.amount, p.payment_mode
           FROM parking_session s
           JOIN vehicle v       ON s.vehicle_id = v.vehicle_id
           JOIN parking_slot ps ON s.slot_id    = ps.slot_id
           JOIN parking_lot l   ON ps.lot_id    = l.lot_id
           LEFT JOIN payment p  ON s.session_id = p.session_id
           ORDER BY (s.exit_time IS NULL) DESC, s.entry_time DESC"""
    )
    free_vehicles = query(
        """SELECT v.vehicle_id, v.plate_no, v.vehicle_type
           FROM vehicle v
           WHERE NOT EXISTS (SELECT 1 FROM parking_session s
                             WHERE s.vehicle_id = v.vehicle_id AND s.exit_time IS NULL)
           ORDER BY v.plate_no"""
    )
    free_slots = query(
        """SELECT ps.slot_id, l.lot_name, ps.slot_number, st.type_name, st.rate_per_hour
           FROM parking_slot ps
           JOIN parking_lot l ON ps.lot_id  = l.lot_id
           JOIN slot_type st  ON ps.type_id = st.type_id
           WHERE ps.status = 'Available'
           ORDER BY l.lot_name, ps.slot_number"""
    )
    return render_template(
        "sessions.html",
        sessions=rows, free_vehicles=free_vehicles, free_slots=free_slots, modes=PAYMENT_MODES,
    )


@app.post("/sessions/checkin")
def checkin():
    vehicle_id = request.form.get("vehicle_id", type=int)
    slot_id = request.form.get("slot_id", type=int)
    if not vehicle_id or not slot_id:
        flash("Choose a vehicle and a slot.", "error")
        return redirect(url_for("sessions"))

    conn = get_conn()
    try:
        conn.start_transaction()
        cur = conn.cursor(dictionary=True)

        cur.execute("SELECT vehicle_type FROM vehicle WHERE vehicle_id = %s", (vehicle_id,))
        vehicle = cur.fetchone()
        cur.execute(
            """SELECT ps.status, st.type_name
               FROM parking_slot ps JOIN slot_type st ON ps.type_id = st.type_id
               WHERE ps.slot_id = %s FOR UPDATE""",
            (slot_id,),
        )
        slot = cur.fetchone()
        cur.execute(
            "SELECT 1 AS x FROM parking_session WHERE vehicle_id = %s AND exit_time IS NULL",
            (vehicle_id,),
        )
        already_parked = cur.fetchone()

        if not vehicle or not slot:
            flash("Vehicle or slot not found.", "error")
        elif already_parked:
            flash("That vehicle is already parked.", "error")
        elif slot["status"] != "Available":
            flash("That slot is not available.", "error")
        elif slot["type_name"] != vehicle["vehicle_type"]:
            flash(f"A {vehicle['vehicle_type']} cannot use a {slot['type_name']} slot.", "error")
        else:
            cur.execute(
                "INSERT INTO parking_session (vehicle_id, slot_id) VALUES (%s, %s)",
                (vehicle_id, slot_id),
            )
            cur.execute("UPDATE parking_slot SET status = 'Occupied' WHERE slot_id = %s", (slot_id,))
            conn.commit()
            flash("Vehicle checked in.", "success")
            return redirect(url_for("sessions"))
        conn.rollback()
    except Error as e:
        conn.rollback()
        flash(friendly_error(e), "error")
    finally:
        conn.close()
    return redirect(url_for("sessions"))


@app.post("/sessions/<int:session_id>/checkout")
def checkout(session_id):
    mode = request.form.get("payment_mode", "Cash")
    if mode not in PAYMENT_MODES:
        flash("Invalid payment mode.", "error")
        return redirect(url_for("sessions"))

    conn = get_conn()
    try:
        conn.start_transaction()
        cur = conn.cursor(dictionary=True)
        cur.execute(
            """SELECT s.entry_time, s.exit_time, s.slot_id, st.rate_per_hour
               FROM parking_session s
               JOIN parking_slot ps ON s.slot_id  = ps.slot_id
               JOIN slot_type st    ON ps.type_id = st.type_id
               WHERE s.session_id = %s FOR UPDATE""",
            (session_id,),
        )
        row = cur.fetchone()
        if not row or row["exit_time"] is not None:
            conn.rollback()
            flash("This session does not exist or is already closed.", "error")
            return redirect(url_for("sessions"))

        now = datetime.now().replace(microsecond=0)
        if now <= row["entry_time"]:          # keeps the CHECK (exit_time > entry_time) happy
            now = row["entry_time"] + timedelta(minutes=1)

        minutes = (now - row["entry_time"]).total_seconds() / 60
        hours = max(1, math.ceil(minutes / 60))          # billed per started hour, minimum 1
        amount = Decimal(hours) * row["rate_per_hour"]

        cur.execute("UPDATE parking_session SET exit_time = %s WHERE session_id = %s", (now, session_id))
        cur.execute("UPDATE parking_slot SET status = 'Available' WHERE slot_id = %s", (row["slot_id"],))
        cur.execute(
            "INSERT INTO payment (session_id, amount, payment_mode) VALUES (%s, %s, %s)",
            (session_id, amount, mode),
        )
        conn.commit()
        flash(f"Checked out. Billed {hours} hour(s): Rs. {amount:.2f} paid by {mode}.", "success")
    except Error as e:
        conn.rollback()
        flash(friendly_error(e), "error")
    finally:
        conn.close()
    return redirect(url_for("sessions"))


# ------------------------------------------------------------------ Payments
@app.route("/payments")
def payments():
    rows = query(
        """SELECT p.payment_id, p.session_id, v.plate_no, l.lot_name,
                  p.amount, p.payment_mode, p.payment_time
           FROM payment p
           JOIN parking_session s ON p.session_id = s.session_id
           JOIN vehicle v         ON s.vehicle_id = v.vehicle_id
           JOIN parking_slot ps   ON s.slot_id    = ps.slot_id
           JOIN parking_lot l     ON ps.lot_id    = l.lot_id
           ORDER BY p.payment_time DESC"""
    )
    return render_template("payments.html", payments=rows)


# ------------------------------------------------------------------- Reports
@app.route("/reports")
def reports():
    definitions = [
        ("Revenue by parking lot",
         "Total money earned and number of paid sessions per lot (view: v_lot_revenue).",
         "SELECT lot_name, paid_sessions, total_revenue FROM v_lot_revenue ORDER BY total_revenue DESC"),
        ("Top customers by spending",
         "Visits and total amount paid per customer.",
         """SELECT c.full_name, COUNT(DISTINCT s.session_id) AS visits, SUM(p.amount) AS total_spent
            FROM customer c
            JOIN vehicle v         ON c.customer_id = v.customer_id
            JOIN parking_session s ON v.vehicle_id  = s.vehicle_id
            JOIN payment p         ON s.session_id  = p.session_id
            GROUP BY c.customer_id, c.full_name
            ORDER BY total_spent DESC"""),
        ("Slot-type usage and revenue",
         "Which kind of slot earns the most.",
         """SELECT st.type_name, COUNT(s.session_id) AS sessions, COALESCE(SUM(p.amount), 0) AS revenue
            FROM slot_type st
            JOIN parking_slot ps        ON st.type_id = ps.type_id
            LEFT JOIN parking_session s ON ps.slot_id = s.slot_id
            LEFT JOIN payment p         ON s.session_id = p.session_id
            GROUP BY st.type_name
            ORDER BY revenue DESC"""),
        ("Daily revenue",
         "Payments received per day.",
         """SELECT DATE(payment_time) AS day, COUNT(*) AS payments, SUM(amount) AS revenue
            FROM payment GROUP BY DATE(payment_time) ORDER BY day DESC"""),
        ("Slot availability by lot",
         "Live snapshot (view: v_slot_availability).",
         "SELECT * FROM v_slot_availability"),
        ("Payment summary",
         "COUNT, SUM, AVG, MIN and MAX of all payments.",
         """SELECT COUNT(*) AS total_payments, COALESCE(SUM(amount), 0) AS total_revenue,
                   ROUND(AVG(amount), 2) AS average_payment,
                   MIN(amount) AS smallest_payment, MAX(amount) AS largest_payment
            FROM payment"""),
    ]
    results = []
    try:
        for title, description, sql in definitions:
            results.append({"title": title, "description": description, "rows": query(sql)})
    except Error as e:
        flash(friendly_error(e), "error")
    return render_template("reports.html", reports=results)


if __name__ == "__main__":
    app.run(debug=True)
