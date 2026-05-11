# Telco Project — i2i Systems

> A SQL analytics exercise on synthetic Turkish telecom data. The work consists of designing a relational schema, ingesting three CSV files into Oracle Database 21c Express Edition, and answering 11 business questions through SQL queries.

This repository is my solution to the [i2i Systems Telco Project](https://github.com/hantheemp/i2i-systems-telco-example) template.

---

## 🛠️ Tech Stack

| Component | Version / Detail |
|---|---|
| Database | Oracle Database 21c Express Edition (`gvenzl/oracle-xe:21-slim`) |
| Runtime | Docker Desktop (Windows / WSL 2) |
| SQL Client | DBeaver Community 26.0.x |
| Character set | AL32UTF8 (required for Turkish characters) |

---

## 📁 Repository Structure

```
telco-project/
├── README.md                      ← this file
├── TABLE_CREATION_SCRIPTS.sql     ← DDL: tables, constraints, indexes
├── SOLUTIONS.sql                  ← 11 queries with detailed comments
├── CUSTOMERS.csv                  ← 10,000 customer records
├── MONTHLY_STATS.csv              ← 9,950 monthly usage records
└── TARIFFS.csv                    ← 4 tariff definitions
```

---

## 🚀 Quick Start (Reproducible Setup)

### Prerequisites

- Docker Desktop installed and running
- DBeaver (Community Edition) installed
- ~1 GB free disk space for the Oracle image

> **Note for Apple Silicon / ARM users:** `gvenzl/oracle-xe` does not support ARM64. Use `gvenzl/oracle-free:23-slim` instead and substitute service name `FREEPDB1` for `XEPDB1` below. All queries work unchanged.

### 1 · Start Oracle XE in Docker

```bash
docker run -d \
  --name oracle-xe \
  -p 1521:1521 \
  -e ORACLE_PASSWORD=OraclePass123 \
  -e APP_USER=telco_user \
  -e APP_USER_PASSWORD=TelcoPass123 \
  -v oracle-volume:/opt/oracle/oradata \
  gvenzl/oracle-xe:21-slim
```

PowerShell one-liner:

```powershell
docker run -d --name oracle-xe -p 1521:1521 -e ORACLE_PASSWORD=OraclePass123 -e APP_USER=telco_user -e APP_USER_PASSWORD=TelcoPass123 -v oracle-volume:/opt/oracle/oradata gvenzl/oracle-xe:21-slim
```

Wait for `DATABASE IS READY TO USE!` to appear in the container logs (≈ 1–3 minutes on first run):

```bash
docker logs -f oracle-xe
```

### 2 · Connect via DBeaver

Create a new **Oracle** connection with these parameters:

| Setting | Value |
|---|---|
| Host | `localhost` |
| Port | `1521` |
| Database (use **Service Name**, not SID) | `XEPDB1` |
| Username | `telco_user` |
| Password | `TelcoPass123` |

DBeaver will offer to download the Oracle JDBC driver on first connect — accept.

### 3 · Create the schema

Open `TABLE_CREATION_SCRIPTS.sql` in a DBeaver SQL Editor and execute the whole script (`Alt + X`). This creates the three tables, all primary / foreign keys, check constraints, and helper indexes.

### 4 · Import the CSV data

For each CSV file, in this **strict order** (to satisfy foreign-key constraints):

1. **TARIFFS.csv** → `TARIFFS` table
2. **CUSTOMERS.csv** → `CUSTOMERS` table
3. **MONTHLY_STATS.csv** → `MONTHLY_STATS` table

For each one: right-click the target table in DBeaver → **Import Data** → select **CSV** → pick the file → set **Encoding** to `utf-8`.

> **CUSTOMERS.csv only:** on the column-mapping screen, set the `SIGNUP_DATE` column's format to `dd/MM/yyyy`. Otherwise the import will fail with `ORA-01843: not a valid month`.

### 5 · Verify the import

Run this sanity check:

```sql
SELECT 'TARIFFS'       AS TABLE_NAME, COUNT(*) AS ROW_COUNT FROM TARIFFS
UNION ALL SELECT 'CUSTOMERS',     COUNT(*) FROM CUSTOMERS
UNION ALL SELECT 'MONTHLY_STATS', COUNT(*) FROM MONTHLY_STATS;
```

Expected result:

| TABLE_NAME | ROW_COUNT |
|---|---:|
| TARIFFS | 4 |
| CUSTOMERS | 10,000 |
| MONTHLY_STATS | 9,950 |

### 6 · Run the queries

Open `SOLUTIONS.sql` in DBeaver. Place the cursor inside any query and press `Ctrl + Enter` to execute it individually.

---

## 🗺️ Schema Design

```
┌────────────────────┐         ┌────────────────────┐
│      TARIFFS       │         │     CUSTOMERS      │
├────────────────────┤         ├────────────────────┤
│ TARIFF_ID    PK    │◄────┐   │ CUSTOMER_ID    PK  │◄────┐
│ NAME         UQ    │     │   │ NAME               │     │
│ MONTHLY_FEE        │     └───│ TARIFF_ID      FK  │     │
│ DATA_LIMIT         │         │ CITY               │     │
│ MINUTE_LIMIT       │         │ SIGNUP_DATE        │     │
│ SMS_LIMIT          │         └────────────────────┘     │
└────────────────────┘                                    │
                                                          │
                              ┌────────────────────┐      │
                              │   MONTHLY_STATS    │      │
                              ├────────────────────┤      │
                              │ ID             PK  │      │
                              │ CUSTOMER_ID  FK/UQ │──────┘
                              │ DATA_USAGE         │
                              │ MINUTE_USAGE       │
                              │ SMS_USAGE          │
                              │ PAYMENT_STATUS     │
                              └────────────────────┘
```

### Key design decisions

- **`VARCHAR2(... CHAR)` semantics** — Turkish characters (ş, ğ, ı, İ, ç, ö, ü) count as 1 character each, regardless of their UTF-8 byte width. Sizes are generous (`50 CHAR` for names and cities, `100 CHAR` for tariff names).
- **`MONTHLY_STATS.CUSTOMER_ID` is `UNIQUE`** — each customer has exactly one monthly record by domain rule. Declaring uniqueness at the schema level prevents duplicate inserts and lets the optimizer use the unique index for joins.
- **`CHECK` constraints** validate domain values: `PAYMENT_STATUS IN ('PAID', 'LATE', 'UNPAID')` and `usage >= 0` on every numeric resource column. Bad data cannot enter the database, even via a buggy ETL job.
- **Targeted indexes** — secondary indexes on `TARIFF_ID`, `SIGNUP_DATE`, `CITY` (CUSTOMERS) and `PAYMENT_STATUS` (MONTHLY_STATS) cover the columns hit by `WHERE` / `GROUP BY` in the 11 analytical queries.

---

## 📊 Results Summary

| # | Question | Result |
|---|---|---|
| **1.1** | Subscribers of the `Kobiye Destek` tariff | **2,483** customers |
| **1.2** | Newest subscriber(s) of `Kobiye Destek` | **7 customers** tied on `2026-04-05` |
| **2.1** | Distribution of tariffs across all customers | Kurumsal SMS 25.77% · Genç Dinamik 25.27% · Kobiye Destek 24.83% · Çalışan GB 24.13% |
| **3.1** | Earliest customers to sign up (`2025-04-07`) | **35** customers (CUSTOMER_IDs scattered across the full range — earliest are *not* the lowest IDs) |
| **3.2** | City distribution of the earliest customers | 30 distinct cities; ties at the top (ANTALYA, GAZİANTEP, SAKARYA, YOZGAT, ŞIRNAK with 2 each) |
| **4.1** | Customers whose monthly record is missing | **50** customers (IDs include 6, 10, 31, 39, 45, 81, 116, 136, 140, 156, …) |
| **4.2** | City distribution of missing customers | 39 distinct cities; OSMANİYE most affected (3); rest spread out, suggesting a random insertion failure rather than a regional issue |
| **5.1** | Customers using ≥ 75% of their data limit | See SOLUTIONS.sql output (excludes `Kurumsal SMS` whose data limit is 0) |
| **5.2** | Customers who completely exhausted ALL limits | **0 customers** — see ⚠️ note below |
| **6.1** | Customers with unpaid (`UNPAID`) fees | **1,454** customers (≈ 14.6% of monthly records) |
| **6.2** | Payment status by tariff (crosstab) | 4 rows × 4 columns (PAID / LATE / UNPAID / TOTAL); per-tariff totals sum to 9,950 |

### ⚠️ Note on Q5.2

The query for *"customers who have completely exhausted all of their package limits"* returns **0 rows** against the provided dataset. This is not a bug — it is a property of the generated data:

| Resource | Maximum value observed | Tariff limit |
|---|---:|---:|
| `DATA_USAGE` | 20,476.31 | 20,480 |
| `MINUTE_USAGE` | 999 | 1,000 |
| `SMS_USAGE` | 9,999 | 10,000 |

Every usage value in the dataset sits just below its corresponding limit, so no record satisfies `usage >= limit` simultaneously on data, minutes **and** SMS. The query is logically correct and would surface any qualifying customer the moment such a row appears in `MONTHLY_STATS`. The detailed reasoning is preserved in a comment block above the query in `SOLUTIONS.sql`.

---

## 🧹 Cleanup

```bash
docker stop oracle-xe                # stop, keep data
docker start oracle-xe               # restart later — data persists
docker rm -f oracle-xe               # remove container, keep volume
docker volume rm oracle-volume       # nuke the data too
```

---

## 📚 References

- Original task template: <https://github.com/hantheemp/i2i-systems-telco-example>
- `gvenzl/oracle-xe` image: <https://hub.docker.com/r/gvenzl/oracle-xe>
- DBeaver Community: <https://dbeaver.io/>
