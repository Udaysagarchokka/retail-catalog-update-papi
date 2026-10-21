# MUnit Coverage Implementation Plan

## Executive Summary

Current coverage: **19%** with 25 existing tests
Target coverage: **90%+**

The coverage gap is due to:
1. **Duplicate file detection** — DB returns non-empty result, flow short-circuits
2. **Truncated FULL extract guard** — recordCount < minRecordCount, file moved to error
3. **Rejection threshold exceeded** — rejection % > maxRejectPercentAllowed, run aborted
4. **Foreach history row writes** — CHANGED_CUSTOMER_FACING and CHANGED_INTERNAL_ONLY paths never hit the foreach
5. **Delisting foreach** — omittedProducts iteration not exercised
6. **Finalize alerts** — high change volume and unconfirmed invalidations branches
7. **CDN dispatch with HTTP mocking** — dispatch-cdn-invalidation-batch-subflow needs http:request mocking
8. **Mock CDN service branches** — 202, 429, 207 responses not tested
9. **API endpoints** — GET /history, GET /invalidations never called
10. **Error handler flows** — APIKit errors, file errors, DB errors not triggered
11. **File operations mocking** — file:move and file:copy not mocked

---

## New Tests Required (36 total)

### SECTION 1: Orchestrator Flow Branches (5 tests)

#### Test 26: Duplicate File Detection
**Description:** When file_name + file_checksum match an existing run, flow returns SKIPPED_DUPLICATE
**Flow:** catalog-file-intake-orchestrator-flow
**Setup:**
- Mock `db:select` (check duplicate) to return: `[{run_id: 'RUN-PREV', run_status: 'COMPLETED'}]`
- Payload: 1 record (minimum for non-truncation)
- Variables: `fileName = 'CATALOG_FULL_test.csv'`
**Mocks:**
- db:select (duplicate check) → non-empty array
**Expected:** Payload contains `status: 'SKIPPED_DUPLICATE'`, no db:insert for new run called
**Verification:** `munit:verify-call processor="db:select"` (duplicate check only), NOT called for selection of run counts

#### Test 27: Truncated FULL Extract (recordCount < minRecordCount)
**Description:** FULL extract with fewer records than threshold aborts and moves file to error
**Flow:** catalog-file-intake-orchestrator-flow
**Setup:**
- Payload: 500 records (assume minRecordCount config = 1000)
- Variables: `fileName = 'CATALOG_FULL_small.csv'`, `extractType = 'FULL'`
- Mock db:select (duplicate check) → empty array (new file)
**Mocks:**
- db:select (duplicate check) → `[]`
- file:move → return mock success
**Expected:** Payload contains `status: 'ABORTED_TRUNCATED_EXTRACT'`, file moved to error directory
**Verification:** file:move called once to error path, verify payload status field

#### Test 28: FULL Extract Minimum Record Count Check Passed
**Description:** FULL extract with recordCount >= minRecordCount proceeds to ingestion
**Flow:** catalog-file-intake-orchestrator-flow
**Setup:**
- Payload: 1100 records (> 1000 minimum)
- Variables: `fileName = 'CATALOG_FULL_valid.csv'`, `extractType = 'FULL'`
- Mock db:select (duplicate check) → empty array
**Mocks:**
- db:select (duplicate check) → `[]`
- db:insert (initial run record) → `{generatedKeys: [1], affectedRows: 1}`
**Expected:** Payload not null, no truncation error, flow proceeds to batch
**Verification:** db:insert called for initial run record

#### Test 29: Rejection Threshold Exceeded (rejection % > maxRejectPercentAllowed)
**Description:** After batch, if rejected % > threshold, run marked ABORTED_HIGH_REJECTION
**Flow:** run-catalog-ingestion-subflow
**Setup:**
- Payload: 10 records (1 valid, 9 invalid)
- Variables: `runId = 'RUN-REJECT-HIGH'`, `fileName = 'test.csv'`, `filePayload = [list of 10]`
- Mock db:select (post-batch counts) → `[{parsed_count: 10, rejected_count: 9, run_status: 'IN_PROGRESS'}]`
**Mocks:**
- db:insert (initial run) → success
- db:select (post-batch) → {parsed_count: 10, rejected_count: 9}
- db:update (mark ABORTED) → success
- file:move (file to error) → success
**Expected:** Payload contains `status: 'ABORTED_HIGH_REJECTION'`, `rejected: 9`, `parsed: 10`
**Verification:** db:update called with 'ABORTED_HIGH_REJECTION', file:move called

#### Test 30: Rejection Check Passed (rejection % within threshold)
**Description:** After batch, if rejected % <= threshold, flow completes normally
**Flow:** run-catalog-ingestion-subflow
**Setup:**
- Payload: 100 records (95 valid, 5 invalid)
- Variables: `runId = 'RUN-REJECT-OK'`, `fileName = 'test.csv'`
- Mock db:select (post-batch) → `[{parsed_count: 100, rejected_count: 5, run_status: 'IN_PROGRESS'}]` (5% ≤ threshold)
**Mocks:**
- db:insert (initial run) → success
- db:select (post-batch) → {parsed_count: 100, rejected_count: 5}
**Expected:** Flow completes without ABORTED_HIGH_REJECTION error, proceeds normally
**Verification:** db:update NOT called with ABORTED status, flow reaches end without error

---

### SECTION 2: Persistence Flow — History Row Foreach (3 tests)

#### Test 31: CHANGED_CUSTOMER_FACING with Multiple Diffs (Foreach Path)
**Description:** When classification is CHANGED_CUSTOMER_FACING with diffs, each diff written as separate history row via foreach
**Flow:** persist-product-record-subflow
**Setup:**
- Payload: `{sku: 'SKU-MULTI-DIFF', productName: 'NewName', price: '299.99'}`
- Variables:
  - `runId = 'RUN-HIST-001'`
  - `currentSku = 'SKU-MULTI-DIFF'`
  - `deltaClassification = { classification: 'CHANGED_CUSTOMER_FACING', diffs: [ {fieldName: 'productName', oldValue: 'OldName', newValue: 'NewName', customerFacing: true}, {fieldName: 'price', oldValue: '199.99', newValue: '299.99', customerFacing: true} ] }`
  - `computedHash = 'newhash123'`
**Mocks:**
- db:update (update product) → `{affectedRows: 1}`
- db:insert (insert history) → `{generatedKeys: [1], affectedRows: 1}` (called twice via foreach)
**Expected:** db:insert called exactly 2 times (one per diff in foreach), each with correct field_name
**Verification:** `munit:verify-call processor="db:insert" times="2"`, verify second insert has field_name='price'

#### Test 32: CHANGED_INTERNAL_ONLY with Diffs (Foreach Path)
**Description:** CHANGED_INTERNAL_ONLY also triggers foreach for each diff
**Flow:** persist-product-record-subflow
**Setup:**
- Payload: `{sku: 'SKU-INT-DIFF', brand: 'NewBrand'}`
- Variables:
  - `runId = 'RUN-HIST-002'`
  - `currentSku = 'SKU-INT-DIFF'`
  - `deltaClassification = { classification: 'CHANGED_INTERNAL_ONLY', diffs: [ {fieldName: 'brand', oldValue: 'OldBrand', newValue: 'NewBrand', customerFacing: false}, {fieldName: 'taxClass', oldValue: 'GST12', newValue: 'GST18', customerFacing: false} ] }`
**Mocks:**
- db:update → `{affectedRows: 1}`
- db:insert → `{generatedKeys: [1], affectedRows: 1}` (× 2)
**Expected:** db:insert called 2 times for internal-only diffs
**Verification:** `munit:verify-call processor="db:insert" times="2"`

#### Test 33: NEW Product with Single History Row (No Foreach)
**Description:** NEW classification inserts 1 product row + 1 history row (no foreach)
**Flow:** persist-product-record-subflow
**Setup:**
- Payload: `{sku: 'SKU-NEW-FRESH', productName: 'NewProd', price: '100.00', currency: 'INR', ...}`
- Variables:
  - `runId = 'RUN-NEW-001'`
  - `currentSku = 'SKU-NEW-FRESH'`
  - `deltaClassification = {classification: 'NEW'}`
  - `computedHash = 'newhash'`
**Mocks:**
- db:insert → `{generatedKeys: [1], affectedRows: 1}`
**Expected:** db:insert called exactly 2 times (product + single history row, NOT a foreach loop)
**Verification:** `munit:verify-call processor="db:insert" times="2"`, inspect call stack to confirm NO foreach iteration

---

### SECTION 3: Delisting Flow — Foreach Path (2 tests)

#### Test 34: Full Extract Delisting with Multiple Absent Products (Foreach Path)
**Description:** When delisting finds absent products, foreach iterates and writes history for each
**Flow:** evaluate-full-extract-delisting-subflow
**Setup:**
- Variables:
  - `runId = 'RUN-DELIST-MULTI'`
  - `extractType = 'FULL'`
- Mock db:select (find absent) → `[{sku: 'SKU-ABSENT-1', category_code: 'CAT-X'}, {sku: 'SKU-ABSENT-2', category_code: 'CAT-Y'}, {sku: 'SKU-ABSENT-3', category_code: 'CAT-Z'}]`
**Mocks:**
- db:select (find absent) → 3 products
- db:update (mark delisted) → `{affectedRows: 3}`
- db:insert (history per SKU) → `{generatedKeys: [1], affectedRows: 1}` (called 3 times via foreach)
**Expected:** db:insert called exactly 3 times (one per delisted product), each with different SKU in history row
**Verification:** `munit:verify-call processor="db:insert" times="3"`, inspect 2nd and 3rd calls for different SKU values

#### Test 35: Full Extract Delisting with Empty Absent Products (No Foreach)
**Description:** When no absent products found, foreach never iterates
**Flow:** evaluate-full-extract-delisting-subflow
**Setup:**
- Variables: `runId = 'RUN-DELIST-EMPTY'`, `extractType = 'FULL'`
- Mock db:select (find absent) → `[]`
**Mocks:**
- db:select → `[]`
- db:insert → NOT called
**Expected:** No delisting occurs, foreach never executes
**Verification:** `munit:verify-call processor="db:insert" times="0"`

---

### SECTION 4: Finalize Flow — Alert Branches (2 tests)

#### Test 36: High Change Volume Alert (>80% of parsed records changed)
**Description:** Finalize alerts when (changed_count / parsed_count) > 0.8
**Flow:** finalize-catalog-import-run-subflow
**Setup:**
- Variables: `runId = 'RUN-FINAL-HIGH-VOL'`
- Mock db:select (aggregate history) → `[{new_count: 10, changed_count: 85, held_count: 0, delisted_count: 0}]`
- Mock db:select (aggregate invalidation) → `[{invalidation_requests: 5, invalidation_paths: 150, unconfirmed_paths: 0}]`
- Mock db:select (parsed/rejected) → `[{parsed_count: 100, rejected_count: 5}]`
**Mocks:**
- All db:select calls return values as above
- db:update (finalize) → `{affectedRows: 1}`
**Expected:** Alert logger called with ALERT_HIGH_CHANGE_VOLUME, message includes "changed" count and percent
**Verification:** Check logs for "ALERT_HIGH_CHANGE_VOLUME", verify 85/100 = 85% > 80%

#### Test 37: Unconfirmed Invalidations Alert (unconfirmed_paths > 0)
**Description:** Finalize alerts when invalidation records have unconfirmed_paths > 0
**Flow:** finalize-catalog-import-run-subflow
**Setup:**
- Variables: `runId = 'RUN-FINAL-UNCONF'`
- Mock db:select (aggregate history) → `[{new_count: 5, changed_count: 10, held_count: 0, delisted_count: 0}]`
- Mock db:select (aggregate invalidation) → `[{invalidation_requests: 3, invalidation_paths: 25, unconfirmed_paths: 5}]` (5 > 0)
- Mock db:select (parsed/rejected) → `[{parsed_count: 50, rejected_count: 0}]`
**Mocks:**
- All db:select → values as above
- db:update (finalize) → `{affectedRows: 1}`
**Expected:** Alert logger called with ALERT_UNCONFIRMED_INVALIDATIONS, includes path count
**Verification:** Check logs for "ALERT_UNCONFIRMED_INVALIDATIONS", unconfirmed_paths = 5

---

### SECTION 5: CDN Invalidation — HTTP Mocking (4 tests)

#### Test 38: CDN Batch Dispatch 202 Accepted Response
**Description:** dispatch-cdn-invalidation-batch-subflow sends request, receives 202 ACCEPTED
**Flow:** dispatch-cdn-invalidation-batch-subflow
**Setup:**
- Variables:
  - `runId = 'RUN-CDN-202'`
  - `currentBatchNumber = 1`
  - `currentBatchPaths = ['/p/SKU-1', '/p/SKU-1/images', '/c/CAT-A']`
  - `correlationId = 'CORR-CDN-001'`
  - `requestReference = 'RUN-CDN-202-B1'`
- Payload: (will be transformed to CDN request JSON)
**Mocks:**
- http:request → return 202 with `{invalidationId: 'INV-123', status: 'IN_PROGRESS', pathCount: 3}`
- db:insert (CDN invalidation record) → `{affectedRows: 1}`
**Expected:** db:insert called with http_status=202, provider_status='IN_PROGRESS', confirmed=true
**Verification:** `munit:verify-call processor="http:request"`, `munit:verify-call processor="db:insert" times="1"`, check payload for confirmed=true

#### Test 39: CDN Batch Dispatch 429 Rate Limit with Retry-After
**Description:** http:request returns 429 with Retry-After header, flow reads header and backs off
**Flow:** dispatch-cdn-invalidation-batch-subflow
**Setup:**
- Variables: `runId = 'RUN-CDN-429'`, `currentBatchPaths = ['/p/SKU-2']`, `requestReference = 'RUN-CDN-429-B1'`
**Mocks:**
- http:request (1st call) → throw HTTP:TOO_MANY_REQUESTS with header Retry-After=2
- http:request (2nd call, after sleep) → return 202 success
- db:insert → `{affectedRows: 1}`
**Expected:** Flow sleeps for ~2 seconds (Retry-After value), then retries, eventually succeeds with 202
**Verification:** `munit:verify-call processor="http:request" times="2"`, first DB insert shows final 202 status

#### Test 40: CDN Batch Dispatch 207 Partial Rejection (Retry Rejected Paths)
**Description:** http:request returns 207 with rejected paths list, flow retries each rejected path individually
**Flow:** dispatch-cdn-invalidation-batch-subflow
**Setup:**
- Variables:
  - `runId = 'RUN-CDN-207'`
  - `currentBatchPaths = ['/p/SKU-3', '/p/SKU-4', '/INVALID_PATH']`
  - `requestReference = 'RUN-CDN-207-B1'`
**Mocks:**
- http:request (batch call) → return 207 with `{accepted: ['/p/SKU-3', '/p/SKU-4'], rejected: [{path: '/INVALID_PATH', reason: 'INVALID_PATH_PATTERN'}]}`
- http:request (retry /INVALID_PATH) → return 400 (cannot accept)
- db:insert → `{affectedRows: 1}` (called multiple times)
**Expected:**
  - Initial db:insert with status=207
  - 3 individual db:insert calls (one per rejected path retry): 2 successful, 1 failed → PERMANENTLY_UNCONFIRMED
**Verification:** `munit:verify-call processor="db:insert" times="4"` (1 batch + 3 individual), final insert with provider_status='PERMANENTLY_UNCONFIRMED'

#### Test 41: CDN Batch Dispatch Permanent Failure (HTTP Error, Recorded as Pending)
**Description:** http:request fails permanently (5xx after retries), DB not rolled back, recorded as PENDING_RETRY
**Flow:** dispatch-cdn-invalidation-batch-subflow
**Setup:**
- Variables: `runId = 'RUN-CDN-FAIL'`, `currentBatchPaths = ['/p/SKU-5']`, `requestReference = 'RUN-CDN-FAIL-B1'`
**Mocks:**
- http:request → throw HTTP:SERVICE_UNAVAILABLE (503) 3 times (all retries exhausted)
- db:insert (failure record) → `{affectedRows: 1}`
**Expected:** Flow catches permanent error, records batch as PENDING_RETRY in DB without rolling back
**Verification:** `munit:verify-call processor="db:insert" times="1"`, inserted record has provider_status='PENDING_RETRY', confirmed=false

---

### SECTION 6: Mock CDN Service — Response Branches (3 tests)

#### Test 42: Mock CDN Service 202 Accepted Response
**Description:** POST /mock-cdn/api/v2/invalidations returns 202 with invalidationId
**Flow:** mock-cdn-invalidation-service-flow
**Setup:**
- Payload: `{distributionId: 'DIST-1', paths: ['/p/SKU-A', '/p/SKU-B']}`
- HTTP headers: default (no simulation headers)
**Expected:** Response status=202, body contains invalidationId, status='IN_PROGRESS'
**Verification:** Assert payload.status='IN_PROGRESS', assert payload.invalidationId matches pattern 'INV-*'

#### Test 43: Mock CDN Service 429 Rate Limit Response
**Description:** POST /mock-cdn/api/v2/invalidations with simulate-rate-limit header returns 429
**Flow:** mock-cdn-invalidation-service-flow
**Setup:**
- Payload: `{distributionId: 'DIST-1', paths: ['/p/SKU-C']}`
- HTTP headers: `simulate-rate-limit: true`
**Expected:** Response status=429, body contains error='RATE_LIMIT_EXCEEDED', retryAfterSeconds=30
**Verification:** Assert payload.error='RATE_LIMIT_EXCEEDED', assert payload.retryAfterSeconds exists

#### Test 44: Mock CDN Service 207 Partial Rejection Response
**Description:** POST /mock-cdn/api/v2/invalidations with simulate-multi-status header returns 207
**Flow:** mock-cdn-invalidation-service-flow
**Setup:**
- Payload: `{distributionId: 'DIST-1', paths: ['/p/SKU-D', '/INVALID_PATH']}`
- HTTP headers: `simulate-multi-status: true`
**Expected:** Response status=207, body contains accepted array and rejected array with reasons
**Verification:** Assert payload.accepted contains '/p/SKU-D', assert payload.rejected contains '/INVALID_PATH' with reason

---

### SECTION 7: API Endpoints — Never Called (2 tests)

#### Test 45: GET /catalog/history Endpoint
**Description:** GET /catalog/history retrieves field-level change history from DB
**Flow:** get:\catalog\history:retail-catalog-apikit-config
**Setup:**
- Mock db:select → `[{change_seq: 1, run_id: 'RUN-001', sku: 'SKU-001', change_type: 'NEW', field_name: 'ALL', customer_facing: true}, {change_seq: 2, run_id: 'RUN-001', sku: 'SKU-002', change_type: 'CHANGED_CUSTOMER_FACING', field_name: 'price', customer_facing: true}]`
**Mocks:**
- db:select (history) → 2 records as above
**Expected:** Response is array of 2 history records, status=200
**Verification:** Assert sizeOf(payload)=2, assert payload[0].change_type='NEW'

#### Test 46: GET /catalog/invalidations Endpoint
**Description:** GET /catalog/invalidations retrieves CDN invalidation audit records
**Flow:** get:\catalog\invalidations:retail-catalog-apikit-config
**Setup:**
- Mock db:select → `[{invalidation_seq: 1, run_id: 'RUN-001', request_ref: 'RUN-001-B1', path_count: 3, http_status: 202, confirmed: true}, {invalidation_seq: 2, run_id: 'RUN-001', request_ref: 'RUN-001-B2', path_count: 2, http_status: 207, confirmed: false}]`
**Mocks:**
- db:select (invalidations) → 2 records
**Expected:** Response is array of 2 invalidation records, status=200
**Verification:** Assert sizeOf(payload)=2, assert payload[0].http_status=202

---

### SECTION 8: Global Error Handler — Error Paths (6 tests)

#### Test 47: APIKit 404 Not Found Error
**Description:** Trigger APIKIT:NOT_FOUND error via error handler
**Flow:** global-error-handler (triggered by calling invalid endpoint)
**Setup:**
- Call non-existent flow to trigger APIKit 404
**Mocks:**
- munit-tools:mock-when to trigger APIKIT:NOT_FOUND
**Expected:** Response status=404, errorCode='RESOURCE_NOT_FOUND'
**Verification:** Assert payload.status=404, assert payload.errorCode='RESOURCE_NOT_FOUND'

#### Test 48: File System Error — ACCESS_DENIED
**Description:** File operation throws FILE:ACCESS_DENIED, error handler logs and marks run FAILED
**Flow:** Any flow that calls file:move and receives ACCESS_DENIED
**Setup:**
- Variables: `runId = 'RUN-FILE-ERR'`, `fileName = 'test.csv'`, `extractType = 'FULL'`
- Mock file:move → throw FILE:ACCESS_DENIED
- Mock db:update → `{affectedRows: 1}`
**Mocks:**
- file:move → throwException with FILE:ACCESS_DENIED
- db:update (mark failed) → `{affectedRows: 1}`
**Expected:** Error handler catches, marks run FAILED, returns error response
**Verification:** db:update called with run_status='FAILED', payload contains errorCode='FILE_SYSTEM_ERROR'

#### Test 49: Database Connectivity Error
**Description:** DB connection fails, error handler propagates with structured response
**Flow:** Any flow calling db:select
**Setup:**
- Mock db:select → throw DB:CONNECTIVITY
**Mocks:**
- db:select → throwException with DB:CONNECTIVITY
**Expected:** Error propagates with errorCode='DB_CONNECTIVITY_ERROR'
**Verification:** Assert payload.errorCode='DB_CONNECTIVITY_ERROR'

#### Test 50: Database Query Execution Error
**Description:** DB query fails (bad SQL, constraint), run marked FAILED
**Flow:** Any flow with db:insert/update
**Setup:**
- Variables: `runId = 'RUN-DB-QUERY-ERR'`
- Mock db:insert → throw DB:BAD_SQL_SYNTAX
- Mock db:update (mark failed) → `{affectedRows: 1}`
**Mocks:**
- db:insert → throwException with DB:BAD_SQL_SYNTAX
- db:update (on error) → `{affectedRows: 1}`
**Expected:** Error handler catches, marks run FAILED, returns error response
**Verification:** db:update called, payload.errorCode='DB_QUERY_ERROR'

#### Test 51: CDN HTTP Error — Preserved DB, Recorded Pending
**Description:** HTTP call to CDN fails (CONNECTIVITY), DB not rolled back, invalidation recorded PENDING_RETRY
**Flow:** Error handler for CDN HTTP failures
**Setup:**
- Variables: `runId = 'RUN-CDN-HTTP-ERR'`, `currentBatchPaths = ['/p/SKU']`, `requestReference = 'REF-1'`
- Mock http:request → throw HTTP:CONNECTIVITY
- Mock db:insert (pending record) → `{affectedRows: 1}`
**Mocks:**
- http:request → throwException with HTTP:CONNECTIVITY
- db:insert (pending) → `{affectedRows: 1}`
**Expected:** Error handler continues (not propagate), records as PENDING_RETRY
**Verification:** db:insert called with provider_status='PENDING_RETRY', confirmed=false, payload.errorCode='CDN_INVALIDATION_PENDING'

#### Test 52: Generic Any Error Fallback
**Description:** Unexpected error caught by generic ANY handler, run marked FAILED
**Flow:** Error handler ANY fallback
**Setup:**
- Variables: `runId = 'RUN-GENERIC-ERR'`, `fileName = 'test.csv'`
- Trigger unexpected error (e.g., NullPointerException)
- Mock db:update (mark failed) → `{affectedRows: 1}`
**Mocks:**
- munit-tools:mock-when for any expression to throw generic error
- db:update (on error) → `{affectedRows: 1}`
**Expected:** Error propagates, run marked FAILED, response includes all context (runId, fileName, sku)
**Verification:** db:update called with run_status='FAILED', payload.errorCode='INTERNAL_SERVER_ERROR'

---

### SECTION 9: File Operations Mocking (2 tests)

#### Test 53: File Move Operation Mock — Success
**Description:** file:move operation mocked to return success
**Flow:** catalog-batch-processing-flow (on-complete, archive file)
**Setup:**
- Variables: `runId = 'RUN-FILE-MOVE'`, `fileName = 'CATALOG_FULL_20260911.csv'`
- Mock file:move → return success
**Mocks:**
- file:move → `{}`
**Expected:** Flow completes, file considered archived
**Verification:** `munit:verify-call processor="file:move" times="1"`

#### Test 54: File Move Operation Mock — Failure Ignored
**Description:** file:move fails but is caught by on-error-continue (does not abort flow)
**Flow:** catalog-batch-processing-flow (on-complete, file movement error handling)
**Setup:**
- Variables: `runId = 'RUN-FILE-MOVE-ERR'`, `fileName = 'test.csv'`
- Mock file:move → throw FILE:FILE_NOT_FOUND
**Mocks:**
- file:move → throwException with FILE:FILE_NOT_FOUND
**Expected:** Error caught, flow continues, does NOT abort overall run
**Verification:** Flow completes without propagating error, log message shows "Could not archive"

---

## Summary Table

| Test # | Category | Name | Gap Addressed | Mock Count |
|--------|----------|------|---------------|-----------|
| 26 | Orchestrator | Duplicate file detection | DB returns existing run | 1 (db:select) |
| 27 | Orchestrator | Truncated FULL extract | recordCount < minimum | 2 (db:select, file:move) |
| 28 | Orchestrator | FULL extract passes minimum | recordCount ≥ minimum | 2 (db:select, db:insert) |
| 29 | Orchestrator | Rejection threshold exceeded | rejection % > max | 4 (db:insert, db:select, db:update, file:move) |
| 30 | Orchestrator | Rejection check passed | rejection % ≤ max | 2 (db:insert, db:select) |
| 31 | Persistence | CHANGED_CUSTOMER_FACING foreach | 2+ diffs, foreach writes history | 2 (db:update, db:insert ×2) |
| 32 | Persistence | CHANGED_INTERNAL_ONLY foreach | 2+ diffs, foreach writes history | 2 (db:update, db:insert ×2) |
| 33 | Persistence | NEW product single history | No foreach, 1 history row | 1 (db:insert ×2) |
| 34 | Delisting | Multiple absent products foreach | 3+ products, foreach writes history | 3 (db:select, db:update, db:insert ×3) |
| 35 | Delisting | Empty absent products no foreach | 0 products, foreach skipped | 1 (db:select) |
| 36 | Finalize | High change volume alert | changed_count/parsed > 80% | 4 (db:select ×3, db:update) |
| 37 | Finalize | Unconfirmed invalidations alert | unconfirmed_paths > 0 | 4 (db:select ×3, db:update) |
| 38 | CDN | Batch 202 accepted | HTTP 202 response, confirmed | 2 (http:request, db:insert) |
| 39 | CDN | Batch 429 rate limit | HTTP 429, Retry-After header, backoff + retry | 3 (http:request ×2, db:insert) |
| 40 | CDN | Batch 207 partial rejection | HTTP 207, retry rejected paths individually | 4 (http:request ×2, db:insert ×4) |
| 41 | CDN | Batch permanent failure | HTTP 5xx, permanent fail, pending retry | 2 (http:request, db:insert) |
| 42 | Mock CDN | 202 response | Mock service returns 202 | 0 (no mocks needed) |
| 43 | Mock CDN | 429 response | Mock service returns 429 | 0 |
| 44 | Mock CDN | 207 response | Mock service returns 207 | 0 |
| 45 | API | GET /history | Endpoint never called | 1 (db:select) |
| 46 | API | GET /invalidations | Endpoint never called | 1 (db:select) |
| 47 | Error Handler | APIKit 404 | APIKIT:NOT_FOUND error | 0 (mock error trigger) |
| 48 | Error Handler | File system error | FILE:ACCESS_DENIED | 2 (file:move, db:update) |
| 49 | Error Handler | DB connectivity error | DB:CONNECTIVITY | 1 (db:select) |
| 50 | Error Handler | DB query error | DB:BAD_SQL_SYNTAX | 2 (db:insert, db:update) |
| 51 | Error Handler | CDN HTTP error + preserve DB | HTTP:CONNECTIVITY, PENDING_RETRY | 2 (http:request, db:insert) |
| 52 | Error Handler | Generic ANY fallback | Unexpected error | 2 (error trigger, db:update) |
| 53 | File Ops | file:move success | File archive succeeds | 1 (file:move) |
| 54 | File Ops | file:move failure ignored | File archive fails but doesn't abort | 1 (file:move) |

**Total new tests: 29** (Tests 26–54)
**Existing tests: 25** (Tests 1–25)
**Total after implementation: 54 tests**

---

## Implementation Notes

1. **Test Execution Order:** Implement in section order (Sections 1–9) to ensure:
   - Core flow branches tested first (Sections 1–3)
   - Then alerts and special behaviors (Section 4)
   - Then HTTP interactions (Sections 5–7)
   - Then error paths (Section 8)
   - Then file operations (Section 9)

2. **Mock Consistency:**
   - All `db:select` mocks for "check duplicate" must return empty array or a single prior run
   - All `db:insert`/`db:update` mocks must return affectedRows > 0 or generatedKeys
   - HTTP mocks must use `munit-tools:mock-when processor="http:request"` with exact status codes

3. **Foreach Verification:**
   - Tests 31–32 (persistence history): Count db:insert calls to verify foreach executed correct number of times
   - Tests 34 (delisting): Same pattern—count db:insert calls for each omitted product
   - Do NOT use `munit:verify-call times="N"` for processors inside loops—instead, count total calls and divide

4. **Error Handler Tests (47–52):**
   - Trigger errors via `munit-tools:mock-when ... throwException`
   - Wrap error-triggering flow call in try-catch at test level OR use `munit:verify-call` to confirm error handler ran
   - Confirm both logger output AND DB updates (run marked FAILED, or invalidation recorded PENDING)

5. **File Operations Tests (53–54):**
   - File connector mocks must be in before-test or behavior section of test
   - When file:move fails, ensure on-error-continue handler is verified (flow does NOT abort)

6. **Coverage Target:**
   - Existing 25 tests: ~19% → should be ~50% with current coverage
   - New 29 tests: should add ~40%+ coverage
   - Total expected: **90%+** coverage

---

## Next Step

Implement all tests in `src/test/munit/catalog-core-tests.xml`, appending after existing Test 25.

Use the **exact test names** and **setup/mocks/verification** as specified above.

Run verification with: `mvn clean test -DskipTests=false` or via Anypoint Studio Run → MUnit Test Suite.

Expected outcome: **90%+ coverage** with all critical paths and branches exercised.
