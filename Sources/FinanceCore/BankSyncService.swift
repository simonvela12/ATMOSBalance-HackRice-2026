import Foundation

public struct SyncResult: Equatable, Sendable {
    public let accountsFetched: Int
    public let accountsInserted: Int
    public let accountsUpdated: Int
    public let transactionsFetched: Int
    public let transactionsInserted: Int
    public let transactionsUpdated: Int
    public let duplicatesIgnored: Int
    public let startedAt: Date
    public let finishedAt: Date
}

public actor BankSyncService {
    private let provider: any BankingProvider
    private let repository: any FinancialDataRepository
    private var isSyncing = false

    public init(provider: any BankingProvider, repository: any FinancialDataRepository) {
        self.provider = provider; self.repository = repository
    }

    public func syncAll() async throws -> SyncResult {
        guard !isSyncing else { throw BankingError.syncAlreadyInProgress }
        isSyncing = true
        defer { isSyncing = false }
        let startedAt = Date()
        var connection = try await provider.connect()
        let externalAccounts = try await provider.fetchAccounts()
        let normalizedAccounts = externalAccounts.map { BankingDomainMapper.account($0, syncedAt: startedAt) }
        let provider = self.provider
        let normalizedTransactions = try await withThrowingTaskGroup(
            of: [FinancialTransaction].self,
            returning: [FinancialTransaction].self
        ) { group in
            for account in externalAccounts {
                group.addTask {
                    let fetched = try await provider.fetchTransactions(for: account)
                    return fetched.map { BankingDomainMapper.transaction($0, syncedAt: startedAt) }
                }
            }
            var combined: [FinancialTransaction] = []
            combined.reserveCapacity(externalAccounts.count * 16)
            for try await transactions in group { combined.append(contentsOf: transactions) }
            return combined
        }
        let finishedAt = Date()
        connection.status = .connected; connection.lastSyncedAt = finishedAt
        let counts = try await repository.persist(connection: connection, accounts: normalizedAccounts,
                                                  transactions: normalizedTransactions)
        return SyncResult(accountsFetched: externalAccounts.count,
                          accountsInserted: counts.accountsInserted, accountsUpdated: counts.accountsUpdated,
                          transactionsFetched: normalizedTransactions.count,
                          transactionsInserted: counts.transactionsInserted,
                          transactionsUpdated: counts.transactionsUpdated,
                          duplicatesIgnored: counts.duplicatesIgnored,
                          startedAt: startedAt, finishedAt: finishedAt)
    }
}
