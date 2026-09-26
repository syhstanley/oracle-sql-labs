# Shared Schema Reference

Every lab in this course uses the same six tables. Run the two scripts here
**once**, in order, before starting Lab 01 (Lab 00 walks you through this):

1. `01_create_tables.sql` — creates the tables, PKs, FKs, one CHECK constraint
2. `02_seed_data.sql` — loads 9 departments, 52 employees (a manager
   hierarchy up to 4 levels deep), 500 customers, 104 products, 10,000
   orders, 29,710 order line items

The seed is **deterministic** — no `DBMS_RANDOM` — so everyone gets exactly
the same rows, and the same answers to every lab exercise.

If you ever want a clean slate, just re-run both scripts — `01_create_tables.sql`
drops and recreates everything.

## Entity-relationship overview

```
departments ──< employees >── employees          (self-referencing: manager_id)
                    │
                    │ (sales rep, nullable)
                    ▼
customers ──< orders >── employees
    │             │
    │             │
    ▼             ▼
 (via orders) order_items >── products
```

## Table reference

### `departments`
| Column | Type | Notes |
|---|---|---|
| department_id | NUMBER(4) PK | 10, 20, 30 … 90 |
| department_name | VARCHAR2(50) | Sales, Engineering, … — `Research` (90) has no employees |
| location | VARCHAR2(50) | |

### `employees`
| Column | Type | Notes |
|---|---|---|
| employee_id | NUMBER(6) PK | 100 = CEO; 2xx = dept heads (200 + department_id); 1001+ = everyone else. Sales reps are 1001–1012 |
| first_name / last_name | VARCHAR2 | |
| email | VARCHAR2(60) | |
| hire_date | DATE | |
| job_title | VARCHAR2(40) | |
| salary | NUMBER(10,2) | |
| commission_pct | NUMBER(4,2) | only set for Sales reps (1009 is on a 0.00 plan, trainee 1012 has none); NULL otherwise — good for NULL-handling exercises |
| department_id | NUMBER(4) FK → departments | |
| manager_id | NUMBER(6) FK → employees | NULL only for the CEO (row 100) — the root of the hierarchy used in Lab 11 (`CONNECT BY`). Tech Lead 1017 manages six engineers, adding a 4th level |

### `customers`
| Column | Type | Notes |
|---|---|---|
| customer_id | NUMBER(6) PK | 1..500 |
| customer_name, email | VARCHAR2 | names are `Customer 1` … `Customer 500`; emails use several domains, 10 are NULL and 5 are malformed |
| country | VARCHAR2(40) | 7 distinct values, deliberately uneven: Taiwan 130, Japan 100, USA 95, Singapore 60, Germany 50, Vietnam 45, Canada 20 |
| signup_date | DATE | 1–440: 2021–2023, 441–480: 2024, 481–500: 2025 |

### `products`
| Column | Type | Notes |
|---|---|---|
| product_id | NUMBER(6) PK | 1..104 |
| product_name | VARCHAR2(60) | |
| category | VARCHAR2(40) | Electronics, Home, Office, Outdoor, Toys (20 each) + Garden (101–104, never ordered) |
| unit_price | NUMBER(10,2) | |

### `orders`
| Column | Type | Notes |
|---|---|---|
| order_id | NUMBER(8) PK | 1..10000, increasing with `order_date` |
| customer_id | NUMBER(6) FK → customers | **no index** initially (see Module 6) |
| employee_id | NUMBER(6) FK → employees | nullable; **no index** initially |
| order_date | DATE | 2023-01-01 .. 2025-09-30, busier in Nov/Dec; **no index** initially |
| status | VARCHAR2(20) | PENDING / SHIPPED / CANCELLED / COMPLETED (mostly COMPLETED) |

### `order_items`
| Column | Type | Notes |
|---|---|---|
| order_id | NUMBER(8) PK part 1, FK → orders | |
| line_no | NUMBER(3) PK part 2 | 1..5 per order |
| product_id | NUMBER(6) FK → products | |
| quantity | NUMBER(5) | |
| unit_price | NUMBER(10,2) | copied at order time (denormalized on purpose — prices in `products` can drift): 8% below today's list price in 2023, 4% below in 2024 |

**Why no secondary indexes yet?** Modules 1–5 deliberately run against a
schema with only primary-key indexes, so when you hit Module 6 (execution
plans / index access paths) you'll *see* a full table scan on 10,000+ rows,
add an index yourself, and watch the plan flip to a range scan — not just
read about it.

## Data features the labs rely on

The data is shaped so that every exercise has something to find. If you
modify the tables during a lab (e.g. Lab 17's `MERGE`, Lab 21's salary
updates), re-run both scripts to get back to this state.

| Feature | Where it matters |
|---|---|
| 24 customers never ordered (97, 194, 291, 388, 481–500) | Labs 09, 10 — outer joins, `NOT EXISTS`, `MINUS` |
| `Garden` category (products 101–104) never sold | Lab 09 debug — `LEFT JOIN` vs `JOIN` before `GROUP BY` |
| `Research` department (90) has no employees | Labs 00, 19 — `LEFT JOIN` headcount shows 0 |
| ~10% of orders have `employee_id IS NULL` (994 rows) | Labs 01, 09, 10, 22 — `IS NULL`, `NOT IN` NULL trap |
| Only reps 1003 and 1007 (plus unassigned orders) have cancelled orders | Lab 22 — "exclude reps with cancellation history" still leaves rows |
| Uneven countries (3 with > 90 customers) | Lab 05 — `HAVING COUNT(*) > 90` |
| Nov/Dec have 440–513 orders, other months 256–285 | Lab 05 — months with > 350 orders |
| 10 NULL emails and 5 malformed ones (customers 25, 60, 133, 208, 350) | Lab 06 — `REGEXP_LIKE` / `REGEXP_SUBSTR` |
| Customer 7 is a key account with ~700 orders | Lab 06 — `LISTAGG` genuinely overflows without `ON OVERFLOW TRUNCATE` |
| Price ties (e.g. two Electronics at 899.00, two Toys at 89.99) | Lab 08 — `RANK` vs `DENSE_RANK` |
| Salary ties (three at 10,500, two at 10,000) | Lab 08 — `ROW_NUMBER` tiebreakers |
| Products priced exactly 50.00, 150.00 and 200.00 | Labs 01, 02 — `BETWEEN` is inclusive, `CASE` boundaries |
| `Rubik's Cube`, `Clearance Tag Roll 100%_off`, `Filter Paper 100-pack for Coffee` | Lab 01 — quotes in literals, `LIKE ... ESCAPE` |
| Many customers placed two orders on the same day | Lab 07 — `ROWS` vs `RANGE`, tiebreakers |
| Employee 1001 is a Sales rep; tripling their salary exceeds 2× the Sales average, but no one does today | Labs 12, 21 — `WITH CHECK OPTION`, salary-cap triggers |
