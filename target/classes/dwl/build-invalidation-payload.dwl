/**
 * build-invalidation-payload.dwl
 * Builds the CDN invalidation HTTP request body.
 * Called from: cdn-invalidation-flow.xml — dispatch-cdn-invalidation-batch-subflow
 *
 * Input:
 *   vars.currentBatchPaths  = Array<String> of CDN paths for this batch
 *   vars.runId              = current run identifier
 *   vars.currentBatchNumber = batch sequence number (Integer)
 *
 * Output: CDN invalidation request Object (serialised as application/json by HTTP requestor)
 */
%dw 2.0
output application/json

var distId   = p('cdn.distributionId') default "DIST-RETAIL-PRD-01"
var batchRef = (vars.runId default "CATALOG-RUN") ++ "-B" ++ ((vars.currentBatchNumber default 1) as String)

---
{
    distributionId: distId,
    reference:      batchRef,
    paths:          vars.currentBatchPaths default []
}
