# Lab 03 — CREATE TABLE, ALTER TABLE & Constraints

## Concept

Every table you've queried so far already existed — Lab 00 ran
[`schema/01_create_tables.sql`](../schema/01_create_tables.sql) for you.
This lab is about being the person who writes that kind of script: how
tables actually get built, how constraints (`PRIMARY KEY`, `FOREIGN KEY`,
`UNIQUE`, `CHECK`, `NOT NULL`, `DEFAULT`) keep bad data out at the database
level instead of trusting every application, script, and person who ever
touches the table to get it right — and how to change a table's structure
later with `ALTER TABLE` once real rows are already in it. It's worth
reopening `schema/01_create_tables.sql` now: you'll recognize every clause
in it after this lab.

## Syntax

```sql
CREATE TABLE table_name (
   col1   NUMBER(6)      NOT NULL,
   col2   VARCHAR2(50)   NOT NULL,
   col3   VARCHAR2(40)   DEFAULT 'UNKNOWN',
   col4   NUMBER(2)      CHECK (col4 BETWEEN 1 AND 5),
   CONSTRAINT pk_table_name PRIMARY KEY (col1),
   CONSTRAINT uq_table_name UNIQUE (col2),
   CONSTRAINT fk_table_name FOREIGN KEY (col1) REFERENCES other_table(other_col)
);

ALTER TABLE table_name ADD (new_col VARCHAR2(200));
ALTER TABLE table_name MODIFY (col3 VARCHAR2(80));
ALTER TABLE table_name DROP COLUMN new_col;

ALTER TABLE table_name ADD CONSTRAINT ck_table_col4 CHECK (col4 > 0);
ALTER TABLE table_name DROP CONSTRAINT ck_table_col4;
ALTER TABLE table_name DISABLE CONSTRAINT ck_table_col4;
ALTER TABLE table_name ENABLE CONSTRAINT ck_table_col4;

DROP TABLE table_name CASCADE CONSTRAINTS;
```

| Constraint | Enforces |
|---|---|
| `NOT NULL` | column can never be `NULL` |
| `PRIMARY KEY` | unique **and** not null, identifies one row |
| `FOREIGN KEY ... REFERENCES` | value must exist in the referenced table's key (or be `NULL`) |
| `UNIQUE` | no two rows share this value (`NULL`s are allowed to repeat) |
| `CHECK (condition)` | condition must be `TRUE` **or `UNKNOWN`** for every row — see the NULL pitfall below |
| `DEFAULT value` | value used when `INSERT` doesn't specify the column |

**Always name your constraints** (`CONSTRAINT pk_x PRIMARY KEY (...)`
rather than leaving it unnamed). An unnamed constraint gets an
auto-generated name like `SYS_C0012345` — impossible to recognize later
when you need to `ALTER TABLE ... DROP CONSTRAINT` it.

## Scenario

Purchasing wants to start tracking suppliers, independent of the shared
`products`/`orders` schema every other lab depends on — so this is a
brand-new table, not a change to the tables Lab 00 built.

```sql
CREATE TABLE suppliers (
   supplier_id     NUMBER(6)     NOT NULL,
   supplier_name   VARCHAR2(60)  NOT NULL,
   country         VARCHAR2(40),
   rating          NUMBER(1),
   CONSTRAINT pk_suppliers PRIMARY KEY (supplier_id),
   CONSTRAINT uq_suppliers_name UNIQUE (supplier_name),
   CONSTRAINT ck_suppliers_rating CHECK (rating BETWEEN 1 AND 5)
);

INSERT INTO suppliers (supplier_id, supplier_name, country, rating)
VALUES (1, 'Acme Parts', 'Taiwan', 4);
COMMIT;
```

A few weeks later, purchasing wants a free-text `notes` column, and wants
every *new* supplier to require a rating (existing ones can stay as-is):

```sql
ALTER TABLE suppliers ADD (notes VARCHAR2(200));
```

## Common Pitfalls

**1. Adding a `NOT NULL` column to a table that already has rows**

```sql
-- WRONG: fails immediately if suppliers already has any rows
ALTER TABLE suppliers ADD (contact_email VARCHAR2(60) NOT NULL);
-- ORA-01758: table must be empty to add mandatory (NOT NULL) column
```

```sql
-- RIGHT: add it nullable with a DEFAULT, so existing rows get a real
-- value instead of failing, then tighten it if you truly need NOT NULL
ALTER TABLE suppliers ADD (contact_email VARCHAR2(60) DEFAULT 'unknown@example.com' NOT NULL);
```

*Why:* Oracle can't retroactively invent a value for existing rows to
satisfy a bare `NOT NULL`. Pairing the new column with a `DEFAULT`
lets Oracle backfill every existing row with that value in the same
statement, satisfying `NOT NULL` for rows that already exist.

**2. Dropping a table that's still referenced by a foreign key**

```sql
-- WRONG: fails if any other table has a FK pointing at suppliers
DROP TABLE suppliers;
-- ORA-02449: unique/primary keys in table referenced by foreign keys
```

```sql
-- RIGHT: explicitly drop the dependent foreign key constraints too
DROP TABLE suppliers CASCADE CONSTRAINTS;
```

*Why:* Oracle won't silently orphan a foreign key by dropping the table
its `REFERENCES` clause points at. `CASCADE CONSTRAINTS` tells Oracle to
drop those referencing FK constraints along with the table — it does
**not** delete the referencing table or its rows, just the constraint
that pointed at what you're removing.

**3. Leaving constraints unnamed**

```sql
-- WRONG: Oracle auto-names this something like SYS_C0012345
CREATE TABLE suppliers (
   rating NUMBER(1) CHECK (rating BETWEEN 1 AND 5)
);
```

```sql
-- RIGHT: name it, so a future ALTER TABLE ... DROP CONSTRAINT is
-- actually readable
CREATE TABLE suppliers (
   rating NUMBER(1),
   CONSTRAINT ck_suppliers_rating CHECK (rating BETWEEN 1 AND 5)
);
```

*Why:* every error message, every `DROP CONSTRAINT`, and every query
against `user_constraints` refers to the constraint by name. `SYS_C0012345`
tells the next person nothing about what it enforces or which table it's
on.

**4. `CHECK` constraints don't reject `NULL`**

```sql
-- Looks like it requires a rating from 1-5...
CONSTRAINT ck_suppliers_rating CHECK (rating BETWEEN 1 AND 5)
```

```sql
INSERT INTO suppliers (supplier_id, supplier_name, rating)
VALUES (2, 'Nameless Supply Co', NULL);
-- succeeds! rating is NULL, not out of range.
```

*Why:* just like `WHERE` (Lab 01), a `CHECK` constraint only **rejects**
a row when the condition evaluates to `FALSE`. `NULL BETWEEN 1 AND 5`
evaluates to `UNKNOWN`, not `FALSE` — and Oracle lets `UNKNOWN` rows
through a `CHECK` exactly like it lets them through a `WHERE`. If a
rating is genuinely mandatory, add `NOT NULL` as well; the `CHECK`
alone only constrains values that are present.

## Hands-on Practice

1. Create the `suppliers` table exactly as in the Scenario, with all
   three named constraints.
2. Insert two suppliers, then attempt to insert a third with
   `rating = 6` — confirm it's rejected, and identify the constraint
   name in the error message.
3. Attempt to insert a supplier with a duplicate `supplier_name` —
   confirm it's rejected by `uq_suppliers_name`.
4. Add a `notes VARCHAR2(200)` column to `suppliers` with `ALTER TABLE`.
5. Add a `contact_email` column that must be `NOT NULL` going forward,
   without breaking the two existing rows (use the `DEFAULT` technique
   from Pitfall 1).

### Answers

```sql
-- 1
CREATE TABLE suppliers (
   supplier_id     NUMBER(6)     NOT NULL,
   supplier_name   VARCHAR2(60)  NOT NULL,
   country         VARCHAR2(40),
   rating          NUMBER(1),
   CONSTRAINT pk_suppliers PRIMARY KEY (supplier_id),
   CONSTRAINT uq_suppliers_name UNIQUE (supplier_name),
   CONSTRAINT ck_suppliers_rating CHECK (rating BETWEEN 1 AND 5)
);

-- 2
INSERT INTO suppliers (supplier_id, supplier_name, country, rating)
VALUES (1, 'Acme Parts', 'Taiwan', 4);
INSERT INTO suppliers (supplier_id, supplier_name, country, rating)
VALUES (2, 'Bolt Supply', 'Japan', 5);

INSERT INTO suppliers (supplier_id, supplier_name, country, rating)
VALUES (3, 'Bad Rating Co', 'USA', 6);
-- ORA-02290: check constraint (SCHEMA.CK_SUPPLIERS_RATING) violated
-- the constraint name in the message is exactly the one we chose above.

-- 3
INSERT INTO suppliers (supplier_id, supplier_name, country, rating)
VALUES (4, 'Acme Parts', 'USA', 3);
-- ORA-00001: unique constraint (SCHEMA.UQ_SUPPLIERS_NAME) violated

-- 4
ALTER TABLE suppliers ADD (notes VARCHAR2(200));

-- 5
ALTER TABLE suppliers ADD (contact_email VARCHAR2(60) DEFAULT 'unknown@example.com' NOT NULL);
-- existing rows (1, 2) are backfilled with the default; any future
-- INSERT must supply a real contact_email or accept the default.
```

## Debug / Optimize Challenge

Someone tried to enforce "every supplier must have a rating" this way:

```sql
CREATE TABLE suppliers_v2 (
   supplier_id     NUMBER(6)     NOT NULL,
   supplier_name   VARCHAR2(60)  NOT NULL,
   rating          NUMBER(1)     CHECK (rating BETWEEN 1 AND 5),
   CONSTRAINT pk_suppliers_v2 PRIMARY KEY (supplier_id)
);

INSERT INTO suppliers_v2 (supplier_id, supplier_name, rating)
VALUES (1, 'Ghost Supplier', NULL);
-- succeeds — but a rating was supposed to be mandatory!
```

**Fix:**

```sql
CREATE TABLE suppliers_v2 (
   supplier_id     NUMBER(6)     NOT NULL,
   supplier_name   VARCHAR2(60)  NOT NULL,
   rating          NUMBER(1)     NOT NULL CHECK (rating BETWEEN 1 AND 5),
   CONSTRAINT pk_suppliers_v2 PRIMARY KEY (supplier_id)
);
```

**Why:** this is Pitfall 4 above. `CHECK (rating BETWEEN 1 AND 5)` only
rejects a rating that's present and out of range — it was never asked to
reject the *absence* of a rating. `NOT NULL` and `CHECK` enforce two
different things and are usually needed together: `NOT NULL` says "this
value must exist," `CHECK` says "if it exists, it must be in range."

---

⬅️ Previous: [Lab 02 — INSERT / UPDATE / DELETE / CASE / NULLIF](../lab02-dml-basics/)
➡️ Next: [Lab 04 — DUAL & Pseudo-columns](../lab04-dual-pseudocolumns/)
