# Manual checks for Financial Engine v2

These are intentionally written without code first. If Swift disagrees with these calculations, the Swift implementation is wrong or an assumption changed.

## Check 1 — original $1,250 checkpoint

Inputs:

- current cash = $8,000
- personal reserve = $7,000
- institutional minimum = $0
- safety buffer = $250
- future income = $1,000
- committed expenses = $500
- projected normal variable spending = $0 for this controlled test
- mandatory goals = $0

Calculation:

1. Projected cash = 8,000 + 1,000 - 500 = **$8,500**
2. Hard floor = max(7,000, 0) = **$7,000**
3. Hard headroom = 8,500 - 7,000 = **$1,500**
4. Recommended headroom = 1,500 - 250 = **$1,250**

Expected safe discretionary cash = **$1,250**.

---

## Check 2 — reserve releases later

Inputs:

- current cash = $9,000
- personal reserve until Feb 28 = $8,800
- personal reserve from Mar 1 = $8,500
- no institutional minimum
- no safety buffer for this controlled test
- proposed purchase = $300

Before Mar 1:

1. Hard headroom = 9,000 - 8,800 = **$200**
2. After a $300 purchase = 200 - 300 = **-$100**
3. Result = **NOT_SAFE**

From Mar 1:

1. Hard headroom = 9,000 - 8,500 = **$500**
2. After a $300 purchase = 500 - 300 = **$200**
3. Result = **SAFE**

Expected earliest safe date = **Mar 1**.

---

## Check 3 — bank minimum creates a TIGHT zone

Inputs:

- current cash = $900
- personal reserve = $0
- bank minimum = $500
- safety buffer = $200

Baseline:

1. Hard floor = max(0, 500) = **$500**
2. Hard headroom = 900 - 500 = **$400**
3. Recommended headroom = 400 - 200 = **$200**

If purchase = $300:

- hard headroom after purchase = 400 - 300 = **$100**
- recommended headroom after purchase = 200 - 300 = **-$100**
- Result = **TIGHT**

The user does not violate the bank rule, but consumes the recommended cushion.

If purchase = $450:

- hard headroom after purchase = 400 - 450 = **-$50**
- Result = **NOT_SAFE**

The purchase would leave only $450 in the account and violate the $500 minimum.

---

## Check 4 — reimbursement can create a temporary problem

Inputs:

- current cash = $1,000
- personal reserve = $500
- safety buffer = $100
- Sep 10 reimbursable purchase = -$300
- Sep 20 reimbursement = +$300

Sep 15:

1. Projected cash = 1,000 - 300 = **$700**
2. Hard headroom = 700 - 500 = **$200**
3. Recommended headroom = 200 - 100 = **$100**

After Sep 20:

1. Projected cash = 1,000 - 300 + 300 = **$1,000**
2. Hard headroom = 1,000 - 500 = **$500**
3. Recommended headroom = 500 - 100 = **$400**

The future reimbursement does not erase the fact that liquidity was tighter between Sep 10 and Sep 20. This is why the engine checks the full trajectory.

---

## Check 5 — median-based spending buffer

Recent eligible weekly variable spending:

`$80, $95, $87, $92, $410, $90`

Sorted:

`$80, $87, $90, $92, $95, $410`

Median for an even number of values is the average of the two middle values:

`(90 + 92) / 2 = $91`

With a 2-week safety policy:

`SafetyBuffer = 91 * 2 = $182`

The $410 week does not dominate the estimate the way it would under a simple arithmetic mean.
