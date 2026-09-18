# Lab 17 — MERGE, Transactions & Locking

## Concept

Real systems rarely just `INSERT`. A nightly price feed, a CRM sync, a
batch reconciliation job — these all hand you a set of rows where *some*
already exist (need an `UPDATE`) and *some* don't (need an `INSERT`).
Doing that as a separate `UPDATE` followed by an `INSERT ... WHERE NOT
EXISTS` works, but it's two full passes over the data and two statements to
keep in sync. Oracle's `MERGE` does both in one statement — this is the
"upsert" pattern.

Transactions are the second half of this lab: `MERGE`, like any DML, only
becomes permanent when you `COMMIT`. Understanding exactly what a
`COMMIT`/`ROLLBACK` affects — and the one place Oracle silently commits
for you — is what keeps a batch job from partially applying and leaving
your data in a state nobody intended.

Locking is the third half, in practice: the moment your `MERGE`/`UPDATE`/
`DELETE` touches a row, Oracle holds a row-level lock on it until you
`COMMIT` or `ROLLBACK` — anyone else trying to change that same row has
to wait. Two sessions that lock rows in opposite orders can end up
waiting on each other forever; Oracle detects that specific case and
kills one of them for you rather than let both hang indefinitely.

## Syntax

```sql
MERGE INTO target_table t
USING source_table_or_subquery s
   ON (t.key_column = s.key_column)
WHEN MATCHED THEN
   UPDATE SET t.col1 = s.col1,
              t.col2 = s.col2
   -- optional: delete rows out of the target once they're matched & updated
   DELETE WHERE (t.some_condition)
WHEN NOT MATCHED THEN
   INSERT (t.key_column, t.col1, t.col2)
   VALUES (s.key_column, s.col1, s.col2);
```

Transaction control:

```sql
SAVEPOINT sp_name;      -- mark a point you can roll back to
ROLLBACK TO sp_name;    -- undo everything since that savepoint, keep the transaction open
COMMIT;                 -- make all changes since the last COMMIT permanent
ROLLBACK;               -- undo everything since the last COMMIT
```

Locking:

```sql
-- take an explicit row lock before changing rows, so you fail fast
-- instead of hanging if another session already holds it
SELECT * FROM table_name WHERE condition FOR UPDATE NOWAIT;
SELECT * FROM table_name WHERE condition FOR UPDATE WAIT 5;      -- wait up to 5 seconds
SELECT * FROM table_name WHERE condition FOR UPDATE SKIP LOCKED; -- skip rows already locked

-- see who's blocking whom right now
SELECT blocking_session, sid, serial#, event
FROM   v$session
WHERE  blocking_session IS NOT NULL;
```

| Clause | Runs when |
|---|---|
| `WHEN MATCHED THEN UPDATE` | source row's key matches an existing target row |
| `WHEN MATCHED ... DELETE WHERE` | after the UPDATE above, for rows also satisfying the DELETE condition |
| `WHEN NOT MATCHED THEN INSERT` | source row's key has no matching target row |

## Scenario

A supplier sends you a daily CSV of price changes, which you load into a
staging table. You need `products` to end up reflecting the new prices —
updating existing products, and (if the feed ever includes a brand-new
product_id) inserting it.

Set this up once for the lab:

```sql
CREATE TABLE product_price_staging (
   product_id  NUMBER(6),
   new_price   NUMBER(10,2)
);

INSERT INTO product_price_staging VALUES (1, 19.99);
INSERT INTO product_price_staging VALUES (2, 249.50);
INSERT INTO product_price_staging VALUES (3, 12.00);
INSERT INTO product_price_staging VALUES (150, 39.99); -- product_id 150 doesn't exist yet
COMMIT;
```

Now merge the feed into `products`:

```sql
MERGE INTO products p
USING product_price_staging s
   ON (p.product_id = s.product_id)
WHEN MATCHED THEN
   UPDATE SET p.unit_price = s.new_price
WHEN NOT MATCHED THEN
   INSERT (product_id, product_name, category, unit_price)
   VALUES (s.product_id, 'Product ' || s.product_id, 'Uncategorized', s.new_price);

COMMIT;
```

products 1, 2, 3 get new prices; product 150 gets created.

## Common Pitfalls

**1. Duplicate keys in the source cause `ORA-30926`**

If `product_price_staging` has two rows for the same `product_id`, Oracle
can't tell which one should win — `MATCHED` is evaluated once per *source*
row, so both rows try to update the same target row in one statement, and
Oracle refuses rather than guess.

```sql
-- WRONG: staging has two rows for product_id 1
INSERT INTO product_price_staging VALUES (1, 19.99);
INSERT INTO product_price_staging VALUES (1, 21.99);
-- MERGE ... raises ORA-30926: unable to get a stable set of rows in the source tables
```

```sql
-- RIGHT: de-duplicate the source first, deciding which row wins
MERGE INTO products p
USING (
   SELECT product_id, new_price
   FROM (
      SELECT product_id, new_price,
             ROW_NUMBER() OVER (PARTITION BY product_id ORDER BY new_price DESC) AS rn
      FROM product_price_staging
   )
   WHERE rn = 1
) s
   ON (p.product_id = s.product_id)
WHEN MATCHED THEN UPDATE SET p.unit_price = s.new_price;
```

*Why:* `MERGE` requires the join between target and source to resolve to
at most one source row per target row. Duplicate source keys break that
guarantee — collapse them with `ROW_NUMBER()` (Lab 08) before merging.

**2. Assuming DDL can be rolled back with prior DML**

```sql
-- WRONG: expecting a single ROLLBACK to undo both statements
UPDATE products SET unit_price = unit_price * 1.1 WHERE category = 'Electronics';
ALTER TABLE products ADD (discontinued CHAR(1) DEFAULT 'N');
ROLLBACK; -- only the UPDATE is undone; the ALTER TABLE already committed
```

```sql
-- RIGHT: if a DDL statement must be part of an atomic change, commit or
-- verify the DML *before* running DDL, don't rely on ROLLBACK to cover both
UPDATE products SET unit_price = unit_price * 1.1 WHERE category = 'Electronics';
COMMIT; -- explicit checkpoint before the DDL
ALTER TABLE products ADD (discontinued CHAR(1) DEFAULT 'N');
```

*Why:* every DDL statement (`CREATE`, `ALTER`, `DROP`, `TRUNCATE`, ...) in
Oracle issues an implicit `COMMIT` immediately before *and* after it runs.
Any uncommitted DML sitting in your session gets committed as a side
effect — it's not undoable afterward.

**3. `SAVEPOINT` mistaken for a nested transaction**

```sql
-- WRONG: expecting COMMIT to only affect work since the SAVEPOINT
UPDATE products SET unit_price = 0 WHERE product_id = 1;
SAVEPOINT sp1;
UPDATE products SET unit_price = 0 WHERE product_id = 2;
COMMIT; -- commits BOTH updates, not just the one after sp1
```

*Why:* `COMMIT` always finalizes the entire transaction, regardless of any
savepoints inside it. Savepoints only give you a partial `ROLLBACK TO`
target — they don't scope what a `COMMIT` applies to.

**4. Blocking sessions, and the classic deadlock**

```sql
-- Session A:
UPDATE products SET unit_price = unit_price * 1.1 WHERE product_id = 1;
-- (no COMMIT yet -- the row lock on product_id = 1 is held)

-- Session B, at the same time:
UPDATE products SET unit_price = unit_price * 1.1 WHERE product_id = 1;
-- hangs, waiting for Session A's lock to release
```

```sql
-- RIGHT: fail fast instead of hanging indefinitely, if that's the
-- correct behavior for your job (a batch job usually shouldn't just hang)
SELECT * FROM products WHERE product_id = 1 FOR UPDATE NOWAIT;
-- ORA-00054: resource busy and acquire with NOWAIT specified -- handle
-- it (retry later, skip, alert) instead of blocking silently
```

If Session A and Session B each try to lock rows the *other* already
holds, in opposite order, neither can proceed — a genuine deadlock.
Oracle detects this specific cycle automatically and rolls back one
session's statement with `ORA-00060: deadlock detected while waiting for
resource`, so at least one of them can continue; the other must retry its
transaction from scratch.

*Why:* Oracle can prevent an unbounded wait in a two-party lock cycle by
detecting it, but it can't decide which side "should" win — that's still
your application's job, by catching the error and retrying.

## Hands-on Practice

1. Re-create `product_price_staging`, load 5 rows where 3 match existing
   `product_id`s and 2 don't, then `MERGE` them into `products`.
2. Extend the `MERGE` from #1 so that any product whose `new_price` in the
   staging table is exactly `0` gets **deleted** from `products` instead of
   updated (use `WHEN MATCHED ... DELETE WHERE`).
3. Start a transaction: update `products.unit_price` for category
   `'Toys'` to increase by 10%, create a `SAVEPOINT toy_bump`, then
   accidentally set every product's price to `1` with an unfiltered
   `UPDATE`. Use `ROLLBACK TO toy_bump` to undo only the mistake, then
   `COMMIT` the toy price bump.
4. Explain in one sentence (no SQL needed) why running `ALTER TABLE
   products ADD (notes VARCHAR2(200))` in the middle of the exercise above
   would make step 3's `ROLLBACK TO toy_bump` behave differently than
   expected.
5. In one session/worksheet tab, run `UPDATE products SET unit_price =
   unit_price WHERE product_id = 1;` and do **not** commit yet. In a
   second session, run `SELECT * FROM products WHERE product_id = 1 FOR
   UPDATE NOWAIT;` and confirm you get `ORA-00054` instead of hanging.
   Then `COMMIT` the first session and confirm the second session's lock
   request now succeeds immediately.

### Answers

```sql
-- 1
CREATE TABLE product_price_staging (product_id NUMBER(6), new_price NUMBER(10,2));
INSERT INTO product_price_staging VALUES (1, 9.99);
INSERT INTO product_price_staging VALUES (2, 199.00);
INSERT INTO product_price_staging VALUES (3, 5.50);
INSERT INTO product_price_staging VALUES (201, 29.99);
INSERT INTO product_price_staging VALUES (202, 14.25);
COMMIT;

MERGE INTO products p
USING product_price_staging s ON (p.product_id = s.product_id)
WHEN MATCHED THEN UPDATE SET p.unit_price = s.new_price
WHEN NOT MATCHED THEN
   INSERT (product_id, product_name, category, unit_price)
   VALUES (s.product_id, 'Product ' || s.product_id, 'Uncategorized', s.new_price);
COMMIT;
-- 3 products updated (1,2,3), 2 products inserted (201,202)
```

```sql
-- 2
MERGE INTO products p
USING product_price_staging s ON (p.product_id = s.product_id)
WHEN MATCHED THEN
   UPDATE SET p.unit_price = s.new_price
   DELETE WHERE (s.new_price = 0)
WHEN NOT MATCHED THEN
   INSERT (product_id, product_name, category, unit_price)
   VALUES (s.product_id, 'Product ' || s.product_id, 'Uncategorized', s.new_price);
-- rows with new_price = 0 are updated to 0 THEN immediately deleted in the same statement
```

```sql
-- 3
UPDATE products SET unit_price = unit_price * 1.10 WHERE category = 'Toys';
SAVEPOINT toy_bump;
UPDATE products SET unit_price = 1; -- oops, no WHERE clause
ROLLBACK TO toy_bump;   -- undoes only the unfiltered UPDATE
COMMIT;                 -- makes the Toys price bump permanent
```

```
-- 4
Because ALTER TABLE issues an implicit COMMIT. Running it between the
toy-price UPDATE and ROLLBACK TO toy_bump would commit the toy-price
change (fine) AND the unfiltered price-wipe UPDATE if it happened before
the ALTER — and ROLLBACK TO toy_bump would then raise
ORA-01086: savepoint never established in this session (or the current one)
because the implicit commit ended the transaction the savepoint belonged to.
```

```sql
-- 5 (Session 1)
UPDATE products SET unit_price = unit_price WHERE product_id = 1;
-- do not commit yet

-- (Session 2)
SELECT * FROM products WHERE product_id = 1 FOR UPDATE NOWAIT;
-- ORA-00054: resource busy and acquire with NOWAIT specified

-- (Session 1)
COMMIT;

-- (Session 2, retried)
SELECT * FROM products WHERE product_id = 1 FOR UPDATE NOWAIT;
-- succeeds immediately -- Session 1's lock was released by its COMMIT
```

## Debug / Optimize Challenge

This MERGE is meant to sync `orders.status` to `'CANCELLED'` for any order
listed in a `cancellation_feed` staging table, but it's failing:

```sql
CREATE TABLE cancellation_feed (order_id NUMBER, reason VARCHAR2(100));
INSERT INTO cancellation_feed VALUES (5, 'customer request');
INSERT INTO cancellation_feed VALUES (5, 'duplicate order');
INSERT INTO cancellation_feed VALUES (17, 'fraud check');
COMMIT;

MERGE INTO orders o
USING cancellation_feed c
   ON (o.order_id = c.order_id)
WHEN MATCHED THEN
   UPDATE SET o.status = 'CANCELLED';
-- ORA-30926: unable to get a stable set of rows in the source tables
```

**Fix:** `cancellation_feed` has two rows for `order_id = 5`, so the source
isn't guaranteed to produce one row per target match. Collapse the feed to
one row per `order_id` before merging:

```sql
MERGE INTO orders o
USING (
   SELECT DISTINCT order_id FROM cancellation_feed
) c
   ON (o.order_id = c.order_id)
WHEN MATCHED THEN
   UPDATE SET o.status = 'CANCELLED';
COMMIT;
```

If you needed to keep one specific `reason` per order (not just the
`order_id`), use `ROW_NUMBER() OVER (PARTITION BY order_id ORDER BY ...)
= 1` instead of `DISTINCT` — the same de-duplication technique from
Pitfall 1 above. The point either way: any transformation that guarantees
at most one source row per `order_id`.

---

⬅️ Previous: [Lab 16 — Bind Variables](../lab16-bind-variables/)
➡️ Next: [Lab 18 — PIVOT/UNPIVOT & JSON](../lab18-pivot-json/)
