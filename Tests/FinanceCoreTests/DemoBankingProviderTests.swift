import XCTest
@testable import FinanceCore

final class DemoBankingProviderTests: XCTestCase {
    func testDemoProviderUsesProductionSyncPipelineAndDeduplicates() async throws {
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
        XCTAssertEqual(accounts.count, 1)
        XCTAssertEqual(accounts.first?.provider, .demo)
        XCTAssertEqual(accounts.first?.balanceMinorUnits, 586_423)
        XCTAssertEqual(transactions.filter { $0.direction == .inflow }.count, 2)
        XCTAssertEqual(transactions.filter { $0.direction == .outflow }.count, 2)
    }
}
