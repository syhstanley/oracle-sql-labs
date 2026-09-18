# Lab 11 — Index Access Paths

## Concept

An index is a separate, sorted structure that lets Oracle find rows
without reading the whole table — but *which* index operation the
optimizer picks depends on the predicate, the index's structure, and the
data's selectivity. Knowing the names of these operations (and reading
them in a plan) is how you tell "this query will scale" from "this query
will fall over once the table gets bigger."

Building the index is the easy part (`CREATE INDEX`). The skill is knowing
when the optimizer *will* and *won't* use it — and indexes are just as
often defeated by how the query is written as by the index not existing.

## Syntax

```sql
CREATE INDEX index_name ON table_name (column1, column2, ...);

CREATE UNIQUE INDEX index_name ON table_name (column1);

-- function-based index: indexes the RESULT of an expression, not a raw column
CREATE INDEX index_name ON table_name (UPPER(column1));

DROP INDEX index_name;
```

| Access path (seen in `DBMS_XPLAN` output) | What it means | When the optimizer picks it |
|---|---|---|
| `TABLE ACCESS FULL` | Reads every block of the table | No usable index; predicate matches a large fraction of rows; table is small enough that scanning is cheaper than the overhead of an index lookup |
| `INDEX UNIQUE SCAN` | At most one matching index entry | Equality predicate on a `UNIQUE`/`PRIMARY KEY` index |
| `INDEX RANGE SCAN` | Reads a contiguous run of index entries, then table rows | Equality/range predicate (`=`, `>`, `<`, `BETWEEN`, `LIKE 'abc%'`) on a non-unique index, or a non-unique predicate on any index |
| `INDEX SKIP SCAN` | "Skips" through each distinct value of a composite index's leading column, range-scanning within each | Predicate on a *non-leading* column of a composite index, and the leading column has few distinct values |
| `INDEX FAST FULL SCAN` | Reads the entire index, unordered, like a full scan but of the (smaller) index | Query only needs columns that are all in the index — no table access needed at all |
| `TABLE ACCESS BY INDEX ROWID` | After an index scan finds matching ROWIDs, fetches the actual row from the table | Follows any of the index scans above when the query needs columns not in the index |

## Scenario

`orders` has 10,000 rows and, on purpose, no index besides the primary key
on `order_id`. Your team's dashboard does `WHERE customer_id = :id` and
`WHERE order_date BETWEEN :start AND :end` constantly — right now, both of
those force a full table scan every single time. You're about to add the
index that fixes it, and you need to prove — with the plan, not a guess —
that it actually worked.

## Common Pitfalls

**1. Wrapping the indexed column in a function**

```sql
-- WRONG: index on order_date can't be used
SELECT * FROM orders WHERE TRUNC(order_date) = DATE '2024-01-01';

-- RIGHT: rewrite as a range so the raw column is compared directly
SELECT * FROM orders
WHERE order_date >= DATE '2024-01-01' AND order_date < DATE '2024-01-02';

-- RIGHT (alternative): index the expression itself
CREATE INDEX idx_orders_trunc_date ON orders (TRUNC(order_date));
```
*Why:* a B-tree index stores the column's raw stored values, sorted. Once
you apply `TRUNC()` to the column in the predicate, Oracle would have to
apply `TRUNC()` to every row's value to compare — which means visiting
every row, i.e. a full scan. Either avoid the function on the indexed side
of the predicate, or build a function-based index on that exact
expression.

**2. Implicit datatype conversion**

```sql
-- WRONG: customer_id is NUMBER; comparing to a string forces conversion
SELECT * FROM orders WHERE customer_id = '42';

-- RIGHT: compare NUMBER to NUMBER
SELECT * FROM orders WHERE customer_id = 42;
```
*Why:* Oracle's implicit conversion rules generally convert the *column*
to match the literal's type when they differ, not the other way around
(this depends on the specific type pairing) — a NUMBER column compared to
a string literal can get wrapped in an implicit `TO_NUMBER`/`TO_CHAR`,
which, just like pitfall #1, defeats the index on that column. In the
worst case (comparing a column whose text can't cleanly convert), this
can even raise `ORA-01722: invalid number` instead of just being slow.
Always match literal types to column types explicitly.

**3. Assuming more indexes are always better**

```sql
-- Indexing every column "just in case"
CREATE INDEX idx_orders_status ON orders(status);
```
*Why it can backfire:* `status` only has 4 distinct values across 10,000
rows (~2,500 rows per value) — the optimizer will likely ignore this
index and full-scan anyway, because reading 25% of the table via
index-then-table-lookup (many scattered single-row fetches) is *more*
expensive than one sequential full scan. Meanwhile every index you create
still has to be maintained (slower `INSERT`/`UPDATE`/`DELETE`) whether or
not it's ever used for a read. Index selective columns, not every column.

## Hands-on Practice

1. Run `EXPLAIN PLAN` for `SELECT * FROM orders WHERE customer_id = 42;`
   and confirm it's `TABLE ACCESS FULL` (same as Lab 10).
2. Create an index on `orders.customer_id`, re-run the same `EXPLAIN
   PLAN`, and confirm the operation changed.
3. Create a composite index on `orders(status, order_date)` and run
   `EXPLAIN PLAN` for `SELECT * FROM orders WHERE order_date BETWEEN
   DATE '2024-06-01' AND DATE '2024-06-30';` (note: the predicate is on
   `order_date`, the *second* column). What access path do you see, and
   why is it not a plain `INDEX RANGE SCAN`?
4. Run `EXPLAIN PLAN` for `SELECT customer_id FROM orders WHERE customer_id
   = 42;` (only the indexed column, nothing else) using the index from
   step 2. Do you still see `TABLE ACCESS BY INDEX ROWID`?

### Answers

1. `TABLE ACCESS FULL` on `ORDERS` — no relevant index exists yet.

2.
   ```sql
   CREATE INDEX idx_orders_customer ON orders(customer_id);

   EXPLAIN PLAN FOR
   SELECT * FROM orders WHERE customer_id = 42;
   SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY());
   ```
   Now the plan shows `TABLE ACCESS BY INDEX ROWID` on `ORDERS` with an
   `INDEX RANGE SCAN` on `IDX_ORDERS_CUSTOMER` beneath it (range scan, not
   unique scan, because `customer_id` isn't declared unique on this
   table — one customer can have many orders).

3.
   ```sql
   CREATE INDEX idx_orders_status_date ON orders(status, order_date);

   EXPLAIN PLAN FOR
   SELECT * FROM orders
   WHERE order_date BETWEEN DATE '2024-06-01' AND DATE '2024-06-30';
   SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY());
   ```
   Because `status` (the leading column) isn't in the predicate at all,
   and it only has 4 distinct values, the optimizer *may* choose
   `INDEX SKIP SCAN` — effectively probing the index once per distinct
   `status` value and range-scanning `order_date` within each. Whether it
   actually picks skip scan vs a full table scan depends on cost
   estimates; either way, this shows why the *leading* column of a
   composite index matters — put the column your queries filter on most
   often first.

4.
   ```sql
   EXPLAIN PLAN FOR
   SELECT customer_id FROM orders WHERE customer_id = 42;
   SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY());
   ```
   No — this becomes `INDEX RANGE SCAN` with **no** `TABLE ACCESS BY INDEX
   ROWID` step at all, because every column the query needs
   (`customer_id`) is already in the index itself. Oracle never has to
   touch the table. This is why narrow, covering `SELECT` lists (instead
   of `SELECT *`) can be meaningfully faster, not just cleaner.

## Debug / Optimize Challenge

A report query is timing out. `orders.order_date` has an index
(`idx_orders_date`), but the plan still shows a full scan:

```sql
SELECT *
FROM orders
WHERE TO_CHAR(order_date, 'YYYY-MM') = '2024-06';
```

**The fix:**

```sql
SELECT *
FROM orders
WHERE order_date >= DATE '2024-06-01'
  AND order_date <  DATE '2024-07-01';
```

**Why:** `TO_CHAR(order_date, 'YYYY-MM')` wraps the indexed column in a
function, exactly like pitfall #1 above — the index on the raw
`order_date` column can't be used to satisfy a predicate on the
*transformed* value. Rewriting the month comparison as a half-open date
range compares the raw column directly, so `idx_orders_date` becomes
usable again (`INDEX RANGE SCAN` instead of `TABLE ACCESS FULL`).

---

⬅️ Previous: [Lab 10 — Reading Execution Plans](../lab10-explain-plan/)
➡️ Next: [Lab 12 — Optimizer Hints](../lab12-hints-leading/)
