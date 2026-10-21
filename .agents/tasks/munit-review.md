# MUnit Test Suite Review: catalog-core-tests.xml

## Summary

The MUnit test file contains 55 tests (test-01 through test-55) covering batch processing, file intake, persistence, delisting, CDN invalidation, finalization, API endpoints, and global error handling. XML syntax is valid with proper namespace declarations. All tested flow-refs match defined flows in the application. However, coverage is incomplete: critical data path scenarios lack tests, and several high-risk error cases are untested. The test design emphasizes behavioral coverage but shows gaps in edge cases, retry logic validation, and transaction rollback scenarios.

**Watch for:** Missing integration tests for batch-on-complete handlers, no tests for schema initialization failure scenarios, incomplete validation of CDN batch retry logic, and HTTP-to-error-handler propagation tests use simplified error mocking that doesn't validate actual handler routing. The suite achieves broad scenario coverage but lacks depth in failure recovery and complex multi-step orchestrations.

**Verdict**: CHANGES_REQUESTED

<details>
<summary>Issues (8)</summary>

1. **Missing batch-on-complete handler tests** — Tests reference `catalog-batch-processing-flow` but don't test the batch completion trigger (on-complete section) that invokes downstream delisting, CDN invalidation, and finalization subflows. Test-40 attempts integration but only validates the intake orchestrator. The batch processor's on-complete callback is untested.

2. **No schema initialization failure scenario coverage** — Test-44 mocks db:execute-ddl to succeed, but no test covers DB:CONNECTIVITY, DB:QUERY_EXECUTION, or other transient failures during schema setup. Critical startup path has zero failure-case coverage.

3. **CDN retry logic incomplete** — Tests mock single HTTP failures but don't validate until-successful retry counts, backoff timing, or max-attempts termination. Test-25 (retry exhausted) and test-22/23 (429/CONNECTIVITY) don't verify that retries actually occur; they only verify that errors are mocked.

4. **Global error handler HTTP propagation untested** — Tests-31 through test-39 use http:request with error-response-handler, but this doesn't actually test whether errors from nested processors propagate through APIKit and the error handler to HTTP response. The tests mock direct flow-refs instead of invoking through the HTTP listener and router.

5. **Transaction rollback on persistence failure untested** — Persistence tests mock successful db:insert/update, but no test triggers a failure mid-persistence (e.g., db:insert succeeds but history insert fails) to verify rollback or compensating transaction behavior. until-successful wrapping may hide failures.

6. **Delisting edge case: exact boundary at fetch limit untested** — Delisting tests return hardcoded results, but no test validates behavior when the database cursor exactly hits batch size limits or pagination boundaries during the absent-product scan.

7. **CDN batch dispatch with empty paths list untested** — Tests set currentBatchPaths but no test covers the case where the list is empty or null before dispatch. Pre-condition validation is not tested.

8. **Correlation ID propagation in batch on-complete untested** — Test-45 checks correlation ID in error response for HTTP, but no test validates that correlationId flows through batch on-complete into delisting, CDN, and finalization subflows.

</details>

## High-level view

The test file follows MUnit 3.x conventions correctly: mock-when processors use proper syntax, munit:variable children are properly nested (not attributes), and error mocks use typeId. All namespace prefixes are declared. The 55 tests are organized into logical groups: batch processing (6 tests), file intake (5 tests), persistence (4 tests), delisting (2 tests), finalization (2 tests), CDN dispatch (8 tests), HTTP API endpoints (5 tests), global error handler (9 tests), and integration/edge cases (14 tests). Coverage spans the five main API endpoints (GET /runs, /products, /history, /invalidations; POST /trigger) and exercises database errors, HTTP errors, file errors, and expression errors through the error handler. The test design favors breadth over depth—many scenarios are touched but few are explored thoroughly.

The largest gap is in orchestration semantics. Batch, delisting, CDN, and finalization flows are tested in isolation but never together; the on-complete handler that chains them is mocked at the subflow level rather than tested end-to-end. Similarly, retry logic is exercised by mocking errors but not by validating retry counts or timing constraints. Tests assume successful DB writes and don't explore partial-failure scenarios where some records persist and others fail. Correlation ID propagation is tested once (test-45) but only for the direct HTTP error path, not through batch orchestration. Transaction safety during persistence of multiple records with mixed classifications (test-54) is only superficially tested.

The error handler tests focus on status code mapping and don't verify message content, payload structure, or whether error details are properly logged or propagated to downstream consumers. Tests use HTTP:error-response-handler in some cases but these do not actually invoke the global error handler defined in the application—they short-circuit before routing.

## Behavioral sections

<details>
<summary>Details</summary>

### XML Syntax and MUnit 3.x API Correctness

All namespace prefixes are properly declared at the root mule element. Closing tags match opening tags. The munit-tools:before-suite section correctly mocks global defaults for db:select, db:insert, db:update, db:execute-ddl, file:move, and http:request. Individual test behavior sections override these mocks correctly using munit-tools:mock-when and munit-tools:then-return.

**confirmed** — All munit:variable declarations use child elements inside munit:set-event (not attributes on the set-event element itself), which is correct for MUnit 3.x. Example: `<munit:variable key="runId" value="#['RUN-B001']" />` is properly nested within `<munit:set-event>`.

**confirmed** — Error mocks use typeId attribute inside munit-tools:then-return: `<munit-tools:error typeId="DB:CONNECTIVITY" />`. This is correct MUnit 3.x syntax.

**confirmed** — Assertions use MunitTools matchers: `MunitTools::notNullValue()`, `MunitTools::equalTo()`, `MunitTools::instanceOf()`. Syntax is valid.

**confirmed** — All flow-ref names reference flows or subflows that exist in the application: catalog-batch-processing-flow, catalog-file-intake-orchestrator-flow, persist-product-record-subflow, evaluate-full-extract-delisting-subflow, finalize-catalog-import-run-subflow, run-catalog-ingestion-subflow, trigger-cdn-invalidation-orchestrator-subflow, dispatch-cdn-invalidation-batch-subflow, and db-schema-initialisation-flow are all defined in src/main/mule/*.xml files.

### Batch Processing Flow Coverage

Tests 1–6 exercise batch-processing-flow in isolation with varying input sizes and validation outcomes. Test-01 (single valid product) and test-02 (50 valid products) represent happy paths. Test-03 (all invalid) and test-04 (mixed valid/invalid) test partial acceptance. Tests 05–06 test the price guard logic by mocking db:select to return prior price, then sending a new price that triggers the suspicious-change threshold (HOLD_FOR_REVIEW classification).

**likely** — The mock in tests 05–06 returns a single prior product via db:select, but the actual flow may iterate through a batch. If the flow processes multiple products and queries one prior price per product, the mock setup (returning a single record) may not accurately simulate batching behavior. No test sends multiple products through the batch to verify that the price guard applies to each record independently.

**likely** — Test-43 mocks db:select with DB:CONNECTIVITY error, but the test doesn't verify retry behavior—it only verifies that the error is thrown. If the flow wraps the batch processing in until-successful, retries should occur, but the test doesn't mock a recovery (e.g., first call fails, second call succeeds). The validation only checks that `processor="db:select"` was called, not how many times or with what outcome.

### File Intake Orchestrator Coverage

Tests 7–9 and 9b exercise the file intake orchestrator. Test-07 tests duplicate detection by mocking db:select to return a prior run with matching filename. Test-08 tests truncated FULL extract detection by limiting the incoming payload to 30 records (simulating an incomplete file). Test-09 tests rejection threshold exceeded by sending 100 invalid records. Test-09b tests delta extract success (non-FULL extract type).

**likely** — Test-08 sends 30 records and expects the flow to detect truncation. The actual logic may have a threshold (e.g., abort if < 50 records in a FULL extract). The test doesn't verify the threshold; it only asserts the status is ABORTED_TRUNCATED_EXTRACT. If the threshold is different in production, this test may pass but not exercise the actual guard.

**likely** — Test-09 and test-47 both send 100 records with high rejection, but neither validates that the actual rejection percentage is calculated correctly from the batch payload. The mock sets `rejected_count: 60` and `parsed_count: 100` in the DB select response, but the flow's logic for calculating rejection rate from the batch is not tested end-to-end; the test assumes the DB query already reflects the calculation.

### Persistence Flow Coverage

Tests 10–13 exercise persist-product-record-subflow with different delta classifications: NEW, CHANGED_CUSTOMER_FACING, CHANGED_INTERNAL_ONLY, and HOLD_FOR_REVIEW. Mocks verify that db:insert and db:update are called the correct number of times.

**confirmed** — Test-11 sends multiple diffs with customerFacing=true and verifies that db:update (for product) is called once and db:insert (for history) is called 3 times (once per diff). This correctly validates the foreach iteration over diffs.

**likely** — Test-54 (mixed classifications) sends a single record with CHANGED_CUSTOMER_FACING and 2 diffs, mocking db:update=1 and db:insert=2. This doesn't test actual batch processing of multiple records with different classifications mixed together (e.g., some NEW, some CHANGED_CUSTOMER_FACING). A foreach that processes multiple incoming records with different classifications is not exercised.

**possible** — Tests 10–13 and 54 don't verify that the until-successful wrapper (if present) around persistence actually handles transient DB errors. Test-43 mocks DB:CONNECTIVITY during batch processing, but no test mocks it during persist-product-record-subflow invocation. If until-successful is applied to persistence, its retry logic is untested.

### Delisting Flow Coverage

Tests 14–15 and test-46 exercise evaluate-full-extract-delisting-subflow. Test-14 mocks db:select to return 3 absent products and verifies db:update is called once (to mark them DELISTED) and db:insert is called 3 times (history record per product). Test-15 mocks extractType=DELTA and expects no delisting. Test-46 mocks extractType=FULL but with no absent products and expects no delisting.

**likely** — Tests assume the subflow queries for absent products, marks them DELISTED, and inserts history records. The actual implementation may batch the update (single INSERT INTO product_change_history SELECT...) rather than looping and calling db:insert three times. The mock setup expects three separate db:insert calls; if the actual flow uses a single batch insert, the test may fail even though the logic is correct.

**likely** — Test-46 validates the boundary case (FULL extract, no absent products), but the test doesn't verify that the SELECT query itself was executed and returned an empty result. The mock returns `#[[]]` (empty list) regardless of the query; there's no assertion that the query was called to discover the empty result.

### CDN Invalidation Coverage

Tests 18–19 cover the orchestrator (batch query and splitting). Tests 20–25 cover dispatch with different response codes (202, 207, 429, CONNECTIVITY, SERVICE_UNAVAILABLE, retry exhausted). Test-36-39 cover error scenarios from HTTP/CDN.

**confirmed** — Test-20 mocks 202 Accepted and verifies http:request and db:insert are called. Test-21 mocks 207 Partial Rejection with accepted and rejected arrays and verifies db:insert. Test-22/23 mock 429 and CONNECTIVITY errors. Test-24 mocks SERVICE_UNAVAILABLE.

**likely** — The tests mock error responses but don't validate retry behavior. If the dispatch subflow wraps the http:request in until-successful with maxRetries=3, the test should verify that http:request is called 3 times before the error is recorded. Test-25 (retry exhausted) mocks `MULE:UNKNOWN` but doesn't verify maxRetries or backoff timing.

**likely** — Test-22 and test-23 mock HTTP errors, but the tests don't verify that a retry actually occurs. They only verify that db:insert is called once. If until-successful is wrapping the http:request, should db:insert be called after each failed retry, or only once after all retries fail? The test doesn't clarify this behavior.

**possible** — Tests 18–19 mock db:select to return changed products, but the batching logic (split into batches of N paths per request) is not exercised. If the orchestrator splits a large list into multiple batches and dispatches each, only test-52 (with 5 products) attempts this, but doesn't verify batch boundaries are correct.

### API Endpoint Coverage

Tests 26–30 invoke the API endpoints via http:request using HTTP methods (GET, POST). Mocks ensure db:select and db:insert return appropriate payloads.

**likely** — These tests use http:request but don't actually invoke through the HTTP listener and APIKit router. They call flow-refs directly after setting payload and headers. A true integration test would start an HTTP listener, make HTTP requests to it, and verify the full request/response cycle through APIKit. These tests skip that layer and test only the flow logic, not the APIKit routing.

**confirmed** — Test-26 (GET /runs) mocks db:select with 2 runs and asserts sizeOf(payload)==2. Test-27 (GET /products) asserts sizeOf(payload)==2 and payload[0].sku=='SKU-HTTP-1'. Test-30 (POST /trigger) mocks db:select and db:insert and asserts payload.status=='ACCEPTED' and payload.runId is not null.

### Global Error Handler Coverage

Tests 31–39 and test-45 attempt to test error handler responses. Tests 31–32 test APIKit-level errors (404, 400). Tests 33–35 test DB and FILE errors. Tests 36–39 test HTTP errors and a fallback SECURITY:UNAUTHORIZED.

**likely** — These tests use http:request with error-response-handler, which captures errors before they propagate to the global error handler. This does not actually test the global error handler defined in global-error-handler.xml. To test the handler, requests should flow through APIKit and the HTTP listener, then encounter errors in actual flow processors, and only then be handled by the global handler. Instead, these tests mock errors at the processor level within the test flow and capture them locally.

**likely** — Tests 33–34 mock db:select to throw DB:CONNECTIVITY and DB:QUERY_EXECUTION respectively, then use http:request with error-response-handler to catch the error and assert statusCode==500. This simulates an error during the endpoint flow, but doesn't verify that the global error handler's exception mapping (which maps DB:CONNECTIVITY → 500 with a specific message) is applied. The test just checks the status code, not the error message or payload structure.

**confirmed** — Test-31 expects APIKIT:NOT_FOUND (404) for a nonexistent path (/api/v1/catalog/nonexistent). Test-32 expects 400 for invalid query parameters. These are legitimate endpoint-level error tests.

### Integration and Edge Case Coverage

Tests 40–55 cover broader scenarios. Test-40 integrates batch + delisting + CDN + finalize. Test-41–42 test run-catalog-ingestion-subflow directly. Test-44 tests schema initialization. Test-45 tests correlation ID propagation. Test-46 tests delisting boundary case. Test-47 tests rejection threshold at boundary. Test-48 tests malformed payload. Test-49 tests EXPRESSION error. Test-50 tests file listener path. Test-51 tests normal price change. Test-52 tests multiple CDN batches. Test-53 tests finalize with multiple alerts. Test-54 tests mixed classifications. Test-55 tests CDN 207 with multiple rejected paths.

**likely** — Test-40 calls catalog-file-intake-orchestrator-flow, which should trigger the batch processor, which should trigger the on-complete handler (delisting, CDN, finalize). However, the test only mocks db:select, db:insert, db:update, http:request, and file:move globally. The on-complete handler itself is not tested; it's exercised as a side effect. If the on-complete handler has its own logic (e.g., conditional branching based on payload), this test doesn't verify it.

**likely** — Test-41 calls run-catalog-ingestion-subflow directly and mocks db:insert with generatedKeys=[123]. This tests that a run record is created and the runId is returned. But the test doesn't verify that the runId matches the generatedKey, only that runId is notNullValue(). 

**likely** — Test-44 mocks db:execute-ddl to succeed and expects it to be called 4 times (once per table). But if db-schema-initialisation-flow includes error handling (e.g., "create table if not exists" with exception suppression), the test doesn't verify that the handler allows duplicate creation attempts or that existing tables are not recreated.

**possible** — Test-48 sends malformed JSON (`{ &quot;invalid&quot;: json }`) and expects 400. But this might be caught by JSON parsing at the HTTP listener level before reaching the endpoint flow, or it might reach the endpoint and trigger an EXPRESSION error. The test doesn't verify which error type is caught or where the error originates.

### Missing Critical Scenarios

**not tested** — The batch processor's on-complete handler is never tested in isolation or as the final step of a full orchestration. If the handler has branching logic (e.g., "only run delisting if extractType==FULL"), this is not verified.

**not tested** — Schema initialization failure scenarios. If db:execute-ddl fails with DB:CONNECTIVITY or a syntax error, the flow should handle it gracefully. No test covers this.

**not tested** — Retry logic validation. Tests mock errors but don't verify that retries occur, or that max-attempts is honored. The until-successful wrapping is invisible to the tests.

**not tested** — Transaction rollback during persistence. If persist-product-record-subflow is processing 3 records and the 2nd one fails, is the 1st record already committed to the database? No test explores this.

**not tested** — Correlation ID propagation through batch on-complete. Test-45 checks it in the HTTP error response, but not through the full orchestration chain.

**not tested** — CDN batch boundary cases: empty path lists, exact batch-size boundaries, pagination limits.

**not tested** — Delisting with cursor pagination: if the query returns N pages of absent products, is the delisting applied to all pages, or only the first batch?

**not tested** — HTTP listener rate limiting and request queuing: if 100 requests arrive simultaneously, are they queued correctly?

</details>

## File map

<details>
<summary>Changed files (1)</summary>

- **src/test/munit/catalog-core-tests.xml** — 55 MUnit tests covering batch processing, file intake, persistence, delisting, CDN invalidation, finalization, API endpoints, and error handling. Tests use munit-tools:mock-when to mock database and HTTP operations, munit-tools:verify-call to count invocations, and munit-tools:assert-that to validate responses. Global mocks are set in before-suite; individual tests override with behavior blocks. All tests include after blocks to clear mocks.

Full diff: `git diff HEAD -- src/test/munit/catalog-core-tests.xml`

</details>

---

**Review conducted by:** Semantic MUnit Analyzer
**Date:** 2026-10-15
**Test count:** 55 tests (test-01 through test-55)
**Result:** XML valid, all flow-refs correct, coverage breadth adequate but depth gaps identified.
