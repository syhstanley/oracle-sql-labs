# Lab 18 — PIVOT/UNPIVOT & JSON

## Concept

Two unrelated but equally practical skills for this lab.

**`PIVOT`/`UNPIVOT`** turn rows into columns and back. Analysts and
spreadsheet consumers usually want "one row per entity, one column per
category" (a cross-tab); your tables store "one row per fact." Oracle can
do that reshaping in SQL instead of forcing you to hand it raw rows and
let someone else pivot it in Excel.

**JSON functions** exist because more and more systems exchange data as
JSON even when the source of truth is relational — an API response, an
audit log, a document a customer uploaded. Oracle lets you build JSON out
of relational rows, validate it, pull specific values back out, and shred
a JSON array back into rows — all in SQL, without a middle-tier script.

## Syntax

```sql
-- PIVOT: rows -> columns
SELECT *
FROM (SELECT category, unit_price FROM products)
PIVOT (
   AGG_FUNCTION(unit_price)
   FOR category IN ('val1' AS alias1, 'val2' AS alias2, ...)
);

-- UNPIVOT: columns -> rows
SELECT *
FROM pivoted_table
UNPIVOT (
   value_column FOR category_column IN (col1 AS 'val1', col2 AS 'val2', ...)
);

-- JSON construction
JSON_OBJECT(KEY 'k1' VALUE col1, KEY 'k2' VALUE col2 [, ...])
JSON_ARRAYAGG(json_expr [ORDER BY ...])

-- JSON extraction
JSON_VALUE(json_expr, '$.path.to.scalar')
JSON_QUERY(json_expr, '$.path.to.object_or_array')

-- JSON shredding (JSON -> rows/columns)
SELECT jt.*
FROM some_table t,
     JSON_TABLE(t.json_col, '$.array_path'
        COLUMNS (
           col1 datatype PATH '$.field1',
           col2 datatype PATH '$.field2'
        )) jt;
```

| Function | Direction | Use |
|---|---|---|
| `PIVOT` | rows → columns | cross-tab reports |
| `UNPIVOT` | columns → rows | normalize a wide table back to long form |
| `JSON_OBJECT` / `JSON_ARRAYAGG` | relational → JSON | building an API response or export |
| `JSON_VALUE` | JSON → scalar | pull one value out |
| `JSON_QUERY` | JSON → object/array | pull a nested structure out (still JSON) |
| `JSON_TABLE` | JSON → rows/columns | shred JSON back into a relational result set |

## Scenario

**PIVOT:** Finance asks for "average product price per category, one
row, one column per category" — a single summary row instead of 5 rows
from `GROUP BY`.

**JSON:** The mobile team wants an endpoint that returns one order with
all its line items as a single JSON document, instead of joining
`orders` and `order_items` client-side.

## Common Pitfalls

**1. PIVOT's category list must be hardcoded**

```sql
-- WRONG: trying to pivot on values you don't know ahead of time
SELECT * FROM (SELECT category, unit_price FROM products)
PIVOT (AVG(unit_price) FOR category IN (SELECT DISTINCT category FROM products));
-- ORA-00936 / not valid syntax: PIVOT's IN list can't be a subquery
```

```sql
-- RIGHT: know your categories (query them once, then hardcode), or use
-- dynamic SQL (DBMS_SQL / EXECUTE IMMEDIATE) if the set truly varies —
-- out of scope for this lab, but know it exists
SELECT * FROM (SELECT category, unit_price FROM products)
PIVOT (AVG(unit_price) FOR category IN (
   'Electronics' AS electronics, 'Home' AS home, 'Office' AS office,
   'Outdoor' AS outdoor, 'Toys' AS toys
));
```

*Why:* `PIVOT`'s column list is resolved at parse time, before any data is
read — SQL needs to know the result's column names in advance, and a
subquery's values aren't known until runtime.

**2. Forgetting `PIVOT` drops non-aggregated, non-pivoted columns**

```sql
-- WRONG: expecting product_name to survive the pivot
SELECT * FROM (SELECT product_name, category, unit_price FROM products)
PIVOT (AVG(unit_price) FOR category IN ('Electronics' AS electronics));
-- product_name silently collapses into the aggregation and disappears
-- from the output entirely (not an error — just missing)
```

```sql
-- RIGHT: only include columns in the inner query that you want as
-- GROUP BY keys in the pivoted result (or pivot at the right grain)
SELECT * FROM (SELECT category, unit_price FROM products) -- no product_name
PIVOT (AVG(unit_price) FOR category IN ('Electronics' AS electronics));
```

*Why:* any column in the source query that isn't the pivot column or the
aggregated column is implicitly part of the `GROUP BY` — if you don't want
it, don't select it going into the `PIVOT`.

**3. `JSON_VALUE` truncates or errors past 4000 bytes by default**

```sql
-- WRONG: assuming JSON_VALUE always returns whatever it finds
SELECT JSON_VALUE(big_json_col, '$.long_field') FROM some_table;
-- may raise ORA-40478 (value too large) for long values
```

```sql
-- RIGHT: cap or size the return type explicitly if the field can be long
SELECT JSON_VALUE(big_json_col, '$.long_field' RETURNING VARCHAR2(4000))
   AS long_field
FROM some_table;
-- or use JSON_QUERY (returns as a JSON fragment, no scalar size limit)
-- for genuinely large text
```

*Why:* `JSON_VALUE` returns a SQL scalar (default `VARCHAR2(4000)`) — it's
built for pulling out short values, not documents. Long content needs an
explicit `RETURNING` clause or a different function.

## Hands-on Practice

1. Write a `PIVOT` query showing `COUNT(*)` of orders per `status`
   (`PENDING`, `SHIPPED`, `CANCELLED`, `COMPLETED`), one row, one column
   per status.
2. Using `UNPIVOT`, take the result of #1 and turn it back into one row
   per status with a `status` and `order_count` column (you'll need to
   materialize #1's result first, e.g. as a `WITH` clause, before
   unpivoting it).
3. For order `order_id = 1`, build a single JSON document shaped like
   `{"order_id": 1, "status": "...", "items": [{"product_id": ..,
   "quantity": ..}, ...]}` using `JSON_OBJECT` and `JSON_ARRAYAGG`.
4. Take the JSON string you got from #3, and use `JSON_TABLE` to shred
   the `items` array back into one row per line item (`product_id`,
   `quantity`).

### Answers

```sql
-- 1
SELECT * FROM (SELECT status FROM orders)
PIVOT (COUNT(*) FOR status IN (
   'PENDING' AS pending, 'SHIPPED' AS shipped,
   'CANCELLED' AS cancelled, 'COMPLETED' AS completed
));
```

```sql
-- 2
WITH pivoted AS (
   SELECT * FROM (SELECT status FROM orders)
   PIVOT (COUNT(*) FOR status IN (
      'PENDING' AS pending, 'SHIPPED' AS shipped,
      'CANCELLED' AS cancelled, 'COMPLETED' AS completed
   ))
)
SELECT * FROM pivoted
UNPIVOT (
   order_count FOR status IN (
      pending AS 'PENDING', shipped AS 'SHIPPED',
      cancelled AS 'CANCELLED', completed AS 'COMPLETED'
   )
);
```

```sql
-- 3
SELECT JSON_OBJECT(
          KEY 'order_id' VALUE o.order_id,
          KEY 'status'   VALUE o.status,
          KEY 'items'    VALUE (
             SELECT JSON_ARRAYAGG(
                       JSON_OBJECT(KEY 'product_id' VALUE oi.product_id,
                                   KEY 'quantity'    VALUE oi.quantity)
                    )
             FROM order_items oi
             WHERE oi.order_id = o.order_id
          )
       ) AS order_json
FROM orders o
WHERE o.order_id = 1;
```

```sql
-- 4 (feed #3's output in as :order_json, or wrap #3 as a subquery)
SELECT jt.product_id, jt.quantity
FROM (
   SELECT JSON_OBJECT(
             KEY 'order_id' VALUE o.order_id,
             KEY 'status'   VALUE o.status,
             KEY 'items'    VALUE (
                SELECT JSON_ARRAYAGG(
                          JSON_OBJECT(KEY 'product_id' VALUE oi.product_id,
                                      KEY 'quantity'    VALUE oi.quantity)
                       )
                FROM order_items oi WHERE oi.order_id = o.order_id
             )
          ) AS order_json
   FROM orders o WHERE o.order_id = 1
) src,
JSON_TABLE(src.order_json, '$.items'
   COLUMNS (
      product_id NUMBER PATH '$.product_id',
      quantity   NUMBER PATH '$.quantity'
   )) jt;
```

## Debug / Optimize Challenge

This is meant to validate that a `notes` column (defined as `VARCHAR2`,
holding hand-typed JSON from an internal tool) always contains valid JSON
before it's trusted downstream — but invalid rows are slipping through:

```sql
-- WRONG: this "validates" nothing — it's just a comment, not a constraint
CREATE TABLE order_notes (
   order_id NUMBER,
   notes    VARCHAR2(2000)  -- should be JSON
);
```

**Fix:** Oracle has a real constraint for this — `IS JSON`:

```sql
CREATE TABLE order_notes (
   order_id NUMBER,
   notes    VARCHAR2(2000),
   CONSTRAINT ck_order_notes_json CHECK (notes IS JSON)
);

-- now this fails at INSERT time instead of breaking a consumer downstream:
INSERT INTO order_notes VALUES (1, 'not actually json');
-- ORA-02290: check constraint violated
```

*Why it matters:* a plain `VARCHAR2` column with a comment saying "should
be JSON" enforces nothing — bad data gets in silently and only breaks
things when something tries to `JSON_VALUE`/`JSON_TABLE` it later, far
from where the bad row was inserted. `IS JSON` pushes the validation to
the earliest possible point.

---

⬅️ Previous: [Lab 17 — MERGE, Transactions & Locking](../lab17-merge-transactions/)
➡️ Next: [Lab 19 — PL/SQL Basics](../lab19-plsql-basics/)
