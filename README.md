# Retail Real-Time Product Catalog Update (MuleSoft 4 / Anypoint Studio)

[![Mule Runtime](https://img.shields.io/badge/Mule%20Runtime-4.4.0%2B-blue.svg)](https://www.mulesoft.com/)
[![Anypoint Studio](https://img.shields.io/badge/Anypoint%20Studio-7.x-orange.svg)](https://www.mulesoft.com/platform/studio)
[![MUnit Coverage](https://img.shields.io/badge/MUnit%20Tests-Passing-brightgreen.svg)]()

Production-grade Mule 4 application for the **Cognizant 2027 Nurture Partner Network (NPN) MuleSoft Hackathon Challenge – Retail Real Time Product Catalog Update**.

---

## 🚀 Key Features & Architecture

1. **File Intake & Duplicate Check (`catalog-intake-flow.xml`)**:
   - Watches inbound directory with the File Connector for pattern `CATALOG_*.csv`.
   - Uses file size locks (`timeBetweenSizeCheck="1000"`) to prevent reading partially written files.
   - Computes SHA-256 file checksum and queries `catalog_import_runs` to ignore duplicate files without processing or issuing redundant CDN invalidations.
   - Moves files to `data/in-process/` before streaming.

2. **Streamed Parsing & Batch Processing (`catalog-processing-flow.xml`)**:
   - Parses pipe-delimited records (`separator="|"`, `streaming=true`).
   - Uses `<batch:job>` with a configurable block size (`500`) to process tens of thousands of catalog records without exhausting JVM memory.
   - **Record Validation**: Validates SKU, product name, price (>0), 3-letter currency code, category code (`CAT-*`), stock status, product status, and malformed image paths (`/img/*`).
   - **SHA-256 Content Hashing**: Hashes 10 business fields to recognize `UNCHANGED` records in O(1) comparison against stored hashes.
   - **Delta Classification**: Classifies records into:
     - `NEW`: Inserts product and logs history.
     - `UNCHANGED`: Zero database writes and zero history records.
     - `CHANGED_CUSTOMER_FACING`: Updates database and marks paths for CDN invalidation.
     - `CHANGED_INTERNAL_ONLY`: Updates database only; triggers zero CDN invalidations.
   - **Price Change Guardrail**: Detects swings exceeding configured limits (+50% increase or -40% decrease), holding them for review (`HOLD_FOR_REVIEW`) with stored prices intact.
   - **Delisting Logic**: On full extract runs (`CATALOG_FULL_*`), detects products in DB absent from the extract and marks them `DELISTED` (never deletes rows).

3. **CDN Cache Invalidation (`cdn-invalidation-flow.xml`)**:
   - Generates invalidation paths (`/p/{sku}`, `/p/{sku}/images`, `/c/{categoryCode}`).
   - Deduplicates paths and groups them into batches of max 30 paths (`maxPathsPerRequest: 30`).
   - Dispatches HTTP POST requests to CDN provider.
   - **HTTP 429 Rate Limit Compliance**: Handles rate limits using exponential backoff and retries (`until-successful`).
   - **HTTP 207 Multi-Status**: Handles partial rejections and tracks unconfirmed paths.
   - Records all attempts in `cdn_invalidations` table.

4. **Audit & Lineage (`catalog-persistence-flow.xml`)**:
   - Persists execution state in `catalog_import_runs`.
   - Records field-level before/after diffs in `product_change_history`.

5. **Built-in Studio Test Service (`catalog-api.xml`)**:
   - Includes REST endpoints to trigger catalog parsing manually via HTTP (`POST /api/v1/catalog/trigger`).
   - Includes query endpoints: `/api/v1/catalog/runs`, `/api/v1/catalog/products`, `/api/v1/catalog/history`, `/api/v1/catalog/invalidations`.
   - Includes a built-in Mock CDN service (`POST /mock-cdn/api/v2/invalidations`) so the application is 100% self-contained and runnable in Anypoint Studio right after import.

---

## 📁 Project Structure

```
d:/deva-musesoft/
├── pom.xml                                           # Maven build & dependencies descriptor
├── mule-artifact.json                                # Mule 4 artifact configuration
├── .project                                          # Anypoint Studio / Eclipse project file
├── .classpath                                        # Anypoint Studio classpath file
├── data/
│   ├── input/                                        # Inbound CSV watcher directory
│   ├── in-process/                                    # Active ingestion directory
│   ├── archive/                                      # Successfully processed file archive
│   └── error/                                        # Failed file directory
└── src/
    ├── main/
    │   ├── mule/
    │   │   ├── global-config.xml                     # Connector configurations & properties
    │   │   ├── global-error-handler.xml              # Global error handling & retries
    │   │   ├── catalog-intake-flow.xml               # File intake, checksum & duplicate guard
    │   │   ├── catalog-processing-flow.xml           # Streamed Batch job & delta classification
    │   │   ├── catalog-persistence-flow.xml          # Selective DB update, delisting & history
    │   │   ├── cdn-invalidation-flow.xml             # Path grouping, CDN dispatch & 429 handling
    │   │   └── catalog-api.xml                       # HTTP REST trigger & Mock CDN service
    │   └── resources/
    │       ├── config/
    │       │   ├── catalog-delta.yaml                # Delta rules, thresholds, path templates
    │       │   └── config-dev.yaml                   # Connection properties & ports
    │       ├── db/
    │       │   └── schema.sql                        # Database table DDL script
    │       ├── dwl/
    │       │   ├── compute-hash.dwl                  # SHA-256 hash generator
    │       │   ├── validate-record.dwl               # Business validation
    │       │   ├── classify-delta.dwl                # Delta classifier & field diffing
    │       │   ├── price-guard-check.dwl             # Price swing calculation
    │       │   ├── build-invalidation-payload.dwl     # CDN request payload builder
    │       │   └── map-history-records.dwl           # History audit row mapping
    │       ├── sample-data/
    │       │   ├── CATALOG_FULL_20260911_0600.csv    # Sample full extract
    │       │   ├── CATALOG_DELTA_20260911_0700.csv   # Sample delta extract
    │       │   └── CATALOG_SUSPICIOUS_PRICE.csv      # Sample price swing violation
    │       └── log4j2.xml
    └── test/
        ├── mule/
        │   └── catalog-update-test-suite.xml         # Complete MUnit test suite
        └── resources/
            └── log4j2-test.xml
```

---

## 🛠️ How to Import and Run in Anypoint Studio

### Step 1: Open in Anypoint Studio
1. Open **Anypoint Studio 7.x**.
2. Select **File** -> **Open Projects from File System...** (or **File** -> **Import...** -> **Anypoint Studio** -> **Anypoint Studio project from External Location**).
3. Set the directory path to:
   ```
   d:\deva-musesoft
   ```
4. Click **Finish**.

### Step 2: Database Setup
The application is pre-configured with an in-memory **H2 Database** operating in MySQL mode (`jdbc:h2:mem:retail_catalog;DB_CLOSE_DELAY=-1;MODE=MySQL;DATABASE_TO_LOWER=TRUE`) with automatic table creation via `src/main/resources/db/schema.sql`.

If you prefer external **MySQL**:
1. Open `src/main/resources/config/config-dev.yaml`.
2. Update the `db` properties:
   ```yaml
   db:
     driverClassName: "com.mysql.cj.jdbc.Driver"
     url: "jdbc:mysql://localhost:3306/retail_catalog?useSSL=false"
     user: "root"
     password: "your_password"
   ```
3. Run the DDL script in `src/main/resources/db/schema.sql` on your MySQL server.

### Step 3: Run the Application
1. In Package Explorer, right click on `retail-catalog-update-papi`.
2. Select **Run As** -> **Mule Application**.
3. Wait until the console displays:
   ```
   **********************************************************************
   * Application: retail-catalog-update-papi                            *
   * OS-Architecture: x86_64                                            *
   * Server-State: STARTED                                              *
   **********************************************************************
   ```

---

## 🧪 Testing the Solution

### Option A: Automatic File Drop
1. Copy `CATALOG_FULL_20260911_0600.csv` from `src/main/resources/sample-data/` into `data/input/`.
2. The file listener will automatically detect the file, move it to `data/in-process/`, process the batch, insert new products, trigger CDN invalidations, and move the completed file to `data/archive/`.
3. Drop the same file again to verify duplicate detection: the run will skip processing with zero duplicate invalidations!

### Option B: HTTP REST Ingestion & Inspection
You can test and inspect the data directly via HTTP (Port `8081`):

1. **Trigger Ingestion**:
   ```bash
   POST http://localhost:8081/api/v1/catalog/trigger
   Header: filename = CATALOG_FULL_20260911_0600.csv
   Body (text/csv): [paste content of CATALOG_FULL_20260911_0600.csv]
   ```

2. **Check Audit Runs**:
   ```bash
   GET http://localhost:8081/api/v1/catalog/runs
   ```

3. **Check Products in Database**:
   ```bash
   GET http://localhost:8081/api/v1/catalog/products
   ```

4. **Check Field-by-Field Change History**:
   ```bash
   GET http://localhost:8081/api/v1/catalog/history
   ```

5. **Check CDN Invalidation Requests**:
   ```bash
   GET http://localhost:8081/api/v1/catalog/invalidations
   ```

---

## 📊 Running MUnit Tests

Run all automated MUnit test scenarios:
```bash
mvn clean test
```

The test suite covers:
- **Test 1**: New product classification & database insertion.
- **Test 2**: Customer-facing field change triggers CDN invalidation call.
- **Test 3**: Internal-only change (tax class) updates DB with 0 CDN invalidations.
- **Test 4**: Suspicious price swing (drop from 920 to 92) held for review (`HOLD_FOR_REVIEW`).
- **Test 5**: Full extract delisting marks absent active products as `DELISTED`.
- **Test 6**: Duplicate file detection skips processing with zero invalidations.
