/**
 * map-history-records.dwl
 * Maps a list of field diffs into product_change_history row objects.
 * Called from: catalog-persistence-flow.xml — CHANGED_* branch
 *
 * Input:
 *   payload                          = Array of diff objects from classify-delta.dwl
 *   vars.runId                       = current run identifier
 *   vars.currentRecord.sku           = SKU being processed
 *   vars.deltaClassification.classification = CHANGED_CUSTOMER_FACING | CHANGED_INTERNAL_ONLY
 *
 * Output: Array of history row Objects ready for DB bulk insert
 */
%dw 2.0
output application/java

var runId      = vars.runId default "RUN-DEFAULT"
var sku        = vars.currentRecord.sku default "UNKNOWN"
var changeType = vars.deltaClassification.classification default "CHANGED"

---
payload map ((diff) -> {
    run_id:          runId,
    sku:             sku,
    change_type:     changeType,
    field_name:      diff.fieldName,
    old_value:       if (diff.oldValue != null) (diff.oldValue as String) else null,
    new_value:       if (diff.newValue != null) (diff.newValue as String) else null,
    customer_facing: diff.customerFacing default false
})
