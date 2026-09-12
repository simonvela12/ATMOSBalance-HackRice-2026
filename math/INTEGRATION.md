# Financial Engine Integration Contract — v2

This is the handoff between the qualitative/banking pipeline, the math engine, and the iOS UI.

The engine itself does **not** parse natural language, classify merchants, call APIs, or render UI. It receives normalized financial inputs and returns deterministic numbers/statuses.

## Upstream -> math engine

The upstream layer should provide a `FinancialProfileV2` containing:

- `currentCash`
- `asOfDate`
- `personalReserveSteps`
- `institutionalMinimums`
- `incomeEvents`
- `expenseEvents`
- `goals`
- `weeklySpendingHistory`
- `safetyBufferPolicy`

### Important qualitative workflow

If the app infers a recurring/irregular income pattern, reserve schedule, reimbursement, or special future expense from conversation/history, it should ask the user to confirm the interpretation before creating the normalized math input.

Example:

User says:

> I need about $8,800 available until March, then I can release around $300.

Upstream representation:

- reserve step at current date -> `$8,800`
- reserve step Mar 1 -> `$8,500`

The math engine never needs the original sentence.

---

## Core v2 calls

The primary functions are:

1. `forecast(profile, targetDate)`
2. `minimumHeadroom(profile, from, through)`
3. `safeToSpend(profile, from, through)`
4. `assessPurchase(profile, amount, purchaseDate, planningHorizon)`
5. `earliestSafePurchaseDate(profile, amount, startDate, planningHorizon)`
6. `assessFlexibleGoal(profile, goal, planningHorizon)`

---

## Forecast output

`ForecastResultV2` returns:

- expected income
- committed expenses
- projected normal variable spending
- mandatory goal payments
- projected cash
- personal reserve
- institutional minimum
- hard floor
- safety buffer
- hard headroom
- recommended headroom

Definitions:

`hardFloor = max(personalReserve, institutionalMinimum)`

`hardHeadroom = projectedCash - hardFloor`

`recommendedHeadroom = hardHeadroom - safetyBuffer`

---

## Purchase output

`PurchaseAssessmentV2` returns one of:

- `SAFE`: preserves the recommended buffer through the full horizon
- `TIGHT`: preserves hard constraints but consumes some/all recommended buffer
- `NOT_SAFE`: violates a personal/institutional hard floor somewhere in the horizon

It also returns:

- minimum hard/recommended headroom before purchase
- minimum hard/recommended headroom after purchase
- shortfall to hard floor
- shortfall to recommended floor
- earliest fully safe date when available

The UI should explain the numeric trade-off rather than presenting a paternalistic yes/no.

---

## Spending-history contract

The math engine expects weekly variable-spending totals that have already excluded:

- reimbursable purchases
- extraordinary/one-off purchases
- fixed committed bills represented separately

The engine takes the median of eligible weeks to estimate `typicalWeeklySpending`.

Known future unusual spending — special dinner, trip, ticket, etc. — should be passed as an explicit future expense/What-If event instead of contaminating the normal baseline.

---

## Reimbursement contract

A reimbursement is represented as two cash events:

1. the original expense on the date cash leaves;
2. the expected reimbursement as a future one-time income event.

This preserves the temporary liquidity dip.

Historical reimbursable purchases should not feed the normal-spending baseline.

---

## Goal contract

Goal priorities:

- `mandatory`: included in the baseline cash trajectory on the deadline;
- `flexible`: assessed separately as a What-If/trade-off.

`amountAlreadyPaid` means money that has actually left the account already. Money merely earmarked inside the current bank balance is not treated as already paid.

This design removes the old `alreadyProtected` double-counting ambiguity.

---

## Rules that must remain true

- Past transactions are never added again if already reflected in current cash.
- Past one-time income is never projected forward.
- Irregular future income uses `amount * confidence` in the deterministic MVP.
- A later reimbursement/income cannot hide an earlier liquidity shortfall; the full path matters.
- Personal reserve requirements can rise or fall over time.
- Institutional minimums are hard constraints.
- Safety buffer is recommended headroom, not a hard institutional constraint.
- Optional purchases are evaluated as scenarios rather than silently inserted into baseline expenses.
- Flexible goals are trade-offs, not hard obligations.
- Negative headroom is preserved internally because it communicates the size of a shortfall.

---

## Current source of truth

- mathematical specification: `MODEL_V2.md`
- Swift reference implementation: `FinancialEngineV2.swift`
- executable Swift tests: `FinancialEngineV2Tests.swift`
- human-readable scenarios: `test_cases_v2.csv`

The older v1 files remain temporarily for comparison while v2 is validated in Xcode. Once v2 passes on the iOS project, v1 can be removed or archived.
