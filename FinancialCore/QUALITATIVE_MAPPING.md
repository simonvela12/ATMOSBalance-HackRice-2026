# Qualitative layer -> FinancialCore mapping

This file is the boundary contract between Simon's qualitative logic and `FinancialCore`.

The qualitative layer interprets transaction meaning. `FinancialCore` does not guess intent; it receives normalized dated cash-flow events and deterministic policy inputs.

## Expense mapping

A classified transaction should become an `ExpenseEvent` when it represents a future cash outflow that belongs in the planning horizon.

- `essential`: descriptive signal for needs vs wants.
- `committed`: controls whether the expense is automatically included in the baseline forecast.
- `reimbursable`: marks an expense expected to be paid back.
- `extraordinary`: marks a one-off event that should not contaminate normal weekly-spending history.

Important: an expense can be non-essential but still committed (for example, a subscription the user has not cancelled). Do not equate `essential == committed` mechanically.

A reimbursement is represented as two dated movements:

1. the original `ExpenseEvent` on the payment date; and
2. a future `.oneTime` `IncomeEvent` on the expected reimbursement date.

That preserves the temporary liquidity dip instead of netting the two together.

## Recurring expenses

`ExpenseEvent` represents one dated cash movement. A qualitative label saying "recurring" does not make one `ExpenseEvent` repeat automatically.

Use `FinancialScheduleBuilder.recurringExpense(...)` to materialize the expected future occurrences through the planning horizon, or create those dated events in the normalization layer yourself.

Typical mapping:

```swift
let rentEvents = try FinancialScheduleBuilder.recurringExpense(
    amount: 900,
    firstDate: nextRentDate,
    through: horizon,
    category: "Rent",
    cadence: .monthly,
    essential: true,
    committed: true
)
```

Supported MVP cadences are weekly, biweekly, and monthly.

## Income mapping

Use:

- `.recurring` for expected repeated/contracted income such as wages;
- `.irregular` for plausible income whose amount or arrival is uncertain;
- `.oneTime` for known isolated inflows such as a reimbursement or confirmed transfer.

For `.irregular`, `confidence` is an explicit 0...1 input used only in the expected scenario. Conservative counts no irregular income; optimistic counts the entered amount in full.

Important: `IncomeType.recurring` describes the event's type; it does not automatically generate future paychecks. Use `FinancialScheduleBuilder.recurringIncome(...)` or materialize each dated occurrence upstream.

Example:

```swift
let paychecks = try FinancialScheduleBuilder.recurringIncome(
    amount: 450,
    firstDate: nextPayday,
    through: horizon,
    source: "Campus job",
    cadence: .biweekly
)
```

## Goal mapping

Use `.mandatory` when the user says the goal/obligation must be funded by the deadline. Mandatory goals are part of the baseline cash path.

Use `.flexible` when the user wants the goal but is willing to trade it off against other choices. Flexible goals stay outside the baseline and are assessed as What-If decisions.

`amountAlreadyPaid` means money that has actually left the user's cash balance toward the goal. Do not use it for money that is merely mentally earmarked.

If a personal reserve already contains money earmarked for a goal that is also represented explicitly as a `Goal`, the reserve schedule must release that earmarked amount when the goal is paid. Otherwise the same need is effectively protected twice.

## Reserve and minimum-balance mapping

`PersonalReserveStep` is the user's own minimum liquidity requirement and may change over time.

`InstitutionalMinimum` is an external constraint such as a required account balance.

The engine computes:

```text
hard floor = max(personal reserve, aggregate active institutional minimums)
recommended floor = hard floor + safety buffer
```

The safety buffer is prudential, not a hard prohibition. Falling below it produces `TIGHT`; falling below the hard floor produces `NOT_SAFE`.

## Weekly spending history

The weekly history should contain ordinary variable spending only.

Exclude or normalize separately:

- reimbursements;
- extraordinary trips or purchases;
- committed fixed bills already represented as dated `ExpenseEvent`s.

The engine uses the median of recent eligible weeks so one unusually expensive week does not dominate the forecast.

## Before presenting a decision

Run diagnostics after building the profile:

```swift
let diagnostics = FinancialProfileDiagnostics.report(
    profile: profile,
    planningHorizon: horizon
)
```

If `diagnostics.isReadyForForecast == false`, the qualitative/normalization layer supplied malformed inputs and the app should fix them before presenting an affordability result.

Warnings are not hard failures. They expose assumptions such as sparse spending history, long forecast horizons, overdue goals, or irregular-income confidence values that were clamped.

## Integration principle

The intended flow is:

```text
Nessie / user transactions
        ↓
pattern detection + qualitative questions
        ↓
normalized dated events + goals + reserves
        ↓
FinancialProfileDiagnostics
        ↓
FinancialCore deterministic engine
        ↓
dashboard / calendar / What-If / goal trade-offs
```

The qualitative layer decides what the data means. The deterministic engine decides what that meaning implies for liquidity and affordability.
