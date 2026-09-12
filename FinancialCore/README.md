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

let purchase = try FinancialEngine.assessPurchase(
    profile: profile,
    amount: 450,
    purchaseDate: purchaseDate,
    planningHorizon: horizon
)
```

## Core outputs

- projected cash on a future date
- hard and recommended headroom
- path-safe discretionary spending
- SAFE / TIGHT / NOT_SAFE purchase assessment
- tightest future date
- shortfall to hard/recommended floors
- earliest fully safe purchase date
- flexible-goal assessment
- CONSERVATIVE / EXPECTED / OPTIMISTIC deterministic scenarios

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

## Current MVP assumptions

- past transactions are already reflected in current cash
- irregular income uses `amount × confidence` in the expected scenario
- conservative scenario counts no irregular income; optimistic counts the explicitly-entered irregular amount in full
- normal variable spending uses the median of recent eligible weekly history
- only the configured lookback window is used (default 6 weeks)
- reimbursable/extraordinary spending should be excluded upstream from weekly baseline samples
- reimbursements are represented as an expense followed by a future one-time income event
- mandatory goals are baseline future cash outflows
- flexible goals are What-If scenarios
- hard floor is `max(personal reserve, aggregate institutional minimum)`
- safety buffer is recommended headroom, not a hard constraint

This is a deterministic hackathon MVP, not a production financial-advice system.

## Validation status

Before committing this package, it was compiled with Swift 6.2.1 and the package test suite passed 15/15 tests in the development environment. Simon should still run `swift test` in Xcode/macOS before integrating it into the app.
