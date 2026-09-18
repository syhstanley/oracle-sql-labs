# Lab 01 — SELECT / WHERE

## Concept

`SELECT` retrieves rows from a table; `WHERE` filters which rows come back
before any grouping or ordering happens. Everything else in SQL — joins,
aggregates, window functions — builds on top of correctly filtering and
shaping a single result set first. Oracle evaluates `WHERE` row-by-row
against the raw table data, using three-valued logic (`TRUE`/`FALSE`/`UNKNOWN`)
because of `NULL` — that third value is where almost every beginner mistake
in this lab comes from.

## Syntax

```sql
SELECT [DISTINCT] column1 [AS alias1], column2 [AS alias2], ...
FROM table_name
WHERE condition
ORDER BY column1 [ASC|DESC] [NULLS FIRST|NULLS LAST],
         column2 [ASC|DESC];
```

| Clause / operator | Meaning |
|---|---|
| `=, !=, <>, <, >, <=, >=` | comparison |
| `AND, OR, NOT` | boolean combination (AND binds tighter than OR) |
| `BETWEEN a AND b` | inclusive range |
| `IN (v1, v2, ...)` | membership test |
| `LIKE 'pattern'` | `%` = any 0+ chars, `_` = exactly 1 char |
| `LIKE ... ESCAPE 'x'` | treat the char after `x` as literal, not a wildcard |
| `IS NULL` / `IS NOT NULL` | the only valid way to test for NULL |
| `ORDER BY ... NULLS FIRST/LAST` | control where NULLs sort (Oracle default: NULLS LAST for ASC, NULLS FIRST for DESC) |

## Scenario

You're new on the team and support asks: "Which customers in Taiwan or
Japan signed up in 2024, and which sales reps don't have a manager on
file?" Both questions are pure filtering — no joins or aggregates needed
yet — and both have a NULL trap hiding in them.

```sql
SELECT customer_id, customer_name, country, signup_date
FROM customers
WHERE country IN ('Taiwan', 'Japan')
  AND signup_date >= DATE '2024-01-01'
  AND signup_date <  DATE '2025-01-01'
ORDER BY signup_date;
```

## Common Pitfalls

| Mistake | Wrong | Right | Why |
|---|---|---|---|
| Testing NULL with `=` | `SELECT * FROM employees WHERE commission_pct = NULL` | `SELECT * FROM employees WHERE commission_pct IS NULL` | `NULL = NULL` evaluates to `UNKNOWN`, not `TRUE`, in Oracle's three-valued logic. `WHERE` only keeps rows where the condition is `TRUE`, so `= NULL` silently returns **zero rows**, no error — the most dangerous kind of bug. |
| Missing `AND`/`OR` precedence | `WHERE department_id = 10 OR department_id = 20 AND salary > 8000` | `WHERE department_id = 10 OR (department_id = 20 AND salary > 8000)` | `AND` binds tighter than `OR`, so the left version actually means "dept 10 (any salary) OR (dept 20 with salary > 8000)" — probably not what you meant. Always parenthesize mixed `AND`/`OR`. |
| Forgetting `%` wraps `LIKE` | `WHERE product_name LIKE 'Pro'` | `WHERE product_name LIKE 'Pro%'` | Without wildcards, `LIKE` behaves like `=` — it only matches the exact string `'Pro'`, not anything containing it. |
| Wildcard characters in real data | `WHERE product_name LIKE '%100%_off%'` (searching for literal text `100%_off`) | `WHERE product_name LIKE '%100\%\_off%' ESCAPE '\'` | `%` and `_` are wildcards even inside data you're searching for. Without `ESCAPE`, `%` and `_` in your search term are interpreted as wildcards, not literal characters, and match far more (or different) rows than intended. |
| Assuming `ORDER BY` puts NULLs last everywhere | Relying on NULLs "always sorting last" | `ORDER BY commission_pct NULLS LAST` | Oracle's default is NULLS LAST for `ASC` but **NULLS FIRST for `DESC`** — the opposite of what most people assume. State it explicitly if it matters. |
| `DISTINCT` on the wrong columns | `SELECT DISTINCT country FROM customers, orders` (Cartesian mistake) | `SELECT DISTINCT country FROM customers` | `DISTINCT` dedupes the *entire selected row*, not one column — pulling in an unrelated table changes what counts as a duplicate and can silently multiply or dedupe wrong. |

## Hands-on Practice

1. Find every employee whose `commission_pct` is not set (i.e., not in Sales).
2. Find all orders with status `'PENDING'` or `'CANCELLED'`, ordered by `order_date` descending, most recent first.
3. Find all products priced between 50 and 150 (inclusive), in the `'Electronics'` or `'Office'` category.
4. Find all customers whose `customer_name` contains an apostrophe-free, exact single-digit suffix like `Customer 7` (not `Customer 17`, `Customer 71`, etc.) — use `LIKE` with `_`.
5. List distinct `country` values from `customers`, with `NULL` values (if any) sorted first.

### Answers

```sql
-- 1. NULL commission
SELECT employee_id, first_name, last_name, department_id
FROM employees
WHERE commission_pct IS NULL;
-- IS NULL is the only correct NULL test; `= NULL` would return 0 rows.

-- 2. Pending or cancelled orders, newest first
SELECT order_id, customer_id, order_date, status
FROM orders
WHERE status IN ('PENDING', 'CANCELLED')
ORDER BY order_date DESC;
-- IN() reads cleaner than chained OR status = 'PENDING' OR status = 'CANCELLED'.

-- 3. Price range in two categories
SELECT product_id, product_name, category, unit_price
FROM products
WHERE unit_price BETWEEN 50 AND 150
  AND category IN ('Electronics', 'Office');
-- BETWEEN is inclusive on both ends; parentheses aren't needed here since
-- there's only one AND, but IN already reads unambiguously.

-- 4. Exactly one digit after "Customer "
SELECT customer_id, customer_name
FROM customers
WHERE customer_name LIKE 'Customer _'
ORDER BY customer_id;
-- One `_` matches exactly one character, so 'Customer 7' matches but
-- 'Customer 17' (two digits) does not.

-- 5. Distinct countries, NULLs first
SELECT DISTINCT country
FROM customers
ORDER BY country NULLS FIRST;
-- Explicit NULLS FIRST removes any ambiguity about sort order, even
-- though this dataset likely has no NULL countries.
```

## Debug / Optimize Challenge

A colleague wrote this to find every order that has **no** assigned sales
rep, expecting `employee_id IS NULL` rows back:

```sql
-- BUGGY
SELECT order_id, customer_id, employee_id
FROM orders
WHERE employee_id = NULL;
```

It runs without error and returns **zero rows**, even though you know from
`orders` (10% of rows have no rep) that matches should exist.

**Fix:**

```sql
SELECT order_id, customer_id, employee_id
FROM orders
WHERE employee_id IS NULL;
```

**Why:** `employee_id = NULL` is not a valid equality test — any comparison
against `NULL` evaluates to `UNKNOWN`, which `WHERE` treats as "exclude this
row," no matter what's actually in the column. Oracle doesn't raise an error
for this, which is exactly what makes it dangerous: the query looks correct
and just quietly returns the wrong (empty) result set. `IS NULL` / `IS NOT
NULL` are the only operators that test nullness correctly.

---

⬅️ Previous: none — start at [Lab 00 — Setup](../lab00-setup/)
➡️ Next: [Lab 02 — INSERT / UPDATE / DELETE / CASE / NULLIF](../lab02-dml-basics/)
