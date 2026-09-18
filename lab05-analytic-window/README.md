# Lab 05 — Analytic (Window) Functions

## Concept

An **analytic function** (Oracle's name for what most databases call a
"window function") computes a value across a set of rows — a *window* —
while still returning **one row of output per input row**. That's the key
difference from the aggregate functions you used in Lab 03 with `GROUP BY`:
`GROUP BY` collapses many rows into one row per group; analytic functions
keep every row and attach a computed value to each one.

The same function names — `SUM`, `AVG`, `COUNT`, `MIN`, `MAX` — do both
jobs. What makes a call analytic is the `OVER (...)` clause after it. No
`OVER` and a `GROUP BY` in the query → aggregate function, one row per
group. `OVER (...)` present → analytic function, one row per input row,
computed using a window of related rows.

This matters constantly in reporting: "this order's revenue, and also the
customer's running total to date", "this employee's salary, and also the
department average", "this product's rank within its category" — all of
these need the detail row *and* a value computed across a group of rows at
the same time. That's exactly what analytic functions are for.

## Syntax

```sql
function_name(argument, ...) OVER (
    [ PARTITION BY expr [, expr] ... ]
    [ ORDER BY expr [ASC|DESC] [NULLS FIRST|NULLS LAST] [, expr ...] ]
    [ { ROWS | RANGE } BETWEEN frame_start AND frame_end ]
)
```

| Clause | Meaning |
|---|---|
| `PARTITION BY` | Splits rows into independent groups (like `GROUP BY`, but rows aren't collapsed). Omit it and the whole result set is one partition. |
| `ORDER BY` | Orders rows *within* each partition. Required for `LAG`/`LEAD`/`RANK`/running totals; optional for a flat partition total. Changes the **default frame** — see Pitfall 1 below. |
| `ROWS`/`RANGE BETWEEN ... AND ...` | Explicitly controls which rows around the current row are included. Frame boundaries: `UNBOUNDED PRECEDING`, `N PRECEDING`, `CURRENT ROW`, `N FOLLOWING`, `UNBOUNDED FOLLOWING`. |

Common analytic functions used in this lab: `SUM`, `AVG`, `COUNT`, `MIN`,
`MAX`, `LAG(expr, offset, default)`, `LEAD(expr, offset, default)`,
`FIRST_VALUE(expr)`, `LAST_VALUE(expr)`.

## Scenario

Sales wants a report of every order for each customer, showing the order's
own revenue *and* that customer's running total revenue up to that order,
so account managers can see momentum without opening a spreadsheet. You
also want, for each order, "how much more or less was this order than the
customer's previous one" — a classic `LAG()` use case. Both need per-row
detail plus a cross-row computation in the same result set — a job
`GROUP BY` structurally cannot do.

## Common Pitfalls

### Pitfall 1: adding `ORDER BY` silently turns a total into a running total

This is the single most common analytic-function bug. The default frame
depends on whether `ORDER BY` is present:

- **No `ORDER BY`** → default frame is the whole partition → you get the
  **partition total** repeated on every row.
- **`ORDER BY` present** → default frame becomes
  `RANGE BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW` → you get a
  **running/cumulative total**, not the full total.

```sql
-- WRONG (if the goal was "each order's revenue + the customer's grand total"):
SELECT customer_id, order_id, order_date,
       SUM(order_total) OVER (PARTITION BY customer_id ORDER BY order_date) AS customer_total
FROM order_revenue;
-- Every row gets a DIFFERENT, growing number — not the grand total you expected.

-- RIGHT — grand total per customer on every row (no ORDER BY):
SELECT customer_id, order_id, order_date,
       SUM(order_total) OVER (PARTITION BY customer_id) AS customer_total
FROM order_revenue;

-- RIGHT — if you actually wanted a running total, the first version was correct,
-- just be explicit about the frame so the next reader isn't confused:
SELECT customer_id, order_id, order_date,
       SUM(order_total) OVER (
           PARTITION BY customer_id ORDER BY order_date
           ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
       ) AS running_total
FROM order_revenue;
```

**Why it happens:** Oracle silently changes the default frame the moment
`ORDER BY` appears in the `OVER` clause. Nothing in the syntax warns you —
the query runs fine either way, it just computes a different thing.

### Pitfall 2: `ROWS` vs `RANGE` disagree when the `ORDER BY` column has ties

`ROWS BETWEEN` counts physical rows. `RANGE BETWEEN` counts *logical peer
groups* — all rows that tie on the `ORDER BY` value are treated as a single
step, and a running total under `RANGE` includes **all** rows tied with the
current row, not just up to the current physical row.

```sql
-- Two orders placed on the exact same order_date for the same customer:
-- order_id 1: order_date 2024-01-05, order_total 100
-- order_id 2: order_date 2024-01-05, order_total 50   (tied date)
-- order_id 3: order_date 2024-01-10, order_total 30

SELECT order_id, order_date, order_total,
       SUM(order_total) OVER (ORDER BY order_date
           ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS rows_total,
       SUM(order_total) OVER (ORDER BY order_date
           RANGE BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS range_total
FROM (...);

-- rows_total:  100, 150, 180   (strictly by physical row order)
-- range_total: 150, 150, 180   (both 2024-01-05 rows see the FULL tied-group sum,
--                                because RANGE treats ties as arriving "together")
```

**Why it happens:** `RANGE` frames are defined by *value*, not *position* —
if two rows have the same `ORDER BY` value, `RANGE` can't tell them apart
and includes both in each other's frame. `ROWS` is purely positional and
never has this ambiguity. When you need a deterministic running total,
prefer `ROWS` (and add a tiebreaker to `ORDER BY`, e.g. `order_date, order_id`).

### Pitfall 3: `LAST_VALUE()` returns the current row, not the last row

```sql
-- WRONG — "last_price" is NOT the last row's price, it's just the current row's price:
SELECT product_id, order_id, unit_price,
       LAST_VALUE(unit_price) OVER (PARTITION BY product_id ORDER BY order_id) AS last_price
FROM order_items;

-- RIGHT — extend the frame to the whole partition:
SELECT product_id, order_id, unit_price,
       LAST_VALUE(unit_price) OVER (
           PARTITION BY product_id ORDER BY order_id
           RANGE BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
       ) AS last_price
FROM order_items;
```

**Why it happens:** `LAST_VALUE` inherits the same default frame as
Pitfall 1 (`... AND CURRENT ROW`) whenever `ORDER BY` is present. Since the
frame's upper boundary is always "current row", `LAST_VALUE` can only ever
see up to itself — it's mathematically identical to just reading the
column directly unless you widen the frame to include the whole partition.

## Hands-on Practice

Run these against the shared schema.

1. For every order, show `order_id`, `customer_id`, `order_date`, and that
   order's total revenue (`SUM(quantity * unit_price)` from `order_items`
   for that order), alongside the customer's **grand total** revenue across
   all their orders.
2. For every order, show the customer's **running total** revenue up to and
   including that order, ordered by `order_date` (use `order_id` as a
   tiebreaker).
3. For each order (ordered by `order_date` within customer), show the
   revenue of the customer's **previous** order using `LAG`, and the
   difference between this order and the previous one.
4. For each product category, show every product's `unit_price` alongside
   the **average unit_price for that category** (analytic, not `GROUP BY`
   — every product row must still appear).
5. For each customer, find their **first** and **last** order dates using
   `FIRST_VALUE`/`LAST_VALUE` in the same query as the per-order detail
   rows (remember Pitfall 3).

### Answers

```sql
-- 1. Order revenue + customer grand total
SELECT o.order_id, o.customer_id, o.order_date,
       oi.order_revenue,
       SUM(oi.order_revenue) OVER (PARTITION BY o.customer_id) AS customer_grand_total
FROM orders o
JOIN (SELECT order_id, SUM(quantity * unit_price) AS order_revenue
      FROM order_items GROUP BY order_id) oi
  ON oi.order_id = o.order_id
ORDER BY o.customer_id, o.order_date;
-- No ORDER BY inside OVER() -> default frame is the whole partition -> true grand total.

-- 2. Running total
SELECT o.order_id, o.customer_id, o.order_date,
       oi.order_revenue,
       SUM(oi.order_revenue) OVER (
           PARTITION BY o.customer_id ORDER BY o.order_date, o.order_id
           ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
       ) AS running_total
FROM orders o
JOIN (SELECT order_id, SUM(quantity * unit_price) AS order_revenue
      FROM order_items GROUP BY order_id) oi
  ON oi.order_id = o.order_id
ORDER BY o.customer_id, o.order_date;
-- ROWS (not RANGE) + a unique tiebreaker (order_id) makes this deterministic even with tied dates.

-- 3. LAG comparison
SELECT o.order_id, o.customer_id, o.order_date, oi.order_revenue,
       LAG(oi.order_revenue) OVER (PARTITION BY o.customer_id ORDER BY o.order_date, o.order_id) AS prev_order_revenue,
       oi.order_revenue - LAG(oi.order_revenue) OVER (PARTITION BY o.customer_id ORDER BY o.order_date, o.order_id) AS delta
FROM orders o
JOIN (SELECT order_id, SUM(quantity * unit_price) AS order_revenue
      FROM order_items GROUP BY order_id) oi
  ON oi.order_id = o.order_id
ORDER BY o.customer_id, o.order_date;
-- LAG with no offset defaults to 1 row back; first order per customer gets NULL, which is correct (no previous order).

-- 4. Product price vs category average, every product row kept
SELECT product_id, product_name, category, unit_price,
       AVG(unit_price) OVER (PARTITION BY category) AS category_avg_price
FROM products
ORDER BY category, unit_price DESC;
-- AVG() OVER (PARTITION BY ...) with no ORDER BY -> one flat average per partition, on every row.

-- 5. First/last order date per customer, alongside detail rows
SELECT o.order_id, o.customer_id, o.order_date,
       FIRST_VALUE(o.order_date) OVER (
           PARTITION BY o.customer_id ORDER BY o.order_date, o.order_id
       ) AS first_order_date,
       LAST_VALUE(o.order_date) OVER (
           PARTITION BY o.customer_id ORDER BY o.order_date, o.order_id
           RANGE BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
       ) AS last_order_date
FROM orders o
ORDER BY o.customer_id, o.order_date;
-- LAST_VALUE needs the widened frame (Pitfall 3) or it just repeats order_date on every row.
```

## Debug / Optimize Challenge

This query is meant to flag orders that are more than double the
customer's **average** order size, but it's returning wrong results for
every single order:

```sql
SELECT o.order_id, o.customer_id, oi.order_revenue,
       AVG(oi.order_revenue) OVER (PARTITION BY o.customer_id ORDER BY o.order_date) AS avg_order_revenue,
       CASE WHEN oi.order_revenue > 2 * AVG(oi.order_revenue)
                 OVER (PARTITION BY o.customer_id ORDER BY o.order_date)
            THEN 'FLAG' END AS flag
FROM orders o
JOIN (SELECT order_id, SUM(quantity * unit_price) AS order_revenue
      FROM order_items GROUP BY order_id) oi
  ON oi.order_id = o.order_id;
```

**The bug:** `AVG(...) OVER (PARTITION BY o.customer_id ORDER BY o.order_date)`
has an `ORDER BY` inside the window, so — Pitfall 1 again — it's computing a
**running average up to that order**, not the customer's overall average
order size. Early orders get compared against a running average built from
almost no data, producing nonsense flags.

**The fix:** drop the `ORDER BY` from inside the `OVER` clause so the
window is the whole partition:

```sql
SELECT o.order_id, o.customer_id, oi.order_revenue,
       AVG(oi.order_revenue) OVER (PARTITION BY o.customer_id) AS avg_order_revenue,
       CASE WHEN oi.order_revenue > 2 * AVG(oi.order_revenue) OVER (PARTITION BY o.customer_id)
            THEN 'FLAG' END AS flag
FROM orders o
JOIN (SELECT order_id, SUM(quantity * unit_price) AS order_revenue
      FROM order_items GROUP BY order_id) oi
  ON oi.order_id = o.order_id;
```

Now every row is compared against the customer's true overall average, computed once per partition and reused for every row in it.

---

⬅️ Previous: [Lab 04 — LISTAGG / XMLAGG](../lab04-listagg-xmlagg/)
➡️ Next: [Lab 06 — Ranking & ROWNUM](../lab06-ranking-rownum/)
