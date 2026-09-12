# Financial Engine v2 — mathematical specification

This is the model we are building for the HackRice MVP. It replaces the idea that every user has one fixed `protectedCash` number.

The guiding question is:

> Given what I have today, what I am likely to earn, what I must spend, what minimum liquidity I need to preserve, and how uncertain my life is, how much money is actually safe to play with?

The model is intentionally deterministic and explainable. Natural-language interpretation, transaction classification, UI, and APIs are upstream/downstream concerns. The math engine receives normalized inputs and returns numbers/statuses.

---

## 1. Current cash

`currentCash` is the total liquid cash represented by the connected accounts at the profile's `asOfDate`.

Past transactions are already reflected in this number. Therefore a past transfer or reimbursement must never be added again as future income.

---

## 2. Personal reserve schedule

A college student's liquidity needs are personal and can change over time.

Examples:

- one student may need to preserve about $8,800 until March, $8,500 until August, then $8,200 afterward;
- another may be comfortable approaching zero at semester end because a known payment arrives immediately after;
- another may only plan month-to-month.

The engine therefore uses a time-dependent personal reserve:

`personalReserve(t)` = minimum total cash the user wants/needs to preserve at date `t`.

The qualitative layer can convert user statements into dated reserve steps, but the user should confirm the interpretation before the math engine uses it.

For the MVP, a reserve schedule is represented by effective-date steps:

- Sep 1 -> $8,800
- Mar 1 -> $8,500
- Aug 1 -> $8,200

The most recent step effective on or before date `t` applies.

The reserve may decrease, stay flat, or increase.

---

## 3. Institutional minimums

Some constraints are external rather than personal, e.g. a bank/account requirement to maintain a $500 minimum balance.

For MVP math:

`institutionalMinimum(t)` = sum of all active institutional minimum-balance constraints.

We aggregate these constraints rather than modelling per-account routing. Account-specific enforcement is a later refinement.

---

## 4. Hard floor

The user must satisfy both their personal reserve policy and institutional constraints.

Because the personal reserve is a minimum on total cash, and institutional minimums are also minimum cash constraints, the aggregate hard floor is:

`hardFloor(t) = max(personalReserve(t), institutionalMinimum(t))`

The same dollars can satisfy both constraints. We do not add them unless they are genuinely independent account requirements already summed inside `institutionalMinimum(t)`.

---

## 5. Typical variable spending

Known bills such as rent or subscriptions are explicit future expense events.

Normal variable spending — food, Uber, ordinary social spending, small purchases — is projected from recent history.

For the MVP, upstream logic provides weekly variable-spending totals after excluding:

- reimbursements,
- one-off/extraordinary purchases,
- known fixed bills already represented separately.

The engine uses the median weekly total:

`typicalWeeklySpending = median(eligible weekly totals)`

Median is preferred to raw mean because one unusually expensive week should not redefine the user's normal lifestyle.

Projected normal variable spending is prorated by time:

`projectedVariableSpending(t) = typicalWeeklySpending * days(asOfDate, t) / 7`

A known unusually expensive dinner/trip/purchase is added separately as a planned expense, not hidden inside the baseline.

---

## 6. Safety buffer

The safety buffer is not a hard legal/account constraint. It is recommended uncertainty headroom.

MVP rule:

`safetyBuffer = max(manualMinimumBuffer, typicalWeeklySpending * weeksOfCoverage)`

Default `weeksOfCoverage = 2`.

If there is not enough spending history, `manualMinimumBuffer` acts as the fallback.

This rule is intentionally simple and explainable. More adaptive volatility-based buffers can come after the hackathon.

---

## 7. Income events

Every normalized income event contains amount, date, source, type, and confidence.

Types:

- `recurring`: explicitly expected/scheduled and counted at full amount;
- `irregular`: expected amount multiplied by confidence;
- `oneTime`: counted only on its explicit future date and never extrapolated.

Past income is never added because it is already inside `currentCash`.

For MVP:

`expectedIncome(t) = sum(adjusted future income events up to t)`

where irregular income uses:

`adjustedAmount = amount * confidence`

The qualitative layer should ask the user whether detected patterns are expected to continue before creating future events.

---

## 8. Reimbursements

A reimbursable purchase is still a real liquidity outflow before reimbursement arrives.

Example:

- Sep 10: -$300 purchase
- Sep 20: +$300 expected reimbursement

Both events are represented separately so the model captures the temporary cash dip.

Historical reimbursable spending should be excluded from the normal-spending baseline so the engine does not learn it as ordinary lifestyle spending.

---

## 9. Goals

Goals have two priorities:

- `mandatory` / must happen;
- `flexible` / nice to have.

For mathematical clarity, a goal's `targetAmount` is the total planned cost and `amountAlreadyPaid` means money that has actually left the account already. Money merely earmarked inside a bank balance is not `amountAlreadyPaid`.

`remainingGoalAmount = max(0, targetAmount - amountAlreadyPaid)`

Mandatory goal payments are included in the baseline cash trajectory on their deadlines.

Flexible goals are not silently subtracted from baseline. They are evaluated as What-If scenarios so the app can report trade-offs instead of pretending they are hard obligations.

This removes the previous `alreadyProtected` double-counting problem.

---

## 10. Projected cash

For any future date `t`:

`projectedCash(t) = currentCash`
`                 + expectedIncome(t)`
`                 - committedExpenses(t)`
`                 - projectedVariableSpending(t)`
`                 - mandatoryGoalPayments(t)`

This is the expected liquid balance before applying reserve/buffer constraints.

---

## 11. Hard and recommended headroom

`hardHeadroom(t) = projectedCash(t) - hardFloor(t)`

`recommendedHeadroom(t) = hardHeadroom(t) - safetyBuffer`

Interpretation:

- hard headroom < 0: a real personal/institutional minimum is violated;
- hard headroom >= 0 but recommended headroom < 0: technically possible but too close to the edge;
- recommended headroom >= 0: maintains both hard constraints and the recommended buffer.

---

## 12. Safe discretionary spending across a horizon

A final-date balance alone is not enough. The engine checks the entire trajectory because a later reimbursement/income cannot rescue a cash shortfall that occurred earlier.

For horizon `[start, H]`:

`minimumHardHeadroom = min(hardHeadroom(t))`

`minimumRecommendedHeadroom = min(recommendedHeadroom(t))`

The core user-facing safe-spend number is:

`safeToSpend = max(0, minimumRecommendedHeadroom)`

Negative values are preserved internally for diagnostics.

---

## 13. Planned purchase assessment

For purchase amount `A` on date `D`, the purchase reduces all future headroom from `D` onward by `A`.

Compute the minimum headroom from `D` through the planning horizon `H`.

Status:

- `SAFE` if `minimumRecommendedHeadroom - A >= 0`
- `TIGHT` if the recommended buffer is breached but `minimumHardHeadroom - A >= 0`
- `NOT_SAFE` if `minimumHardHeadroom - A < 0`

This is intentionally more informative than a binary yes/no.

The engine also returns the shortfall to both the hard floor and recommended floor.

---

## 14. Earliest safe purchase date

Search candidate dates from the desired purchase date through horizon `H`.

The earliest date `D` satisfying:

`minimumRecommendedHeadroom(D...H) >= purchaseAmount`

is the earliest fully safe purchase date.

For MVP, daily iteration is acceptable.

---

## 15. Flexible-goal trade-offs

A flexible goal is evaluated like a hypothetical future purchase on its deadline.

The app can compare a flexible goal's status before and after another What-If purchase.

Example:

- without F1: Miami = SAFE
- with F1: Miami = TIGHT

The UI can then say that F1 is technically possible but consumes the margin that keeps Miami comfortably on track.

For the hackathon, we do not optimize a complex utility function across many desires. Priority order is:

1. institutional/personal hard floors
2. essential committed expenses
3. mandatory goals
4. safety buffer
5. flexible goals
6. discretionary spending

---

## 16. Reference manual check

Inputs:

- current cash = $8,000
- personal reserve = $7,000
- institutional minimum = $0
- manual safety buffer = $250
- no spending-history baseline for this check
- expected future income before Nov 30 = $1,000
- committed expenses before Nov 30 = $500
- no mandatory goal payment

Then:

`projectedCash = 8000 + 1000 - 500 = 8500`

`hardFloor = max(7000, 0) = 7000`

`hardHeadroom = 8500 - 7000 = 1500`

`recommendedHeadroom = 1500 - 250 = 1250`

Expected result: **$1,250 safe discretionary cash**.

This preserves the original checkpoint while using the new model.

---

## 17. What is intentionally not in v2 yet

- machine learning
- Monte Carlo simulation
- automatic NLP parsing inside the math engine
- per-account transfer optimization
- investment recommendations
- complex optimization across many flexible goals

Those features are lower priority than having a deterministic engine whose assumptions can be explained to a judge in under a minute.
