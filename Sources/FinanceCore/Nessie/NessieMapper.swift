import Foundation

enum NessieMapper {
    static func account(_ dto: NessieAccount, customerID: String, syncedAt: Date) throws -> ExternalBankAccount {
        ExternalBankAccount(
            provider: .nessie,
            externalAccountID: dto.id,
            externalCustomerID: dto.customerID ?? customerID,
            name: dto.nickname?.nilIfBlank ?? dto.type?.nilIfBlank ?? "Nessie Account",
            accountType: mapAccountType(dto.type),
            balanceMinorUnits: try MoneyConversion.minorUnits(from: dto.balance),
            currencyCode: "USD"
        )
    }

    static func purchase(_ dto: NessiePurchase, account: ExternalBankAccount,
                         merchantName: String? = nil, category: String? = nil) throws -> ExternalBankTransaction {
        try transaction(id: dto.id, account: account, date: dto.purchaseDate, amount: dto.amount,
                        description: dto.description ?? merchantName ?? dto.merchantID ?? "Purchase",
                        merchantName: merchantName, category: category, status: dto.status,
                        source: .purchase, direction: .outflow, isTransfer: false,
                        fallbackParts: [dto.merchantID, dto.payerID])
    }

    static func deposit(_ dto: NessieDeposit, account: ExternalBankAccount) throws -> ExternalBankTransaction {
        try transaction(id: dto.id, account: account, date: dto.transactionDate, amount: dto.amount,
                        description: dto.description ?? "Deposit", status: dto.status,
                        source: .deposit, direction: .inflow, isTransfer: false,
                        fallbackParts: [dto.payeeID])
    }

    static func withdrawal(_ dto: NessieWithdrawal, account: ExternalBankAccount) throws -> ExternalBankTransaction {
        try transaction(id: dto.id, account: account, date: dto.transactionDate, amount: dto.amount,
                        description: dto.description ?? "Withdrawal", status: dto.status,
                        source: .withdrawal, direction: .outflow, isTransfer: false,
                        fallbackParts: [dto.payerID])
    }

    static func transfer(_ dto: NessieTransfer, account: ExternalBankAccount) throws -> ExternalBankTransaction {
        let direction: TransactionDirection
        if dto.payerID == account.externalAccountID { direction = .outflow }
        else if dto.payeeID == account.externalAccountID { direction = .inflow }
        // The current Nessie sandbox also returns account-scoped transfers with
        // `id` (rather than `_id`) and without payer/payee fields. The account in
        // the request path is the source account for this representation.
        else if dto.payerID == nil && dto.payeeID == nil { direction = .outflow }
        else { throw BankingError.malformedTransaction("Transfer does not reference account \(account.externalAccountID)") }
        return try transaction(id: dto.id, account: account, date: dto.transactionDate, amount: dto.amount,
                               description: dto.description ?? "Transfer", status: dto.status,
                               source: .transfer, direction: direction, isTransfer: true,
                               fallbackParts: [dto.payerID, dto.payeeID])
    }

    private static func transaction(id: String?, account: ExternalBankAccount, date: String?, amount: Decimal?,
                                    description: String, merchantName: String? = nil, category: String? = nil,
                                    status: String?, source: TransactionSourceType,
                                    direction: TransactionDirection, isTransfer: Bool,
                                    fallbackParts: [String?]) throws -> ExternalBankTransaction {
        guard let date, let parsedDate = parseDate(date) else {
            throw BankingError.malformedTransaction("\(source.rawValue) has no valid date")
        }
        guard let amount else { throw BankingError.malformedTransaction("\(source.rawValue) has no amount") }
        let converted = try MoneyConversion.minorUnits(from: amount)
        guard converted != Int64.min else {
            throw BankingError.malformedTransaction("Amount is outside supported range")
        }
        let minorUnits = converted < 0 ? -converted : converted
        let rawID = id?.nilIfBlank ?? deterministicID(
            [account.provider.rawValue, account.externalAccountID, source.rawValue, date,
             String(describing: amount), description] + fallbackParts.compactMap { $0 }
        )
        let externalID = isTransfer ? "\(source.rawValue):\(rawID):\(direction.rawValue)" : "\(source.rawValue):\(rawID)"
        return ExternalBankTransaction(
            provider: account.provider, externalTransactionID: externalID,
            externalAccountID: account.externalAccountID, externalCustomerID: account.externalCustomerID,
            transactionDate: parsedDate, merchantName: merchantName, description: description,
            category: category, sourceType: source, direction: direction, amountMinorUnits: minorUnits,
            isPending: status?.lowercased() == "pending", isTransfer: isTransfer
        )
    }

    private static func mapAccountType(_ value: String?) -> AccountType {
        let normalized = value?.lowercased().replacingOccurrences(of: "_", with: " ") ?? ""
        if normalized.contains("checking") { return .checking }
        if normalized.contains("saving") { return .savings }
        if normalized.contains("credit") { return .creditCard }
        return .other
    }

    private static func parseDate(_ value: String) -> Date? {
        if let date = ISO8601DateFormatter().date(from: value) { return date }
        for format in ["yyyy-MM-dd", "yyyy-MM-dd HH:mm:ss"] {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = format
            if let date = formatter.date(from: value) { return date }
        }
        return nil
    }

    private static func deterministicID(_ parts: [String]) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in parts.joined(separator: "|").utf8 { hash = (hash ^ UInt64(byte)) &* 1_099_511_628_211 }
        return String(hash, radix: 16)
    }
}

private extension String {
    var nilIfBlank: String? { trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : self }
}
