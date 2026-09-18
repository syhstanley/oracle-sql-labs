# Shared Schema Reference

Every lab in this course uses the same six tables. Run the two scripts here
**once**, in order, before starting Lab 01 (Lab 00 walks you through this):

1. `01_create_tables.sql` — creates the tables, PKs, FKs, one CHECK constraint
2. `02_seed_data.sql` — loads ~8 departments, ~50 employees (3-level manager
   hierarchy), 500 customers, 100 products, 10,000 orders, ~25,000 order
   line items

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
| department_id | NUMBER(4) PK | 10, 20, 30 … 80 |
| department_name | VARCHAR2(50) | Sales, Engineering, … |
| location | VARCHAR2(50) | |

### `employees`
| Column | Type | Notes |
|---|---|---|
| employee_id | NUMBER(6) PK | 100 = CEO; 2xx = dept heads; 1xxx = ICs |
| first_name / last_name | VARCHAR2 | |
| email | VARCHAR2(60) | |
| hire_date | DATE | |
| job_title | VARCHAR2(40) | |
| salary | NUMBER(10,2) | |
| commission_pct | NUMBER(4,2) | only set for Sales reps; NULL otherwise — good for NULL-handling exercises |
| department_id | NUMBER(4) FK → departments | |
| manager_id | NUMBER(6) FK → employees | NULL only for the CEO (row 100) — the root of the hierarchy used in Lab 09 (`CONNECT BY`) |

### `customers`
| Column | Type | Notes |
|---|---|---|
| customer_id | NUMBER(6) PK | 1..500 |
| customer_name, email | VARCHAR2 | |
| country | VARCHAR2(40) | 6 distinct values — good GROUP BY cardinality |
| signup_date | DATE | |

### `products`
| Column | Type | Notes |
|---|---|---|
| product_id | NUMBER(6) PK | 1..100 |
| product_name | VARCHAR2(60) | |
| category | VARCHAR2(40) | 5 distinct values |
| unit_price | NUMBER(10,2) | |

### `orders`
| Column | Type | Notes |
|---|---|---|
| order_id | NUMBER(8) PK | 1..10000 |
| customer_id | NUMBER(6) FK → customers | **no index** initially (see Module 5) |
| employee_id | NUMBER(6) FK → employees | nullable; **no index** initially |
| order_date | DATE | spread across ~3 years; **no index** initially |
| status | VARCHAR2(20) | PENDING / SHIPPED / CANCELLED / COMPLETED |

### `order_items`
| Column | Type | Notes |
|---|---|---|
| order_id | NUMBER(8) PK part 1, FK → orders | |
| line_no | NUMBER(3) PK part 2 | 1..5 per order |
| product_id | NUMBER(6) FK → products | |
| quantity | NUMBER(5) | |
| unit_price | NUMBER(10,2) | copied at order time (denormalized on purpose — prices in `products` can drift) |

**Why no secondary indexes yet?** Modules 1–4 deliberately run against a
schema with only primary-key indexes, so when you hit Module 5 (execution
plans / index access paths) you'll *see* a full table scan on 10,000+ rows,
add an index yourself, and watch the plan flip to a range scan — not just
read about it.
