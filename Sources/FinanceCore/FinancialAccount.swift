import Foundation

public enum AccountType: String, Codable, CaseIterable, Sendable {
    case checking, savings, creditCard, cash, other
}

public struct FinancialAccount: Identifiable, Codable, Hashable, Sendable {
    public let id: String
    public let provider: BankingProviderID
    public let externalAccountID: String
    public let externalCustomerID: String
    public var name: String
    public var accountType: AccountType
    public var balanceMinorUnits: Int64
    public var currencyCode: String
    public var lastSyncedAt: Date

    public init(id: String, provider: BankingProviderID, externalAccountID: String,
                externalCustomerID: String, name: String, accountType: AccountType,
                balanceMinorUnits: Int64, currencyCode: String, lastSyncedAt: Date) {
        self.id = id; self.provider = provider; self.externalAccountID = externalAccountID
        self.externalCustomerID = externalCustomerID; self.name = name; self.accountType = accountType
        self.balanceMinorUnits = balanceMinorUnits; self.currencyCode = currencyCode
        self.lastSyncedAt = lastSyncedAt
    }
}
