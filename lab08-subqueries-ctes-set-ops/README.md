# Lab 08 — Subqueries, CTEs, and Set Operators

## Concept

A subquery is a query nested inside another query — used to compute a
single value (scalar subquery), a list of values (multi-row subquery), or
to test existence (`EXISTS`). A subquery can be **correlated** (it
references a column from the outer query, so it's conceptually
re-evaluated per outer row) or **uncorrelated** (it stands alone and runs
once). A **CTE** (Common Table Expression, the `WITH` clause) names a
subquery so you can reference it — possibly more than once — later in the
statement, which makes multi-step logic readable instead of deeply nested.
**Set operators** (`UNION`, `UNION ALL`, `INTERSECT`, `MINUS`) combine the
*results* of two queries with the same column shape, rather than joining
tables on a key.

This is also where Oracle produces one of its most common real-world bugs:
`NOT IN` against a list that can contain `NULL`.

## Syntax

```sql
-- Scalar subquery (must return exactly 0 or 1 row/column)
SELECT customer_name,
       (SELECT MAX(order_date) FROM orders o WHERE o.customer_id = c.customer_id) AS last_order
FROM customers c;

-- Multi-row subquery with IN / ANY / ALL
SELECT * FROM employees WHERE department_id IN (SELECT department_id FROM departments WHERE location = 'Taipei');
SELECT * FROM employees WHERE salary > ALL (SELECT salary FROM employees WHERE department_id = 40);

-- Correlated subquery (references the outer table's alias)
SELECT * FROM orders o
WHERE EXISTS (SELECT 1 FROM order_items oi WHERE oi.order_id = o.order_id AND oi.quantity > 4);

-- EXISTS / NOT EXISTS (preferred over IN / NOT IN for existence checks)
SELECT * FROM customers c
WHERE NOT EXISTS (SELECT 1 FROM orders o WHERE o.customer_id = c.customer_id);

-- WITH clause (CTE) — one or more named subqueries
WITH category_revenue AS (
   SELECT p.category, SUM(oi.quantity * oi.unit_price) AS revenue
   FROM   order_items oi
   JOIN   products p ON p.product_id = oi.product_id
   GROUP BY p.category
),
ranked AS (
   SELECT category, revenue, RANK() OVER (ORDER BY revenue DESC) AS rnk
   FROM   category_revenue
)
SELECT * FROM ranked WHERE rnk <= 3;

-- Set operators (both sides must have the same number/type of columns)
SELECT customer_id FROM customers WHERE country = 'Taiwan'
UNION                                    -- dedupes, sorts
SELECT customer_id FROM customers WHERE signup_date < DATE '2022-01-01';

SELECT customer_id FROM customers WHERE country = 'Taiwan'
UNION ALL                                -- keeps duplicates, no sort — cheaper
SELECT customer_id FROM customers WHERE signup_date < DATE '2022-01-01';

SELECT product_id FROM order_items
INTERSECT                                -- rows in both
SELECT product_id FROM products WHERE category = 'Electronics';

SELECT customer_id FROM customers
MINUS                                    -- rows in first, not in second (Oracle's EXCEPT)
SELECT customer_id FROM orders;
```

| Operator | Removes duplicates? | Cost note |
|---|---|---|
| `UNION` | yes | implies a sort/dedup pass |
| `UNION ALL` | no | cheapest — use whenever you know the two sides can't overlap |
| `INTERSECT` | yes | |
| `MINUS` | yes | Oracle's name for standard SQL's `EXCEPT` |

## Scenario

Marketing wants a list of customers who signed up but never bought
anything (for a win-back campaign), and a separate report ranking the top
3 product categories by revenue using an intermediate "revenue per
category" calculation that's easier to read as a named step than as one
giant nested query.

## Common Pitfalls

### `NOT IN` with a NULL-able subquery silently returns nothing

```sql
-- WRONG: looks reasonable, returns ZERO rows even though several employees
-- genuinely have never been the sales rep on an order
SELECT employee_id, last_name
FROM employees
WHERE employee_id NOT IN (SELECT employee_id FROM orders);
```
`orders.employee_id` is nullable (~10% of rows are `NULL`, since not every
order has a sales rep). `NOT IN (list)` expands to
`employee_id <> v1 AND employee_id <> v2 AND ... AND employee_id <> NULL`
for every value in the list, including the `NULL`s. Any comparison against
`NULL` evaluates to `UNKNOWN`, and `AND`-ing `UNKNOWN` into a chain of
otherwise-`TRUE` comparisons makes the *whole row's* condition `UNKNOWN` —
which `WHERE` treats as "don't return this row." Since at least one `NULL`
exists in the subquery, **every** row is excluded, even ones that clearly
don't match any real value in the list. No error is raised — the query
just quietly returns the wrong (empty, or too-small) result.

```sql
-- RIGHT: NOT EXISTS never has this problem, because it checks row
-- existence rather than comparing values against a NULL-able list
SELECT employee_id, last_name
FROM employees e
WHERE NOT EXISTS (SELECT 1 FROM orders o WHERE o.employee_id = e.employee_id);

-- Alternative fix if you must keep NOT IN: filter the NULLs out yourself
SELECT employee_id, last_name
FROM employees
WHERE employee_id NOT IN (SELECT employee_id FROM orders WHERE employee_id IS NOT NULL);
```
**Rule of thumb: prefer `EXISTS`/`NOT EXISTS` over `IN`/`NOT IN` whenever
the subquery's column can contain `NULL` — which, unless you've verified
otherwise, you should assume it can.**

### Mismatched column count/type in a set operator

```sql
-- WRONG
SELECT customer_id, customer_name FROM customers
UNION
SELECT product_id FROM products;
```
Raises `ORA-01789: query block has incorrect number of result columns`.
Every branch of a set operator must return the same number of columns,
with compatible types in the same positions — the column *names* used in
the output come from the first branch only.

```sql
-- RIGHT
SELECT customer_id, customer_name FROM customers
UNION
SELECT product_id, product_name FROM products;
```

## Hands-on Practice

1. Find all customers who have never placed an order, using `NOT EXISTS`.
2. Find all employees who have never been the sales rep on any order (be
   careful of the `NOT IN` NULL trap above).
3. Using a CTE, compute total revenue per product category, then select
   only the categories whose revenue is above the average revenue across
   all categories.
4. Get a single deduplicated list of customer IDs that either are from
   `'Japan'` or placed an order in 2023 (two separate criteria, combined).
5. Find products that exist in `order_items` (i.e., have been sold at
   least once) but are **not** in the `'Toys'` category, using `MINUS`.

### Answers

```sql
-- 1.
SELECT customer_id, customer_name
FROM customers c
WHERE NOT EXISTS (SELECT 1 FROM orders o WHERE o.customer_id = c.customer_id);
-- NOT EXISTS is safe regardless of NULLs in orders.customer_id (and customer_id isn't nullable here anyway).

-- 2.
SELECT employee_id, last_name
FROM employees e
WHERE NOT EXISTS (SELECT 1 FROM orders o WHERE o.employee_id = e.employee_id);
-- NOT EXISTS avoids the NOT IN + NULL trap since orders.employee_id can be NULL.

-- 3.
WITH category_revenue AS (
   SELECT p.category, SUM(oi.quantity * oi.unit_price) AS revenue
   FROM   order_items oi
   JOIN   products p ON p.product_id = oi.product_id
   GROUP BY p.category
)
SELECT category, revenue
FROM   category_revenue
WHERE  revenue > (SELECT AVG(revenue) FROM category_revenue);
-- The CTE is referenced twice (main query + scalar subquery) without repeating the join/aggregation logic.

-- 4.
SELECT customer_id FROM customers WHERE country = 'Japan'
UNION
SELECT customer_id FROM orders WHERE order_date >= DATE '2023-01-01' AND order_date < DATE '2024-01-01';
-- UNION (not UNION ALL) because a customer could satisfy both criteria and we want them listed once.

-- 5.
SELECT DISTINCT oi.product_id FROM order_items oi
MINUS
SELECT product_id FROM products WHERE category = 'Toys';
-- MINUS removes any product_id that's also a Toys product, leaving only sold, non-Toys products.
```

## Debug / Optimize Challenge

This report is meant to list every order along with how many distinct
products were ordered elsewhere (i.e., by other orders) at a higher total
line value — a check for "orders that look small compared to typical
activity." It runs, but it's extremely slow on the full 10,000-row
`orders` table.

```sql
-- SLOW: correlated subquery re-executed once per outer row, and it's
-- itself scanning + aggregating order_items from scratch every time
SELECT o.order_id,
       (SELECT COUNT(DISTINCT oi2.product_id)
        FROM order_items oi2
        JOIN orders o2 ON o2.order_id = oi2.order_id
        WHERE o2.order_id <> o.order_id
          AND (SELECT SUM(oi3.quantity * oi3.unit_price) FROM order_items oi3 WHERE oi3.order_id = o2.order_id)
              > (SELECT SUM(oi4.quantity * oi4.unit_price) FROM order_items oi4 WHERE oi4.order_id = o.order_id)
       ) AS bigger_order_product_count
FROM orders o;
```

**Fix — pre-aggregate once with a CTE, then join:**

```sql
WITH order_totals AS (
   SELECT order_id, SUM(quantity * unit_price) AS order_value
   FROM   order_items
   GROUP BY order_id
),
order_products AS (
   SELECT order_id, COUNT(DISTINCT product_id) AS distinct_products
   FROM   order_items
   GROUP BY order_id
)
SELECT o.order_id,
       (SELECT SUM(op.distinct_products)
        FROM   order_totals t2
        JOIN   order_products op ON op.order_id = t2.order_id
        WHERE  t2.order_id <> o.order_id
          AND  t2.order_value > ot.order_value) AS bigger_order_product_count
FROM   orders o
JOIN   order_totals ot ON ot.order_id = o.order_id;
```

The original nests **three levels of correlated subqueries**, each
re-scanning and re-aggregating `order_items` for every single row of the
outer query — roughly O(n²) aggregation work over a 25,000-row table. The
fix computes each order's total value and distinct-product count **once**
each (via the CTEs), so the remaining comparison works against small,
already-aggregated result sets instead of recomputing `SUM`/`COUNT
DISTINCT` from raw rows on every iteration.

---

⬅️ Previous: [Lab 07 — Joins](../lab07-joins/)
➡️ Next: [Lab 09 — Hierarchical Queries (CONNECT BY)](../lab09-hierarchical-connect-by/)
