# High Level Design (HLD) Document
## Retail Real-Time Product Catalog Update API
**Hackathon Challenge:** 2027 Nurture Partner Network (NPN) MuleSoft Hackathon  
**Architecture Style:** API-Led Connectivity (Process API Layer)  
**Runtime:** MuleSoft Mule Runtime 4.4+ / Anypoint Studio 7.x  

---

## 1. Executive Summary & Architecture Overview

This project implements an enterprise-grade, high-throughput MuleSoft integration that automates retail catalog updates from flat file extracts. It features **streaming batch ingestion**, **O(1) SHA-256 change detection**, **intelligent customer-facing vs. internal delta classification**, **price swing guardrails**, **selective non-destructive database updates**, and **rate-limited CDN cache invalidation**.

### API-Led Connectivity Architecture

```mermaid
graph TD
    subgraph System Layer
        SYS_DB[(Retail Database<br/>products, history, runs, invalidations)]
        SYS_CDN[CDN Edge Provider<br/>Akamai / Cloudflare / CloudFront]
        SYS_FILE[File System / SFTP / S3<br/>Inbound & In-Process Directories]
    end

    subgraph Process Layer - retail-catalog-update-papi
        P_INTAKE[Catalog File Intake & Deduplication Engine]
        P_BATCH[Streamed Batch Processor - 500 Records/Block]
        P_DELTA[SHA-256 Delta & Field Classification Engine]
        P_GUARD[Price Swing Guardrail Engine]
        P_CDN[CDN Invalidation Orchestrator & Backoff Manager]
    end

    subgraph Experience Layer
        EXP_OPS[Operations & Catalog Manager Dashboard]
        EXP_MON[Monitoring & Alerting Center - Dynatrace / Splunk]
    end

    SYS_FILE -->|Polls Inbound| P_INTAKE
    P_INTAKE --> P_BATCH
    P_BATCH --> P_DELTA
    P_DELTA --> P_GUARD
    P_GUARD -->|Selective Upsert| SYS_DB
    P_GUARD -->|Invalidation Paths| P_CDN
    P_CDN -->|Batch POST Max 30 Paths| SYS_CDN
    P_INTAKE & P_BATCH & P_CDN -->|Audit Status| SYS_DB
    EXP_OPS -->|REST Trigger & Status Queries| P_INTAKE
    P_INTAKE --> EXP_MON
```

---

## 2. Component Design & Responsibilities

| Component | Flow / File | Core Responsibility |
| :--- | :--- | :--- |
| **Intake & Checksum Guard** | `catalog-intake-flow.xml` | Ingests CSVs via File Listener, verifies file lock (`timeBetweenSizeCheck`), calculates SHA-256 file checksum, rejects duplicates. |
| **Streamed Batch Processing** | `catalog-processing-flow.xml` | Uses `<batch:job>` with block size 500. Processes records as streams to prevent JVM memory exhaustion. |
| **Validation Engine** | `validate-record.dwl` | Validates mandatory fields, regex formats, positive pricing, and enum constraints. |
| **Delta Classifier** | `classify-delta.dwl` | Computes SHA-256 hash across 10 business fields. Categorizes into `NEW`, `UNCHANGED`, `CHANGED_CUSTOMER_FACING`, `CHANGED_INTERNAL_ONLY`. |
| **Price Guardrail** | `price-guard-check.dwl` | Evaluates price swing. Increases >50% or decreases >40% trigger `HOLD_FOR_REVIEW` without altering stored price. |
| **Selective Persistence** | `catalog-persistence-flow.xml` | Writes only `NEW` and `CHANGED` rows; preserves `UNCHANGED` timestamps. Records all diffs to `product_change_history`. |
| **Delisting Engine** | `catalog-persistence-flow.xml` | Full extract runs mark missing active records as `DELISTED` (never physical delete) subject to safety record counts. |
| **CDN Invalidation Engine** | `cdn-invalidation-flow.xml` | Batches paths (max 30), calls CDN API, implements HTTP 429 backoff retry, tracks HTTP 207 partial responses. |
| **Global Error Handler** | `global-error-handler.xml` | Centralized recovery for DB, HTTP, and File errors. Ensures CDN failure never rolls back valid DB commits. |

---

## 3. End-to-End Sequence Diagram

```mermaid
sequenceDiagram
    autonumber
    actor PMS as Product Management System
    participant Mule as MuleSoft Application
    participant DB as Retail Database
    participant CDN as CDN Provider API

    PMS->>Mule: Writes CATALOG_FULL_*.csv to data/input
    Note over Mule: File Listener locks file until write is complete
    Mule->>Mule: Calculate File Checksum (SHA-256)
    Mule->>DB: Check if (file_name, file_checksum) exists
    alt Is Duplicate File
        Mule-->>PMS: Skip processing & move to archive (Zero invalidations)
    else Is New File
        Mule->>DB: Insert catalog_import_runs (Status: IN_PROGRESS)
        Mule->>Mule: Move file to data/in-process
        loop For each record in Batch (500 per block)
            Mule->>Mule: Validate SKU, Price > 0, Category, Image Path
            Mule->>Mule: Compute Record SHA-256 Hash
            Mule->>DB: SELECT * FROM products WHERE sku = :sku
            alt Product Missing
                Mule->>DB: INSERT into products (Classification: NEW)
                Mule->>DB: INSERT into product_change_history
            else Hash Matches Stored Hash
                Note over Mule: UNCHANGED - No DB write, preserves updated_at
            else Hash Differs
                Mule->>Mule: Evaluate Price Swing (+50% / -40%)
                alt Suspicious Price Swing
                    Mule->>DB: UPDATE review_hold = true (Price unchanged)
                    Mule->>DB: INSERT history (HOLD_FOR_REVIEW)
                else Internal-Only Change (e.g. taxClass)
                    Mule->>DB: UPDATE products & INSERT history (0 CDN calls)
                else Customer-Facing Change
                    Mule->>DB: UPDATE products & INSERT history
                    Mule->>Mule: Stage Invalidation Paths (/p/{sku}, /c/{cat})
                end
            end
        end
        opt Full Extract Run
            Mule->>DB: Find active products missing from current run
            Mule->>DB: UPDATE product_status = 'DELISTED' (Never DELETE)
        end
        loop For Each Batch of 30 Invalidation Paths
            Mule->>CDN: POST /invalidations (Max 30 paths)
            alt 429 Too Many Requests
                Mule->>Mule: Read Retry-After & Exponential Backoff
                Mule->>CDN: Retry Request (Until Successful)
            else 202 Accepted
                Mule->>DB: INSERT cdn_invalidations (confirmed = true)
            else 207 Multi-Status
                Mule->>DB: INSERT cdn_invalidations (confirmed = false, alert)
            end
        end
        Mule->>DB: UPDATE catalog_import_runs (Status: COMPLETED, final counts)
        Mule->>Mule: Move file to data/archive
    end
```

---

## 4. Delta Classification Matrix

| Existing in DB? | Hash Matches Stored? | Changed Fields | Price Swing Normal? | Resulting Classification | DB Action | CDN Invalidation? |
| :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| **No** | N/A | All | N/A | `NEW` | `INSERT` | **Yes** |
| **Yes** | **Yes** | None | N/A | `UNCHANGED` | **None** (Untouched) | **No** |
| **Yes** | **No** | `taxClass`, `categoryCode`, `brand` | Yes | `CHANGED_INTERNAL_ONLY` | `UPDATE` | **No** |
| **Yes** | **No** | `productName`, `price`, `stockStatus`, `imagePath` | Yes | `CHANGED_CUSTOMER_FACING` | `UPDATE` | **Yes** |
| **Yes** | **No** | `price` | **No** (+60% or -90%) | `HOLD_FOR_REVIEW` | `UPDATE review_hold` | **No** |
| **Yes (Active)** | N/A (Missing from Full File) | N/A | N/A | `DELISTED` | `UPDATE status` | **Yes** |

---

## 5. Security & Production Best Practices

1. **Auto-Discovery & API Gateway**: Managed via Anypoint API Manager using `api-gateway:autodiscovery` with standard Client ID Enforcement and Rate Limiting SLA tiers.
2. **Secure Credentials**: Sensitive credentials (`cdn.api.token`, DB credentials) protected via Mule Secure Configuration Properties (`mule-artifact.json`).
3. **Resilience & Transaction Independence**: CDN outages never roll back successfully committed database catalog changes. Pending invalidations are persisted and retried asynchronously.
4. **Structured JSON Logging**: Every transaction is logged with `correlationId`, `runId`, and timestamp for automated ingestion into Splunk/ELK.
