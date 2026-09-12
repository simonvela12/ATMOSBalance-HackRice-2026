# Product V1.4 integration ownership

This branch is intentionally integrated by responsibility rather than by whole-branch conflict resolution.

- **UI / UX:** latest `ui-design` from Marc is authoritative for visible structure, layout, calendar/goals presentation and interaction patterns.
- **Goals math:** latest `goals_logic` from Carlos is authoritative for `SmartGoalEngine`, goal health, priority/flexibility/lifecycle, required savings, projected completion, conflicts and goal-aware safe-to-spend.
- **Banking / Nessie:** latest `codex/product-v1.3-nessie-sync` is authoritative for linked accounts, balances, transaction normalization, refresh/persistence and reconciliation.
- **Context V2 / product integration:** Lucas's latest Context V2 planning/materiality/NLP work is integrated into the shared core without replacing Marc's UI or Carlos's goal model.

Shared files are reconciled semantically. In particular, `ContentView.swift`, `Models.swift`, `QualitativeProfileUpdater.swift`, `FinancialCoreBridge.swift`, `Finanzas2026App.swift` and the Xcode project must not be resolved with blanket ours/theirs choices.
