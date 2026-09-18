# Lab 00 — Get a Real Oracle Database, Free

## Concept

You don't have Oracle installed, and your company's Oracle instance isn't
something you practice destructive experiments on. The fix used by Oracle's
own training material — and a reasonable stand-in for a Docker-based local
instance if you get one later — is **Oracle Live SQL**: a free, browser-based
SQL worksheet running against a real, current Oracle Database. Everything
you type executes on the actual Oracle engine, so syntax, error messages,
and (mostly) execution plans behave the way they will at work.

Live SQL is multi-tenant and doesn't give you DBA privileges (no
tablespace management, no `ALTER SYSTEM`), but everything this course
uses — DDL, DML, indexes, hints, `EXPLAIN PLAN`, PL/SQL — works fine there.

## Setup steps

1. Go to **https://livesql.oracle.com** and sign in (a free Oracle account
   is enough — use the "Sign Up" link if you don't have one).
2. Click **SQL Worksheet** in the top nav. You'll see a query editor with a
   green "Run Statement" (▶, single statement) and "Run Script" (▶▶,
   whole worksheet) button.
3. Open [`../schema/01_create_tables.sql`](../schema/01_create_tables.sql)
   from this repo, paste its full contents into the worksheet, and click
   **Run Script** (▶▶ — this file has multiple statements separated by
   `/` and `;`, so the single-statement Run button won't work here).
4. Clear the worksheet, paste in
   [`../schema/02_seed_data.sql`](../schema/02_seed_data.sql), and **Run
   Script** again. The PL/SQL block at the end takes a few seconds — it's
   inserting ~25,000 rows of order line items.
5. You should see a final result set listing row counts per table. Confirm
   it matches:

   | TBL | ROWS_ |
   |---|---|
   | departments | 8 |
   | employees | 48 |
   | customers | 500 |
   | products | 100 |
   | orders | 10000 |
   | order_items | ~25000 (varies — it's randomized) |

If any step errors, re-run `01_create_tables.sql` first (it drops and
recreates all six tables) and try again.

## Common Pitfalls

| Mistake | What happens | Fix |
|---|---|---|
| Pasting the seed script and clicking single-statement **Run** instead of **Run Script** | Only the first `INSERT` runs; everything after it is silently ignored | Always use **Run Script** (▶▶) for multi-statement files in this course |
| Running `02_seed_data.sql` before `01_create_tables.sql` | `ORA-00942: table or view does not exist` | Tables must exist first — run scripts in the numbered order |
| Re-running `02_seed_data.sql` without re-running `01_create_tables.sql` first | `ORA-00001: unique constraint violated` (duplicate primary keys) | `01_create_tables.sql` is idempotent (drops before creating) — re-run it whenever you want a clean slate |
| Confusing "Run Script" output truncation with a real error | Live SQL only displays a bounded number of result rows/messages per script; this is a display limit, not a failure | Re-run just the final `SELECT` (the row-count sanity check) as a single statement to confirm |

## Practice: confirm you're ready

Run this as a single statement once setup is done:

```sql
SELECT d.department_name, COUNT(e.employee_id) AS headcount
FROM departments d
LEFT JOIN employees e ON e.department_id = d.department_id
GROUP BY d.department_name
ORDER BY headcount DESC;
```

You should get 8 rows, one per department, with headcounts summing to 48.
If this runs and returns sensible numbers, your environment is ready —
move on to [Lab 01](../lab01-select-where/).

---

⬅️ Previous: none
➡️ Next: [Lab 01 — SELECT / WHERE](../lab01-select-where/)
