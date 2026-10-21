/**
 * price-guard-check.dwl
 * Evaluates whether a price change exceeds the configured thresholds.
 * Called from: catalog-processing-flow.xml — PriceGuardStep
 *
 * Input:
 *   payload               = incoming CSV record
 *   vars.storedProduct    = existing DB row (must have .price)
 *   p('priceGuard.maxIncreasePercent') = max % increase allowed (default 50)
 *   p('priceGuard.maxDecreasePercent') = max % decrease allowed (default 40)
 *
 * Output: {
 *   isSuspicious: Boolean,
 *   reason:       String,
 *   increasePct:  Number,
 *   decreasePct:  Number,
 *   action:       "HOLD_FOR_REVIEW" | "APPLY"
 * }
 */
%dw 2.0
output application/java

var oldPrice     = (vars.storedProduct.price as Number) default 0
var newPrice     = (payload.price as Number) default 0
var maxIncrease  = (p('priceGuard.maxIncreasePercent') default "50") as Number
var maxDecrease  = (p('priceGuard.maxDecreasePercent') default "40") as Number

var increasePct  = if (oldPrice > 0 and newPrice > oldPrice) ((newPrice - oldPrice) / oldPrice) * 100 else 0
var decreasePct  = if (oldPrice > 0 and newPrice < oldPrice) ((oldPrice - newPrice) / oldPrice) * 100 else 0

var isSuspicious = (oldPrice > 0) and (increasePct > maxIncrease or decreasePct > maxDecrease)

var reasonMsg    = if (increasePct > maxIncrease)
                       "Price increase of " ++ (increasePct as String {format: "0.0"}) ++ "% exceeds max allowed " ++ (maxIncrease as String) ++ "%"
                   else if (decreasePct > maxDecrease)
                       "Price decrease of " ++ (decreasePct as String {format: "0.0"}) ++ "% exceeds max allowed " ++ (maxDecrease as String) ++ "% (suspected decimal error)"
                   else ""

---
{
    isSuspicious: isSuspicious,
    reason:       reasonMsg,
    increasePct:  increasePct,
    decreasePct:  decreasePct,
    action:       if (isSuspicious) (p('priceGuard.action') default "HOLD_FOR_REVIEW") else "APPLY"
}
