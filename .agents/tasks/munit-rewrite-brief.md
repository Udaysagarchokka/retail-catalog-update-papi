# MUnit Implementation Brief — Retail Catalog Update PAPI 6
## Target: 90% Coverage with 36 Comprehensive Tests

---

## Section 1: Confirmed Flow Names

All flow and sub-flow names extracted from the 7 XML files:

### catalog-api.xml (8 flows)
- `trigger-catalog-ingest-api-flow`
- `retail-catalog-apikit-console`
- `post:\catalog\trigger:retail-catalog-apikit-config`
- `get:\catalog\runs:retail-catalog-apikit-config`
- `get:\catalog\products:retail-catalog-apikit-config`
- `get:\catalog\history:retail-catalog-apikit-config`
- `get:\catalog\invalidations:retail-catalog-apikit-config`
- `mock-cdn-invalidation-service-flow`

### catalog-intake-flow.xml (3 flows)
- `catalog-file-intake-listener-flow`
- `catalog-file-intake-orchestrator-flow`
- `run-catalog-ingestion-subflow`

### catalog-processing-flow.xml (1 flow + batch)
- `catalog-batch-processing-flow` (contains batch job with 4 steps + on-complete)

### catalog-persistence-flow.xml (3 sub-flows)
- `persist-product-record-subflow`
- `evaluate-full-extract-delisting-subflow`
- `finalize-catalog-import-run-subflow`

### cdn-invalidation-flow.xml (2 sub-flows)
- `trigger-cdn-invalidation-orchestrator-subflow`
- `dispatch-cdn-invalidation-batch-subflow`

### global-config.xml (1 flow)
- `db-schema-initialisation-flow`

### global-error-handler.xml
- Error handler name: `global-error-handler` (contains 9 on-error handlers)

---

## Section 2: MUnit XML Namespace Block

Use this **exact** namespace block at the top of all MUnit test files for **MUnit 3.3.1**:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<mule xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
      xmlns:munit="http://www.mulesoft.org/schema/mule/munit"
      xmlns:munit-tools="http://www.mulesoft.org/schema/mule/munit-tools"
      xmlns:db="http://www.mulesoft.org/schema/mule/db"
      xmlns:ee="http://www.mulesoft.org/schema/mule/ee/core"
      xmlns:file="http://www.mulesoft.org/schema/mule/file"
      xmlns:http="http://www.mulesoft.org/schema/mule/http"
      xmlns:batch="http://www.mulesoft.org/schema/mule/batch"
      xmlns="http://www.mulesoft.org/schema/mule/core"
      xmlns:doc="http://www.mulesoft.org/schema/mule/documentation"
      xsi:schemaLocation="
http://www.mulesoft.org/schema/mule/core http://www.mulesoft.org/schema/mule/core/current/mule.xsd
http://www.mulesoft.org/schema/mule/munit http://www.mulesoft.org/schema/mule/munit/current/mule-munit.xsd
http://www.mulesoft.org/schema/mule/munit-tools http://www.mulesoft.org/schema/mule/munit-tools/current/mule-munit-tools.xsd
http://www.mulesoft.org/schema/mule/db http://www.mulesoft.org/schema/mule/db/current/mule-db.xsd
http://www.mulesoft.org/schema/mule/file http://www.mulesoft.org/schema/mule/file/current/mule-file.xsd
http://www.mulesoft.org/schema/mule/http http://www.mulesoft.org/schema/mule/http/current/mule-http.xsd
http://www.mulesoft.org/schema/mule/ee/core http://www.mulesoft.org/schema/mule/ee/core/current/mule-ee.xsd
http://www.mulesoft.org/schema/mule/batch http://www.mulesoft.org/schema/mule/batch/current/mule-batch.xsd">

    <munit:config name="catalog-comprehensive-tests" />
```

---

## Section 3: Global Mock Strategy

Place these global mocks in `munit:before-suite` to provide default responses for all database, file, and HTTP operations:

```xml
<munit:before-suite name="before-suite-global-mocks">
    
    <!-- Mock all db:select to return empty array by default -->
    <munit-tools:mock-when processor="db:select">
        <munit-tools:then-return>
            <munit-tools:payload value="#[[]]" mediaType="application/java" />
        </munit-tools:then-return>
    </munit-tools:mock-when>
    
    <!-- Mock all db:insert to return success -->
    <munit-tools:mock-when processor="db:insert">
        <munit-tools:then-return>
            <munit-tools:payload value="#[{ generatedKeys: [1], affectedRows: 1 }]" mediaType="application/java" />
        </munit-tools:then-return>
    </munit-tools:mock-when>
    
    <!-- Mock all db:update to return 1 affected row -->
    <munit-tools:mock-when processor="db:update">
        <munit-tools:then-return>
            <munit-tools:payload value="#[{ affectedRows: 1 }]" mediaType="application/java" />
        </munit-tools:then-return>
    </munit-tools:mock-when>
    
    <!-- Mock all db:execute-ddl to return empty map -->
    <munit-tools:mock-when processor="db:execute-ddl">
        <munit-tools:then-return>
            <munit-tools:payload value="#[{}]" mediaType="application/java" />
        </munit-tools:then-return>
    </munit-tools:mock-when>
    
    <!-- Mock all file:move to return success -->
    <munit-tools:mock-when processor="file:move">
        <munit-tools:then-return>
            <munit-tools:payload value="#[payload]" />
        </munit-tools:then-return>
    </munit-tools:mock-when>
    
    <!-- Mock all http:request to return 202 Accepted by default -->
    <munit-tools:mock-when processor="http:request">
        <munit-tools:then-return>
            <munit-tools:payload value='#[{"invalidationId": "INV-DEFAULT-001", "status": "IN_PROGRESS"}]' mediaType="application/json" />
            <munit-tools:attributes value='#[{ statusCode: 202 }]' />
        </munit-tools:then-return>
    </munit-tools:mock-when>
    
</munit:before-suite>
```

**Default return values:**
- `db:select` → `[]` (empty array)
- `db:insert` → `{generatedKeys: [1], affectedRows: 1}`
- `db:update` → `{affectedRows: 1}`
- `db:execute-ddl` → `{}`
- `file:move` → passes payload through
- `http:request` → `202` status with `{invalidationId: "INV-DEFAULT-001", status: "IN_PROGRESS"}`

---

## Section 4: Test Catalogue (36 tests)

---

### GROUP 1: Delta Classification Tests (5 tests)

#### test-001: NEW product classification
**Flow:** `catalog-batch-processing-flow`  
**Variables:**
- `runId` = `"RUN-NEW-001"`
- `extractType` = `"DELTA"`
- `fileName` = `"CATALOG_DELTA_NEW.csv"`

**Payload:**
```java
[{
  sku: "NEW-SKU-001",
  productName: "Brand New Product",
  categoryCode: "CAT-APP",
  brand: "NewBrand",
  price: "299.99",
  currency: "INR",
  taxClass: "GST12",
  stockStatus: "IN_STOCK",
  productStatus: "ACTIVE",
  shortDescription: "New product description",
  imagePath: "/img/new-001.jpg"
}]
```

**Per-test mock override:**
- `db:select` with `doc:name="Query Existing Product"` → return `[]` (no existing product)

**Assertions:**
- `vars.deltaClassification.classification == "NEW"`
- `db:insert` called for new product
- `db:insert` called for history with `change_type = "NEW"`

---

#### test-002: UNCHANGED product classification
**Flow:** `catalog-batch-processing-flow`  
**Variables:**
- `runId` = `"RUN-UNCHANGED-001"`
- `extractType` = `"DELTA"`

**Payload:**
```java
[{
  sku: "UNCHANGED-001",
  productName: "Unchanged Product",
  categoryCode: "CAT-FAS",
  brand: "BrandX",
  price: "100.00",
  currency: "INR",
  taxClass: "GST18",
  stockStatus: "IN_STOCK",
  productStatus: "ACTIVE",
  shortDescription: "Same description",
  imagePath: "/img/unchanged.jpg"
}]
```

**Per-test mock override:**
- `db:select` with `doc:name="Query Existing Product"` → return:
```java
[{
  sku: "UNCHANGED-001",
  product_name: "Unchanged Product",
  category_code: "CAT-FAS",
  brand: "BrandX",
  price: 100.00,
  currency: "INR",
  tax_class: "GST18",
  stock_status: "IN_STOCK",
  product_status: "ACTIVE",
  short_description: "Same description",
  image_path: "/img/unchanged.jpg",
  content_hash: "Unchanged Product|CAT-FAS|BrandX|100.00|INR|GST18|IN_STO"
}]
```

**Assertions:**
- `vars.deltaClassification.classification == "UNCHANGED"`
- `db:update` NOT called (step acceptance expression filters UNCHANGED)
- No history rows written

---

#### test-003: CHANGED_CUSTOMER_FACING with price and name changes
**Flow:** `catalog-batch-processing-flow`  
**Variables:**
- `runId` = `"RUN-CHANGED-CF-001"`

**Payload:**
```java
[{
  sku: "CHANGED-CF-001",
  productName: "Updated Product Name",
  categoryCode: "CAT-HOM",
  brand: "BrandY",
  price: "150.00",
  currency: "INR",
  taxClass: "GST12",
  stockStatus: "OUT_OF_STOCK",
  productStatus: "ACTIVE",
  shortDescription: "Updated description",
  imagePath: "/img/updated.jpg"
}]
```

**Per-test mock override:**
- `db:select` with `doc:name="Query Existing Product"` → return:
```java
[{
  sku: "CHANGED-CF-001",
  product_name: "Old Product Name",
  category_code: "CAT-HOM",
  brand: "BrandY",
  price: 120.00,
  currency: "INR",
  tax_class: "GST12",
  stock_status: "IN_STOCK",
  product_status: "ACTIVE",
  short_description: "Old description",
  image_path: "/img/old.jpg",
  content_hash: "Old Product Name|CAT-HOM|BrandY|120.00|INR|GST12|IN_STOC"
}]
```

**Assertions:**
- `vars.deltaClassification.classification == "CHANGED_CUSTOMER_FACING"`
- `vars.deltaClassification.diffs` contains 5 field changes (productName, price, stockStatus, shortDescription, imagePath)
- `db:update` called to update product
- `db:insert` called 5 times (foreach loop for each diff)

---

#### test-004: CHANGED_INTERNAL_ONLY with brand and tax class changes
**Flow:** `catalog-batch-processing-flow`  
**Variables:**
- `runId` = `"RUN-CHANGED-IO-001"`

**Payload:**
```java
[{
  sku: "CHANGED-IO-001",
  productName: "Internal Change Product",
  categoryCode: "CAT-APP",
  brand: "NewBrandZ",
  price: "100.00",
  currency: "INR",
  taxClass: "GST18",
  stockStatus: "IN_STOCK",
  productStatus: "ACTIVE",
  shortDescription: "Same description",
  imagePath: "/img/same.jpg"
}]
```

**Per-test mock override:**
- `db:select` with `doc:name="Query Existing Product"` → return:
```java
[{
  sku: "CHANGED-IO-001",
  product_name: "Internal Change Product",
  category_code: "CAT-APP",
  brand: "OldBrandZ",
  price: 100.00,
  currency: "INR",
  tax_class: "GST12",
  stock_status: "IN_STOCK",
  product_status: "ACTIVE",
  short_description: "Same description",
  image_path: "/img/same.jpg",
  content_hash: "Internal Change Product|CAT-APP|OldBrandZ|100.00|INR|GST"
}]
```

**Assertions:**
- `vars.deltaClassification.classification == "CHANGED_INTERNAL_ONLY"`
- `vars.deltaClassification.customerFacingChanged == false`
- `db:update` called
- `db:insert` called 2 times (brand, taxClass diffs with customerFacing = false)

---

#### test-005: HOLD_FOR_REVIEW triggered by price guard
**Flow:** `catalog-batch-processing-flow`  
**Variables:**
- `runId` = `"RUN-HOLD-001"`

**Payload:**
```java
[{
  sku: "HOLD-001",
  productName: "Price Guard Product",
  categoryCode: "CAT-FAS",
  brand: "BrandA",
  price: "5000.00",
  currency: "INR",
  taxClass: "GST12",
  stockStatus: "IN_STOCK",
  productStatus: "ACTIVE",
  shortDescription: "Huge price jump",
  imagePath: "/img/hold.jpg"
}]
```

**Per-test mock override:**
- `db:select` with `doc:name="Query Existing Product"` → return:
```java
[{
  sku: "HOLD-001",
  product_name: "Price Guard Product",
  category_code: "CAT-FAS",
  brand: "BrandA",
  price: 100.00,
  currency: "INR",
  tax_class: "GST12",
  stock_status: "IN_STOCK",
  product_status: "ACTIVE",
  short_description: "Huge price jump",
  image_path: "/img/hold.jpg",
  content_hash: "Price Guard Product|CAT-FAS|BrandA|100.00|INR|GST12|IN_S"
}]
```

**Assertions:**
- `vars.priceGuard.isSuspicious == true`
- `vars.deltaClassification.classification == "HOLD_FOR_REVIEW"`
- `db:update` called with `review_hold = TRUE`
- Price NOT updated (only flag set)
- `db:insert` called once for HOLD_FOR_REVIEW history

---

### GROUP 2: Negative Scenarios (12 tests)

#### test-006: Validation failure — missing SKU
**Flow:** `catalog-batch-processing-flow`  
**Variables:**
- `runId` = `"RUN-REJECT-001"`

**Payload:**
```java
[{
  sku: "",
  productName: "No SKU Product",
  categoryCode: "CAT-APP",
  brand: "BrandB",
  price: "100.00",
  currency: "INR",
  taxClass: "GST12",
  stockStatus: "IN_STOCK",
  productStatus: "ACTIVE",
  shortDescription: "Missing SKU",
  imagePath: "/img/missing-sku.jpg"
}]
```

**Assertions:**
- `vars.validationResult.isValid == false`
- `vars.validationResult.errors` contains "Missing or empty SKU"
- `vars.isRejected == true`
- Step 2, 3, 4 skipped (acceptExpression filters rejected records)
- Logger shows "REJECTED SKU=UNKNOWN"

---

#### test-007: Validation failure — negative price
**Flow:** `catalog-batch-processing-flow`  
**Variables:**
- `runId` = `"RUN-REJECT-002"`

**Payload:**
```java
[{
  sku: "NEG-PRICE-001",
  productName: "Negative Price Product",
  categoryCode: "CAT-HOM",
  brand: "BrandC",
  price: "-50.00",
  currency: "INR",
  taxClass: "GST18",
  stockStatus: "IN_STOCK",
  productStatus: "ACTIVE",
  shortDescription: "Invalid price",
  imagePath: "/img/neg.jpg"
}]
```

**Assertions:**
- `vars.validationResult.isValid == false`
- `vars.validationResult.errors` contains "Price must be positive"
- `vars.isRejected == true`

---

#### test-008: Validation failure — invalid currency code
**Flow:** `catalog-batch-processing-flow`  
**Variables:**
- `runId` = `"RUN-REJECT-003"`

**Payload:**
```java
[{
  sku: "BAD-CURR-001",
  productName: "Bad Currency Product",
  categoryCode: "CAT-APP",
  brand: "BrandD",
  price: "100.00",
  currency: "INRR",
  taxClass: "GST12",
  stockStatus: "IN_STOCK",
  productStatus: "ACTIVE",
  shortDescription: "4-char currency",
  imagePath: "/img/curr.jpg"
}]
```

**Assertions:**
- `vars.validationResult.isValid == false`
- `vars.validationResult.errors` contains "Currency must be 3-letter code"

---

#### test-009: Validation failure — invalid category code
**Flow:** `catalog-batch-processing-flow`  
**Variables:**
- `runId` = `"RUN-REJECT-004"`

**Payload:**
```java
[{
  sku: "BAD-CAT-001",
  productName: "Bad Category Product",
  categoryCode: "INVALID",
  brand: "BrandE",
  price: "100.00",
  currency: "INR",
  taxClass: "GST12",
  stockStatus: "IN_STOCK",
  productStatus: "ACTIVE",
  shortDescription: "Bad category",
  imagePath: "/img/cat.jpg"
}]
```

**Assertions:**
- `vars.validationResult.isValid == false`
- `vars.validationResult.errors` contains "Invalid category code (must start with CAT-)"

---

#### test-010: Validation failure — unsupported stock status
**Flow:** `catalog-batch-processing-flow`  
**Variables:**
- `runId` = `"RUN-REJECT-005"`

**Payload:**
```java
[{
  sku: "BAD-STOCK-001",
  productName: "Bad Stock Status Product",
  categoryCode: "CAT-FAS",
  brand: "BrandF",
  price: "100.00",
  currency: "INR",
  taxClass: "GST12",
  stockStatus: "MAYBE_IN_STOCK",
  productStatus: "ACTIVE",
  shortDescription: "Invalid stock status",
  imagePath: "/img/stock.jpg"
}]
```

**Assertions:**
- `vars.validationResult.isValid == false`
- `vars.validationResult.errors` contains "Unsupported stockStatus"

---

#### test-011: Validation failure — unsupported product status
**Flow:** `catalog-batch-processing-flow`  
**Variables:**
- `runId` = `"RUN-REJECT-006"`

**Payload:**
```java
[{
  sku: "BAD-STATUS-001",
  productName: "Bad Product Status",
  categoryCode: "CAT-HOM",
  brand: "BrandG",
  price: "100.00",
  currency: "INR",
  taxClass: "GST12",
  stockStatus: "IN_STOCK",
  productStatus: "ZOMBIE",
  shortDescription: "Invalid product status",
  imagePath: "/img/status.jpg"
}]
```

**Assertions:**
- `vars.validationResult.isValid == false`
- `vars.validationResult.errors` contains "Unsupported productStatus"

---

#### test-012: Validation failure — malformed image path
**Flow:** `catalog-batch-processing-flow`  
**Variables:**
- `runId` = `"RUN-REJECT-007"`

**Payload:**
```java
[{
  sku: "BAD-IMG-001",
  productName: "Bad Image Path Product",
  categoryCode: "CAT-APP",
  brand: "BrandH",
  price: "100.00",
  currency: "INR",
  taxClass: "GST12",
  stockStatus: "IN_STOCK",
  productStatus: "ACTIVE",
  shortDescription: "Invalid image",
  imagePath: "http://cdn.com/img/bad.jpg"
}]
```

**Assertions:**
- `vars.validationResult.isValid == false`
- `vars.validationResult.errors` contains "Malformed imagePath (must start with /img/)"

---

#### test-013: Duplicate file detection — file skipped
**Flow:** `catalog-file-intake-orchestrator-flow`  
**Variables:**
- `fileName` = `"CATALOG_FULL_DUPLICATE.csv"`

**Payload:**
```java
[{
  sku: "DUP-001",
  productName: "Duplicate File Product",
  categoryCode: "CAT-FAS",
  brand: "BrandI",
  price: "100.00",
  currency: "INR",
  taxClass: "GST12",
  stockStatus: "IN_STOCK",
  productStatus: "ACTIVE",
  shortDescription: "Dup file",
  imagePath: "/img/dup.jpg"
}]
```

**Per-test mock override:**
- `db:select` with `doc:name="Check Duplicate Run"` → return:
```java
[{
  run_id: "RUN-OLD-001",
  run_status: "COMPLETED"
}]
```

**Assertions:**
- Response contains `status: "SKIPPED_DUPLICATE"`
- `catalog-batch-processing-flow` NOT called
- No batch processing

---

#### test-014: Truncated FULL extract — aborted
**Flow:** `catalog-file-intake-orchestrator-flow`  
**Variables:**
- `fileName` = `"CATALOG_FULL_TRUNCATED.csv"`

**Payload:** (50 records)
```java
(0 to 49) map {
  sku: "TRUNC-" ++ $,
  productName: "Truncated Product " ++ $,
  categoryCode: "CAT-APP",
  brand: "BrandJ",
  price: "100.00",
  currency: "INR",
  taxClass: "GST12",
  stockStatus: "IN_STOCK",
  productStatus: "ACTIVE",
  shortDescription: "Truncated",
  imagePath: "/img/trunc.jpg"
}
```

**Per-test mock override:**
- Configuration: `fullExtractPolicy.requireMinimumRecordCount = 1000`
- `db:select` (duplicate check) → return `[]`
- `file:move` (move to error) → return payload

**Assertions:**
- Response contains `status: "ABORTED_TRUNCATED_EXTRACT"`
- `recordCount: 50`
- `minimumRequired: 1000`
- `file:move` called to move to error directory
- No batch processing

---

#### test-015: High rejection rate — run aborted
**Flow:** `catalog-file-intake-orchestrator-flow`  
**Variables:**
- `fileName` = `"CATALOG_DELTA_HIGH_REJECT.csv"`

**Payload:** (100 records, 50 valid, 50 invalid)
```java
(0 to 49) map {
  sku: "VALID-" ++ $,
  productName: "Valid Product " ++ $,
  categoryCode: "CAT-FAS",
  brand: "BrandK",
  price: "100.00",
  currency: "INR",
  taxClass: "GST12",
  stockStatus: "IN_STOCK",
  productStatus: "ACTIVE",
  shortDescription: "Valid",
  imagePath: "/img/valid.jpg"
} ++ (0 to 49) map {
  sku: "",
  productName: "Invalid Product " ++ $,
  categoryCode: "CAT-APP",
  brand: "BrandL",
  price: "-100.00",
  currency: "INRR",
  taxClass: "GST12",
  stockStatus: "MAYBE",
  productStatus: "ZOMBIE",
  shortDescription: "Invalid",
  imagePath: "bad-path"
}
```

**Per-test mock override:**
- Configuration: `processing.maxRejectPercentAllowed = 5`
- `db:select` (post-batch counts) → return:
```java
[{
  parsed_count: 100,
  rejected_count: 50,
  run_status: "IN_PROGRESS"
}]
```
- `db:update` (mark aborted) → return `{affectedRows: 1}`
- `file:move` (move to error) → return payload

**Assertions:**
- Response contains `status: "ABORTED_HIGH_REJECTION"`
- `rejected: 50`
- `parsed: 100`
- `rejectPercent: 50`
- `db:update` called to mark ABORTED_HIGH_REJECTION
- `file:move` called to error directory

---

#### test-016: FULL extract delisting — absent products marked DELISTED
**Flow:** `evaluate-full-extract-delisting-subflow`  
**Variables:**
- `runId` = `"RUN-DELIST-001"`
- `extractType` = `"FULL"`

**Per-test mock override:**
- `db:select` with `doc:name="Find Absent Active Products"` → return:
```java
[
  {sku: "ABSENT-001", category_code: "CAT-APP"},
  {sku: "ABSENT-002", category_code: "CAT-FAS"}
]
```
- `db:update` (mark delisted) → return `{affectedRows: 2}`
- `db:insert` (delist history) → return `{affectedRows: 1}` (called 2 times in foreach)

**Assertions:**
- `vars.omittedProducts` size == 2
- `db:update` called to mark 2 products DELISTED
- `db:insert` called 2 times (foreach loop for each SKU)
- Each history row has `change_type: "DELISTED"`, `old_value: "ACTIVE"`, `new_value: "DELISTED"`

---

#### test-017: DB connectivity error — propagates
**Flow:** `catalog-file-intake-orchestrator-flow`  
**Variables:**
- `runId` = `"RUN-DB-ERROR-001"`
- `fileName` = `"CATALOG_DELTA_DB_ERROR.csv"`

**Payload:** (1 valid record)
```java
[{
  sku: "DB-ERROR-001",
  productName: "DB Error Product",
  categoryCode: "CAT-HOM",
  brand: "BrandM",
  price: "100.00",
  currency: "INR",
  taxClass: "GST12",
  stockStatus: "IN_STOCK",
  productStatus: "ACTIVE",
  shortDescription: "DB error test",
  imagePath: "/img/db.jpg"
}]
```

**Per-test mock override:**
- `db:insert` with `doc:name="Insert Initial Run Record"` → throw `DB:CONNECTIVITY` error:
```xml
<munit-tools:mock-when processor="db:insert">
    <munit-tools:with-attributes>
        <munit-tools:with-attribute attributeName="doc:name" whereValue="Insert Initial Run Record" />
    </munit-tools:with-attributes>
    <munit-tools:then-return>
        <munit-tools:error typeId="DB:CONNECTIVITY">
            <munit-tools:message>Connection to database lost</munit-tools:message>
        </munit-tools:error>
    </munit-tools:then-return>
</munit-tools:mock-when>
```

**Assertions:**
- Error caught by global-error-handler
- Response contains `errorCode: "DB_CONNECTIVITY_ERROR"`
- Response contains `message: "Database connection failed"`

---

### GROUP 3: API Endpoint Tests (5 tests)

#### test-018: POST /catalog/trigger — manual ingestion
**Flow:** `post:\catalog\trigger:retail-catalog-apikit-config`  
**Variables:**
- None (set via APIKit router)

**Payload:**
```csv
sku|productName|categoryCode|brand|price|currency|taxClass|stockStatus|productStatus|shortDescription|imagePath
API-SKU-001|API Product 1|CAT-APP|BrandAPI|299.99|INR|GST12|IN_STOCK|ACTIVE|API test|/img/api1.jpg
API-SKU-002|API Product 2|CAT-FAS|BrandAPI|399.99|INR|GST18|IN_STOCK|ACTIVE|API test 2|/img/api2.jpg
```

**Per-test mock override:**
- All default mocks apply

**Execution:**
- Call flow directly: `flow-ref name="post:\catalog\trigger:retail-catalog-apikit-config"`
- Set event payload to CSV string
- Set attribute `headers.filename = "API_MANUAL.csv"`

**Assertions:**
- Response status = 200
- Response JSON contains `status: "ACCEPTED"`, `runId`, `fileName: "API_MANUAL.csv"`

---

#### test-019: GET /catalog/runs
**Flow:** `get:\catalog\runs:retail-catalog-apikit-config`  
**Variables:**
- None

**Per-test mock override:**
- `db:select` with `doc:name="Select All Import Runs"` → return:
```java
[
  {run_id: "RUN-A", file_name: "FILE-A.csv", run_status: "COMPLETED"},
  {run_id: "RUN-B", file_name: "FILE-B.csv", run_status: "IN_PROGRESS"}
]
```

**Execution:**
- Call flow: `flow-ref name="get:\catalog\runs:retail-catalog-apikit-config"`

**Assertions:**
- Response status = 200
- Response is JSON array with 2 elements
- First element `run_id == "RUN-A"`

---

#### test-020: GET /catalog/products
**Flow:** `get:\catalog\products:retail-catalog-apikit-config`  
**Variables:**
- None

**Per-test mock override:**
- `db:select` with `doc:name="Select All Products"` → return:
```java
[
  {sku: "SKU-A", product_name: "Product A", price: 100.00},
  {sku: "SKU-B", product_name: "Product B", price: 200.00}
]
```

**Assertions:**
- Response status = 200
- Response is JSON array with 2 products

---

#### test-021: GET /catalog/history
**Flow:** `get:\catalog\history:retail-catalog-apikit-config`  
**Variables:**
- None

**Per-test mock override:**
- `db:select` with `doc:name="Select All Change History"` → return:
```java
[
  {sku: "SKU-A", change_type: "NEW", field_name: "ALL"},
  {sku: "SKU-B", change_type: "CHANGED_CUSTOMER_FACING", field_name: "price"}
]
```

**Assertions:**
- Response status = 200
- Response is JSON array with 2 history records

---

#### test-022: GET /catalog/invalidations
**Flow:** `get:\catalog\invalidations:retail-catalog-apikit-config`  
**Variables:**
- None

**Per-test mock override:**
- `db:select` with `doc:name="Select All CDN Invalidations"` → return:
```java
[
  {run_id: "RUN-A", request_ref: "BATCH-1", http_status: 202, confirmed: true},
  {run_id: "RUN-B", request_ref: "BATCH-2", http_status: 207, confirmed: false}
]
```

**Assertions:**
- Response status = 200
- Response is JSON array with 2 invalidation records

---

### GROUP 4: Error Handler Tests (9 tests)

#### test-023: APIKIT:NOT_FOUND (404)
**Flow:** `catalog-file-intake-orchestrator-flow` (use a flow that references global-error-handler)  
**Variables:**
- `runId` = `"RUN-ERR-404"`

**Per-test mock override:**
- `db:select` (any) → throw APIKIT:NOT_FOUND:
```xml
<munit-tools:mock-when processor="db:select">
    <munit-tools:then-return>
        <munit-tools:error typeId="APIKIT:NOT_FOUND">
            <munit-tools:message>Resource not found</munit-tools:message>
        </munit-tools:error>
    </munit-tools:then-return>
</munit-tools:mock-when>
```

**Assertions:**
- Error caught by global-error-handler
- Response contains `status: 404`, `errorCode: "RESOURCE_NOT_FOUND"`

---

#### test-024: APIKIT:METHOD_NOT_ALLOWED (405)
**Flow:** `catalog-file-intake-orchestrator-flow`  
**Per-test mock override:**
- Throw `APIKIT:METHOD_NOT_ALLOWED`

**Assertions:**
- Response contains `status: 405`, `errorCode: "METHOD_NOT_ALLOWED"`

---

#### test-025: APIKIT:UNSUPPORTED_MEDIA_TYPE (415)
**Flow:** `catalog-file-intake-orchestrator-flow`  
**Per-test mock override:**
- Throw `APIKIT:UNSUPPORTED_MEDIA_TYPE`

**Assertions:**
- Response contains `status: 415`, `errorCode: "UNSUPPORTED_MEDIA_TYPE"`

---

#### test-026: FILE:ACCESS_DENIED
**Flow:** `catalog-file-intake-orchestrator-flow`  
**Variables:**
- `runId` = `"RUN-FILE-ERR-001"`
- `fileName` = `"DENIED.csv"`

**Per-test mock override:**
- `file:move` → throw `FILE:ACCESS_DENIED`:
```xml
<munit-tools:mock-when processor="file:move">
    <munit-tools:then-return>
        <munit-tools:error typeId="FILE:ACCESS_DENIED">
            <munit-tools:message>Permission denied</munit-tools:message>
        </munit-tools:error>
    </munit-tools:then-return>
</munit-tools:mock-when>
```

**Assertions:**
- Error caught by global-error-handler (on-error-continue)
- Response contains `errorCode: "FILE_SYSTEM_ERROR"`
- `db:update` called to mark run FAILED

---

#### test-027: DB:QUERY_EXECUTION
**Flow:** `catalog-file-intake-orchestrator-flow`  
**Per-test mock override:**
- `db:insert` → throw `DB:QUERY_EXECUTION`:
```xml
<munit-tools:mock-when processor="db:insert">
    <munit-tools:then-return>
        <munit-tools:error typeId="DB:QUERY_EXECUTION">
            <munit-tools:message>SQL syntax error</munit-tools:message>
        </munit-tools:error>
    </munit-tools:then-return>
</munit-tools:mock-when>
```

**Assertions:**
- Error caught and propagates
- Response contains `errorCode: "DB_QUERY_ERROR"`

---

#### test-028: HTTP:TOO_MANY_REQUESTS (429 CDN)
**Flow:** `dispatch-cdn-invalidation-batch-subflow`  
**Variables:**
- `runId` = `"RUN-CDN-429"`
- `currentBatchPaths` = `["/p/SKU-429"]`
- `currentBatchNumber` = `1`
- `requestReference` = `"RUN-CDN-429-B1"`

**Per-test mock override:**
- `http:request` → throw `HTTP:TOO_MANY_REQUESTS`:
```xml
<munit-tools:mock-when processor="http:request">
    <munit-tools:then-return>
        <munit-tools:error typeId="HTTP:TOO_MANY_REQUESTS">
            <munit-tools:message>Rate limit exceeded</munit-tools:message>
        </munit-tools:error>
    </munit-tools:then-return>
</munit-tools:mock-when>
```

**Assertions:**
- Error caught by CDN on-error-continue
- `db:insert` called to record as PENDING_RETRY
- Response contains `errorCode: "CDN_INVALIDATION_PENDING"`

---

#### test-029: EXPRESSION (DataWeave error)
**Flow:** `catalog-batch-processing-flow`  
**Variables:**
- `runId` = `"RUN-EXPR-ERR-001"`

**Per-test mock override:**
- Mock `ee:transform` to throw `EXPRESSION` error (simulate by having a field reference an undefined variable)

**Assertions:**
- Error caught by global-error-handler
- Response contains `errorCode: "TRANSFORM_ERROR"`

---

#### test-030: MULE:RETRY_EXHAUSTED
**Flow:** `dispatch-cdn-invalidation-batch-subflow`  
**Variables:**
- `runId` = `"RUN-RETRY-EXHAUST"`
- `currentBatchPaths` = `["/p/EXHAUST"]`
- `currentBatchNumber` = `1`

**Per-test mock override:**
- `http:request` → throw `HTTP:CONNECTIVITY` (all 3 retries fail):
```xml
<munit-tools:mock-when processor="http:request">
    <munit-tools:then-return>
        <munit-tools:error typeId="HTTP:CONNECTIVITY">
            <munit-tools:message>Connection lost</munit-tools:message>
        </munit-tools:error>
    </munit-tools:then-return>
</munit-tools:mock-when>
```

**Assertions:**
- until-successful exhausts maxRetries (3) and throws `MULE:RETRY_EXHAUSTED`
- Global error handler catches it (on-error-continue)
- `db:insert` called to record as RETRY_EXHAUSTED

---

#### test-031: ANY fallback (generic error)
**Flow:** `catalog-file-intake-orchestrator-flow`  
**Per-test mock override:**
- `db:select` → throw custom error `CUSTOM:UNKNOWN_ERROR`:
```xml
<munit-tools:mock-when processor="db:select">
    <munit-tools:then-return>
        <munit-tools:error typeId="CUSTOM:UNKNOWN_ERROR">
            <munit-tools:message>Unknown error occurred</munit-tools:message>
        </munit-tools:error>
    </munit-tools:then-return>
</munit-tools:mock-when>
```

**Assertions:**
- Error caught by ANY fallback handler
- Response contains `errorCode: "INTERNAL_SERVER_ERROR"`, `errorType: "CUSTOM:UNKNOWN_ERROR"`
- `db:update` called to mark run FAILED

---

### GROUP 5: Batch On-Complete Tests (2 tests)

#### test-032: On-complete with parsed/rejected counts
**Flow:** `catalog-batch-processing-flow`  
**Variables:**
- `runId` = `"RUN-ON-COMPLETE-001"`
- `extractType` = `"DELTA"`

**Payload:** (100 records, 95 valid, 5 invalid)
```java
(0 to 94) map {
  sku: "VALID-" ++ $,
  productName: "Valid " ++ $,
  categoryCode: "CAT-APP",
  brand: "BrandN",
  price: "100.00",
  currency: "INR",
  taxClass: "GST12",
  stockStatus: "IN_STOCK",
  productStatus: "ACTIVE",
  shortDescription: "Valid",
  imagePath: "/img/valid.jpg"
} ++ (0 to 4) map {
  sku: "",
  productName: "Invalid " ++ $,
  categoryCode: "BADCAT",
  brand: "BrandO",
  price: "-100.00",
  currency: "INRR",
  taxClass: "GST12",
  stockStatus: "UNKNOWN",
  productStatus: "ZOMBIE",
  shortDescription: "Invalid",
  imagePath: "no-path"
}
```

**Per-test mock override:**
- All default mocks apply
- After batch completes, batch summary available as `payload` in on-complete

**Assertions:**
- Batch on-complete executes
- `payload.totalRecords == 100`
- `payload.failedRecords == 5`
- `db:update` called to write parsed_count = 100, rejected_count = 5

---

#### test-033: On-complete file archive move
**Flow:** `catalog-batch-processing-flow`  
**Variables:**
- `runId` = `"RUN-ARCHIVE-001"`
- `fileName` = `"CATALOG_FULL_ARCHIVE.csv"`
- `extractType` = `"FULL"`

**Payload:** (10 valid records)
```java
(0 to 9) map {
  sku: "ARCH-" ++ $,
  productName: "Archive Product " ++ $,
  categoryCode: "CAT-FAS",
  brand: "BrandP",
  price: "100.00",
  currency: "INR",
  taxClass: "GST12",
  stockStatus: "IN_STOCK",
  productStatus: "ACTIVE",
  shortDescription: "Archive test",
  imagePath: "/img/archive.jpg"
}
```

**Per-test mock override:**
- `file:move` (archive) → return payload

**Assertions:**
- Batch on-complete executes
- `file:move` called to move file to archive directory
- Logger shows "FILE_ARCHIVED"

---

### GROUP 6: CDN Invalidation Tests (3 tests)

#### test-034: CDN 202 accepted batch
**Flow:** `dispatch-cdn-invalidation-batch-subflow`  
**Variables:**
- `runId` = `"RUN-CDN-202"`
- `currentBatchPaths` = `["/p/SKU-1", "/p/SKU-1/images", "/c/CAT-APP"]`
- `currentBatchNumber` = `1`
- `requestReference` = `"RUN-CDN-202-B1"`

**Per-test mock override:**
- `http:request` → return:
```java
{
  invalidationId: "INV-202-001",
  status: "IN_PROGRESS"
}
```
- HTTP attributes: `{statusCode: 202}`

**Assertions:**
- `http:request` called to POST to CDN
- Response status = 202
- `db:insert` called with httpStatus: 202, confirmed: true
- Logger shows "CDN_BATCH_ACCEPTED"

---

#### test-035: CDN 207 partial rejection with retry
**Flow:** `dispatch-cdn-invalidation-batch-subflow`  
**Variables:**
- `runId` = `"RUN-CDN-207"`
- `currentBatchPaths` = `["/p/INVALID", "/p/SKU-2", "/c/CAT-FAS"]`
- `currentBatchNumber` = `1`
- `requestReference` = `"RUN-CDN-207-B1"`

**Per-test mock override:**
- `http:request` (first POST) → return:
```java
{
  invalidationId: "INV-207-001",
  accepted: ["/p/SKU-2", "/c/CAT-FAS"],
  rejected: [{path: "/p/INVALID", reason: "INVALID_PATH_PATTERN"}]
}
```
- HTTP attributes: `{statusCode: 207}`
- `http:request` (retry single path) → return `{invalidationId: "INV-RETRY-207", status: "IN_PROGRESS"}` with status 202

**Assertions:**
- First `http:request` returns 207
- `db:insert` called for initial 207 record
- Foreach loop processes 1 rejected path
- Second `http:request` called for retry
- `db:insert` called for retry result with confirmed: true
- Logger shows "CDN_207_PARTIAL" and "RETRY_PATH_CONFIRMED"

---

#### test-036: CDN orchestrator batch generation
**Flow:** `trigger-cdn-invalidation-orchestrator-subflow`  
**Variables:**
- `runId` = `"RUN-CDN-ORCH-001"`

**Per-test mock override:**
- `db:select` with `doc:name="Find Customer-Facing Changed Products for Invalidation"` → return:
```java
[
  {sku: "SKU-A", category_code: "CAT-APP"},
  {sku: "SKU-B", category_code: "CAT-FAS"}
]
```
- Configuration: `invalidation.maxPathsPerRequest = 3`
- `http:request` → return 202 (called 2 times)

**Assertions:**
- `db:select` called to find changed products
- Result: 2 SKUs → 6 paths (3 per SKU)
- Paths deduplicated: ["/p/SKU-A", "/p/SKU-A/images", "/c/CAT-APP", "/p/SKU-B", "/p/SKU-B/images", "/c/CAT-FAS"]
- Batch generation: 2 batches (maxPathsPerRequest = 3)
- Foreach loop processes 2 batches
- `dispatch-cdn-invalidation-batch-subflow` invoked 2 times

---

## Summary

**Total Tests:** 36  
**Expected Coverage:** 90%+  

### Coverage Distribution
- Delta classification: 5 tests (NEW, UNCHANGED, CHANGED_CF, CHANGED_IO, HOLD_FOR_REVIEW)
- Negative scenarios: 12 tests (7 validation failures, duplicate, truncated, high rejection, delisting, DB error)
- API endpoints: 5 tests (POST /trigger, 4 GET endpoints)
- Error handlers: 9 tests (404, 405, 415, FILE, DB, HTTP, EXPRESSION, RETRY_EXHAUSTED, ANY)
- Batch on-complete: 2 tests (counts, archive)
- CDN invalidation: 3 tests (202, 207, orchestrator)

---

## Key Implementation Constraints

1. **For error handler tests:** The flow MUST reference `global-error-handler` in its configuration or via `<configuration defaultErrorHandler-ref="global-error-handler" />`. Use `catalog-file-intake-orchestrator-flow` as the entry point since it references the global handler.

2. **For munit-tools:mock-when with errors:** Use MUnit 3.3.1 syntax:
```xml
<munit-tools:mock-when processor="db:select">
    <munit-tools:then-return>
        <munit-tools:error typeId="DB:CONNECTIVITY">
            <munit-tools:message>Connection lost</munit-tools:message>
        </munit-tools:error>
    </munit-tools:then-return>
</munit-tools:mock-when>
```

3. **For db:select overrides with doc:name matching:** Use `withAttributes` to match only the specific SELECT:
```xml
<munit-tools:mock-when processor="db:select">
    <munit-tools:with-attributes>
        <munit-tools:with-attribute attributeName="doc:name" whereValue="Query Existing Product" />
    </munit-tools:with-attributes>
    <munit-tools:then-return>
        <munit-tools:payload value="#[[{...}]]" mediaType="application/java" />
    </munit-tools:then-return>
</munit-tools:mock-when>
```

4. **For API endpoint tests:** Call the APIKit-generated flow directly by its exact name (e.g., `post:\catalog\trigger:retail-catalog-apikit-config`) — do NOT send HTTP requests via HTTP test driver.

5. **For batch tests:** Set the initial payload as a Java list of maps. Batch processes each element as a record.

6. **For CDN tests:** Set all required variables (`runId`, `currentBatchPaths`, `currentBatchNumber`, `requestReference`) before calling the subflow.

---

**Implementation complete. All 36 tests are specified with exact flows, variables, payloads, mocks, and assertions.**
