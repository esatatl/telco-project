-- =============================================================================
-- i2i Systems Telco Project - Table Creation Scripts
-- =============================================================================
-- Schema design rationale:
--   * Three relational tables matching the three CSV files.
--   * TARIFFS is the master/lookup table; CUSTOMERS references it (many-to-one).
--   * MONTHLY_STATS holds one row per customer for the current month, so
--     CUSTOMER_ID is declared UNIQUE (not just FK) — this matches the dataset
--     (where ID == CUSTOMER_ID) and prevents duplicate monthly records.
--   * VARCHAR2(... CHAR) is used so Turkish characters (ş, ğ, ı, İ, ç, ö, ü)
--     count as 1 character regardless of UTF-8 byte length.
--   * CHECK constraints validate domain values (payment status, non-negative
--     usage/limits) at the database layer, so bad data can never be inserted.
--   * Indexes are added on columns frequently used in WHERE / GROUP BY clauses
--     of the functional requirement queries (tariff_id, signup_date, city,
--     payment_status) to keep query plans efficient.
-- =============================================================================

-- Run this whole file in DBeaver against the telco_user / XEPDB1 connection.
-- If you re-run, drop in reverse dependency order first:

-- DROP TABLE MONTHLY_STATS CASCADE CONSTRAINTS;
-- DROP TABLE CUSTOMERS     CASCADE CONSTRAINTS;
-- DROP TABLE TARIFFS       CASCADE CONSTRAINTS;


-- -----------------------------------------------------------------------------
-- 1) TARIFFS  (master / lookup table — only 4 rows)
-- -----------------------------------------------------------------------------
CREATE TABLE TARIFFS (
    TARIFF_ID     NUMBER(3)         NOT NULL,
    NAME          VARCHAR2(100 CHAR) NOT NULL,
    MONTHLY_FEE   NUMBER(10, 2)     NOT NULL,
    DATA_LIMIT    NUMBER(10)        NOT NULL,   -- in MB
    MINUTE_LIMIT  NUMBER(10)        NOT NULL,
    SMS_LIMIT     NUMBER(10)        NOT NULL,
    --
    CONSTRAINT PK_TARIFFS                PRIMARY KEY (TARIFF_ID),
    CONSTRAINT UQ_TARIFFS_NAME           UNIQUE (NAME),
    CONSTRAINT CHK_TARIFFS_FEE_NONNEG    CHECK (MONTHLY_FEE  >= 0),
    CONSTRAINT CHK_TARIFFS_DATA_NONNEG   CHECK (DATA_LIMIT   >= 0),
    CONSTRAINT CHK_TARIFFS_MIN_NONNEG    CHECK (MINUTE_LIMIT >= 0),
    CONSTRAINT CHK_TARIFFS_SMS_NONNEG    CHECK (SMS_LIMIT    >= 0)
);


-- -----------------------------------------------------------------------------
-- 2) CUSTOMERS  (10 000 rows)
-- -----------------------------------------------------------------------------
CREATE TABLE CUSTOMERS (
    CUSTOMER_ID  NUMBER(10)        NOT NULL,
    NAME         VARCHAR2(50 CHAR) NOT NULL,
    CITY         VARCHAR2(50 CHAR) NOT NULL,
    SIGNUP_DATE  DATE              NOT NULL,
    TARIFF_ID    NUMBER(3)         NOT NULL,
    --
    CONSTRAINT PK_CUSTOMERS              PRIMARY KEY (CUSTOMER_ID),
    CONSTRAINT FK_CUSTOMERS_TARIFF       FOREIGN KEY (TARIFF_ID)
                                         REFERENCES TARIFFS (TARIFF_ID)
);

-- Helpful indexes for the analytical queries in SOLUTIONS.sql:
CREATE INDEX IDX_CUSTOMERS_TARIFF_ID   ON CUSTOMERS (TARIFF_ID);     -- Q1, Q2, Q6.2
CREATE INDEX IDX_CUSTOMERS_SIGNUP_DATE ON CUSTOMERS (SIGNUP_DATE);   -- Q3.1
CREATE INDEX IDX_CUSTOMERS_CITY        ON CUSTOMERS (CITY);          -- Q3.2, Q4.2


-- -----------------------------------------------------------------------------
-- 3) MONTHLY_STATS  (9 950 rows — 50 customers' records are intentionally missing)
-- -----------------------------------------------------------------------------
CREATE TABLE MONTHLY_STATS (
    ID              NUMBER(10)        NOT NULL,
    CUSTOMER_ID     NUMBER(10)        NOT NULL,
    DATA_USAGE      NUMBER(10, 2)     NOT NULL,   -- in MB, decimals allowed
    MINUTE_USAGE    NUMBER(10)        NOT NULL,
    SMS_USAGE       NUMBER(10)        NOT NULL,
    PAYMENT_STATUS  VARCHAR2(10 CHAR) NOT NULL,
    --
    CONSTRAINT PK_MONTHLY_STATS                PRIMARY KEY (ID),
    CONSTRAINT UQ_MONTHLY_STATS_CUSTOMER       UNIQUE      (CUSTOMER_ID),
    CONSTRAINT FK_MONTHLY_STATS_CUSTOMER       FOREIGN KEY (CUSTOMER_ID)
                                               REFERENCES CUSTOMERS (CUSTOMER_ID),
    CONSTRAINT CHK_MS_PAYMENT_STATUS           CHECK (PAYMENT_STATUS IN ('PAID', 'LATE', 'UNPAID')),
    CONSTRAINT CHK_MS_DATA_NONNEG              CHECK (DATA_USAGE   >= 0),
    CONSTRAINT CHK_MS_MIN_NONNEG               CHECK (MINUTE_USAGE >= 0),
    CONSTRAINT CHK_MS_SMS_NONNEG               CHECK (SMS_USAGE    >= 0)
);

-- Index on PAYMENT_STATUS for Q6.1 / Q6.2 (low-cardinality but used in
-- aggregations and filters; helps the optimizer choose hash group-by paths).
CREATE INDEX IDX_MONTHLY_STATS_PAYMENT_STATUS ON MONTHLY_STATS (PAYMENT_STATUS);


-- -----------------------------------------------------------------------------
-- Quick sanity check after import:
-- -----------------------------------------------------------------------------
-- SELECT 'TARIFFS' AS T, COUNT(*) FROM TARIFFS
-- UNION ALL SELECT 'CUSTOMERS',     COUNT(*) FROM CUSTOMERS
-- UNION ALL SELECT 'MONTHLY_STATS', COUNT(*) FROM MONTHLY_STATS;
-- Expected: 4 / 10000 / 9950
