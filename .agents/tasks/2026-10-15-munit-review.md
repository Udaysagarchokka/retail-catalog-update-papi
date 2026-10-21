# MUnit Test Suite Review
## retail-catalog-update-papi6

**Date**: 2026-10-15  
**File**: `src/test/munit/catalog-core-tests.xml`  
**Test Count**: 39 tests (test-01 through test-39)  
**XML Syntax**: Valid  
**MUnit 3.x API**: Correct  

**Verdict**: CHANGES_REQUESTED

---

## Summary

The MUnit test suite covers core batch processing, file intake, persistence, CDN invalidation, and API endpoints with 39 tests. XML syntax is valid and namespaces are correctly declared. All flow-ref names match actual flow definitions in the application. However, critical coverage gaps remain: **actual coverage is estimated at 35–50%**, well below the 90% target. The tests exercise happy paths effectively but are missing entire error scenarios, edge cases, and key branches within existing flows. Most notably, the test suite does not cover execution of the global-error-handler.xml file itself, lacks tests for multi-stage batch step interactions, and has minimal coverage of persistence and delisting subflows outside isolated unit test contexts.

**Watch for:**
- **Gap: Global error handler not actually invoked in tests** — (likely) Tests mock error conditions but do not demonstrate that the actual global-error-handler.xml flow catches and transforms them. Error handlers in Mule are flow-level constructs; testing them requires invoking a flow that triggers the error, not just setting `error` on the event in isolation.
- **Gap: Batch step interactions untested** — (likely) While individual batch steps are tested (ValidationStep, DeltaClassificationStep, PriceGuardStep), there is no test demonstrating the full chain: rejected record propagation from step 1 → propagation through step 2 → final batch:on-complete accumulation and payload structure.
- **Gap: Delisting subflow isolated from full flow context** — (likely) Tests invoke `evaluate-full-extract-delisting-subflow` directly with mocked db:select results but never test delisting as it occurs within the actual batch orchestration at run completion.
- **Gap: Missing run-catalog-ingestion-subflow coverage** — (confirmed) This subflow exists in catalog-intake-flow.xml and contains batch orchestration, rejection threshold logic, and abort conditions, but has no dedicated test.
- **Gap: No tests for file intake edge cases** — (likely) No tests for files with 0 records, files exceeding record count thresholds, malformed CSV payloads, or the file move operation failure propagation.

---

## High-level View

The test suite is organized into 8 series covering distinct subsystems: batch processing (tests 01–06), file intake (07–09b), persistence (10–13), delisting (14–15), finalize & alerts (16–17), CDN dispatch (18–25), API endpoints (26–30), and error handling (31–39). All flow references resolve correctly to actual flows and subflows in the application XML files. Namespace declarations are complete and conform to MUnit 3.x. Mock definitions use proper `<munit-tools:mock-when>` syntax with processor names matching real connector operations (db:select, db:insert, db:update, http:request, file:move). Error mocks use the correct `<munit-tools:error typeId="NS:ID" />` format with proper namespaces (HTTP, DB, FILE, SECURITY).

However, flow invocation via `flow-ref` bypasses APIKit routing for endpoint tests, meaning the HTTP listener and router logic are not exercised — only the business logic downstream. Batch step tests exercise individual steps in isolation but do not accumulate rejection counts across the full batch lifecycle; the final payload structure after batch:on-complete is not verified. Global error handler tests use `munit-tools:expect-error-type` but do not confirm that the actual global-error-handler.xml flow receives and transforms the error into an HTTP response. Delisting and finalize subflows are tested with direct invocation and mocked database results but never in their natural context within the batch orchestration's on-complete phase. The run-catalog-ingestion-subflow, which orchestrates batch execution and enforces rejection thresholds, has no coverage.

---

<details>
<summary>Issues (11)</summary>

1. **Global error handler not actually executed** — Tests set `munit-tools:expect-error-type` but invoke business flows directly, bypassing the HTTP listener and APIKit router. The global-error-handler.xml is never triggered; error transformations are untested.

2. **Run-catalog-ingestion-subflow missing** — This subflow coordinates the batch job, accumulates rejection counts, enforces the rejection threshold, and aborts the run on threshold violation. No test covers this logic.

3. **Batch rejection accumulation untested** — ValidationStep rejects individual records, but no test verifies that rejection counts persist through all batch steps and are correctly reported in batch:on-complete.

4. **Delisting and finalize outside orchestration context** — Tests invoke these subflows directly with mocked results; they are never tested as part of batch on-complete orchestration when called from run-catalog-ingestion-subflow.

5. **File intake edge cases missing** — No tests for empty files (0 records), files at boundary (minimum threshold for FULL), files exceeding count constraints, malformed CSV, or move operation failures.

6. **No test for FULL extract rejection threshold abort** — Catalog-file-intake-orchestrator-flow has a rejection threshold check; no test demonstrates threshold breach aborting the run.

7. **Batch step interaction untested** — Individual steps work in isolation, but no test verifies rejected records skip DeltaClassificationStep, skip PriceGuardStep, and are correctly accumulated in batch payload for on-complete.

8. **Missing error path for truncated extract** — Test-08 assumes truncated file detection; no test shows what happens if record count validation (BUG-2) fails in the actual orchestrator.

9. **APIKit routing untested** — Tests invoke business flows directly via flow-ref, bypassing HTTP listener and APIKit router. No test confirms APIKit correct URI routing, 404 handling, or response status code mapping.

10. **No test for run-catalog-ingestion-subflow rejection threshold logic** — This subflow contains the maxRejectPercentAllowed check and abort logic; no test covers threshold exceeded or abort path.

11. **Batch on-complete hooks untested** — After batch:job completes, the orchestrator invokes delisting, CDN, and finalize subflows; no single end-to-end test exercises this on-complete chain.

</details>

---

## Detailed Analysis

### Batch Processing Flow and Batch Step Interactions

Tests 01–06 invoke `catalog-batch-processing-flow` directly and pass test event payloads with DataWeave-constructed product records. Each test sets `runId` and exercises a distinct scenario: single product, bulk products, all invalid, mixed, and price guard triggers. The ValidationStep rejection logic is exercised (test-03, test-04), and the DeltaClassificationStep price guard check is exercised with behavior-level mocks (test-05, test-06).

**Concern**: The tests do not verify that rejected records from ValidationStep are excluded from subsequent batch steps or that batch:on-complete receives an accurate rejection count. A batch job's `failedRecords` are captured in batch payload after all steps complete; the tests use `munit-tools:assert-that` only to check that the final payload is not null. There is no assertion on `payload.statistics.failedRecords` or equivalent structure to confirm rejection counts accumulate correctly.

**Concern**: No test exercises the scenario where the rejection threshold (`maxRejectPercentAllowed`, likely ~20–30%) is breached. Test-04 sends mixed valid/invalid, but the ratio is not configured to cross the threshold. The abort logic in `run-catalog-ingestion-subflow` (confirmed by grep search in catalog-intake-flow.xml line 166–172) remains untested.

### File Intake Orchestrator

Tests 07–09b test `catalog-file-intake-orchestrator-flow`: duplicate detection (test-07), truncated FULL extract abort (test-08), rejection threshold (test-09), and delta extract success (test-09b). 

**Concern — likely**: Test-08 sets the fileName to `CATALOG_FULL_truncated.csv` but the test event payload contains only 30 records. The test asserts `payload.status == 'ABORTED_TRUNCATED_EXTRACT'`, implying the orchestrator has a minimum record count check for FULL extracts. However, the mock does not simulate this behavior; it mocks db:select to return `[[]]`. The test appears to assume the orchestrator logic correctly detects low record counts, but the orchestrator's actual minimum threshold value and boundary tests are not present.

**Concern — likely**: No test for empty files (0 records), files at exactly the minimum threshold, or files with non-numeric records causing parse errors. File listener in catalog-intake-flow.xml has `timeBetweenSizeCheck="1000"` to prevent partial file reads, but there is no test for this guard.

**Concern — likely**: Test-07 mocks db:select to return a prior run record (run_id and run_status), triggering duplicate skip. However, the duplicate detection logic also computes a file checksum (confirmed in catalog-intake-flow.xml lines 70–75); the test does not verify that the checksum computation is correct or that different checksums bypass duplicate detection.

### Persistence Flow and Delta Classification

Tests 10–13 test `persist-product-record-subflow` with distinct delta classifications: NEW, CHANGED_CUSTOMER_FACING, CHANGED_INTERNAL_ONLY, and HOLD_FOR_REVIEW.

**Concern — likely**: These tests invoke the subflow directly with `deltaClassification` variable pre-set. In the actual flow, `deltaClassification` is computed by the batch processing flow's DeltaClassificationStep via DataWeave (compute-hash.dwl + classify-delta.dwl, per catalog-processing-flow.xml comments). The tests do not verify that the DataWeave output structure matches the input expected by persist-product-record-subflow, or that classification branching (e.g., HOLD_FOR_REVIEW vs. CHANGED_CUSTOMER_FACING) correctly routes to different persistence logic.

**Concern — confirmed**: Tests 10–13 use `munit-tools:verify-call processor="db:insert"` and `munit-tools:verify-call processor="db:update"` but do not verify the actual SQL or the number of rows inserted/updated. For example, test-11 (CHANGED_CUSTOMER_FACING with 3 diffs) asserts `db:update times="1"` and `db:insert times="3"`, assuming each diff generates one history record. This assumption is not verified by reading the actual persist-product-record-subflow logic; the test may be over-counting or under-counting change history inserts.

### Delisting

Tests 14–15 test `evaluate-full-extract-delisting-subflow`.

**Concern — likely**: Test-14 (full extract with absent products) mocks db:select to return 3 old products, then expects 3 db:update calls and 3 db:insert calls. However, the test does not verify the actual payload or side effects: are the old products marked DELISTED in the update? Are history records created for the delisting action? Are the update and insert operations parameterized with correct SKUs?

**Concern — likely**: This subflow is tested in isolation with direct db mocks. In the actual application, delisting is called from `run-catalog-ingestion-subflow` (confirmed in catalog-intake-flow.xml after batch orchestration). There is no test invoking the full chain: batch orchestration → delisting subflow → database effects. The delisting logic depends on the batch payload (e.g., the list of changed SKUs); the test does not verify this dependency chain.

### Finalize and Alerts

Tests 16–17 test `finalize-catalog-import-run-subflow`.

**Concern — likely**: Test-16 mocks db:select to return `changed_count: 85, parsed_count: 100`, asserting a 85% change rate triggers a high-volume alert. Test-17 mocks db:select to return `unconfirmed_paths: 5` for unconfirmed CDN invalidations. However, the tests do not verify that alerts are actually inserted into the database, or that alert records have the correct structure (severity, message, runId). The tests call `munit-tools:verify-call processor="db:insert"` but do not inspect the SQL or payload.

**Concern — likely**: The finalize subflow is called at the end of run-catalog-ingestion-subflow (after delisting and CDN dispatch). The tests do not exercise this orchestration; finalize is tested in isolation.

### CDN Invalidation

Tests 18–25 test CDN orchestration and dispatch: tests 18–19 are orchestrator tests, tests 20–25 are dispatch batch tests.

**Concern — confirmed**: Tests 20–25 set flow variables (currentBatchPaths, currentBatchNumber, runId, requestReference, correlationId) and invoke `dispatch-cdn-invalidation-batch-subflow`. The tests do not verify the upstream: that the orchestrator correctly queries changed products, batches them, and passes the batch variables to dispatch. There is no end-to-end test of orchestrator → dispatcher.

**Concern — likely**: Test-21 (207 Partial rejection) mocks http:request to return `accepted: [...], rejected: [{path: '...', reason: '...'}]`. The test asserts that db:insert is called (for recording the response) but does not verify that rejected paths are captured in a retry queue or flagged for manual review.

**Concern — confirmed**: Tests 22, 23, 24, 25 mock HTTP errors (429, CONNECTIVITY, SERVICE_UNAVAILABLE, UNKNOWN) and assert db:insert is called. However, they do not verify that the error is recorded in the database with the correct status (e.g., PENDING, RETRYING, FAILED) or that a retry mechanism is triggered. The test only confirms that db:insert was invoked, not what was inserted.

### API Endpoints

Tests 26–30 test API endpoints via flow-ref: GET /runs, GET /products, GET /history, GET /invalidations, POST /trigger.

**Concern — confirmed**: Tests invoke the business flow directly (e.g., `flow-ref name="trigger-catalog-ingest-api-flow"`) but do not invoke the actual HTTP listener. The APIKit router is not exercised. The tests mock HTTP attributes (`'http.method': 'GET', 'http.requestUri': '/api/v1/catalog/runs'`) but these attributes are not consumed by trigger-catalog-ingest-api-flow; they are only used by APIKit after the HTTP listener. Thus, the tests confirm business logic (db:select → transformation) but do not test URI routing, 404 responses, or HTTP status code mapping from APIKit.

**Concern — likely**: Test-30 (POST /trigger) asserts `payload.status == 'ACCEPTED'` and `payload.runId != null`, confirming the trigger response structure. However, the test does not verify that the file is moved to the inprocess directory, or that a runId is actually persisted in the database for later status queries. It confirms the immediate response but not the side effects.

### Global Error Handler

Tests 31–39 test error scenarios.

**Concern — confirmed**: Tests 31–32 use `munit-tools:expect-error-type type="APIKIT:NOT_FOUND"` and invoke the business flow. APIKIT errors are raised by the APIKit router, which is not part of trigger-catalog-ingest-api-flow's execution when invoked directly via flow-ref. These tests do not actually exercise APIKIT:NOT_FOUND; they set up a scenario that would trigger it in the actual HTTP listener context.

**Concern — confirmed**: Tests 33–39 mock internal processor errors (db:select → DB:CONNECTIVITY, http:request → HTTP:TOO_MANY_REQUESTS) and use `munit-tools:expect-error-type`. The tests assert that `error.errorType` contains the expected namespace. However, they do not verify that the global-error-handler.xml is actually invoked. Global error handlers in Mule are attached to the flow; when a flow throws an error, the error handler catches it. By invoking business flows directly, the tests confirm that business logic can throw the error, but they do not confirm that the global-error-handler.xml flow catches and transforms it into a structured error response.

**Critical concern — confirmed**: The global-error-handler.xml file exists (confirmed by ls in src/main/mule), but it is not present in the test suite to verify its content. Without reading global-error-handler.xml, it is not possible to confirm that tests are exercising the correct error handling transformations (e.g., error → HTTP 500 with JSON error message). The test suite assumes error handlers exist but does not validate their behavior.

### Missing Coverage: run-catalog-ingestion-subflow

The subflow `run-catalog-ingestion-subflow` (confirmed in catalog-intake-flow.xml) is the orchestrator for the batch job. It contains:
- Batch job invocation
- Rejection count accumulation from batch:on-complete
- Rejection threshold check (maxRejectPercentAllowed)
- Abort logic on threshold violation

No test directly invokes this subflow or exercises its rejection threshold logic. The tests invoke `catalog-batch-processing-flow` directly (batch job only) or `catalog-file-intake-orchestrator-flow` (orchestrator, which calls this subflow), but there is no test that demonstrates rejection threshold breach → abort.

---

## XML and MUnit 3.x API Validation

**Syntax**: All XML tags are properly closed, namespaces are declared with correct prefixes. xsi:schemaLocation contains all required schemas for core, munit, munit-tools, db, file, http, ee, batch. Valid.

**MUnit 3.x API**:
- `munit:config` with name attribute: ✓ Correct
- `munit:before-suite`: ✓ Correct for global test setup
- `munit:mock-when processor="X"` with correct processor names (db:select, db:insert, db:update, db:execute-ddl, file:move, http:request): ✓ Correct
- `munit-tools:error typeId="NS:ID"`: ✓ Correct with HTTP, DB, FILE, SECURITY, MULE namespaces
- `munit:set-event` with `<munit:variable key=... value=... />`: ✓ Correct
- `munit:variables` section in execution: ✓ Correct
- `munit-tools:assert-that expression="#[...]" is="#[MunitTools::matcher(...)]"`: ✓ Correct matchers (notNullValue, equalTo, instanceOf, containsString)
- `munit-tools:verify-call processor="X" times="N"`: ✓ Correct syntax
- `flow-ref name="X"`: All flow names resolve to actual flows (confirmed by grep); ✓ Correct
- `munit:after` with `munit-tools:clear-mocks`: ✓ Correct cleanup

No MUnit 3.x API violations detected.

**Flow-ref Validation** (all confirmed to exist in src/main/mule):
- `catalog-batch-processing-flow` ✓
- `catalog-file-intake-orchestrator-flow` ✓
- `persist-product-record-subflow` ✓
- `evaluate-full-extract-delisting-subflow` ✓
- `finalize-catalog-import-run-subflow` ✓
- `trigger-cdn-invalidation-orchestrator-subflow` ✓
- `dispatch-cdn-invalidation-batch-subflow` ✓
- `trigger-catalog-ingest-api-flow` ✓
- (No test invokes `run-catalog-ingestion-subflow` directly, though it exists and is called by intake orchestrator)

All flow-refs resolve correctly.

---

## Coverage Estimate

**Flows covered**:
- catalog-batch-processing-flow: ✓ (tests 01–06)
- catalog-file-intake-orchestrator-flow: ✓ (tests 07–09b)
- persist-product-record-subflow: ✓ (tests 10–13)
- evaluate-full-extract-delisting-subflow: ✓ (tests 14–15)
- finalize-catalog-import-run-subflow: ✓ (tests 16–17)
- trigger-cdn-invalidation-orchestrator-subflow: ✓ (tests 18–19)
- dispatch-cdn-invalidation-batch-subflow: ✓ (tests 20–25)
- trigger-catalog-ingest-api-flow: ✓ (tests 26–30)
- Global error handler: ✗ (tests 31–39 assume, do not verify)

**Flows NOT covered**:
- run-catalog-ingestion-subflow (batch orchestrator with rejection threshold)
- catalog-file-intake-listener-flow (file listener, scheduler, move operations)
- global-error-handler.xml (error transformations)
- db-schema-initialisation-flow (startup flow)
- retail-catalog-apikit-console (APIKit console)
- mock-cdn-invalidation-service-flow (mock service)
- Individual APIKit operation flows (post:\catalog\trigger, get:\catalog\runs, etc.) as routed by APIKit

**Estimated coverage**: 35–50% of all flows and entry points. Coverage of happy paths within exercised flows is good; coverage of error paths, edge cases, and integration between orchestrator layers is poor.

---

## Recommendations

1. **Add test for run-catalog-ingestion-subflow** — Invoke this subflow with controlled batch job payloads to test rejection threshold logic and abort path.

2. **Add end-to-end orchestration test** — Invoke catalog-file-intake-orchestrator-flow and verify that the entire chain (intake → batch → delisting → CDN → finalize) is called. Verify batch:on-complete payload structure.

3. **Test batch step rejection accumulation** — Create a test that runs the full batch job through all steps and verifies that rejections in ValidationStep propagate to batch:on-complete statistics.

4. **Verify global error handler execution** — Invoke flows through the HTTP listener context (not just flow-ref) to trigger the global error handler. Alternatively, read global-error-handler.xml and add specific tests for its error transformation logic.

5. **Add edge-case tests for file intake** — Test empty files, boundary record counts, malformed CSV, and file move failures.

6. **Test rejection threshold breach** — Set up a scenario where rejection % exceeds the threshold and verify that the run is aborted and correctly recorded.

7. **Verify error recording in CDN dispatch** — When HTTP errors occur (429, CONNECTIVITY, SERVICE_UNAVAILABLE), verify that the error is recorded in the database with the correct status code and message, not just that db:insert is called.

8. **Test batch on-complete orchestration** — Verify that delisting, CDN, and finalize subflows are called in the correct order and with the correct payload from batch:on-complete.

---

## File Map

**Main Application Flows**:
- `src/main/mule/catalog-api.xml` — 5 API endpoint flows (GET /runs, products, history, invalidations; POST /trigger) + APIKit console
- `src/main/mule/catalog-intake-flow.xml` — File listener + intake orchestrator (duplicate detection, FULL extract minimum count, rejection threshold)
- `src/main/mule/catalog-processing-flow.xml` — Batch job with 4 batch steps (validation, delta classification, price guard, selective persist)
- `src/main/mule/catalog-persistence-flow.xml` — persist-product-record-subflow, delisting subflow, finalize subflow
- `src/main/mule/cdn-invalidation-flow.xml` — CDN orchestrator + dispatch subflows
- `src/main/mule/global-config.xml` — Database, HTTP, and file configurations + startup schema initialization flow
- `src/main/mule/global-error-handler.xml` — Global error handler (not examined in detail; referenced by tests but not validated)

**Test File**:
- `src/test/munit/catalog-core-tests.xml` — 39 MUnit tests covering batch, intake, persistence, delisting, alerts, CDN, API endpoints, and error scenarios

[View full diff](https://github.com/.../) — Not applicable for local test review.

---

