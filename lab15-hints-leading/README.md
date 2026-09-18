# Lab 15 — Optimizer Hints: LEADING, USE_NL/USE_HASH, INDEX, FULL

## Concept

Hints are directives embedded in a SQL comment that override the
cost-based optimizer's own decision for a specific aspect of the plan —
which table to start a join from, which join algorithm to use, whether to
use a particular index or force a full scan. They exist because the
optimizer, despite being right most of the time, occasionally makes a
provably worse choice than a human with domain knowledge can specify.

They are also the most misused tool in this entire course, for one
specific reason covered below: **a broken hint fails silently.**

## Syntax

```sql
SELECT /*+ HINT_NAME(args) */ column1, column2
FROM table1 a JOIN table2 b ON ...
WHERE ...;
```

The hint comment must come immediately after the `SELECT` (or `INSERT`/
`UPDATE`/`DELETE`) keyword — nowhere else. Hints reference table
**aliases**, not table names, whenever the query uses aliases.

| Hint | Effect |
|---|---|
| `LEADING(a b c)` | Forces the join order to start with table alias `a`, then join `b`, then `c` |
| `USE_NL(a b)` | Forces a nested-loops join between aliases `a` and `b` |
| `USE_HASH(a b)` | Forces a hash join between aliases `a` and `b` |
| `INDEX(table index_name)` | Forces use of a specific index for that table |
| `FULL(table)` | Forces a full table scan of that table, ignoring any index |

## Scenario

`EXPLAIN PLAN` (Lab 13) shows the optimizer starting a 3-table join from
the wrong table — say, scanning all 10,000 `orders` first instead of
starting from `customers` filtered to one country (500 rows, further
filtered). You believe you know the better join order. Rather than
restructure the query and hope the optimizer agrees, you can pin the join
order directly with `LEADING` — and then prove with `EXPLAIN PLAN` whether
your instinct actually produced a lower cost.

## Common Pitfalls

**1. A broken hint produces no error — it's just silently ignored**

```sql
-- WRONG: typo'd alias ("ord" doesn't exist — the alias is "o") — NO ERROR,
-- the hint is silently treated as a plain comment and ignored
SELECT /*+ LEADING(ord c) */ o.order_id, c.customer_name
FROM orders o JOIN customers c ON c.customer_id = o.customer_id;

-- RIGHT: alias matches exactly what's used in the FROM clause
SELECT /*+ LEADING(o c) */ o.order_id, c.customer_name
FROM orders o JOIN customers c ON c.customer_id = o.customer_id;
```
*Why:* the `/*+ ... */` hint syntax is, to the parser, still just a
comment (`/* ... */`) — Oracle only recognizes the `+` after `/*` as
"this comment contains hints" and then best-effort parses hint names and
arguments inside it. An unrecognized alias, a misspelled hint name, or a
hint in the wrong position doesn't raise a syntax error; Oracle just can't
apply that hint and quietly falls back to its own plan. **Always verify a
hint worked by checking `EXPLAIN PLAN`, never assume it took effect
because the query ran without error.**

**2. Placing the hint anywhere but right after the leading keyword**

```sql
-- WRONG: hint placed after column list — ignored
SELECT o.order_id, c.customer_name /*+ USE_HASH(o c) */
FROM orders o JOIN customers c ON c.customer_id = o.customer_id;

-- RIGHT
SELECT /*+ USE_HASH(o c) */ o.order_id, c.customer_name
FROM orders o JOIN customers c ON c.customer_id = o.customer_id;
```
*Why:* Oracle only scans for hints in the comment immediately following
the statement's leading keyword. A `/*+ ... */` comment anywhere else in
the statement is just a regular comment, hints or not.

**3. Treating a hint as a permanent fix**

```sql
-- A hint that made sense when orders had 500 rows and index X was cheap...
SELECT /*+ USE_NL(o c) */ o.order_id, c.customer_name
FROM orders o JOIN customers c ON c.customer_id = o.customer_id;
```
*Why it's risky long-term:* a nested-loops join is good when the driving
row set is small. If `orders` grows from 500 rows to 5 million, a
hardcoded `USE_NL` forces Oracle to keep doing a nested loop — now the
*wrong* choice — while the unhinted cost-based optimizer would have
automatically switched to a hash join as the data grew. Hints freeze a
decision; the optimizer's own statistics-driven choice adapts. Use hints
to diagnose and to handle genuine, verified optimizer misjudgments — not
as a first resort, and re-verify them periodically as data volume changes.

## Hands-on Practice

1. Run `EXPLAIN PLAN` (unhinted) for a 3-table join across `orders`,
   `customers`, and `order_items` filtered to one country, and note the
   `Cost` and which table the plan starts from.
2. Add a `LEADING` hint that forces the join to start from `customers`
   instead, and compare the `Cost`.
3. Force the join between `orders` and `order_items` to use a hash join
   with `USE_HASH`, and check whether the plan actually changed.
4. Deliberately misspell an alias inside a `LEADING` hint, run
   `EXPLAIN PLAN`, and confirm Oracle produces no error — only a plan
   that ignores the hint.

### Answers

1.
   ```sql
   EXPLAIN PLAN FOR
   SELECT o.order_id, c.customer_name, oi.product_id
   FROM orders o
   JOIN customers c ON c.customer_id = o.customer_id
   JOIN order_items oi ON oi.order_id = o.order_id
   WHERE c.country = 'Japan';
   SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY());
   ```
   Note the `Cost` value at the top row and which table appears at the
   deepest indentation (the join's starting point).

2.
   ```sql
   EXPLAIN PLAN FOR
   SELECT /*+ LEADING(c o oi) */ o.order_id, c.customer_name, oi.product_id
   FROM orders o
   JOIN customers c ON c.customer_id = o.customer_id
   JOIN order_items oi ON oi.order_id = o.order_id
   WHERE c.country = 'Japan';
   SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY());
   ```
   If the optimizer was already starting from `customers` unhinted, cost
   should be identical (the hint just confirms what it already chose). If
   it wasn't, compare the two costs directly — this is how you prove a
   hint helped instead of assuming it did.

3.
   ```sql
   EXPLAIN PLAN FOR
   SELECT /*+ USE_HASH(o oi) */ o.order_id, oi.product_id
   FROM orders o JOIN order_items oi ON oi.order_id = o.order_id;
   SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY());
   ```
   Look for `HASH JOIN` in the `Operation` column. With no index on
   `order_items.order_id` beyond the composite PK's leading column, a
   hash join is often what the optimizer picks anyway for this size of
   join — the hint here should match the unhinted plan's choice, which is
   itself a useful confirmation exercise.

4.
   ```sql
   EXPLAIN PLAN FOR
   SELECT /*+ LEADING(cust o) */ o.order_id, c.customer_name
   FROM orders o JOIN customers c ON c.customer_id = o.customer_id;
   SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY());
   ```
   No error is raised (`cust` doesn't exist as an alias — the real alias
   is `c`). The plan reverts to whatever the optimizer would have chosen
   unhinted, proving the hint was silently dropped.

## Debug / Optimize Challenge

A teammate insists this query is hinted to avoid a full scan on `orders`,
but `EXPLAIN PLAN` still shows `TABLE ACCESS FULL`:

```sql
SELECT o.order_id, o.order_date
FROM orders o
WHERE o.customer_id = 42
/*+ FULL(o) */;
```

**The fix:**

```sql
SELECT /*+ INDEX(o idx_orders_customer) */ o.order_id, o.order_date
FROM orders o
WHERE o.customer_id = 42;
```

**Why:** two bugs stacked here. First, the hint comment is placed after
the `WHERE` clause instead of right after `SELECT`, so Oracle never even
parses it as a hint — it's a plain trailing comment, and gets ignored
exactly per pitfall #2. Second, even if it were positioned correctly,
`FULL(o)` *forces* a full scan — the opposite of what the teammate wanted;
they meant to force **index use**, which is `INDEX(o index_name)`, not
`FULL`.

---

⬅️ Previous: [Lab 14 — Index Access Paths](../lab14-index-access-paths/)
➡️ Next: [Lab 16 — Bind Variables](../lab16-bind-variables/)
