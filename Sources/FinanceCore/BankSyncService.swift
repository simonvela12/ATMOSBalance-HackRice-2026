import Foundation

public struct AccountSyncFailure: Equatable, Sendable {
    public let externalAccountID: String
    public let error: BankingError

    public init(externalAccountID: String, error: BankingError) {
        self.externalAccountID = externalAccountID
        self.error = error
    }
}

public struct SyncResult: Equatable, Sendable {
    public let accountsFetched: Int
    public let accountsInserted: Int
    public let accountsUpdated: Int
    public let transactionsFetched: Int
    public let transactionsInserted: Int
    public let transactionsUpdated: Int
    public let duplicatesIgnored: Int
    public let accountFailures: [AccountSyncFailure]
    public let startedAt: Date
    public let finishedAt: Date

    public var isPartial: Bool { !accountFailures.isEmpty }
}

public actor BankSyncService {
    private let provider: any BankingProvider
    private let repository: any FinancialDataRepository
    private let diagnostics: BankingDiagnostics
    private var isSyncing = false

    public init(provider: any BankingProvider, repository: any FinancialDataRepository,
                diagnostics: BankingDiagnostics = .disabled) {
        self.provider = provider
        self.repository = repository
        self.diagnostics = diagnostics
    }

    public func syncAll() async throws -> SyncResult {
        guard !isSyncing else { throw BankingError.syncAlreadyInProgress }
        isSyncing = true
        defer { isSyncing = false }
        let startedAt = Date()
        await diagnostics.record(.syncStart)
        do {
            var connection = try await provider.connect()
            let externalAccounts = try await provider.fetchAccounts()
            let normalizedAccounts = externalAccounts.map { BankingDomainMapper.account($0, syncedAt: startedAt) }
            let transactionSync = await fetchTransactions(for: externalAccounts, syncedAt: startedAt)
            await diagnostics.record(.transactionsReceived, details: [
                "accounts": String(externalAccounts.count),
                "count": String(transactionSync.transactions.count),
                "failedAccounts": String(transactionSync.failures.count)
            ])
            let finishedAt = Date()
            connection.status = .connected; connection.lastSyncedAt = finishedAt
            let counts = try await repository.persist(connection: connection, accounts: normalizedAccounts,
                                                      transactions: transactionSync.transactions)
            await diagnostics.record(.newTransactions,
                                     details: ["count": String(counts.transactionsInserted)])
            await diagnostics.record(.duplicatesIgnored,
                                     details: ["count": String(counts.duplicatesIgnored)])
            await diagnostics.record(.localStoreUpdated, details: [
                "accountsInserted": String(counts.accountsInserted),
                "accountsUpdated": String(counts.accountsUpdated),
                "transactionsInserted": String(counts.transactionsInserted),
                "transactionsUpdated": String(counts.transactionsUpdated)
            ])
            await diagnostics.record(.syncEnd, details: [
                "durationMs": String(Int(finishedAt.timeIntervalSince(startedAt) * 1_000)),
                "result": transactionSync.failures.isEmpty ? "success" : "partial"
            ])
            return SyncResult(accountsFetched: externalAccounts.count,
                              accountsInserted: counts.accountsInserted, accountsUpdated: counts.accountsUpdated,
                              transactionsFetched: transactionSync.transactions.count,
                              transactionsInserted: counts.transactionsInserted,
                              transactionsUpdated: counts.transactionsUpdated,
                              duplicatesIgnored: counts.duplicatesIgnored,
                              accountFailures: transactionSync.failures,
                              startedAt: startedAt, finishedAt: finishedAt)
        } catch {
            let finishedAt = Date()
            await diagnostics.record(.syncEnd, details: [
                "durationMs": String(Int(finishedAt.timeIntervalSince(startedAt) * 1_000)),
                "result": "failure", "errorType": String(describing: type(of: error))
            ])
            throw error
        }
    }

    private func fetchTransactions(
        for accounts: [ExternalBankAccount],
        syncedAt: Date
    ) async -> (transactions: [FinancialTransaction], failures: [AccountSyncFailure]) {
        await withTaskGroup(of: AccountFetchOutcome.self) { group in
            for account in accounts {
                group.addTask { [provider] in
                    do {
                        let fetched = try await provider.fetchTransactions(for: account)
                        return .success(
                            fetched.map { BankingDomainMapper.transaction($0, syncedAt: syncedAt) }
                        )
                    } catch let error as BankingError {
                        return .failure(AccountSyncFailure(
                            externalAccountID: account.externalAccountID,
                            error: error
                        ))
                    } catch {
                        return .failure(AccountSyncFailure(
                            externalAccountID: account.externalAccountID,
                            error: .networkError(error.localizedDescription)
                        ))
                    }
                }
            }

            var transactions: [FinancialTransaction] = []
            var failures: [AccountSyncFailure] = []
            for await outcome in group {
                switch outcome {
                case .success(let fetched): transactions += fetched
                case .failure(let failure): failures.append(failure)
                }
            }
            failures.sort { $0.externalAccountID < $1.externalAccountID }
            return (transactions, failures)
        }
    }
}

private enum AccountFetchOutcome: Sendable {
    case success([FinancialTransaction])
    case failure(AccountSyncFailure)
}
