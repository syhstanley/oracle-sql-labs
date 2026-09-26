-- ============================================================
-- oracle-sql-labs seed data
-- Run AFTER 01_create_tables.sql.
--
-- The data is DETERMINISTIC: there is no DBMS_RANDOM anywhere, so
-- every learner who runs this script gets exactly the same rows and
-- the same query results. The "random-looking" parts (orders and
-- order_items) come from a small integer hash, LAB_RND, created
-- below and dropped again at the end.
--
-- Volumes (10,000 orders / ~30,000 order_items) are large enough that
-- the optimizer's choice between full scans and index scans in
-- Module 5 is real, not simulated.
--
-- The data also has a few deliberate features the labs rely on
-- (customers who never ordered, a category that never sold, NULL and
-- malformed emails, price/salary ties, ...). They're listed in
-- schema/README.md under "Data features the labs rely on".
-- ============================================================

-- 0. Helper: deterministic pseudo-random integer in [0, 2147483646] ----
CREATE OR REPLACE FUNCTION lab_rnd (p_n IN NUMBER, p_salt IN NUMBER)
   RETURN NUMBER DETERMINISTIC
IS
   c_m CONSTANT NUMBER := 2147483647;
   x   NUMBER;
BEGIN
   x := MOD(p_n * 7919 + p_salt * 104729 + 12345, c_m);
   x := MOD(x * x, c_m);
   x := MOD(x * 48271 + p_salt, c_m);
   x := MOD(x * x + 7, c_m);
   RETURN x;
END lab_rnd;
/

-- 1. Departments ---------------------------------------------------
-- Research (90) has no employees yet -- useful for LEFT JOIN demos.
INSERT INTO departments (department_id, department_name, location)
SELECT 10, 'Sales',        'Taipei' FROM dual UNION ALL
SELECT 20, 'Marketing',    'Taipei' FROM dual UNION ALL
SELECT 30, 'Engineering',  'Hsinchu' FROM dual UNION ALL
SELECT 40, 'Support',      'Hsinchu' FROM dual UNION ALL
SELECT 50, 'Finance',      'Taipei' FROM dual UNION ALL
SELECT 60, 'HR',           'Taipei' FROM dual UNION ALL
SELECT 70, 'Logistics',    'Taichung' FROM dual UNION ALL
SELECT 80, 'Executive',    'Taipei' FROM dual UNION ALL
SELECT 90, 'Research',     'Kaohsiung' FROM dual;

-- 2. Employees: CEO -> department heads -> staff ------------------
-- 100 = CEO, 2xx = department heads (200 + department_id),
-- 1001+ = everyone else. Engineering has a 4th level: Tech Lead 1017
-- manages six of the engineers.
-- Sales (dept 10) reps carry a commission_pct; everyone else is NULL,
-- except rep 1009 who is on a 0% plan and trainee 1012 who has none.
INSERT INTO employees (employee_id, first_name, last_name, email, hire_date,
                       job_title, salary, commission_pct, department_id, manager_id)
SELECT  100, 'Alice',    'Chen',    'alice.chen@example.com',     DATE '2015-01-05', 'CEO',                       25000, NULL, 80, NULL FROM dual UNION ALL
SELECT  210, 'Brian',    'Wang',    'brian.wang@example.com',     DATE '2016-03-01', 'Sales Director',            13000, NULL, 10, 100 FROM dual UNION ALL
SELECT  220, 'Cindy',    'Huang',   'cindy.huang@example.com',    DATE '2016-05-16', 'Marketing Director',        11500, NULL, 20, 100 FROM dual UNION ALL
SELECT  230, 'David',    'Liu',     'david.liu@example.com',      DATE '2016-02-15', 'Engineering Director',      15000, NULL, 30, 100 FROM dual UNION ALL
SELECT  240, 'Emily',    'Tsai',    'emily.tsai@example.com',     DATE '2017-01-09', 'Support Manager',           10500, NULL, 40, 100 FROM dual UNION ALL
SELECT  250, 'Frank',    'Yang',    'frank.yang@example.com',     DATE '2016-08-01', 'Finance Director',          12500, NULL, 50, 100 FROM dual UNION ALL
SELECT  260, 'Grace',    'Hsu',     'grace.hsu@example.com',      DATE '2017-04-03', 'HR Manager',                10000, NULL, 60, 100 FROM dual UNION ALL
SELECT  270, 'Henry',    'Wu',      'henry.wu@example.com',       DATE '2018-06-11', 'Logistics Manager',         10000, NULL, 70, 100 FROM dual UNION ALL
SELECT  280, 'Irene',    'Kuo',     'irene.kuo@example.com',      DATE '2015-09-01', 'Chief Operating Officer',   18000, NULL, 80, 100 FROM dual UNION ALL
SELECT 1001, 'Kevin',    'Lin',     'kevin.lin@example.com',      DATE '2018-03-12', 'Sales Rep',                  6500, 0.10, 10, 210 FROM dual UNION ALL
SELECT 1002, 'Linda',    'Chang',   'linda.chang@example.com',    DATE '2017-07-03', 'Senior Sales Rep',           8800, 0.15, 10, 210 FROM dual UNION ALL
SELECT 1003, 'Michael',  'Lee',     'michael.lee@example.com',    DATE '2019-02-18', 'Sales Rep',                  7200, 0.12, 10, 210 FROM dual UNION ALL
SELECT 1004, 'Nancy',    'Chou',    'nancy.chou@example.com',     DATE '2019-10-07', 'Sales Rep',                  7200, 0.10, 10, 210 FROM dual UNION ALL
SELECT 1005, 'Oscar',    'Lai',     'oscar.lai@example.com',      DATE '2020-05-04', 'Sales Rep',                  6900, 0.08, 10, 210 FROM dual UNION ALL
SELECT 1006, 'Peggy',    'Hung',    'peggy.hung@example.com',     DATE '2016-11-21', 'Senior Sales Rep',           8800, 0.15, 10, 210 FROM dual UNION ALL
SELECT 1007, 'Quentin',  'Ho',      'quentin.ho@example.com',     DATE '2021-01-11', 'Sales Rep',                  6800, 0.10, 10, 210 FROM dual UNION ALL
SELECT 1008, 'Rachel',   'Cheng',   'rachel.cheng@example.com',   DATE '2021-08-16', 'Sales Rep',                  7500, 0.12, 10, 210 FROM dual UNION ALL
SELECT 1009, 'Steven',   'Lu',      'steven.lu@example.com',      DATE '2022-03-07', 'Sales Rep',                  7000, 0.00, 10, 210 FROM dual UNION ALL
SELECT 1010, 'Tina',     'Kao',     'tina.kao@example.com',       DATE '2024-03-04', 'Sales Rep',                  6200, 0.05, 10, 210 FROM dual UNION ALL
SELECT 1011, 'Victor',   'Su',      'victor.su@example.com',      DATE '2024-07-15', 'Sales Rep',                  6000, 0.05, 10, 210 FROM dual UNION ALL
SELECT 1012, 'Wendy',    'Chiu',    'wendy.chiu@example.com',     DATE '2025-09-15', 'Sales Trainee',              4800, NULL, 10, 210 FROM dual UNION ALL
SELECT 1013, 'Amy',      'Chao',    'amy.chao@example.com',       DATE '2019-04-15', 'Marketing Specialist',       6400, NULL, 20, 220 FROM dual UNION ALL
SELECT 1014, 'Ben',      'Tseng',   'ben.tseng@example.com',      DATE '2021-06-01', 'Content Writer',             5600, NULL, 20, 220 FROM dual UNION ALL
SELECT 1015, 'Chloe',    'Pan',     'chloe.pan@example.com',      DATE '2022-09-19', 'Marketing Analyst',          6100, NULL, 20, 220 FROM dual UNION ALL
SELECT 1016, 'Derek',    'Fang',    'derek.fang@example.com',     DATE '2018-02-05', 'Brand Manager',              8200, NULL, 20, 220 FROM dual UNION ALL
SELECT 1017, 'Ethan',    'Hsieh',   'ethan.hsieh@example.com',    DATE '2017-03-20', 'Tech Lead',                 12000, NULL, 30, 230 FROM dual UNION ALL
SELECT 1018, 'Fiona',    'Yeh',     'fiona.yeh@example.com',      DATE '2018-08-13', 'Senior Software Engineer',  10500, NULL, 30, 1017 FROM dual UNION ALL
SELECT 1019, 'George',   'Lo',      'george.lo@example.com',      DATE '2020-01-06', 'Software Engineer',          9000, NULL, 30, 1017 FROM dual UNION ALL
SELECT 1020, 'Hannah',   'Shih',    'hannah.shih@example.com',    DATE '2021-04-12', 'Software Engineer',          8800, NULL, 30, 1017 FROM dual UNION ALL
SELECT 1021, 'Ian',      'Tang',    'ian.tang@example.com',       DATE '2022-07-18', 'Software Engineer',          8500, NULL, 30, 1017 FROM dual UNION ALL
SELECT 1022, 'Julia',    'Weng',    'julia.weng@example.com',     DATE '2023-02-13', 'Software Engineer',          8500, NULL, 30, 1017 FROM dual UNION ALL
SELECT 1023, 'Kelvin',   'Fan',     'kelvin.fan@example.com',     DATE '2019-05-27', 'Senior Software Engineer',  10500, NULL, 30, 230 FROM dual UNION ALL
SELECT 1024, 'Lily',     'Chu',     'lily.chu@example.com',       DATE '2020-10-05', 'QA Engineer',                7400, NULL, 30, 230 FROM dual UNION ALL
SELECT 1025, 'Marcus',   'Yu',      'marcus.yu@example.com',      DATE '2021-11-22', 'DevOps Engineer',            9800, NULL, 30, 230 FROM dual UNION ALL
SELECT 1026, 'Nina',     'Hou',     'nina.hou@example.com',       DATE '2024-09-02', 'Software Engineer',          8000, NULL, 30, 1017 FROM dual UNION ALL
SELECT 1027, 'Oliver',   'Chien',   'oliver.chien@example.com',   DATE '2019-08-19', 'Support Engineer',           6200, NULL, 40, 240 FROM dual UNION ALL
SELECT 1028, 'Paula',    'Tu',      'paula.tu@example.com',       DATE '2020-06-15', 'Support Engineer',           5800, NULL, 40, 240 FROM dual UNION ALL
SELECT 1029, 'Ryan',     'Kang',    'ryan.kang@example.com',      DATE '2022-01-10', 'Support Engineer',           5500, NULL, 40, 240 FROM dual UNION ALL
SELECT 1030, 'Sandy',    'Liao',    'sandy.liao@example.com',     DATE '2023-05-22', 'Support Engineer',           5200, NULL, 40, 240 FROM dual UNION ALL
SELECT 1031, 'Tony',     'Hsiao',   'tony.hsiao@example.com',     DATE '2021-03-08', 'Support Engineer',           5800, NULL, 40, 240 FROM dual UNION ALL
SELECT 1032, 'Uma',      'Peng',    'uma.peng@example.com',       DATE '2018-10-01', 'Accountant',                 7000, NULL, 50, 250 FROM dual UNION ALL
SELECT 1033, 'Vincent',  'Chiang',  'vincent.chiang@example.com', DATE '2020-02-17', 'Financial Analyst',          7600, NULL, 50, 250 FROM dual UNION ALL
SELECT 1034, 'Wanda',    'Jian',    'wanda.jian@example.com',     DATE '2023-08-07', 'Accountant',                 6300, NULL, 50, 250 FROM dual UNION ALL
SELECT 1035, 'Xavier',   'Yen',     'xavier.yen@example.com',     DATE '2019-12-02', 'HR Specialist',              5900, NULL, 60, 260 FROM dual UNION ALL
SELECT 1036, 'Yvonne',   'Lan',     'yvonne.lan@example.com',     DATE '2022-04-18', 'Recruiter',                  5400, NULL, 60, 260 FROM dual UNION ALL
SELECT 1037, 'Zack',     'Pai',     'zack.pai@example.com',       DATE '2024-01-15', 'HR Specialist',              5100, NULL, 60, 260 FROM dual UNION ALL
SELECT 1038, 'Aaron',    'Lin',     'aaron.lin@example.com',      DATE '2018-05-14', 'Warehouse Supervisor',       6800, NULL, 70, 270 FROM dual UNION ALL
SELECT 1039, 'Bella',    'Ma',      'bella.ma@example.com',       DATE '2020-09-07', 'Logistics Coordinator',      5600, NULL, 70, 270 FROM dual UNION ALL
SELECT 1040, 'Carl',     'Hsu',     'carl.hsu@example.com',       DATE '2021-02-22', 'Driver',                     4900, NULL, 70, 270 FROM dual UNION ALL
SELECT 1041, 'Diana',    'Ou',      'diana.ou@example.com',       DATE '2022-11-14', 'Inventory Analyst',          5800, NULL, 70, 270 FROM dual UNION ALL
SELECT 1042, 'Edward',   'Mo',      'edward.mo@example.com',      DATE '2023-06-26', 'Driver',                     4900, NULL, 70, 270 FROM dual UNION ALL
SELECT 1043, 'Flora',    'Ning',    'flora.ning@example.com',     DATE '2019-01-21', 'Executive Assistant',        5800, NULL, 80, 280 FROM dual;

-- 3. Products (104) ------------------------------------------------
-- 5 established categories of 20 products each, plus a brand-new
-- 'Garden' line (101-104) that has never been ordered.
INSERT INTO products (product_id, product_name, category, unit_price)
SELECT   1, 'Wireless Mouse',                    'Electronics',  24.99 FROM dual UNION ALL
SELECT   2, 'Mechanical Keyboard',               'Electronics',  89.00 FROM dual UNION ALL
SELECT   3, 'USB-C Hub 7-in-1',                  'Electronics',  45.50 FROM dual UNION ALL
SELECT   4, '27-inch 4K Monitor',                'Electronics', 399.00 FROM dual UNION ALL
SELECT   5, 'Noise-Cancelling Headphones',       'Electronics', 249.00 FROM dual UNION ALL
SELECT   6, 'Bluetooth Speaker',                 'Electronics',  59.90 FROM dual UNION ALL
SELECT   7, 'Webcam 1080p',                      'Electronics',  50.00 FROM dual UNION ALL
SELECT   8, 'Portable SSD 1TB',                  'Electronics', 129.00 FROM dual UNION ALL
SELECT   9, 'Smartwatch',                        'Electronics', 199.00 FROM dual UNION ALL
SELECT  10, 'Wireless Earbuds',                  'Electronics', 129.00 FROM dual UNION ALL
SELECT  11, 'HDMI Cable 2m',                     'Electronics',   9.99 FROM dual UNION ALL
SELECT  12, 'Power Bank 20000mAh',               'Electronics',  39.90 FROM dual UNION ALL
SELECT  13, 'Tablet 10-inch',                    'Electronics', 329.00 FROM dual UNION ALL
SELECT  14, 'Smart Plug 2-pack',                 'Electronics',  29.99 FROM dual UNION ALL
SELECT  15, 'Gaming Laptop 15-inch',             'Electronics', 899.00 FROM dual UNION ALL
SELECT  16, 'Mirrorless Camera Body',            'Electronics', 899.00 FROM dual UNION ALL
SELECT  17, 'E-Reader',                          'Electronics', 139.00 FROM dual UNION ALL
SELECT  18, 'Wi-Fi 6 Router',                    'Electronics', 149.00 FROM dual UNION ALL
SELECT  19, 'USB Flash Drive 128GB',             'Electronics',  19.99 FROM dual UNION ALL
SELECT  20, 'Graphics Tablet',                   'Electronics',  79.00 FROM dual UNION ALL
SELECT  21, 'Ceramic Mug Set',                   'Home',         18.50 FROM dual UNION ALL
SELECT  22, 'Stainless Steel Kettle',            'Home',         35.00 FROM dual UNION ALL
SELECT  23, 'Cotton Bath Towel',                 'Home',         12.99 FROM dual UNION ALL
SELECT  24, 'Memory Foam Pillow',                'Home',         45.00 FROM dual UNION ALL
SELECT  25, 'Bedside Lamp',                      'Home',         32.00 FROM dual UNION ALL
SELECT  26, 'Air Purifier',                      'Home',        219.00 FROM dual UNION ALL
SELECT  27, 'Robot Vacuum',                      'Home',        249.00 FROM dual UNION ALL
SELECT  28, 'Non-stick Frying Pan',              'Home',         29.90 FROM dual UNION ALL
SELECT  29, 'Chef Knife 8-inch',                 'Home',         59.00 FROM dual UNION ALL
SELECT  30, 'Bamboo Cutting Board',              'Home',         22.00 FROM dual UNION ALL
SELECT  31, 'Blender 1.5L',                      'Home',         79.00 FROM dual UNION ALL
SELECT  32, 'Rice Cooker 6-cup',                 'Home',        119.00 FROM dual UNION ALL
SELECT  33, 'Scented Candle',                    'Home',          9.99 FROM dual UNION ALL
SELECT  34, 'Storage Basket Set',                'Home',         27.50 FROM dual UNION ALL
SELECT  35, 'Wall Clock',                        'Home',         25.00 FROM dual UNION ALL
SELECT  36, 'Coffee Maker',                      'Home',         89.00 FROM dual UNION ALL
SELECT  37, 'Filter Paper 100-pack for Coffee',  'Home',          4.99 FROM dual UNION ALL
SELECT  38, 'Duvet Cover Queen',                 'Home',         65.00 FROM dual UNION ALL
SELECT  39, 'Electric Fan',                      'Home',         49.00 FROM dual UNION ALL
SELECT  40, 'Dish Rack',                         'Home',         24.00 FROM dual UNION ALL
SELECT  41, 'Ballpoint Pens 12-pack',            'Office',        5.99 FROM dual UNION ALL
SELECT  42, 'A4 Copy Paper 500 Sheets',          'Office',        6.50 FROM dual UNION ALL
SELECT  43, 'Stapler',                           'Office',       11.00 FROM dual UNION ALL
SELECT  44, 'Ergonomic Office Chair',            'Office',      289.00 FROM dual UNION ALL
SELECT  45, 'Standing Desk',                     'Office',      349.00 FROM dual UNION ALL
SELECT  46, 'Whiteboard 90x60cm',                'Office',       75.00 FROM dual UNION ALL
SELECT  47, 'Label Printer',                     'Office',      119.00 FROM dual UNION ALL
SELECT  48, 'Desk Organizer',                    'Office',       19.90 FROM dual UNION ALL
SELECT  49, 'Paper Shredder',                    'Office',      150.00 FROM dual UNION ALL
SELECT  50, 'Notebook A5 3-pack',                'Office',        8.90 FROM dual UNION ALL
SELECT  51, 'Laser Printer',                     'Office',      200.00 FROM dual UNION ALL
SELECT  52, 'Monitor Arm',                       'Office',       89.00 FROM dual UNION ALL
SELECT  53, 'Filing Cabinet 3-drawer',           'Office',      179.00 FROM dual UNION ALL
SELECT  54, 'Sticky Notes 12-pack',              'Office',        7.50 FROM dual UNION ALL
SELECT  55, 'Laptop Stand',                      'Office',       49.00 FROM dual UNION ALL
SELECT  56, 'Document Scanner',                  'Office',      229.00 FROM dual UNION ALL
SELECT  57, 'Highlighters 6-pack',               'Office',        4.50 FROM dual UNION ALL
SELECT  58, 'Desk Calculator',                   'Office',       15.00 FROM dual UNION ALL
SELECT  59, 'Clearance Tag Roll 100%_off',       'Office',        3.99 FROM dual UNION ALL
SELECT  60, 'Conference Speakerphone',           'Office',      139.00 FROM dual UNION ALL
SELECT  61, 'Camping Tent 4-person',             'Outdoor',     189.00 FROM dual UNION ALL
SELECT  62, 'Sleeping Bag',                      'Outdoor',      79.00 FROM dual UNION ALL
SELECT  63, 'Hiking Backpack 40L',               'Outdoor',      99.00 FROM dual UNION ALL
SELECT  64, 'Trekking Poles',                    'Outdoor',      45.00 FROM dual UNION ALL
SELECT  65, 'Water Bottle 1L',                   'Outdoor',      19.00 FROM dual UNION ALL
SELECT  66, 'Camping Stove',                     'Outdoor',      55.00 FROM dual UNION ALL
SELECT  67, 'Headlamp',                          'Outdoor',      25.00 FROM dual UNION ALL
SELECT  68, 'Folding Camp Chair',                'Outdoor',      39.00 FROM dual UNION ALL
SELECT  69, 'Cooler Box 35L',                    'Outdoor',     129.00 FROM dual UNION ALL
SELECT  70, 'Mountain Bike',                     'Outdoor',     599.00 FROM dual UNION ALL
SELECT  71, 'Bike Helmet',                       'Outdoor',      69.00 FROM dual UNION ALL
SELECT  72, 'Portable Hammock',                  'Outdoor',      35.00 FROM dual UNION ALL
SELECT  73, 'Fishing Rod Combo',                 'Outdoor',      89.00 FROM dual UNION ALL
SELECT  74, 'Rain Jacket',                       'Outdoor',     119.00 FROM dual UNION ALL
SELECT  75, 'Picnic Blanket',                    'Outdoor',      29.00 FROM dual UNION ALL
SELECT  76, 'Binoculars 10x42',                  'Outdoor',     149.00 FROM dual UNION ALL
SELECT  77, 'Kayak Paddle',                      'Outdoor',      99.00 FROM dual UNION ALL
SELECT  78, 'First Aid Kit',                     'Outdoor',      24.00 FROM dual UNION ALL
SELECT  79, 'Solar Lantern',                     'Outdoor',      32.00 FROM dual UNION ALL
SELECT  80, 'Inflatable Kayak',                  'Outdoor',     349.00 FROM dual UNION ALL
SELECT  81, 'Building Blocks 500 pcs',           'Toys',         49.99 FROM dual UNION ALL
SELECT  82, 'Remote Control Car',                'Toys',         59.99 FROM dual UNION ALL
SELECT  83, 'Jigsaw Puzzle 1000 pcs',            'Toys',         19.99 FROM dual UNION ALL
SELECT  84, 'Plush Teddy Bear',                  'Toys',         24.99 FROM dual UNION ALL
SELECT  85, 'Classic Board Game',                'Toys',         34.99 FROM dual UNION ALL
SELECT  86, 'Wooden Train Set',                  'Toys',         89.99 FROM dual UNION ALL
SELECT  87, 'Dollhouse',                         'Toys',         89.99 FROM dual UNION ALL
SELECT  88, 'Science Kit',                       'Toys',         39.99 FROM dual UNION ALL
SELECT  89, 'Art & Craft Box',                   'Toys',         29.99 FROM dual UNION ALL
SELECT  90, 'Kids Drone',                        'Toys',         79.99 FROM dual UNION ALL
SELECT  91, 'Yo-Yo',                             'Toys',          4.99 FROM dual UNION ALL
SELECT  92, 'Kite',                              'Toys',         14.99 FROM dual UNION ALL
SELECT  93, 'Water Blaster',                     'Toys',         12.99 FROM dual UNION ALL
SELECT  94, 'Magnetic Tiles',                    'Toys',         64.99 FROM dual UNION ALL
SELECT  95, 'Card Game',                         'Toys',          9.99 FROM dual UNION ALL
SELECT  96, 'Toy Kitchen Set',                   'Toys',         79.99 FROM dual UNION ALL
SELECT  97, 'Rubik''s Cube',                     'Toys',          8.99 FROM dual UNION ALL
SELECT  98, 'Stuffed Dinosaur',                  'Toys',         24.99 FROM dual UNION ALL
SELECT  99, 'Marble Run',                        'Toys',         44.99 FROM dual UNION ALL
SELECT 100, 'Bubble Machine',                    'Toys',         19.99 FROM dual UNION ALL
SELECT 101, 'Garden Hose 20m',                   'Garden',       34.00 FROM dual UNION ALL
SELECT 102, 'Pruning Shears',                    'Garden',       18.00 FROM dual UNION ALL
SELECT 103, 'Raised Garden Bed',                 'Garden',      129.00 FROM dual UNION ALL
SELECT 104, 'Seed Starter Kit',                  'Garden',       15.00 FROM dual;

-- 4. Customers (500) -----------------------------------------------
-- Countries are deliberately uneven (Taiwan 130, Japan 100, USA 95,
-- Singapore 60, Germany 50, Vietnam 45, Canada 20).
-- Customers 1-440 signed up 2021-2023, 441-480 during 2024, and
-- 481-500 in 2025 (those last 20 haven't ordered anything yet).
INSERT INTO customers (customer_id, customer_name, email, country, signup_date)
SELECT LEVEL,
       'Customer ' || LEVEL,
       CASE WHEN MOD(LEVEL, 50) = 17 THEN NULL          -- 10 customers never gave an email
            ELSE 'customer' || LEVEL || '@' ||
                 CASE MOD(LEVEL, 6)
                      WHEN 0 THEN 'example.com' WHEN 1 THEN 'gmail.com'
                      WHEN 2 THEN 'yahoo.com.tw' WHEN 3 THEN 'outlook.com'
                      WHEN 4 THEN 'example.com' ELSE 'hotmail.com' END
       END,
       CASE WHEN MOD(LEVEL * 37, 100) < 26 THEN 'Taiwan'
            WHEN MOD(LEVEL * 37, 100) < 46 THEN 'Japan'
            WHEN MOD(LEVEL * 37, 100) < 65 THEN 'USA'
            WHEN MOD(LEVEL * 37, 100) < 77 THEN 'Singapore'
            WHEN MOD(LEVEL * 37, 100) < 87 THEN 'Germany'
            WHEN MOD(LEVEL * 37, 100) < 96 THEN 'Vietnam'
            ELSE 'Canada' END,
       CASE WHEN LEVEL <= 440 THEN DATE '2021-01-01' + MOD(lab_rnd(LEVEL, 1), 1095)
            WHEN LEVEL <= 480 THEN DATE '2024-01-01' + MOD(lab_rnd(LEVEL, 1), 366)
            ELSE                   DATE '2025-01-01' + MOD(lab_rnd(LEVEL, 1), 270) END
FROM dual CONNECT BY LEVEL <= 500;

-- A few hand-typed emails that are wrong (Lab 06's REGEXP exercises)
UPDATE customers SET email = 'customer25.gmail.com'     WHERE customer_id = 25;   -- no @
UPDATE customers SET email = 'customer60@gmail'         WHERE customer_id = 60;   -- no dot in domain
UPDATE customers SET email = 'customer133@@example.com' WHERE customer_id = 133;  -- double @
UPDATE customers SET email = 'customer208@example.'     WHERE customer_id = 208;  -- nothing after the dot
UPDATE customers SET email = '@example.com'             WHERE customer_id = 350;  -- no local part

COMMIT;

-- 5. Orders (10,000), 2023-01-01 .. 2025-09-30 --------------------
-- * order_id increases with order_date (like a real sequence would).
-- * November/December are busier than other months.
-- * An order is never placed before the customer signed up, and never
--   assigned to a rep hired after the order date.
-- * Customer 7 is a big key account (~700 orders); customers
--   97, 194, 291, 388 and 481-500 have no orders at all.
-- * ~10% of orders have no sales rep (employee_id IS NULL).
-- * Only reps 1003 and 1007 (and unassigned orders) have cancellations.
-- * PENDING = placed in the last 2 weeks, SHIPPED = the 2-6 weeks
--   before that, COMPLETED = older.
-- Note: no index on customer_id / order_date / employee_id yet, on
-- purpose -- Labs 13-14 are where you add them and watch the
-- execution plan change.
DECLARE
   TYPE t_num_tab  IS TABLE OF NUMBER       INDEX BY PLS_INTEGER;
   TYPE t_date_tab IS TABLE OF DATE         INDEX BY PLS_INTEGER;
   TYPE t_str_tab  IS TABLE OF VARCHAR2(20) INDEX BY PLS_INTEGER;
   c_first    CONSTANT DATE := DATE '2023-01-01';
   c_last     CONSTANT DATE := DATE '2025-09-30';
   c_whale    CONSTANT PLS_INTEGER := 7;
   l_day_pool t_date_tab;   -- each calendar day repeated by its weight
   l_pool_cnt PLS_INTEGER := 0;
   l_signup   t_date_tab;   -- customer_id -> signup_date
   l_hire     t_date_tab;   -- employee_id -> hire_date
   l_ord_id   t_num_tab;
   l_cust_id  t_num_tab;
   l_emp_id   t_num_tab;
   l_ord_date t_date_tab;
   l_status   t_str_tab;
   l_day      DATE;
   l_cust     PLS_INTEGER;
   l_cand     PLS_INTEGER;
   l_rep      PLS_INTEGER;
   l_try      PLS_INTEGER;
BEGIN
   l_day := c_first;
   WHILE l_day <= c_last LOOP
      FOR k IN 1 .. CASE EXTRACT(MONTH FROM l_day) WHEN 11 THEN 16 WHEN 12 THEN 18 ELSE 10 END LOOP
         l_pool_cnt := l_pool_cnt + 1;
         l_day_pool(l_pool_cnt) := l_day;
      END LOOP;
      l_day := l_day + 1;
   END LOOP;

   FOR c IN (SELECT customer_id, signup_date FROM customers) LOOP
      l_signup(c.customer_id) := c.signup_date;
   END LOOP;
   FOR e IN (SELECT employee_id, hire_date FROM employees) LOOP
      l_hire(e.employee_id) := e.hire_date;
   END LOOP;

   FOR n IN 1 .. 10000 LOOP
      l_ord_id(n)   := n;
      -- walking the day pool in order keeps order_date non-decreasing
      l_ord_date(n) := l_day_pool(1 + FLOOR(((n - 1) * 1000 + MOD(lab_rnd(n, 11), 1000))
                                            * l_pool_cnt / 10000000));

      -- customer: 7% go to the key account, the rest to an eligible customer
      IF MOD(lab_rnd(n, 12), 100) < 7 THEN
         l_cust := c_whale;
      ELSE
         l_cust := NULL;
         l_try  := 0;
         WHILE l_cust IS NULL LOOP
            l_try  := l_try + 1;
            l_cand := 1 + MOD(lab_rnd(n, 100 + l_try), 480);
            IF l_cand NOT IN (97, 194, 291, 388) AND l_signup(l_cand) <= l_ord_date(n) THEN
               l_cust := l_cand;
            ELSIF l_try >= 50 THEN
               l_cust := c_whale;
            END IF;
         END LOOP;
      END IF;
      l_cust_id(n) := l_cust;

      -- sales rep: 10% unassigned, otherwise one of reps 1001-1011
      -- who was already hired on the order date
      IF MOD(lab_rnd(n, 13), 100) < 10 THEN
         l_emp_id(n) := NULL;
      ELSE
         l_try := 0;
         LOOP
            l_try := l_try + 1;
            l_rep := 1001 + MOD(lab_rnd(n, 200 + l_try), 11);
            EXIT WHEN l_hire(l_rep) <= l_ord_date(n) OR l_try >= 20;
         END LOOP;
         l_emp_id(n) := CASE WHEN l_hire(l_rep) <= l_ord_date(n) THEN l_rep ELSE 1001 END;
      END IF;

      l_status(n) :=
         CASE
            WHEN (l_emp_id(n) IS NULL OR l_emp_id(n) IN (1003, 1007))
                 AND MOD(lab_rnd(n, 14), 100) < 30  THEN 'CANCELLED'
            WHEN c_last - l_ord_date(n) < 14        THEN 'PENDING'
            WHEN c_last - l_ord_date(n) < 40        THEN 'SHIPPED'
            ELSE                                         'COMPLETED'
         END;
   END LOOP;

   FORALL j IN 1 .. l_ord_id.COUNT
      INSERT INTO orders (order_id, customer_id, employee_id, order_date, status)
      VALUES (l_ord_id(j), l_cust_id(j), l_emp_id(j), l_ord_date(j), l_status(j));

   COMMIT;
END;
/

-- 6. Order items: 1-5 lines per order, 29,710 rows ------------------
-- Written with BULK COLLECT + FORALL on purpose -- this is the
-- exact pattern Lab 19 (PL/SQL basics) teaches you to write.
-- * Cheaper products are ordered more often (weight 3 / 2 / 1 for
--   under 50 / under 200 / 200+); the Garden line (101-104) never is.
-- * No product appears twice in the same order.
-- * unit_price is the list price at order time: 8% lower in 2023,
--   4% lower in 2024 than today's products.unit_price.
DECLARE
   TYPE t_num_tab  IS TABLE OF NUMBER INDEX BY PLS_INTEGER;
   TYPE t_date_tab IS TABLE OF DATE   INDEX BY PLS_INTEGER;
   l_prod_ids   t_num_tab;
   l_prod_price t_num_tab;
   l_price_of   t_num_tab;   -- product_id -> unit_price lookup
   l_prod_pool  t_num_tab;   -- product_ids repeated by popularity weight
   l_pool_cnt   PLS_INTEGER := 0;
   l_ord_ids    t_num_tab;
   l_ord_dates  t_date_tab;
   l_used       t_num_tab;   -- product_ids already on the current order
   l_order_id   t_num_tab;
   l_line_no    t_num_tab;
   l_product_id t_num_tab;
   l_qty        t_num_tab;
   l_price      t_num_tab;
   l_idx        PLS_INTEGER := 0;
   l_pid        PLS_INTEGER;
   l_try        PLS_INTEGER;
   l_factor     NUMBER;
   l_oid        NUMBER;
BEGIN
   SELECT product_id, unit_price
     BULK COLLECT INTO l_prod_ids, l_prod_price
     FROM products
    WHERE product_id <= 100
    ORDER BY product_id;

   FOR p IN 1 .. l_prod_ids.COUNT LOOP
      l_price_of(l_prod_ids(p)) := l_prod_price(p);
      FOR k IN 1 .. CASE WHEN l_prod_price(p) < 50 THEN 3
                         WHEN l_prod_price(p) < 200 THEN 2 ELSE 1 END LOOP
         l_pool_cnt := l_pool_cnt + 1;
         l_prod_pool(l_pool_cnt) := l_prod_ids(p);
      END LOOP;
   END LOOP;

   SELECT order_id, order_date
     BULK COLLECT INTO l_ord_ids, l_ord_dates
     FROM orders
    ORDER BY order_id;

   FOR o IN 1 .. l_ord_ids.COUNT LOOP
      l_oid    := l_ord_ids(o);
      l_factor := CASE EXTRACT(YEAR FROM l_ord_dates(o))
                     WHEN 2023 THEN 0.92 WHEN 2024 THEN 0.96 ELSE 1 END;
      l_used.DELETE;
      FOR i IN 1 .. 1 + MOD(lab_rnd(l_oid, 21), 5) LOOP
         l_try := 0;
         LOOP
            l_pid := l_prod_pool(1 + MOD(lab_rnd(l_oid * 10 + i, 22 + l_try), l_pool_cnt));
            l_try := l_try + 1;
            EXIT WHEN NOT l_used.EXISTS(l_pid) OR l_try >= 10;
         END LOOP;
         l_used(l_pid) := 1;

         l_idx := l_idx + 1;
         l_order_id(l_idx)   := l_oid;
         l_line_no(l_idx)    := i;
         l_product_id(l_idx) := l_pid;
         l_qty(l_idx)        := 1 + MOD(lab_rnd(l_oid * 10 + i, 40), 5);
         l_price(l_idx)      := ROUND(l_price_of(l_pid) * l_factor, 2);
      END LOOP;
   END LOOP;

   FORALL j IN 1 .. l_idx
      INSERT INTO order_items (order_id, line_no, product_id, quantity, unit_price)
      VALUES (l_order_id(j), l_line_no(j), l_product_id(j), l_qty(j), l_price(j));

   COMMIT;
   DBMS_OUTPUT.PUT_LINE('Inserted ' || l_idx || ' order_items rows.');
END;
/

-- The helper isn't part of the lab schema -- remove it again
DROP FUNCTION lab_rnd;

-- 7. Sanity check ----------------------------------------------------
-- Expected: 9 / 52 / 500 / 104 / 10000 / 29710
SELECT 'departments' tbl, COUNT(*) rows_ FROM departments UNION ALL
SELECT 'employees',        COUNT(*) FROM employees UNION ALL
SELECT 'customers',        COUNT(*) FROM customers UNION ALL
SELECT 'products',         COUNT(*) FROM products UNION ALL
SELECT 'orders',           COUNT(*) FROM orders UNION ALL
SELECT 'order_items',      COUNT(*) FROM order_items;
