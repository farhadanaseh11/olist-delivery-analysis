-- ============================================================
-- Olist Brazilian E-Commerce - Table Definitions
-- Target: PostgreSQL 17, database "olist", schema "public"
--
-- Run this ONCE before importing any CSVs.
-- Creating tables with explicit types up front means DBeaver
-- imports into a correct schema instead of guessing and
-- turning every timestamp into text.
-- ============================================================


-- ------------------------------------------------------------
-- Customers
-- One row per order-level customer key.
-- NOTE: customer_id is per-ORDER. customer_unique_id is the
-- real person. A repeat buyer has many customer_id values
-- and one customer_unique_id. This trips up nearly everyone.
-- ------------------------------------------------------------
DROP TABLE IF EXISTS customers;
CREATE TABLE customers (
    customer_id                 TEXT,
    customer_unique_id          TEXT,
    customer_zip_code_prefix    INTEGER,
    customer_city               TEXT,
    customer_state              CHAR(2)
);


-- ------------------------------------------------------------
-- Sellers
-- ------------------------------------------------------------
DROP TABLE IF EXISTS sellers;
CREATE TABLE sellers (
    seller_id                   TEXT,
    seller_zip_code_prefix      INTEGER,
    seller_city                 TEXT,
    seller_state                CHAR(2)
);


-- ------------------------------------------------------------
-- Geolocation
-- Zip prefix -> lat/lng. Many rows per zip prefix.
-- Do NOT join this directly to orders without aggregating
-- first, or you will multiply your row counts.
-- ------------------------------------------------------------
DROP TABLE IF EXISTS geolocation;
CREATE TABLE geolocation (
    geolocation_zip_code_prefix INTEGER,
    geolocation_lat             NUMERIC,
    geolocation_lng             NUMERIC,
    geolocation_city            TEXT,
    geolocation_state           CHAR(2)
);


-- ------------------------------------------------------------
-- Products
-- The misspellings "lenght" are in the source data.
-- Keep them here so the import maps cleanly; rename later
-- in your staging views.
-- ------------------------------------------------------------
DROP TABLE IF EXISTS products;
CREATE TABLE products (
    product_id                  TEXT,
    product_category_name       TEXT,
    product_name_lenght         INTEGER,
    product_description_lenght  INTEGER,
    product_photos_qty          INTEGER,
    product_weight_g            INTEGER,
    product_length_cm           INTEGER,
    product_height_cm           INTEGER,
    product_width_cm            INTEGER
);


-- ------------------------------------------------------------
-- Product category name translation
-- Portuguese -> English category names.
-- Does not cover every category; expect nulls on join.
-- ------------------------------------------------------------
DROP TABLE IF EXISTS product_category_translation;
CREATE TABLE product_category_translation (
    product_category_name          TEXT,
    product_category_name_english  TEXT
);


-- ------------------------------------------------------------
-- Orders  *** the spine of the whole project ***
--
-- The delivery story lives in these five timestamps:
--   order_purchase_timestamp        customer clicks buy
--   order_approved_at               payment clears
--   order_delivered_carrier_date    handed to logistics
--   order_delivered_customer_date   actually delivered
--   order_estimated_delivery_date   what the customer was promised
--
-- Late delivery = order_delivered_customer_date
--                 > order_estimated_delivery_date
--
-- Nulls are meaningful here, not dirty: an undelivered or
-- cancelled order legitimately has no delivery date.
-- ------------------------------------------------------------
DROP TABLE IF EXISTS orders;
CREATE TABLE orders (
    order_id                      TEXT,
    customer_id                   TEXT,
    order_status                  TEXT,
    order_purchase_timestamp      TIMESTAMP,
    order_approved_at             TIMESTAMP,
    order_delivered_carrier_date  TIMESTAMP,
    order_delivered_customer_date TIMESTAMP,
    order_estimated_delivery_date TIMESTAMP
);


-- ------------------------------------------------------------
-- Order items
-- One row per ITEM, not per order. An order with 3 items has
-- 3 rows. Summing price here without care double-counts
-- order-level metrics.
-- ------------------------------------------------------------
DROP TABLE IF EXISTS order_items;
CREATE TABLE order_items (
    order_id                    TEXT,
    order_item_id               INTEGER,
    product_id                  TEXT,
    seller_id                   TEXT,
    shipping_limit_date         TIMESTAMP,
    price                       NUMERIC(10,2),
    freight_value               NUMERIC(10,2)
);


-- ------------------------------------------------------------
-- Order payments
-- One row per payment method used. A split payment produces
-- multiple rows for the same order_id.
-- ------------------------------------------------------------
DROP TABLE IF EXISTS order_payments;
CREATE TABLE order_payments (
    order_id                    TEXT,
    payment_sequential          INTEGER,
    payment_type                TEXT,
    payment_installments        INTEGER,
    payment_value               NUMERIC(10,2)
);


-- ------------------------------------------------------------
-- Order reviews
-- review_score is 1-5 and is your outcome variable.
-- Comment fields are free text in Portuguese and contain
-- commas, quotes, and newlines -- this is the file most
-- likely to give you import trouble.
-- ------------------------------------------------------------
DROP TABLE IF EXISTS order_reviews;
CREATE TABLE order_reviews (
    review_id                   TEXT,
    order_id                    TEXT,
    review_score                INTEGER,
    review_comment_title        TEXT,
    review_comment_message      TEXT,
    review_creation_date        TIMESTAMP,
    review_answer_timestamp     TIMESTAMP
);


-- ============================================================
-- VERIFICATION -- run after all nine imports finish.
-- Expected row counts are approximate but should be very close.
-- If any count is 0 or wildly off, that import failed.
-- ============================================================

SELECT 'customers'                    AS table_name, COUNT(*) AS rows, 99441  AS expected FROM customers
UNION ALL SELECT 'sellers',                          COUNT(*), 3095          FROM sellers
UNION ALL SELECT 'geolocation',                      COUNT(*), 1000163       FROM geolocation
UNION ALL SELECT 'products',                         COUNT(*), 32951         FROM products
UNION ALL SELECT 'product_category_translation',     COUNT(*), 71            FROM product_category_translation
UNION ALL SELECT 'orders',                           COUNT(*), 99441         FROM orders
UNION ALL SELECT 'order_items',                      COUNT(*), 112650        FROM order_items
UNION ALL SELECT 'order_payments',                   COUNT(*), 103886        FROM order_payments
UNION ALL SELECT 'order_reviews',                    COUNT(*), 99224         FROM order_reviews
ORDER BY table_name;
