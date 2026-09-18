-- ============================================================
-- oracle-sql-labs shared schema
-- Run this ONCE (Lab 00) before starting any other lab.
-- Models a small sales system: departments/employees (with a
-- manager hierarchy) selling products to customers via orders.
-- ============================================================

-- Clean slate if re-running -----------------------------------
BEGIN
   FOR t IN (SELECT table_name FROM user_tables
             WHERE table_name IN ('ORDER_ITEMS','ORDERS','EMPLOYEES',
                                   'DEPARTMENTS','PRODUCTS','CUSTOMERS'))
   LOOP
      EXECUTE IMMEDIATE 'DROP TABLE ' || t.table_name || ' CASCADE CONSTRAINTS PURGE';
   END LOOP;
END;
/

CREATE TABLE departments (
   department_id    NUMBER(4)      NOT NULL,
   department_name  VARCHAR2(50)   NOT NULL,
   location         VARCHAR2(50),
   CONSTRAINT pk_departments PRIMARY KEY (department_id)
);

CREATE TABLE employees (
   employee_id      NUMBER(6)      NOT NULL,
   first_name       VARCHAR2(30),
   last_name        VARCHAR2(30)   NOT NULL,
   email            VARCHAR2(60)   NOT NULL,
   hire_date        DATE           NOT NULL,
   job_title        VARCHAR2(40)   NOT NULL,
   salary           NUMBER(10,2)   NOT NULL,
   commission_pct   NUMBER(4,2),
   department_id    NUMBER(4),
   manager_id       NUMBER(6),
   CONSTRAINT pk_employees PRIMARY KEY (employee_id),
   CONSTRAINT fk_emp_dept FOREIGN KEY (department_id) REFERENCES departments(department_id),
   CONSTRAINT fk_emp_mgr  FOREIGN KEY (manager_id) REFERENCES employees(employee_id)
);

CREATE TABLE customers (
   customer_id      NUMBER(6)      NOT NULL,
   customer_name    VARCHAR2(60)   NOT NULL,
   email            VARCHAR2(60),
   country          VARCHAR2(40)   NOT NULL,
   signup_date      DATE           NOT NULL,
   CONSTRAINT pk_customers PRIMARY KEY (customer_id)
);

CREATE TABLE products (
   product_id       NUMBER(6)      NOT NULL,
   product_name     VARCHAR2(60)   NOT NULL,
   category         VARCHAR2(40)   NOT NULL,
   unit_price       NUMBER(10,2)   NOT NULL,
   CONSTRAINT pk_products PRIMARY KEY (product_id)
);

CREATE TABLE orders (
   order_id         NUMBER(8)      NOT NULL,
   customer_id      NUMBER(6)      NOT NULL,
   employee_id      NUMBER(6),
   order_date       DATE           NOT NULL,
   status           VARCHAR2(20)   NOT NULL,
   CONSTRAINT pk_orders PRIMARY KEY (order_id),
   CONSTRAINT fk_ord_cust FOREIGN KEY (customer_id) REFERENCES customers(customer_id),
   CONSTRAINT fk_ord_emp  FOREIGN KEY (employee_id) REFERENCES employees(employee_id),
   CONSTRAINT ck_ord_status CHECK (status IN ('PENDING','SHIPPED','CANCELLED','COMPLETED'))
);

CREATE TABLE order_items (
   order_id         NUMBER(8)      NOT NULL,
   line_no          NUMBER(3)      NOT NULL,
   product_id       NUMBER(6)      NOT NULL,
   quantity         NUMBER(5)      NOT NULL,
   unit_price       NUMBER(10,2)   NOT NULL,
   CONSTRAINT pk_order_items PRIMARY KEY (order_id, line_no),
   CONSTRAINT fk_oi_order   FOREIGN KEY (order_id) REFERENCES orders(order_id),
   CONSTRAINT fk_oi_product FOREIGN KEY (product_id) REFERENCES products(product_id)
);

COMMIT;
