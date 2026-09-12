# Hackathon2026 — current product

**Canonical product branch:** `product-v1.4-clean-integration`

Use this branch for the integrated iPhone app. Older Lucas/OpenAI experiment branches are obsolete; they should not be used as a source of truth.

## What the app does

This is a visual financial-planning app for students with irregular income. It combines linked-account data with user-entered plans and qualitative context to show:

- current cash from linked accounts
- forecasted financial weather and cash path
- editable future income and expenses
- goals with priority/flexibility and progress guidance
- personal cash reserve
- purchase What-If analysis
- confirm-first Context for information the bank cannot infer

Bank facts come from `FinanceCore`. Planning, goals, Context semantics and deterministic financial calculations live in `FinancialCore`. The SwiftUI app consumes those shared engines rather than reimplementing the math in the UI.

## Run on iPhone

1. Checkout `product-v1.4-clean-integration`.
2. Open `Finanzas2026/Finanzas2026.xcodeproj`.
3. Select scheme `Finanzas2026`.
4. Select the connected iPhone and choose a Development Team if Xcode asks.
5. Run the app.
6. Use the profile/account connection flow to enter the Nessie access key and customer ID at runtime.

No bank credential is committed to GitHub.

## Validation

The canonical branch runs one workflow, **Product Validation**, which must pass all three checks:

```bash
swift test
swift test --package-path FinancialCore
xcodebuild \
  -project Finanzas2026/Finanzas2026.xcodeproj \
  -scheme Finanzas2026 \
  -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO \
  build
```

## Repository map

- `Finanzas2026/` — iOS app and Xcode project
- `Sources/FinanceCore/` — bank/Nessie sync, normalization and persistence
- `FinancialCore/` — deterministic planning, goals, Context and What-If engine
- `Tests/` and `FinancialCore/Tests/` — banking and planning tests
- `SETUP.md` — setup details
- `ARCHITECTURE.md` — current architecture

### Product rule

Do not invent financial facts. Bank data stays bank data; uncertain future information is explicit and user-confirmed. If missing information could materially change financial safety, ask rather than guess.
