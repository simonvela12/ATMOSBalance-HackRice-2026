# Context Product Specification

Working branch: `product-v1.2-context-design`

This document captures product decisions for the next Context iteration without interfering with Simon's active work on `product-v1.2`.

## Product idea

Context exists to capture financially relevant information that the bank cannot know by itself.

The user should have two clear entry modes:

1. **Explain a transaction** — attach meaning to an existing linked-bank transaction.
2. **Add something I expect** — create a future financial event that has not appeared in the bank yet.

Nothing that changes the plan should be applied silently. The app should interpret supported context, show the result back to the user, request missing information instead of guessing, and require confirmation.

## Supported concepts already agreed

### Income

- One-time income.
- Recurring income.
- Irregular / uncertain income.
- Weekly, biweekly, and monthly recurrence.
- Expected future income with amount, date, and confidence.
- Confidence UX is confirmed as: **Confirmed 100% / Likely 70% / Possible 30% / Custom %**.
- Custom confidence accepts an explicit user-entered percentage such as 55%, 65%, or 80%.
- For irregular income, expected-value planning may use `amount × confidence` while scenario views can remain conservative / expected / optimistic.

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
- If flexibility is **Maybe**, the full amount remains in the normal forecast until the user explicitly changes the plan
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
- Never silently guess missing amount, date, cadence, or reimbursement amount.
- Preserve deterministic and explainable planning behavior.
- Do not introduce opaque financial scores or probability claims beyond explicit user-provided confidence.

## Confirmed decisions

1. Uncertain income confidence uses quick presets plus a custom percentage: **Confirmed 100% / Likely 70% / Possible 30% / Custom %**.
2. Reimbursements can be partial. The user must explicitly provide the **amount expected back** and **repayment date**; the app never assumes full reimbursement. The original expense and later repayment stay as separate dated events so temporary liquidity risk remains visible.
3. Future expenses can be created before they appear in bank data. Required inputs are **amount, date, whether the user must pay it, whether it can be reduced/canceled, and whether it recurs**. Recurrence choices are **No / Weekly / Every 2 weeks / Monthly**. Confirmed future expenses immediately affect the shared financial plan.
4. If the user marks an expense as **Maybe** reducible/cancelable, the baseline forecast remains conservative and includes the **full amount**. The app may show up to that full amount as potential savings, but it does not assume any reduction until the user explicitly changes or cancels the expense.

## Open decisions

The remaining UX and semantic choices will be decided interactively and recorded here before implementation.
