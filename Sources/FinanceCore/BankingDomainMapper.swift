import Foundation

enum BankingDomainMapper {
    static func account(_ external: ExternalBankAccount, syncedAt: Date) -> FinancialAccount {
        let id = "\(external.provider.rawValue)|\(external.externalAccountID)"
        return FinancialAccount(id: id, provider: external.provider,
                                externalAccountID: external.externalAccountID,
                                externalCustomerID: external.externalCustomerID, name: external.name,
                                accountType: external.accountType, balanceMinorUnits: external.balanceMinorUnits,
                                providerReportedBalanceMinorUnits: external.balanceMinorUnits,
                                currencyCode: external.currencyCode, lastSyncedAt: syncedAt)
    }

    static func transaction(_ external: ExternalBankTransaction, syncedAt: Date) -> FinancialTransaction {
        let key = [external.provider.rawValue, external.externalAccountID,
                   external.sourceType.rawValue, external.externalTransactionID].joined(separator: "|")
        return FinancialTransaction(
            id: key, deduplicationKey: key, provider: external.provider,
            externalTransactionID: external.externalTransactionID,
            externalAccountID: external.externalAccountID,
            externalCustomerID: external.externalCustomerID,
            transactionDate: external.transactionDate, postedDate: external.postedDate,
            merchantName: external.merchantName, transactionDescription: external.description,
            category: external.category, sourceType: external.sourceType, direction: external.direction,
            amountMinorUnits: external.amountMinorUnits, currencyCode: external.currencyCode,
            isPending: external.isPending, isTransfer: external.isTransfer, lastUpdatedAt: syncedAt
        )
    }
}
