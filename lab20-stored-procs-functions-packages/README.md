# Lab 20 — Procedures, Functions & Packages

## Concept

Lab 19's anonymous blocks run once and disappear — nothing about them is
callable from anywhere else. A **function** is a named PL/SQL block that
returns a value and can be called from plain SQL (inside a `SELECT`, a
`WHERE`, a `CASE`) as well as from PL/SQL. A **procedure** performs an
action and cannot be called from a SQL expression — only from PL/SQL (or
directly, as a standalone call). A **package** bundles related procedures
and functions under one name, and lets you hide implementation details:
anything declared only in the package *body* (not the *spec*) is private,
invisible outside the package, exactly like a private helper method.

## Syntax

```sql
CREATE OR REPLACE FUNCTION function_name (
   p_param1 IN NUMBER,
   p_param2 IN DATE
) RETURN NUMBER
IS
   l_result NUMBER;
BEGIN
   l_result := p_param1 * 2; -- whatever the calculation is
   RETURN l_result;
END function_name;
/

CREATE OR REPLACE PROCEDURE procedure_name (
   p_in_param   IN  NUMBER,
   p_out_param  OUT NUMBER,
   p_io_param   IN OUT NUMBER
)
IS
BEGIN
   p_out_param := p_in_param * 2;
   p_io_param  := p_io_param + p_in_param;
END procedure_name;
/

CREATE OR REPLACE PACKAGE pkg_name IS
   -- public: everything declared here is callable from outside the package
   FUNCTION  get_something(p_id IN NUMBER) RETURN NUMBER;
   PROCEDURE do_something(p_id IN NUMBER);
END pkg_name;
/

CREATE OR REPLACE PACKAGE BODY pkg_name IS
   -- private: declared in the body only, invisible outside the package
   FUNCTION helper(p_x IN NUMBER) RETURN NUMBER IS
   BEGIN
      RETURN p_x * 10;
   END helper;

   FUNCTION get_something(p_id IN NUMBER) RETURN NUMBER IS
   BEGIN
      RETURN helper(p_id);
   END get_something;

   PROCEDURE do_something(p_id IN NUMBER) IS
   BEGIN
      NULL; -- ...
   END do_something;
END pkg_name;
/
```

| Parameter mode | Meaning |
|---|---|
| `IN` (default) | caller passes a value in; the routine can't change the caller's variable |
| `OUT` | routine sets a value the caller receives back; its **incoming** value is ignored |
| `IN OUT` | both — routine reads the caller's value *and* can change it |

## Scenario

Lab 19's one-off bonus calculation is worth making reusable. First, a pure
function with no side effects — safe to call from SQL:

```sql
CREATE OR REPLACE FUNCTION get_bonus_amount (
   p_salary    IN NUMBER,
   p_hire_date IN DATE
) RETURN NUMBER
IS
BEGIN
   RETURN CASE
             WHEN p_hire_date < DATE '2020-01-01' THEN p_salary * 0.10
             ELSE p_salary * 0.05
          END;
END get_bonus_amount;
/

SELECT employee_id, salary, get_bonus_amount(salary, hire_date) AS bonus
FROM employees
WHERE department_id = 10;
```

Then a procedure that applies it and logs the result — this one *does*
have side effects (an `INSERT`), so it stays a procedure, not a function:

```sql
CREATE OR REPLACE PROCEDURE award_department_bonus (
   p_department_id IN NUMBER
)
IS
BEGIN
   FOR r IN (SELECT employee_id, salary, hire_date
             FROM employees WHERE department_id = p_department_id) LOOP
      INSERT INTO bonus_log (employee_id, bonus_amount, awarded_on)
      VALUES (r.employee_id, get_bonus_amount(r.salary, r.hire_date), SYSDATE);
   END LOOP;
   COMMIT;
END award_department_bonus;
/

EXEC award_department_bonus(10);
```

Finally, bundle both into a package once they're stable enough to
maintain together:

```sql
CREATE OR REPLACE PACKAGE hr_pkg IS
   FUNCTION  get_bonus_amount(p_salary IN NUMBER, p_hire_date IN DATE) RETURN NUMBER;
   PROCEDURE award_department_bonus(p_department_id IN NUMBER);
END hr_pkg;
/

CREATE OR REPLACE PACKAGE BODY hr_pkg IS
   FUNCTION get_bonus_amount(p_salary IN NUMBER, p_hire_date IN DATE) RETURN NUMBER IS
   BEGIN
      RETURN CASE
                WHEN p_hire_date < DATE '2020-01-01' THEN p_salary * 0.10
                ELSE p_salary * 0.05
             END;
   END get_bonus_amount;

   PROCEDURE award_department_bonus(p_department_id IN NUMBER) IS
   BEGIN
      FOR r IN (SELECT employee_id, salary, hire_date
                FROM employees WHERE department_id = p_department_id) LOOP
         INSERT INTO bonus_log (employee_id, bonus_amount, awarded_on)
         VALUES (r.employee_id, get_bonus_amount(r.salary, r.hire_date), SYSDATE);
      END LOOP;
      COMMIT;
   END award_department_bonus;
END hr_pkg;
/

EXEC hr_pkg.award_department_bonus(10);
```

## Common Pitfalls

**1. Calling a function with side effects from inside a `SELECT`**

```sql
CREATE OR REPLACE FUNCTION log_and_get_price (p_product_id IN NUMBER) RETURN NUMBER IS
   l_price NUMBER;
BEGIN
   SELECT unit_price INTO l_price FROM products WHERE product_id = p_product_id;
   INSERT INTO price_lookup_log (product_id, looked_up_on) VALUES (p_product_id, SYSDATE);
   RETURN l_price;
END;
/

SELECT product_id, log_and_get_price(product_id) FROM products;
-- ORA-14551: cannot perform a DML operation inside a query
```

```sql
-- RIGHT: keep the function pure (no DML); do the logging in the caller
-- (a procedure), not inside something meant to be called from SQL
CREATE OR REPLACE FUNCTION get_price (p_product_id IN NUMBER) RETURN NUMBER IS
   l_price NUMBER;
BEGIN
   SELECT unit_price INTO l_price FROM products WHERE product_id = p_product_id;
   RETURN l_price;
END;
/
```

*Why:* a `SELECT` is read-only by definition — Oracle won't let a
function invoked from one perform `INSERT`/`UPDATE`/`DELETE`, because the
query might be part of a read-consistent snapshot, run in parallel, or
invoked more times than you'd expect. (`PRAGMA AUTONOMOUS_TRANSACTION`
can technically work around this by running the DML in its own
sub-transaction — but reach for restructuring the logic first; an
autonomous transaction that partially commits independently of its caller
is its own source of subtle bugs.)

**2. Mixing up `IN`, `OUT`, and `IN OUT`**

```sql
DECLARE
   l_val NUMBER := 5;
BEGIN
   procedure_name(10, l_val, l_val); -- p_out_param is OUT — passing l_val here is legal
   -- but if procedure_name reads p_out_param's incoming value expecting 5, it won't see it
END;
/
```

*Why:* an `OUT` parameter's incoming value is always ignored — the
routine starts with it as `NULL` regardless of what the caller passed.
If you need the routine to both read *and* modify a value, that's
`IN OUT`, not `OUT`.

**3. Forgetting a package spec change invalidates its dependents**

```sql
-- Changing hr_pkg's spec (e.g. adding a parameter) invalidates every
-- object that references hr_pkg, until they're recompiled
ALTER PACKAGE hr_pkg COMPILE;
ALTER PACKAGE hr_pkg COMPILE BODY;

-- if a compile fails, the actual error is here, not in a generic message:
SELECT line, position, text FROM user_errors WHERE name = 'HR_PKG';
```

*Why:* PL/SQL tracks dependencies between compiled objects. Changing a
package's spec (even just adding a parameter to one function) marks
every caller `INVALID` until Oracle recompiles them — usually
automatically on next use, but a failed recompile just gets silently
skipped unless you check `user_errors` yourself.

**4. Assuming a SQL-callable function runs exactly once per output row**

Oracle may call a function referenced in a `WHERE` clause once per row
*scanned*, not once per row *returned* — and may call it more times than
either, depending on the execution plan. A function that's expensive, or
that behaves differently on repeated calls with the same input, will
behave unpredictably here. Keep functions called from SQL cheap and
deterministic; do anything expensive or stateful in a procedure instead.

## Hands-on Practice

1. Create `get_bonus_amount` as a function and call it directly in a
   `SELECT` against `employees` for `department_id = 10`.
2. Create `award_department_bonus` as a procedure that loops over a
   department and inserts into `bonus_log`, calling `get_bonus_amount`
   internally. Run it for `department_id = 20`.
3. Bundle both into `hr_pkg` (spec + body) and call
   `hr_pkg.award_department_bonus` for `department_id = 30`.
4. Confirm calling `hr_pkg.get_bonus_amount` directly from a `SELECT`
   works (it's a pure function — no DML inside it).

### Answers

```sql
-- 1
CREATE OR REPLACE FUNCTION get_bonus_amount (
   p_salary IN NUMBER, p_hire_date IN DATE
) RETURN NUMBER
IS
BEGIN
   RETURN CASE WHEN p_hire_date < DATE '2020-01-01' THEN p_salary * 0.10
               ELSE p_salary * 0.05 END;
END get_bonus_amount;
/

SELECT employee_id, salary, get_bonus_amount(salary, hire_date) AS bonus
FROM employees WHERE department_id = 10;

-- 2
CREATE OR REPLACE PROCEDURE award_department_bonus (p_department_id IN NUMBER) IS
BEGIN
   FOR r IN (SELECT employee_id, salary, hire_date
             FROM employees WHERE department_id = p_department_id) LOOP
      INSERT INTO bonus_log (employee_id, bonus_amount, awarded_on)
      VALUES (r.employee_id, get_bonus_amount(r.salary, r.hire_date), SYSDATE);
   END LOOP;
   COMMIT;
END award_department_bonus;
/

EXEC award_department_bonus(20);

-- 3
CREATE OR REPLACE PACKAGE hr_pkg IS
   FUNCTION  get_bonus_amount(p_salary IN NUMBER, p_hire_date IN DATE) RETURN NUMBER;
   PROCEDURE award_department_bonus(p_department_id IN NUMBER);
END hr_pkg;
/

CREATE OR REPLACE PACKAGE BODY hr_pkg IS
   FUNCTION get_bonus_amount(p_salary IN NUMBER, p_hire_date IN DATE) RETURN NUMBER IS
   BEGIN
      RETURN CASE WHEN p_hire_date < DATE '2020-01-01' THEN p_salary * 0.10
                  ELSE p_salary * 0.05 END;
   END get_bonus_amount;

   PROCEDURE award_department_bonus(p_department_id IN NUMBER) IS
   BEGIN
      FOR r IN (SELECT employee_id, salary, hire_date
                FROM employees WHERE department_id = p_department_id) LOOP
         INSERT INTO bonus_log (employee_id, bonus_amount, awarded_on)
         VALUES (r.employee_id, get_bonus_amount(r.salary, r.hire_date), SYSDATE);
      END LOOP;
      COMMIT;
   END award_department_bonus;
END hr_pkg;
/

EXEC hr_pkg.award_department_bonus(30);

-- 4
SELECT employee_id, hr_pkg.get_bonus_amount(salary, hire_date) AS bonus
FROM employees WHERE department_id = 30;
```

## Debug / Optimize Challenge

A teammate wanted a single function that both returns a discount rate
*and* logs every lookup for auditing — then couldn't figure out why it
breaks whenever it's used in a report query:

```sql
-- BROKEN
CREATE OR REPLACE FUNCTION get_discount_rate (p_customer_id IN NUMBER) RETURN NUMBER IS
   l_rate NUMBER;
BEGIN
   SELECT CASE WHEN country IN ('USA','Canada') THEN 0.05 ELSE 0.10 END
     INTO l_rate FROM customers WHERE customer_id = p_customer_id;

   INSERT INTO discount_lookup_log (customer_id, looked_up_on)
   VALUES (p_customer_id, SYSDATE);

   RETURN l_rate;
END;
/

SELECT customer_id, get_discount_rate(customer_id) FROM customers;
-- ORA-14551: cannot perform a DML operation inside a query
```

**Fix:** split the pure calculation from the logging — call the function
from SQL, and do the logging separately in a procedure that wraps it:

```sql
CREATE OR REPLACE FUNCTION get_discount_rate (p_customer_id IN NUMBER) RETURN NUMBER IS
   l_rate NUMBER;
BEGIN
   SELECT CASE WHEN country IN ('USA','Canada') THEN 0.05 ELSE 0.10 END
     INTO l_rate FROM customers WHERE customer_id = p_customer_id;
   RETURN l_rate;
END;
/

CREATE OR REPLACE PROCEDURE log_discount_lookup (p_customer_id IN NUMBER) IS
BEGIN
   INSERT INTO discount_lookup_log (customer_id, looked_up_on)
   VALUES (p_customer_id, SYSDATE);
   COMMIT;
END;
/

-- report query: pure function, safe from SQL
SELECT customer_id, get_discount_rate(customer_id) FROM customers;

-- separately, when a specific lookup needs auditing:
EXEC log_discount_lookup(42);
```

**Why:** the original function tried to be two things at once — a value
computation *and* a side effect. Anything called from a `SELECT` must
stay read-only (Pitfall 1); the fix isn't to force the DML through with
`PRAGMA AUTONOMOUS_TRANSACTION`, it's to recognize that logging belongs
in the caller, not inside the thing being selected.

---

⬅️ Previous: [Lab 19 — PL/SQL Basics](../lab19-plsql-basics/)
➡️ Next: [Lab 21 — Triggers](../lab21-triggers/)
