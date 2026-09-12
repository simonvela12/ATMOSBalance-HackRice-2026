# Product V1.2 handoff

## Recommended branch

Use `product-v1.2` for the next integrated iPhone iteration. Keep `main` and the source branches intact for reference.

## What was reviewed

The branch was built after comparing all current repository branches:

- `product-v1-cleanup-v2`
- `product-v1-cleanup`
- `integration/combined-app`
- `integration/iphone-app`
- `iphone-app-nessie-hardening`
- `financecore-nessie`
- `simon-ios-app`
- `simon-qualitative`
- `ui-design`
- `lucas-math`
- `main`

Most integration, UI-design, qualitative, and hardening branches were already ancestors of V2 or had been superseded there. Two branches still contained unique work worth porting: `financecore-nessie` and `simon-ios-app`. V1.2 incorporates their useful behavior while retaining the newer product shell and deterministic planning engine.

## V1.2 integration decisions

### Banking / Nessie

Kept the hardened provider-independent `FinanceCore` architecture already used by the iPhone app and added the deterministic `DemoBankingProvider` plus the broader Nessie integration test suite. The tests cover authenticated requests, all transaction endpoints, merchant caching, typed API failures, persistence reload, stable fallback identities, malformed payload rejection, and transfer validation.

The old tracked `.env` from the source banking branch is intentionally not copied into the V1.2 tip. API keys must not be committed into the iPhone product branch.

### Financial engine

The latest `FinancialCore` remains authoritative for safe-to-spend, path liquidity, reserve rules, goals, recurring schedules, reimbursements, What-If and qualitative profile updates. No bank or UI code is allowed to duplicate those formulas.

### Qualitative work

Simon's qualitative concepts are represented in `QualitativeMetadata.swift`: category, need level, flexibility, planning status, frequency, priority, income source and confidence bands. Merchant/category suggestions are deterministic and confirmation-only. The previous numeric `cutPriorityScore` was not promoted into the product because it would create an opaque recommendation score that the current product direction explicitly avoids.

### UI / iPhone

The V2 SwiftUI shell remains the product entry point because it is newer than the older mock/weather-oriented shells. It keeps the Nessie `BankAccountStore` integration, uses linked data when available, and labels preview/sample behavior when real banking data is absent.

## CI contract

Every push to `product-v1.2` runs:

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

A green run means the bank layer, planning engine, and iOS shell all compile together.

## Running on Simon's iPhone

1. Checkout `product-v1.2`.
2. Open `Finanzas2026/Finanzas2026.xcodeproj` in Xcode.
3. Select the `Finanzas2026` scheme.
4. Select Simon's attached iPhone as the run destination.
5. Set the Development Team/signing identity if Xcode asks.
6. Build and Run.
7. Use the in-app bank connection flow to enter Nessie sandbox credentials; do not hardcode them in source.

## Product rule going forward

New work should preserve one flow:

`bank transaction → normalized bank data → confirmed Context → FinancialCore → explainable UI`

Avoid reintroducing raw-balance-first dashboards, financial-weather framing, mock metrics presented as real, opaque scores, probability claims, or a second implementation of financial formulas inside SwiftUI.
