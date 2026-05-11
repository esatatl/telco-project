-- =============================================================================
-- i2i Systems Telco Project - SOLUTIONS
-- =============================================================================
-- Each query below addresses one of the functional requirements in the README.
-- Per the project rules, every query is preceded by a comment block of at
-- least three sentences explaining the approach. The expected row counts /
-- shapes are noted at the end of each comment block where useful, so the
-- output can be sanity-checked at a glance.
-- =============================================================================


-- -----------------------------------------------------------------------------
-- Q1.1  List customers subscribed to the 'Kobiye Destek' tariff.
-- -----------------------------------------------------------------------------
-- The tariff name lives in the TARIFFS table while customer subscriptions are
-- recorded in CUSTOMERS via TARIFF_ID, so we join the two tables on that key.
-- Filtering by the literal tariff name (rather than its numeric id) keeps the
-- query resilient to changes in the master table — even if 'Kobiye Destek'
-- moved to a different TARIFF_ID, the query would still return the right set.
-- The result is the full customer record for every subscriber of that tariff.
SELECT c.CUSTOMER_ID,
       c.NAME,
       c.CITY,
       c.SIGNUP_DATE,
       c.TARIFF_ID
FROM   CUSTOMERS c
JOIN   TARIFFS   t ON c.TARIFF_ID = t.TARIFF_ID
WHERE  t.NAME = 'Kobiye Destek'
ORDER  BY c.CUSTOMER_ID;


-- -----------------------------------------------------------------------------
-- Q1.2  Find the NEWEST customer who subscribed to the 'Kobiye Destek' tariff.
-- -----------------------------------------------------------------------------
-- "Newest" is interpreted as the customer(s) with the maximum SIGNUP_DATE
-- among subscribers of this specific tariff. Since multiple people can sign up
-- on the same day, FETCH FIRST 1 ROW WITH TIES is used so that — if there is
-- a tie on the latest day — every tied customer is returned, not an arbitrary
-- one. Ordering by SIGNUP_DATE DESC, the WITH TIES clause guarantees correct
-- behaviour without needing an extra subquery for MAX(SIGNUP_DATE).
SELECT c.CUSTOMER_ID,
       c.NAME,
       c.CITY,
       c.SIGNUP_DATE,
       c.TARIFF_ID
FROM   CUSTOMERS c
JOIN   TARIFFS   t ON c.TARIFF_ID = t.TARIFF_ID
WHERE  t.NAME = 'Kobiye Destek'
ORDER  BY c.SIGNUP_DATE DESC
FETCH  FIRST 1 ROW WITH TIES;


-- -----------------------------------------------------------------------------
-- Q2.1  Distribution of tariffs among the customers.
-- -----------------------------------------------------------------------------
-- We group the customer base by tariff and count rows per group, joining to
-- TARIFFS so the human-readable name is shown next to the count. A LEFT JOIN
-- starting from TARIFFS makes the query future-proof: a tariff with zero
-- subscribers would still appear with a count of 0, which is desirable for
-- a distribution report. The percentage is computed with a window function
-- so it always sums to 100 across the result set, regardless of filters.
SELECT t.TARIFF_ID,
       t.NAME                                                              AS TARIFF_NAME,
       COUNT(c.CUSTOMER_ID)                                                AS CUSTOMER_COUNT,
       ROUND(COUNT(c.CUSTOMER_ID) * 100.0
             / NULLIF(SUM(COUNT(c.CUSTOMER_ID)) OVER (), 0), 2)            AS PERCENTAGE
FROM   TARIFFS   t
LEFT JOIN CUSTOMERS c ON c.TARIFF_ID = t.TARIFF_ID
GROUP  BY t.TARIFF_ID, t.NAME
ORDER  BY CUSTOMER_COUNT DESC;


-- -----------------------------------------------------------------------------
-- Q3.1  Identify the EARLIEST customers to sign up.
-- -----------------------------------------------------------------------------
-- The hint in the README warns that the earliest customers do NOT necessarily
-- have the lowest CUSTOMER_IDs, so we cannot just sort by ID — we must rank
-- by SIGNUP_DATE. The query selects every customer whose SIGNUP_DATE equals
-- the global minimum SIGNUP_DATE in the table, which correctly returns all
-- customers tied on that earliest day rather than a single arbitrary record.
-- A scalar subquery for MIN(SIGNUP_DATE) makes the intent explicit and
-- the optimizer evaluates it once thanks to the index on SIGNUP_DATE.
SELECT c.CUSTOMER_ID,
       c.NAME,
       c.CITY,
       c.SIGNUP_DATE,
       c.TARIFF_ID
FROM   CUSTOMERS c
WHERE  c.SIGNUP_DATE = (SELECT MIN(SIGNUP_DATE) FROM CUSTOMERS)
ORDER  BY c.CUSTOMER_ID;


-- -----------------------------------------------------------------------------
-- Q3.2  City distribution of those EARLIEST customers (with totals).
-- -----------------------------------------------------------------------------
-- Building on Q3.1, we restrict the data set to customers who signed up on
-- the very first day, then aggregate by CITY and count. The same scalar
-- subquery for MIN(SIGNUP_DATE) is reused so the two questions stay logically
-- aligned. Results are ordered by count descending and then by city name for
-- a deterministic, easy-to-read report.
SELECT c.CITY,
       COUNT(*) AS CUSTOMER_COUNT
FROM   CUSTOMERS c
WHERE  c.SIGNUP_DATE = (SELECT MIN(SIGNUP_DATE) FROM CUSTOMERS)
GROUP  BY c.CITY
ORDER  BY CUSTOMER_COUNT DESC, c.CITY;


-- -----------------------------------------------------------------------------
-- Q4.1  Identify customers whose monthly record is MISSING.
-- -----------------------------------------------------------------------------
-- Every customer should have one row in MONTHLY_STATS, but an insertion error
-- left some rows behind. A LEFT JOIN from CUSTOMERS to MONTHLY_STATS surfaces
-- the gap: any row where the right-hand side is NULL means no monthly record
-- exists for that customer. We could equivalently use a NOT EXISTS subquery;
-- the LEFT JOIN form is chosen here for readability and because it lets us
-- reuse the same join shape in Q4.2 below.
SELECT c.CUSTOMER_ID
FROM   CUSTOMERS     c
LEFT JOIN MONTHLY_STATS ms ON ms.CUSTOMER_ID = c.CUSTOMER_ID
WHERE  ms.CUSTOMER_ID IS NULL
ORDER  BY c.CUSTOMER_ID;


-- -----------------------------------------------------------------------------
-- Q4.2  City distribution of those missing customers.
-- -----------------------------------------------------------------------------
-- Same anti-join shape as Q4.1, but instead of listing IDs we aggregate by
-- CITY and count to see whether the missing rows cluster geographically. If
-- one city dominates the result it would suggest a region-specific issue in
-- the failed batch insert; an even spread instead suggests a random failure.
-- Sorting by descending count makes the worst-affected cities appear first.
SELECT c.CITY,
       COUNT(*) AS MISSING_COUNT
FROM   CUSTOMERS     c
LEFT JOIN MONTHLY_STATS ms ON ms.CUSTOMER_ID = c.CUSTOMER_ID
WHERE  ms.CUSTOMER_ID IS NULL
GROUP  BY c.CITY
ORDER  BY MISSING_COUNT DESC, c.CITY;


-- -----------------------------------------------------------------------------
-- Q5.1  Customers who have used at least 75% of their DATA limit.
-- -----------------------------------------------------------------------------
-- We compare each customer's monthly DATA_USAGE against the DATA_LIMIT of
-- their assigned tariff, joining all three tables. The 75% threshold is
-- expressed as DATA_USAGE >= DATA_LIMIT * 0.75 — staying on the multiplicative
-- side of the inequality avoids any floating-point surprises that division
-- could introduce. Customers on tariffs with DATA_LIMIT = 0 (e.g. 'Kurumsal
-- SMS') are excluded because the 75% concept is undefined for a zero limit;
-- those records would otherwise satisfy any non-negative usage trivially.
SELECT c.CUSTOMER_ID,
       c.NAME,
       t.NAME                                              AS TARIFF_NAME,
       ms.DATA_USAGE,
       t.DATA_LIMIT,
       ROUND(ms.DATA_USAGE / t.DATA_LIMIT * 100, 2)        AS USAGE_PCT
FROM   CUSTOMERS     c
JOIN   TARIFFS       t  ON t.TARIFF_ID  = c.TARIFF_ID
JOIN   MONTHLY_STATS ms ON ms.CUSTOMER_ID = c.CUSTOMER_ID
WHERE  t.DATA_LIMIT > 0
  AND  ms.DATA_USAGE >= t.DATA_LIMIT * 0.75
ORDER  BY USAGE_PCT DESC, c.CUSTOMER_ID;


-- -----------------------------------------------------------------------------
-- Q5.2  Customers who have COMPLETELY exhausted ALL package limits
--       (data AND minutes AND sms).
-- -----------------------------------------------------------------------------
-- "Completely exhausted" is interpreted as usage >= the corresponding limit
-- on every one of the three resources. Combining the three predicates with
-- AND ensures we only return customers who hit (or exceeded) every limit
-- simultaneously — partial exhaustion does not qualify. For tariffs whose
-- limit is 0 on a given resource, "usage >= 0" is trivially true, which
-- correctly reflects that there was nothing left to consume on that
-- resource to begin with.
SELECT c.CUSTOMER_ID,
       c.NAME,
       t.NAME           AS TARIFF_NAME,
       ms.DATA_USAGE,   t.DATA_LIMIT,
       ms.MINUTE_USAGE, t.MINUTE_LIMIT,
       ms.SMS_USAGE,    t.SMS_LIMIT
FROM   CUSTOMERS     c
JOIN   TARIFFS       t  ON t.TARIFF_ID    = c.TARIFF_ID
JOIN   MONTHLY_STATS ms ON ms.CUSTOMER_ID = c.CUSTOMER_ID
WHERE  ms.DATA_USAGE   >= t.DATA_LIMIT
  AND  ms.MINUTE_USAGE >= t.MINUTE_LIMIT
  AND  ms.SMS_USAGE    >= t.SMS_LIMIT
ORDER  BY c.CUSTOMER_ID;


-- -----------------------------------------------------------------------------
-- Q6.1  Customers with UNPAID fees.
-- -----------------------------------------------------------------------------
-- PAYMENT_STATUS is one of three values: PAID, LATE, UNPAID. The literal
-- "unpaid" is matched directly against 'UNPAID', which represents fees that
-- have not been paid at all. ('LATE' is interpreted as paid but past the due
-- date and is therefore excluded — adjust the IN-list if business rules
-- require treating LATE as unpaid.) The query also surfaces the customer's
-- tariff and monthly fee so collections / billing teams have the full
-- context they need in a single result set.
SELECT c.CUSTOMER_ID,
       c.NAME,
       c.CITY,
       t.NAME           AS TARIFF_NAME,
       t.MONTHLY_FEE,
       ms.PAYMENT_STATUS
FROM   CUSTOMERS     c
JOIN   TARIFFS       t  ON t.TARIFF_ID    = c.TARIFF_ID
JOIN   MONTHLY_STATS ms ON ms.CUSTOMER_ID = c.CUSTOMER_ID
WHERE  ms.PAYMENT_STATUS = 'UNPAID'
ORDER  BY c.CUSTOMER_ID;


-- -----------------------------------------------------------------------------
-- Q6.2  Distribution of ALL payment statuses across the different tariffs.
-- -----------------------------------------------------------------------------
-- The result is a 2-D crosstab: each row is one tariff and the columns count
-- how many of its subscribers fall into each payment status. SUM(CASE ...)
-- per status produces the pivoted columns; this is the most portable way to
-- pivot in Oracle and works in any version. A TOTAL column is added so the
-- per-tariff sanity check is trivial — paid + late + unpaid must equal total.
SELECT t.NAME                                                          AS TARIFF_NAME,
       SUM(CASE WHEN ms.PAYMENT_STATUS = 'PAID'   THEN 1 ELSE 0 END)   AS PAID,
       SUM(CASE WHEN ms.PAYMENT_STATUS = 'LATE'   THEN 1 ELSE 0 END)   AS LATE_CNT,
       SUM(CASE WHEN ms.PAYMENT_STATUS = 'UNPAID' THEN 1 ELSE 0 END)   AS UNPAID,
       COUNT(*)                                                        AS TOTAL
FROM   CUSTOMERS     c
JOIN   TARIFFS       t  ON t.TARIFF_ID    = c.TARIFF_ID
JOIN   MONTHLY_STATS ms ON ms.CUSTOMER_ID = c.CUSTOMER_ID
GROUP  BY t.NAME
ORDER  BY t.NAME;
