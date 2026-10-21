/**
 * compute-hash.dwl
 * Computes a deterministic content fingerprint over the 10 business-relevant
 * fields. Returns the first 64 characters to fit the content_hash column.
 */
%dw 2.0
output application/java
var full = (payload.productName      default "") ++ "|" ++
           (payload.categoryCode     default "") ++ "|" ++
           (payload.brand            default "") ++ "|" ++
           ((((payload.price as Number) default 0) as String {format: "0.00"}) default "0.00") ++ "|" ++
           (payload.currency         default "") ++ "|" ++
           (payload.taxClass         default "") ++ "|" ++
           (payload.stockStatus      default "") ++ "|" ++
           (payload.productStatus    default "") ++ "|" ++
           (payload.shortDescription default "") ++ "|" ++
           (payload.imagePath        default "")
---
full[0 to 63]
