# API Policies — Retail Catalog Update PAPI
## Anypoint API Manager Configuration Guide

These policies must be applied via **Anypoint API Manager** before CloudHub deployment.
They cannot be configured in code — they are enforced by the API Gateway at the platform level.

---

## Step 1: Register the API in API Manager

1. Log in to [Anypoint Platform](https://anypoint.mulesoft.com)
2. Go to **API Manager → Manage API → Create new API**
3. Set:
   - **API Name:** `retail-catalog-update-papi`
   - **Asset Type:** RAML
   - **RAML:** Upload `src/main/resources/api/retail-catalog-papi.raml`
   - **Environment:** Sandbox (dev) / Production
4. Copy the **API ID** from the overview page
5. Update `src/main/resources/config/config-dev.yaml`:
   ```yaml
   api:
     id: "<your-real-api-manager-id>"
   ```

---

## Step 2: Apply These Policies

### Policy 1: Client ID Enforcement (Security — Required)
**Purpose:** Validates that every API request carries a registered client_id and client_secret.

| Setting | Value |
|---------|-------|
| Policy | Client ID Enforcement |
| Client ID Expression | `#[attributes.headers['client_id']]` |
| Client Secret Expression | `#[attributes.headers['client_secret']]` |
| HTTP Basic Auth Header | Disabled |

**How to apply:**
1. API Manager → your API → Policies → Apply New Policy
2. Select **Client ID Enforcement**
3. Set the expressions above
4. Save

### Policy 2: Rate Limiting SLA Based (Performance — Required)
**Purpose:** Limits the number of requests per client to prevent abuse and protect downstream systems.

| Tier | Requests per Period | Period | Throughput |
|------|---------------------|--------|------------|
| Basic | 60 | 1 minute | Standard catalog syncs |
| Premium | 300 | 1 minute | Bulk operations |

**How to apply:**
1. API Manager → your API → SLA Tiers → Add Tier → set values above
2. API Manager → Policies → Apply New Policy
3. Select **Rate Limiting - SLA Based**
4. Set `#[attributes.headers['client_id']]` as the identifier

### Policy 3: HTTP Caching (Performance — Optional)
**Purpose:** Cache GET /catalog/products and GET /catalog/runs responses to reduce DB load.

| Setting | Value |
|---------|-------|
| TTL | 60 seconds |
| Cache Key | `#[attributes.requestPath]` |
| Invalidate on POST | Enabled |

### Policy 4: IP Whitelist (Security — Production)
**Purpose:** Restrict catalog ingestion trigger to known internal IP ranges.

Apply to `POST /catalog/trigger` only.

---

## Step 3: Register Client Applications

For each system that calls the API (PMS, monitoring dashboards):
1. Anypoint Exchange → Request Access → choose this API
2. Note the auto-generated `client_id` and `client_secret`
3. Configure the calling system to send these in headers

---

## Verification

After applying policies, test with:

```bash
# Should succeed (with valid credentials)
curl -X POST http://localhost:8081/api/v1/catalog/trigger \
  -H "client_id: your-client-id" \
  -H "client_secret: your-client-secret" \
  -H "Content-Type: text/csv" \
  --data-binary @data/input/CATALOG_FULL_20260911_0600.csv

# Should fail with 401 (no credentials)
curl -X POST http://localhost:8081/api/v1/catalog/trigger \
  -H "Content-Type: text/csv" \
  --data-binary @data/input/CATALOG_FULL_20260911_0600.csv
```
