# MUnit Test Coverage Review

Test file reviewed: `src/test/munit/catalog-core-tests.xml`

**Verdict**: NEEDS_CHANGES

**Watch for:** Many tests use weak assertions (`true == true`) that don't verify actual business logic. The file has 36 tests across 6 groups, but roughly 60% use placeholder assertions that only confirm flows don't throw exceptions rather than validating behavioral outcomes. Coverage tracking depends on meaningful assertions, not test count.

## High-level view

The test file defines 36 MUnit tests organized into 6 behavioral groups. The XML structure is valid, namespace declarations are correct, and MUnit 3.3.1 syntax is properly used throughout (error mocks use `typeId`, verify-call uses `atLeast`/`times`, before-suite has `name` attribute). Global mocks are comprehensive, covering all external dependencies: db:select, db:insert, db:update, db:execute-ddl, file:move, and http:request with statusCode attributes.

The critical weakness is assertion quality. While Group 1 (delta classification) uses verify-call to confirm database operations, and Groups 2-3 include some meaningful assertions checking status codes and payload sizes, Groups 4-6 rely heavily on `#[true] == true` assertions. These tests confirm that flows complete without throwing exceptions, but they don't validate that error handlers produce correct error responses, that batch processing updates the right records, or that file operations move files to expected locations.

API endpoint tests (Group 3) properly use APIKit-generated flow names with `flow-ref`, not HTTP listener calls. Error handling tests (Group 4) correctly mock error types and wrap calls in try-catch blocks, but most only assert the error was caught, not the response shape or status. Group 5 (batch on-complete) and Group 6 (file operations) both test critical lifecycle behavior but provide no concrete validation of outcomes.

<details>
<summary>Issues (18)</summary>

1. **Weak assertions in test-008, test-009, test-010** — Tests assert `#[true] == true` instead of validating batch processing outcomes. Add assertions checking parsed_count, rejected_count, or change classification in the batch result.

2. **Weak assertion in test-012** — Test mocks high rejection rate but only asserts flow completes. Add assertion checking payload.status equals 'ABORTED_HIGH_REJECTION_RATE' or similar.

3. **Weak assertion in test-013** — CDN rate limit test doesn't verify retry behavior or final statusCode. Assert that http:request was called more than once or that payload contains invalidationId.

4. **Weak assertion in test-015** — CDN permanent failure test doesn't verify error handling outcome. Assert payload.cdnStatus or vars.cdnErrorHandled.

5. **Weak assertion in test-017** — Excessive change volume alert test doesn't verify alert was raised. Assert that db:insert was called for alert record or payload.alertsRaised > 0.

6. **Weak assertion in test-025** — HTTP connectivity error test doesn't validate error response. Assert vars.caughtError or payload.errorCode.

7. **Weak assertion in test-026** — Too many requests test doesn't verify retry-after handling. Assert http:request called multiple times or vars.retryCount.

8. **Weak assertion in test-027** — Service unavailable test doesn't verify error propagation. Assert vars.caughtError contains 'SERVICE_UNAVAILABLE' or payload.errorCode.

9. **Missing assertion in test-028** — Any fallback error test only checks error is not null. Add assertion checking error type equals 'UNKNOWN_ERROR' or payload.errorCode.

10. **Weak assertion in test-031** — CDN orchestrator no-changes test verifies http:request NOT called but doesn't validate early exit. Assert payload.cdnInvalidationsSkipped or vars.skipReason.

11. **Weak assertion in test-032** — Batch oncomplete full extract test doesn't verify delisting subflow was invoked. Add verify-call for db:update with doc:name matching delisting operation or assert vars.delistedCount > 0.

12. **Weak assertion in test-034** — File intake test doesn't verify file was moved to inprocess directory. Assert vars.fileMovedTo or verify-call for file:move with specific targetPath attribute.

13. **Weak assertion in test-035** — Archive test doesn't verify file moved to archive directory. Add verify-call for file:move matching archive path or assert vars.archivedFileName.

14. **Weak assertion in test-036** — Schema initialization test only asserts no exception. Verify db:execute-ddl was called with atLeast=4 (for 4+ tables) or check vars.tablesCreated.

15. **Group coverage imbalance** — Group 4 has 9 error tests but most use weak assertions. Error tests are critical for ensuring graceful degradation; strengthen assertions to verify error response payloads match expected structure.

16. **API endpoint test coverage incomplete** — Test-018 through test-022 verify response size/status but don't validate response schema. Add assertions checking payload contains expected fields (runId, status, sku, etc.).

17. **Batch processing coverage gap** — No test validates batch job splitting behavior when processing >100 records. Test-032 provides 1100 records but doesn't assert batch job ran in multiple chunks.

18. **No validation of change history detail** — Test-003 triggers CHANGED_CUSTOMER_FACING and verifies db:insert for history, but doesn't assert the inserted history record contains correct field_name, old_value, new_value. Strengthen with verify-call using with-attributes matching specific field changes.

</details>

<details>
<summary>Details</summary>

## Coverage completeness: 36 tests across 6 groups

The test file contains 36 tests organized into 6 groups:
- **Group 1**: Delta Classification Tests (5 tests) — test-001 through test-005
- **Group 2**: Negative Scenarios (12 tests) — test-006 through test-017
- **Group 3**: API Endpoint Tests (5 tests) — test-018 through test-022
- **Group 4**: Error Handler Tests (9 tests) — test-023 through test-031
- **Group 5**: Batch On-Complete Tests (2 tests) — test-032 through test-033
- **Group 6**: File Operations Tests (3 tests) — test-034 through test-036

This meets the requirement of "at least 36 tests covering all 6 groups." Each test has a unique name attribute and targets specific behavioral concerns.

## XML validity and namespace declarations

**Confirmed valid**. The XML structure is well-formed:
- Root `<mule>` element with complete namespace declarations for munit, munit-tools, db, ee, file, http, batch, and core
- Schema locations properly defined for all namespaces
- All elements properly closed
- `<munit:config name="catalog-core-tests" />` present at file start
- No DataWeave syntax errors detected in payload expressions

## MUnit 3.3.1 syntax correctness

**Confirmed correct**. All MUnit-specific syntax follows 3.3.1 conventions:

**Error mocks** use `<munit-tools:error typeId="NS:TYPE" />` (not the deprecated `<munit-tools:error-type>`). Examples:
- Line 606: `<munit-tools:error typeId="HTTP:CONNECTIVITY">`
- Line 629: `<munit-tools:error typeId="DB:CONNECTIVITY">`
- Line 800: `<munit-tools:error typeId="FILE:ACCESS_DENIED">`
- Line 942: `<munit-tools:error typeId="CUSTOM:UNKNOWN_ERROR">`
- Line 983: `<munit-tools:error typeId="DB:QUERY_EXECUTION">`

**before-suite** has `name` attribute (line 38): `<munit:before-suite name="before-suite-global-mocks">`

**All test elements** have `name` attributes: `<munit:test name="test-001-classification-new">` through `test-036-schema-initialisation`

**verify-call** uses `atLeast` or `times`, never the deprecated `count`:
- `<munit-tools:verify-call processor="db:insert" atLeast="1">` (appears 4 times)
- `<munit-tools:verify-call processor="db:update" times="0">` (test-002)
- `<munit-tools:verify-call processor="http:request" times="0">` (test-031)

## Global mock completeness

**Confirmed complete**. The before-suite block (lines 38-69) mocks all six required external dependencies:

1. **db:select** → returns empty array `#[[]]`
2. **db:insert** → returns `{ generatedKeys: [1], affectedRows: 1 }`
3. **db:update** → returns `{ affectedRows: 1 }`
4. **db:execute-ddl** → returns `{}`
5. **file:move** → returns payload unchanged
6. **http:request** → returns both payload (invalidationId, status, pathCount, acceptedAt) and attributes (statusCode: 202, headers)

The http:request mock correctly includes `<munit-tools:attributes>` with statusCode, meeting the requirement for "attributes for statusCode."

## Assertion quality: mixed strength

**Partially met**. The file contains meaningful assertions in some tests but relies heavily on weak assertions in others.

**Strong assertions** (18 tests use equalTo, hasSize, containsString, or verify-call):
- test-001: `verify-call processor="db:insert" atLeast="1"`
- test-002: `verify-call processor="db:update" times="0"`
- test-003: `verify-call` for both db:update and db:insert
- test-006: `assert-that payload.status equalTo('SKIPPED_DUPLICATE')`
- test-007: `assert-that payload.status equalTo('ABORTED_TRUNCATED_EXTRACT')` + `assert-that payload.recordCount equalTo(50)`
- test-016: `assert-that vars.caughtError containsString('CONNECTIVITY')`
- test-018: `assert-that payload.status equalTo('ACCEPTED')`
- test-019: `assert-that sizeOf(payload) equalTo(2)`
- test-020: `assert-that sizeOf(payload) equalTo(5)`
- test-021: `assert-that sizeOf(payload) equalTo(3)`
- test-022: `assert-that sizeOf(payload) equalTo(2)`
- test-023: `assert-that payload.errorCode equalTo('FILE_SYSTEM_ERROR')`
- test-024: `assert-that vars.caughtError containsString('CONNECTIVITY')`
- test-029: `assert-that vars.caughtError containsString('QUERY_EXECUTION')`
- test-030: `verify-call processor="db:update" atLeast="1"`
- test-031: `verify-call processor="http:request" times="0"`
- test-033: `verify-call processor="http:request" atLeast="1"`
- test-014: `verify-call processor="db:insert" atLeast="1"`

**Weak assertions** (18 tests use `#[true] == true` or `notNullValue()` only):
- test-008, test-009, test-010: batch processing tests with no validation of outcomes
- test-012: rejection threshold test doesn't verify abort behavior
- test-013: CDN rate limit test doesn't verify retry
- test-015: CDN permanent failure test doesn't verify error handling
- test-017: excessive change volume test doesn't verify alert raised
- test-025, test-026, test-027: CDN error tests with no error response validation
- test-028: fallback error test only checks error not null
- test-032, test-034, test-035, test-036: file and batch tests with no outcome validation

**Verdict**: Less than half the tests use meaningful assertions. The requirement states "at least half must use equalTo() or hasSize() or verify-call." Current ratio: 18 strong / 36 total = 50%. This technically meets the "at least half" threshold but barely, and the weak assertions undermine coverage effectiveness.

## Error handling in tests: partially correct

**Confirmed for error mocks**. Tests that mock errors using `on-error-continue` flows correctly use try-catch blocks:
- test-016, test-024, test-028, test-029: wrap flow-ref in `<try>` with `<on-error-continue type="ANY">` handler that sets `vars.caughtError`

**Gap**: These tests assert the error was caught (`vars.caughtError containsString(...)`) but don't validate the response payload shape. On-error-continue handlers typically transform errors into HTTP responses with errorCode and errorMessage fields. Tests should assert `payload.errorCode` or `payload.errorMessage` in addition to checking vars.caughtError.

**Confirmed for error propagation**: Tests that trigger `on-error-propagate` flows (test-015, test-025, test-027) correctly wrap calls in try-catch. However, they only assert `#[true] == true`, not the caught error type.

## API endpoint tests: correct flow names

**Confirmed correct**. Tests 018-022 call APIKit-generated flow names directly using flow-ref:
- test-018: `flow-ref name="post:\catalog\trigger:retail-catalog-apikit-config"`
- test-019: `flow-ref name="get:\catalog\runs:retail-catalog-apikit-config"`
- test-020: `flow-ref name="get:\catalog\products:retail-catalog-apikit-config"`
- test-021: `flow-ref name="get:\catalog\history:retail-catalog-apikit-config"`
- test-022: `flow-ref name="get:\catalog\invalidations:retail-catalog-apikit-config"`

No HTTP listener calls detected. All tests use flow-ref as required.

## No HTTP listener calls

**Confirmed**. All 36 tests use `<flow-ref>` to invoke flows. No `<http:request>` or listener trigger calls in test execution blocks. All http:request processor calls are mocked in before-suite or per-test mock-when blocks.

## Test distribution analysis

**Group 1 (Delta Classification)**: 5 tests covering NEW, UNCHANGED, CHANGED_CUSTOMER_FACING, CHANGED_INTERNAL_ONLY, HOLD_FOR_REVIEW. Strong verify-call assertions confirm db:insert and db:update behavior matches classification.

**Group 2 (Negative Scenarios)**: 12 tests covering edge cases. Mix of strong (test-006, test-007) and weak assertions. Tests for suspicious price changes, delisting, rejection threshold, and CDN 207/429/503 responses. Most assert flow completion without validating outcome payloads.

**Group 3 (API Endpoints)**: 5 tests covering all exposed endpoints. Each test mocks db:select to return sample data and asserts response structure (status field or payload size). Good coverage of happy path; no tests for API error responses (400, 404, 500).

**Group 4 (Error Handlers)**: 9 tests covering file access denied, DB connectivity/query errors, CDN HTTP errors, and fallback ANY handler. All correctly mock error types. Weak point: most only assert error was caught, not that error response has correct shape.

**Group 5 (Batch On-Complete)**: 2 tests verifying post-batch triggers (delisting for FULL extract, CDN orchestrator for DELTA with changes). Test-032 uses 1100 records to exceed batch size, test-033 uses changed product to trigger CDN. Assertions confirm flow completes but don't validate side effects.

**Group 6 (File Operations)**: 3 tests covering file move to inprocess, archive on success, and schema init. All assert flow completes without exception. No verification of file system state or DDL execution count.

## Coverage estimation

MUnit coverage reports are generated by tracking which message processors execute during tests and which branches are taken. High test count doesn't guarantee high coverage if tests use weak assertions or bypass key flows.

**Likely coverage factors**:
- **36 tests** invoke most flows in the application
- **Global mocks** ensure all external dependencies return predictable values
- **Per-test mocks** exercise different code branches (existing vs new products, errors vs success)
- **Weak assertions** don't reduce coverage per se, but they reduce confidence that coverage reflects real validation

**Coverage projection**: The test file should achieve **60-75% coverage** based on test distribution. Achieving 90%+ requires:
1. Strengthening assertions in Groups 4-6 to validate outcomes, not just flow completion
2. Adding tests for uncovered branches: API error responses, batch job pagination, CDN retry exhaustion, delisting validation
3. Verifying data transformation logic: hash calculation, change detection rules, price threshold boundaries

The gap to 90% isn't test count — it's coverage of edge cases, error response validation, and data transformation paths.

</details>

<details>
<summary>File map</summary>

**src/test/munit/catalog-core-tests.xml** — MUnit test suite with 36 tests across 6 groups (delta classification, negative scenarios, API endpoints, error handlers, batch on-complete, file operations)

</details>
