# Lab 08 — Ranking & ROWNUM

## Concept

"Give me the top N" is one of the most common requests in reporting, and
Oracle gives you three different tools that look similar but behave
differently: the ranking analytic functions (`RANK`, `DENSE_RANK`,
`ROW_NUMBER`), and the much older pseudo-column `ROWNUM`. Understanding
exactly how `ROWNUM` is assigned — and why it interacts badly with
`ORDER BY` — is one of the most valuable, most-tested pieces of Oracle
knowledge you can have, because the wrong version *runs without error* and
just quietly returns the wrong rows.

## Syntax

```sql
-- Ranking analytic functions (built on the OVER clause from Lab 07)
RANK()       OVER ( [PARTITION BY expr,...] ORDER BY expr [ASC|DESC] )
DENSE_RANK() OVER ( [PARTITION BY expr,...] ORDER BY expr [ASC|DESC] )
ROW_NUMBER() OVER ( [PARTITION BY expr,...] ORDER BY expr [ASC|DESC] )

-- ROWNUM: a pseudo-column, not a function -- no OVER, no ORDER BY of its own
SELECT ..., ROWNUM FROM table_name WHERE ...

-- Modern (12c+) top-N syntax -- prefer this over ROWNUM for new code
SELECT ... FROM table_name
ORDER BY expr
FETCH FIRST n ROWS ONLY;          -- or: OFFSET m ROWS FETCH NEXT n ROWS ONLY
```

| Function | Ties behave as | Example over values (90, 80, 80, 70) |
|---|---|---|
| `RANK()` | same rank, **next rank skips** the gap | 1, 2, 2, 4 |
| `DENSE_RANK()` | same rank, **no gap** | 1, 2, 2, 3 |
| `ROW_NUMBER()` | always unique — ties broken arbitrarily unless you add a tiebreaker | 1, 2, 3, 4 |

## Scenario

Two requests land in the same week: "give me the top 3 highest-priced
products in each category for the catalog redesign" (ranking, per group),
and "give me the 10 highest-paid employees for a compensation review"
(simple top-N). They look like the same kind of query, but the first needs
`PARTITION BY` + a ranking function, and the second is a plain top-N where
reaching for `ROWNUM` out of habit is a well-known trap.

## Common Pitfalls

### Pitfall 1: `ROWNUM` is assigned *before* `ORDER BY` runs

```sql
-- WRONG -- looks like "top 5 highest-paid employees" but is NOT:
SELECT employee_id, last_name, salary
FROM employees
WHERE ROWNUM <= 5
ORDER BY salary DESC;
```

This runs without error and returns exactly 5 rows — which makes it
dangerous, because nothing signals the mistake. What actually happens:
Oracle assigns `ROWNUM` (1, 2, 3, 4, 5, ...) to rows **as it fetches them
from the table, before `WHERE` finishes and long before `ORDER BY` is
applied**. So `WHERE ROWNUM <= 5` grabs whatever 5 rows the engine happened
to read first (arbitrary, plan-dependent), and only *then* does `ORDER BY`
sort those same 5 rows by salary. You get the 5 highest salaries **among an
arbitrary sample**, not the 5 highest salaries overall.

**Fix 1 — wrap the ordered query in a subquery, filter `ROWNUM` in the outer query:**

```sql
SELECT employee_id, last_name, salary
FROM (
    SELECT employee_id, last_name, salary
    FROM employees
    ORDER BY salary DESC
)
WHERE ROWNUM <= 5;
```

Now the `ORDER BY` runs first (inside the subquery), and `ROWNUM` is
assigned to the *already-sorted* result, so `ROWNUM <= 5` correctly grabs
the top 5.

**Fix 2 — the modern, readable way (Oracle 12c+):**

```sql
SELECT employee_id, last_name, salary
FROM employees
ORDER BY salary DESC
FETCH FIRST 5 ROWS ONLY;
```

`FETCH FIRST` is explicitly defined to apply *after* `ORDER BY`, so there's
no ambiguity to get wrong. Prefer this for all new code.

### Pitfall 2: `WHERE ROWNUM > 1` (or any `ROWNUM` lower bound alone) always returns zero rows

```sql
-- WRONG -- intended to "skip the first row", returns NOTHING:
SELECT * FROM employees WHERE ROWNUM > 1;
```

**Why:** `ROWNUM` values are assigned incrementally, in order, starting at
1, and only to rows that pass the `WHERE` clause so far. For the very first
row Oracle evaluates, it hasn't been assigned a `ROWNUM` yet when the
condition is checked, so it's tentatively `1` — and `1 > 1` is false. That
row is rejected. But rejecting it means no row is ever assigned `ROWNUM =
1` and kept, and because assignment is sequential, no row ever gets to
`ROWNUM = 2` either (rows are only numbered *after* passing the filter,
and the filter can never pass). The result is unconditionally empty — for
every row, every time.

**Fix:** if you actually need to skip the first N rows, use `OFFSET`:

```sql
SELECT employee_id, last_name, salary
FROM employees
ORDER BY salary DESC
OFFSET 1 ROWS FETCH NEXT 10 ROWS ONLY;   -- skip the top earner, get the next 10
```

### Pitfall 3: `ROW_NUMBER()` on a non-unique `ORDER BY` is nondeterministic

```sql
-- Ambiguous -- many employees can tie on salary:
SELECT employee_id, last_name, salary,
       ROW_NUMBER() OVER (ORDER BY salary DESC) AS rn
FROM employees
WHERE ROW_NUMBER() OVER (ORDER BY salary DESC) <= 5;  -- also illegal, see below
```

(Note: this specific query wouldn't even compile — analytic functions
can't be referenced directly in `WHERE`, see the Debug Challenge below.)
Even once fixed to compile, if two employees are tied on `salary`,
`ROW_NUMBER()` assigns them different numbers based on whichever
internal row order Oracle happens to process them in — which can change
between runs or after a plan change. If a tied employee unpredictably
appears or disappears from a "top 5" report between two runs of the exact
same query, this is why.

**Fix:** add a deterministic tiebreaker column to `ORDER BY`:

```sql
ROW_NUMBER() OVER (ORDER BY salary DESC, employee_id ASC) AS rn
```

## Hands-on Practice

1. Get the 10 highest-paid employees, using `FETCH FIRST`.
2. For each product category, rank products by `unit_price` descending
   using `RANK()`, and return only the top 3 per category.
3. Repeat exercise 2 with `DENSE_RANK()` instead, on a category where at
   least two products tie on price, and explain in a comment how the
   output differs from `RANK()`.
4. List employees ordered by `salary DESC`, and for each one show its
   `ROW_NUMBER()` — then deliberately break determinism by removing any
   tiebreaker, and explain what could go wrong.
5. Get "page 2" of employees (rows 11–20) ordered by `hire_date`, using
   `OFFSET`/`FETCH`.

### Answers

```sql
-- 1. Top 10 highest-paid employees
SELECT employee_id, last_name, salary
FROM employees
ORDER BY salary DESC
FETCH FIRST 10 ROWS ONLY;
-- FETCH FIRST always applies after ORDER BY -- no ROWNUM ambiguity.

-- 2. Top 3 products per category by price, RANK
SELECT product_id, product_name, category, unit_price, rnk
FROM (
    SELECT product_id, product_name, category, unit_price,
           RANK() OVER (PARTITION BY category ORDER BY unit_price DESC) AS rnk
    FROM products
)
WHERE rnk <= 3
ORDER BY category, rnk;
-- PARTITION BY resets ranking per category; RANK() lets a 4-way tie for 1st push "4th place" to rank 5.

-- 3. Same with DENSE_RANK
SELECT product_id, product_name, category, unit_price, rnk
FROM (
    SELECT product_id, product_name, category, unit_price,
           DENSE_RANK() OVER (PARTITION BY category ORDER BY unit_price DESC) AS rnk
    FROM products
)
WHERE rnk <= 3
ORDER BY category, rnk;
-- With DENSE_RANK, a 2-way tie for 1st is followed by rank 2 (not 3), so more distinct
-- price tiers can appear within "top 3" than with RANK, which burns rank numbers on ties.

-- 4. ROW_NUMBER with and without a tiebreaker
SELECT employee_id, last_name, salary,
       ROW_NUMBER() OVER (ORDER BY salary DESC, employee_id ASC) AS rn_stable
FROM employees
ORDER BY rn_stable;
-- Deterministic: employee_id as tiebreaker means the same two salary-tied employees
-- always come out in the same order, every run.
-- Without ", employee_id ASC": still runs and still returns unique numbers, but WHICH
-- tied employee gets rn=N vs rn=N+1 is not guaranteed to stay the same across runs/plans --
-- a "top 5" report built on it could silently swap which tied employee appears.

-- 5. Page 2 (rows 11-20) by hire_date
SELECT employee_id, last_name, hire_date
FROM employees
ORDER BY hire_date, employee_id
OFFSET 10 ROWS FETCH NEXT 10 ROWS ONLY;
-- hire_date, employee_id as a composite ORDER BY guarantees a stable, repeatable page 2.
```

## Debug / Optimize Challenge

This is meant to list the 5 most recent orders per customer, but it fails
to even run:

```sql
SELECT order_id, customer_id, order_date
FROM orders
WHERE ROW_NUMBER() OVER (PARTITION BY customer_id ORDER BY order_date DESC) <= 5;
```

**The bug:** `ORA-30483: window functions are not allowed here`. Analytic
functions are computed *after* the `WHERE` clause is evaluated (they need
the row set `WHERE` produces before they can rank anything), so Oracle
doesn't allow you to reference one directly inside `WHERE` — the same
reason you can't reference a `SELECT`-list alias in `WHERE` either.

**The fix:** compute the analytic function in an inline view, then filter
in the outer query, exactly like the `ROWNUM` fix in Pitfall 1:

```sql
SELECT order_id, customer_id, order_date
FROM (
    SELECT order_id, customer_id, order_date,
           ROW_NUMBER() OVER (PARTITION BY customer_id ORDER BY order_date DESC, order_id DESC) AS rn
    FROM orders
)
WHERE rn <= 5
ORDER BY customer_id, order_date DESC;
```

The `order_id DESC` tiebreaker also fixes Pitfall 3 for customers who
placed two orders on the exact same date.

---

⬅️ Previous: [Lab 07 — Analytic (Window) Functions](../lab07-analytic-window/)
➡️ Next: [Lab 09 — Joins](../lab09-joins/)
