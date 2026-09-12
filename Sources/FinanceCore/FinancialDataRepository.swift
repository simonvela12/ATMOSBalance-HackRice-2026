import Foundation

public struct RepositorySyncCounts: Equatable, Sendable {
    public let accountsInserted: Int
    public let accountsUpdated: Int
    public let transactionsInserted: Int
    public let transactionsUpdated: Int
    public let duplicatesIgnored: Int

    public init(accountsInserted: Int, accountsUpdated: Int, transactionsInserted: Int,
                transactionsUpdated: Int, duplicatesIgnored: Int) {
        self.accountsInserted = accountsInserted; self.accountsUpdated = accountsUpdated
        self.transactionsInserted = transactionsInserted; self.transactionsUpdated = transactionsUpdated
        self.duplicatesIgnored = duplicatesIgnored
    }
}

public protocol FinancialDataRepository: Sendable {
    func persist(connection: BankConnection, accounts: [FinancialAccount],
                 transactions: [FinancialTransaction]) async throws -> RepositorySyncCounts
    func replaceSnapshot(connection: BankConnection, accounts: [FinancialAccount],
                         transactions: [FinancialTransaction],
                         authoritativeTransactionAccountIDs: Set<String>) async throws -> RepositorySyncCounts
    func connections() async throws -> [BankConnection]
    func accounts() async throws -> [FinancialAccount]
    func transactions(from startDate: Date?, to endDate: Date?) async throws -> [FinancialTransaction]
    func transactions(accountID: String, from startDate: Date?,
                      to endDate: Date?) async throws -> [FinancialTransaction]
}

public extension FinancialDataRepository {
    func replaceSnapshot(connection: BankConnection, accounts: [FinancialAccount],
                         transactions: [FinancialTransaction],
                         authoritativeTransactionAccountIDs: Set<String>) async throws -> RepositorySyncCounts {
        try await persist(connection: connection, accounts: accounts, transactions: transactions)
    }
}

public actor InMemoryFinancialRepository: FinancialDataRepository {
    private var connectionStorage: [String: BankConnection] = [:]
    private var accountStorage: [String: FinancialAccount] = [:]
    private var transactionStorage: [String: FinancialTransaction] = [:]

    public init() {}

    public func persist(connection: BankConnection, accounts: [FinancialAccount],
                        transactions: [FinancialTransaction]) throws -> RepositorySyncCounts {
        let counts = upsert(accounts: accounts, transactions: transactions)
        connectionStorage[connection.id] = connection
        return counts
    }

    public func replaceSnapshot(connection: BankConnection, accounts: [FinancialAccount],
                                transactions: [FinancialTransaction],
                                authoritativeTransactionAccountIDs: Set<String>) async throws -> RepositorySyncCounts {
        let reconciledAccounts = accounts.map { incoming -> FinancialAccount in
            guard incoming.provider == .nessie,
                  authoritativeTransactionAccountIDs.contains(incoming.externalAccountID),
                  let existing = accountStorage[incoming.id] else { return incoming }

            let previousProviderBalance = existing.providerReportedBalanceMinorUnits
                ?? existing.balanceMinorUnits
            let incomingProviderBalance = incoming.providerReportedBalanceMinorUnits
                ?? incoming.balanceMinorUnits

            // If Nessie itself changed the reported balance, it is authoritative.
            // Otherwise apply only the transaction delta observed since the last
            // snapshot. Nessie's sandbox accepts purchases/deposits/transfers but
            // currently leaves `account.balance` unchanged.
            guard previousProviderBalance == incomingProviderBalance else { return incoming }

            let previousTotal = transactionStorage.values.lazy
                .filter { $0.provider == incoming.provider &&
                    $0.externalCustomerID == incoming.externalCustomerID &&
                    $0.externalAccountID == incoming.externalAccountID && !$0.isPending }
                .reduce(Int64(0)) { $0 + $1.signedAmountMinorUnits }
            let incomingTotal = transactions.lazy
                .filter { $0.provider == incoming.provider &&
                    $0.externalCustomerID == incoming.externalCustomerID &&
                    $0.externalAccountID == incoming.externalAccountID && !$0.isPending }
                .reduce(Int64(0)) { $0 + $1.signedAmountMinorUnits }

            var adjusted = incoming
            adjusted.balanceMinorUnits = existing.balanceMinorUnits + incomingTotal - previousTotal
            return adjusted
        }

        let incomingAccountIDs = Set(accounts.map(\.id))
        accountStorage = accountStorage.filter { _, account in
            account.provider != connection.provider ||
            account.externalCustomerID != connection.externalCustomerID ||
            incomingAccountIDs.contains(account.id)
        }

        let incomingTransactionKeys = Set(transactions.map(\.deduplicationKey))
        let incomingExternalAccountIDs = Set(accounts.map(\.externalAccountID))
        transactionStorage = transactionStorage.filter { _, transaction in
            guard transaction.provider == connection.provider,
                  transaction.externalCustomerID == connection.externalCustomerID else { return true }
            guard incomingExternalAccountIDs.contains(transaction.externalAccountID) else { return false }
            guard authoritativeTransactionAccountIDs.contains(transaction.externalAccountID) else { return true }
            return incomingTransactionKeys.contains(transaction.deduplicationKey)
        }

        let counts = upsert(accounts: reconciledAccounts, transactions: transactions)
        connectionStorage[connection.id] = connection
        return counts
    }

    public func connections() throws -> [BankConnection] { Array(connectionStorage.values) }
    public func accounts() throws -> [FinancialAccount] { accountStorage.values.sorted { $0.id < $1.id } }

    public func transactions(from startDate: Date? = nil,
                             to endDate: Date? = nil) throws -> [FinancialTransaction] {
        filtered(accountID: nil, from: startDate, to: endDate)
    }

    public func transactions(accountID: String, from startDate: Date? = nil,
                             to endDate: Date? = nil) throws -> [FinancialTransaction] {
        filtered(accountID: accountID, from: startDate, to: endDate)
    }

    private func upsert(accounts: [FinancialAccount], transactions: [FinancialTransaction]) -> RepositorySyncCounts {
        var accountsInserted = 0, accountsUpdated = 0, transactionsInserted = 0
        var transactionsUpdated = 0, duplicatesIgnored = 0
        for account in accounts {
            if let existing = accountStorage[account.id] {
                if existing.hasSameProviderContent(as: account) { accountStorage[account.id] = account }
                else { accountStorage[account.id] = account; accountsUpdated += 1 }
            } else { accountStorage[account.id] = account; accountsInserted += 1 }
        }
        for transaction in transactions {
            if let existing = transactionStorage[transaction.deduplicationKey] {
                if existing.hasSameMutableContent(as: transaction) { duplicatesIgnored += 1 }
                else { transactionStorage[transaction.deduplicationKey] = transaction; transactionsUpdated += 1 }
            } else { transactionStorage[transaction.deduplicationKey] = transaction; transactionsInserted += 1 }
        }
        return RepositorySyncCounts(accountsInserted: accountsInserted, accountsUpdated: accountsUpdated,
                                    transactionsInserted: transactionsInserted,
                                    transactionsUpdated: transactionsUpdated,
                                    duplicatesIgnored: duplicatesIgnored)
    }

    private func filtered(accountID: String?, from startDate: Date?,
                          to endDate: Date?) -> [FinancialTransaction] {
        transactionStorage.values.filter {
            if let accountID, $0.externalAccountID != accountID { return false }
            if let startDate, $0.transactionDate < startDate { return false }
            if let endDate, $0.transactionDate > endDate { return false }
            return true
        }.sorted { $0.transactionDate == $1.transactionDate ? $0.id < $1.id : $0.transactionDate < $1.transactionDate }
    }
}

private extension FinancialAccount {
    func hasSameProviderContent(as other: FinancialAccount) -> Bool {
        provider == other.provider && externalAccountID == other.externalAccountID &&
        externalCustomerID == other.externalCustomerID && name == other.name &&
        accountType == other.accountType && balanceMinorUnits == other.balanceMinorUnits &&
        providerReportedBalanceMinorUnits == other.providerReportedBalanceMinorUnits &&
        currencyCode == other.currencyCode
    }
}
