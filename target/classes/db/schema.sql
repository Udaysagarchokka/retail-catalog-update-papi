-- ============================================================
-- Retail Real-Time Product Catalog Update
-- Database Schema — Strictly as defined in Hackathon PDF (Pages 6-7)
-- Target: MySQL 8.x
-- Run against schema: retail_catalog
-- ============================================================

-- 1. Main products catalog table (PDF Page 6)
CREATE TABLE IF NOT EXISTS products (
    sku                 VARCHAR(40)     PRIMARY KEY,
    product_name        VARCHAR(200)    NOT NULL,
    category_code       VARCHAR(20)     NOT NULL,
    brand               VARCHAR(80),
    price               DECIMAL(12,2)   NOT NULL,
    currency            CHAR(3)         NOT NULL,
    tax_class           VARCHAR(10),
    stock_status        VARCHAR(15)     NOT NULL,
    product_status      VARCHAR(15)     NOT NULL,
    short_description   VARCHAR(500),
    image_path          VARCHAR(300),
    content_hash        VARCHAR(200)     NOT NULL,
    source_updated_at   TIMESTAMP,
    last_run_id         VARCHAR(40),
    review_hold         BOOLEAN         DEFAULT FALSE,
    updated_at          TIMESTAMP       DEFAULT CURRENT_TIMESTAMP
);

-- 2. Product change history audit table (PDF Page 6)
CREATE TABLE IF NOT EXISTS product_change_history (
    change_seq      BIGINT          AUTO_INCREMENT PRIMARY KEY,
    run_id          VARCHAR(40)     NOT NULL,
    sku             VARCHAR(40)     NOT NULL,
    change_type     VARCHAR(15)     NOT NULL,
    field_name      VARCHAR(40),
    old_value       VARCHAR(500),
    new_value       VARCHAR(500),
    customer_facing BOOLEAN         NOT NULL,
    changed_at      TIMESTAMP       DEFAULT CURRENT_TIMESTAMP
);

-- 3. Catalog import runs audit table (PDF Page 6)
CREATE TABLE IF NOT EXISTS catalog_import_runs (
    run_id                  VARCHAR(40)     PRIMARY KEY,
    file_name               VARCHAR(200)    NOT NULL,
    file_checksum           VARCHAR(64)     NOT NULL,
    extract_type            VARCHAR(10)     NOT NULL,
    parsed_count            INT,
    new_count               INT,
    changed_count           INT,
    unchanged_count         INT,
    delisted_count          INT,
    held_count              INT,
    rejected_count          INT,
    invalidation_requests   INT,
    invalidation_paths      INT,
    unconfirmed_paths       INT,
    run_status              VARCHAR(20)     NOT NULL,
    started_at              TIMESTAMP,
    completed_at            TIMESTAMP,
    correlation_id          VARCHAR(50),
    UNIQUE KEY uk_catalog_file (file_name, file_checksum)
);

-- 4. CDN invalidation tracking table (PDF Page 7)
CREATE TABLE IF NOT EXISTS cdn_invalidations (
    invalidation_seq    BIGINT          AUTO_INCREMENT PRIMARY KEY,
    run_id              VARCHAR(40)     NOT NULL,
    request_ref         VARCHAR(80),
    path_count          INT             NOT NULL,
    paths               TEXT            NOT NULL,
    http_status         INT,
    provider_status     VARCHAR(20),
    attempt_count       INT             DEFAULT 1,
    confirmed           BOOLEAN         DEFAULT FALSE,
    requested_at        TIMESTAMP       DEFAULT CURRENT_TIMESTAMP
);
