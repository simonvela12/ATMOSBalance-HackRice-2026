# Hackathon2026 — Product V1.2

`product-v1.2` is the integrated product branch for the iPhone demo.

## Product

The app is a college-student money-planning tool for irregular income. Linked-bank data provides current cash and transaction history; qualitative Context adds user-confirmed meaning; `FinancialCore` then produces deterministic, explainable planning outputs including safe-to-spend, future cash health, goals, calendar risk, and purchase What-If.

## Architecture

```text
Nessie / Demo provider
        ↓
FinanceCore
(sync, normalization, persistence, multi-account handling)
        ↓
BankAccountStore / iOS adapter
        ↓
user-confirmed Context
        ↓
FinancialCore
(deterministic cash path, reserves, goals, What-If)
        ↓
SwiftUI product shell
(Home / Calendar / Plans / What-If / Context)
```

`FinanceCore` owns bank-provider concerns. `FinancialCore` owns planning semantics and must remain provider-independent. The SwiftUI shell should not duplicate either layer's formulas.

## Qualitative transaction context

V1.2 incorporates the useful parts of the qualitative tagging work: spending category, need level, expense flexibility, planning status, frequency, user priority, income source kind, and explicit confidence bands. Deterministic merchant/category suggestions are confirmation defaults only; they never silently change the plan. The earlier opaque cut-priority score is intentionally not used by the product engine.

## Validation

The V1.2 workflow validates all three integration layers on macOS:

1. `swift test` — banking `FinanceCore`, including Nessie integration coverage.
2. `swift test --package-path FinancialCore` — planning engine and Context semantics.
3. `xcodebuild` for `Finanzas2026/Finanzas2026.xcodeproj` — the actual iOS product shell.

## Xcode / iPhone

Checkout `product-v1.2`, open `Finanzas2026/Finanzas2026.xcodeproj`, select the `Finanzas2026` scheme and an attached iPhone, choose the appropriate Development Team if Xcode asks, and Run. No API key is committed in this branch; Nessie credentials are entered at runtime through the connection flow.

See `PRODUCT_V1_2_HANDOFF.md` for the integration decisions and branch map.
