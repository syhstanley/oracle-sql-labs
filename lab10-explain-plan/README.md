# Lab 10 — Reading Execution Plans

## Concept

Every SQL statement you write is a *request*, not an *instruction*. Oracle's
cost-based optimizer (CBO) decides the actual algorithm — which table to
touch first, whether to use an index, which join method to use — based on
table statistics (row counts, distinct values, data distribution). An
**execution plan** is Oracle showing you that decision before (or after) it
runs.

You cannot reason about "is this query fast" without reading its plan.
Query text tells you *what* you asked for; the plan tells you *how* Oracle
is going to get it, and that's where performance lives or dies.

## Syntax

```sql
-- 1. Ask Oracle to plan the query without running it
EXPLAIN PLAN FOR
SELECT * FROM orders WHERE customer_id = 42;

-- 2. Display the plan that was just generated
SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY());

-- 3. To see what ACTUALLY happened (not just the estimate), run the
--    query for real with a hint that turns on row-source statistics...
SELECT /*+ gather_plan_statistics */ * FROM orders WHERE customer_id = 42;

-- ...then pull the plan for that specific execution out of the cursor cache
SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY_CURSOR(NULL, NULL, 'ALLSTATS LAST'));
```

| Tool | Shows | When to use |
|---|---|---|
| `EXPLAIN PLAN` + `DBMS_XPLAN.DISPLAY` | The optimizer's *estimated* plan, without running the query | Quick check before running something expensive/destructive |
| `DBMS_XPLAN.DISPLAY_CURSOR` with `gather_plan_statistics` | The *actual* plan used, with real row counts, after running it | Diagnosing why a query that "looks fine" on paper is slow in practice |
| `SET AUTOTRACE ON` | Estimated plan + execution stats, SQL*Plus/SQLcl only | You'll see this in books and at work if your team uses SQL*Plus/SQLcl — it may not behave the same in the Live SQL browser worksheet, so this course teaches `EXPLAIN PLAN`/`DBMS_XPLAN` instead, which works identically everywhere |

## Scenario

A teammate says "the orders-by-customer lookup got slow." Before you touch
anything, you need to know: is Oracle scanning the whole 10,000-row
`orders` table for every lookup, or using an index? The execution plan is
the only place that question actually gets answered — guessing from the
SQL text alone doesn't work, because the same SQL can produce different
plans depending on indexes, statistics, and even bind variable values.

## Common Pitfalls

| Mistake | Why it's wrong |
|---|---|
| Reading a plan top-to-bottom, left-to-right, like English text | Oracle executes the *most indented* (innermost) operations **first**, then works outward and upward. The row at the very top of the output is usually the *last* thing that happens (e.g. the final SELECT), not the first. |
| Trusting `EXPLAIN PLAN`'s `Rows` column as ground truth | That's the optimizer's **estimate** (cardinality), computed from statistics — it can be badly wrong if statistics are stale or the predicate is hard to estimate. Compare E-Rows vs A-Rows via `DISPLAY_CURSOR` before trusting it. |
| Assuming a low `Cost` always means a fast query | Cost is an internal, unitless number the optimizer uses to *compare plans against each other* for the same query — it is not milliseconds, and isn't directly comparable across different queries. |
| Ignoring a big gap between `E-Rows` (estimated) and `A-Rows` (actual) | This gap is the single most common root cause of "the optimizer picked a bad plan" in real production incidents — it means the optimizer's statistics (or its assumptions about the predicate) don't match reality, so every downstream decision it made (join method, join order) was based on a wrong guess. |

## Hands-on Practice

1. Run `EXPLAIN PLAN` for `SELECT * FROM orders WHERE customer_id = 42;`
   and display it. What's the `Operation` on the row with the deepest
   indentation?
2. Run the same query for real with `/*+ gather_plan_statistics */` added,
   then pull its actual plan with `DISPLAY_CURSOR`. Compare `E-Rows` to
   `A-Rows` — are they close?
3. Run `EXPLAIN PLAN` for `SELECT COUNT(*) FROM order_items;` and display
   it. Is this a full scan or something cheaper? Why might `COUNT(*)` be
   able to avoid touching every column of every row even in a full scan?
4. Run `EXPLAIN PLAN` for a query that joins `orders` to `customers`
   (`SELECT o.order_id, c.customer_name FROM orders o JOIN customers c ON
   c.customer_id = o.customer_id WHERE c.country = 'Japan';`) and identify
   which table the plan accesses first (the most-indented table operation).

### Answers

1.
   ```sql
   EXPLAIN PLAN FOR
   SELECT * FROM orders WHERE customer_id = 42;
   SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY());
   ```
   The deepest (most indented) operation is `TABLE ACCESS FULL` on
   `ORDERS` — there's no index on `customer_id` yet (that's Lab 11), so
   Oracle has no choice but to scan every row.

2.
   ```sql
   SELECT /*+ gather_plan_statistics */ * FROM orders WHERE customer_id = 42;
   SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY_CURSOR(NULL, NULL, 'ALLSTATS LAST'));
   ```
   Expect `E-Rows` and `A-Rows` to be close here (roughly 20, since
   ~10,000 orders / 500 customers ≈ 20 orders/customer on average) —
   Oracle's default statistics are usually decent for a simple equality
   predicate on evenly distributed data like this.

3.
   ```sql
   EXPLAIN PLAN FOR SELECT COUNT(*) FROM order_items;
   SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY());
   ```
   It's still a full scan (`TABLE ACCESS FULL` or an index fast full scan
   if a suitable index exists) — but with a `SORT AGGREGATE` on top.
   `COUNT(*)` doesn't need column values, only to know a row exists, so if
   any index exists on the table, Oracle can count *index* entries
   instead of table rows (an `INDEX FAST FULL SCAN`), which is cheaper
   because the index is physically smaller than the table.

4.
   ```sql
   EXPLAIN PLAN FOR
   SELECT o.order_id, c.customer_name
   FROM orders o JOIN customers c ON c.customer_id = o.customer_id
   WHERE c.country = 'Japan';
   SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY());
   ```
   Expect the optimizer to start from `CUSTOMERS` (filtered to
   `country = 'Japan'`, roughly 1/6 of 500 rows — a smaller, more
   selective starting point) and then join out to `ORDERS`, rather than
   starting from the larger, unfiltered `ORDERS` table. This is the
   optimizer choosing join order based on selectivity — the same decision
   you'll override manually with `LEADING` in Lab 12.

## Debug / Optimize Challenge

A teammate ran this and is confused why the plan shows `TABLE ACCESS
FULL` on `orders` even though `order_id` is the primary key:

```sql
EXPLAIN PLAN FOR
SELECT * FROM orders WHERE order_id + 0 = 42;
SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY());
```

**The fix:**

```sql
EXPLAIN PLAN FOR
SELECT * FROM orders WHERE order_id = 42;
SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY());
```

**Why:** `order_id + 0` wraps the indexed column in an expression. Oracle
indexes store the *column's raw values*, not the result of arbitrary
expressions applied to them — so once `order_id` is inside `+ 0`, the
index on `order_id` can no longer be used to look up rows by that
expression, and Oracle falls back to scanning every row and evaluating
`order_id + 0 = 42` for each one. This is the same class of bug Lab 11
covers in depth with `TRUNC(order_date)`.

---

⬅️ Previous: [Lab 09 — Hierarchical Queries (CONNECT BY)](../lab09-hierarchical-connect-by/)
➡️ Next: [Lab 11 — Index Access Paths](../lab11-index-access-paths/)
