# Product V1.2 handoff

## Recommended branch

Use `product-v1.2` for the integrated iPhone demo and the next product iteration. Keep `main` and all source branches intact for reference.

## Repository review

V1.2 was reviewed against every current branch:

- `main`
- `ui-design`
- `simon-ios-app`
- `simon-qualitative`
- `financecore-nessie`
- `integration/iphone-app`
- `integration/combined-app`
- `iphone-app-nessie-hardening`
- `lucas-math`
- `product-v1-cleanup`
- `product-v1-cleanup-v2`

The final V1.2 history includes the latest team branch tips that contained unique work. Where branches had diverged, the V1.2 tree keeps the newer or safer implementation rather than replacing it with an older copy.

## Integration decisions

### Banking / Nessie

`FinanceCore` is the provider-independent bank layer. V1.2 keeps the hardened Nessie client, typed errors, configurable timeout, merchant enrichment fallback, stable transaction identity, multi-account synchronization, deduplication, persistence, and partial-account failure handling. The deterministic `DemoBankingProvider` is also included and now has an explicit test proving it goes through the same production `BankSyncService` path and deduplicates correctly.

No `.env` or API key is committed in V1.2. Nessie credentials are entered at runtime in the iPhone connection sheet.

### Financial engine

`FinancialCore` remains the single source of truth for safe-to-spend, dated cash-path health, reserves, goals, recurring schedules, reimbursements, What-If, diagnostics, and Context application. Historical bank transactions stay available for grounding but are not counted again as future cash flow.

The newer recurring-schedule and qualitative work from `lucas-math` is retained in the V1.2 tree; the branch history is also connected so the source work remains traceable.

### Qualitative context

Simon's qualitative concepts are represented as explicit metadata: spending category, need level, flexibility, planning status, frequency, priority, income source kind, and confidence bands. Merchant/category suggestions are deterministic defaults only. They require confirmation before changing the financial plan.

The old numeric `cutPriorityScore` was intentionally not made authoritative because it would introduce an opaque recommendation score. V1.2 instead preserves explicit, explainable fields.

### UI / iPhone

The SwiftUI product shell is the V2 cleanup shell rather than the older mock/weather-first UI. It exposes Home, Calendar, Plans, What-If, and Context from one shared `FinancialProfile`, consumes normalized bank data through `BankAccountStore`, and clearly distinguishes linked data from preview/sample behavior.

The app target imports both local packages:

- `FinanceCore` — bank connection, normalization, persistence
- `FinancialCore` — deterministic planning engine

## CI contract

Every push to `product-v1.2` must pass all three layers:

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

The workflow uses `actions/checkout@v5` and validates the exact Xcode project Simon will run.

## Run on Simon's iPhone

1. Checkout `product-v1.2`.
2. Open `Finanzas2026/Finanzas2026.xcodeproj` in Xcode.
3. Select the `Finanzas2026` scheme.
4. Select the attached iPhone as the run destination.
5. Set the Development Team/signing identity if Xcode requests it.
6. Build and Run.
7. Open the bank connection button in the app and enter Nessie sandbox `apiKey` + `customerID` at runtime.

## Product rule going forward

Preserve one explainable flow:

`bank transaction → normalized bank data → confirmed Context → FinancialCore → Home / Calendar / Plans / What-If`

Do not reintroduce raw-balance-first dashboards, financial-weather framing, demo metrics presented as live data, opaque scores, probability claims, hardcoded secrets, or a second implementation of financial formulas inside SwiftUI.
