import Foundation

public enum TransactionDirection: String, Codable, CaseIterable, Sendable { case inflow, outflow }
public enum TransactionSourceType: String, Codable, CaseIterable, Sendable {
    case purchase, deposit, withdrawal, transfer, refund, other
}

public struct FinancialTransaction: Identifiable, Codable, Hashable, Sendable {
    public let id: String
    public let deduplicationKey: String
    public let provider: BankingProviderID
    public let externalTransactionID: String
    public let externalAccountID: String
    public let externalCustomerID: String
    public var transactionDate: Date
    public var postedDate: Date?
    public var merchantName: String?
    public var transactionDescription: String
    public var category: String?
    public var sourceType: TransactionSourceType
    public var direction: TransactionDirection
    public var amountMinorUnits: Int64
    public var signedAmountMinorUnits: Int64
    public var currencyCode: String
    public var isPending: Bool
    public var isTransfer: Bool
    public var lastUpdatedAt: Date

    public init(id: String, deduplicationKey: String, provider: BankingProviderID,
                externalTransactionID: String, externalAccountID: String, externalCustomerID: String,
                transactionDate: Date, postedDate: Date? = nil, merchantName: String? = nil,
                transactionDescription: String, category: String? = nil,
                sourceType: TransactionSourceType, direction: TransactionDirection,
                amountMinorUnits: Int64, currencyCode: String = "USD",
                isPending: Bool = false, isTransfer: Bool = false, lastUpdatedAt: Date) {
        precondition(amountMinorUnits >= 0, "Transaction amount must be non-negative")
        self.id = id; self.deduplicationKey = deduplicationKey; self.provider = provider
        self.externalTransactionID = externalTransactionID; self.externalAccountID = externalAccountID
        self.externalCustomerID = externalCustomerID; self.transactionDate = transactionDate
        self.postedDate = postedDate; self.merchantName = merchantName
        self.transactionDescription = transactionDescription; self.category = category
        self.sourceType = sourceType; self.direction = direction; self.amountMinorUnits = amountMinorUnits
        self.signedAmountMinorUnits = direction == .inflow ? amountMinorUnits : -amountMinorUnits
        self.currencyCode = currencyCode; self.isPending = isPending; self.isTransfer = isTransfer
        self.lastUpdatedAt = lastUpdatedAt
    }

    func hasSameMutableContent(as other: FinancialTransaction) -> Bool {
        transactionDate == other.transactionDate && postedDate == other.postedDate &&
        merchantName == other.merchantName && transactionDescription == other.transactionDescription &&
        category == other.category && sourceType == other.sourceType && direction == other.direction &&
        amountMinorUnits == other.amountMinorUnits && signedAmountMinorUnits == other.signedAmountMinorUnits &&
        currencyCode == other.currencyCode && isPending == other.isPending && isTransfer == other.isTransfer
    }
}
