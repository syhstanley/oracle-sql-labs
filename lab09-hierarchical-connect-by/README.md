# Lab 09 — Hierarchical Queries (CONNECT BY)

## Concept

Some data is naturally tree-shaped: an org chart, a bill-of-materials, a
category-within-category taxonomy. Oracle has a dedicated,
Oracle-only syntax for walking these trees — `CONNECT BY` — that predates
the ANSI-standard recursive CTE (which Oracle also supports, since 11g R2)
and is still what you'll find in most existing Oracle codebases. `employees`
in this schema is a self-referencing tree via `manager_id`, exactly the
shape `CONNECT BY` is built for.

## Syntax

```sql
SELECT LEVEL,
       LPAD(' ', 2 * (LEVEL - 1)) || last_name AS org_chart,
       employee_id, manager_id
FROM   employees
START WITH manager_id IS NULL          -- the root(s) of the tree
CONNECT BY PRIOR employee_id = manager_id  -- child.manager_id = parent.employee_id
ORDER SIBLINGS BY last_name;           -- sort within each sibling group, keep tree order
```

| Element | Meaning |
|---|---|
| `START WITH <condition>` | which row(s) are the root(s) of the tree |
| `CONNECT BY PRIOR parent_col = child_col` | how a parent row relates to its children; `PRIOR` marks which side is the *parent* row |
| `LEVEL` | pseudo-column: 1 for the root, 2 for its children, etc. |
| `SYS_CONNECT_BY_PATH(col, sep)` | builds a delimited path from the root down to the current row |
| `CONNECT_BY_ROOT col` | returns the root row's value of `col`, for any row in the tree |
| `CONNECT_BY_ISLEAF` | 1 if the current row has no children, else 0 |
| `ORDER SIBLINGS BY <cols>` | sorts children within each parent, without breaking the tree's depth-first order |
| `NOCYCLE` | tolerate cycles instead of raising `ORA-01436` (pairs with `CONNECT_BY_ISCYCLE`) |

Equivalent ANSI recursive CTE, same result:

```sql
WITH org_chart (employee_id, manager_id, last_name, lvl, path) AS (
   SELECT employee_id, manager_id, last_name, 1, last_name
   FROM   employees
   WHERE  manager_id IS NULL
   UNION ALL
   SELECT e.employee_id, e.manager_id, e.last_name, oc.lvl + 1, oc.path || '/' || e.last_name
   FROM   employees e
   JOIN   org_chart oc ON e.manager_id = oc.employee_id
)
SELECT * FROM org_chart ORDER BY path;
```

## Scenario

HR wants a printable org chart showing every employee indented by
reporting level under their manager, plus, for every individual
contributor, a quick way to see which department head they ultimately
roll up to (useful once reorgs make the chain non-obvious).

## Common Pitfalls

### Forgetting `START WITH`

```sql
-- WRONG: no START WITH at all
SELECT employee_id, manager_id, LEVEL
FROM employees
CONNECT BY PRIOR employee_id = manager_id;
```
Without `START WITH`, Oracle treats **every row** as a potential root and
walks the tree starting from each one independently, so you get the same
employees repeated many times over (once per starting point that can
reach them) instead of one clean tree from the CEO down. This doesn't
error — it just produces a much larger, confusing result set than
intended.

```sql
-- RIGHT
SELECT employee_id, manager_id, LEVEL
FROM employees
START WITH manager_id IS NULL
CONNECT BY PRIOR employee_id = manager_id;
```

### Using plain `ORDER BY` instead of `ORDER SIBLINGS BY`

```sql
-- WRONG: intent is an org chart sorted alphabetically within each level,
-- but keeping the parent-before-children tree structure
SELECT LEVEL, last_name
FROM employees
START WITH manager_id IS NULL
CONNECT BY PRIOR employee_id = manager_id
ORDER BY last_name;
```
A plain `ORDER BY` after `CONNECT BY` re-sorts the **entire flattened
result set** by `last_name`, ignoring `LEVEL` completely — the CEO could
end up sorted in among the individual contributors alphabetically, and the
tree/indentation structure is destroyed.

```sql
-- RIGHT
SELECT LEVEL, last_name
FROM employees
START WITH manager_id IS NULL
CONNECT BY PRIOR employee_id = manager_id
ORDER SIBLINGS BY last_name;
```
`ORDER SIBLINGS BY` only reorders children *within* their existing parent
group — the depth-first, parent-before-children shape of the tree is
preserved.

### Cyclic data

If `manager_id` data ever contains a cycle (e.g. a data-entry error where
A reports to B and B reports to A), `CONNECT BY` raises
`ORA-01436: CONNECT BY loop in user data` and the query fails outright.
For data that's *expected* to have cycles, add `NOCYCLE` to keep the query
running and use `CONNECT_BY_ISCYCLE` to flag where it stopped:

```sql
SELECT employee_id, manager_id, CONNECT_BY_ISCYCLE AS is_cycle
FROM employees
START WITH manager_id IS NULL
CONNECT BY NOCYCLE PRIOR employee_id = manager_id;
```

## Hands-on Practice

1. Print the full org chart: `LEVEL`, indented `last_name`, ordered so
   siblings are alphabetical but the tree structure is intact.
2. For every individual contributor (`employee_id >= 1000`), show their
   name and the full path from the CEO down to them using
   `SYS_CONNECT_BY_PATH`.
3. For every employee, show which department head (`employee_id` between
   200 and 299) they ultimately roll up to, using `CONNECT_BY_ROOT` —
   but start the tree at each department head instead of the CEO so the
   "root" is meaningful per department.
4. List only the leaf nodes of the org chart (employees with no direct
   reports) using `CONNECT_BY_ISLEAF`.
5. Rewrite exercise 1 as an ANSI recursive CTE instead of `CONNECT BY`.

### Answers

```sql
-- 1.
SELECT LEVEL, LPAD(' ', 2*(LEVEL-1)) || last_name AS org_chart
FROM employees
START WITH manager_id IS NULL
CONNECT BY PRIOR employee_id = manager_id
ORDER SIBLINGS BY last_name;
-- ORDER SIBLINGS BY keeps parents before children while still sorting each sibling group.

-- 2.
SELECT employee_id, last_name,
       SYS_CONNECT_BY_PATH(last_name, '/') AS path
FROM employees
START WITH manager_id IS NULL
CONNECT BY PRIOR employee_id = manager_id
WHERE employee_id >= 1000;
-- SYS_CONNECT_BY_PATH concatenates last_name from the root down to each row.

-- 3.
SELECT employee_id, last_name,
       CONNECT_BY_ROOT last_name AS department_head
FROM employees
START WITH employee_id BETWEEN 200 AND 299
CONNECT BY PRIOR employee_id = manager_id;
-- Starting the tree at each department head (instead of the CEO) makes CONNECT_BY_ROOT return that head's own name.

-- 4.
SELECT employee_id, last_name
FROM employees
START WITH manager_id IS NULL
CONNECT BY PRIOR employee_id = manager_id
WHERE CONNECT_BY_ISLEAF = 1;
-- CONNECT_BY_ISLEAF = 1 means this row has no children pointing manager_id back at it.

-- 5.
WITH org_chart (employee_id, last_name, lvl) AS (
   SELECT employee_id, last_name, 1
   FROM employees
   WHERE manager_id IS NULL
   UNION ALL
   SELECT e.employee_id, e.last_name, oc.lvl + 1
   FROM employees e
   JOIN org_chart oc ON e.manager_id = oc.employee_id
)
SELECT lvl, LPAD(' ', 2*(lvl-1)) || last_name AS org_chart
FROM org_chart
ORDER BY lvl;
-- UNION ALL between the anchor (root) and recursive member reconstructs the same tree CONNECT BY walks.
```

## Debug / Optimize Challenge

This query is meant to find, for every individual contributor, their
department head's name. It runs without error, but every row comes back
with `department_head = 'Chen'` (the CEO's last name) instead of the
actual department head.

```sql
-- BROKEN
SELECT employee_id, last_name,
       CONNECT_BY_ROOT last_name AS department_head
FROM employees
START WITH manager_id IS NULL
CONNECT BY PRIOR employee_id = manager_id
WHERE employee_id >= 1000;
```

**Fix — root the tree at each department head instead of the CEO:**

```sql
SELECT employee_id, last_name,
       CONNECT_BY_ROOT last_name AS department_head
FROM employees
START WITH employee_id BETWEEN 200 AND 299
CONNECT BY PRIOR employee_id = manager_id
WHERE employee_id >= 1000;
```

`CONNECT_BY_ROOT` returns the root-row value **of whatever `START WITH`
declared as the root** — it has no idea "department head" is what you
meant. With `START WITH manager_id IS NULL`, the root of every tree is the
CEO, so `CONNECT_BY_ROOT last_name` correctly, but unhelpfully, returns
the CEO's name for every single row. Changing `START WITH` to start from
each department head (`employee_id BETWEEN 200 AND 299`) makes those rows
the roots instead, so `CONNECT_BY_ROOT` now returns what was actually
wanted. The lesson: `CONNECT_BY_ROOT`/`LEVEL`/`SYS_CONNECT_BY_PATH` are
only ever relative to whatever `START WITH` picked as the root — get the
root wrong and every one of these functions is "correct" but useless.

---

⬅️ Previous: [Lab 08 — Subqueries, CTEs, Set Operators](../lab08-subqueries-ctes-set-ops/)
➡️ Next: [Lab 10 — EXPLAIN PLAN / DBMS_XPLAN](../lab10-explain-plan/)
