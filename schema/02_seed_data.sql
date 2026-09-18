-- ============================================================
-- oracle-sql-labs seed data
-- Run AFTER 01_create_tables.sql.
-- Volumes are large enough (orders/order_items) that the
-- optimizer's choice between full scans and index scans in
-- Module 5 is real, not simulated.
-- ============================================================

-- 1. Departments -------------------------------------------------
INSERT INTO departments (department_id, department_name, location)
SELECT 10, 'Sales', 'Taipei' FROM dual UNION ALL
SELECT 20, 'Marketing', 'Taipei' FROM dual UNION ALL
SELECT 30, 'Engineering', 'Hsinchu' FROM dual UNION ALL
SELECT 40, 'Support', 'Hsinchu' FROM dual UNION ALL
SELECT 50, 'Finance', 'Taipei' FROM dual UNION ALL
SELECT 60, 'HR', 'Taipei' FROM dual UNION ALL
SELECT 70, 'Logistics', 'Taichung' FROM dual UNION ALL
SELECT 80, 'Executive', 'Taipei' FROM dual;

-- 2. Employees: a small manager hierarchy ------------------------
-- 1 CEO -> department heads (one per dept) -> individual contributors
INSERT INTO employees (employee_id, first_name, last_name, email, hire_date,
                        job_title, salary, commission_pct, department_id, manager_id)
VALUES (100, 'Alice', 'Chen', 'alice.chen@example.com', DATE '2015-01-05',
        'CEO', 25000, NULL, 80, NULL);

INSERT INTO employees (employee_id, first_name, last_name, email, hire_date,
                        job_title, salary, commission_pct, department_id, manager_id)
SELECT 200 + department_id,
       'Head', department_name,
       LOWER('head.' || department_name) || '@example.com',
       DATE '2016-03-01' + department_id,
       'Department Head', 15000 + department_id * 20, NULL,
       department_id, 100
FROM departments;

-- Individual contributors: ~5 per department, reporting to that dept's head
INSERT INTO employees (employee_id, first_name, last_name, email, hire_date,
                        job_title, salary, commission_pct, department_id, manager_id)
SELECT 1000 + (d.department_id * 10) + rn,
       'Emp' || (d.department_id * 10 + rn),
       INITCAP(d.department_name),
       'emp' || (d.department_id * 10 + rn) || '@example.com',
       DATE '2018-01-01' + TRUNC(DBMS_RANDOM.VALUE(0, 2000)),
       CASE d.department_id WHEN 10 THEN 'Sales Rep'
                             WHEN 30 THEN 'Software Engineer'
                             WHEN 40 THEN 'Support Engineer'
                             ELSE 'Analyst' END,
       ROUND(DBMS_RANDOM.VALUE(3500, 9500), 2),
       CASE WHEN d.department_id = 10 THEN ROUND(DBMS_RANDOM.VALUE(0.05, 0.25), 2) ELSE NULL END,
       d.department_id,
       200 + d.department_id
FROM departments d
CROSS JOIN (SELECT LEVEL rn FROM dual CONNECT BY LEVEL <= 5) r;

-- 3. Customers (500) ----------------------------------------------
INSERT INTO customers (customer_id, customer_name, email, country, signup_date)
SELECT LEVEL,
       'Customer ' || LEVEL,
       'customer' || LEVEL || '@example.com',
       CASE MOD(LEVEL, 6)
            WHEN 0 THEN 'Taiwan' WHEN 1 THEN 'Japan' WHEN 2 THEN 'USA'
            WHEN 3 THEN 'Germany' WHEN 4 THEN 'Vietnam' ELSE 'Singapore' END,
       DATE '2021-01-01' + TRUNC(DBMS_RANDOM.VALUE(0, 1400))
FROM dual CONNECT BY LEVEL <= 500;

-- 4. Products (100) -------------------------------------------------
INSERT INTO products (product_id, product_name, category, unit_price)
SELECT LEVEL,
       'Product ' || LEVEL,
       CASE MOD(LEVEL, 5)
            WHEN 0 THEN 'Electronics' WHEN 1 THEN 'Home' WHEN 2 THEN 'Office'
            WHEN 3 THEN 'Outdoor' ELSE 'Toys' END,
       ROUND(DBMS_RANDOM.VALUE(5, 500), 2)
FROM dual CONNECT BY LEVEL <= 100;

-- 5. Orders (10,000), spread over ~3 years -------------------------
-- Note: no index on customer_id / order_date / employee_id yet on
-- purpose -- Module 5 (Lab 11/12) is where you add them and watch
-- the execution plan change.
INSERT INTO orders (order_id, customer_id, employee_id, order_date, status)
SELECT LEVEL,
       TRUNC(DBMS_RANDOM.VALUE(1, 501)),
       CASE WHEN DBMS_RANDOM.VALUE < 0.9
            THEN (SELECT employee_id FROM (
                     SELECT employee_id FROM employees WHERE department_id = 10
                     ORDER BY DBMS_RANDOM.VALUE) WHERE ROWNUM = 1)
            ELSE NULL END,
       DATE '2023-01-01' + TRUNC(DBMS_RANDOM.VALUE(0, 1000)),
       CASE TRUNC(DBMS_RANDOM.VALUE(1, 11))
            WHEN 1 THEN 'PENDING'
            WHEN 2 THEN 'CANCELLED'
            WHEN 3 THEN 'SHIPPED'
            ELSE 'COMPLETED' END
FROM dual CONNECT BY LEVEL <= 10000;

COMMIT;

-- 6. Order items: 1-5 lines per order, ~25,000 rows total ----------
-- Written with BULK COLLECT + FORALL on purpose -- this is the
-- exact pattern Lab 16 (PL/SQL basics) teaches you to write.
DECLARE
   TYPE t_num_tab IS TABLE OF NUMBER INDEX BY PLS_INTEGER;
   l_order_id   t_num_tab;
   l_line_no    t_num_tab;
   l_product_id t_num_tab;
   l_qty        t_num_tab;
   l_price      t_num_tab;
   l_price_of   t_num_tab;  -- product_id -> unit_price lookup
   l_idx        PLS_INTEGER := 0;
   l_items      PLS_INTEGER;
   l_pid        PLS_INTEGER;
BEGIN
   FOR p IN (SELECT product_id, unit_price FROM products) LOOP
      l_price_of(p.product_id) := p.unit_price;
   END LOOP;

   FOR o IN (SELECT order_id FROM orders) LOOP
      l_items := TRUNC(DBMS_RANDOM.VALUE(1, 6));
      FOR i IN 1..l_items LOOP
         l_idx := l_idx + 1;
         l_pid := TRUNC(DBMS_RANDOM.VALUE(1, 101));
         l_order_id(l_idx)   := o.order_id;
         l_line_no(l_idx)    := i;
         l_product_id(l_idx) := l_pid;
         l_qty(l_idx)        := TRUNC(DBMS_RANDOM.VALUE(1, 6));
         l_price(l_idx)      := l_price_of(l_pid);
      END LOOP;
   END LOOP;

   FORALL j IN 1..l_idx
      INSERT INTO order_items (order_id, line_no, product_id, quantity, unit_price)
      VALUES (l_order_id(j), l_line_no(j), l_product_id(j), l_qty(j), l_price(j));

   COMMIT;
   DBMS_OUTPUT.PUT_LINE('Inserted ' || l_idx || ' order_items rows.');
END;
/

-- 7. Sanity check ----------------------------------------------------
SELECT 'departments' tbl, COUNT(*) rows_ FROM departments UNION ALL
SELECT 'employees',        COUNT(*) FROM employees UNION ALL
SELECT 'customers',        COUNT(*) FROM customers UNION ALL
SELECT 'products',         COUNT(*) FROM products UNION ALL
SELECT 'orders',           COUNT(*) FROM orders UNION ALL
SELECT 'order_items',      COUNT(*) FROM order_items;
