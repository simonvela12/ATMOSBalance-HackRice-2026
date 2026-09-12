import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import XCTest
@testable import FinanceCore

final class FinanceCoreTests: XCTestCase {
    private let account1 = ExternalBankAccount(provider: .nessie, externalAccountID: "account-1",
                                               externalCustomerID: "customer-1", name: "Checking",
                                               accountType: .checking, balanceMinorUnits: 100_00)
    private let account2 = ExternalBankAccount(provider: .nessie, externalAccountID: "account-2",
                                               externalCustomerID: "customer-1", name: "Savings",
                                               accountType: .savings, balanceMinorUnits: 200_00)

    func testPurchaseMapsToNegativeSignedAmount() throws {
        let dto: NessiePurchase = try fixture("purchase")
        let mapped = BankingDomainMapper.transaction(try NessieMapper.purchase(dto, account: account1), syncedAt: Date())
        XCTAssertEqual(mapped.signedAmountMinorUnits, -1_482)
        XCTAssertEqual(mapped.sourceType, .purchase)
    }

    func testDepositMapsToPositiveSignedAmount() throws {
        let dto: NessieDeposit = try fixture("deposit")
        let mapped = BankingDomainMapper.transaction(try NessieMapper.deposit(dto, account: account1), syncedAt: Date())
        XCTAssertEqual(mapped.signedAmountMinorUnits, 45_000)
        XCTAssertEqual(mapped.direction, .inflow)
    }

    func testWithdrawalMapsToNegativeSignedAmount() throws {
        let dto: NessieWithdrawal = try fixture("withdrawal")
        let mapped = BankingDomainMapper.transaction(try NessieMapper.withdrawal(dto, account: account1), syncedAt: Date())
        XCTAssertEqual(mapped.signedAmountMinorUnits, -2_000)
    }

    func testTransferCreatesAccountAwareIncomingAndOutgoingEntries() throws {
        let dto: NessieTransfer = try fixture("transfer")
        let outgoing = BankingDomainMapper.transaction(try NessieMapper.transfer(dto, account: account1), syncedAt: Date())
        let incoming = BankingDomainMapper.transaction(try NessieMapper.transfer(dto, account: account2), syncedAt: Date())
        XCTAssertEqual(outgoing.signedAmountMinorUnits, -7_525)
        XCTAssertEqual(incoming.signedAmountMinorUnits, 7_525)
        XCTAssertTrue(outgoing.isTransfer); XCTAssertTrue(incoming.isTransfer)
        XCTAssertNotEqual(outgoing.deduplicationKey, incoming.deduplicationKey)
    }

    func testAccountScopedNessieTransferUsesCurrentSandboxShape() throws {
        let dto = try JSONDecoder().decode(
            NessieTransfer.self,
            from: Data("""
                {"id":"transfer-current","transaction_date":"2026-09-12","amount":75,
                 "status":"completed","description":"Student savings transfer"}
                """.utf8)
        )

        let mapped = try NessieMapper.transfer(dto, account: account1)

        XCTAssertEqual(mapped.externalTransactionID, "transfer:transfer-current:outflow")
        XCTAssertEqual(mapped.direction, .outflow)
        XCTAssertEqual(mapped.amountMinorUnits, 7_500)
        XCTAssertTrue(mapped.isTransfer)
    }

    func testDecimalMoneyConversionUsesExplicitRounding() throws {
        let amount = try XCTUnwrap(Decimal(string: "14.825"))
        let exact = try XCTUnwrap(Decimal(string: "0.29"))
        XCTAssertEqual(try MoneyConversion.minorUnits(from: amount), 1_482)
        XCTAssertEqual(try MoneyConversion.minorUnits(from: exact), 29)
    }

    func testSecondSyncDeduplicatesAndLaterSyncInsertsOnlyNewTransaction() async throws {
        let first = externalTransaction(id: "purchase:one", description: "One", amount: 500)
        let provider = MockBankingProvider(account: account1, transactions: [first])
        let repository = InMemoryFinancialRepository()
        let service = BankSyncService(provider: provider, repository: repository)

        let initial = try await service.syncAll()
        let duplicate = try await service.syncAll()
        await provider.setTransactions([first, externalTransaction(id: "purchase:two", description: "Two", amount: 700)])
        let incremental = try await service.syncAll()

        XCTAssertEqual(initial.transactionsInserted, 1)
        XCTAssertEqual(duplicate.transactionsInserted, 0)
        XCTAssertEqual(duplicate.duplicatesIgnored, 1)
        XCTAssertEqual(incremental.transactionsInserted, 1)
        let stored = try await repository.transactions(from: nil, to: nil)
        XCTAssertEqual(stored.count, 2)
    }

    func testSyncDiagnosticsReportPersistenceAndDeduplication() async throws {
        let collector = DiagnosticCollector()
        let diagnostics = BankingDiagnostics { event in await collector.append(event) }
        let transaction = externalTransaction(id: "purchase:one", description: "One", amount: 500)
        let provider = MockBankingProvider(account: account1, transactions: [transaction])
        let repository = InMemoryFinancialRepository()
        let service = BankSyncService(provider: provider, repository: repository,
                                      diagnostics: diagnostics)

        _ = try await service.syncAll()
        _ = try await service.syncAll()
        let events = await collector.events()

        XCTAssertEqual(events.filter { $0.kind == .syncStart }.count, 2)
        XCTAssertEqual(events.filter { $0.kind == .syncEnd }.count, 2)
        XCTAssertTrue(events.contains {
            $0.kind == .newTransactions && $0.details["count"] == "1"
        })
        XCTAssertTrue(events.contains {
            $0.kind == .duplicatesIgnored && $0.details["count"] == "1"
        })
        XCTAssertEqual(events.filter { $0.kind == .localStoreUpdated }.count, 2)
    }

    func testChangedProviderDataUpdatesRatherThanDuplicates() async throws {
        let provider = MockBankingProvider(account: account1,
                                           transactions: [externalTransaction(id: "purchase:one", description: "Old", amount: 500)])
        let repository = InMemoryFinancialRepository()
        let service = BankSyncService(provider: provider, repository: repository)
        _ = try await service.syncAll()
        await provider.setTransactions([externalTransaction(id: "purchase:one", description: "Corrected", amount: 500)])
        let result = try await service.syncAll()
        let stored = try await repository.transactions(from: nil, to: nil)

        XCTAssertEqual(result.transactionsUpdated, 1)
        XCTAssertEqual(stored.count, 1)
        XCTAssertEqual(stored.first?.transactionDescription, "Corrected")
    }

    func testAuthoritativeSnapshotRemovesStaleNessieAccountsAndTransactions() async throws {
        let repository = InMemoryFinancialRepository()
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let connection = BankConnection(
            id: "nessie|customer-1", provider: .nessie, externalCustomerID: "customer-1",
            status: .connected, connectedAt: now
        )
        let firstAccounts = [account1, account2].map { BankingDomainMapper.account($0, syncedAt: now) }
        let firstTransactions = [
            externalTransaction(id: "purchase:one", accountID: "account-1", description: "One", amount: 500),
            externalTransaction(id: "purchase:two", accountID: "account-2", description: "Two", amount: 700)
        ].map { BankingDomainMapper.transaction($0, syncedAt: now) }
        _ = try await repository.replaceSnapshot(
            connection: connection, accounts: firstAccounts, transactions: firstTransactions,
            authoritativeTransactionAccountIDs: ["account-1", "account-2"]
        )

        let refreshedAccount = ExternalBankAccount(
            provider: .nessie, externalAccountID: "account-1", externalCustomerID: "customer-1",
            name: "Checking", accountType: .checking, balanceMinorUnits: 42_000
        )
        _ = try await repository.replaceSnapshot(
            connection: connection,
            accounts: [BankingDomainMapper.account(refreshedAccount, syncedAt: now.addingTimeInterval(10))],
            transactions: [], authoritativeTransactionAccountIDs: ["account-1"]
        )

        let storedAccounts = try await repository.accounts()
        let storedTransactions = try await repository.transactions(from: nil, to: nil)
        XCTAssertEqual(storedAccounts.count, 1)
        XCTAssertEqual(storedAccounts.first?.balanceMinorUnits, 42_000)
        XCTAssertTrue(storedTransactions.isEmpty)
    }

    func testPartialSnapshotKeepsTransactionsForFailedAccount() async throws {
        let repository = InMemoryFinancialRepository()
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let connection = BankConnection(
            id: "nessie|customer-1", provider: .nessie, externalCustomerID: "customer-1",
            status: .connected, connectedAt: now
        )
        let accounts = [account1, account2].map { BankingDomainMapper.account($0, syncedAt: now) }
        let checking = BankingDomainMapper.transaction(
            externalTransaction(id: "purchase:checking", accountID: "account-1", description: "Checking", amount: 500),
            syncedAt: now
        )
        let savings = BankingDomainMapper.transaction(
            externalTransaction(id: "purchase:savings", accountID: "account-2", description: "Savings", amount: 700),
            syncedAt: now
        )
        _ = try await repository.replaceSnapshot(
            connection: connection, accounts: accounts, transactions: [checking, savings],
            authoritativeTransactionAccountIDs: ["account-1", "account-2"]
        )

        _ = try await repository.replaceSnapshot(
            connection: connection, accounts: accounts, transactions: [],
            authoritativeTransactionAccountIDs: ["account-1"]
        )

        let stored = try await repository.transactions(from: nil, to: nil)
        XCTAssertEqual(stored.map(\.externalAccountID), ["account-2"])
    }

    func testNessieOnlyFileStorePurgesPreviouslyCachedDemoData() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FinanceCoreProviderFilter-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("store.json")
        let unfiltered = try FileFinancialRepository(fileURL: fileURL)
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let demoConnection = BankConnection(
            id: "demo|customer", provider: .demo, externalCustomerID: "customer",
            status: .connected, connectedAt: now
        )
        let demoAccount = FinancialAccount(
            id: "demo|account", provider: .demo, externalAccountID: "account",
            externalCustomerID: "customer", name: "Demo", accountType: .checking,
            balanceMinorUnits: 999_999, currencyCode: "USD", lastSyncedAt: now
        )
        _ = try await unfiltered.persist(connection: demoConnection, accounts: [demoAccount], transactions: [])

        let filtered = try FileFinancialRepository(fileURL: fileURL, allowedProviders: [.nessie])
        try await filtered.load()

        let connections = try await filtered.connections()
        let accounts = try await filtered.accounts()
        let transactions = try await filtered.transactions(from: nil, to: nil)
        XCTAssertTrue(connections.isEmpty)
        XCTAssertTrue(accounts.isEmpty)
        XCTAssertTrue(transactions.isEmpty)
    }

    func testMultipleAccountsKeepTransactionsIsolatedWhenProviderIDsMatch() async throws {
        let provider = MultiAccountMockProvider(
            accounts: [account1, account2],
            transactionsByAccount: [
                account1.externalAccountID: [
                    externalTransaction(id: "purchase:shared", accountID: account1.externalAccountID,
                                        description: "Checking purchase", amount: 500)
                ],
                account2.externalAccountID: [
                    externalTransaction(id: "purchase:shared", accountID: account2.externalAccountID,
                                        description: "Savings purchase", amount: 700)
                ]
            ]
        )
        let repository = InMemoryFinancialRepository()
        let result = try await BankSyncService(provider: provider, repository: repository).syncAll()
        let checkingTransactions = try await repository.transactions(
            accountID: account1.externalAccountID, from: nil, to: nil
        )
        let savingsTransactions = try await repository.transactions(
            accountID: account2.externalAccountID, from: nil, to: nil
        )

        XCTAssertEqual(result.accountsFetched, 2)
        XCTAssertEqual(result.transactionsInserted, 2)
        XCTAssertTrue(result.accountFailures.isEmpty)
        XCTAssertEqual(checkingTransactions.count, 1)
        XCTAssertEqual(savingsTransactions.count, 1)
    }

    func testOneAccountFailureDoesNotDiscardOtherAccountsOrTransactions() async throws {
        let provider = MultiAccountMockProvider(
            accounts: [account1, account2],
            transactionsByAccount: [
                account1.externalAccountID: [
                    externalTransaction(id: "purchase:one", accountID: account1.externalAccountID,
                                        description: "Available transaction", amount: 500)
                ]
            ],
            failingAccountIDs: [account2.externalAccountID]
        )
        let repository = InMemoryFinancialRepository()
        let result = try await BankSyncService(provider: provider, repository: repository).syncAll()
        let storedAccounts = try await repository.accounts()
        let storedTransactions = try await repository.transactions(from: nil, to: nil)

        XCTAssertTrue(result.isPartial)
        XCTAssertEqual(result.accountFailures, [
            AccountSyncFailure(externalAccountID: account2.externalAccountID,
                               error: .networkError("Simulated account failure"))
        ])
        XCTAssertEqual(result.accountsInserted, 2)
        XCTAssertEqual(result.transactionsInserted, 1)
        XCTAssertEqual(storedAccounts.count, 2)
        XCTAssertEqual(storedTransactions.count, 1)
    }

    func testHTTPErrorBecomesTypedError() async throws {
        let url = try XCTUnwrap(URL(string: "https://example.test"))
        let response = try XCTUnwrap(HTTPURLResponse(url: url,
                                                    statusCode: 401, httpVersion: nil, headerFields: nil))
        let transport = StubTransport(data: Data("unauthorized".utf8), response: response)
        let configuration = try NessieConfiguration(baseURL: url,
                                                    apiKey: "test-key", customerID: "customer")
        let client = NessieAPIClient(configuration: configuration, transport: transport)
        do {
            let _: [NessieAccount] = try await client.accounts()
            XCTFail("Expected invalidAPIKey")
        } catch let error as BankingError {
            XCTAssertEqual(error, .invalidAPIKey)
        }
    }

    func testKnownNessieWithdrawalSchemaErrorDoesNotBlockOtherAccountData() async throws {
        let baseURL = try XCTUnwrap(URL(string: "https://example.test"))
        let configuration = try NessieConfiguration(
            baseURL: baseURL,
            apiKey: "test-key",
            customerID: "customer-1"
        )
        let provider = NessieBankingProvider(
            configuration: configuration,
            transport: WithdrawalSchemaErrorTransport()
        )

        let accounts = try await provider.fetchAccounts()
        let account = try XCTUnwrap(accounts.first)
        let transactions = try await provider.fetchTransactions(for: account)

        XCTAssertTrue(transactions.isEmpty)
    }

    func testNessieNoTransactionsFoundIsAnEmptyCollection() async throws {
        let baseURL = try XCTUnwrap(URL(string: "https://example.test"))
        let configuration = try NessieConfiguration(
            baseURL: baseURL,
            apiKey: "test-key",
            customerID: "customer-1"
        )
        let client = NessieAPIClient(
            configuration: configuration,
            transport: NoTransactionsFoundTransport()
        )

        let transfers: [NessieTransfer] = try await client.transfers(accountID: "account-1")

        XCTAssertTrue(transfers.isEmpty)
    }

    private func fixture<T: Decodable>(_ name: String) throws -> T {
        let url = try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: "json"))
        return try JSONDecoder().decode(T.self, from: Data(contentsOf: url))
    }

    private func externalTransaction(id: String, accountID: String = "account-1",
                                     description: String, amount: Int64) -> ExternalBankTransaction {
        ExternalBankTransaction(provider: .nessie, externalTransactionID: id,
                                externalAccountID: accountID, externalCustomerID: "customer-1",
                                transactionDate: Date(timeIntervalSince1970: 1_700_000_000),
                                description: description, sourceType: .purchase, direction: .outflow,
                                amountMinorUnits: amount)
    }
}

private actor DiagnosticCollector {
    private var recorded: [BankingDiagnosticEvent] = []

    func append(_ event: BankingDiagnosticEvent) { recorded.append(event) }
    func events() -> [BankingDiagnosticEvent] { recorded }
}

private actor MultiAccountMockProvider: BankingProvider {
    let accounts: [ExternalBankAccount]
    let transactionsByAccount: [String: [ExternalBankTransaction]]
    let failingAccountIDs: Set<String>

    init(accounts: [ExternalBankAccount],
         transactionsByAccount: [String: [ExternalBankTransaction]],
         failingAccountIDs: Set<String> = []) {
        self.accounts = accounts
        self.transactionsByAccount = transactionsByAccount
        self.failingAccountIDs = failingAccountIDs
    }

    func connect() async throws -> BankConnection {
        BankConnection(id: "connection", provider: .nessie,
                       externalCustomerID: accounts.first?.externalCustomerID ?? "customer-1",
                       status: .connecting, connectedAt: Date())
    }

    func fetchAccounts() async throws -> [ExternalBankAccount] { accounts }

    func fetchTransactions(for account: ExternalBankAccount) async throws -> [ExternalBankTransaction] {
        if failingAccountIDs.contains(account.externalAccountID) {
            throw BankingError.networkError("Simulated account failure")
        }
        return transactionsByAccount[account.externalAccountID] ?? []
    }
}

private actor WithdrawalSchemaErrorTransport: NessieTransport {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let url = try XCTUnwrap(request.url)
        let statusCode: Int
        let body: String

        if url.path.hasSuffix("/withdrawals") {
            statusCode = 400
            body = #"{"error":"1 validation error for Withdrawal\\nstatus\\n field required (type=value_error.missing)"}"#
        } else if url.path.hasSuffix("/accounts") {
            statusCode = 200
            body = #"[{"_id":"account-1","type":"Checking","nickname":"Test","balance":100,"customer_id":"customer-1"}]"#
        } else {
            statusCode = 200
            body = "[]"
        }

        let response = try XCTUnwrap(HTTPURLResponse(
            url: url,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: nil
        ))
        return (Data(body.utf8), response)
    }
}

private actor NoTransactionsFoundTransport: NessieTransport {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let url = try XCTUnwrap(request.url)
        let response = try XCTUnwrap(HTTPURLResponse(
            url: url,
            statusCode: 404,
            httpVersion: nil,
            headerFields: nil
        ))
        return (Data(#""No transfers found for this account""#.utf8), response)
    }
}

private actor MockBankingProvider: BankingProvider {
    let account: ExternalBankAccount
    var storedTransactions: [ExternalBankTransaction]
    init(account: ExternalBankAccount, transactions: [ExternalBankTransaction]) {
        self.account = account; self.storedTransactions = transactions
    }
    func connect() async throws -> BankConnection {
        BankConnection(id: "connection", provider: .nessie, externalCustomerID: account.externalCustomerID,
                       status: .connecting, connectedAt: Date())
    }
    func fetchAccounts() async throws -> [ExternalBankAccount] { [account] }
    func fetchTransactions(for account: ExternalBankAccount) async throws -> [ExternalBankTransaction] { storedTransactions }
    func setTransactions(_ transactions: [ExternalBankTransaction]) { storedTransactions = transactions }
}

private actor StubTransport: NessieTransport {
    let data: Data
    let response: HTTPURLResponse
    init(data: Data, response: HTTPURLResponse) { self.data = data; self.response = response }
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) { (data, response) }
}
