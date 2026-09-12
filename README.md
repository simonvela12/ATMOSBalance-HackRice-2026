# Hackathon2026 — FinanceCore + Nessie

Swift 6 package for ingesting Capital One Nessie sandbox bank data into provider-independent personal-finance models. It runs on Windows and avoids SwiftUI, UIKit, SwiftData, and third-party packages.

## Open in Xcode

On a Mac, clone the repository and open `Package.swift` with Xcode. The `FinanceCore` library supports iOS 17+ and macOS 13+. Select the `FinanceCoreDemo` scheme to run the sandbox CLI on macOS, or add the `FinanceCore` library product to an iOS 17+ application target.

The package deliberately keeps networking, normalization, synchronization, deduplication, and repository contracts independent from SwiftUI. The future iPhone interface can therefore import `FinanceCore` without depending on Nessie DTOs.

## Configure

This hackathon branch includes `.env` with the shared Nessie sandbox API key so collaborators can run it immediately. Add a Nessie sandbox customer ID:

```text
NESSIE_CUSTOMER_ID=your_customer_id
```

Alternatively, leave it blank and enter the customer ID when the executable prompts. The included key is for the mock Nessie sandbox only; replace this arrangement with backend-managed secrets before integrating any real financial provider.

## Run on Windows

Open **Developer PowerShell for VS 2022**, change to this directory, and run:

```powershell
swift run
```

Data is persisted at `.finance-data/finance-store.json`. Run the command again to verify that existing records are reported as duplicates rather than inserted again.

Run tests with:

```powershell
swift test
```

If `swift` is not recognized, restart VS Code so it receives the updated user `PATH`. If `link` is not found, launch VS Code from Developer PowerShell for VS 2022.

See `BANKING_INTEGRATION.md` for architecture, normalized fields, endpoints, limitations, and integration guidance.
