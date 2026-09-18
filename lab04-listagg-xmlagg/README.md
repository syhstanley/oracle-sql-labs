# Lab 04 — LISTAGG & XMLAGG

## Concept

`GROUP BY` aggregates numbers down to one value per group. Sometimes what
you want to collapse per group is *text* — "give me one row per order,
with a comma-separated list of every product name in it" instead of one
row per line item. That's string aggregation: `LISTAGG` is the modern,
readable way to do it; `XMLAGG` is the older mechanism that still shows up
in legacy code and in the rare case `LISTAGG`'s length limit gets in your
way. Alongside them, Oracle's `REGEXP_*` functions let you validate,
extract, and rewrite text using regular expressions instead of chains of
`SUBSTR`/`INSTR`.

## Syntax

```sql
-- LISTAGG
LISTAGG(expr, 'delimiter' [ON OVERFLOW TRUNCATE ['marker'] [WITH|WITHOUT COUNT]])
  WITHIN GROUP (ORDER BY sort_expr)

-- XMLAGG (the pre-12.2 way to aggregate strings with no length limit)
XMLCAST(
  XMLAGG(XMLELEMENT(E, expr || ',') ORDER BY sort_expr)
  AS VARCHAR2(4000)
)
-- then RTRIM(..., ',') to drop the trailing delimiter

-- Regex functions
REGEXP_LIKE(expr, pattern [, match_option])          -- boolean test, used in WHERE
REGEXP_SUBSTR(expr, pattern [, position [, occurrence [, match_option]]])
REGEXP_REPLACE(expr, pattern, replacement [, position [, occurrence [, match_option]]])
REGEXP_COUNT(expr, pattern [, position [, match_option]])
```

| Feature | Length limit | Notes |
|---|---|---|
| `LISTAGG` | VARCHAR2 (4000 bytes, or 32767 with `MAX_STRING_SIZE=EXTENDED`) | throws by default if exceeded; `ON OVERFLOW TRUNCATE` avoids the error |
| `XMLAGG` → `XMLCAST` | same VARCHAR2 limit if you cast to VARCHAR2, but you can instead keep it as XMLTYPE (unbounded) | more verbose, but never throws a length error if you don't cast it down |

## Scenario

Customer support wants a quick lookup: given an order number, show the
product names in that order as one readable string, instead of clicking
through multiple line-item rows.

```sql
SELECT o.order_id,
       LISTAGG(p.product_name, ', ') WITHIN GROUP (ORDER BY oi.line_no) AS products
FROM   orders o
JOIN   order_items oi ON oi.order_id = o.order_id
JOIN   products p     ON p.product_id = oi.product_id
WHERE  o.order_id = 1
GROUP BY o.order_id;
```

## Common Pitfalls

### 1. `LISTAGG` blowing up on a wide group

```sql
-- WRONG (in production, once some order/customer has enough child rows)
SELECT customer_id,
       LISTAGG(product_name, ', ') WITHIN GROUP (ORDER BY product_name) AS all_products
FROM   (SELECT o.customer_id, p.product_name
        FROM orders o
        JOIN order_items oi ON oi.order_id = o.order_id
        JOIN products p ON p.product_id = oi.product_id)
GROUP BY customer_id;
```
```
ORA-01489: result of string concatenation is too long
```
This query works fine in testing with small data, then breaks in
production the moment one customer's aggregated product list crosses the
VARCHAR2 limit — a classic "worked on my machine" bug because dev/test
data rarely has a customer with hundreds of orders. Guard against it:

```sql
-- RIGHT
SELECT customer_id,
       LISTAGG(product_name, ', ' ON OVERFLOW TRUNCATE '...' WITH COUNT)
         WITHIN GROUP (ORDER BY product_name) AS all_products
FROM   (SELECT o.customer_id, p.product_name
        FROM orders o
        JOIN order_items oi ON oi.order_id = o.order_id
        JOIN products p ON p.product_id = oi.product_id)
GROUP BY customer_id;
```
`ON OVERFLOW TRUNCATE` caps the output and appends a marker instead of
erroring; `WITH COUNT` appends how many values were dropped, so you can
tell a truncated list from a complete one.

### 2. Forgetting the trailing delimiter with `XMLAGG`

```sql
-- WRONG: leaves a dangling comma
SELECT o.order_id,
       XMLCAST(XMLAGG(XMLELEMENT(E, p.product_name || ',') ORDER BY oi.line_no)
                AS VARCHAR2(4000)) AS products
FROM   orders o
JOIN   order_items oi ON oi.order_id = o.order_id
JOIN   products p     ON p.product_id = oi.product_id
GROUP BY o.order_id;
-- e.g. "Widget A,Widget B,Widget C,"  <- trailing comma
```
Every iteration appends the delimiter *after* the value, including the
last one — there's no built-in "only between elements" behavior like
`LISTAGG` has. You must trim it yourself:

```sql
-- RIGHT
SELECT o.order_id,
       RTRIM(
         XMLCAST(XMLAGG(XMLELEMENT(E, p.product_name || ',') ORDER BY oi.line_no)
                  AS VARCHAR2(4000)),
       ',') AS products
FROM   orders o
JOIN   order_items oi ON oi.order_id = o.order_id
JOIN   products p     ON p.product_id = oi.product_id
GROUP BY o.order_id;
```

### 3. `REGEXP_LIKE` with an unescaped `.` doing more than expected

```sql
-- MISLEADING: "find emails containing a literal dot before the domain"
SELECT customer_name, email FROM customers
WHERE REGEXP_LIKE(email, 'example.com');
```
In regex, `.` means "any single character," not a literal dot — this
pattern would also match `exampleXcom` if such a value existed. It
happens to look right here only because no such row exists in this data;
the bug is silent and latent, not obvious. Escape it:

```sql
-- RIGHT
SELECT customer_name, email FROM customers
WHERE REGEXP_LIKE(email, 'example\.com');
```

## Hands-on Practice

1. For order `#5000`, list its product names as one comma-separated
   string using `LISTAGG`, ordered by `line_no`.
2. Do the same as (1) but using `XMLAGG`/`XMLCAST` instead, with the
   trailing delimiter correctly trimmed.
3. For each `category`, list the names of all products in that category
   as a single string, sorted alphabetically, using `LISTAGG` with
   `ON OVERFLOW TRUNCATE` as a safety net.
4. Using `REGEXP_LIKE`, find all customers whose `email` does *not* look
   like a basic `something@something.something` pattern.
5. Using `REGEXP_SUBSTR`, extract just the domain (the part after `@`)
   from every customer's email.

### Answers

```sql
-- 1
SELECT o.order_id,
       LISTAGG(p.product_name, ', ') WITHIN GROUP (ORDER BY oi.line_no) AS products
FROM   orders o
JOIN   order_items oi ON oi.order_id = o.order_id
JOIN   products p     ON p.product_id = oi.product_id
WHERE  o.order_id = 5000
GROUP BY o.order_id;
```
Standard `LISTAGG`; `WITHIN GROUP (ORDER BY ...)` controls the order of
values inside the string, independent of any outer `ORDER BY`.

```sql
-- 2
SELECT o.order_id,
       RTRIM(
         XMLCAST(XMLAGG(XMLELEMENT(E, p.product_name || ', ') ORDER BY oi.line_no)
                  AS VARCHAR2(4000)),
       ', ') AS products
FROM   orders o
JOIN   order_items oi ON oi.order_id = o.order_id
JOIN   products p     ON p.product_id = oi.product_id
WHERE  o.order_id = 5000
GROUP BY o.order_id;
```
Same result as (1) via the older mechanism — note the explicit `RTRIM`
that `LISTAGG` doesn't need.

```sql
-- 3
SELECT category,
       LISTAGG(product_name, ', ' ON OVERFLOW TRUNCATE '...' WITH COUNT)
         WITHIN GROUP (ORDER BY product_name) AS products
FROM   products
GROUP BY category;
```
With only 100 products across 5 categories this won't actually overflow,
but adding the safety clause is a habit worth having any time the group
size isn't tightly bounded.

```sql
-- 4
SELECT customer_name, email
FROM   customers
WHERE  NOT REGEXP_LIKE(email, '^[^@]+@[^@]+\.[^@]+$');
```
`^[^@]+@[^@]+\.[^@]+$` anchors the whole string (`^`...`$`) so partial
matches don't count, and requires at least one char before `@`, one
between `@` and the dot, and one after.

```sql
-- 5
SELECT customer_name, email,
       REGEXP_SUBSTR(email, '@(.+)$', 1, 1, NULL, 1) AS domain
FROM   customers;
```
The trailing `1` selects capture group 1 (the part after `@`, via the
parentheses in the pattern) instead of the whole match.

## Debug / Optimize Challenge

A colleague wrote this to build a per-order product summary and ran it
against the full `orders` table. It works in a quick test but they're
worried about it breaking later:

```sql
SELECT o.order_id,
       LISTAGG(p.product_name, ', ') WITHIN GROUP (ORDER BY oi.line_no) AS products
FROM   orders o
JOIN   order_items oi ON oi.order_id = o.order_id
JOIN   products p     ON p.product_id = oi.product_id
GROUP BY o.order_id;
```

**The bug:** it's not broken *today* — `order_items` currently caps out at
5 lines per order, well under any VARCHAR2 limit. But there's no
`ON OVERFLOW TRUNCATE` guard, so the very first order that accumulates
enough line items (a bulk-order feature, a data migration, a bug that
lets duplicate lines in) will throw `ORA-01489` in production with no
warning today.

**Fix:**

```sql
SELECT o.order_id,
       LISTAGG(p.product_name, ', ' ON OVERFLOW TRUNCATE '...' WITH COUNT)
         WITHIN GROUP (ORDER BY oi.line_no) AS products
FROM   orders o
JOIN   order_items oi ON oi.order_id = o.order_id
JOIN   products p     ON p.product_id = oi.product_id
GROUP BY o.order_id;
```

Treat `ON OVERFLOW TRUNCATE` as the default choice for any `LISTAGG` over
a group size you don't tightly control, not something you add after the
first production incident.

---

⬅️ Previous: [Lab 03 — GROUP BY / Aggregates](../lab03-group-by-aggregates/)
➡️ Next: [Lab 05 — Analytic / Window Functions](../lab05-analytic-window/)
