import Foundation

/// Deterministic local data for demos, previews, and offline development.
public struct DemoBankingProvider: BankingProvider, Sendable {
    public static let customerID = "demo-customer-001"
    public static let accountID = "demo-checking-001"

    private let account: ExternalBankAccount
    private let transactions: [ExternalBankTransaction]

    public init() {
        account = ExternalBankAccount(
            provider: .demo,
            externalAccountID: Self.accountID,
            externalCustomerID: Self.customerID,
            name: "Everyday Checking",
            accountType: .checking,
            balanceMinorUnits: 586_423,
            currencyCode: "USD"
        )

        let baseDate = Date(timeIntervalSince1970: 1_788_796_800)
        transactions = [
            ExternalBankTransaction(
                provider: .demo,
                externalTransactionID: "demo-paycheck-001",
                externalAccountID: Self.accountID,
                externalCustomerID: Self.customerID,
                transactionDate: baseDate,
                merchantName: "Rice Hackathon Labs",
                description: "Monthly paycheck",
                category: "Income",
                sourceType: .deposit,
                direction: .inflow,
                amountMinorUnits: 320_000
            ),
            ExternalBankTransaction(
                provider: .demo,
                externalTransactionID: "demo-groceries-001",
                externalAccountID: Self.accountID,
                externalCustomerID: Self.customerID,
                transactionDate: baseDate.addingTimeInterval(86_400),
                merchantName: "Neighborhood Market",
                description: "Weekly groceries",
                category: "Groceries",
                sourceType: .purchase,
                direction: .outflow,
                amountMinorUnits: 8_426
            ),
            ExternalBankTransaction(
                provider: .demo,
                externalTransactionID: "demo-rent-001",
                externalAccountID: Self.accountID,
                externalCustomerID: Self.customerID,
                transactionDate: baseDate.addingTimeInterval(2 * 86_400),
                merchantName: "Oak Street Apartments",
                description: "September rent",
                category: "Housing",
                sourceType: .withdrawal,
                direction: .outflow,
                amountMinorUnits: 125_000
            ),
            ExternalBankTransaction(
                provider: .demo,
                externalTransactionID: "demo-refund-001",
                externalAccountID: Self.accountID,
                externalCustomerID: Self.customerID,
                transactionDate: baseDate.addingTimeInterval(3 * 86_400),
                merchantName: "Neighborhood Market",
                description: "Returned item refund",
                category: "Groceries",
                sourceType: .refund,
                direction: .inflow,
                amountMinorUnits: 1_849
            )
        ]
    }

    public func connect() async throws -> BankConnection {
        BankConnection(
            id: "demo-connection-001",
            provider: .demo,
            externalCustomerID: Self.customerID,
            status: .connecting,
            connectedAt: Date()
        )
    }

    public func fetchAccounts() async throws -> [ExternalBankAccount] { [account] }

    public func fetchTransactions(for account: ExternalBankAccount) async throws -> [ExternalBankTransaction] {
        account.externalAccountID == Self.accountID ? transactions : []
    }
}
