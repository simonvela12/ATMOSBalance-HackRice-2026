import Foundation

public actor FileFinancialRepository: FinancialDataRepository {
    private struct Store: Codable {
        var connections: [BankConnection] = []
        var accounts: [FinancialAccount] = []
        var transactions: [FinancialTransaction] = []
    }

    private let fileURL: URL
    private let allowedProviders: [BankingProviderID]?
    private var memory: InMemoryFinancialRepository

    public init(fileURL: URL, allowedProviders: [BankingProviderID]? = nil) throws {
        self.fileURL = fileURL
        self.allowedProviders = allowedProviders
        self.memory = InMemoryFinancialRepository()
    }

    public func load() async throws {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
            var store = try decoder.decode(Store.self, from: data)
            if let allowedProviders {
                store.connections.removeAll { !allowedProviders.contains($0.provider) }
                store.accounts.removeAll { !allowedProviders.contains($0.provider) }
                store.transactions.removeAll { !allowedProviders.contains($0.provider) }
            }
            let rebuilt = InMemoryFinancialRepository()
            let transactionsByCustomer = Dictionary(grouping: store.transactions, by: \.externalCustomerID)
            for connection in store.connections {
                let relatedAccounts = store.accounts.filter { $0.externalCustomerID == connection.externalCustomerID }
                _ = try await rebuilt.persist(connection: connection, accounts: relatedAccounts,
                                              transactions: transactionsByCustomer[connection.externalCustomerID] ?? [])
            }
            self.memory = rebuilt
            if allowedProviders != nil { try await writeToDisk() }
        } catch {
            throw BankingError.persistenceError("Could not read \(fileURL.path): \(error.localizedDescription)")
        }
    }

    public func persist(connection: BankConnection, accounts: [FinancialAccount],
                        transactions: [FinancialTransaction]) async throws -> RepositorySyncCounts {
        guard allowedProviders?.contains(connection.provider) ?? true else {
            throw BankingError.persistenceError("Provider \(connection.provider.rawValue) is not allowed in this store")
        }
        let counts = try await memory.persist(connection: connection, accounts: accounts, transactions: transactions)
        try await writeToDisk()
        return counts
    }

    public func replaceSnapshot(connection: BankConnection, accounts: [FinancialAccount],
                                transactions: [FinancialTransaction],
                                authoritativeTransactionAccountIDs: Set<String>) async throws -> RepositorySyncCounts {
        guard allowedProviders?.contains(connection.provider) ?? true else {
            throw BankingError.persistenceError("Provider \(connection.provider.rawValue) is not allowed in this store")
        }
        let counts = try await memory.replaceSnapshot(
            connection: connection,
            accounts: accounts,
            transactions: transactions,
            authoritativeTransactionAccountIDs: authoritativeTransactionAccountIDs
        )
        try await writeToDisk()
        return counts
    }

    public func connections() async throws -> [BankConnection] { try await memory.connections() }
    public func accounts() async throws -> [FinancialAccount] { try await memory.accounts() }
    public func transactions(from startDate: Date? = nil,
                             to endDate: Date? = nil) async throws -> [FinancialTransaction] {
        try await memory.transactions(from: startDate, to: endDate)
    }
    public func transactions(accountID: String, from startDate: Date? = nil,
                             to endDate: Date? = nil) async throws -> [FinancialTransaction] {
        try await memory.transactions(accountID: accountID, from: startDate, to: endDate)
    }

    private func writeToDisk() async throws {
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            let store = Store(connections: try await memory.connections(), accounts: try await memory.accounts(),
                              transactions: try await memory.transactions(from: nil, to: nil))
            let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601; encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(store).write(to: fileURL, options: .atomic)
        } catch {
            throw BankingError.persistenceError("Could not write \(fileURL.path): \(error.localizedDescription)")
        }
    }
}
