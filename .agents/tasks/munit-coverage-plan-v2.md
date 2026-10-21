# MUnit Coverage Plan v2 - Retail Catalog Update PAPI 6
## Target: 90% Coverage across all 7 flows

**Current Status**: ~39% coverage (18 tests) | **Target**: 90%+ coverage with targeted path-based tests

---

## Project Architecture Overview

### Flow Files & Functions
1. **catalog-api.xml** - HTTP entry point (0% coverage) → 7 flows
   - `trigger-catalog-ingest-api-flow` (HTTP listener + APIKit router)
   - `retail-catalog-apikit-console` (Console listener)
   - `post:\catalog\trigger:retail-catalog-apikit-config` (POST /catalog/trigger)
   - `get:\catalog\runs:retail-catalog-apikit-config` (GET /catalog/runs)
   - `get:\catalog\products:retail-catalog-apikit-config` (GET /catalog/products)
   - `get:\catalog\history:retail-catalog-apikit-config` (GET /catalog/history)
   - `get:\catalog\invalidations:retail-catalog-apikit-config` (GET /catalog/invalidations)
   - `mock-cdn-invalidation-service-flow` (Mock CDN, 3 response paths: 202 / 207 / 429)

2. **catalog-intake-flow.xml** (~55% coverage) → 3 flows
   - `catalog-file-intake-listener-flow` (File listener)
   - `catalog-file-intake-orchestrator-flow` (Duplicate check, truncated extract guard, rejection threshold)
   - `run-catalog-ingestion-subflow` (Batch trigger)

3. **catalog-processing-flow.xml** (~86% coverage) → 1 flow + 4 batch steps
   - `catalog-batch-processing-flow` (Main batch orchestrator)
     - Step 1: ValidationStep (parse validation → pass/fail)
     - Step 2: DeltaClassificationStep (hash, delta type detection)
     - Step 3: PriceGuardStep (price swing detection)
     - Step 4: PersistenceStep (selective persist)
     - on-complete: Counts, delisting, CDN, finalize

4. **catalog-persistence-flow.xml** (~83% coverage) → 3 sub-flows
   - `persist-product-record-subflow` (NEW / CHANGED_CUSTOMER_FACING / CHANGED_INTERNAL_ONLY / HOLD_FOR_REVIEW)
   - `evaluate-full-extract-delisting-subflow` (FULL vs DELTA, mark delisted)
   - `finalize-catalog-import-run-subflow` (Aggregate counts, write audit, alerts)

5. **cdn-invalidation-flow.xml** (~9% coverage) → 2 sub-flows
   - `trigger-cdn-invalidation-orchestrator-subflow` (Query changed products, batch generation)
   - `dispatch-cdn-invalidation-batch-subflow` (HTTP call, 207 retry, 429 backoff, error handling)

6. **global-error-handler.xml** (0% coverage) → 9 on-error handlers
   - APIKIT errors: 404, 405, 406, 415, 400 (5 handlers)
   - File system errors (1 handler: move to error dir)
   - DB connectivity (1 handler: propagate)
   - DB query execution (1 handler: propagate)
   - HTTP CDN errors (1 handler: continue, record pending)
   - Expression/transformation (1 handler: propagate)
   - Retry exhausted (1 handler: continue, mark unconfirmed)
   - Generic ANY fallback (1 handler: propagate)

7. **global-config.xml** → 1 flow
   - `db-schema-initialisation-flow` (Create 4 tables)

---

## Coverage Gaps & Uncovered Paths

### catalog-api.xml (0% coverage — 0/8 flows tested)

**Uncovered Flows:**
1. `trigger-catalog-ingest-api-flow` → Not called; need HTTP GET/POST to /api/v1/catalog/*
2. `retail-catalog-apikit-console` → HTTP listener on /api/v1/catalog/console/*
3. `post:\catalog\trigger:retail-catalog-apikit-config` → POST /catalog/trigger (manually triggered ingestion)
4. `get:\catalog\runs:retail-catalog-apikit-config` → SELECT all import runs
5. `get:\catalog\products:retail-catalog-apikit-config` → SELECT all products
6. `get:\catalog\history:retail-catalog-apikit-config` → SELECT all history
7. `get:\catalog\invalidations:retail-catalog-apikit-config` → SELECT all invalidations
8. `mock-cdn-invalidation-service-flow` → Mock CDN service (3 branches: 202 accepted / 207 partial / 429 rate limit)

**Strategy:** APIKit router flows cannot be invoked directly via flow-ref in unit tests; use flow-ref to the APIKit-generated sub-flow names. Test via direct HTTP requests to the listener, or use MUnit's HTTP test driver.

---

### global-error-handler.xml (0% coverage — 0/9 handlers tested)

**Uncovered Handlers:**
1. APIKIT:NOT_FOUND (404)
2. APIKIT:METHOD_NOT_ALLOWED (405)
3. APIKIT:NOT_ACCEPTABLE (406)
4. APIKIT:UNSUPPORTED_MEDIA_TYPE (415)
5. APIKIT:BAD_REQUEST (400)
6. FILE:ACCESS_DENIED / FILE:ILLEGAL_PATH / FILE:FILE_ALREADY_EXISTS (file errors)
7. DB:CONNECTIVITY
8. DB:QUERY_EXECUTION / DB:BAD_SQL_SYNTAX
9. HTTP:CONNECTIVITY / HTTP:TIMEOUT / HTTP:TOO_MANY_REQUESTS / HTTP:SERVICE_UNAVAILABLE (CDN errors)
10. EXPRESSION / TRANSFORMATION (DataWeave errors)
11. MULE:RETRY_EXHAUSTED
12. ANY fallback

**Strategy:** Error handlers are only invoked when an exception occurs within a flow that references the global-error-handler. Test by:
1. Create a test flow that calls a processor expected to throw each error type
2. Mock the processor with `munit-tools:mock-when` to throw the specific error
3. Verify the error handler transforms the error into the expected JSON response

**Example Approach:**
- For APIKIT:NOT_FOUND → mock an apikit:router that throws APIKIT:NOT_FOUND
- For FILE:ACCESS_DENIED → mock a file:move that throws FILE:ACCESS_DENIED
- For DB:CONNECTIVITY → mock a db:select that throws DB:CONNECTIVITY
- For HTTP:TOO_MANY_REQUESTS → mock an http:request that throws HTTP:TOO_MANY_REQUESTS

---

### catalog-intake-flow.xml (~55% coverage — missing 3 key paths)

**Uncovered Paths:**
1. **Duplicate Detection Branch** (DB returns non-empty) → File skipped with zero invalidations
   - Condition: `!isEmpty(payload)` on duplicate check SELECT
   - Currently not tested

2. **Truncated FULL Extract Guard** (recordCount < minRecordCount)
   - Condition: `vars.extractType == 'FULL' AND vars.recordCount < vars.minRecordCount`
   - File moved to error directory
   - Currently not tested

3. **Rejection Threshold Exceeded Branch** (rejected% > maxRejectPercentAllowed)
   - Condition: `vars.rejectionCheck.thresholdExceeded == true`
   - Run marked ABORTED_HIGH_REJECTION
   - File moved to error directory
   - Currently not tested

---

### catalog-processing-flow.xml (~86% coverage — missing 1 key path)

**Uncovered Path:**
1. **Price Guard Suspicious Swing → HOLD_FOR_REVIEW** (Step 3 trigger)
   - Condition: `vars.priceGuard.isSuspicious == true`
   - Classification override to HOLD_FOR_REVIEW
   - Currently tested in test-06 but assertion is minimal; need detailed price swing values

---

### cdn-invalidation-flow.xml (~9% coverage — missing 8+ paths)

**Uncovered Paths:**
1. **207 Partial Rejection Loop** (dispatch-cdn-invalidation-batch-subflow)
   - CDN returns 207 with rejected paths array
   - Each rejected path retried individually in foreach
   - Each retry result recorded in cdn_invalidations

2. **429 Rate Limit Backoff** (dispatch-cdn-invalidation-batch-subflow)
   - until-successful catches HTTP:TOO_MANY_REQUESTS
   - Reads Retry-After header (seconds)
   - Sleeps for that duration before retry
   - Currently not tested

3. **Transient HTTP Error Retry** (HTTP:CONNECTIVITY / HTTP:TIMEOUT)
   - until-successful catches and retries up to 3 times
   - Currently not tested

4. **Permanent CDN Failure** (on-error-continue ANY after 3 retries)
   - Records batch as PENDING_RETRY in cdn_invalidations
   - DB not rolled back (as per PDF requirement)
   - Currently not tested

5. **Retry-Exhausted Handler** (global-error-handler)
   - until-successful throws MULE:RETRY_EXHAUSTED after maxRetries exceeded
   - on-error-continue records as RETRY_EXHAUSTED in db
   - Currently not tested

---

### catalog-persistence-flow.xml (~83% coverage — missing 1 key path)

**Uncovered Path:**
1. **HOLD_FOR_REVIEW Classification** (persist-product-record-subflow)
   - Price guard override sets review_hold = TRUE
   - History row written but price NOT updated
   - Currently not tested

2. **Foreach Loop for CHANGED History Rows** (persist-product-record-subflow)
   - For CHANGED_CUSTOMER_FACING and CHANGED_INTERNAL_ONLY, multiple history rows written
   - One per field diff (fieldName, oldValue, newValue, customerFacing)
   - Currently not fully exercised (need explicit multi-diff record)

3. **Delisting Absent Products** (evaluate-full-extract-delisting-subflow)
   - FULL extract marks old active products as DELISTED
   - History row written per delisted product
   - Currently not tested

---

## Detailed Test Plan: 30+ New Tests → 90%+ Coverage

### Test Naming Convention
`test-NN-<flow>-<scenario>` where:
- NN = Test number (01-50)
- flow = catalog / intake / batch / cdn / error / api
- scenario = Specific condition being tested

---

## TEST GROUP 1: catalog-api.xml (8 tests)

### Test 1.1: POST /catalog/trigger — Manual Ingestion Success (202 Accepted)
**Flow to test:** `post:\catalog\trigger:retail-catalog-apikit-config` (via HTTP POST)
**Variables to set:**
- `fileName` = "CATALOG_MANUAL_20261015_1234.csv"
- `payload` = 100 valid product records (piped CSV)

**Mocks:**
- `db:select` (duplicate check) → return [] (no duplicates)
- `db:insert` (audit record) → return {affectedRows: 1}
- `file:move` (archive) → return payload

**Assertions:**
- Response status = 202 or 200
- Response JSON contains `runId`, `status: "ACCEPTED"`, `message`
- `db:insert` called for audit record
- `catalog-batch-processing-flow` invoked (verify via logger or spy)

**Verify:** HTTP flow-ref works; POST triggers intake orchestrator

---

### Test 1.2: GET /catalog/runs — Retrieve All Runs
**Flow to test:** `get:\catalog\runs:retail-catalog-apikit-config` (via HTTP GET)

**Mocks:**
- `db:select` (SELECT * FROM catalog_import_runs) → return [{runId: "RUN-A", status: "COMPLETED"}, ...]

**Assertions:**
- Response status = 200
- Response body is JSON array of runs
- Result count matches mock return

**Verify:** GET endpoint returns runs list

---

### Test 1.3: GET /catalog/products — Retrieve All Products
**Flow to test:** `get:\catalog\products:retail-catalog-apikit-config` (via HTTP GET)

**Mocks:**
- `db:select` (SELECT * FROM products) → return [{sku: "SKU-1", productName: "Prod1"}, ...]

**Assertions:**
- Response status = 200
- Response body is JSON array of products

**Verify:** GET endpoint returns products list

---

### Test 1.4: GET /catalog/history — Retrieve All Change History
**Flow to test:** `get:\catalog\history:retail-catalog-apikit-config` (via HTTP GET)

**Mocks:**
- `db:select` (SELECT * FROM product_change_history) → return [{sku: "SKU-1", change_type: "NEW"}, ...]

**Assertions:**
- Response status = 200
- Response body is JSON array of history

**Verify:** GET endpoint returns history

---

### Test 1.5: GET /catalog/invalidations — Retrieve CDN Invalidation Records
**Flow to test:** `get:\catalog\invalidations:retail-catalog-apikit-config` (via HTTP GET)

**Mocks:**
- `db:select` (SELECT * FROM cdn_invalidations) → return [{runId: "RUN-A", request_ref: "BATCH-1"}, ...]

**Assertions:**
- Response status = 200
- Response body is JSON array of invalidations

**Verify:** GET endpoint returns invalidations

---

### Test 1.6: Mock CDN Service — 202 Accepted Response
**Flow to test:** `mock-cdn-invalidation-service-flow` (direct POST to /mock-cdn/api/v2/invalidations)

**Payload:** `{distributionId: "DIST-1", paths: ["/p/SKU-1", "/p/SKU-1/images", "/c/CAT-1"]}`

**Execution:**
- HTTP POST /mock-cdn/api/v2/invalidations with no simulate-* headers

**Assertions:**
- Response status = 202
- Response JSON contains `invalidationId`, `status: "IN_PROGRESS"`, `pathCount: 3`

**Verify:** Mock CDN accepts batch and returns 202

---

### Test 1.7: Mock CDN Service — 207 Partial Rejection
**Flow to test:** `mock-cdn-invalidation-service-flow`

**Payload:** `{distributionId: "DIST-1", paths: ["/p/INVALID/path", "/p/SKU-1", "/c/CAT-1"]}`

**Headers:** `simulate-multi-status: true`

**Assertions:**
- Response status = 207
- Response JSON contains `accepted: ["/p/SKU-1", "/c/CAT-1"]`
- Response JSON contains `rejected: [{path: "/p/INVALID/path", reason: "INVALID_PATH_PATTERN"}]`

**Verify:** Mock CDN returns 207 with rejected paths

---

### Test 1.8: Mock CDN Service — 429 Rate Limit
**Flow to test:** `mock-cdn-invalidation-service-flow`

**Headers:** `simulate-rate-limit: true`

**Assertions:**
- Response status = 429
- Response JSON contains `error: "RATE_LIMIT_EXCEEDED"`, `retryAfterSeconds: 30`

**Verify:** Mock CDN returns 429 with Retry-After

---

## TEST GROUP 2: global-error-handler.xml (12 tests)

### Test 2.1: APIKIT:NOT_FOUND (404)
**Strategy:** Create a test flow that mocks apikit:router to throw APIKIT:NOT_FOUND

**Test Flow:**
```xml
<flow name="test-apikit-404-flow">
    <set-payload value="#[payload]" />
    <munit-tools:mock-when processor="apikit:router">
        <munit-tools:then-return type="error">
            <munit-tools:error type="APIKIT:NOT_FOUND" />
        </munit-tools:then-return>
    </munit-tools:mock-when>
</flow>
```

**Execution:** Invoke test flow

**Assertions:**
- Error caught by global-error-handler
- Response status = 404
- Response JSON contains `status: 404, errorCode: "RESOURCE_NOT_FOUND"`

**Verify:** 404 handler transforms error

---

### Test 2.2: APIKIT:METHOD_NOT_ALLOWED (405)
Similar to 2.1, but mock apikit:router → APIKIT:METHOD_NOT_ALLOWED
**Expected response:** 405, errorCode: "METHOD_NOT_ALLOWED"

---

### Test 2.3: APIKIT:NOT_ACCEPTABLE (406)
Mock apikit:router → APIKIT:NOT_ACCEPTABLE
**Expected response:** 406, errorCode: "NOT_ACCEPTABLE"

---

### Test 2.4: APIKIT:UNSUPPORTED_MEDIA_TYPE (415)
Mock apikit:router → APIKIT:UNSUPPORTED_MEDIA_TYPE
**Expected response:** 415, errorCode: "UNSUPPORTED_MEDIA_TYPE"

---

### Test 2.5: APIKIT:BAD_REQUEST (400)
Mock apikit:router → APIKIT:BAD_REQUEST with description "Invalid JSON"
**Expected response:** 400, errorCode: "BAD_REQUEST", message: "Invalid JSON"

---

### Test 2.6: FILE:ACCESS_DENIED
**Test Flow:** Mock file:move → FILE:ACCESS_DENIED

**Execution:** 
- Set `vars.fileName` and `vars.runId`
- Mock file:move to throw FILE:ACCESS_DENIED

**Assertions:**
- Error caught by global-error-handler
- Response status = not set (on-error-continue)
- Response JSON contains `errorCode: "FILE_SYSTEM_ERROR"`, `message: "File access or directory permission error"`
- `db:update` called to mark run FAILED (verify mock was called)

**Verify:** FILE:ACCESS_DENIED handler recorded as on-error-continue

---

### Test 2.7: DB:CONNECTIVITY
**Test Flow:** Mock db:select → DB:CONNECTIVITY

**Assertions:**
- Error propagates (on-error-propagate)
- Response JSON contains `errorCode: "DB_CONNECTIVITY_ERROR"`, message about transient retry

---

### Test 2.8: DB:QUERY_EXECUTION
**Test Flow:** Mock db:select → DB:QUERY_EXECUTION with description "Syntax error"

**Assertions:**
- Error propagates
- Response JSON contains `errorCode: "DB_QUERY_ERROR"`
- `db:update` called to mark run FAILED

---

### Test 2.9: HTTP:TOO_MANY_REQUESTS (429 CDN error)
**Test Flow:** Mock http:request → HTTP:TOO_MANY_REQUESTS

**Execution:**
- Set `vars.runId`, `vars.requestReference`, `vars.currentBatchPaths`
- Mock http:request to throw HTTP:TOO_MANY_REQUESTS

**Assertions:**
- Error caught by CDN HTTP on-error-continue
- `db:insert` called to record as PENDING_RETRY
- Response JSON contains `errorCode: "CDN_INVALIDATION_PENDING"`

---

### Test 2.10: HTTP:CONNECTIVITY (CDN connection lost)
**Test Flow:** Mock http:request → HTTP:CONNECTIVITY

**Assertions:**
- `db:insert` called to record as PENDING_RETRY
- Response JSON contains `errorCode: "CDN_INVALIDATION_PENDING"`

---

### Test 2.11: MULE:RETRY_EXHAUSTED (from until-successful)
**Test Flow:** until-successful with mock that always fails

**Execution:**
- Mock http:request to throw HTTP:CONNECTIVITY
- until-successful maxRetries=3 → after 3 failures, throws MULE:RETRY_EXHAUSTED
- Global error handler catches it

**Assertions:**
- MULE:RETRY_EXHAUSTED on-error-continue triggered
- `db:insert` called to record as RETRY_EXHAUSTED
- Response indicates "All retries exhausted"

---

### Test 2.12: ANY Fallback (generic error)
**Test Flow:** Mock a processor to throw an unexpected error type

**Execution:**
- Mock any processor to throw a custom error not covered by specific handlers
- Flow throws error

**Assertions:**
- ANY handler catches it
- Response status = 500
- Response JSON contains `errorCode: "INTERNAL_SERVER_ERROR"`, `errorType: "CUSTOM_ERROR"`
- `db:update` called to mark run FAILED

---

## TEST GROUP 3: catalog-intake-flow.xml (3 tests — Missing Path Coverage)

### Test 3.1: Duplicate File Detection
**Flow to test:** `catalog-file-intake-orchestrator-flow`

**Setup:**
- `vars.fileName` = "CATALOG_FULL_test.csv"
- Payload = 100 records

**Mock:**
- `db:select` (duplicate check) → return [{run_id: "RUN-OLD", run_status: "COMPLETED"}] (duplicate found)
- All other db:* → default mocks

**Assertions:**
- Response JSON contains `status: "SKIPPED_DUPLICATE"`, message about already processed
- File NOT moved to archive (because ingestion was skipped)
- No batch processing occurs

**Verify:** Duplicate check correctly skips duplicate files

---

### Test 3.2: Truncated FULL Extract Guard
**Flow to test:** `catalog-file-intake-orchestrator-flow`

**Setup:**
- `vars.fileName` = "CATALOG_FULL_test.csv" (FULL extract detected)
- Payload = 50 records (below minRecordCount)

**Mock:**
- `db:select` (duplicate check) → return [] (no duplicates)
- `file:move` (move to error) → return payload
- Configuration: `fullExtractPolicy.requireMinimumRecordCount = 1000`

**Assertions:**
- Response JSON contains `status: "ABORTED_TRUNCATED_EXTRACT"`, `recordCount: 50`, `minimumRequired: 1000`
- `file:move` called to move to error directory
- No batch processing
- `db:insert` NOT called (run never inserted)

**Verify:** Truncated full extracts are caught and moved to error directory

---

### Test 3.3: Rejection Threshold Exceeded
**Flow to test:** `run-catalog-ingestion-subflow` (via orchestrator-flow by simulating post-batch counts)

**Setup:**
- Payload = 100 records
- `vars.fileName` = "CATALOG_FULL_high_rejection.csv"
- Simulate batch with 50 rejected out of 100 parsed (50%)

**Mock:**
- `db:insert` (audit record) → return {affectedRows: 1}
- `db:select` (post-batch counts) → return [{parsed_count: 100, rejected_count: 50, run_status: "IN_PROGRESS"}]
- `db:update` (mark ABORTED) → return {affectedRows: 1}
- `file:move` (move to error) → return payload
- Configuration: `processing.maxRejectPercentAllowed = 5`

**Assertions:**
- Response JSON contains `status: "ABORTED_HIGH_REJECTION"`, `rejected: 50`, `parsed: 100`, `rejectPercent: 50`
- `db:update` called to mark run ABORTED_HIGH_REJECTION
- `file:move` called to move to error directory
- No CDN invalidations issued

**Verify:** High rejection runs are aborted

---

## TEST GROUP 4: catalog-processing-flow.xml (2 tests — Enhanced Price Guard Coverage)

### Test 4.1: Price Guard Extreme Increase Triggers HOLD
**Flow to test:** `catalog-batch-processing-flow` (PriceGuardStep)

**Setup:**
- Payload = 1 record: `{sku: "EXTREME-UP", productName: "Prod", categoryCode: "CAT-APP", brand: "B", price: "5000", currency: "INR", taxClass: "GST12", stockStatus: "IN_STOCK", productStatus: "ACTIVE", shortDescription: "Huge increase", imagePath: "/img/huge.jpg"}`
- `vars.storedProduct` = {price: 100} (existing product at 100, now 5000 = 4900% increase)

**Mock:**
- `db:select` (query existing product) → return vars.storedProduct
- Configuration: `priceGuard.maxIncreasePercent = 50`

**Assertions:**
- Batch step 3 (PriceGuardStep) detection: `vars.priceGuard.isSuspicious == true`
- Classification override: `vars.deltaClassification.classification == "HOLD_FOR_REVIEW"`
- Logger alert: "PRICE_GUARD_TRIGGERED" appears in logs
- Persistence step: proceeds with HOLD_FOR_REVIEW (review_hold = TRUE, price NOT updated)

**Verify:** Extreme price increases trigger HOLD_FOR_REVIEW override

---

### Test 4.2: Price Guard Extreme Decrease Triggers HOLD
**Setup:**
- Payload = 1 record: `{sku: "EXTREME-DOWN", ..., price: "10"}`
- `vars.storedProduct` = {price: 1000} (existing product at 1000, now 10 = 99% decrease)

**Mock:**
- Configuration: `priceGuard.maxDecreasePercent = 40`

**Assertions:**
- Batch step 3 detection: `vars.priceGuard.isSuspicious == true`
- Classification override: HOLD_FOR_REVIEW
- Logger alert with decrease percentage appears

**Verify:** Extreme price decreases trigger HOLD_FOR_REVIEW override

---

## TEST GROUP 5: catalog-persistence-flow.xml (3 tests — Missing Path Coverage)

### Test 5.1: CHANGED_CUSTOMER_FACING with Multiple Field Diffs
**Flow to test:** `persist-product-record-subflow`

**Setup:**
- Payload = `{sku: "MULTI-DIFF", productName: "NewName", price: "200", stockStatus: "OUT_OF_STOCK"}`
- `vars.currentSku` = "MULTI-DIFF"
- `vars.deltaClassification` = 
  ```json
  {
    classification: "CHANGED_CUSTOMER_FACING",
    customerFacingChanged: true,
    diffs: [
      {fieldName: "productName", oldValue: "OldName", newValue: "NewName", customerFacing: true},
      {fieldName: "price", oldValue: "100", newValue: "200", customerFacing: true},
      {fieldName: "stockStatus", oldValue: "IN_STOCK", newValue: "OUT_OF_STOCK", customerFacing: true}
    ]
  }
  ```

**Mock:**
- `db:update` (update product) → return {affectedRows: 1}
- `db:insert` (history row) → return {affectedRows: 1} (called 3 times for 3 diffs)

**Assertions:**
- `db:update` called once to update product
- `db:insert` called 3 times (foreach loop processes all 3 diffs)
- Each history row has correct fieldName, oldValue, newValue, customerFacing = true
- Logger shows update for SKU MULTI-DIFF

**Verify:** Multiple diffs are written as separate history rows in foreach loop

---

### Test 5.2: HOLD_FOR_REVIEW Classification
**Flow to test:** `persist-product-record-subflow`

**Setup:**
- Payload = `{sku: "HOLD-SKU", price: "250"}`
- `vars.storedProduct` = {price: 100} (for history old value)
- `vars.currentSku` = "HOLD-SKU"
- `vars.deltaClassification` = `{classification: "HOLD_FOR_REVIEW"}`

**Mock:**
- `db:update` (mark review_hold = TRUE) → return {affectedRows: 1}
- `db:insert` (history row for price guard) → return {affectedRows: 1}

**Assertions:**
- `db:update` called with `review_hold = TRUE`
- `db:insert` called once with change_type = "HOLD_FOR_REVIEW", field_name = "price", oldValue: "100", newValue: "250"
- Price is NOT updated (only review_hold flag set)

**Verify:** HOLD_FOR_REVIEW prevents price update but flags product for review

---

### Test 5.3: FULL Extract Delisting with Absent Products
**Flow to test:** `evaluate-full-extract-delisting-subflow`

**Setup:**
- `vars.runId` = "RUN-DELIST"
- `vars.extractType` = "FULL"

**Mock:**
- `db:select` (find absent products) → return [{sku: "OLD-1", category_code: "CAT-A"}, {sku: "OLD-2", category_code: "CAT-B"}]
- `db:update` (mark delisted) → return {affectedRows: 2}
- `db:insert` (delist history) → return {affectedRows: 1} (called in foreach for each delisted SKU)

**Assertions:**
- `db:select` called to find absent products
- Result: 2 products found
- `db:update` called to mark both as DELISTED
- `db:insert` called 2 times (foreach loop) to write history rows
- Each history row has change_type = "DELISTED", old_value: "ACTIVE", new_value: "DELISTED"

**Verify:** Absent products are marked DELISTED and history recorded per SKU

---

## TEST GROUP 6: cdn-invalidation-flow.xml (8 tests — Heavy Coverage)

### Test 6.1: CDN 202 Accepted Response
**Flow to test:** `dispatch-cdn-invalidation-batch-subflow`

**Setup:**
- `vars.currentBatchPaths` = ["/p/SKU-1", "/p/SKU-1/images", "/c/CAT-1"]
- `vars.currentBatchNumber` = 1
- `vars.runId` = "RUN-CDN-001"
- `vars.requestReference` = "RUN-CDN-001-B1"

**Mock:**
- `http:request` (CDN API POST) → return {invalidationId: "INV-12345", status: "IN_PROGRESS"}
- `db:insert` (record invalidation) → return {affectedRows: 1}

**Assertions:**
- `http:request` called to POST to CDN
- Response status = 202
- `db:insert` called with httpStatus: 202, confirmed: true, provider_status: "IN_PROGRESS"
- Logger: "CDN_BATCH_ACCEPTED"

**Verify:** 202 accepted batch is recorded with confirmed = true

---

### Test 6.2: CDN 207 Partial Rejection — Retry Rejected Paths
**Flow to test:** `dispatch-cdn-invalidation-batch-subflow`

**Setup:**
- `vars.currentBatchPaths` = ["/p/INVALID", "/p/SKU-1", "/c/CAT-1"]

**Mock:**
- `http:request` (first POST) → return 
  ```json
  {
    invalidationId: "INV-8841",
    accepted: ["/p/SKU-1", "/c/CAT-1"],
    rejected: [{path: "/p/INVALID", reason: "INVALID_PATH_PATTERN"}]
  }
  ```
- `db:insert` (initial 207 record) → return {affectedRows: 1}
- `http:request` (retry single path) → return {invalidationId: "INV-RETRY-1", status: "IN_PROGRESS"} (202 on retry)
- `db:insert` (retry result) → return {affectedRows: 1}

**Assertions:**
- First `http:request` returns 207
- `db:insert` called for initial 207 record with httpStatus: 207
- Foreach loop processes rejectedPaths array (1 item)
- Second `http:request` called to retry "/p/INVALID" individually
- `db:insert` called again for retry result with reference "RUN-CDN-001-B1-RETRY-1"
- Logger: "CDN_207_PARTIAL" and "RETRY_PATH_CONFIRMED"

**Verify:** 207 responses trigger individual path retries

---

### Test 6.3: CDN 429 Rate Limit — Honor Retry-After Header
**Flow to test:** `dispatch-cdn-invalidation-batch-subflow`

**Setup:**
- `vars.currentBatchPaths` = ["/p/SKU-1"]

**Mock:**
- `http:request` (first attempt) → throw HTTP:TOO_MANY_REQUESTS with header `Retry-After: 60`
- until-successful retry mechanism + Thread.sleep

**Assertions:**
- First `http:request` throws HTTP:TOO_MANY_REQUESTS
- on-error handler reads `Retry-After: 60` header
- Computes retryAfterMs = 60 * 1000
- Logger: "CDN_RATE_LIMITED Retry-After=60s"
- until-successful catches and retries (mock returns 202 on 2nd attempt)

**Verify:** 429 rate limit respects Retry-After header and sleeps

---

### Test 6.4: CDN Transient Error (HTTP:CONNECTIVITY) — until-successful Retries
**Flow to test:** `dispatch-cdn-invalidation-batch-subflow`

**Setup:**
- `vars.currentBatchPaths` = ["/p/SKU-2"]

**Mock:**
- `http:request` (attempt 1-2) → throw HTTP:CONNECTIVITY
- `http:request` (attempt 3) → return 202 (success)

**Assertions:**
- First 2 attempts throw HTTP:CONNECTIVITY
- Logger: "CDN_TRANSIENT_ERROR ... Retrying"
- until-successful retries 3 times (maxRetries=3)
- 3rd attempt succeeds with 202
- `db:insert` called with confirmed: true

**Verify:** Transient errors are retried up to maxRetries

---

### Test 6.5: CDN Permanent Failure (5xx after retries) — Record as PENDING
**Flow to test:** `dispatch-cdn-invalidation-batch-subflow`

**Setup:**
- `vars.currentBatchPaths` = ["/p/SKU-3"]

**Mock:**
- `http:request` (all 3 attempts) → return 500 Internal Server Error (or throw HTTP:SERVICE_UNAVAILABLE)

**Assertions:**
- All 3 retries fail
- until-successful exhausts retries
- on-error-continue (permanent failure handler) triggers
- `db:insert` called to record as PENDING_RETRY with confirmed: false
- Logger: "CDN_PERMANENT_FAILURE ... DB updates preserved"
- No exception propagated (on-error-continue)

**Verify:** Permanent failures record as PENDING and don't roll back DB

---

### Test 6.6: MULE:RETRY_EXHAUSTED from until-successful
**Flow to test:** `dispatch-cdn-invalidation-batch-subflow`

**Setup:**
- Similar to 6.5, but force until-successful to throw MULE:RETRY_EXHAUSTED

**Mock:**
- `http:request` (all 3 attempts) → throw HTTP:CONNECTIVITY

**Assertions:**
- until-successful exhausts maxRetries and throws MULE:RETRY_EXHAUSTED
- Global error handler on-error-continue (RETRY_EXHAUSTED type) catches it
- `db:insert` called to record as RETRY_EXHAUSTED
- Logger: "CDN_RETRY_EXHAUSTED ... All retries exhausted"

**Verify:** Retry exhausted batches are recorded

---

### Test 6.7: CDN Orchestrator — Query Changed Products and Batch Generation
**Flow to test:** `trigger-cdn-invalidation-orchestrator-subflow`

**Setup:**
- `vars.runId` = "RUN-CDN-ORCH"

**Mock:**
- `db:select` (find changed products) → return 
  ```json
  [
    {sku: "SKU-1", category_code: "CAT-APP"},
    {sku: "SKU-2", category_code: "CAT-FAS"},
    {sku: "SKU-3", category_code: "CAT-HOM"}
  ]
  ```
- Configuration: `invalidation.maxPathsPerRequest = 2` (forces 2 batches)
- `http:request` (CDN batch POST) → return 202 (called 2 times)
- `db:insert` (record each batch) → return {affectedRows: 1}

**Assertions:**
- `db:select` called to find customer-facing changed products
- Result: 3 SKUs → 9 paths (3 per SKU: /p/{sku}, /p/{sku}/images, /c/{cat})
- Paths deduplicated and batched by maxPathsPerRequest (2)
- Batch 1: 2 paths, Batch 2: 7 paths (maxBatch enforced)
- foreach loop processes 2 batches
- dispatch-cdn-invalidation-batch-subflow invoked for each batch
- Rate limit sleep between batches: 60000 / maxRequestsPerMinute (1000ms default)

**Verify:** Orchestrator correctly queries and batches paths

---

### Test 6.8: CDN Orchestrator — No Customer-Facing Changes (Skip Invalidation)
**Flow to test:** `trigger-cdn-invalidation-orchestrator-subflow`

**Setup:**
- `vars.runId` = "RUN-CDN-NONE"

**Mock:**
- `db:select` (find changed products) → return [] (no customer-facing changes)

**Assertions:**
- `db:select` called
- Result: empty array
- choice branch: "No customer-facing changes" logs
- dispatch-cdn-invalidation-batch-subflow NOT called
- `http:request` NOT called

**Verify:** No invalidations issued when no customer-facing changes

---

## Summary Table: Expected Test Count & Coverage

| Flow File | Existing Tests | New Tests | Total | Coverage Target |
|-----------|---|---|---|---|
| catalog-api.xml | 0 | 8 | 8 | 100% (all 8 flows) |
| global-error-handler.xml | 0 | 12 | 12 | 100% (all 9 handlers + types) |
| catalog-intake-flow.xml | 4 | 3 | 7 | 95%+ (missing paths covered) |
| catalog-processing-flow.xml | 6 | 2 | 8 | 95%+ (price guard scenarios) |
| catalog-persistence-flow.xml | 4 | 3 | 7 | 95%+ (multi-diff, HOLD, delist) |
| cdn-invalidation-flow.xml | 1 | 8 | 9 | 95%+ (207, 429, transient, permanent, retry-exhausted) |
| global-config.xml | 1 | 0 | 1 | 100% (schema init) |
| **TOTAL** | **18** | **36** | **54** | **90%+** |

---

## Implementation Notes

### Mock Scoping (MUnit 3.x)
- Global mocks (in `<munit:before-suite>`) apply to all tests by default
- Per-test mocks (in `<munit:behavior>`) override global mocks for that test only
- Per-test mocks are scoped to that single test execution

### Key Mocking Patterns

1. **Database Mocking:**
   - `munit-tools:mock-when processor="db:select"` → return result set or []
   - Use `targetValue` to simulate extracting first row (for single-row queries)
   - For errors: `<munit-tools:then-return type="error"><munit-tools:error type="DB:CONNECTIVITY" /></munit-tools:then-return>`

2. **HTTP Request Mocking (CDN):**
   - `munit-tools:mock-when processor="http:request"` with `withAttribute matchers`
   - Match by config-ref: `withAttribute("config-ref").ofValue("CDN_HTTP_Request_configuration")`
   - Return response payload or throw error

3. **File Operation Mocking:**
   - `munit-tools:mock-when processor="file:move"` → return payload (simulates successful move)
   - For errors: throw FILE:ACCESS_DENIED or FILE:FILE_ALREADY_EXISTS

4. **Error Handling Mocking:**
   - Mock a processor to throw a specific error type
   - Global error handler must be referenced by the flow (via `defaultErrorHandler-ref` in global-config)
   - Verify the error is caught and transformed into JSON response

5. **Thread.sleep Mocking:**
   - For rate limit delays, mock `java:java::lang::Thread::sleep` to return immediately (don't actually sleep)
   - Or verify logger entry instead of actual sleep

### Assertion Strategy

- **For flow invocation:** Use `flow-ref` to call the flow, then assert on payload/variables
- **For HTTP flows:** Use MUnit HTTP test driver or assert flow-ref invoked with correct params
- **For error handlers:** Mock underlying processor to throw error, catch in test flow, verify response JSON
- **For batch processing:** Assert batch payload structure (totalRecords, failedRecords, loadedRecords)
- **For DB operations:** Use `<munit-tools:verify-call>` to confirm mock was called with expected params

### Testing Until-Successful Retry Scopes

- Mock processor to fail N times, succeed on retry
- Or mock to always fail, verify all 3 retries occur
- until-successful throws MULE:RETRY_EXHAUSTED when maxRetries exceeded
- Catch in global error handler and verify response

### Testing Global Error Handler

Since error handlers are only invoked on errors, create dedicated test flows that:
1. Call a processor mocked to throw specific error
2. Global-error-handler catches it (via defaultErrorHandler-ref)
3. Assert error response JSON

Example:
```xml
<flow name="test-file-error-flow">
    <set-variable variableName="runId" value="#['TEST-RUN']" />
    <munit-tools:mock-when processor="file:move">
        <munit-tools:then-return type="error">
            <munit-tools:error type="FILE:ACCESS_DENIED" description="Permission denied" />
        </munit-tools:then-return>
    </munit-tools:mock-when>
    <file:move doc:name="Trigger FILE:ACCESS_DENIED" config-ref="File_Config" sourcePath="test" targetPath="test" />
</flow>
```

Then call this flow in test and verify error response.

---

## Execution Plan

1. **Phase 1:** Implement Tests 1-8 (catalog-api.xml) — HTTP endpoint coverage
2. **Phase 2:** Implement Tests 2.1-2.12 (global-error-handler.xml) — Error path coverage
3. **Phase 3:** Implement Tests 3.1-3.3 (catalog-intake-flow.xml) — Missing intake paths
4. **Phase 4:** Implement Tests 4.1-4.2 (catalog-processing-flow.xml) — Price guard coverage
5. **Phase 5:** Implement Tests 5.1-5.3 (catalog-persistence-flow.xml) — Multi-diff and delisting
6. **Phase 6:** Implement Tests 6.1-6.8 (cdn-invalidation-flow.xml) — CDN error scenarios

After each phase, run:
```
mvn clean munit:test
```

And verify coverage increased in console output and reports.

---

## Expected Coverage After Implementation

- **catalog-api.xml:** 100% (8/8 flows tested)
- **global-error-handler.xml:** 100% (all error types triggered)
- **catalog-intake-flow.xml:** 95%+ (all major branches)
- **catalog-processing-flow.xml:** 95%+ (all batch steps + price guard)
- **catalog-persistence-flow.xml:** 95%+ (all classifications + multi-diff)
- **cdn-invalidation-flow.xml:** 95%+ (202 / 207 / 429 / transient / permanent / retry-exhausted)
- **global-config.xml:** 100% (schema init)

**Overall: 90%+ coverage achieved.**

---

## Configuration Property References

Ensure the following are set in `config/config-dev.yaml` or `config/catalog-delta.yaml`:

```yaml
# Batch processing
processing.batchSize: 100
processing.maxRejectPercentAllowed: 5

# Price guard
priceGuard.maxIncreasePercent: 50
priceGuard.maxDecreasePercent: 40
priceGuard.action: HOLD_FOR_REVIEW

# CDN invalidation
invalidation.maxPathsPerRequest: 30
invalidation.maxRequestsPerMinute: 60
invalidation.backoffMillis: 2000

# Full extract policy
fullExtractPolicy.requireMinimumRecordCount: 1000

# File paths
file.inbound.path: data/input
file.inprocess.path: data/archive/in-process
file.archive.path: data/archive
file.error.path: data/error
file.inbound.pollFrequency: 5000

# HTTP
http.port: 8081

# CDN
cdn.host: localhost
cdn.port: 8082
cdn.path: /api/v2/invalidations
cdn.timeout: 30000
cdn.distributionId: DIST-RETAIL-PRD-01
```

---

## Final Notes

1. **All tests must be independent** — each test should set its own variables and mocks
2. **Mocks are test-scoped** — per-test mocks override global mocks for that test only
3. **No actual file/DB operations** — all processors are mocked
4. **Error handlers require test flows** — create dedicated flows to trigger error types
5. **Run full suite:** `mvn clean munit:test` produces coverage report in `target/site/munit/coverage/`
6. **Expected result:** 54 tests passing, 90%+ coverage across all 7 flows

