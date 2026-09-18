# Oracle SQL Labs 🐘

A hands-on course for going from "I can write `SELECT * FROM table`" to
professionally competent Oracle SQL — including the parts most SQL courses
skip: `LISTAGG`/`XMLAGG`, analytic (window) functions, `ROWNUM` vs
`ROW_NUMBER`, execution plans, index access paths, and optimizer hints like
`LEADING`.

No local Oracle install required — see **Setup** below.

## Who this is for

You know basic `SELECT` / `WHERE` already, but you're new to SQL as a
profession and need to work against a real Oracle database through a
company IDE. This course is written against **real Oracle** (via Oracle
Live SQL), not a SQLite/Postgres stand-in — Oracle-specific syntax and
behavior (hints, `DUAL`, analytic function frames, `(+)` join syntax) works
exactly like it will at work.

## How each lab is structured

Every lab folder has one `README.md` with the same six sections:

1. **Concept** — what the feature is and why it exists
2. **Syntax** — the reference syntax, spelled out
3. **Scenario** — a realistic situation where you'd reach for it
4. **Common Pitfalls** — mistakes people actually make, shown as wrong-SQL
   vs right-SQL side by side, with *why* the wrong one is wrong
5. **Hands-on Practice** — exercises against the shared schema (below),
   with an answer key
6. **Debug / Optimize Challenge** — a broken or inefficient query for you
   to fix, with the fix explained

Work through labs **in order** — later labs assume the schema and concepts
from earlier ones.

## Setup

No Docker, no local install. Use **[Oracle Live SQL](https://livesql.oracle.com)**
(free, official, runs on real Oracle Database — sign in with a free Oracle
account). Start with **[Lab 00](lab00-setup/)**, which walks you through:

1. Creating a Live SQL account and opening the SQL Worksheet
2. Running `schema/01_create_tables.sql` then `schema/02_seed_data.sql`
   (also described in [`schema/README.md`](schema/README.md))
3. Running a sanity-check query to confirm the data loaded

If your company gives you a real Oracle connection later (via SQL Developer,
DBeaver, or a VS Code Oracle extension), the exact same scripts and every
lab in this course work unchanged — Live SQL is just the free way to
practice before you have that access.

## Lab index

**Module 0 — Setup**
| Lab | Topic |
|---|---|
| [Lab 00](lab00-setup/) | Oracle Live SQL account, schema, seed data |

**Module 1 — Foundations**
| Lab | Topic |
|---|---|
| [Lab 01](lab01-select-where/) | `SELECT` / `WHERE` / operators / `NULL` / `ORDER BY` |
| [Lab 02](lab02-dual-pseudocolumns/) | `DUAL`, pseudo-columns, `SYSDATE`, sequences, `TO_CHAR`/`TO_DATE` |

**Module 2 — Aggregation & Strings**
| Lab | Topic |
|---|---|
| [Lab 03](lab03-group-by-aggregates/) | `GROUP BY` / `HAVING` / `MAX`/`MIN`/`SUM`/`AVG`/`COUNT` |
| [Lab 04](lab04-listagg-xmlagg/) | `LISTAGG`, `XMLAGG`, `REGEXP_*` |

**Module 3 — Window & Ranking**
| Lab | Topic |
|---|---|
| [Lab 05](lab05-analytic-window/) | Analytic functions: `OVER`, `PARTITION BY`, frame clauses |
| [Lab 06](lab06-ranking-rownum/) | `RANK`, `DENSE_RANK`, `ROW_NUMBER`, `ROWNUM` vs `ROW_NUMBER`, top-N |

**Module 4 — Joins & Set Logic**
| Lab | Topic |
|---|---|
| [Lab 07](lab07-joins/) | Inner/outer/self/cross joins, ANSI vs Oracle `(+)` syntax |
| [Lab 08](lab08-subqueries-ctes-set-ops/) | Subqueries, `WITH` (CTEs), `UNION`/`INTERSECT`/`MINUS` |
| [Lab 09](lab09-hierarchical-connect-by/) | `CONNECT BY PRIOR`, `START WITH`, `LEVEL` |

**Module 5 — Performance & Indexing**
| Lab | Topic |
|---|---|
| [Lab 10](lab10-explain-plan/) | `EXPLAIN PLAN`, `DBMS_XPLAN.DISPLAY`, reading a plan |
| [Lab 11](lab11-index-access-paths/) | Full scan vs index range/unique/skip scan |
| [Lab 12](lab12-hints-leading/) | Hints: `LEADING`, `USE_NL`/`USE_HASH`, `INDEX`, `FULL` |
| [Lab 13](lab13-bind-variables/) | Bind variables, hard parses, cursor sharing |

**Module 6 — Advanced**
| Lab | Topic |
|---|---|
| [Lab 14](lab14-merge-transactions/) | `MERGE` (upsert), transactions, locking basics |
| [Lab 15](lab15-pivot-json/) | `PIVOT`/`UNPIVOT`, `JSON_TABLE`, JSON functions |
| [Lab 16](lab16-plsql-basics/) | PL/SQL: anonymous blocks, cursors, `BULK COLLECT`/`FORALL` |
| [Lab 17](lab17-capstone-tuning/) | **Capstone** — diagnose and fix a slow real-world query |

## Shared schema

All labs query the same small sales system (departments/employees with a
manager hierarchy, customers, products, orders, order line items). Full
details, ER diagram, and column reference: [`schema/README.md`](schema/README.md).
