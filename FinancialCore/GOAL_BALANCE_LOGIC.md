# Goal contribution and balance semantics

This document defines how the goal engine and the banking/account layer should interact.

## 1. Goal progress is not inferred from income

A paycheck, deposit, refund, or other inflow does **not** automatically increase a goal's saved amount.

`Goal.amountAlreadyPaid` is the source of truth for money the user has actually assigned/saved toward the goal.

The engine uses the user's overall financial capacity to generate recommendations such as required daily, weekly, and monthly saving. If the user saves less than the previous recommendation, the next evaluation starts from the lower real `amountAlreadyPaid` with fewer days remaining, so the recommended saving rate increases automatically.

Example:

- Goal: $1,000 in 100 days
- Initial real progress: $0
- Initial recommendation: $10/day
- Ten days later the user has only assigned $50 instead of the implied $100
- Remaining: $950
- Remaining time: 90 days
- New recommendation: ~$10.56/day

No transaction is automatically moved into the goal.

## 2. Two balances

The product should expose two different concepts.

### Total balance

`FinancialBalanceSummary.totalBalance`

This is the signed sum of all normalized account balances supplied by the banking layer.

Conventions:

- checking/savings assets: positive
- liabilities such as credit-card debt: negative

The Nessie/Plaid adapter is responsible for normalizing provider-specific balance semantics before creating `AccountBalanceSnapshot` values.

### Liquid balance

The liquid view answers a different question: **how much money can the user realistically treat as available?**

The calculation starts from balances marked `isLiquid == true` and protects money needed for:

1. personal/emergency reserves;
2. institutional minimum balances;
3. the safety buffer derived from spending history;
4. committed expenses due in the short-term horizon;
5. mandatory goals due in the short-term horizon;
6. recommended short-term contributions toward other active goals.

The default short-term horizon is 30 days and is configurable.

The summary exposes both stages:

- `liquidBalanceBeforeGoalPlan`: after reserves + committed obligations + mandatory goal payments;
- `liquidBalanceAfterGoalPlan`: also subtracts recommended contributions for non-mandatory goals;
- `spendableLiquidBalance`: clamped at zero for UI display;
- `liquidShortfall`: how far below zero the full short-term plan would be.

## 3. Goal contribution breakdown

`FinancialBalanceSummary.shortTermGoalContributions` gives one entry per active unfinished goal.

Each entry includes:

- goal ID/name;
- deadline;
- priority;
- flexibility;
- remaining amount;
- required weekly saving;
- recommended contribution over the configured short-term horizon;
- current goal status;
- whether the contribution is already protected in the liquid balance.

A 30-day recommended contribution is generally:

`requiredDailySavings * min(30, daysRemaining)`

capped at the remaining goal amount.

This is a recommendation only. It does not mutate `Goal.amountAlreadyPaid`.

## 4. Avoiding double counting

Mandatory goals due inside the short-term horizon are already included in `mandatoryGoalPaymentsDue` and removed from `liquidBalanceBeforeGoalPlan`.

They still appear in `shortTermGoalContributions` for UI explanation, but are marked `alreadyProtectedInLiquidBalance = true` and are not subtracted again when calculating `liquidBalanceAfterGoalPlan`.

## 5. Banking integration contract

The banking ingestion layer should provide normalized account snapshots:

```swift
AccountBalanceSnapshot(
    id: "checking-1",
    name: "Checking",
    balance: 1800,
    isLiquid: true
)
```

Credit-card debt should be normalized with a negative signed balance and normally `isLiquid = false`:

```swift
AccountBalanceSnapshot(
    id: "credit-1",
    name: "Credit Card",
    balance: -420,
    isLiquid: false
)
```

The account adapter should not contain goal logic. Nessie/Plaid normalize provider data; `FinancialBalanceEngine` and `SmartGoalEngine` perform financial planning.

## 6. Recommended UI interpretation

A UI can display:

- **Total balance** — overall signed value across accounts;
- **Liquid balance** — cash realistically available after protected commitments;
- **Protected for bills/reserve** — reserve + committed short-term obligations;
- **Goal plan (next 30 days)** — per-goal recommended contributions;
- **Spendable** — final non-negative spendable liquid balance.

This distinction prevents the app from telling a user that their full bank balance is safe to spend simply because the cash physically exists in an account.
