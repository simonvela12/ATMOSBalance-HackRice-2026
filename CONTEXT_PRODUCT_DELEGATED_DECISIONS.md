# Context Product Decisions — Delegated Batch

Working branch: `product-v1.2-context-design`

This file extends `CONTEXT_PRODUCT_SPEC.md`.

The user explicitly asked the assistant to continue the remaining product-design questions by assuming the answers that best fit the product principles already established. These decisions should therefore be treated as approved product direction unless the user later explicitly changes one of them. If a future explicit user decision conflicts with this file, the newer explicit decision wins.

## Decision rules used for this batch

- College-student-first: irregular, sparse, lumpy cash flow is normal.
- Event-based, not salary-based.
- Never invent income, recurrence, dates, amounts, reimbursements, or savings.
- Prefer conservative treatment when the alternative would overstate spendable cash.
- Bank facts and user-confirmed context remain distinguishable.
- Suggestions may be automatic; plan-changing actions require confirmation when identity or intent is uncertain.
- Actual bank facts do not get rewritten by planning edits.
- Safe to Spend must respect reserves, earmarks, mandatory obligations, and the dated cash path.
- Explanations should stay deterministic and human-readable.

## Delegated questions and approved answers

### 16. How should flexible goals be funded?

**Question:** For a goal such as `$900 for a December trip`, should the app require the full amount only at the target date, reserve money gradually, or support both?

**Answer:** Support both. The default is **target-date funding**: the plan only requires the money to be available by the target date. The user can optionally enable **Save gradually**, which creates a suggested weekly or monthly reservation path based on the remaining unfunded amount and time left. This is a planning reservation, not a fake bank transaction, and it can be turned off or edited.

### 17. What counts as progress toward a goal?

**Question:** Should earmarked income or user-confirmed allocations count toward a goal automatically?

**Answer:** Yes, when the user explicitly allocates funds to that goal. Earmarked money assigned to the goal counts toward its funded amount. General cash is never silently assigned to a goal. The same dollar cannot fund two goals at once.

### 18. What happens when several goals compete for limited cash?

**Question:** How should the app prioritize multiple goals when they cannot all be funded safely?

**Answer:** Protect the personal reserve, hard minimums, must-pay expenses, and mandatory goals first. Then use the user's explicit goal priorities. Flexible goals are the first to slip or be postponed rather than violating a hard cash floor. The app should explain which goal is causing the conflict and why.

### 19. What happens when a goal is completed early or has excess earmarked money?

**Question:** If a goal is already fully funded, should extra earmarked money become free cash automatically?

**Answer:** No. Stop creating additional gradual-saving reservations once the goal is fully funded. If earmarked money is left over, ask the user to **Move to General cash / Reassign / Keep reserved**. Never release it silently.

### 20. How should edits to a recurring rule work?

**Question:** If the user changes a recurring item, should the edit affect one occurrence or the whole series?

**Answer:** Offer **This occurrence / This and future occurrences / Entire rule where still uncompleted**. Historical bank transactions and already completed occurrences remain historical facts and are never rewritten by editing a recurrence rule.

### 21. Can a recurring item be skipped or paused?

**Question:** What if rent, a subscription, campus work, or another recurrence temporarily stops?

**Answer:** Support **Skip this occurrence** and **Pause recurrence** without deleting the rule. A paused rule stops generating future occurrences until resumed. Skipping one occurrence does not alter the cadence of the rest of the series unless the user explicitly changes it.

### 22. What happens when expected income never arrives?

**Question:** If an expected income date or its latest date passes without a matching deposit, should the app assume the money arrived?

**Answer:** No. Never treat unobserved income as received. Mark it **Overdue / Not confirmed** and ask the user to **Update date / Mark as missed / Cancel / Link to a transaction**. Current cash still comes from actual bank balances, so overdue expected income must not silently inflate cash.

### 23. What happens when a planned expense date passes with no matching bank transaction?

**Question:** Should the expense disappear?

**Answer:** Not automatically. A **must-pay** expense remains due and should be treated as an immediate obligation until the user marks it paid, reschedules it, links it to a transaction, or explicitly cancels it. For optional/flexible expenses, ask whether the expense is still planned before continuing to carry it forward.

### 24. Can reimbursements arrive in multiple payments?

**Question:** What if a `$180` shared expense is reimbursed as `$60 Friday + $60 next week`, with the rest never reimbursed?

**Answer:** Support multiple reimbursement installments. Each installment has its own amount and exact date or date window, and may have its own confidence if timing/arrival is uncertain. The total reimbursement may be less than the original expense. The original cash dip remains on the original transaction date.

### 25. What happens when a reimbursement is late?

**Question:** Should a promised reimbursement be considered received once its date passes?

**Answer:** No. Use the same overdue logic as expected income: **Update date / Mark as missed / Cancel / Link to actual repayment**. A late reimbursement cannot silently increase current cash.

### 26. How should transfers between the user's own accounts be treated?

**Question:** Is moving `$500` from checking to savings income and spending?

**Answer:** No. Transfers between the user's own linked accounts are internal cash movements, not income or consumption. They should net to zero in the aggregate plan and must not distort spending history or Safe to Spend.

### 27. How should credit-card purchases and card payments be treated?

**Question:** If both the card and checking account are linked, should a card purchase and the later card payment both count as expenses?

**Answer:** No. The underlying purchase is the expense. A payment from the user's checking account to the user's own credit-card account is a transfer/debt settlement and should not become a second copy of the expense. If only one side is visible, the app should avoid making an aggressive classification and allow the user to correct it.

### 28. Can users add cash/off-bank activity?

**Question:** What about cash income, cash spending, Venmo-like activity not available through the bank feed, or money expected outside linked accounts?

**Answer:** Yes. Allow manual income/expense events and manual historical cash events. They must be clearly labeled **Manual** and remain distinguishable from bank-sourced transactions.

### 29. How should multiple bank accounts appear in the product?

**Question:** Should the user see one combined plan or separate plans per account?

**Answer:** Both. The default financial plan aggregates all selected accounts so the user sees total liquidity and one Safe to Spend number. The user can drill into each account. Internal transfers between included accounts net to zero at the aggregate level.

### 30. What happens when an account is unlinked?

**Question:** Should unlinking a bank account delete everything associated with it?

**Answer:** No. Unlinking stops future synchronization. Historical bank records and user-confirmed context should not be silently destroyed. If the user wants imported history removed, require an explicit destructive action and clearly explain what downstream context/links will be affected.

### 31. What is the source-of-truth precedence when bank data and planning data disagree?

**Question:** Which data wins?

**Answer:** Use this precedence: **actual linked-bank facts > user-confirmed planning/context > automatic suggestions**. Once a planned occurrence is confirmed as matching a real transaction, the real amount/date become the historical fact for that occurrence. Automatic suggestions never overwrite explicit user input.

### 32. Should the app claim data is real-time?

**Question:** What if bank synchronization is polling or delayed?

**Answer:** Never overclaim. Show **Last synced**, current sync state, and errors. The UI may say near-real-time only if the implementation genuinely supports it. Otherwise display the actual freshness of the data.

### 33. How should pending bank transactions affect the plan?

**Question:** Should pending activity be ignored completely?

**Answer:** Show it separately as **Pending**, never as finalized history. Pending outgoing transactions should conservatively reduce free/spendable cash when the provider amount is reliable, so Safe to Spend is not overstated. Pending incoming transactions should not become spendable cash until posted, unless the user separately modeled them as expected income. When a pending transaction posts, provider-level identity/deduplication should replace the pending copy rather than count both.

### 34. Which scenario should the main UI use by default?

**Question:** Conservative, Expected, or Optimistic?

**Answer:** Default to **Expected**, because explicit confidence and ranges already make it risk-adjusted and usable. Always provide a one-tap **Conservative / Expected / Optimistic** view. If Conservative materially reduces Safe to Spend or reveals a shortfall, surface that clearly. Hard reserves and mandatory floors are never relaxed just because the user switches scenario.

### 35. What if an income has both amount variability and arrival uncertainty?

**Question:** How should range and confidence combine without becoming opaque?

**Answer:** Keep the two concepts separate and visible. **Amount range** describes how much arrives if the event occurs; **confidence** describes whether an uncertain event occurs. For an uncertain non-recurring income, Conservative may use `$0`, Expected uses the user-entered expected amount weighted by explicit confidence, and Optimistic may use the high/maximum amount at full occurrence. The UI should show the arithmetic rather than hide it.

### 36. What should What-If support?

**Question:** Only one-time purchases, or recurring commitments too?

**Answer:** Both. What-If should support a one-time purchase and a new recurring commitment/subscription. It must run through the same dated cash path and respect earmarks, reserves, must-pay expenses, goals, recurrence end dates, and selected scenario.

### 37. How should automatic categories and merchant corrections work?

**Question:** Can the app learn that a merchant is Food, Transportation, Subscription, etc.?

**Answer:** Yes, as a deterministic suggestion. The user can correct it. A previously confirmed merchant mapping can make future suggestions stronger, but category/merchant learning must not silently create recurrence, change amounts, or alter must-pay/flexibility semantics.

### 38. What if the merchant or category is unknown?

**Question:** Should an unclassified transaction be excluded from planning?

**Answer:** No. Its cash effect is still real and must be included where appropriate. Unknown qualitative metadata should not block the transaction from affecting cash/history; the app can ask for context only when that context changes planning semantics.

### 39. Should recurrence support custom cadences beyond weekly/biweekly/monthly?

**Question:** What about every 3 weeks, every 2 months, quarterly, or semester-specific payments?

**Answer:** Keep **Weekly / Every 2 weeks / Monthly** as the fast MVP choices, but support an advanced **Custom recurrence** in the model/UI when needed. Custom recurrence must still require an explicit start/next date and may have an optional end date. Never infer it from history alone.

### 40. What planning horizon should users see?

**Question:** How far ahead should the product plan?

**Answer:** Default to a practical **90-day** horizon, with quick views for **30 days / 90 days / Semester** and an advanced custom horizon. The same engine should evaluate the entire selected path, not only the endpoint.

### 41. What should trigger notifications or prompts?

**Question:** Should the app send lots of generic financial reminders?

**Answer:** No. Prioritize actionable events: an overdue expected income/reimbursement, upcoming projected reserve breach, a must-pay obligation at risk, a strong planned-vs-actual match needing confirmation, a clearly matched recurring-price change, or a gradual goal falling materially behind. Avoid generic engagement spam.

### 42. How should borrowed money be represented?

**Question:** Should student-loan disbursements or other borrowed cash look like ordinary income?

**Answer:** No. They still increase cash when received, but should be labeled as **borrowed funds**, not earnings. They can be earmarked, for example to Tuition or Living expenses. Do not infer recurrence. Debt-management features can remain outside the MVP, but the source must not be misrepresented.

### 43. How should refunds, reversals, and chargebacks be represented?

**Question:** Is a refund ordinary new income?

**Answer:** No. If it can be linked to an original expense, show it as a **refund/reversal** tied to that expense. It increases cash on the actual refund date but is not treated as a new recurring income source. Ambiguous matches require confirmation.

### 44. What happens when the user is already below reserve or has negative cash?

**Question:** Can Safe to Spend become negative?

**Answer:** The displayed Safe to Spend floor remains `$0`, but the product must separately show the **shortfall amount and earliest problem date**. Flexible goals and optional spending should be deprioritized first; the app must not hide the deficit behind a zero.

### 45. Can historical context be corrected later?

**Question:** What if the user later realizes a transaction was categorized or interpreted incorrectly?

**Answer:** Yes. The user can edit labels, category, reimbursement links, and other context. The underlying bank amount/date/source remain immutable bank facts. Recomputations should be deterministic and the product should make clear what changed.

### 46. Should Safe to Spend have a “Why?” explanation?

**Question:** Should users be able to understand exactly why the number is what it is?

**Answer:** Yes. Provide a human-readable breakdown such as **Current cash → expected income → must-pay expenses → variable-spending allowance → goals → reserve → lowest cash point → Safe to Spend**. When a scenario or user-context assumption changes the number, show that assumption explicitly.

### 47. What happens when the user deletes or cancels a context item?

**Question:** Should deletion happen immediately with no explanation?

**Answer:** If the item affects the future plan, show a concise impact preview before the destructive action, for example: **“Removing this $900 tuition expense increases Safe to Spend by $X and removes the Oct 15 obligation.”** Then require confirmation. Historical bank facts themselves are not deletable through Context.

### 48. How should duplicate transactions be handled?

**Question:** What if the provider sends the same transaction twice or a pending transaction later posts?

**Answer:** Deduplicate using stable provider identity plus deterministic fallback identity. Pending-to-posted transitions should resolve to one economic transaction. Never make the user fix provider duplicates manually when the system can prove they are the same item.

### 49. What date semantics should financial events use?

**Question:** Should timezone conversion be able to shift a tuition/rent event to another calendar day?

**Answer:** Planning dates are user-local **calendar dates**, effectively all-day financial events unless a provider transaction has a real timestamp. Recurrence and deadlines should not drift by timezone conversion.

### 50. How should grants, scholarships, stipends, and family support be modeled?

**Question:** Are they assumed to be monthly salary-like income?

**Answer:** No. Treat each according to what the user actually knows: one-time, recurring, irregular, exact date or date window, confidence, and optional earmark. A scholarship for a semester can be a one-time or term-based event; it never becomes recurring just because something similar appeared historically.

## Resulting implementation posture

The product should now be designed around a single explainable financial event model that can represent actual bank facts, manual facts, future expectations, recurrence, ranges, confidence, earmarks, goals, reimbursements, and matches between planned and actual events without double counting.

The UI can stay simple by keeping advanced fields collapsed until needed. Complexity belongs in the model and deterministic engine, not in forcing every user through a long form.

`CONTEXT_PRODUCT_SPEC.md` remains the base specification. This delegated decision batch adds decisions 16–50 and should be incorporated into the implementation plan before coding the next Context iteration.
