# Architecture

Four layers, four owners. The point of the boundaries is that we can all work at
once without editing the same files.

```
Nessie  →  FinanceCore  →  AppFinancialData  →  FinancialCore  →  LiveFinancialContext  →  ContentView
           (Carlos)        (integration)        (Lucas)           (integration)            (Marc)
```

## Layers

### `Sources/FinanceCore` — banking. Owner: Carlos

Talks to Nessie, normalises what comes back, persists it. Knows nothing about
goals, safe-to-spend, or the UI.

Hands out `FinancialAccount`, `FinancialTransaction`, `SyncResult`, `BankingError`.
Money is integer minor units, never `Double`.

### `FinancialCore/` — the engine. Owner: Lucas

Takes a `FinancialProfile` and decides consequences: safe-to-spend, the cash-flow
timeline, goal health, purchase what-ifs. Deterministic, no networking, no parsing
of raw bank data.

Takes `FinancialProfile`. Hands out `FinancialDashboardSnapshot`, `CashFlowPoint`,
`GoalPlanAssessment`, `PurchaseWhatIfAnalysis`, `FinancialHealthStatus`.

### `Finanzas2026/Finanzas2026/ContentView.swift` — the design. Owner: Marc

Every screen, every component, all styling and animation. Consumes view-ready
values and renders them.

It does no financial arithmetic. If a number needs working out, it belongs one
layer down.

### Integration — the seams. Owner: Simon

Four files, and they are the only places where one layer is translated into another:

| File | Does |
| --- | --- |
| `BankAccountStore.swift` | Owns sync state and the linked-bank connection. The only `ObservableObject` the UI sees. |
| `AppFinancialData.swift` | Bank transactions + the user's plan → `FinancialProfile`. Also `SavingsAccrual`. |
| `LiveFinancialContext.swift` | Engine output + bank history → per-day figures the forecast views render. No view code. |
| `GeminiExplainer.swift` | Turns a decision the engine already made into a sentence. Never decides anything. |

## Rules that keep the seams honest

1. **The UI never does financial maths.** If a view computes a figure, that figure
   is unreviewed and untested. It belongs in the engine or the integration layer.
2. **The engine never parses bank data.** It receives normalised, already-decided
   inputs. It should not know Nessie exists.
3. **Banking never decides health.** SAFE / TIGHT / NOT_SAFE comes from
   `FinancialCore` and nowhere else.
4. **AI never decides.** Gemini is given a verdict and asked to word it. It is told
   not to re-judge and not to introduce numbers. If it is unreachable, the screen
   still works.
5. **Nothing is seeded.** No placeholder goals, no sample bills, no assumed reserve.
   An account with no plan has no plan, and the forecast says so.

## Working in parallel

- **Carlos** changes `Sources/FinanceCore` freely. If the shape of `FinancialAccount`
  or `FinancialTransaction` changes, `AppFinancialData` is the only app file that
  needs updating.
- **Lucas** changes `FinancialCore` freely. If engine outputs change,
  `LiveFinancialContext` and `WhatIfSheet` are the consumers.
- **Marc** changes `ContentView.swift` freely. Integration logic was deliberately
  moved out of that file so his pushes do not collide with engine wiring.
- **Simon** owns the four integration files and reconciles the rest.

The one shared file is `ContentView.swift`, because `UserPlan`, `PlanPersistence`
and the sheets that read them sit beside the private types they persist. Coordinate
before restructuring it.

## Where numbers come from

| Shown | Source |
| --- | --- |
| Account balances, available cash | `BankAccountStore` ← FinanceCore |
| Recorded days in the forecast | Linked-bank transactions |
| Future days, projected cash, weather | `FinancialCore.cashFlowTimeline` |
| Safe-to-spend | `FinancialInsights.dashboard` |
| Goal progress | User's target + savings accrued from underspending |
| What-If verdict | `FinancialInsights.analyzePurchaseWhatIf` |
| What-If wording | Gemini, from that verdict |
