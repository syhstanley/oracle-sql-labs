# Lab 03 — GROUP BY / HAVING / Aggregates

## Concept

Aggregate functions (`COUNT`, `SUM`, `AVG`, `MAX`, `MIN`) collapse many rows
into one summary value. `GROUP BY` lets you do that collapse *per bucket*
instead of for the whole table — one row per department, per month, per
customer, whatever you group by. `HAVING` is the filter that runs *after*
grouping, on the aggregated values, because `WHERE` physically cannot see
them (it runs before grouping even happens).

This distinction — filter rows first (`WHERE`) vs filter groups after
aggregating (`HAVING`) — is the single most common source of beginner
errors in this lab, and Oracle's error messages for it are blunt but
precise once you know how to read them.

## Syntax

```sql
SELECT   group_expr1, group_expr2, agg_func(expr), ...
FROM     table
WHERE    row_filter_condition        -- applied BEFORE grouping
GROUP BY group_expr1, group_expr2    -- every non-aggregated SELECT column must be here
HAVING   agg_filter_condition        -- applied AFTER grouping
ORDER BY group_expr1;
```

| Aggregate | Behavior with NULL |
|---|---|
| `COUNT(*)` | counts rows, NULLs included |
| `COUNT(column)` | counts non-NULL values of `column` only |
| `COUNT(DISTINCT column)` | counts distinct non-NULL values |
| `SUM(column)` / `AVG(column)` | NULLs are skipped (not treated as 0) |
| `MAX(column)` / `MIN(column)` | NULLs are ignored |

## Scenario

Sales leadership wants a monthly revenue report per department, but only
for departments that shipped at least $50,000 in a given month — small or
inactive departments should be dropped from the report entirely, not shown
with tiny numbers.

```sql
SELECT d.department_name,
       TO_CHAR(o.order_date, 'YYYY-MM') AS order_month,
       SUM(oi.quantity * oi.unit_price) AS revenue
FROM   orders o
JOIN   employees  e  ON e.employee_id  = o.employee_id
JOIN   departments d ON d.department_id = e.department_id
JOIN   order_items oi ON oi.order_id    = o.order_id
WHERE  o.status <> 'CANCELLED'
GROUP BY d.department_name, TO_CHAR(o.order_date, 'YYYY-MM')
HAVING SUM(oi.quantity * oi.unit_price) >= 50000
ORDER BY order_month, d.department_name;
```

Notice `status <> 'CANCELLED'` is in `WHERE` (a per-row fact, known before
grouping), while the $50,000 threshold is in `HAVING` (a per-group fact,
only known after summing).

## Common Pitfalls

### 1. Putting an aggregate condition in `WHERE`

```sql
-- WRONG
SELECT department_id, SUM(salary)
FROM   employees
WHERE  SUM(salary) > 100000
GROUP BY department_id;
```
```
ORA-00934: group function is not allowed here
```
`WHERE` filters individual rows *before* any grouping or aggregation has
happened — at that point `SUM(salary)` doesn't exist yet for Oracle to
compare against. Move it to `HAVING`:

```sql
-- RIGHT
SELECT department_id, SUM(salary)
FROM   employees
GROUP BY department_id
HAVING SUM(salary) > 100000;
```

### 2. Selecting a non-aggregated column that isn't in `GROUP BY`

```sql
-- WRONG
SELECT department_id, job_title, SUM(salary)
FROM   employees
GROUP BY department_id;
```
```
ORA-00979: not a GROUP BY expression
```
Oracle can't know *which* `job_title` to show for a department that has
multiple job titles collapsed into one row — every selected column must
either be aggregated or listed in `GROUP BY`.

```sql
-- RIGHT
SELECT department_id, job_title, SUM(salary)
FROM   employees
GROUP BY department_id, job_title;
```

### 3. Assuming `COUNT(column)` behaves like `COUNT(*)`

```sql
-- MISLEADING: "how many employees have a commission?"
SELECT COUNT(*) FROM employees WHERE department_id = 10;
-- returns total headcount in Sales, not the number WITH a commission_pct
```
`COUNT(*)` counts rows regardless of NULLs. If you actually want "how many
Sales employees have a commission set", you need `COUNT(commission_pct)`,
which silently skips NULL values — no error, just a quietly wrong number
if you used the wrong one:

```sql
-- RIGHT
SELECT COUNT(*)              AS headcount,
       COUNT(commission_pct) AS with_commission
FROM   employees
WHERE  department_id = 10;
```

### 4. `AVG()` over NULLs instead of over all rows

```sql
-- WRONG assumption: "average commission across all Sales employees"
SELECT AVG(commission_pct) FROM employees WHERE department_id = 10;
-- silently averages only the NON-NULL rows, not all Sales employees
```
If every non-Sales employee (or a Sales employee without a commission
plan) has `commission_pct IS NULL`, `AVG` ignores those rows entirely
instead of treating them as 0 — the denominator shrinks without warning.
If you mean "treat missing commission as 0", say so explicitly:

```sql
-- RIGHT (if 0 is the intended default)
SELECT AVG(NVL(commission_pct, 0)) FROM employees WHERE department_id = 10;
```

## Hands-on Practice

1. Count how many employees are in each department, ordered from largest
   to smallest.
2. Find the average and max `unit_price` for each product `category`.
3. Find every `country` with more than 90 customers.
4. Produce total revenue (`quantity * unit_price` from `order_items`,
   joined through `orders`) per `status`, excluding `CANCELLED` orders
   entirely from the calculation.
5. Find each month (`YYYY-MM` from `order_date`) where more than 350
   orders were placed.

### Answers

```sql
-- 1
SELECT department_id, COUNT(*) AS headcount
FROM   employees
GROUP BY department_id
ORDER BY headcount DESC;
```
Plain `GROUP BY` + `COUNT(*)`, no filtering needed on either side.

```sql
-- 2
SELECT category, AVG(unit_price) AS avg_price, MAX(unit_price) AS max_price
FROM   products
GROUP BY category;
```
Two aggregates in the same query, both scoped per `category` group.

```sql
-- 3
SELECT country, COUNT(*) AS customer_count
FROM   customers
GROUP BY country
HAVING COUNT(*) > 90;
```
The threshold is on the aggregated count, so it belongs in `HAVING`, not `WHERE`.

```sql
-- 4
SELECT o.status, SUM(oi.quantity * oi.unit_price) AS revenue
FROM   orders o
JOIN   order_items oi ON oi.order_id = o.order_id
WHERE  o.status <> 'CANCELLED'
GROUP BY o.status;
```
The `CANCELLED` exclusion is a per-row fact known before aggregation, so
it's a `WHERE` clause — filtering it in `HAVING` would still compute the
sum first, which is wasted work (and here happens to give the same
result only because we're excluding a whole group, not a partial one).

```sql
-- 5
SELECT TO_CHAR(order_date, 'YYYY-MM') AS order_month, COUNT(*) AS order_count
FROM   orders
GROUP BY TO_CHAR(order_date, 'YYYY-MM')
HAVING COUNT(*) > 350
ORDER BY order_month;
```
You can `GROUP BY` an expression, not just a bare column — Oracle just
needs the exact same expression repeated in the `SELECT` list.

## Debug / Optimize Challenge

A colleague wrote this to find departments where average salary exceeds
$8,000, restricted to employees hired since 2020. It throws an error:

```sql
SELECT department_id, AVG(salary) AS avg_salary
FROM   employees
WHERE  hire_date >= DATE '2020-01-01'
  AND  AVG(salary) > 8000
GROUP BY department_id;
```

```
ORA-00934: group function is not allowed here
```

**The bug:** `AVG(salary) > 8000` is mixed into `WHERE`, but `WHERE`
executes before aggregation exists. The hire-date filter belongs in
`WHERE` (it's a per-row fact); the average-salary filter belongs in
`HAVING` (it's a per-group fact).

**Fix:**

```sql
SELECT department_id, AVG(salary) AS avg_salary
FROM   employees
WHERE  hire_date >= DATE '2020-01-01'
GROUP BY department_id
HAVING AVG(salary) > 8000;
```

Splitting the two conditions by what they actually filter — rows vs
groups — is the rule, not a style preference; Oracle enforces it with a
hard error rather than silently doing the wrong thing.

---

⬅️ Previous: [Lab 02 — DUAL / Pseudo-columns](../lab02-dual-pseudocolumns/)
➡️ Next: [Lab 04 — LISTAGG & XMLAGG](../lab04-listagg-xmlagg/)
