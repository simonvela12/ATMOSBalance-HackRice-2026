# FinancialCore

Standalone Swift Package containing the hackathon's financial math engine.

## What Simon can do with this

Open the `FinancialCore` folder as a Swift Package in Xcode, or from a terminal run:

```bash
cd FinancialCore
swift test
swift run FinancialCoreDemo
```

The package exposes a library called `FinancialCore` that can later be added to the iOS project.

```swift
import FinancialCore

let forecast = try FinancialEngine.forecast(
    profile: profile,
    targetDate: targetDate
)

let dashboard = try FinancialInsights.dashboard(
    profile: profile,
    through: horizon
)

let timeline = try FinancialInsights.cashFlowTimeline(
    profile: profile,
    from: profile.asOfDate,
    through: horizon
)

let explainedPurchase = try FinancialInsights.assessAndExplainPurchase(
    profile: profile,
    amount: 450,
    purchaseDate: purchaseDate,
    planningHorizon: horizon
)

let goals = try FinancialInsights.assessAllGoals(
    profile: profile,
    planningHorizon: horizon
)

let whatIf = try FinancialInsights.analyzePurchaseWhatIf(
    profile: profile,
    amount: 450,
    purchaseDate: purchaseDate,
    planningHorizon: horizon
)

let diagnostics = FinancialProfileDiagnostics.report(
    profile: profile,
    planningHorizon: horizon
)

let goalPortfolio = try SmartGoalEngine.evaluate(
    profile: profile,
    planningHorizon: horizon
)
```

## Core outputs

- projected cash on a future date
- hard and recommended headroom
- path-safe discretionary spending
- SAFE / TIGHT / NOT_SAFE purchase assessment
- current health and full-horizon health
- tightest future date
- shortfall to hard/recommended floors
- earliest fully safe purchase date
- mandatory/flexible goal health
- goal-aware purchase trade-offs (for example, a purchase moving a goal from SAFE to TIGHT)
- CONSERVATIVE / EXPECTED / OPTIMISTIC deterministic scenarios
- daily cash-flow points for a SwiftUI calendar/chart
- recommended weekly spending limit
- deterministic purchase reason codes for UI explanations
- profile diagnostics for malformed or weak upstream data
- dynamic Goal health, projected completion, required savings, portfolio conflicts,
  priority/flexibility allocation, and goal-aware Safe-to-Spend

## Smart Goals

`SmartGoalEngine` consumes the same normalized `FinancialProfile` and forecast as
the rest of the package. It does not import Nessie or SwiftUI and does not persist
derived values. `GoalHealth` is recalculated from cash, dated income and expenses,
historical variable spending, reserves, deadlines, priority and flexibility.

Use `SmartGoalEngine.impact(of:on:)` for a normalized transaction or an aggregate
day. Positive movements model unexpected income and negative movements model
unexpected spending. The numeric impact contract is intentionally separate from
user-facing copy.

## Core inputs

`FinancialProfile` contains:

- current cash
- as-of date
- personal reserve schedule
- institutional minimum-balance constraints
- normalized income events
- committed expense events
- mandatory/flexible goals
- recent weekly variable-spending history
- spending/safety-buffer policy

## Important distinction

`forecast(...).recommendedHeadroom` is the headroom **on the target date**.

`safeToSpend(profile:from:through:)` is the amount that can be spent while remaining above the recommended floor **at every point in the path**.

These can be different. For the original $8,000 example, target-date headroom on Nov 30 is $1,250, but if the $1,000 income does not arrive until November, the amount safely spendable today can be lower. The engine intentionally preserves that chronology.

## Dashboard / visual UI support

`FinancialInsights.dashboard(...)` is intended as a thin home-screen contract. It returns:

- current `SAFE / TIGHT / NOT_SAFE`
- full-horizon `SAFE / TIGHT / NOT_SAFE`
- path-safe money available now
- typical weekly spending
- additional weekly capacity
- recommended weekly spending limit
- minimum future headroom
- tightest future date

`FinancialInsights.cashFlowTimeline(...)` returns one `CashFlowPoint` per day containing projected cash, hard floor, recommended floor, headroom, and health status. SwiftUI can use those points directly for a financial-health calendar or line graph without reimplementing the math.

## Purchase explanations

`FinancialInsights.assessAndExplainPurchase(...)` returns the normal numeric assessment plus structured explanation context.

Reason codes currently include:

- preserves recommended buffer
- uses safety buffer
- violates personal reserve
- violates institutional minimum
- violates multiple hard constraints

The UI can turn those deterministic outputs into plain-language copy. The math engine does not ask an LLM to invent affordability reasoning.

## Goal planning and What-If trade-offs

`FinancialInsights.assessAllGoals(...)` evaluates every goal using the same liquidity model as the rest of the engine.

- mandatory goals are already included in the baseline and report whether the cash path can support them;
- flexible goals are evaluated as explicit What-If decisions;
- overdue unpaid mandatory goals remain immediately due;
- overdue flexible goals are assessed as decisions the user can make today.

`FinancialInsights.analyzePurchaseWhatIf(...)` inserts a hypothetical purchase into a copy of the profile, re-runs every goal, and reports which goals worsen. This is designed for product copy such as:

> F1 is technically possible, but it moves Miami from SAFE to TIGHT.

The comparison is deterministic and based on the same cash-path rules as the purchase assessment.

## Recurring cash flows

One `IncomeEvent` or `ExpenseEvent` is one dated cash movement. A qualitative label saying that something is recurring does **not** automatically create future occurrences.

The normalization layer can materialize weekly, biweekly, or monthly events with `FinancialScheduleBuilder`:

```swift
let paychecks = try FinancialScheduleBuilder.recurringIncome(
    amount: 450,
    firstDate: nextPayday,
    through: horizon,
    source: "Campus job",
    cadence: .biweekly
)

let subscriptions = try FinancialScheduleBuilder.recurringExpense(
    amount: 25,
    firstDate: nextSubscriptionDate,
    through: horizon,
    category: "Subscription",
    cadence: .monthly,
    essential: false,
    committed: true
)
```

This is intentionally separate from the math engine: Simon's qualitative layer decides that a pattern repeats, then the schedule helper converts that meaning into dated events.

See `QUALITATIVE_MAPPING.md` for the full mapping contract.

## Profile diagnostics

Before showing an affordability decision, the app can inspect the normalized profile:

```swift
let diagnostics = FinancialProfileDiagnostics.report(
    profile: profile,
    planningHorizon: horizon
)

if diagnostics.isReadyForForecast {
    // Present deterministic engine outputs.
}
```

Diagnostics surface issues such as:

- negative or malformed normalized cash-flow amounts
- irregular-income confidence outside `0...1`
- duplicate reserve dates
- invalid institutional-minimum ranges
- missing or sparse recent spending history
- overdue goals
- long planning horizons that should be treated as rolling forecasts

Warnings expose assumptions but do not block the engine. Errors indicate malformed upstream data that should be fixed before presenting a financial recommendation.

## Current MVP assumptions

- past transactions are already reflected in current cash
- irregular income uses `amount × confidence` in the expected scenario
- conservative scenario counts no irregular income; optimistic counts the explicitly-entered irregular amount in full
- normal variable spending uses the median of recent eligible weekly history
- only the configured lookback window is used (default 6 weeks)
- reimbursable/extraordinary spending should be excluded upstream from weekly baseline samples
- reimbursements are represented as an expense followed by a future one-time income event
- mandatory goals are baseline cash obligations; overdue unpaid mandatory goals remain immediately due rather than disappearing
- flexible goals are What-If scenarios; an overdue flexible goal can still be assessed as a decision today
- hard floor is `max(personal reserve, aggregate institutional minimum)`
- safety buffer is recommended headroom, not a hard constraint

## Planning-horizon guidance

The engine can mathematically evaluate long horizons, but normal-spending history should not be presented as a precise multi-year prediction. The intended product behavior is a **rolling forecast**: re-run the engine as new transactions, goals, income expectations, and qualitative context arrive.

Long-term commitments can still be represented through reserve schedules and dated goals. Operational safe-to-spend recommendations should use a horizon for which the app has meaningful inputs rather than pretending six weeks of history perfectly predicts four years.

`FinancialProfileDiagnostics.report(...)` uses a configurable operational-horizon warning threshold (default 180 days). It warns; it does not block longer forecasts.

## Validation status

The package is continuously validated by GitHub Actions on macOS.

Latest validated milestone after adding dashboard, timeline, purchase explanations, adaptive goal health, goal-aware What-If analysis, recurring schedule helpers, and profile diagnostics:

- Apple Swift 6.3.3 on macOS runner
- `40` XCTest tests
- `0` failures
- `FinancialCoreDemo` builds and runs successfully

Simon also independently opened the package in Xcode and confirmed build/test success before the later insight additions. Re-run `swift test` after pulling the latest branch before iOS integration.

This is a deterministic hackathon MVP, not a production financial-advice system.
