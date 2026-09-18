# Lab 09 — Joins

## Concept

A join combines rows from two or more tables based on a related column.
Almost every real query you write professionally touches more than one
table — an order without its customer's name, or a product without its
category, is rarely useful on its own. Oracle supports the ANSI-standard
`JOIN ... ON` syntax (the one you should write in new code) and also the
legacy Oracle-only `(+)` outer-join operator in the `WHERE` clause (which
you will *read* constantly in existing company code, even if you never
write it yourself). Knowing both is not optional if you're maintaining a
codebase older than a few years.

The type of join you choose changes not just which rows come back, but how
many: an `INNER JOIN` only returns rows that match on both sides, while an
`OUTER JOIN` also returns unmatched rows from one (or both) sides, padded
with `NULL`s for the missing side's columns.

## Syntax

```sql
-- ANSI syntax (preferred in new code) ------------------------------
SELECT a.col, b.col
FROM   table_a a
JOIN   table_b b ON a.key = b.key;              -- INNER JOIN (JOIN alone means INNER)

SELECT a.col, b.col
FROM   table_a a
LEFT JOIN table_b b ON a.key = b.key;            -- all of A, matched rows of B (NULL if none)

SELECT a.col, b.col
FROM   table_a a
RIGHT JOIN table_b b ON a.key = b.key;           -- all of B, matched rows of A (NULL if none)

SELECT a.col, b.col
FROM   table_a a
FULL OUTER JOIN table_b b ON a.key = b.key;      -- all of A and all of B, unmatched side is NULL

SELECT a.col, b.col
FROM   table_a a
CROSS JOIN table_b b;                            -- every row of A paired with every row of B

-- self-join: alias the same table twice
SELECT e.last_name AS employee, m.last_name AS manager
FROM   employees e
JOIN   employees m ON e.manager_id = m.employee_id;

-- Legacy Oracle syntax (you will see this in old code) --------------
SELECT a.col, b.col
FROM   table_a a, table_b b
WHERE  a.key = b.key(+);          -- LEFT JOIN: (+) goes on the side that may be missing
```

| Join type | ANSI keyword | Legacy `(+)` placement |
|---|---|---|
| Inner | `JOIN` / `INNER JOIN` | plain `WHERE a.key = b.key` |
| Left outer | `LEFT [OUTER] JOIN` | `(+)` on the *right*-side table's column |
| Right outer | `RIGHT [OUTER] JOIN` | `(+)` on the *left*-side table's column |
| Full outer | `FULL [OUTER] JOIN` | not expressible with `(+)` — must use ANSI or `UNION` of two outer joins |
| Cross | `CROSS JOIN` | comma join with no `WHERE` condition at all |

## Scenario

Sales wants a report of every customer, including ones who signed up but
have never placed an order (so the team can target them with a
re-engagement email), alongside a normal report of order details joined to
customer and product names for the ones who *have* ordered. The first
needs an outer join; the second needs plain inner joins across three
tables.

## Common Pitfalls

### 1. Missing join condition → accidental Cartesian product

```sql
-- WRONG: no ON, no WHERE linking the tables
SELECT c.customer_name, o.order_id
FROM customers c, orders o;
```
This silently returns `500 * 10000 = 5,000,000` rows — every customer
paired with every order, not just their own. On this schema you'd notice
from the row count, but on a query with a `WHERE` clause that *looks*
complete but is missing just one join predicate among several tables, this
is easy to miss and just quietly inflates aggregates (e.g. `SUM` becomes
wildly too large).

```sql
-- RIGHT
SELECT c.customer_name, o.order_id
FROM customers c
JOIN orders o ON o.customer_id = c.customer_id;
```

### 2. `(+)` on both sides of the same predicate

```sql
-- WRONG
SELECT c.customer_name, o.order_id
FROM customers c, orders o
WHERE c.customer_id(+) = o.customer_id(+);
```
Raises `ORA-01468: a predicate may reference only one outer-joined table`.
Oracle's `(+)` syntax cannot express a full outer join on a single
predicate — only one side may be "optional" at a time.

```sql
-- RIGHT (use ANSI syntax for full outer joins)
SELECT c.customer_name, o.order_id
FROM customers c
FULL OUTER JOIN orders o ON o.customer_id = c.customer_id;
```

### 3. Filtering an outer-joined table in `WHERE` instead of `ON`

```sql
-- WRONG: intent is "all customers, and their COMPLETED orders if any"
SELECT c.customer_name, o.order_id, o.status
FROM customers c
LEFT JOIN orders o ON o.customer_id = c.customer_id
WHERE o.status = 'COMPLETED';
```
This silently turns the `LEFT JOIN` back into an `INNER JOIN`. A customer
with zero orders produces a row with `o.status = NULL`, and
`NULL = 'COMPLETED'` evaluates to `UNKNOWN`, so `WHERE` throws that row
away — exactly the rows the left join was supposed to preserve. No error,
just quietly wrong results.

```sql
-- RIGHT: move the filter into the join condition
SELECT c.customer_name, o.order_id, o.status
FROM customers c
LEFT JOIN orders o ON o.customer_id = c.customer_id AND o.status = 'COMPLETED';
```
Now the status filter only decides *which order rows attach*, not whether
the customer row survives at all.

## Hands-on Practice

1. List every customer who has **never** placed an order.
2. For each order, show the order id, customer name, and the sales rep's
   last name (remember `employee_id` on `orders` is nullable).
3. List every employee together with their manager's last name (use
   `'(no manager)'` for the CEO).
4. Using the legacy `(+)` syntax, reproduce exercise 1.
5. Count how many rows a `CROSS JOIN` between `departments` and `products`
   would produce, without actually running it — then verify by running it
   with `COUNT(*)`.

### Answers

```sql
-- 1. Customers with zero orders
SELECT c.customer_id, c.customer_name
FROM customers c
LEFT JOIN orders o ON o.customer_id = c.customer_id
WHERE o.order_id IS NULL;
-- Correct because IS NULL only matches customers whose LEFT JOIN found no matching order row.

-- 2. Order + customer + rep, rep may be absent
SELECT o.order_id, c.customer_name, e.last_name AS rep_last_name
FROM orders o
JOIN customers c ON c.customer_id = o.customer_id
LEFT JOIN employees e ON e.employee_id = o.employee_id;
-- LEFT JOIN on employees because o.employee_id can be NULL; an INNER JOIN here would drop those orders entirely.

-- 3. Employee + manager name
SELECT e.last_name AS employee, NVL(m.last_name, '(no manager)') AS manager
FROM employees e
LEFT JOIN employees m ON e.manager_id = m.employee_id;
-- LEFT JOIN (not INNER) because the CEO's manager_id is NULL and must still appear.

-- 4. Same as #1, legacy syntax
SELECT c.customer_id, c.customer_name
FROM customers c, orders o
WHERE c.customer_id = o.customer_id(+)
  AND o.order_id IS NULL;
-- (+) marks orders as the optional side; identical result set to the ANSI LEFT JOIN version.

-- 5. Row count of a CROSS JOIN = product of row counts
SELECT COUNT(*) FROM departments CROSS JOIN products;
-- Expect 8 * 100 = 800.
```

## Debug / Optimize Challenge

This query is supposed to show every product's category along with the
total revenue booked for that category, including categories that have
never sold a single unit. It's returning fewer categories than exist in
`products`.

```sql
-- BROKEN
SELECT p.category, SUM(oi.quantity * oi.unit_price) AS revenue
FROM products p
JOIN order_items oi ON oi.product_id = p.product_id
GROUP BY p.category;
```

**Fix:**

```sql
SELECT p.category, SUM(oi.quantity * oi.unit_price) AS revenue
FROM products p
LEFT JOIN order_items oi ON oi.product_id = p.product_id
GROUP BY p.category;
```

An `INNER JOIN` between `products` and `order_items` drops any product (and
therefore, if an entire category never sold, that category) that has no
matching order line — `SUM` over an empty group never even gets computed
because the group never exists. Switching to `LEFT JOIN` keeps every
product row; `SUM` over the resulting all-`NULL` group returns `NULL`
correctly represents "zero revenue," and can be wrapped in `NVL(..., 0)` if
a literal `0` is preferred.

---

⬅️ Previous: [Lab 08 — Ranking & ROWNUM](../lab08-ranking-rownum/)
➡️ Next: [Lab 10 — Subqueries, CTEs, Set Operators](../lab10-subqueries-ctes-set-ops/)
