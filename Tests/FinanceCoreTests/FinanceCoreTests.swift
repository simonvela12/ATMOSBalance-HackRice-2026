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

    func testDemoClientSyncsAccountTransactionsAndDeduplicates() async throws {
        let repository = InMemoryFinancialRepository()
        let service = BankSyncService(provider: DemoBankingProvider(), repository: repository)

        let first = try await service.syncAll()
        let second = try await service.syncAll()
        let accounts = try await repository.accounts()
        let transactions = try await repository.transactions(from: nil, to: nil)

        XCTAssertEqual(first.accountsFetched, 1)
        XCTAssertEqual(first.accountsInserted, 1)
        XCTAssertEqual(first.transactionsFetched, 4)
        XCTAssertEqual(first.transactionsInserted, 4)
        XCTAssertEqual(second.transactionsInserted, 0)
        XCTAssertEqual(second.duplicatesIgnored, 4)
        XCTAssertEqual(accounts.first?.provider, .demo)
        XCTAssertEqual(accounts.first?.balanceMinorUnits, 586_423)
        XCTAssertEqual(transactions.filter { $0.direction == .inflow }.count, 2)
        XCTAssertEqual(transactions.filter { $0.direction == .outflow }.count, 2)
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

    private func fixture<T: Decodable>(_ name: String) throws -> T {
        let url = try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: "json"))
        return try JSONDecoder().decode(T.self, from: Data(contentsOf: url))
    }

    private func externalTransaction(id: String, description: String, amount: Int64) -> ExternalBankTransaction {
        ExternalBankTransaction(provider: .nessie, externalTransactionID: id,
                                externalAccountID: "account-1", externalCustomerID: "customer-1",
                                transactionDate: Date(timeIntervalSince1970: 1_700_000_000),
                                description: description, sourceType: .purchase, direction: .outflow,
                                amountMinorUnits: amount)
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
