# Deterministic scenarios — conservative / expected / optimistic

This layer is intentionally simple. It does **not** use machine learning or Monte Carlo simulation.

Its purpose is to answer a practical question:

> If uncertain income arrives less than expected, or normal spending is a little higher than usual, does the plan still work?

The core financial engine stays deterministic. We simply feed it three different, transparent assumptions.

---

## 1. Income assumptions

Known recurring and explicitly-known one-time payments are treated the same in all scenarios.

Irregular income changes by scenario:

- **Conservative:** count `$0` from irregular income.
- **Expected:** count `amount × confidence`.
- **Optimistic:** count the full explicitly-entered irregular amount.

Example:

- tutoring event = `$1,000`
- confidence = `0.60`

Then:

- conservative = `$0`
- expected = `$600`
- optimistic = `$1,000`

The point is not to predict the future perfectly. The point is to show how dependent the user's plan is on uncertain income.

---

## 2. Spending assumptions

We use the user's eligible weekly variable-spending history.

Instead of inventing arbitrary +/- percentages, scenarios use history-based percentiles:

- **Conservative:** 75th percentile weekly spending
- **Expected:** 50th percentile / median weekly spending
- **Optimistic:** 25th percentile weekly spending

This means conservative assumes a somewhat more expensive week than normal, while optimistic assumes a somewhat cheaper week.

Example weekly history:

`80, 95, 87, 92, 410, 90`

Sorted:

`80, 87, 90, 92, 95, 410`

Using linear percentile interpolation:

- optimistic (25th percentile) = `$87.75/week`
- expected (median) = `$91/week`
- conservative (75th percentile) = `$94.25/week`

The unusual `$410` week remains in the history unless the upstream layer marks it extraordinary. The main v2 flow is expected to exclude known one-off weeks before they reach this calculation.

---

## 3. Safety buffer

Each scenario uses its own weekly-spending assumption inside the existing safety-buffer rule:

`safetyBuffer = max(manualMinimum, scenarioWeeklySpending × weeksOfCoverage)`

So a conservative scenario naturally carries a slightly larger buffer when recent spending history supports it.

---

## 4. Hard constraints do not change

The following do **not** become easier just because the scenario is optimistic:

- personal reserve schedule
- institutional minimum balances
- committed expenses
- mandatory goals

Those are treated as real constraints, not uncertain guesses.

---

## 5. Example purchase that changes by scenario

Suppose:

- current cash = `$1,000`
- personal reserve = `$500`
- safety buffer = `$100`
- possible side income = `$300`
- confidence = `0.30`
- side income arrives before the purchase date
- planned purchase = `$550`

### Conservative

Irregular income counted = `$0`

Before purchase:

- projected cash = `$1,000`
- hard headroom = `1000 - 500 = $500`
- recommended headroom = `500 - 100 = $400`

After `$550` purchase:

- hard headroom = `500 - 550 = -$50`

Result: **NOT_SAFE**

### Expected

Irregular income counted = `300 × 0.30 = $90`

Before purchase:

- projected cash = `$1,090`
- hard headroom = `1090 - 500 = $590`
- recommended headroom = `590 - 100 = $490`

After `$550` purchase:

- hard headroom = `$40`
- recommended headroom = `-$60`

Result: **TIGHT**

### Optimistic

Irregular income counted = `$300`

Before purchase:

- projected cash = `$1,300`
- hard headroom = `1300 - 500 = $800`
- recommended headroom = `800 - 100 = $700`

After `$550` purchase:

- recommended headroom = `$150`

Result: **SAFE**

The app can therefore explain:

> This purchase is safe only if the uncertain side income arrives. Under the expected case it leaves you inside your recommended buffer, and under the conservative case it breaks your minimum reserve.

That is more useful than a single unexplained yes/no.

---

## 6. What the UI can show

For a What-If purchase, the UI can display three compact outcomes:

- Conservative: NOT_SAFE
- Expected: TIGHT
- Optimistic: SAFE

The math engine should return the numbers behind each status so the explanation is generated from facts rather than invented by an LLM.

---

## 7. What this is not

This is not probability simulation.

We are not claiming:

- a 25% probability of the optimistic case;
- a 50% probability of the expected case;
- a 75% probability of the conservative case.

The percentiles apply only to historical spending assumptions. The scenario labels are stress-test views of the same plan.

For the HackRice MVP, this gives us uncertainty awareness while keeping the entire engine deterministic, explainable, and easy to translate into UI.
