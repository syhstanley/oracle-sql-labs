# Lab 21 — Triggers

## Concept

Everything so far runs because someone explicitly called it — a `SELECT`,
an `UPDATE`, a procedure. A **trigger** runs automatically, fired by a
DML event on a table, without the caller doing anything special or even
knowing the trigger exists. That's exactly what makes triggers powerful
for things an application can't be trusted to remember every time (an
audit trail on every salary change, no matter which of ten different
scripts changes it) — and exactly what makes them dangerous: business
logic hiding somewhere nobody thinks to look when debugging an
`UPDATE` that "shouldn't" have done anything else.

## Syntax

```sql
CREATE OR REPLACE TRIGGER trigger_name
{BEFORE | AFTER} {INSERT | UPDATE [OF column_name] | DELETE} ON table_name
[FOR EACH ROW]
[WHEN (condition)]
DECLARE
   -- optional local variables
BEGIN
   -- :NEW.column  — the row's value after the change (INSERT/UPDATE)
   -- :OLD.column  — the row's value before the change (UPDATE/DELETE)
   NULL;
END;
/

-- ordering multiple triggers on the same table + timing + event
CREATE OR REPLACE TRIGGER trigger_two
AFTER UPDATE ON table_name
FOR EACH ROW
FOLLOWS trigger_name
BEGIN
   NULL;
END;
/

ALTER TABLE table_name DISABLE ALL TRIGGERS;
ALTER TABLE table_name ENABLE ALL TRIGGERS;
```

| Concept | Meaning |
|---|---|
| `FOR EACH ROW` (row-level) | fires once per affected row; `:NEW`/`:OLD` available |
| no `FOR EACH ROW` (statement-level) | fires once per statement, regardless of how many rows it touched; no `:NEW`/`:OLD` |
| `BEFORE` | fires before the row change is applied — can inspect/modify `:NEW` before it's written |
| `AFTER` | fires after the row change is applied — can't modify `:NEW` anymore, but can safely rely on the change having happened |
| `WHEN (condition)` | skip firing unless the condition on `:NEW`/`:OLD` is true — cheaper than an `IF` inside the body |

## Scenario

Payroll wants every salary change traceable, no matter which script or
person made it — an audit table, filled automatically:

```sql
CREATE TABLE salary_audit (
   employee_id  NUMBER(6),
   old_salary   NUMBER(10,2),
   new_salary   NUMBER(10,2),
   changed_on   DATE
);

CREATE OR REPLACE TRIGGER trg_salary_audit
AFTER UPDATE OF salary ON employees
FOR EACH ROW
BEGIN
   INSERT INTO salary_audit (employee_id, old_salary, new_salary, changed_on)
   VALUES (:OLD.employee_id, :OLD.salary, :NEW.salary, SYSDATE);
END;
/

UPDATE employees SET salary = salary * 1.05 WHERE employee_id = 1001;
COMMIT;

SELECT * FROM salary_audit;
```

Nobody running that `UPDATE` had to remember to log anything — the
trigger did it regardless of which tool or script issued the `UPDATE`.

## Common Pitfalls

**1. The mutating-table error**

```sql
-- WRONG: a row-level trigger that reads the same table it's firing on
CREATE OR REPLACE TRIGGER trg_salary_cap
BEFORE UPDATE OF salary ON employees
FOR EACH ROW
DECLARE
   l_dept_avg NUMBER;
BEGIN
   SELECT AVG(salary) INTO l_dept_avg FROM employees WHERE department_id = :NEW.department_id;
   IF :NEW.salary > l_dept_avg * 2 THEN
      RAISE_APPLICATION_ERROR(-20001, 'Salary exceeds department cap');
   END IF;
END;
/
-- ORA-04091: table EMPLOYEES is mutating, trigger/function may not see it
```

```sql
-- RIGHT: move the cross-row check to a statement-level AFTER trigger
-- (no FOR EACH ROW), which runs once the whole statement has finished
-- changing rows, so the table is no longer "mutating"
CREATE OR REPLACE TRIGGER trg_salary_cap_check
AFTER UPDATE OF salary ON employees
DECLARE
   l_violations NUMBER;
BEGIN
   SELECT COUNT(*) INTO l_violations
   FROM employees e
   WHERE e.salary > (SELECT AVG(salary) * 2 FROM employees WHERE department_id = e.department_id);

   IF l_violations > 0 THEN
      RAISE_APPLICATION_ERROR(-20001, 'One or more salaries exceed department cap');
   END IF;
END;
/
```

*Why:* a row-level trigger fires *while* its statement is still in the
middle of changing rows in that table — Oracle can't give you a
consistent, fully-updated view of a table that isn't finished changing
yet, so it refuses with `ORA-04091` rather than show you a half-applied
result. A statement-level trigger (no `FOR EACH ROW`) instead fires once,
after every row the statement touches has already been applied — by then
the table isn't "mutating" anymore.

**2. Reaching for a trigger where a `CHECK` constraint already fits**

```sql
-- WRONG: a trigger reimplementing what Lab 03's CHECK already does,
-- more expensively (fires per row, needs PL/SQL) and less declaratively
CREATE OR REPLACE TRIGGER trg_rating_range
BEFORE INSERT OR UPDATE ON suppliers
FOR EACH ROW
BEGIN
   IF :NEW.rating NOT BETWEEN 1 AND 5 THEN
      RAISE_APPLICATION_ERROR(-20002, 'Rating out of range');
   END IF;
END;
/
```

```sql
-- RIGHT: a single-column, single-row range check belongs in a CHECK
-- constraint (Lab 03) — no PL/SQL, no per-row trigger overhead, and it
-- shows up in user_constraints where anyone inspecting the table will
-- actually find it
ALTER TABLE suppliers ADD CONSTRAINT ck_suppliers_rating CHECK (rating BETWEEN 1 AND 5);
```

*Why:* triggers are for things a constraint genuinely can't express —
cross-row rules, cross-table rules, audit logging, anything needing
procedural logic. A same-row, same-column range check is exactly what
`CHECK` was built for; a trigger doing the same job is slower and easier
to miss when someone's trying to understand the table's rules.

**3. Disabling triggers for a bulk load and forgetting to re-enable them**

```sql
ALTER TABLE employees DISABLE ALL TRIGGERS;
-- ... bulk salary import runs, trg_salary_audit never fires for any of it ...
-- someone forgets the next line:
ALTER TABLE employees ENABLE ALL TRIGGERS;
```

*Why:* disabling triggers for a large load is a legitimate performance
technique, but every row changed while triggers are disabled leaves no
audit trail and skips any other trigger-enforced logic — silently, with
no error. Treat `DISABLE`/`ENABLE ALL TRIGGERS` as a matched pair in the
same script, never as two separate manual steps.

## Hands-on Practice

1. Create `salary_audit` and `trg_salary_audit` exactly as in the
   Scenario.
2. Update `employees.salary` for one employee and confirm a row appears
   in `salary_audit` with the correct old/new values.
3. Update a column *other than* `salary` (e.g. `job_title`) on the same
   employee and confirm **no** row is added to `salary_audit` — explain
   in one sentence why (`OF salary` in the trigger's `UPDATE OF` clause).
4. Write `trg_salary_cap` from Pitfall 1 exactly as shown (the row-level
   version) and confirm it raises `ORA-04091` the first time it fires.
   Then replace it with the statement-level fix and confirm a salary
   updated to more than double its department's average is rejected.

### Answers

```sql
-- 1
CREATE TABLE salary_audit (
   employee_id NUMBER(6), old_salary NUMBER(10,2),
   new_salary NUMBER(10,2), changed_on DATE
);

CREATE OR REPLACE TRIGGER trg_salary_audit
AFTER UPDATE OF salary ON employees
FOR EACH ROW
BEGIN
   INSERT INTO salary_audit (employee_id, old_salary, new_salary, changed_on)
   VALUES (:OLD.employee_id, :OLD.salary, :NEW.salary, SYSDATE);
END;
/

-- 2
UPDATE employees SET salary = salary * 1.05 WHERE employee_id = 1001;
COMMIT;
SELECT * FROM salary_audit WHERE employee_id = 1001;

-- 3
UPDATE employees SET job_title = 'Senior ' || job_title WHERE employee_id = 1001;
COMMIT;
SELECT * FROM salary_audit WHERE employee_id = 1001; -- no new row
-- UPDATE OF salary means the trigger only fires when salary is part of
-- the SET list of the UPDATE statement, regardless of what else changes.

-- 4
CREATE OR REPLACE TRIGGER trg_salary_cap
BEFORE UPDATE OF salary ON employees
FOR EACH ROW
DECLARE
   l_dept_avg NUMBER;
BEGIN
   SELECT AVG(salary) INTO l_dept_avg FROM employees WHERE department_id = :NEW.department_id;
   IF :NEW.salary > l_dept_avg * 2 THEN
      RAISE_APPLICATION_ERROR(-20001, 'Salary exceeds department cap');
   END IF;
END;
/
UPDATE employees SET salary = salary * 3 WHERE employee_id = 1001;
-- ORA-04091: table EMPLOYEES is mutating, trigger/function may not see it

DROP TRIGGER trg_salary_cap;

CREATE OR REPLACE TRIGGER trg_salary_cap_check
AFTER UPDATE OF salary ON employees
DECLARE
   l_violations NUMBER;
BEGIN
   SELECT COUNT(*) INTO l_violations
   FROM employees e
   WHERE e.salary > (SELECT AVG(salary) * 2 FROM employees WHERE department_id = e.department_id);
   IF l_violations > 0 THEN
      RAISE_APPLICATION_ERROR(-20001, 'One or more salaries exceed department cap');
   END IF;
END;
/
UPDATE employees SET salary = salary * 3 WHERE employee_id = 1001;
-- ORA-20001: One or more salaries exceed department cap (statement rolled back)
```

## Debug / Optimize Challenge

A teammate's audit trigger keeps throwing `ORA-04091` and they can't see
why — it looks like it's only reading `:NEW`, not the table:

```sql
-- BROKEN
CREATE OR REPLACE TRIGGER trg_dept_headcount_check
BEFORE INSERT ON employees
FOR EACH ROW
DECLARE
   l_headcount NUMBER;
BEGIN
   SELECT COUNT(*) INTO l_headcount FROM employees WHERE department_id = :NEW.department_id;
   IF l_headcount >= 20 THEN
      RAISE_APPLICATION_ERROR(-20003, 'Department headcount limit reached');
   END IF;
END;
/

INSERT INTO employees (employee_id, last_name, email, hire_date, job_title, salary, department_id, manager_id)
VALUES (9999, 'Test', 'test@example.com', SYSDATE, 'Clerk', 40000, 10, 100);
-- ORA-04091: table EMPLOYEES is mutating, trigger/function may not see it
```

**Fix:** same root cause as Pitfall 1 — move the aggregate check to a
statement-level `AFTER` trigger:

```sql
DROP TRIGGER trg_dept_headcount_check;

CREATE OR REPLACE TRIGGER trg_dept_headcount_check
AFTER INSERT ON employees
DECLARE
   l_over_limit NUMBER;
BEGIN
   SELECT COUNT(*) INTO l_over_limit
   FROM (
      SELECT department_id FROM employees
      GROUP BY department_id
      HAVING COUNT(*) > 20
   );
   IF l_over_limit > 0 THEN
      RAISE_APPLICATION_ERROR(-20003, 'Department headcount limit reached');
   END IF;
END;
/
```

**Why:** it doesn't matter that the trigger body only *reads* `employees`
via `SELECT COUNT(*)` rather than writing to it — reading the same table
that's still being written to by the statement that fired the trigger is
exactly what `ORA-04091` guards against. Any row-level trigger that
queries its own table for a cross-row check (a `COUNT`, `AVG`, `SUM`
across other rows) hits this. The fix is always the same shape: do the
cross-row check once, after the statement finishes, in a statement-level
trigger.

---

⬅️ Previous: [Lab 20 — Procedures, Functions & Packages](../lab20-stored-procs-functions-packages/)
➡️ Next: [Lab 22 — Capstone](../lab22-capstone-tuning/)
