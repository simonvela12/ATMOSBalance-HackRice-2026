# Context Product Specification

Working branch: `product-v1.2-context-design`

This document captures product decisions for the next Context iteration without interfering with Simon's active work on `product-v1.2`.

## Product idea

Context exists to capture financially relevant information that the bank cannot know by itself.

The user should have two clear entry modes:

1. **Explain a transaction** — attach meaning to an existing linked-bank transaction.
2. **Add something I expect** — create a future financial event that has not appeared in the bank yet.

Nothing that changes the plan should be applied silently. The app should interpret supported context, show the result back to the user, request missing information instead of guessing, and require confirmation.

## Core planning principle: event-based, not salary-based

The product must work well for college students and other users with sparse, irregular, or lumpy income.

- Do not assume that users receive income every week, every two weeks, or every month.
- A user may reasonably have **zero income for several months**, followed by one large family transfer, refund, stipend, freelance payment, or other one-time deposit.
- Historical deposits must never create future recurring income unless the user explicitly confirms recurrence.
- If no future income events are confirmed for a period, the forecast should show **$0 future income for that period**.
- Recurrence is an explicit property of an income event, not a default behavior inferred from bank history.
- One-time, irregular, and recurring income must coexist in the same plan.
- Large one-time deposits must be represented on their actual expected date rather than spread evenly across time.
- Safe to Spend and Calendar must respect the actual dated cash path, including long gaps with no income.

## Supported concepts already agreed

### Income

- One-time income.
- Recurring income.
- Irregular / uncertain income.
- Weekly, biweekly, and monthly recurrence only when explicitly provided or confirmed by the user.
- Expected future income with amount, date, and confidence.
- Confidence UX is confirmed as: **Confirmed 100% / Likely 70% / Possible 30% / Custom %**.
- Custom confidence accepts an explicit user-entered percentage such as 55%, 65%, or 80%.
- For irregular income, expected-value planning may use `amount × confidence` while scenario views can remain conservative / expected / optimistic.
- Variable recurring income is supported. The simple path uses one **expected amount per occurrence**.
- Users who want more precision can optionally provide a **minimum and maximum amount** in addition to the expected amount.
- The app must not force users to enter a range; the expected amount alone is sufficient.
- When a recurring-income range is supplied, scenario amounts are explicit and deterministic:
  - **Conservative = minimum amount**
  - **Expected = expected amount**
  - **Optimistic = maximum amount**
- These min/expected/max scenario rules apply only to an income stream the user explicitly marked as recurring; they never create recurrence by themselves.
- A non-recurring uncertain income can still use confidence without implying that similar future deposits will occur.
- A future income can optionally have a **purpose / earmark**. Suggested purposes include **General support / Tuition / Rent / Travel / Other**.
- Purpose is optional; if the user does not assign one, the income remains general cash.
- A single income event may be split across **multiple allocations**. Example: a $3,000 family transfer can be allocated as $2,000 to Tuition and $1,000 to General support.
- Allocation amounts must sum to no more than the income amount. Any unallocated remainder is treated as general/free cash.
- Earmarked income still enters the dated cash path on the expected date, but earmarked portions should not automatically become general Safe to Spend.
- Earmarked funds should be associated with the relevant obligation or goal so the product can distinguish **cash on hand** from **cash actually free to spend**.
- Split allocations must remain visible and editable so the user can understand exactly where an incoming deposit is intended to go.
- If an earmark later becomes unnecessary because the linked obligation/goal was paid another way, removed, or fully satisfied, the app must **not automatically release those funds to general cash**.
- Instead, the app should prompt the user to choose what happens next: **Move to General cash / Reassign to another purpose / Keep reserved**.
- Until the user confirms a new destination, those funds remain reserved and do not automatically inflate discretionary Safe to Spend.

Examples the model must support:

- `$550 every 2 weeks`, optionally with `$450 minimum / $650 maximum`.
- `$800 on Sep 25`, likely 70%, and no other expected income afterward.
- `$0 expected income for the next 3 months`.
- `$3,000 family transfer on Dec 1`, one time.
- `$3,000 family transfer on Dec 1`, split as `$2,000 Tuition + $1,000 General support`.
- A Tuition earmark whose linked tuition obligation is later removed; the app asks whether to make the money general cash, reassign it, or keep it reserved.
- An irregular tutoring payment on one specific date without any implied next payment.

### Expenses

- Mandatory / must-pay expenses.
- Cancelable or avoidable expenses.
- Essential vs non-essential context.
- Recurring expenses.
- Future expenses not yet visible in bank data are explicitly supported.
- A future expense must capture: **amount, date, must-pay status, flexibility/cancelability, and recurrence**.
- Future expense recurrence options are: **No / Weekly / Every 2 weeks / Monthly**.
- Future expenses feed the same plan used by Calendar, Safe to Spend, Plans, and What-If.
- If an expense is marked **Maybe** reducible/cancelable, the normal forecast still counts the **full expense amount**. The app may separately show the full amount as potential savings if the user later reduces or cancels it.
- The app does not estimate a partial reduction for **Maybe** expenses.
- Future or recurring expenses may optionally have an **expected / minimum / maximum** amount when the user knows the cost is variable.
- Variable-expense ranges are optional; a single expected amount remains enough for the simple path.
- When an expense range is supplied, scenario treatment is deterministic and inverted relative to income:
  - **Conservative = maximum expense**
  - **Expected = expected expense**
  - **Optimistic = minimum expense**
- A range never creates an expense event by itself; the user must still provide or confirm the date/recurrence.
- Reimbursements / shared expenses.
- Partial reimbursement is confirmed: the user enters the **exact amount expected back** and the **expected repayment date**.
- The reimbursement amount does not have to equal the original expense.
- The original expense remains fully visible on its original date; the later repayment is represented separately so the temporary liquidity dip is preserved.
- The app must not silently assume that 100% of a shared expense will be reimbursed.

### Goals

- Goal amount and target date.
- Mandatory goals.
- Flexible / postponable goals.

### Personal reserve

- Minimum cash the user does not want to touch.
- The underlying engine supports reserve changes over time, so future UX may allow dated reserve changes.

## Proposed Context quick actions

The UI should make common meanings easy to express without requiring perfect natural-language phrasing.

Suggested quick actions:

- One time
- Recurring
- Expected income
- Uncertain
- Someone owes me
- Must pay
- Can cancel
- Goal
- Keep a reserve

Quick actions should open only the fields needed for that concept.

Examples:

**Expected income**
- Amount
- Date
- Confidence: Confirmed 100% / Likely 70% / Possible 30% / Custom %
- Recurrence defaults to **No** unless the user explicitly chooses otherwise
- Optional purpose allocation(s): General support / Tuition / Rent / Travel / Other
- Multiple allocations are allowed, plus any unallocated remainder as general cash

**Variable recurring income**
- Expected amount — required
- Recurrence: Weekly / Every 2 weeks / Monthly
- First or next expected date
- Optional advanced range: Minimum amount / Maximum amount
- Example: expected $550 every 2 weeks, optionally $450 minimum and $650 maximum
- Scenario mapping: Conservative $450 / Expected $550 / Optimistic $650

**One-time family/support income**
- Amount
- Expected date
- Confidence
- Recurrence: No
- Optional split purpose allocation
- Example: $3,000 from family on Dec 1, with $2,000 for Tuition and $1,000 for General support
- The confirmation preview should make clear which portions are reserved and which portion is discretionary
- If a reserved purpose later disappears, show a follow-up prompt: **Move to General cash / Reassign / Keep reserved**

**Someone owes me**
- Original transaction anchor
- Amount expected back — required and editable
- Repayment date — required
- Confirmation preview should show the original expense and the later reimbursement as separate dated cash-flow events

**Future expense**
- Amount — required
- Date — required
- Must pay? Yes / No
- Can reduce or cancel? No / Maybe / Yes
- Recurrence: No / Weekly / Every 2 weeks / Monthly
- Optional advanced range for variable costs: Minimum / Expected / Maximum
- If a range exists, scenario mapping is Conservative = maximum, Expected = expected, Optimistic = minimum
- If flexibility is **Maybe**, the full expected amount remains in the normal forecast until the user explicitly changes the plan
- The confirmation preview must show exactly what will be added to the future cash path before applying it

## Human-first expense questions

Do not initially expose every internal categorical field as technical metadata. Prefer questions such as:

- Do you have to pay this? Yes / No
- Could you reduce or cancel it? No / Maybe / Yes
- Will it happen again? No / Weekly / Every 2 weeks / Monthly

Merchant/category classification can be suggested automatically and corrected by the user.

## Existing categorical model to preserve

Expense categories:
- housing
- food
- transportation
- education
- entertainment
- shopping
- travel
- health
- subscriptions
- utilities
- social
- personal care
- fees
- other

Expense qualitative dimensions:
- Need: essential / important / optional
- Flexibility: fixed / semi-flexible / flexible
- Planning: planned / unplanned / emergency
- Frequency: recurring / occasional / one-time
- Priority: high / medium / low

Income source kinds:
- job
- campus work
- family
- freelance
- tutoring
- refund
- other

Confidence behavior:
- confirmed = 100%
- likely = 70%
- possible = 30%
- custom = exact user-entered percentage

## Product principles

- Context should change the same `FinancialProfile` used by Home, Calendar, Plans, and What-If.
- Bank data and user context must remain distinguishable.
- Never present demo/sample values as real linked-bank data.
- Never silently infer recurrence from transaction history alone.
- Never silently guess missing amount, date, cadence, reimbursement amount, or purpose.
- Preserve deterministic and explainable planning behavior.
- Do not introduce opaque financial scores or probability claims beyond explicit user-provided confidence.
- Zero-income periods are valid states, not missing data to be filled automatically.
- Dated one-time income should affect the cash path only on and after its actual expected date.
- An earmarked deposit can increase bank cash without increasing discretionary Safe to Spend by the same amount.
- When one deposit is split across purposes, only the unallocated/general portion should be treated as freely discretionary cash unless a linked obligation or goal is later released.
- Earmarked funds are never silently released; when their purpose disappears, the user must explicitly choose whether to make them general, reassign them, or keep them reserved.

## Confirmed decisions

1. Uncertain income confidence uses quick presets plus a custom percentage: **Confirmed 100% / Likely 70% / Possible 30% / Custom %**.
2. Reimbursements can be partial. The user must explicitly provide the **amount expected back** and **repayment date**; the app never assumes full reimbursement. The original expense and later repayment stay as separate dated events so temporary liquidity risk remains visible.
3. Future expenses can be created before they appear in bank data. Required inputs are **amount, date, whether the user must pay it, whether it can be reduced/canceled, and whether it recurs**. Recurrence choices are **No / Weekly / Every 2 weeks / Monthly**. Confirmed future expenses immediately affect the shared financial plan.
4. If the user marks an expense as **Maybe** reducible/cancelable, the baseline forecast remains conservative and includes the **full amount**. The app may show up to that full amount as potential savings, but it does not assume any reduction until the user explicitly changes or cancels the expense.
5. Variable recurring income uses a **required expected amount** plus an **optional minimum–maximum range**. The range is optional and should add precision without making the basic flow more complicated.
6. For an explicitly recurring variable income with a supplied range, scenarios use **minimum / expected / maximum** directly: Conservative = minimum, Expected = expected, Optimistic = maximum.
7. The entire income model is **event-based rather than salary-based**. The product must support long periods of zero income, one-time family transfers, isolated refunds, stipends, freelance payments, and other sparse/lumpy cash inflows without inventing recurrence.
8. Future income can optionally be assigned a **purpose / earmark** such as General support, Tuition, Rent, Travel, or Other. Earmarked funds enter the dated cash balance but should not automatically inflate discretionary Safe to Spend; they remain associated with their intended obligation or goal.
9. A single income event may be **split across multiple purposes**. Example: a $3,000 deposit can allocate $2,000 to Tuition and $1,000 to General support. Any unallocated remainder stays general cash, and the UI must make each allocation explicit before confirmation.
10. If an earmarked purpose later disappears or is already fully satisfied, the earmarked money is **not automatically released**. The app asks the user to choose **Move to General cash / Reassign to another purpose / Keep reserved**. Until confirmed, the funds remain reserved.
11. Variable expenses may use an optional **minimum / expected / maximum** range. Scenario mapping is inverted versus income: **Conservative = maximum expense, Expected = expected expense, Optimistic = minimum expense**.

## Open decisions

The remaining UX and semantic choices will be decided interactively and recorded here before implementation.
