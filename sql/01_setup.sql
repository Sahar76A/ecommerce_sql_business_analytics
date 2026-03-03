--These commands build the required tables--
SET search_path TO public;

-- 1) Drop tables 
DROP TABLE IF EXISTS order_items CASCADE;
DROP TABLE IF EXISTS order_payments CASCADE;
DROP TABLE IF EXISTS order_reviews CASCADE;
DROP TABLE IF EXISTS orders CASCADE;
DROP TABLE IF EXISTS customers CASCADE;
DROP TABLE IF EXISTS sellers CASCADE;
DROP TABLE IF EXISTS products CASCADE;
DROP TABLE IF EXISTS geolocation CASCADE;
DROP TABLE IF EXISTS product_category_name_translation CASCADE;

-- 2) Create tables

CREATE TABLE customers (
  customer_id              VARCHAR(32) PRIMARY KEY,
  customer_unique_id       VARCHAR(32) NOT NULL,
  customer_zip_code_prefix INTEGER,
  customer_city            TEXT,
  customer_state           CHAR(2)
);

CREATE TABLE sellers (
  seller_id                VARCHAR(32) PRIMARY KEY,
  seller_zip_code_prefix   INTEGER,
  seller_city              TEXT,
  seller_state             CHAR(2)
);

CREATE TABLE products (
  product_id                       VARCHAR(32) PRIMARY KEY,
  product_category_name            TEXT,
  product_name_length              INTEGER,
  product_description_length       INTEGER,
  product_photos_qty               INTEGER,
  product_weight_g                 INTEGER,
  product_length_cm                INTEGER,
  product_height_cm                INTEGER,
  product_width_cm                 INTEGER
);

CREATE TABLE orders (
  order_id                       VARCHAR(32) PRIMARY KEY,
  customer_id                    VARCHAR(32) NOT NULL REFERENCES customers(customer_id),
  order_status                   TEXT NOT NULL,
  order_purchase_timestamp       TIMESTAMP,
  order_approved_at              TIMESTAMP,
  order_delivered_carrier_date   TIMESTAMP,
  order_delivered_customer_date  TIMESTAMP,
  order_estimated_delivery_date  TIMESTAMP
);

CREATE TABLE order_items (
  order_id            VARCHAR(32) NOT NULL REFERENCES orders(order_id),
  order_item_id       INTEGER     NOT NULL,
  product_id          VARCHAR(32) REFERENCES products(product_id),
  seller_id           VARCHAR(32) REFERENCES sellers(seller_id),
  shipping_limit_date TIMESTAMP,
  price               NUMERIC(10,2),
  freight_value       NUMERIC(10,2),
  PRIMARY KEY (order_id, order_item_id)
);

CREATE TABLE order_payments (
  order_id              VARCHAR(32) NOT NULL REFERENCES orders(order_id),
  payment_sequential    INTEGER     NOT NULL,
  payment_type          TEXT,
  payment_installments  INTEGER,
  payment_value         NUMERIC(10,2),
  PRIMARY KEY (order_id, payment_sequential)
);

CREATE TABLE order_reviews (
  review_id              VARCHAR(32) NOT NULL,
  order_id               VARCHAR(32) NOT NULL REFERENCES orders(order_id),
  review_score           INTEGER CHECK (review_score BETWEEN 1 AND 5),
  review_comment_title   TEXT,
  review_comment_message TEXT,
  review_creation_date   TIMESTAMP,
  review_answer_timestamp TIMESTAMP,
  PRIMARY KEY (review_id, order_id)
);

CREATE TABLE geolocation (
  geolocation_zip_code_prefix INTEGER,
  geolocation_lat             NUMERIC(10,6),
  geolocation_lng             NUMERIC(10,6),
  geolocation_city            TEXT,
  geolocation_state           CHAR(2)
);

CREATE TABLE product_category_name_translation (
  product_category_name         TEXT PRIMARY KEY,
  product_category_name_english TEXT
);

CREATE INDEX idx_orders_customer_id ON orders(customer_id);
CREATE INDEX idx_order_items_product_id ON order_items(product_id);
CREATE INDEX idx_order_items_seller_id ON order_items(seller_id);
CREATE INDEX idx_orders_purchase_ts ON orders(order_purchase_timestamp);
