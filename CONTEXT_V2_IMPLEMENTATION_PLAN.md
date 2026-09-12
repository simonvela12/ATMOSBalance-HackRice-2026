# Context V2 Implementation Plan

Working branch: `product-v1.2-context-v2-core`

This branch is derived from `product-v1.2-context-design` and is intentionally isolated from Simon's active `product-v1.2` work. The goal is to implement the new Context/planning model in `FinancialCore` first, with deterministic tests, before touching the iOS UI.

## Source product specs

Implementation must remain consistent with:

- `CONTEXT_PRODUCT_SPEC.md`
- `CONTEXT_PRODUCT_DELEGATED_DECISIONS.md`
- `CONTEXT_MATERIALITY_POLICY.md`

When older behavior conflicts with the materiality policy, the newer materiality policy wins.

## Non-negotiable architecture rules

1. `FinancialCore` remains the deterministic planning source of truth.
2. Bank facts and planning assumptions stay distinguishable.
3. Historical bank amount/date/source are not rewritten by planning edits.
4. Recurrence is never inferred silently from bank history.
5. Event matching may be automatic only when identity is strong and the discrepancy is immaterial.
6. Risk-state changes always surface even when the dollar difference is small.
7. Existing public initializers should remain source-compatible where practical.
8. Existing V1.2 tests must remain green while new Context V2 tests are added.
9. No UI work in Phase 1.

## Phase 1 — planning primitives and deterministic resolution

Add small composable model primitives instead of immediately replacing the existing `IncomeEvent` / `ExpenseEvent` types.

### New types

- `AmountRange`
  - `minimum`
  - `expected`
  - `maximum`
  - validation/clamping helpers
  - scenario amount mapping

- `DateWindow`
  - `earliest`
  - `expected`
  - `latest`
  - scenario date mapping

- `RecurrenceCadence`
  - weekly
  - biweekly
  - monthly
  - custom interval support in the model

- `RecurrenceRule`
  - cadence
  - first/next occurrence
  - optional end date
  - optional paused state
  - occurrence generation bounded by a planning horizon

- `IncomeAllocation`
  - amount
  - purpose label
  - optional linked goal/obligation id
  - explicit general-cash allocation supported

- `PlanningEventSource`
  - bank
  - manual
  - planned
  - derivedMatch

- `PlanningEventStatus`
  - planned
  - pending
  - posted/completed
  - overdue
  - missed
  - cancelled

- `MaterialityDecision`
  - autoApply
  - askUser
  - ignoreNoImpact

- `PlanningRiskState`
  - normal
  - belowRecommendedBuffer
  - belowHardFloor
  - negativeCash
  - mandatoryObligationShortfall

### Backward-compatible event extensions

Extend `IncomeEvent` and `ExpenseEvent` only with optional/defaulted planning fields so existing call sites continue to compile.

Income candidates:
- optional `amountRange`
- optional `dateWindow`
- optional `recurrenceRule`
- optional allocations
- optional source/status metadata

Expense candidates:
- optional `amountRange`
- optional `dateWindow`
- optional `recurrenceRule`
- optional merchant/payee identity metadata
- optional source/status metadata

Do not remove the existing canonical `amount` or `date`; they remain the expected/default values used by legacy code.

### Scenario resolution

Create pure helpers that resolve an event for a selected scenario:

Income:
- Conservative amount = minimum when an explicit range exists
- Expected amount = expected
- Optimistic amount = maximum
- Conservative uncertain non-recurring income may still resolve to $0 through confidence semantics
- date window: Conservative latest / Expected expected / Optimistic earliest

Expense:
- Conservative amount = maximum
- Expected amount = expected
- Optimistic amount = minimum
- date window: Conservative earliest / Expected expected / Optimistic latest

`FinancialScenarioEngine.adjustedProfile` should use these helpers rather than duplicating scenario logic.

### Recurrence materialization

Create a pure materializer that expands explicitly recurring rules into occurrences through a requested horizon.

Rules:
- never infer recurrence
- optional end date is authoritative
- end date is inclusive if it lands exactly on an occurrence
- paused recurrence generates nothing after the pause point until resumed
- historical completed occurrences are not rewritten
- materialization must be deterministic for a supplied `Calendar`

Phase 1 only needs pure generation; UI editing semantics (`this occurrence`, `this and future`) can be layered later.

## Phase 2 — materiality and planned-vs-actual resolution

Implement a pure `MaterialityPolicy` service.

### Tiny recurring price changes

For the same strongly identified merchant/service, auto-apply a new amount when:

`abs(actual - expected) <= max(3, expected * 0.01)`

and no risk-state boundary changes.

Otherwise ask.

### Planned-vs-actual matching

When identity is strong, auto-link a planned event to an actual bank transaction when:

- amount difference `<= max(5, planned * 0.02)`
- date difference `<= 3 calendar days` OR inside the explicit date window
- no ambiguity among multiple plausible candidates
- no material risk-state flip requiring surfacing

Use the actual bank amount/date as historical fact after linking.

### Risk-state override

Even a $1-$2 change is material when it crosses:
- projected cash below zero
- personal/institutional hard floor
- recommended buffer
- mandatory obligation funding boundary

The materiality service must accept pre/post risk information instead of hiding this logic in the UI.

## Phase 3 — overdue events, reimbursements, goals and earmarks

Implement after Phase 1/2 are stable.

- overdue expected income/reimbursements never become received automatically
- must-pay overdue expenses remain immediate obligations
- partial and multi-installment reimbursements
- earmarks and split allocations
- no silent release of earmarks
- target-date vs gradual goal funding
- goal priority conflict resolution

## Phase 4 — transfers, multi-account and actual/planned identity

Coordinate with the banking package rather than duplicating provider logic.

- internal transfers net to zero in aggregate planning
- linked credit-card payment is not a second expense
- pending -> posted deduplication
- provider duplicate removal
- aggregate multi-account liquidity with account drill-down

## Phase 5 — Context/iOS integration

Only after `FinancialCore` is green:

- Context quick actions
- advanced fields progressively disclosed
- assumptions/adjustments activity trail
- silent immaterial adjustments shown as non-blocking audit entries
- ask user only for ambiguous/material/semantic changes
- Calendar/Home/What-If read the same resolved profile

## Phase 1 test matrix

At minimum add deterministic tests for:

1. Income range scenario mapping: 450 / 550 / 650 -> Conservative 450, Expected 550, Optimistic 650.
2. Expense range scenario mapping: 300 / 400 / 500 -> Conservative 500, Expected 400, Optimistic 300.
3. Income date window: Oct 1 / Oct 15 / Oct 31 -> Conservative Oct 31, Expected Oct 15, Optimistic Oct 1.
4. Expense date window uses the inverse timing.
5. Recurrence end date prevents later occurrences.
6. Recurrence with no end date stops at planning horizon.
7. Paused recurrence generates no active future occurrences.
8. Existing simple `IncomeEvent` and `ExpenseEvent` initializers still behave exactly as before when no new metadata exists.
9. Scenario engine still preserves legacy irregular-confidence behavior when no range/window exists.
10. A long zero-income period stays zero when no explicit future income events exist.

## Phase 2 test matrix

1. Netflix expected $20 / actual $22 / same merchant / no risk flip -> `autoApply`.
2. Netflix expected $20 / actual $35 -> `askUser`.
3. Rent 900 / actual 905 / strong landlord match / +1 day -> auto-link.
4. Rent 900 / actual 950 -> ask.
5. Tiny $2 difference that crosses hard floor -> ask/surface despite tiny amount.
6. Pending -> posted same provider id -> automatic canonicalization, no question.
7. Ambiguous merchant identity -> never auto-update recurring semantics.

## Validation contract

Before merging any implementation batch:

1. `swift test --package-path FinancialCore`
2. `swift test`
3. `xcodebuild -project Finanzas2026/Finanzas2026.xcodeproj -scheme Finanzas2026 -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build`

Phase 1 should be committed separately from UI changes so regressions are easy to isolate.

## Integration rule with Simon

Do not merge this branch into `product-v1.2` while Simon is actively iterating locally. Once the core is green, compare branches and perform one controlled integration pass preserving his iOS/UI work and this branch's FinancialCore changes.
