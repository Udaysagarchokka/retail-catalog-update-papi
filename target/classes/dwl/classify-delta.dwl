/**
 * classify-delta.dwl
 * Classifies an incoming product record as:
 *   NEW | UNCHANGED | CHANGED_CUSTOMER_FACING | CHANGED_INTERNAL_ONLY
 * Called from: catalog-processing-flow.xml — DeltaClassificationStep
 *
 * Input:
 *   payload       = incoming CSV record Object
 *   vars.storedProduct   = existing DB row or null
 *   vars.computedHash    = SHA-256 of incoming record (from compute-hash.dwl)
 *
 * Output: {
 *   classification: String,
 *   customerFacingChanged: Boolean,
 *   diffs: Array<{ fieldName, oldValue, newValue, customerFacing }>
 * }
 */
%dw 2.0
output application/java

var stored   = vars.storedProduct
var incoming = payload

// Customer-facing fields → trigger CDN invalidation on change
var customerFacingList = ["productName", "price", "stockStatus", "productStatus", "shortDescription", "imagePath"]

// Internal-only fields → update DB only, no CDN
var internalOnlyList = ["taxClass", "categoryCode", "brand"]

fun formatPrice(val) =
    if (isEmpty(val)) "0.00"
    else ((val as Number) as String {format: "0.00"})

var diffs = if (isEmpty(stored)) [] else [
    if ((incoming.productName    default "") != (stored.product_name    default ""))
        { fieldName: "productName",    oldValue: stored.product_name,    newValue: incoming.productName,    customerFacing: true  } else null,
    if (formatPrice(incoming.price) != formatPrice(stored.price as String))
        { fieldName: "price",          oldValue: stored.price as String, newValue: incoming.price as String, customerFacing: true  } else null,
    if ((incoming.stockStatus    default "") != (stored.stock_status    default ""))
        { fieldName: "stockStatus",    oldValue: stored.stock_status,    newValue: incoming.stockStatus,    customerFacing: true  } else null,
    if ((incoming.productStatus  default "") != (stored.product_status  default ""))
        { fieldName: "productStatus",  oldValue: stored.product_status,  newValue: incoming.productStatus,  customerFacing: true  } else null,
    if ((incoming.shortDescription default "") != (stored.short_description default ""))
        { fieldName: "shortDescription", oldValue: stored.short_description, newValue: incoming.shortDescription, customerFacing: true  } else null,
    if ((incoming.imagePath      default "") != (stored.image_path     default ""))
        { fieldName: "imagePath",      oldValue: stored.image_path,      newValue: incoming.imagePath,      customerFacing: true  } else null,
    if ((incoming.categoryCode   default "") != (stored.category_code  default ""))
        { fieldName: "categoryCode",   oldValue: stored.category_code,   newValue: incoming.categoryCode,   customerFacing: false } else null,
    if ((incoming.brand          default "") != (stored.brand          default ""))
        { fieldName: "brand",          oldValue: stored.brand,           newValue: incoming.brand,           customerFacing: false } else null,
    if ((incoming.taxClass       default "") != (stored.tax_class      default ""))
        { fieldName: "taxClass",       oldValue: stored.tax_class,       newValue: incoming.taxClass,        customerFacing: false } else null,
    if ((incoming.currency       default "") != (stored.currency       default ""))
        { fieldName: "currency",       oldValue: stored.currency,        newValue: incoming.currency,        customerFacing: false } else null
] filter (!isEmpty($))

var hasCustomerFacingDiff = !isEmpty(diffs filter ($.customerFacing == true))

---
if (isEmpty(stored))
    {
        classification:         "NEW",
        customerFacingChanged:  true,
        diffs: [{ fieldName: "ALL", oldValue: null, newValue: "NEW_RECORD", customerFacing: true }]
    }
else if (stored.content_hash == vars.computedHash)
    {
        classification:         "UNCHANGED",
        customerFacingChanged:  false,
        diffs: []
    }
else if (hasCustomerFacingDiff)
    {
        classification:         "CHANGED_CUSTOMER_FACING",
        customerFacingChanged:  true,
        diffs: diffs
    }
else
    {
        classification:         "CHANGED_INTERNAL_ONLY",
        customerFacingChanged:  false,
        diffs: diffs
    }
