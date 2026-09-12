import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import XCTest
@testable import FinanceCore

final class NessieIntegrationTests: XCTestCase {
    func testClientBuildsAuthenticatedGETRequestWithConfiguredTimeout() async throws {
        let transport = RoutingNessieTransport(routes: [
            "/customers/customer-123/accounts": .json("[]")
        ])
        let configuration = try NessieConfiguration(
            baseURL: try XCTUnwrap(URL(string: "https://api.nessieisreal.com")),
            apiKey: "test-key", customerID: "customer-123", requestTimeout: 7
        )

        _ = try await NessieAPIClient(configuration: configuration, transport: transport).accounts()
        let recordedRequests = await transport.recordedRequests()
        let request = try XCTUnwrap(recordedRequests.first)
        let components = try XCTUnwrap(URLComponents(string: request.url))

        XCTAssertEqual(request.method, "GET")
        XCTAssertEqual(request.accept, "application/json")
        XCTAssertEqual(request.timeout, 7)
        XCTAssertEqual(components.path, "/customers/customer-123/accounts")
        XCTAssertEqual(components.queryItems, [URLQueryItem(name: "key", value: "test-key")])
    }

    func testNessieDiagnosticsExposePathAndStatusButNeverAPIKey() async throws {
        let collector = NessieDiagnosticCollector()
        let diagnostics = BankingDiagnostics { event in await collector.append(event) }
        let transport = RoutingNessieTransport(routes: [
            "/customers/customer-123/accounts": .json("[]")
        ])
        let client = NessieAPIClient(configuration: try configuration(), transport: transport,
                                     diagnostics: diagnostics)

        let _: [NessieAccount] = try await client.accounts()
        let events = await collector.events()
        let serializedDetails = events.flatMap(\.details.values).joined(separator: " ")

        XCTAssertEqual(events.map(\.kind), [.nessieRequest, .nessieResponse])
        XCTAssertEqual(events.first?.details["path"], "/customers/customer-123/accounts")
        XCTAssertEqual(events.last?.details["status"], "200")
        XCTAssertFalse(serializedDetails.contains("test-key"))
        XCTAssertFalse(serializedDetails.contains("?key="))
    }

    func testCompleteNessieSyncMapsEveryEndpointAndCachesMerchant() async throws {
        let transport = RoutingNessieTransport(routes: fullRoutes)
        let configuration = try configuration()
        let provider = NessieBankingProvider(configuration: configuration, transport: transport)
        let repository = InMemoryFinancialRepository()
        let service = BankSyncService(provider: provider, repository: repository)

        let first = try await service.syncAll()
        let second = try await service.syncAll()
        let accounts = try await repository.accounts()
        let transactions = try await repository.transactions(from: nil, to: nil)
        let requests = await transport.recordedRequests()

        XCTAssertEqual(first.accountsFetched, 1)
        XCTAssertEqual(first.transactionsFetched, 5)
        XCTAssertEqual(first.transactionsInserted, 5)
        XCTAssertEqual(second.transactionsInserted, 0)
        XCTAssertEqual(second.duplicatesIgnored, 5)
        XCTAssertEqual(accounts.first?.accountType, .checking)
        XCTAssertEqual(accounts.first?.balanceMinorUnits, 250_050)
        XCTAssertEqual(transactions.filter { $0.direction == .inflow }.count, 1)
        XCTAssertEqual(transactions.filter { $0.direction == .outflow }.count, 4)
        XCTAssertEqual(transactions.filter { $0.isTransfer }.count, 1)
        XCTAssertEqual(transactions.filter { $0.merchantName == "Test Market" }.count, 2)
        XCTAssertTrue(transactions.contains { $0.category == "Food, Grocery" })
        XCTAssertEqual(requests.filter { URL(string: $0.url)?.path == "/merchants/merchant-1" }.count, 1)
        let requestCounts = Dictionary(grouping: requests, by: { URL(string: $0.url)?.path ?? "" })
            .mapValues(\.count)
        XCTAssertEqual(requestCounts["/customers/customer-123/accounts"], 2)
        XCTAssertEqual(requestCounts["/accounts/account-1/purchases"], 2)
        XCTAssertEqual(requestCounts["/accounts/account-1/deposits"], 2)
        XCTAssertEqual(requestCounts["/accounts/account-1/withdrawals"], 2)
        XCTAssertEqual(requestCounts["/accounts/account-1/transfers"], 2)
        XCTAssertTrue(requests.allSatisfy { request in
            URLComponents(string: request.url)?.queryItems?.contains(
                URLQueryItem(name: "key", value: "test-key")
            ) == true
        })
    }

    func testMerchantFailureDoesNotDiscardPurchase() async throws {
        var routes = emptyTransactionRoutes
        routes["/accounts/account-1/purchases"] = .json("""
            [{"_id":"purchase-1","merchant_id":"merchant-down","payer_id":"account-1",
              "purchase_date":"2026-09-01","amount":12.34,"status":"completed",
              "description":"Purchase without enrichment"}]
            """)
        routes["/merchants/merchant-down"] = .json("{\"message\":\"temporarily unavailable\"}", status: 503)
        let transport = RoutingNessieTransport(routes: routes)
        let provider = NessieBankingProvider(configuration: try configuration(), transport: transport)
        let account = ExternalBankAccount(provider: .nessie, externalAccountID: "account-1",
                                          externalCustomerID: "customer-123", name: "Checking",
                                          accountType: .checking, balanceMinorUnits: 0)

        let transactions = try await provider.fetchTransactions(for: account)
        _ = try await provider.fetchTransactions(for: account)
        let requests = await transport.recordedRequests()

        XCTAssertEqual(transactions.count, 1)
        XCTAssertEqual(transactions.first?.description, "Purchase without enrichment")
        XCTAssertNil(transactions.first?.merchantName)
        XCTAssertEqual(transactions.first?.amountMinorUnits, 1_234)
        XCTAssertEqual(requests.filter { URL(string: $0.url)?.path == "/merchants/merchant-down" }.count, 1)
    }

    func testMerchantAcceptsNessieSingleStringCategory() async throws {
        var routes = emptyTransactionRoutes
        routes["/accounts/account-1/purchases"] = .json("""
            [{"_id":"purchase-1","merchant_id":"merchant-1","payer_id":"account-1",
              "purchase_date":"2026-09-01","amount":12.34,"status":"completed"}]
            """)
        routes["/merchants/merchant-1"] = .json("""
            {"_id":"merchant-1","name":"Campus Market","category":"Groceries"}
            """)
        let provider = NessieBankingProvider(
            configuration: try configuration(),
            transport: RoutingNessieTransport(routes: routes)
        )

        let transactions = try await provider.fetchTransactions(for: testAccount())

        XCTAssertEqual(transactions.first?.merchantName, "Campus Market")
        XCTAssertEqual(transactions.first?.category, "Groceries")
    }

    func testNessieStatusAndDecodingFailuresBecomeTypedErrors() async throws {
        try await assertAccountsError(status: 401, body: "{}", expected: .invalidAPIKey)
        try await assertAccountsError(status: 403, body: "{}", expected: .invalidAPIKey)
        try await assertAccountsError(status: 429, body: "{}", expected: .rateLimited)
        try await assertAccountsError(status: 500, body: "{\"message\":\"sandbox failure\"}",
                                      expected: .serverError(statusCode: 500, message: "sandbox failure"))

        let transport = RoutingNessieTransport(routes: [
            "/customers/customer-123/accounts": .json("not-json")
        ])
        let client = NessieAPIClient(configuration: try configuration(), transport: transport)
        do {
            let _: [NessieAccount] = try await client.accounts()
            XCTFail("Expected decoding error")
        } catch let error as BankingError {
            guard case .decodingError = error else { return XCTFail("Unexpected error: \(error)") }
        }
    }

    func testProviderMapsAccount404ToCustomerNotFound() async throws {
        let transport = RoutingNessieTransport(routes: [
            "/customers/customer-123/accounts": .json("{\"message\":\"missing\"}", status: 404)
        ])
        let provider = NessieBankingProvider(configuration: try configuration(), transport: transport)

        do {
            _ = try await provider.fetchAccounts()
            XCTFail("Expected customerNotFound")
        } catch let error as BankingError {
            XCTAssertEqual(error, .customerNotFound("customer-123"))
        }
    }

    func testTransportFailureBecomesNetworkError() async throws {
        let client = NessieAPIClient(configuration: try configuration(), transport: FailingNessieTransport())
        do {
            let _: [NessieAccount] = try await client.accounts()
            XCTFail("Expected networkError")
        } catch let error as BankingError {
            guard case .networkError = error else { return XCTFail("Unexpected error: \(error)") }
        }
    }

    func testConfigurationRejectsNonPositiveTimeout() throws {
        XCTAssertThrowsError(try NessieConfiguration(apiKey: "key", customerID: "customer", requestTimeout: 0)) {
            XCTAssertEqual($0 as? BankingError,
                           .invalidConfiguration("Nessie request timeout must be positive"))
        }
    }

    func testDefaultConfigurationUsesHTTPS() throws {
        let configuration = try NessieConfiguration(apiKey: "key", customerID: "customer")
        XCTAssertEqual(configuration.baseURL.scheme, "https")
        XCTAssertEqual(configuration.baseURL.host, "api.nessieisreal.com")
    }

    func testCompleteNessieSyncSurvivesFileRepositoryReload() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FinanceCoreTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("finance-store.json")
        let repository = try FileFinancialRepository(fileURL: fileURL)
        let provider = NessieBankingProvider(configuration: try configuration(),
                                             transport: RoutingNessieTransport(routes: fullRoutes))

        let result = try await BankSyncService(provider: provider, repository: repository).syncAll()
        let reloaded = try FileFinancialRepository(fileURL: fileURL)
        try await reloaded.load()
        let connections = try await reloaded.connections()
        let accounts = try await reloaded.accounts()
        let transactions = try await reloaded.transactions(from: nil, to: nil)

        XCTAssertEqual(result.transactionsInserted, 5)
        XCTAssertEqual(connections.count, 1)
        XCTAssertEqual(accounts.count, 1)
        XCTAssertEqual(transactions.count, 5)
    }

    func testMissingNessieTransactionIDProducesStableFallbackIdentity() throws {
        let data = Data("""
            {"merchant_id":"merchant-1","payer_id":"account-1","purchase_date":"2026-09-01",
             "amount":9.99,"status":"completed","description":"Stable purchase"}
            """.utf8)
        let purchase = try JSONDecoder().decode(NessiePurchase.self, from: data)
        let account = testAccount()

        let first = try NessieMapper.purchase(purchase, account: account)
        let second = try NessieMapper.purchase(purchase, account: account)

        XCTAssertEqual(first.externalTransactionID, second.externalTransactionID)
        XCTAssertTrue(first.externalTransactionID.hasPrefix("purchase:"))
    }

    func testMalformedNessiePayloadIsRejectedInsteadOfInventingData() throws {
        let purchase = try JSONDecoder().decode(
            NessiePurchase.self,
            from: Data("{\"_id\":\"broken\",\"amount\":10}".utf8)
        )

        XCTAssertThrowsError(try NessieMapper.purchase(purchase, account: testAccount())) {
            guard case .malformedTransaction = $0 as? BankingError else {
                return XCTFail("Unexpected error: \($0)")
            }
        }
    }

    func testTransferThatDoesNotReferenceAccountIsRejected() throws {
        let transfer = try JSONDecoder().decode(
            NessieTransfer.self,
            from: Data("""
                {"_id":"transfer-x","payer_id":"another-account","payee_id":"third-account",
                 "transaction_date":"2026-09-01","amount":25,"status":"completed"}
                """.utf8)
        )

        XCTAssertThrowsError(try NessieMapper.transfer(transfer, account: testAccount())) {
            guard case .malformedTransaction = $0 as? BankingError else {
                return XCTFail("Unexpected error: \($0)")
            }
        }
    }

    private func configuration() throws -> NessieConfiguration {
        try NessieConfiguration(baseURL: URL(string: "https://api.nessieisreal.com"),
                                apiKey: "test-key", customerID: "customer-123")
    }

    private func testAccount() -> ExternalBankAccount {
        ExternalBankAccount(provider: .nessie, externalAccountID: "account-1",
                            externalCustomerID: "customer-123", name: "Checking",
                            accountType: .checking, balanceMinorUnits: 0)
    }

    private func assertAccountsError(status: Int, body: String, expected: BankingError) async throws {
        let transport = RoutingNessieTransport(routes: [
            "/customers/customer-123/accounts": .json(body, status: status)
        ])
        let client = NessieAPIClient(configuration: try configuration(), transport: transport)
        do {
            let _: [NessieAccount] = try await client.accounts()
            XCTFail("Expected \(expected)")
        } catch let error as BankingError {
            XCTAssertEqual(error, expected)
        }
    }

    private var emptyTransactionRoutes: [String: StubResponse] {
        [
            "/accounts/account-1/purchases": .json("[]"),
            "/accounts/account-1/deposits": .json("[]"),
            "/accounts/account-1/withdrawals": .json("[]"),
            "/accounts/account-1/transfers": .json("[]")
        ]
    }

    private var fullRoutes: [String: StubResponse] {
        var routes = emptyTransactionRoutes
        routes["/customers/customer-123/accounts"] = .json("""
            [{"_id":"account-1","type":"Checking","nickname":"Primary Checking",
              "balance":2500.50,"customer_id":"customer-123"}]
            """)
        routes["/accounts/account-1/purchases"] = .json("""
            [
              {"_id":"purchase-1","merchant_id":"merchant-1","payer_id":"account-1",
               "purchase_date":"2026-09-01","amount":42.25,"status":"completed"},
              {"_id":"purchase-2","merchant_id":"merchant-1","payer_id":"account-1",
               "purchase_date":"2026-09-02","amount":18.75,"status":"pending"}
            ]
            """)
        routes["/accounts/account-1/deposits"] = .json("""
            [{"_id":"deposit-1","payee_id":"account-1","transaction_date":"2026-09-03",
              "amount":500.00,"status":"completed","description":"Paycheck"}]
            """)
        routes["/accounts/account-1/withdrawals"] = .json("""
            [{"_id":"withdrawal-1","payer_id":"account-1","transaction_date":"2026-09-04",
              "amount":20.00,"status":"completed","description":"ATM"}]
            """)
        routes["/accounts/account-1/transfers"] = .json("""
            [{"_id":"transfer-1","payer_id":"account-1","payee_id":"other-account",
              "transaction_date":"2026-09-05","amount":75.00,"status":"completed"}]
            """)
        routes["/merchants/merchant-1"] = .json("""
            {"_id":"merchant-1","name":"Test Market","category":["Food","Grocery"]}
            """)
        return routes
    }
}

private actor NessieDiagnosticCollector {
    private var recorded: [BankingDiagnosticEvent] = []

    func append(_ event: BankingDiagnosticEvent) { recorded.append(event) }
    func events() -> [BankingDiagnosticEvent] { recorded }
}

private struct StubResponse: Sendable {
    let data: Data
    let status: Int

    static func json(_ value: String, status: Int = 200) -> StubResponse {
        StubResponse(data: Data(value.utf8), status: status)
    }
}

private struct RecordedRequest: Sendable {
    let url: String
    let method: String?
    let accept: String?
    let timeout: TimeInterval
}

private actor RoutingNessieTransport: NessieTransport {
    private let routes: [String: StubResponse]
    private var requests: [RecordedRequest] = []

    init(routes: [String: StubResponse]) { self.routes = routes }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let url = try XCTUnwrap(request.url)
        requests.append(RecordedRequest(url: url.absoluteString,
                                        method: request.httpMethod,
                                        accept: request.value(forHTTPHeaderField: "Accept"),
                                        timeout: request.timeoutInterval))
        let stub = routes[url.path] ?? .json("{\"message\":\"unstubbed route\"}", status: 404)
        let response = try XCTUnwrap(HTTPURLResponse(url: url, statusCode: stub.status,
                                                    httpVersion: "HTTP/1.1", headerFields: nil))
        return (stub.data, response)
    }

    func recordedRequests() -> [RecordedRequest] { requests }
}

private struct FailingNessieTransport: NessieTransport {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        throw URLError(.timedOut)
    }
}
