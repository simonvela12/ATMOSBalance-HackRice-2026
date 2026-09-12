# Context Materiality Policy

Working branch: `product-v1.2-context-design`

This file extends `CONTEXT_PRODUCT_SPEC.md` and `CONTEXT_PRODUCT_DELEGATED_DECISIONS.md`.

The product should **not ask the user to confirm every small discrepancy**. When identity is clear and the financial effect is immaterial, the app should make the reasonable deterministic assumption, update the plan, and keep the adjustment visible/editable in an audit trail. The app should interrupt the user only when the difference is material, ambiguous, or changes planning semantics/risk.

This policy supersedes earlier blanket language that required confirmation for every planned-vs-actual match or every recurring-amount change. Confirmation is still required when identity, intent, or material financial impact is uncertain.

## Core rule: ask less, but never guess important meaning

A silent adjustment is allowed only when all of the following are true:

1. **Identity is strong.** The system can explain why the real transaction corresponds to the planned item, recurring merchant, transfer, refund, or other event.
2. **The discrepancy is small.** Amount/date differences are within deterministic tolerances.
3. **The planning meaning does not change.** The adjustment does not invent recurrence, change must-pay status, create/cancel a goal, release earmarked money, change confidence, or reinterpret debt/transfer semantics.
4. **The risk state does not flip.** Even a small dollar change must be surfaced if it creates or removes a reserve breach, hard-floor violation, negative cash point, missed mandatory obligation, or other material warning.
5. **The action is reversible and explainable.** The user can inspect what was assumed and edit/undo it later.

## Deterministic materiality defaults

These are initial product defaults, not opaque scores.

### Tiny recurring-amount change

For a clearly matched recurring merchant/service, a new actual amount may silently replace the expected future amount when:

- absolute difference is `<= max($3, 1% of expected amount)`, and
- the change does not flip a risk state.

Examples:

- Netflix expected `$20`, actual `$22` -> **silently update future expected amount to $22**.
- Spotify expected `$12`, actual `$13` -> silently update.
- Rent expected `$900`, actual `$950` -> **ask**, because the difference is clearly material.
- Rent expected `$900`, actual `$910` -> ask under the default threshold (`max($3, $9) = $9`; the difference is $10).

The UI may show a non-blocking note such as `Adjusted Netflix from $20 to $22 based on the latest charge`, but should not require a modal confirmation.

### Planned-vs-actual matching

When merchant/payee identity is strong, a planned occurrence may be automatically linked to a real bank transaction without asking when:

- amount difference is `<= max($5, 2% of planned amount)`,
- date difference is within `3 calendar days` OR the actual date falls inside the user's explicit date window,
- and linking does not create/remove a material risk state.

Once linked, the actual bank amount/date becomes the historical fact and the planned occurrence is not counted again.

If identity is weak, several candidate events exist, the difference is larger, or the match changes a material warning, ask the user.

### Date drift on a known recurring merchant

For the same clearly identified merchant/service:

- `+/- 3 days` from the expected recurring date is normal operational drift and should be matched silently.
- Any date inside an explicit Earliest/Expected/Latest window is normal and should be resolved silently when the actual transaction arrives.
- A larger shift should only trigger a question if it makes the recurrence rule itself look wrong or materially changes the cash path.

### User-facing change notifications

Safe to Spend and forecast values should recompute continuously, but the app should not notify or interrupt the user for tiny numerical movement.

A generic forecast-change notification is only warranted when the change is at least `max($10, 5% of the previous displayed Safe to Spend)` **or** when any hard risk state changes.

Crossing `$0`, crossing a reserve/hard floor, creating a mandatory-obligation shortfall, or resolving such a shortfall is always material regardless of dollar threshold.

## Translation of this principle across the product

### 1. Recurring subscriptions and bills

If the same merchant is known and the amount change is tiny, update the future expected amount automatically. Ask only for material price changes or ambiguous merchant identity.

For a user-defined variable range, an actual charge inside the range is normal and requires no question. If the actual charge falls outside the range only trivially, record the actual without interrupting the user. Ask to revise the future range only when the miss is material or repeated.

### 2. Planned expenses becoming real transactions

If the bank transaction is an obvious match to a planned event, link it automatically. Do not ask `Is this your rent?` when the system already has strong landlord identity, a matching date, and a matching amount.

Ask only when there are multiple plausible matches, merchant identity is uncertain, or the amount/date is materially different.

### 3. Planned income becoming a real deposit

If an expected income event has a strong source/payor match and the amount/date is within the deterministic tolerance/window, mark it received automatically and replace the forecast event with the bank fact.

If a `$2,000` expected family transfer appears as `$1,150`, or an expected campus-job payment arrives from an unrecognized source, ask before linking.

### 4. Reimbursements

If a repayment clearly matches a specific expected reimbursement installment, link it automatically. A tiny amount/date difference should not generate a question.

If there are several people who owe the user money, the bank description is ambiguous, or the repayment is materially partial/different, ask.

### 5. Pending -> posted transactions

Never ask. Resolve and deduplicate automatically when provider identity/fallback identity proves it is the same economic transaction.

### 6. Duplicate transactions

Never ask when deterministic provider identity proves duplication. Remove the duplicate economic effect automatically and keep one canonical transaction.

### 7. Transfers between the user's own accounts

When both sides can be strongly identified as the user's own accounts, classify and net the transfer automatically. Do not ask whether it is income/spending.

If only one side exists and ownership is uncertain, keep the classification conservative and ask only if the distinction affects the plan materially.

### 8. Credit-card payments

If checking -> linked credit card is clearly an internal card payment, classify it automatically as transfer/debt settlement rather than a second expense. No confirmation needed.

### 9. Refunds and reversals

If provider metadata or a strong merchant/original-transaction match identifies a refund, link it automatically. Ask only when several original purchases are plausible or the refund semantics are unclear.

### 10. Merchant/category classification

High-confidence merchant categories should be applied automatically and remain editable. The user should not be asked whether Netflix is a subscription every month.

Category uncertainty alone should not block cash-flow calculations. Ask only when the distinction changes planning semantics, for example `transfer vs expense`, `borrowed funds vs earnings`, or another high-impact interpretation.

### 11. Merchant aliases and text cleanup

Normalize obvious aliases and bank descriptors silently (`NETFLIX.COM`, `Netflix`, `NETFLIX*1234` -> Netflix) when the mapping is deterministic. Do not create user prompts for spelling/descriptor noise.

### 12. Small goal-progress differences

If a linked deposit/payment changes goal progress by a small amount and the allocation itself is already explicit, update the progress silently. Do not ask the user to confirm every `$1-$5` movement.

Still ask before moving money between goals, releasing earmarked money, or changing a goal deadline/priority.

### 13. Safe to Spend micro-movements

Safe to Spend should update numerically as facts change, but a `$2` movement should not create a notification, warning card, or confirmation flow unless it crosses a hard threshold.

### 14. Exact cents vs planning dollars

Keep cents internally for correctness. The primary planning UI may round headline values to whole dollars when appropriate, while transaction detail keeps exact cents. Penny-level variation should never create a decision prompt.

### 15. Date windows

If the user explicitly said `sometime in October`, any actual date inside that window is already consistent with the user's context and needs no confirmation. The bank fact simply resolves the uncertainty.

### 16. Flexible expenses marked `Maybe`

Do not ask repeatedly about a Maybe expense while nothing has changed. Continue using the full expected amount in the baseline forecast. Surface the possible savings as optional information.

### 17. Overdue expected events

A one-day delay inside normal bank/merchant timing noise should not immediately create an intrusive prompt if the event had a date window or recurring date tolerance. Once the event is genuinely outside its allowed/tolerance window, then show the overdue action flow.

### 18. Recurrence learning

Do **not** extend the materiality rule into inventing recurrence. Three similar deposits do not silently become recurring income. Recurrence is a semantic/high-impact property and still requires explicit user confirmation.

### 19. Must-pay / essential / flexibility semantics

Do **not** silently infer or change `must pay`, `essential`, `can cancel`, or similar planning semantics from small transaction differences. These labels can materially alter Safe to Spend and should come from explicit user context or an already confirmed rule.

### 20. Income confidence

Do **not** silently change confidence because an event happened once or missed once. Confidence is explicit user context. Historical outcomes may generate a non-blocking suggestion, but the user owns the confidence assumption.

### 21. Earmarks and reserves

Never silently release, reassign, or create an earmark/reserve based on materiality. A `$2` difference can be absorbed inside an already established allocation, but changing the purpose of money always requires explicit user intent.

### 22. Risk-state exception

Materiality thresholds never suppress a meaningful warning. If a `$2` difference is literally what pushes projected cash below `$0`, below a personal reserve, or causes a must-pay item to become underfunded, surface the problem even though `$2` is normally tiny.

## Product UX principle

The desired experience is:

- **Obvious + small -> assume and continue.**
- **Obvious + material -> update facts, ask only about future-rule changes if needed.**
- **Ambiguous + small -> usually leave unchanged without bothering the user unless it matters.**
- **Ambiguous + material -> ask.**
- **Semantic/high-impact change -> ask regardless of dollar size.**
- **Hard-risk-state change -> surface regardless of dollar size.**

The app should therefore have an `Assumptions & adjustments` / activity trail where silent normalizations can be inspected and edited, rather than using confirmation dialogs as the default interaction pattern.
