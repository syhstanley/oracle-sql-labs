# Lab 13 — Bind Variables & Parsing

## Concept

Before Oracle can execute any SQL statement, it must **parse** it: check
syntax, resolve object names and privileges, and — the expensive part —
have the cost-based optimizer work out an execution plan. This full
process is a **hard parse**, and it takes a latch (a low-level lock) on
the **shared pool**, a shared memory area every session competes for.

Oracle caches parsed statements (as "cursors") in the shared pool, keyed
by the *exact SQL text*. If the next statement's text matches
character-for-character, Oracle reuses the cached plan — a cheap **soft
parse** — instead of hard-parsing again.

This is where literals become a real problem: `WHERE customer_id = 42`
and `WHERE customer_id = 43` are, character-for-character, **different
SQL text**. Each distinct literal value produces its own cursor, its own
hard parse, its own entry consuming shared pool memory. An application
that builds SQL by concatenating values directly into the query string can
flood the shared pool with thousands of near-identical cursors — a real,
common cause of high CPU and shared-pool contention on busy production
databases.

**Bind variables** fix this: `WHERE customer_id = :cust_id` is one piece
of SQL text regardless of what `:cust_id` holds at runtime, so it's parsed
once and soft-parsed (or reused directly) on every subsequent execution.

## Syntax

```sql
-- Literal SQL (bad for repeated execution with varying values)
SELECT * FROM orders WHERE customer_id = 42;

-- Bind variable inside a PL/SQL block: a plain PL/SQL variable used in
-- static SQL is automatically bound by Oracle -- no special syntax needed
DECLARE
   l_cust_id orders.customer_id%TYPE := 42;
BEGIN
   FOR r IN (SELECT order_id, order_date FROM orders WHERE customer_id = l_cust_id) LOOP
      DBMS_OUTPUT.PUT_LINE(r.order_id || ' ' || r.order_date);
   END LOOP;
END;
/

-- Bind variable with dynamic SQL (EXECUTE IMMEDIATE ... USING)
DECLARE
   l_cust_id orders.customer_id%TYPE := 42;
   l_count   NUMBER;
BEGIN
   EXECUTE IMMEDIATE
      'SELECT COUNT(*) FROM orders WHERE customer_id = :id'
      INTO l_count
      USING l_cust_id;
   DBMS_OUTPUT.PUT_LINE(l_count);
END;
/
```

| Approach | SQL text per distinct value? | Parse cost |
|---|---|---|
| String-concatenated literal (`'... = ' \|\| v_id`) | New text every time | Hard parse every execution |
| Bind variable (`:id`, or a PL/SQL variable in static SQL) | Same text always | One hard parse, then soft parses/cursor reuse |

## Scenario

Your company's order-lookup screen calls a backend that builds SQL like
`"SELECT * FROM orders WHERE customer_id = " || customerId` per request.
Under normal load this "works." Under peak load, the DBA reports shared
pool contention and high CPU spent on parsing rather than executing.
You're asked to explain why — and the fix — before anyone touches the
application code.

## Common Pitfalls

**1. String-concatenating values into SQL text**

```sql
-- WRONG (conceptually — shown as the SQL text this pattern generates):
-- application code does:  sql = "SELECT * FROM orders WHERE customer_id = " + customerId
SELECT * FROM orders WHERE customer_id = 42;
SELECT * FROM orders WHERE customer_id = 43;
SELECT * FROM orders WHERE customer_id = 44;

-- RIGHT: one statement, bind variable, reused for every customer_id
SELECT * FROM orders WHERE customer_id = :cust_id;
```
*Why:* each concatenated literal is distinct SQL text to Oracle, so each
one gets hard-parsed and cached as its own cursor — for a busy lookup
called with thousands of different IDs, this floods the shared pool with
throwaway cursors that are each executed once and never reused, wasting
both parse time and shared pool memory. This is also, separately, a **SQL
injection risk** when the value comes from user input — a second, more
serious reason never to concatenate values into SQL text.

**2. Assuming bind variables are only an application-code concern**

```sql
-- WRONG: dynamic SQL that concatenates the value even inside PL/SQL
EXECUTE IMMEDIATE 'SELECT COUNT(*) FROM orders WHERE customer_id = ' || l_cust_id
   INTO l_count;

-- RIGHT: dynamic SQL with an actual bind, via USING
EXECUTE IMMEDIATE 'SELECT COUNT(*) FROM orders WHERE customer_id = :id'
   INTO l_count USING l_cust_id;
```
*Why:* the same hard-parse-per-value problem happens inside PL/SQL
`EXECUTE IMMEDIATE` just as easily as in application code — using PL/SQL
doesn't automatically protect you; only an actual bind variable (`:id` +
`USING`) does. Note that plain *static* SQL inside PL/SQL (no
`EXECUTE IMMEDIATE`, just a normal `SELECT`/`INSERT` referencing a PL/SQL
variable) is automatically bound by Oracle — the risk is specific to
building dynamic SQL text yourself.

## Hands-on Practice

1. Write a PL/SQL block that looks up an order count for `customer_id =
   42` using a plain PL/SQL variable in a static `SELECT INTO` — confirm
   it runs and returns a count.
2. Rewrite the same lookup using `EXECUTE IMMEDIATE ... USING` instead of
   static SQL, and confirm you get the same result.
3. Rewrite it a third way — **incorrectly** — using `EXECUTE IMMEDIATE`
   with the value concatenated directly into the string — confirm it
   still works, but explain in one sentence why it shouldn't be written
   this way even though it "works."
4. (If your environment has access) query `v$sqlarea` filtered to
   `sql_text LIKE 'SELECT COUNT(*) FROM orders WHERE customer_id%'` after
   running steps 1-3 a few times each with different literal values, and
   compare how many distinct rows appear for the bound version vs the
   concatenated version.

### Answers

1.
   ```sql
   DECLARE
      l_count NUMBER;
   BEGIN
      SELECT COUNT(*) INTO l_count FROM orders WHERE customer_id = 42;
      DBMS_OUTPUT.PUT_LINE(l_count);
   END;
   /
   ```
   This is static SQL — Oracle automatically treats the literal `42`
   (well, technically here it's a hardcoded literal in the demo; in real
   code it would be a PL/SQL variable) as safe from the flooding problem
   *only when it's a variable, not a literal*. Written with a variable —
   `WHERE customer_id = l_cust_id` — the SQL text never changes no matter
   what `l_cust_id` holds, because PL/SQL variables in static SQL are
   compiled as bind variables automatically.

2.
   ```sql
   DECLARE
      l_cust_id NUMBER := 42;
      l_count   NUMBER;
   BEGIN
      EXECUTE IMMEDIATE
         'SELECT COUNT(*) FROM orders WHERE customer_id = :id'
         INTO l_count USING l_cust_id;
      DBMS_OUTPUT.PUT_LINE(l_count);
   END;
   /
   ```
   Same result, and the SQL text (`'SELECT COUNT(*) FROM orders WHERE
   customer_id = :id'`) is identical no matter what `l_cust_id` is set to.

3.
   ```sql
   DECLARE
      l_cust_id NUMBER := 42;
      l_count   NUMBER;
   BEGIN
      EXECUTE IMMEDIATE
         'SELECT COUNT(*) FROM orders WHERE customer_id = ' || l_cust_id
         INTO l_count;
      DBMS_OUTPUT.PUT_LINE(l_count);
   END;
   /
   ```
   It works because `l_cust_id` is a trusted, internally-set number here —
   but every distinct value of `l_cust_id` produces different SQL text,
   which means a fresh hard parse and a new shared-pool cursor per value,
   and if this pattern were ever fed user input instead of an internal
   variable, it would also be a SQL injection vulnerability.

4.
   ```sql
   SELECT sql_text, executions, parse_calls
   FROM v$sqlarea
   WHERE sql_text LIKE 'SELECT COUNT(*) FROM orders WHERE customer_id%'
   ORDER BY parse_calls DESC;
   ```
   Note: `V$SQLAREA` requires appropriate privileges and may be
   restricted on Live SQL's shared, multi-tenant instance — if you don't
   have access here, this is exactly the query you'd run at work (where
   you likely do have read access to `V$` views) to confirm the same
   thing: the bound version should show up as **one row** with
   `executions` incrementing each time you run it; the concatenated
   version shows up as **many rows**, one per distinct literal value,
   each with `executions = 1`.

## Debug / Optimize Challenge

A batch job that updates order status for thousands of orders, one at a
time, is spending more time parsing than updating:

```sql
-- generated once per order, inside a loop, with v_status and v_order_id
-- substituted directly into the string before execution
EXECUTE IMMEDIATE
   'UPDATE orders SET status = ''' || v_status || ''' WHERE order_id = ' || v_order_id;
```

**The fix:**

```sql
EXECUTE IMMEDIATE
   'UPDATE orders SET status = :new_status WHERE order_id = :ord_id'
   USING v_status, v_order_id;
```

**Why:** the original builds a brand-new, distinct SQL string for every
single order (different `order_id` and possibly `status` each time),
forcing a hard parse per iteration — for a batch of thousands of orders,
that's thousands of unnecessary hard parses competing for the shared pool
latch. The fixed version has exactly one SQL text, bound with `USING`, so
it's parsed once and reused (soft-parsed or cursor-cached) for every
iteration of the loop — and as a bonus, it's no longer vulnerable to SQL
injection if `v_status` ever originates from outside the batch job's own
trusted logic.

---

⬅️ Previous: [Lab 12 — Optimizer Hints](../lab12-hints-leading/)
➡️ Next: [Lab 14 — MERGE & Transactions](../lab14-merge-transactions/)
