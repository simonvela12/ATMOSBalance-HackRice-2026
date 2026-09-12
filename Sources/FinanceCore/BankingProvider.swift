import Foundation

public struct ExternalBankAccount: Hashable, Sendable {
    public let provider: BankingProviderID
    public let externalAccountID: String
    public let externalCustomerID: String
    public let name: String
    public let accountType: AccountType
    public let balanceMinorUnits: Int64
    public let currencyCode: String

    public init(provider: BankingProviderID, externalAccountID: String, externalCustomerID: String,
                name: String, accountType: AccountType, balanceMinorUnits: Int64,
                currencyCode: String = "USD") {
        self.provider = provider; self.externalAccountID = externalAccountID
        self.externalCustomerID = externalCustomerID; self.name = name; self.accountType = accountType
        self.balanceMinorUnits = balanceMinorUnits; self.currencyCode = currencyCode
    }
}

public struct ExternalBankTransaction: Hashable, Sendable {
    public let provider: BankingProviderID
    public let externalTransactionID: String
    public let externalAccountID: String
    public let externalCustomerID: String
    public let transactionDate: Date
    public let postedDate: Date?
    public let merchantName: String?
    public let description: String
    public let category: String?
    public let sourceType: TransactionSourceType
    public let direction: TransactionDirection
    public let amountMinorUnits: Int64
    public let currencyCode: String
    public let isPending: Bool
    public let isTransfer: Bool

    public init(provider: BankingProviderID, externalTransactionID: String, externalAccountID: String,
                externalCustomerID: String, transactionDate: Date, postedDate: Date? = nil,
                merchantName: String? = nil, description: String, category: String? = nil,
                sourceType: TransactionSourceType, direction: TransactionDirection,
                amountMinorUnits: Int64, currencyCode: String = "USD",
                isPending: Bool = false, isTransfer: Bool = false) {
        self.provider = provider; self.externalTransactionID = externalTransactionID
        self.externalAccountID = externalAccountID; self.externalCustomerID = externalCustomerID
        self.transactionDate = transactionDate; self.postedDate = postedDate; self.merchantName = merchantName
        self.description = description; self.category = category; self.sourceType = sourceType
        self.direction = direction; self.amountMinorUnits = amountMinorUnits; self.currencyCode = currencyCode
        self.isPending = isPending; self.isTransfer = isTransfer
    }
}

public protocol BankingProvider: Sendable {
    func connect() async throws -> BankConnection
    func fetchAccounts() async throws -> [ExternalBankAccount]
    func fetchTransactions(for account: ExternalBankAccount) async throws -> [ExternalBankTransaction]
}
