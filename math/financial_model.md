# Financial Engine v1

## Purpose

The app is for college students with irregular income. The engine should answer four practical questions:

1. How much money will I probably have by a future date?
2. How much can I safely spend without touching protected money or required goals?
3. Can I afford a planned purchase on a given date without breaking future obligations?
4. If not, what is the earliest date when the purchase becomes safe?

This first version is intentionally deterministic and explainable. It does **not** use machine learning or Monte Carlo simulation yet.

---

## Core principles

### 1. Balance is not the same as spendable money
A user may have $8,000 in the bank while $7,000 is reserved for tuition, rent, an emergency fund, or another commitment. The engine must not treat all cash as discretionary.

### 2. Historical income is not automatically future income
Income can be:
- `recurring`: expected on a schedule (campus job, stipend)
- `irregular`: may recur, but not reliably (tutoring, gigs)
- `oneTime`: exceptional and should not be projected into the future (family transfer, account closure)

A one-time payment that already happened is already reflected in current cash. It must **not** be added again as future income.

### 3. Goals and protected cash must not be double-counted
If $900 for Miami is already included inside `protectedCash`, do not subtract the same $900 again as separate goal funding.

Each goal must therefore have one of two funding states:
- `alreadyProtected = true`: its money is already included in protected cash
- `alreadyProtected = false`: the engine must reserve the still-unfunded amount before the goal deadline

### 4. A safe purchase must remain safe in the future
A purchase can look affordable today but make a later bill or goal impossible.

Therefore the engine must not only check the purchase date. It checks the full planning horizon and uses the tightest future point.

---

## Inputs

### FinancialProfile

- `currentCash: Double`
- `protectedCash: Double`
- `safetyBuffer: Double`
- `asOfDate: Date`
- `incomeEvents: [IncomeEvent]`
- `expenseEvents: [ExpenseEvent]`
- `goals: [Goal]`

### IncomeEvent

- `amount: Double`
- `date: Date`
- `source: String`
- `type: recurring | irregular | oneTime`
- `confidence: Double` in `[0,1]`

Rules for v1:
- past income never gets added to future cash because it is already contained in `currentCash`
- future `recurring` income is included at full amount
- future `irregular` income is multiplied by confidence
- future `oneTime` income is included only if it is explicitly entered as a known future payment; past one-time income is never extrapolated

### ExpenseEvent

- `amount: Double`
- `date: Date`
- `category: String`
- `essential: Bool`
- `committed: Bool`

For v1, all future committed expenses are subtracted from the forecast. Optional scenario purchases are passed separately to the assessment functions so they are not counted twice.

### Goal

- `name: String`
- `targetAmount: Double`
- `currentFundedAmount: Double`
- `deadline: Date`
- `priority: mandatory | flexible`
- `alreadyProtected: Bool`

For a mandatory goal that is not already protected:

`remainingGoalFunding = max(0, targetAmount - currentFundedAmount)`

Flexible goals do not make the user insolvent by themselves; they are reported as trade-offs, not hard constraints.

---

## Derived quantities

For a target date `T`:

### Expected future income

`expectedIncome(T) = sum(adjusted amount of future income events with date <= T)`

Adjustment:
- recurring: `amount`
- irregular: `amount * confidence`
- explicitly-known future one-time: `amount`

### Future committed expenses

`committedExpenses(T) = sum(expense.amount for future committed expenses with date <= T)`

### Mandatory unfunded goals

`mandatoryGoalReserve(T) = sum(remainingGoalFunding for mandatory goals with deadline <= T and alreadyProtected == false)`

### Projected cash balance

`projectedBalance(T) = currentCash + expectedIncome(T) - committedExpenses(T)`

This is a bank-style projected balance. It intentionally does not subtract protected cash because protected cash remains physically in the account.

### Safe discretionary cash

`safeToSpend(T) = projectedBalance(T) - protectedCash - safetyBuffer - mandatoryGoalReserve(T)`

The UI should generally display:

`max(0, safeToSpend(T))`

but the engine should preserve negative values internally because a negative result communicates a funding shortfall.

---

## Purchase assessment

For a proposed purchase `P` with amount `A`, purchase date `D`, and planning horizon `H`:

1. Compute `safeToSpend(T)` for every day from `D` through `H`.
2. Find the tightest future point:

`minimumSafeToSpend(D...H) = minimum safeToSpend across the horizon`

3. Compute:

`remainingAtTightestPoint = minimumSafeToSpend(D...H) - A`

4. Purchase is `SAFE` only when `remainingAtTightestPoint >= 0`.
5. Purchase is `WAIT` when `remainingAtTightestPoint < 0`.

This prevents a false positive where the user can technically pay for something today but doing so would later break a protected balance, bill, safety buffer, or mandatory goal.

Output:
- `status: SAFE | WAIT`
- `safeToSpendOnPurchaseDate`
- `minimumSafeToSpendThroughHorizon`
- `purchaseAmount`
- `remainingAtTightestPoint`
- `shortfall`
- `recommendedDate`

The explanation should be generated from the numeric result, not by an LLM inventing financial logic.

---

## Earliest safe purchase date

Given purchase amount `A`, search candidate dates from the desired purchase date through the planning horizon.

For each candidate date `D`:

`if minimumSafeToSpend(D...H) >= A: return D`

The first date satisfying the condition is the earliest safe date.

For v1, checking once per day is acceptable. A later optimized version can evaluate only dates on which cash flow changes.

---

## Important modeling rule for irregular income

Do **not** use raw average monthly income as the main forecast because one large exceptional transfer can distort it.

Example:

- January: $180 tutoring
- February: $220 tutoring
- March: $0
- April: $190 tutoring
- May: $1,500 family transfer marked `oneTime`

The $1,500 payment contributes to current cash if already received, but it contributes **$0** to inferred future monthly income.

A future irregular tutoring payment of $200 with confidence `0.60` contributes:

`$200 * 0.60 = $120 expected income`

This is intentionally conservative and explainable for the hackathon.

---

## Reference scenario

As-of date: September 12

- current cash: `$8,000`
- protected cash: `$7,000`
- safety buffer: `$250`
- future expected income before November 30: `$1,000`
- committed essential expenses before November 30: `$500`
- no additional unfunded mandatory goal inside this horizon

Then:

`projectedBalance = 8000 + 1000 - 500 = 8500`

`safeToSpend = 8500 - 7000 - 250 = 1250`

Expected result:

**$1,250 safe discretionary cash through November 30.**

If an F1 ticket costs `$450`, the purchase can only be marked `SAFE` if the tightest safe-to-spend point from the purchase date through the planning horizon remains at least `$450`.

---

## Brainstorming scenario: $9,500 / F1

Example inputs:
- current cash: `$9,500`
- protected cash: `$8,800`
- safety buffer: `$150`
- one-time friend repayment: `$200` on September 5
- future committed expenses: `$200 subscriptions + $150 miscellaneous`
- Miami goal: `$1,000` by November 26
- another goal: `$600` by October 25
- F1 purchase: `$450` desired September 15
- planning horizon: December 31

Important date rule: if the profile `asOfDate` is September 11, the September 5 payment is in the past. If it was received, it is already inside current cash; it is not counted again as future income.

If the `$8,800 protected cash` **already includes both goals**, then the goals use `alreadyProtected = true` and must not be subtracted again.

With no additional future income:

`projected balance at year end = 9500 - 350 = 9150`

`safe to spend at year end = 9150 - 8800 - 150 = 200`

On September 15, before later bills arrive, the user appears to have `$550` of free capacity. However the tightest future point is only `$200`.

Therefore a `$450` F1 ticket is:

`WAIT`, with a `$250` shortfall through the planning horizon.

This is exactly why purchase decisions must use the future horizon rather than only today's available money.

If the Miami and $600 goals are **not** already inside the protected `$8,800`, they must be reserved separately, making the shortfall larger. The UI should explicitly ask whether a goal is already funded/protected to avoid ambiguity and double-counting.

---

## v1 outputs required by the iOS app

The Swift implementation exposes equivalents of:

- `forecast(profile, targetDate)`
- `minimumSafeToSpend(profile, from, through)`
- `assessPurchase(profile, amount, purchaseDate, planningHorizon)`
- `earliestSafePurchaseDate(profile, amount, startDate, planningHorizon)`

### ForecastResult
- projectedBalance
- expectedIncome
- committedExpenses
- protectedCash
- safetyBuffer
- mandatoryGoalReserve
- safeToSpend

### PurchaseAssessment
- status
- purchaseAmount
- purchaseDate
- planningHorizon
- safeToSpendOnPurchaseDate
- minimumSafeToSpendThroughHorizon
- remainingAtTightestPoint
- shortfall
- recommendedDate

---

## Out of scope for v1

Do not add these until the deterministic engine passes all tests:
- machine learning
- stock/investment recommendations
- Monte Carlo simulation
- automatic merchant categorization
- LLM-based financial decisions
- optimization across many flexible goals

Those can become stretch features only after the core model is stable.
