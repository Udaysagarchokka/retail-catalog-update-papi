/**
 * validate-record.dwl
 * Validates a single product record from the CSV.
 * Called from: catalog-processing-flow.xml — ValidationStep
 *
 * Input:  payload = one CSV row as Object
 * Output: { isValid: Boolean, errors: Array<String> }
 */
%dw 2.0
output application/java

var skuValid           = !isEmpty(payload.sku)
var nameValid          = !isEmpty(payload.productName)
var priceNum           = (payload.price as Number) default -1
var priceValid         = priceNum > 0
var currencyValid      = !isEmpty(payload.currency) and sizeOf(trim(payload.currency)) == 3
var categoryValid      = !isEmpty(payload.categoryCode) and (payload.categoryCode startsWith "CAT-")
var stockStatusValid   = ["IN_STOCK", "OUT_OF_STOCK", "PRE_ORDER"] contains (payload.stockStatus default "")
var productStatusValid = ["ACTIVE", "DISCONTINUED", "INACTIVE", "DELISTED"] contains (payload.productStatus default "")
var imageValid         = !isEmpty(payload.imagePath) and (payload.imagePath startsWith "/img/")

var errors = []
    ++ (if (!skuValid)           ["Missing or empty SKU"] else [])
    ++ (if (!nameValid)          ["Missing or empty product name"] else [])
    ++ (if (!priceValid)         ["Price must be positive and non-zero: " ++ (payload.price default "null")] else [])
    ++ (if (!currencyValid)      ["Currency must be a valid 3-letter code: " ++ (payload.currency default "null")] else [])
    ++ (if (!categoryValid)      ["Invalid category code (must start with CAT-): " ++ (payload.categoryCode default "null")] else [])
    ++ (if (!stockStatusValid)   ["Unsupported stockStatus: " ++ (payload.stockStatus default "null")] else [])
    ++ (if (!productStatusValid) ["Unsupported productStatus: " ++ (payload.productStatus default "null")] else [])
    ++ (if (!imageValid)         ["Malformed imagePath (must start with /img/): " ++ (payload.imagePath default "null")] else [])

---
{
    isValid: isEmpty(errors),
    errors:  errors
}
