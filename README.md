# Smart Parking Management System (Flask + MySQL)

A web front end for the `smart_parking` database: dashboard, customers, vehicles, lots and slots,
check-in / check-out with automatic billing, payments and reports.

The interface uses a dark admin-dashboard theme (sidebar navigation, stat cards, revenue bar chart,
progress bars and status pills). The sun/moon button in the top bar switches to a light theme, and the
search box filters the tables on whichever page you are on. Fonts load from Google Fonts, so the
first load needs internet; without it the app falls back to your system font.

## Folder layout

```
parking_app/
├── app.py            Flask backend (routes + SQL)
├── setup_db.sql      Creates the database, tables, sample data and the 3 views
├── requirements.txt
├── static/style.css
└── templates/        HTML pages (Jinja2)
```

## Run it

1. **Create the database.** Open MySQL Workbench, open `setup_db.sql` and run the whole script.
   (Or in a terminal: `mysql -u root -p < setup_db.sql`.)
   It drops and recreates `smart_parking`, so run it only when you want a fresh start.

2. **Install the Python packages** (Python 3.9+):

   ```
   pip install -r requirements.txt
   ```

3. **Tell the app your MySQL password.**

   Windows (PowerShell):
   ```
   $env:DB_PASSWORD = "your_mysql_password"
   ```
   Windows (cmd):
   ```
   set DB_PASSWORD=your_mysql_password
   ```
   macOS / Linux:
   ```
   export DB_PASSWORD="your_mysql_password"
   ```

   Other optional settings (defaults in brackets): `DB_HOST` [localhost], `DB_PORT` [3306],
   `DB_USER` [root], `DB_NAME` [smart_parking].

4. **Start the server** and open <http://127.0.0.1:5000>:

   ```
   python app.py
   ```

## How the pages map to your DBMS requirements

| Page | What it demonstrates |
|---|---|
| Dashboard | Views `v_slot_availability`, `v_current_occupancy`, `v_lot_revenue`; aggregates (COUNT/SUM/AVG), GROUP BY, 5-table join |
| Customers | INSERT, UPDATE, DELETE, UNIQUE (phone/email), NOT NULL |
| Vehicles | INSERT, DELETE, FK to customer, CHECK on vehicle type, UNIQUE plate |
| Lots & slots | INSERT, UPDATE (status, hourly rate), DELETE, UNIQUE (lot + slot number) |
| Check in / out | Transaction across 3 tables: session INSERT, slot UPDATE, payment INSERT |
| Payments | 4-table INNER JOIN |
| Reports | 6 reports using joins, GROUP BY, COUNT / SUM / AVG / MIN / MAX, and the views |

## Billing rule

Billed per started hour at the slot type's hourly rate, minimum one hour.
Example: 2 h 10 min in a Car slot at Rs. 30/hr is 3 hours, so Rs. 90.

## Common problems

* **Access denied for user 'root'** — `DB_PASSWORD` is not set in the terminal you start `python app.py` from.
* **Unknown database 'smart_parking'** — run `setup_db.sql` first.
* **Can't connect to MySQL server** — the MySQL service is not running (start it from Services on Windows).
* After a successful check-out you cannot delete that vehicle, slot or customer. This is intentional: the
  foreign keys protect the billing history.
