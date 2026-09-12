# START HERE — Financial Math Engine

This file is the easiest place to understand what the math workstream is doing right now.

## What question are we trying to answer?

> Given what I have today, what I am likely to earn, what I must pay, what minimum cash I need to preserve, and how uncertain my situation is, how much money can I actually use without breaking my financial plan?

The engine does **not** simply look at today's bank balance.

It projects the user's cash through time and checks the worst point in the future.

---

## The pieces

### 1. Current cash

All liquid money the user actually has today.

Example: `$9,500`.

### 2. Future income

Money expected to arrive later.

Each event has:
- amount
- date
- source
- type: recurring / irregular / one-time
- confidence when relevant

Past income is never added again because it is already reflected in current cash.

### 3. Essential + normal spending

We subtract:
- known committed bills
- mandatory expenses
- automatically projected normal spending such as food, Uber, small purchases, etc.

The current MVP idea is to estimate normal weekly spending from recent history using a median so one weird week does not dominate the forecast.

### 4. Personal reserve schedule

This replaces the old idea of one fixed `protectedCash` number.

A user's minimum desired reserve can change over time.

Example:

| Period | Minimum personal reserve |
|---|---:|
| now → March 31 | $8,800 |
| April 1 → July 31 | $8,500 |
| August 1 onward | $8,200 |

This comes from qualitative user context and should be confirmed by the user.

### 5. Institutional minimum

Some accounts may require the user to maintain a minimum balance.

Example: bank requires `$500`.

We treat this as a hard constraint.

For the MVP:

`hardFloor(date) = max(personalReserve(date), institutionalMinimum(date))`

We use the maximum rather than blindly adding them because the same dollars can usually satisfy both constraints.

### 6. Safety buffer

The hard floor tells us what the user must not cross.

The safety buffer gives additional recommended breathing room.

Current MVP proposal:

`SafetyBuffer = max(userMinimumBuffer, 2 × typicalWeeklySpending)`

This is not a universal truth. It is a simple, explainable starting rule for the hackathon.

---

## Core equations

For any future date `t`:

`ProjectedCash(t) = currentCash + futureIncome(t) - committedExpenses(t) - projectedNormalSpending(t) - mandatoryGoalsPaidBy(t)`

Then:

`HardHeadroom(t) = ProjectedCash(t) - HardFloor(t)`

`RecommendedHeadroom(t) = HardHeadroom(t) - SafetyBuffer`

The important part is that we do **not** only inspect the final date.

We check the whole planning horizon and find the tightest point.

`MinimumRecommendedHeadroom = minimum RecommendedHeadroom(t) over the whole horizon`

That is the basis for safe discretionary spending.

---

## Purchase status

For an optional purchase, we temporarily insert the purchase as an extra future cash outflow and recalculate the path.

### SAFE

The user remains above both the hard floor and the recommended safety floor for the full horizon.

### TIGHT

The user stays above the hard floor, but dips inside the recommended safety buffer.

The purchase is technically possible, but the app should explain the trade-off.

### NOT_SAFE

The purchase makes the user fall below a hard constraint at some point in the horizon.

---

# Example

Assume:

- current cash = `$9,500`
- personal reserve until March = `$8,800`
- bank minimum = `$500`
- typical weekly spending = `$100`
- safety buffer = `2 × $100 = $200`
- no future income before the date we are checking

Then:

`hardFloor = max(8800, 500) = 8800`

`recommendedFloor = 8800 + 200 = 9000`

Today:

`HardHeadroom = 9500 - 8800 = 700`

`RecommendedHeadroom = 9500 - 9000 = 500`

So before considering future bills, the user has `$500` of recommended discretionary room.

If a future mandatory bill of `$350` arrives before new income:

`ProjectedCash = 9500 - 350 = 9150`

`HardHeadroom = 9150 - 8800 = 350`

`RecommendedHeadroom = 9150 - 9000 = 150`

The tightest recommended room is now only `$150`.

A `$450` F1 ticket would therefore push the path below the recommended floor and also below the hard floor at the tightest point:

`9150 - 450 = 8700`

`8700 < 8800 hard floor`

Result: **NOT_SAFE** under these assumptions.

If later the personal reserve falls from `$8,800` to `$8,200`, the same purchase may become safe. That is why the engine is time-dependent.

---

## What we are deliberately NOT using yet

- Monte Carlo simulation
- machine learning for purchase decisions
- black-box AI affordability decisions

The core engine is deterministic and explainable first.

Qualitative AI/context can help classify transactions and understand the user's situation, but the final financial calculation should come from transparent rules.

---

## Files to look at next

If this file makes sense, then read in this order:

1. `MODEL_V2.md` — full mathematical specification
2. `MANUAL_CHECKS_V2.md` — calculations done by hand
3. `test_cases_v2.csv` — many edge cases in a spreadsheet-like format
4. `FinancialEngineV2Tests.swift` — the same rules expressed as tests
5. `FinancialEngineV2.swift` — actual implementation

For now, understanding this file is enough to understand the direction of the math engine.
