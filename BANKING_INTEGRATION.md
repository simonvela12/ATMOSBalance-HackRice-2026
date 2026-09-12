# Banking integration

## Architecture

`FinanceCoreDemo` is a small command-line connection and sync UI. It creates a `BankSyncService`, which depends only on the `BankingProvider` and `FinancialDataRepository` protocols. `NessieBankingProvider` is the current provider implementation. Nessie DTOs and endpoint details remain inside `Sources/FinanceCore/Nessie`.

```text
FinanceCoreDemo
    -> BankSyncService
        -> BankingProvider
            -> NessieBankingProvider -> NessieAPIClient -> Nessie REST API
        -> FinancialDataRepository
            -> FileFinancialRepository -> local JSON store
```

The future iPhone app can import the `FinanceCore` library and replace the command-line target with SwiftUI. It can also implement `FinancialDataRepository` using SwiftData without exposing Nessie types to the UI or mathematical engine.

## Nessie configuration

The configured sandbox host is `http://api.nessieisreal.com`, the host currently referenced by Capital One hackathon materials and the official `nessieisreal` GitHub organization. The API key is sent as the `key` query parameter, matching Nessie's API.

Configuration is loaded from process environment variables first and `.env` second:

- `NESSIE_API_KEY`
- `NESSIE_CUSTOMER_ID`
- `NESSIE_BASE_URL`

The `financecore-nessie` hackathon branch intentionally tracks `.env` with the shared mock-sandbox key so collaborators can run it immediately. A real provider secret must instead be held behind a backend and must never ship in an iOS client.

## Connection and sync

Run `swift run`. If `NESSIE_CUSTOMER_ID` is blank, the demo asks for it. A sync then:

1. Creates the simulated sandbox connection.
2. Retrieves every account from `GET /customers/{customerID}/accounts`.
3. For each account, retrieves purchases, deposits, withdrawals, and transfers from their account-scoped endpoints.
4. Optionally fetches merchant details from `GET /merchants/{merchantID}`. Enrichment failure does not fail transaction ingestion.
5. Maps Nessie DTOs to provider-independent accounts and transactions.
6. Atomically writes normalized data to `.finance-data/finance-store.json`.
7. Updates the connection's `lastSyncedAt` only after all remote reads succeed.

Nessie does not expose a cursor in this integration. Each run fetches the available history and deduplicates locally.

## Deduplication

Transactions use a stable composite key containing provider, account, source type, and external identity. Transfers also include direction in their external identity. The same transfer can therefore produce one ledger movement for its source account and another for its destination account without colliding.

When Nessie provides no transaction ID, `NessieMapper` computes a deterministic FNV-1a identifier from stable fields. It never uses a random UUID for external identity.

Repository behavior:

- Unknown key: insert.
- Known key with identical mutable content: ignore as duplicate.
- Known key with changed mutable content: update in place.

## Normalized format

`FinancialAccount` stores provider identity, external account/customer IDs, account type, currency, `Int64` balance minor units, and sync time.

`FinancialTransaction` stores transaction/account/customer identities, dates, merchant, description, category, source type, direction, amount, signed amount, currency, pending/transfer flags, and update time.

Canonical signs are:

- Inflow: positive `signedAmountMinorUnits`.
- Outflow: negative `signedAmountMinorUnits`.

All canonical monetary values are `Int64` minor units. Nessie decimal values are decoded as `Decimal` and explicitly rounded with banker's rounding. Transfers remain marked as transfers and are not interpreted as income or expenses.

## Querying data

Code outside the provider layer depends on `FinancialDataRepository`:

```swift
let accounts = try await repository.accounts()
let all = try await repository.transactions(from: startDate, to: endDate)
let checking = try await repository.transactions(
    accountID: externalAccountID,
    from: startDate,
    to: endDate
)
```

No forecasting, budgeting, goal, AI, or What If calculations are included.

## Adding Plaid later

Implement `PlaidBankingProvider: BankingProvider` and map Plaid responses to `ExternalBankAccount` and `ExternalBankTransaction`. `BankSyncService`, repositories, normalized models, and consumers do not need to change. A Plaid implementation can internally use its cursor while preserving the same provider interface.

## Nessie limitations

- Nessie is a public mock banking API, not a production bank connection or OAuth flow.
- Account types and credit-card detail are limited to fields Nessie actually returns. No debt semantics are fabricated.
- It provides separated transaction-like resources rather than one normalized feed.
- Merchant records may be absent or enrichment may fail; the base transaction is still retained.
- The published sandbox URL is HTTP. A future iOS host app will need an App Transport Security exception for this sandbox or an HTTPS backend proxy. Do not weaken ATS for a production provider.
- The API may not provide posted dates, currencies, incremental cursors, or complete historical coverage. Missing optional values stay absent; required malformed transactions cause a typed error rather than being silently discarded.

## Manual verification

1. Open **Developer PowerShell for VS 2022**.
2. Change directory to the project root.
3. Add a valid sandbox customer ID to `.env`.
4. Run `swift test`; all mapping, rounding, error, update, and deduplication tests should pass.
5. Run `swift run`; note the account and transaction counts.
6. Inspect `.finance-data/finance-store.json` and confirm amounts are integers and every transaction has a `deduplicationKey`.
7. Run `swift run` again. Existing transactions should move to `duplicatesIgnored`, with no increase in stored count.
8. Add a transaction to the Nessie sandbox, run again, and confirm exactly the new ledger movement is inserted.
