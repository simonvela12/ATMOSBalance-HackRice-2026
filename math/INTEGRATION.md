# Financial Engine Integration Contract

This file is the handoff between the math workstream and the iOS app.

## Swift should eventually receive

A financial profile containing:

- current cash balance
- protected cash
- safety buffer
- as-of date
- future/past income events
- future committed expenses
- goals

## Swift should expose four calls

1. `forecast(profile, targetDate)`
2. `safeToSpend(profile, targetDate)`
3. `assessPurchase(profile, amount, purchaseDate)`
4. `earliestSafePurchaseDate(profile, amount, startDate, endDate)`

## Minimum UI-facing outputs

### Forecast
- projected balance
- expected income
- committed expenses
- protected cash
- safety buffer
- mandatory goal reserve
- safe to spend

### Purchase assessment
- SAFE or WAIT
- amount
- safe-to-spend before purchase
- remaining discretionary cash after purchase
- shortfall if unsafe
- recommended date if one exists

## Important rules the Swift implementation must preserve

- Do not project past one-time income into the future.
- Past transactions must not be added again if already reflected in current balance.
- Irregular future income uses `amount * confidence` in v1.
- Protected cash is subtracted from spendable capacity, not from the bank-style projected balance.
- Do not subtract a goal twice if its money is already included in protected cash.
- Optional purchases should be assessed separately, not inserted into committed expenses and then subtracted again.
- Negative safe-to-spend values are valid internally and represent a shortfall.

The reference behavior lives in `prototype.py` and the examples in `test_cases.csv`.
