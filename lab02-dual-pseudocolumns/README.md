# Lab 02 — DUAL & Pseudo-columns

## Concept

Oracle's `SELECT` syntax always requires a `FROM` clause — unlike Postgres
or MySQL, you can't write `SELECT 1 + 1;` on its own. `DUAL` is a tiny
built-in one-row, one-column table Oracle provides purely so you have
something to `FROM` when you just want to evaluate an expression, call a
function, or check a sequence/pseudo-column with no real table involved.

Alongside `DUAL`, Oracle exposes several **pseudo-columns** — values that
look like columns but aren't stored data: `SYSDATE`/`SYSTIMESTAMP` (server
clock), `ROWID` (a row's physical address), `ROWNUM` (a number assigned to
rows as they're fetched), and sequence values (`NEXTVAL`/`CURRVAL`) for
generating surrogate keys. These come up constantly in real Oracle code, so
knowing what they actually mean — not just how to type them — matters.

## Syntax

```sql
-- Evaluate an expression with no real table
SELECT expression FROM DUAL;

-- Pseudo-columns
SELECT SYSDATE, SYSTIMESTAMP FROM DUAL;
SELECT ROWID, ROWNUM, column1 FROM table_name WHERE ...;

-- Sequences
CREATE SEQUENCE seq_name
  START WITH 1
  INCREMENT BY 1
  NOCACHE;              -- NOCACHE keeps behavior predictable for learning; omit in production for speed

SELECT seq_name.NEXTVAL FROM DUAL;   -- advances and returns the next value
SELECT seq_name.CURRVAL FROM DUAL;   -- returns the last value THIS session fetched with NEXTVAL

-- Date formatting / parsing
TO_CHAR(date_expr, 'format_model')
TO_DATE(string_expr, 'format_model')

-- NULL handling
NVL(expr, replacement)                 -- 2 args only, same-ish type
NVL2(expr, value_if_not_null, value_if_null)
COALESCE(expr1, expr2, ..., exprN)     -- first non-NULL, any number of args
```

| Format element | Meaning | Example |
|---|---|---|
| `YYYY-MM-DD` | ISO-ish date | `2024-03-05` |
| `DD-MON-YYYY` | Oracle's classic default display | `05-MAR-2024` |
| `YYYY-MM` | year-month, useful for monthly grouping | `2024-03` |
| `HH24:MI:SS` | 24-hour time | `14:30:00` |

## Scenario

You need to (a) generate a new order ID without relying on `MAX(order_id) + 1`
(which breaks under concurrent inserts), and (b) print today's date and a
customer's signup date in a consistent, readable format for a report.

```sql
CREATE SEQUENCE orders_seq START WITH 10001 INCREMENT BY 1 NOCACHE;

SELECT orders_seq.NEXTVAL AS new_order_id FROM DUAL;

SELECT customer_name,
       TO_CHAR(signup_date, 'YYYY-MM-DD') AS signup_date_fmt,
       TO_CHAR(SYSDATE, 'YYYY-MM-DD') AS report_run_date
FROM customers
WHERE customer_id = 1;
```

## Common Pitfalls

| Mistake | Wrong | Right | Why |
|---|---|---|---|
| Trying to skip `FROM` entirely | `SELECT 1 + 1;` | `SELECT 1 + 1 FROM DUAL;` | Oracle's grammar requires a `FROM` clause. `DUAL` exists specifically to satisfy that when there's no real table to query. |
| Calling `CURRVAL` before `NEXTVAL` in a session | `SELECT orders_seq.CURRVAL FROM DUAL;` (first thing, brand-new session) | `SELECT orders_seq.NEXTVAL FROM DUAL;` first, then `CURRVAL` later in the same session | `CURRVAL` returns "the value this session last generated with `NEXTVAL`" — if `NEXTVAL` was never called in this session, Oracle raises `ORA-08002: sequence <name>.CURRVAL is not yet defined in this session`. |
| Assuming `ROWNUM` reflects sort order | `SELECT * FROM orders WHERE ROWNUM <= 5 ORDER BY order_date DESC;` expecting the 5 most recent orders | `SELECT * FROM (SELECT * FROM orders ORDER BY order_date DESC) WHERE ROWNUM <= 5;` | `ROWNUM` is assigned **as rows are fetched, before `ORDER BY` runs** — so filtering on `ROWNUM` first and sorting after gives you 5 arbitrary rows, then sorts just those 5. You must sort in a subquery first, then apply `ROWNUM` outside it. (Full ranking treatment is Lab 06.) |
| Comparing `TO_DATE` output assuming a specific display format | `WHERE hire_date = '2018-01-01'` | `WHERE hire_date = TO_DATE('2018-01-01', 'YYYY-MM-DD')` or `WHERE hire_date = DATE '2018-01-01'` | An implicit string-to-date conversion depends on the session's `NLS_DATE_FORMAT`, which varies by client/environment. Relying on it means the same query can silently misparse dates on a different machine. Always convert explicitly. |
| Using `NVL` when types differ or there are >2 fallbacks | `NVL(commission_pct, 0, 0.1)` (doesn't compile — NVL takes exactly 2 args) | `COALESCE(commission_pct, standard_rate, 0)` | `NVL` only accepts exactly two arguments. `COALESCE` accepts any number and returns the first non-NULL — it's the more general, ANSI-standard tool once you have more than one fallback. |

## Hands-on Practice

1. Create a sequence `emp_id_seq` starting at 2000, and fetch its first two `NEXTVAL`s in two separate `SELECT`s.
2. Print the current date formatted as `DD-MON-YYYY` (e.g. `05-MAR-2024`).
3. For every employee, show `commission_pct` replaced with `0` when NULL, using `NVL`.
4. For every employee, show a label: `'Has commission'` if `commission_pct` is not NULL, `'No commission'` if it is — using `NVL2`.
5. Get the 3 most recently hired employees (by `hire_date`) using `ROWNUM` correctly.

### Answers

```sql
-- 1. Sequence basics
CREATE SEQUENCE emp_id_seq START WITH 2000 INCREMENT BY 1 NOCACHE;
SELECT emp_id_seq.NEXTVAL FROM DUAL;  -- 2000
SELECT emp_id_seq.NEXTVAL FROM DUAL;  -- 2001
-- Each NEXTVAL call advances the sequence; run in order to see it increment.

-- 2. Formatted current date
SELECT TO_CHAR(SYSDATE, 'DD-MON-YYYY') AS today FROM DUAL;
-- TO_CHAR + an explicit format model avoids relying on NLS session defaults.

-- 3. NVL for a default value
SELECT employee_id, last_name, NVL(commission_pct, 0) AS commission_pct
FROM employees;
-- NVL(expr, 0) returns expr when not NULL, else 0 -- two-argument case fits NVL perfectly.

-- 4. NVL2 for a derived label
SELECT employee_id, last_name,
       NVL2(commission_pct, 'Has commission', 'No commission') AS commission_flag
FROM employees;
-- NVL2 branches on "is it NULL or not" and lets you supply a *different*
-- value for the not-null case too, which NVL alone can't do.

-- 5. Top 3 most recent hires — sort THEN limit
SELECT *
FROM (
   SELECT employee_id, last_name, hire_date
   FROM employees
   ORDER BY hire_date DESC
)
WHERE ROWNUM <= 3;
-- ORDER BY must happen in the inner query before ROWNUM filters, otherwise
-- ROWNUM <= 3 would apply to an arbitrary fetch order, not the 3 newest hires.
```

## Debug / Optimize Challenge

A colleague wants "the 5 highest-paid employees" and writes:

```sql
-- BUGGY
SELECT employee_id, last_name, salary
FROM employees
WHERE ROWNUM <= 5
ORDER BY salary DESC;
```

It runs, returns exactly 5 rows, and looks plausible — but they're not
actually the 5 highest-paid employees; they're just 5 rows Oracle happened
to fetch first, sorted afterward.

**Fix:**

```sql
SELECT employee_id, last_name, salary
FROM (
   SELECT employee_id, last_name, salary
   FROM employees
   ORDER BY salary DESC
)
WHERE ROWNUM <= 5;
```

(Oracle 12c+ alternative, and generally preferred going forward: `ORDER BY
salary DESC FETCH FIRST 5 ROWS ONLY` — no subquery needed. That syntax and
proper tie-breaking with `RANK`/`DENSE_RANK` are covered in Lab 06.)

**Why:** `ROWNUM` is assigned to rows **as they come out of the table scan,
before `ORDER BY` reorders the result set**. Filtering `WHERE ROWNUM <= 5`
first picks 5 essentially-arbitrary rows; the `ORDER BY` that runs afterward
only sorts those already-wrong 5 rows — it can't reach back and pick
different ones. The rows must be fully sorted first (in a subquery, or via
`FETCH FIRST`), and `ROWNUM`/the row limit applied on top of that sorted
result.

---

⬅️ Previous: [Lab 01 — SELECT / WHERE](../lab01-select-where/)
➡️ Next: [Lab 03 — GROUP BY & Aggregates](../lab03-group-by-aggregates/)
