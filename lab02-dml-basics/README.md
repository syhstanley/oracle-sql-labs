# Lab 02 — INSERT / UPDATE / DELETE / CASE / NULLIF

## Concept

Lab 01 only *read* data. Real work changes it: a support agent fixes a
typo'd email, a batch job cancels stale orders, a migration backfills a
column. `INSERT`, `UPDATE`, and `DELETE` are the three DML (Data
Manipulation Language) statements that do that — as opposed to DDL (`CREATE`,
`ALTER`, `DROP`, Lab 03), which changes table *structure*, not data.

`CASE` and `NULLIF` round out this lab because they show up constantly
inside the DML you just learned (and inside every `SELECT` you'll write
from here on): `CASE` lets a single statement branch its output per row,
and `NULLIF` is the cleanest way to turn "a specific value" into `NULL`
mid-expression — most often to dodge a divide-by-zero.

## Syntax

```sql
-- single row, explicit column list (always specify the columns)
INSERT INTO table_name (col1, col2, col3)
VALUES (val1, val2, val3);

-- multiple rows: Oracle has no multi-row VALUES list like some other
-- databases — either repeat INSERT, or use INSERT ALL for one round-trip
INSERT ALL
   INTO table_name (col1, col2) VALUES (v1a, v1b)
   INTO table_name (col1, col2) VALUES (v2a, v2b)
SELECT * FROM dual;

-- copy rows from a query straight into a table (no VALUES at all)
INSERT INTO table_name (col1, col2)
SELECT source_col1, source_col2 FROM other_table WHERE ...;

UPDATE table_name
SET col1 = new_value1,
    col2 = new_value2
WHERE condition;

-- UPDATE driven by a subquery per row
UPDATE table_name t
SET col1 = (SELECT x FROM other_table o WHERE o.key = t.key)
WHERE EXISTS (SELECT 1 FROM other_table o WHERE o.key = t.key);

DELETE FROM table_name WHERE condition;

TRUNCATE TABLE table_name;   -- removes ALL rows — see pitfalls below

-- CASE: simple form (equality only)
CASE column_name
   WHEN value1 THEN result1
   WHEN value2 THEN result2
   ELSE default_result
END

-- CASE: searched form (any condition, including ranges)
CASE
   WHEN condition1 THEN result1
   WHEN condition2 THEN result2
   ELSE default_result
END

NULLIF(expr1, expr2)   -- returns NULL if expr1 = expr2, else returns expr1
```

## Scenario

You're previewing `CREATE TABLE` a lab early (Lab 03 explains it properly)
just enough to get a safe sandbox — a full copy of `customers` you can
break without touching the real shared data every other lab depends on:

```sql
CREATE TABLE customers_scratch AS
SELECT * FROM customers;
```

Support asks you to fix three things in this sandbox: a customer's email
was mistyped, a duplicate test signup needs removing, and marketing wants
customers tagged into spend tiers for a report.

```sql
-- fix a typo'd email
UPDATE customers_scratch
SET email = 'jane.lin@example.com'
WHERE customer_id = 42;

-- remove a known-bad test row
DELETE FROM customers_scratch
WHERE customer_id = 501;

-- tag every real customer (not the scratch copy) into a tier, read-only
SELECT customer_id, customer_name,
       CASE
          WHEN country IN ('USA', 'Canada') THEN 'Tier 1'
          WHEN country IN ('Taiwan', 'Japan') THEN 'Tier 2'
          ELSE 'Tier 3'
       END AS region_tier
FROM customers;
```

## Common Pitfalls

| Mistake | Wrong | Right | Why |
|---|---|---|---|
| `UPDATE`/`DELETE` with no `WHERE` | `UPDATE customers_scratch SET email = 'unknown@example.com';` | `UPDATE customers_scratch SET email = 'unknown@example.com' WHERE customer_id = 42;` | With no `WHERE`, `UPDATE`/`DELETE` apply to **every row in the table**, instantly. There's no confirmation prompt in SQL. Habit: run the equivalent `SELECT ... WHERE ...` first, confirm it's the rows you expect, *then* swap `SELECT *` for the `UPDATE`/`DELETE`. |
| Skipping the column list on `INSERT` | `INSERT INTO customers_scratch VALUES (501, 'Test', 'test@x.com', 'USA', SYSDATE);` | `INSERT INTO customers_scratch (customer_id, customer_name, email, country, signup_date) VALUES (501, 'Test', 'test@x.com', 'USA', SYSDATE);` | Positional `INSERT` silently breaks (wrong values in wrong columns, or `ORA-00947: not enough values`) the day someone adds, removes, or reorders a column. An explicit column list keeps working, or fails loudly and obviously. |
| Confusing `DELETE` and `TRUNCATE` | Using `TRUNCATE TABLE customers_scratch;` expecting to `ROLLBACK` it like a mistake | `DELETE FROM customers_scratch;` (then you *can* `ROLLBACK`) | `TRUNCATE` is DDL under the hood — it issues an implicit `COMMIT` and cannot be rolled back once run. It's also faster and resets the table's high-water mark, which is exactly why it's the wrong tool when you might need to change your mind. |
| Simple `CASE` for a range test | `CASE unit_price WHEN unit_price > 100 THEN 'expensive' END` | `CASE WHEN unit_price > 100 THEN 'expensive' END` | Simple `CASE` only ever tests **equality** against the leading expression — `WHEN unit_price > 100` is comparing `unit_price = (unit_price > 100)`, not a range test, and either errors or silently never matches. Use the searched form (`CASE WHEN ...`) for anything beyond equality. |
| Expecting `NULLIF` to return the second value | Assuming `NULLIF(commission_pct, 0)` returns `0` when they're equal | Knowing it returns `NULL` when they're equal, and the original value otherwise | `NULLIF(a, b)` returns `NULL` if `a = b`, otherwise returns `a` — it never returns `b`. It's built for "treat this sentinel value as missing," e.g. `NULLIF(denominator, 0)` inside a division, not for substituting one value for another. |

## Hands-on Practice

1. Create `customers_scratch` as a full copy of `customers`.
2. Insert a new row into `customers_scratch` with an explicit column list
   (`customer_id` 501, any name/email/country, `signup_date` = today).
3. Update that new row's `country` to `'Taiwan'`.
4. Delete that row again, by `customer_id`, using a `WHERE` clause.
5. Without modifying any table, write a `SELECT` against `products` that
   labels each product `'Budget'` (`unit_price < 50`), `'Standard'`
   (50–200), or `'Premium'` (`> 200`) using a searched `CASE`.
6. Using `order_items`, compute `quantity / NULLIF(quantity, 0)` for every
   row as a sanity check — explain in one sentence why this particular
   expression can never actually divide by zero here, then rewrite it
   against a hypothetical `discount_pct` column where some rows *are* 0,
   to show `NULLIF` actually preventing a real `ORA-01476: divisor is
   equal to zero` error.

### Answers

```sql
-- 1
CREATE TABLE customers_scratch AS
SELECT * FROM customers;

-- 2
INSERT INTO customers_scratch (customer_id, customer_name, email, country, signup_date)
VALUES (501, 'Test Customer', 'test501@example.com', 'USA', SYSDATE);

-- 3
UPDATE customers_scratch
SET country = 'Taiwan'
WHERE customer_id = 501;

-- 4
DELETE FROM customers_scratch
WHERE customer_id = 501;

-- 5
SELECT product_id, product_name, unit_price,
       CASE
          WHEN unit_price < 50 THEN 'Budget'
          WHEN unit_price <= 200 THEN 'Standard'
          ELSE 'Premium'
       END AS price_tier
FROM products;

-- 6
SELECT order_id, line_no, quantity, quantity / NULLIF(quantity, 0) AS ratio
FROM order_items;
-- quantity/NULLIF(quantity,0) can never divide by zero here because
-- order_items.quantity is never 0 in this dataset (and NULLIF only
-- matters when the divisor CAN equal the sentinel value).

-- Hypothetical version where a discount_pct column can legitimately be 0:
-- SELECT order_id, unit_price / NULLIF(discount_pct, 0) AS price_per_pct
-- FROM order_items;
-- Without NULLIF, any row where discount_pct = 0 raises
-- ORA-01476: divisor is equal to zero. NULLIF(discount_pct, 0) turns
-- that 0 into NULL first, and dividing by NULL just yields NULL
-- (not an error) for that row.
```

## Debug / Optimize Challenge

A colleague wanted to mark one bad test order as cancelled in a scratch
copy, but ran this:

```sql
CREATE TABLE orders_scratch AS SELECT * FROM orders;

-- BUGGY
UPDATE orders_scratch
SET status = 'CANCELLED'
WHERE order_id = 5
OR customer_id = 12;
```

They expected exactly one row (`order_id = 5`) to change, but every order
placed by `customer_id = 12` also flipped to `'CANCELLED'`.

**Fix:**

```sql
UPDATE orders_scratch
SET status = 'CANCELLED'
WHERE order_id = 5;
```

**Why:** `OR customer_id = 12` isn't scoped to `order_id = 5` — it's a
second, independent condition on the whole table. The `WHERE` clause reads
as "`order_id = 5` **OR** `customer_id = 12`," matching every row that
satisfies either one, not just order 5. If the intent had genuinely been
"order 5, and also flag anything else customer 12 placed," that's still
worth writing as two conditions joined with parentheses and `AND`/`OR`
made explicit (Lab 01's precedence pitfall applies to `UPDATE`/`DELETE`
just as much as `SELECT`) — but here the fix is simply dropping the
second condition entirely. As in Lab 01: when in doubt, run the `WHERE`
clause as a `SELECT` first and count the rows before you `UPDATE`/`DELETE`.

---

⬅️ Previous: [Lab 01 — SELECT / WHERE](../lab01-select-where/)
➡️ Next: [Lab 03 — CREATE TABLE, ALTER TABLE & Constraints](../lab03-ddl-constraints/)
