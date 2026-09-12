# FinancialCore — judge demo / Q&A notes

The HackRice live slot is short, so the math engine should appear through one visible decision story rather than a list of formulas.

## Recommended 2-minute live demo story

### 0:00–0:20 — Problem

> College students often have irregular income, reimbursements, semester transfers, and money that looks available in their account but is already needed later. A normal balance or monthly budget can say a purchase is affordable even when it breaks the student's future plan.

Show the home screen with connected balance, `safeToSpendNow`, and the future health/calendar.

### 0:20–0:50 — Personalized forecast

Show that the app has interpreted confirmed context:

- current cash;
- recent normal spending;
- irregular/known future income;
- personal reserve/runway;
- bank minimum if relevant;
- upcoming goals.

Point to the cash-flow graph/calendar and the tightest future date.

Key sentence:

> We check the entire cash path, not only today's balance or the final balance.

### 0:50–1:30 — What-If purchase

Try the F1 ticket (or another emotionally clear optional purchase).

Show:

- purchase status: SAFE / TIGHT / NOT_SAFE;
- exact limiting date;
- shortfall or remaining margin;
- deterministic reason;
- earliest fully safe date if the purchase is not yet safe.

Best case for the demo: the purchase itself is technically possible, but a goal changes from SAFE to TIGHT.

> The ticket fits in the account today, but it moves Miami from SAFE to TIGHT because of the student's future commitments.

That demonstrates personalized insight rather than a generic budget warning.

### 1:30–1:50 — Uncertainty

If time permits, show the conservative / expected / optimistic result cards.

Say:

> These are not fake probabilities. They are transparent sensitivity cases: we vary irregular income and recent spending assumptions so the student can see what the decision depends on.

### 1:50–2:00 — Close

> We don't tell students whether they can technically pay for something. We tell them whether they can afford it without breaking the rest of their financial plan.

## 30-second technical explanation for video / Q&A

> Banking and qualitative context are normalized into dated cash events, reserve constraints, spending history, and goals. A standalone Swift engine projects the full cash path, applies personal and institutional liquidity floors plus a safety buffer, and evaluates What-If purchases against every future point. The same engine produces goal trade-offs and conservative/expected/optimistic sensitivity views. The core is deterministic and regression-tested so the explanation in the UI comes from the math rather than an LLM inventing a financial decision.

## Likely judge questions

### Why not just use the current balance?

Because current balance does not encode future bills, dated goals, reserve/runway requirements, or temporary liquidity dips before later income/reimbursement arrives.

### Why check the whole path instead of the final date?

A later deposit cannot retroactively prevent an account from going below a required minimum earlier. The engine therefore uses the tightest future point.

### Why median spending instead of average spending?

A one-off expensive week can distort an average. For the MVP, the median of recent eligible weeks is a simple robust estimate of normal variable spending. Known extraordinary expenses are modeled separately.

### How do you handle irregular income?

The expected view uses a user/upstream confidence on explicitly-entered irregular income. Conservative ignores it; optimistic assumes that entered event arrives in full. Past one-time transfers are never extrapolated.

### Is this AI deciding whether I can buy something?

No. AI/context can help interpret transactions or ask the user what is recurring, reimbursable, or expected. The purchase decision itself is deterministic and auditable.

### What happens as the student's situation changes?

The forecast is rolling. New transactions, spending history, confirmed income expectations, goals, and reserve steps produce a new profile and the engine recalculates. We do not pretend a few weeks of history precisely predicts several years.

### How does Nessie fit?

Nessie supplies/mock-simulates banking-side data. That data is normalized upstream into the `FinancialProfile`; FinancialCore is intentionally independent of the API so the same math can later work with a real account aggregator.

### What is technically challenging here?

The challenge is not a single formula. It is preserving chronology and constraints across heterogeneous cash events: irregular income, changing reserve floors, account minimums, normal spending, reimbursements, mandatory/flexible goals, full-path purchase checks, and goal-aware counterfactuals — while keeping the result explainable and testable.

## What not to spend demo time on

- implementation details of percentile interpolation;
- every edge case/test;
- Monte Carlo or ML ideas that are not in the MVP;
- investment recommendations;
- a long settings flow.

The visible product story should be: **raw finances -> personalized plan -> one actionable decision -> explainable trade-off.**
