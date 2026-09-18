# Lab 22 — Capstone: Diagnose and Fix a Slow Query

## Scenario

A ticket lands in your queue: *"The 'Top Customers 2024' report in the
sales dashboard is timing out. It used to work. Someone tweaked the SQL a
few months ago to 'exclude reps with cancellation history' and it's been
broken/slow ever since — please fix."*

The report is supposed to answer: **for 2024, excluding cancelled orders,
what are the top 10 customers by revenue, and when did each of them last
order?**

You pull up the query behind the report.

## The Query

```sql
SELECT c.customer_id,
       c.customer_name,
       SUM(oi.quantity * oi.unit_price) AS total_revenue,
       MAX(o.order_date) AS most_recent_order
FROM customers c
LEFT JOIN orders o ON o.customer_id = c.customer_id
JOIN order_items oi ON oi.order_id = o.order_id
WHERE TO_CHAR(o.order_date, 'YYYY') = '2024'
  AND o.status != 'CANCELLED'
  AND o.employee_id NOT IN (
        SELECT employee_id FROM orders WHERE status = 'CANCELLED'
      )
  AND ROWNUM <= 10
GROUP BY c.customer_id, c.customer_name
ORDER BY total_revenue DESC;
```

Run it. Notice two things immediately: it's slow, and — look closely at
the result — it's also *wrong*, in more than one way.

## Your Task

1. Run `EXPLAIN PLAN FOR <the query>` and `SELECT * FROM
   TABLE(DBMS_XPLAN.DISPLAY)` against it. What operations show up? Is
   anything scanning more than you'd expect?
2. List every issue you can find — both performance problems and
   correctness problems. There are **four** planted here.
3. Rewrite the query so it's both correct and efficient.
4. Run `EXPLAIN PLAN` on your fixed version and compare it to the
   original. Confirm the *result set* differs too, not just the plan.

Don't read the Walkthrough until you've genuinely attempted 1-3 yourself —
the value of this lab is in the diagnosis, not the answer key.

## Walkthrough

**Bug 1 — `ROWNUM <= 10` evaluated before `ORDER BY` ([Lab 08](../lab08-ranking-rownum/))**

`ROWNUM` is assigned to rows as they're produced by the query, *before*
the final `ORDER BY` sorts them. So `WHERE ROWNUM <= 10` picks an
arbitrary 10 rows first, and *then* those 10 get sorted by revenue — it's
"sort the top 10 of whatever came out first," not "the actual top 10 by
revenue." You'd notice this by checking whether the result actually looks
sorted-then-capped versus just capped: compare it against the same query
with the `ROWNUM` filter removed and `ORDER BY total_revenue DESC` alone —
the top 10 rows won't match.

Fix: filter `ROWNUM` in an outer query wrapped *around* the already-sorted
inner query, or (cleaner, in current Oracle) use `FETCH FIRST 10 ROWS
ONLY`.

**Bug 2 — `TO_CHAR(o.order_date, 'YYYY') = '2024'` defeats the index on
`order_date` ([Lab 14](../lab14-index-access-paths/))**

Wrapping an indexed column in a function means Oracle can't use a
standard B-tree index on that column for a range scan — it has to
evaluate `TO_CHAR(...)` for *every row* first, which forces a full table
scan of `orders` (10,000 rows) even if `idx_orders_date` exists. This is
exactly what you'd catch in step 1: the plan shows `TABLE ACCESS FULL` on
`ORDERS` instead of `INDEX RANGE SCAN`.

Fix: use a **sargable** date range predicate instead —
`o.order_date >= DATE '2024-01-01' AND o.order_date < DATE '2025-01-01'`
— which the optimizer can push straight into an index range scan.

**Bug 3 — `NOT IN` against a nullable column silently returns nothing
([Lab 10](../lab10-subqueries-ctes-set-ops/))**

`orders.employee_id` is nullable (~10% of orders have no assigned rep).
The subquery `SELECT employee_id FROM orders WHERE status = 'CANCELLED'`
will include at least one `NULL` in its result set — and once a `NOT IN`
list contains `NULL`, the whole comparison becomes `UNKNOWN` for *every*
row, not just the ones that would've matched. The entire `WHERE` clause
then evaluates to false for every row, and **the query returns zero
rows** (or very close to it, if you're testing during report iteration
and simply see a suspiciously empty result). That emptiness is the
loudest signal something's wrong — a "top 10" report should basically
never legitimately return 0 rows against 10,000 orders.

Fix: either add `AND employee_id IS NOT NULL` inside the subquery to strip
the poisoning `NULL`, or — better practice generally — rewrite as `NOT
EXISTS`, which doesn't have this failure mode at all:

```sql
AND NOT EXISTS (
   SELECT 1 FROM orders o2
   WHERE o2.employee_id = o.employee_id AND o2.status = 'CANCELLED'
)
```

**Bug 4 — `LEFT JOIN` neutralized by filtering the right-hand table in
`WHERE` ([Lab 09](../lab09-joins/))**

The `LEFT JOIN` from `customers` to `orders` was presumably written so
that customers with **no** matching 2024 orders would still show up
(useful if this report is ever extended to show zero-revenue customers).
But `o.status != 'CANCELLED'` and the date filter live in the `WHERE`
clause, not the `ON` clause — for any customer with no matching order,
every `orders` column (including `o.status`) is `NULL`, and `NULL !=
'CANCELLED'` is `UNKNOWN`, not `TRUE`. `WHERE` throws those rows out. The
`LEFT JOIN` is doing nothing; it behaves exactly like an `INNER JOIN`. You
won't necessarily catch this from the *output* of a top-10-by-revenue
report (zero-revenue customers wouldn't rank in the top 10 regardless) —
you catch it by **re-reading the SQL** and asking "why is this a LEFT
JOIN if every filter on the right table lives in WHERE?" That question is
worth asking on every outer join you review, because the next person to
copy this pattern into a report that *does* need to show zero-revenue
customers will get silently wrong output with no error and no obviously
empty result to tip them off.

For *this specific report* (top 10 by revenue), the practical fix is
simpler than preserving outer-join semantics: since a customer with no
qualifying orders can never be in the top 10 by revenue, use an `INNER
JOIN` and put the filters in the `ON`/`WHERE` clause honestly — there's no
outer-join intent to preserve here. Keep the `LEFT JOIN` only if a future
version of this report genuinely needs to list zero-revenue customers.

## Fixed Query

```sql
SELECT customer_id, customer_name, total_revenue, most_recent_order
FROM (
   SELECT c.customer_id,
          c.customer_name,
          SUM(oi.quantity * oi.unit_price) AS total_revenue,
          MAX(o.order_date) AS most_recent_order
   FROM customers c
   JOIN orders o
      ON o.customer_id = c.customer_id
     AND o.order_date >= DATE '2024-01-01'
     AND o.order_date <  DATE '2025-01-01'
     AND o.status != 'CANCELLED'
   JOIN order_items oi ON oi.order_id = o.order_id
   WHERE o.employee_id IS NULL
      OR NOT EXISTS (
            SELECT 1 FROM orders o2
            WHERE o2.employee_id = o.employee_id
              AND o2.status = 'CANCELLED'
         )
   GROUP BY c.customer_id, c.customer_name
   ORDER BY total_revenue DESC
)
FETCH FIRST 10 ROWS ONLY;
```

Note the `o.employee_id IS NULL OR NOT EXISTS (...)` — orders with no
assigned rep should still count (there's no rep to have a cancellation
history), so that case is kept explicitly rather than accidentally
dropped by the `NOT EXISTS` check.

## Reflection

Answer these for yourself — there's no answer key, this is about your own
working habits:

- When someone hands you a slow query, is your first move to look at the
  execution plan, or to read the SQL top to bottom? Why that order?
- Bug 3 in this lab was loud (zero rows). Which of the four bugs would
  have been the hardest to notice if the "wrong" answer still looked
  plausible — a real number, just not the *correct* number? What would
  make you suspicious of a query that runs fine and returns a
  believable-looking, wrong result?
- This capstone planted bugs on purpose. At work, you won't get a list of
  "there are 4 issues here." What's your personal checklist going to be
  the next time you're handed an unfamiliar slow query — what do you
  check first, second, third?
- Of the six modules in this course, which one do you feel least solid
  on? That's worth another pass before you call yourself done.

---

⬅️ Previous: [Lab 21 — Triggers](../lab21-triggers/)
➡️ Next: none — you've completed the course. Consider [Oracle Live SQL's tutorials](https://livesql.oracle.com) or your company's actual schema next.
