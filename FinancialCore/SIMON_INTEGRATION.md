# Simon integration guide — FinancialCore

This is the shortest handoff for wiring the math package into the iOS app. Keep SwiftUI thin: build a `FinancialProfile`, call the engine, render the result.

## 1. Home screen

Use:

```swift
let dashboard = try FinancialInsights.dashboard(
    profile: profile,
    through: planningHorizon
)
```

Recommended UI mapping:

- large “safe to spend” number -> `dashboard.safeToSpendNow`
- current badge -> `dashboard.currentStatus`
- future-plan badge -> `dashboard.horizonStatus`
- weekly recommendation -> `dashboard.recommendedWeeklySpendingLimit`
- warning date -> `dashboard.tightestDate`

Important: `currentStatus` and `horizonStatus` can differ. A student can be safe today but have a future shortfall.

## 2. Financial-health calendar / graph

Use:

```swift
let points = try FinancialInsights.cashFlowTimeline(
    profile: profile,
    from: profile.asOfDate,
    through: planningHorizon
)
```

Each `CashFlowPoint` already has:

- date
- projected cash
- hard floor
- recommended floor
- hard/recommended headroom
- SAFE / TIGHT / NOT_SAFE

Do not duplicate these calculations in SwiftUI.

## 3. What-If purchase

Use:

```swift
let result = try FinancialInsights.assessAndExplainPurchase(
    profile: profile,
    amount: purchaseAmount,
    purchaseDate: purchaseDate,
    planningHorizon: planningHorizon
)
```

Render:

- status -> `result.assessment.status`
- shortfall -> hard/recommended shortfall
- limiting date -> `result.explanation.limitingDate`
- earliest fully safe date -> `result.assessment.recommendedDate`
- explanation source -> `result.explanation.reason`

Reason codes are deterministic. UI copy can be friendly, but do not recalculate affordability in the view.

## 4. What-If purchase versus goals

Use:

```swift
let analysis = try FinancialInsights.analyzePurchaseWhatIf(
    profile: profile,
    amount: purchaseAmount,
    purchaseDate: purchaseDate,
    planningHorizon: planningHorizon
)
```

Most useful UI field:

```swift
analysis.worsenedGoals
```

Each impact has `before.status` and `after.status`. This directly supports copy such as:

> This purchase keeps your account above the hard minimum, but moves Miami from SAFE to TIGHT.

This is probably the strongest What-If demo path for judging.

## 5. Goals screen

Use:

```swift
let goals = try FinancialInsights.assessAllGoals(
    profile: profile,
    planningHorizon: planningHorizon
)
```

For each goal render:

- `status`
- `remainingAmount`
- `effectiveDeadline`
- `shortfallToHardFloor`
- `shortfallToRecommendedFloor`
- `recommendedDate` for flexible goals when available

Mandatory goals are baseline obligations; flexible goals are scenario decisions.

## 6. Conservative / expected / optimistic views

Use when the UI wants to communicate uncertainty explicitly:

```swift
let scenarios = try FinancialScenarioEngine.assessPurchaseAll(
    profile: profile,
    amount: purchaseAmount,
    purchaseDate: purchaseDate,
    planningHorizon: planningHorizon
)
```

Do not call these “probabilities.” They are deterministic sensitivity cases:

- conservative: higher recent spending + no reliance on irregular income
- expected: median spending + confidence-adjusted irregular income
- optimistic: lower recent spending + entered irregular income in full

## 7. Profile-building responsibilities

FinancialCore expects normalized inputs. The banking/qualitative layer should decide and confirm:

- what cash is currently available
- which future income events are recurring / irregular / one-time
- which expenses are committed
- which past expenses should be excluded from normal-spending history (reimbursements / extraordinary one-offs)
- personal reserve steps over time
- institutional minimum balances
- mandatory versus flexible goals

FinancialCore should not parse raw natural language or guess transaction meaning.

## 8. Minimal integration sequence

For the hackathon, integrate in this order:

1. build a `FinancialProfile` from demo/Nessie data;
2. show `dashboard.safeToSpendNow`;
3. render `cashFlowTimeline` in one visual;
4. wire one What-If purchase using `analyzePurchaseWhatIf`;
5. show the reason + affected goal + earliest safe date;
6. only then add scenario tabs/cards if there is time.

That sequence maximizes visible Finance-track value while keeping integration risk low.
