# Product V1 Cleanup V2 — Xcode handoff

Use branch `product-v1-cleanup-v2` for the integrated iPhone build.

## What is integrated

- Product-focused SwiftUI shell: Home, Calendar, Plans, What If, Context.
- `FinancialCore` remains the deterministic planning/decision engine.
- `FinanceCore` + Nessie provide bank connection, normalized transactions, local cache, refresh, and multi-account sync.
- Linked cash and historical transactions feed the product profile directly.
- Historical bank events remain visible for Context but are not counted again as future cash.
- Context is deterministic, constrained, confirm-before-apply, and grounded in real transactions when a bank is linked.
- The latest `integration/combined-app` history is merged into this branch, while the V2 shell intentionally avoids bringing back financial-weather framing, raw-balance-first UX, and mock technical labels.

## Run on an iPhone from Xcode

1. Checkout `product-v1-cleanup-v2`.
2. Open `Finanzas2026/Finanzas2026.xcodeproj`.
3. Select the `Finanzas2026` scheme.
4. Select Simon's connected iPhone as the run destination.
5. In Signing & Capabilities, select the appropriate Apple development team if Xcode asks for one.
6. Build and Run.
7. In the app, tap the round bank/link button in the upper-right corner.
8. Enter the Nessie API key and Customer ID, then tap Connect.

No Nessie credential is committed to GitHub.

## Product data flow

`Nessie -> FinanceCore normalization/cache -> ProductV2Data -> FinancialProfile -> FinancialCore -> Home / Calendar / Plans / What If`

Context uses the selected normalized bank transaction as its structured anchor and only updates the `FinancialProfile` after user confirmation.

## Validation

The branch workflow runs:

- `swift test --package-path FinancialCore`
- iOS simulator build with `xcodebuild`

The workflow file is configured to validate both `product-v1-cleanup` and `product-v1-cleanup-v2`.
