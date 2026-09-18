# Lab 12 — Views: CREATE VIEW, Updatable Views, Materialized Views

## Concept

By now you've written the same joins and filters more than once across
Module 4 — a customer joined to their orders joined to their order items,
filtered to a status, grouped a dozen ways. A **view** is that query,
saved under a name: `SELECT * FROM v_customer_order_summary` instead of
re-pasting a four-table join every time someone on the team needs it. A
regular view re-runs its underlying query every time it's selected from —
it stores no data of its own. A **materialized view** is the opposite
trade: it stores the *result* of the query as an actual table, so reading
it is fast, but that stored result can go stale until something refreshes
it.

## Syntax

```sql
CREATE [OR REPLACE] VIEW view_name AS
SELECT ...
FROM ...
[WITH READ ONLY]
[WITH CHECK OPTION];

DROP VIEW view_name;

CREATE MATERIALIZED VIEW mv_name
REFRESH [ON DEMAND | ON COMMIT] [COMPLETE | FAST]
AS
SELECT ...;

EXEC DBMS_MVIEW.REFRESH('MV_NAME');   -- for REFRESH ON DEMAND

DROP MATERIALIZED VIEW mv_name;
```

| Clause | Meaning |
|---|---|
| `WITH READ ONLY` | block all DML through this view, even if it would otherwise be updatable |
| `WITH CHECK OPTION` | block any `INSERT`/`UPDATE` through this view that would produce a row the view's own `WHERE` wouldn't select |
| `REFRESH ON DEMAND` (default) | materialized view only updates when you explicitly call `DBMS_MVIEW.REFRESH` |
| `REFRESH ON COMMIT` | materialized view updates automatically at every `COMMIT` to its base tables — convenient, but adds overhead to those commits |

## Scenario

Support keeps asking for "this customer's orders, with totals" — exactly
the kind of join worth saving once:

```sql
CREATE OR REPLACE VIEW v_customer_order_summary AS
SELECT c.customer_id, c.customer_name, o.order_id, o.order_date, o.status,
       SUM(oi.quantity * oi.unit_price) AS order_total
FROM customers c
JOIN orders o      ON o.customer_id = c.customer_id
JOIN order_items oi ON oi.order_id = o.order_id
GROUP BY c.customer_id, c.customer_name, o.order_id, o.order_date, o.status;

SELECT * FROM v_customer_order_summary WHERE customer_id = 42;
```

Separately, HR wants a simple, safely-editable window onto just the Sales
department — a single-table view, which (unlike the join view above) can
actually be updated through:

```sql
CREATE OR REPLACE VIEW v_sales_reps AS
SELECT employee_id, first_name, last_name, salary, commission_pct, department_id
FROM employees
WHERE department_id = 10
WITH CHECK OPTION;

UPDATE v_sales_reps
SET salary = salary * 1.03
WHERE employee_id = 1001;
```

And reporting wants fast daily order totals without re-scanning
`order_items` on every dashboard refresh:

```sql
CREATE MATERIALIZED VIEW mv_daily_order_totals
REFRESH ON DEMAND
AS
SELECT o.order_date, SUM(oi.quantity * oi.unit_price) AS daily_total
FROM orders o
JOIN order_items oi ON oi.order_id = o.order_id
GROUP BY o.order_date;
```

## Common Pitfalls

**1. Assuming a join view is updatable**

```sql
-- WRONG: v_customer_order_summary joins 3 tables and aggregates —
-- Oracle can't map an UPDATE on order_total back to one base row
UPDATE v_customer_order_summary SET order_total = 0 WHERE order_id = 5;
-- ORA-01732: data manipulation operation not legal on this view
```

```sql
-- RIGHT: update the base table directly, or build a single-table view
-- for the specific column you actually need to edit
UPDATE order_items SET unit_price = 0 WHERE order_id = 5;
```

*Why:* a view is only updatable through Oracle's automatic rules when
each row maps back to exactly one row in exactly one "key-preserved"
base table — no joins, aggregates, `GROUP BY`, or `DISTINCT` in the way.
`v_customer_order_summary` fails on every count. `v_sales_reps` (single
table, no aggregation) works.

**2. Forgetting `WITH CHECK OPTION`**

```sql
-- v_sales_reps defined WITHOUT WITH CHECK OPTION
UPDATE v_sales_reps SET department_id = 20 WHERE employee_id = 1001;
-- succeeds — but the row instantly vanishes from v_sales_reps' own
-- result set, since it no longer matches department_id = 10
```

```sql
-- v_sales_reps defined WITH CHECK OPTION (as in the Scenario)
UPDATE v_sales_reps SET department_id = 20 WHERE employee_id = 1001;
-- ORA-01402: view WITH CHECK OPTION where-clause violation
```

*Why:* without `WITH CHECK OPTION`, an `UPDATE` through a view is only
checked against the base table's constraints, not the view's own
`WHERE` — so you can silently update a row right out of the view you're
looking at. `WITH CHECK OPTION` makes that impossible: the update itself
is rejected instead.

**3. Assuming a materialized view is always current**

```sql
-- mv_daily_order_totals was created REFRESH ON DEMAND (the default).
-- New orders were inserted an hour ago. Nobody called REFRESH.
SELECT * FROM mv_daily_order_totals WHERE order_date = TRUNC(SYSDATE);
-- returns stale totals — silently, no error
```

```sql
-- RIGHT: refresh explicitly before relying on it, or use ON COMMIT if
-- the base tables commit infrequently enough to afford the overhead
EXEC DBMS_MVIEW.REFRESH('MV_DAILY_ORDER_TOTALS');
```

*Why:* `REFRESH ON DEMAND` is a deliberate trade — the materialized view
never slows down writes to its base tables, but reads from it can be
stale by any amount until something calls `DBMS_MVIEW.REFRESH` (often a
scheduled job). `REFRESH ON COMMIT` keeps it current automatically, at
the cost of extra work on every commit to `orders`/`order_items` — the
right choice depends on how fresh the report actually needs to be.

## Hands-on Practice

1. Create `v_customer_order_summary` as in the Scenario, and query it
   for `customer_id = 1`.
2. Create `v_sales_reps` with `WITH CHECK OPTION`, then confirm an
   `UPDATE` to `salary` succeeds and an `UPDATE` to `department_id`
   (moving the row out of Sales) is rejected.
3. Create `mv_daily_order_totals`, query it, insert a new order + order
   item dated today into the base tables, query the materialized view
   again (confirm it's unchanged), then `EXEC
   DBMS_MVIEW.REFRESH('MV_DAILY_ORDER_TOTALS')` and query it once more.
4. Try `UPDATE v_customer_order_summary SET order_total = 0 WHERE
   order_id = 5;` and confirm you get `ORA-01732`.

### Answers

```sql
-- 1
CREATE OR REPLACE VIEW v_customer_order_summary AS
SELECT c.customer_id, c.customer_name, o.order_id, o.order_date, o.status,
       SUM(oi.quantity * oi.unit_price) AS order_total
FROM customers c
JOIN orders o       ON o.customer_id = c.customer_id
JOIN order_items oi  ON oi.order_id = o.order_id
GROUP BY c.customer_id, c.customer_name, o.order_id, o.order_date, o.status;

SELECT * FROM v_customer_order_summary WHERE customer_id = 1;

-- 2
CREATE OR REPLACE VIEW v_sales_reps AS
SELECT employee_id, first_name, last_name, salary, commission_pct, department_id
FROM employees
WHERE department_id = 10
WITH CHECK OPTION;

UPDATE v_sales_reps SET salary = salary * 1.03 WHERE employee_id = 1001; -- succeeds
UPDATE v_sales_reps SET department_id = 20 WHERE employee_id = 1001;    -- ORA-01402

-- 3
CREATE MATERIALIZED VIEW mv_daily_order_totals
REFRESH ON DEMAND
AS
SELECT o.order_date, SUM(oi.quantity * oi.unit_price) AS daily_total
FROM orders o
JOIN order_items oi ON oi.order_id = o.order_id
GROUP BY o.order_date;

SELECT * FROM mv_daily_order_totals WHERE order_date = TRUNC(SYSDATE);

INSERT INTO orders (order_id, customer_id, employee_id, order_date, status)
VALUES (100001, 1, NULL, TRUNC(SYSDATE), 'PENDING');
INSERT INTO order_items (order_id, line_no, product_id, quantity, unit_price)
VALUES (100001, 1, 1, 1, 999);
COMMIT;

SELECT * FROM mv_daily_order_totals WHERE order_date = TRUNC(SYSDATE); -- still old total

EXEC DBMS_MVIEW.REFRESH('MV_DAILY_ORDER_TOTALS');

SELECT * FROM mv_daily_order_totals WHERE order_date = TRUNC(SYSDATE); -- now includes the 999

-- 4
UPDATE v_customer_order_summary SET order_total = 0 WHERE order_id = 5;
-- ORA-01732: data manipulation operation not legal on this view
```

## Debug / Optimize Challenge

A teammate built this view to let account managers quickly bump a
customer's country, and can't figure out why the `UPDATE` fails:

```sql
CREATE OR REPLACE VIEW v_customer_orders AS
SELECT c.customer_id, c.customer_name, c.country, o.order_id, o.status
FROM customers c
JOIN orders o ON o.customer_id = c.customer_id;

-- BROKEN
UPDATE v_customer_orders SET country = 'Japan' WHERE customer_id = 1;
-- ORA-01779: cannot modify a column which maps to a non key-preserved table
```

**Fix:** update `customers` directly, or build a single-table view scoped
to just what account managers need to touch:

```sql
CREATE OR REPLACE VIEW v_customer_editable AS
SELECT customer_id, customer_name, email, country, signup_date
FROM customers
WITH CHECK OPTION;

UPDATE v_customer_editable SET country = 'Japan' WHERE customer_id = 1;
```

**Why:** `v_customer_orders` joins `customers` to `orders` — for Oracle to
let you update `country` through the view, every row of `orders` matching
that customer would need to map back to exactly one preserved key on
`customers`, but a join can return many `orders` rows per customer. Since
`customers` isn't "key-preserved" in this join, none of its columns are
updatable through it. A single-table view has no such ambiguity: each
view row is exactly one `customers` row, so the update is unambiguous.

---

⬅️ Previous: [Lab 11 — Hierarchical Queries (CONNECT BY)](../lab11-hierarchical-connect-by/)
➡️ Next: [Lab 13 — Reading Execution Plans](../lab13-explain-plan/)
