# FinancialCore — HackRice judging alignment

This note is for the team, not the production app. It keeps the math workstream focused on the HackRice 16 Finance track instead of adding features for their own sake.

## Finance-track fit

The Finance track emphasizes budgeting/money tracking/planning, personalized actionable insight, goal-based planning, and simple cash-flow forecasting.

FinancialCore directly supports those requirements:

- **Budgeting:** recent variable-spending baseline plus a recommended weekly spending limit.
- **Money tracking:** normalized income/expense events become a dated projected cash path.
- **Personalized insight:** reserve schedules, bank minimums, safety buffers, irregular income, and spending history are user-specific inputs.
- **Goal-based planning:** mandatory goals affect the baseline; flexible goals are evaluated as explicit trade-offs.
- **Cash-flow forecasting:** every decision is checked across the full path rather than only against today's balance or the final balance.

The product-level differentiator is that the app does not ask only “can your current balance pay for this?” It asks whether the purchase remains compatible with the student's future cash path and commitments.

## Technical Rigor

Useful talking points for judges:

- time-dependent personal liquidity floors instead of one static budget number;
- full-path liquidity checks, so later income cannot hide an earlier shortfall;
- irregular, recurring, and one-time income are modeled differently;
- temporary reimbursement liquidity dips are preserved;
- deterministic conservative/expected/optimistic scenarios;
- automatic tests for edge cases and regressions;
- standalone Swift Package cleanly separated from UI/API layers.

Avoid overselling this as prediction or AI. The rigor is in explicit modeling, chronology, scenario handling, and testability.

## Originality & Creativity

The strongest angle is the combination of qualitative student context with deterministic finance math.

Examples of qualitative context that becomes structured math:

- “I need about $8,800 available until March, then I can release $300.”
- “My parents usually send money each semester, but it is not a salary.”
- “This $300 expense gets reimbursed next week.”
- “My account needs $500 to keep its status.”

The qualitative layer interprets/asks for confirmation; FinancialCore receives the normalized result. The math engine itself stays auditable.

## User Experience & Design

UI-ready outputs now include:

- `SAFE / TIGHT / NOT_SAFE` health states;
- path-safe money available now;
- target-date projected cash;
- tightest future date;
- earliest fully safe purchase date;
- daily `CashFlowPoint` values for a financial-health calendar or line chart;
- a recommended weekly spending limit;
- conservative/expected/optimistic purchase outcomes.

A strong demo should visualize the cash path and show one decision changing from safe to tight/not-safe rather than presenting a wall of financial numbers.

## Practicality & Impact

Student finances are often irregular. The engine deliberately handles cases that a standard monthly-budget app can misread:

- no fixed monthly salary;
- family transfers by semester;
- reimbursements;
- variable normal spending;
- changing reserve needs;
- future goals and one-off purchases;
- institutional minimum balances.

The system is designed to re-run as new transactions/context arrive. It should not imply that a four-year forecast is certain based on six weeks of history.

## Relevance

For the Finance track demo, prioritize these flows:

1. Connected/raw banking data becomes normalized cash events.
2. The app learns/asks about irregular context.
3. FinancialCore returns a personalized cash path and safe-to-spend number.
4. User tries a What-If purchase.
5. The app explains the trade-off and, when possible, gives an earliest safer date.

Do not spend hackathon time adding investment recommendations, Monte Carlo, or a black-box purchase-decision model unless every core demo flow is already polished.

## Recommended live-demo story

A concise story for the two-minute live demo:

- Student has enough money in the account to *technically* buy a ticket.
- App knows part of that balance is needed later and that income is irregular.
- Calendar/graph shows the future tight point.
- What-If purchase changes the plan to `TIGHT` or `NOT_SAFE`.
- App shows the exact date/shortfall and suggests when the purchase becomes fully safe.

That demonstrates budgeting, personalized insight, goal planning, forecasting, and actionable guidance in one interaction.
