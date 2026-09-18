# Lab 19 — PL/SQL Basics

## Concept

Every lab so far has been plain SQL — one statement, one round-trip to the
database. PL/SQL is Oracle's procedural extension: `IF`/loops/variables
wrapped around SQL, executed *inside* the database engine. You reach for
it when a task needs logic SQL can't express in one statement, or — just
as often — when you need to process many rows without paying a network
round-trip cost for each one.

You've actually already run PL/SQL in this course: the order-items loader
in [`schema/02_seed_data.sql`](../schema/02_seed_data.sql) (the block you
ran back in Lab 00) uses exactly the `BULK COLLECT`/`FORALL` pattern this
lab teaches. Worth re-opening that file now that you know what you're
looking at.

## Syntax

```sql
DECLARE
   -- variables, using %TYPE / %ROWTYPE to track a column/row's type
   l_var1   table_name.column_name%TYPE;
   l_row    table_name%ROWTYPE;
BEGIN
   -- implicit cursor loop (the common, safe pattern for "for each row, do X")
   FOR r IN (SELECT column_name FROM table_name WHERE ...) LOOP
      -- r.column_name is available here
      NULL;
   END LOOP;

   -- bulk fetch: many rows in one round-trip instead of one row at a time
   -- (declare a collection type first, e.g. TABLE OF NUMBER INDEX BY PLS_INTEGER)
   SELECT column_name BULK COLLECT INTO l_collection FROM table_name;

   -- bulk DML: apply one DML statement per collection element, but as a
   -- single round-trip to the database instead of one round-trip per row
   FORALL i IN 1..l_collection.COUNT
      INSERT INTO other_table VALUES (l_collection(i));

EXCEPTION
   WHEN NO_DATA_FOUND THEN
      NULL; -- handle the specific, expected error
   WHEN OTHERS THEN
      RAISE; -- re-raise unless you have a real reason to handle it
END;
/
```

| Construct | Purpose |
|---|---|
| `%TYPE` | variable matches one column's datatype exactly — survives a column type change with no code edit |
| `%ROWTYPE` | variable matches an entire row's shape (one field per column) |
| `FOR r IN (SELECT ...) LOOP` | implicit cursor — opens, fetches, and closes the cursor for you |
| `BULK COLLECT INTO` | fetch a whole result set into a collection in one round-trip |
| `FORALL` | run one DML statement per collection element, batched as one round-trip |

## Scenario

You're asked to give every employee in the Sales department (`department_id
= 10`) a one-time bonus, logged into a `bonus_log` table, and the logic for
computing the bonus amount is more than a single `UPDATE` can express
cleanly (it depends on tenure and current salary band). This is a small
enough, one-off enough task that a stored procedure would be overkill — an
anonymous PL/SQL block is the right tool.

```sql
CREATE TABLE bonus_log (
   employee_id NUMBER,
   bonus_amount NUMBER(10,2),
   awarded_on DATE
);

DECLARE
   l_bonus employees.salary%TYPE;
BEGIN
   FOR r IN (SELECT employee_id, salary, hire_date
             FROM employees
             WHERE department_id = 10) LOOP
      l_bonus := CASE
                    WHEN r.hire_date < DATE '2020-01-01' THEN r.salary * 0.10
                    ELSE r.salary * 0.05
                 END;
      INSERT INTO bonus_log (employee_id, bonus_amount, awarded_on)
      VALUES (r.employee_id, l_bonus, SYSDATE);
   END LOOP;
   COMMIT;
END;
/
```

## Common Pitfalls

**1. Row-by-row DML in a loop ("slow-by-slow")**

```sql
-- WRONG: one INSERT statement executed once per iteration = one
-- round-trip to the database per row. Fine for 10 rows, painful for 10,000.
DECLARE
BEGIN
   FOR r IN (SELECT product_id, unit_price FROM products WHERE category = 'Toys') LOOP
      INSERT INTO product_price_staging (product_id, new_price)
      VALUES (r.product_id, r.unit_price * 1.05);
   END LOOP;
   COMMIT;
END;
/
```

```sql
-- RIGHT: BULK COLLECT the rows once, then FORALL the inserts as one batch
DECLARE
   TYPE t_num_tab IS TABLE OF NUMBER INDEX BY PLS_INTEGER;
   l_ids    t_num_tab;
   l_prices t_num_tab;
BEGIN
   SELECT product_id, unit_price * 1.05
     BULK COLLECT INTO l_ids, l_prices
     FROM products WHERE category = 'Toys';

   FORALL i IN 1..l_ids.COUNT
      INSERT INTO product_price_staging (product_id, new_price)
      VALUES (l_ids(i), l_prices(i));

   COMMIT;
END;
/
```

*Why:* each individual `INSERT` inside a `FOR` loop is a separate
round-trip between the PL/SQL engine and the SQL engine (yes — even
within the same database session, that context switch has a real cost).
`FORALL` sends the whole batch as one round-trip. On a handful of rows you
won't notice; on the ~25,000-row `order_items` load in
`schema/02_seed_data.sql`, row-by-row would be dramatically slower.

**2. `WHEN OTHERS THEN NULL` — silently swallowing every error**

```sql
-- WRONG: any error, for any reason, is thrown away with no trace
BEGIN
   UPDATE products SET unit_price = unit_price * 1.1 WHERE product_id = 999999;
EXCEPTION
   WHEN OTHERS THEN
      NULL; -- if this update failed for ANY reason, nobody will ever know
END;
/
```

```sql
-- RIGHT: handle the specific errors you expect; log or re-raise the rest
BEGIN
   UPDATE products SET unit_price = unit_price * 1.1 WHERE product_id = 999999;
   IF SQL%ROWCOUNT = 0 THEN
      DBMS_OUTPUT.PUT_LINE('No product with that id — nothing updated.');
   END IF;
EXCEPTION
   WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('Unexpected error: ' || SQLERRM);
      RAISE; -- still fail loudly unless you have a specific reason not to
END;
/
```

*Why:* a bare `WHEN OTHERS THEN NULL` turns every possible failure —
constraint violations, deadlocks, typos in a table name after a refactor
— into silent no-ops. The bug it was "handling" (or something far worse)
resurfaces weeks later as a data-quality ticket with zero trail back to
its cause.

**3. Forgetting `%TYPE` and hardcoding a datatype/length**

```sql
-- WRONG: hardcoded length; breaks silently (or with ORA-06502) the day
-- someone widens employees.job_title past 40 characters
DECLARE
   l_title VARCHAR2(40);
BEGIN
   SELECT job_title INTO l_title FROM employees WHERE employee_id = 100;
END;
/
```

```sql
-- RIGHT: tracks the column definition automatically
DECLARE
   l_title employees.job_title%TYPE;
BEGIN
   SELECT job_title INTO l_title FROM employees WHERE employee_id = 100;
END;
/
```

*Why:* `%TYPE` binds the variable's type to the column at compile time —
if the column's type or length ever changes, this block doesn't need to
be touched (or worse, doesn't start silently truncating data).

## Hands-on Practice

1. Write an anonymous block using `FOR r IN (SELECT ...) LOOP` that prints
   (`DBMS_OUTPUT.PUT_LINE`) each department's name and its headcount.
2. Rewrite the bonus-log example from the Scenario section, but skip any
   employee whose `commission_pct` is `NULL` — handle this with an `IF`
   inside the loop, not by changing the `WHERE` clause.
3. Using `BULK COLLECT` + `FORALL`, copy every `product_id` and
   `unit_price` from `products` where `category = 'Electronics'` into
   `product_price_staging` (from Lab 17) as `new_price = unit_price * 0.95`
   (a 5% discount).
4. Write a block that attempts `SELECT salary INTO l_salary FROM employees
   WHERE employee_id = -1` (an id that doesn't exist) and handles the
   `NO_DATA_FOUND` exception by printing a friendly message instead of
   letting the block fail.

### Answers

```sql
-- 1
BEGIN
   FOR r IN (
      SELECT d.department_name, COUNT(e.employee_id) AS headcount
      FROM departments d
      LEFT JOIN employees e ON e.department_id = d.department_id
      GROUP BY d.department_name
   ) LOOP
      DBMS_OUTPUT.PUT_LINE(r.department_name || ': ' || r.headcount);
   END LOOP;
END;
/
```

```sql
-- 2
DECLARE
   l_bonus employees.salary%TYPE;
BEGIN
   FOR r IN (SELECT employee_id, salary, hire_date, commission_pct
             FROM employees WHERE department_id = 10) LOOP
      IF r.commission_pct IS NOT NULL THEN
         l_bonus := CASE WHEN r.hire_date < DATE '2020-01-01'
                         THEN r.salary * 0.10 ELSE r.salary * 0.05 END;
         INSERT INTO bonus_log (employee_id, bonus_amount, awarded_on)
         VALUES (r.employee_id, l_bonus, SYSDATE);
      END IF;
   END LOOP;
   COMMIT;
END;
/
```

```sql
-- 3
DECLARE
   TYPE t_num_tab IS TABLE OF NUMBER INDEX BY PLS_INTEGER;
   l_ids    t_num_tab;
   l_prices t_num_tab;
BEGIN
   SELECT product_id, unit_price * 0.95
     BULK COLLECT INTO l_ids, l_prices
     FROM products WHERE category = 'Electronics';

   FORALL i IN 1..l_ids.COUNT
      INSERT INTO product_price_staging (product_id, new_price)
      VALUES (l_ids(i), l_prices(i));

   COMMIT;
END;
/
```

```sql
-- 4
DECLARE
   l_salary employees.salary%TYPE;
BEGIN
   SELECT salary INTO l_salary FROM employees WHERE employee_id = -1;
EXCEPTION
   WHEN NO_DATA_FOUND THEN
      DBMS_OUTPUT.PUT_LINE('No employee with that id.');
END;
/
```

## Debug / Optimize Challenge

This block is meant to give every employee in department 30 (Engineering)
a flat raise, logging each change — but it's both slow and silently
wrong:

```sql
-- BROKEN
BEGIN
   FOR r IN (SELECT employee_id, salary FROM employees WHERE department_id = 30) LOOP
      BEGIN
         UPDATE employees SET salary = salary * 1.05 WHERE employee_id = r.employee_id;
         INSERT INTO bonus_log (employee_id, bonus_amount, awarded_on)
         VALUES (r.employee_id, r.salary * 0.05, SYSDATE);
      EXCEPTION
         WHEN OTHERS THEN
            NULL;
      END;
   END LOOP;
   COMMIT;
END;
/
```

**Issues:**
1. `WHEN OTHERS THEN NULL` inside the loop (Pitfall 2) — if the `INSERT`
   into `bonus_log` fails for any employee (bad FK, full tablespace,
   anything), that employee's raise still commits at the end but the
   failure is invisible.
2. Row-by-row `UPDATE`/`INSERT` per iteration (Pitfall 1) — fine for a
   handful of Engineering employees, but the pattern doesn't scale and
   isn't worth the habit.

**Fixed:**

```sql
DECLARE
   TYPE t_num_tab IS TABLE OF NUMBER INDEX BY PLS_INTEGER;
   l_ids     t_num_tab;
   l_amounts t_num_tab;
BEGIN
   SELECT employee_id, salary * 0.05
     BULK COLLECT INTO l_ids, l_amounts
     FROM employees WHERE department_id = 30;

   FORALL i IN 1..l_ids.COUNT
      UPDATE employees SET salary = salary * 1.05 WHERE employee_id = l_ids(i);

   FORALL i IN 1..l_ids.COUNT
      INSERT INTO bonus_log (employee_id, bonus_amount, awarded_on)
      VALUES (l_ids(i), l_amounts(i), SYSDATE);

   COMMIT;
EXCEPTION
   WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('Raise batch failed, rolled back: ' || SQLERRM);
      RAISE;
END;
/
```

Now a failure anywhere rolls back the *entire* batch instead of leaving
some employees raised with no log entry — and both DML operations run as
two batched round-trips instead of N round-trips per employee.

---

⬅️ Previous: [Lab 18 — PIVOT/UNPIVOT & JSON](../lab18-pivot-json/)
➡️ Next: [Lab 20 — Procedures, Functions & Packages](../lab20-stored-procs-functions-packages/)
