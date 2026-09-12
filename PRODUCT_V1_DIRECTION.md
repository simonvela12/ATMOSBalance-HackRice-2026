# Product V1 direction

This branch is a non-destructive product cleanup built from Mark's latest `ui-design` branch.

The original `ContentView.swift` remains untouched as a visual reference. The app entry point now uses `ProductRootView`, which keeps the weather aesthetic only where it communicates real financial health.

## Product promise

A college student connects financial accounts, explains context the bank cannot know, and receives an understandable answer to:

- How am I doing?
- How much can I safely spend?
- What happens if I buy something?
- Does that choice hurt a goal?
- When would the choice become safer?

## User-facing structure

1. **Home** — safe-to-spend is the main number; balance is not treated as free cash.
2. **Calendar** — SAFE / TIGHT / NOT SAFE is represented as financial weather. Large spending does not automatically mean a bad day.
3. **Plans** — goals show their health and whether they are mandatory or flexible.
4. **What If** — uses the real deterministic engine and shows goal trade-offs.
5. **Context** — free text for information a bank cannot know. The local rule interpreter explains what it understood before applying it.

## Things intentionally not exposed as product concepts

- `FinancialCore` is an internal Swift package name only.
- no FinancialCore smoke-test screen in the product navigation;
- no `Mock daily total` or placeholder copy claiming the engine is not connected;
- no daily-spending average as the primary success metric;
- no `financial weather score` with invented math;
- no AI claim for deterministic rules;
- no requirement that users understand internal tags such as `needLevel`, `flexibility`, or `planningStatus`;
- no assumption that current account balance equals spendable money.

## Architecture

```text
Nessie / bank transactions
        ↓
transaction context + deterministic qualitative interpretation
        ↓
normalized FinancialProfile
        ↓
FinancialCore
        ↓
Home / Calendar / Plans / What If
```

The qualitative layer supplies meaning. The deterministic engine decides the financial consequence. The UI explains the result without inventing financial reasoning.

## Integration note

This branch includes the `FinancialCore` Swift package directly from `lucas-math` and references it as a local package from the Xcode project. When Simon's combined V1 is pushed, use this branch as a product/UX reference and reconcile its screens with the combined branch rather than overwriting teammates' work.
