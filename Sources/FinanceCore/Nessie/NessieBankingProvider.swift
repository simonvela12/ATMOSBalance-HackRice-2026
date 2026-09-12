import Foundation

public struct NessieBankingProvider: BankingProvider, Sendable {
    private let configuration: NessieConfiguration
    private let client: NessieAPIClient
    private let merchantCache: MerchantCache

    public init(configuration: NessieConfiguration, transport: any NessieTransport = URLSessionNessieTransport()) {
        self.configuration = configuration
        self.client = NessieAPIClient(configuration: configuration, transport: transport)
        self.merchantCache = MerchantCache()
    }

    public func connect() async throws -> BankConnection {
        BankConnection(id: "nessie|\(configuration.customerID)", provider: .nessie,
                       externalCustomerID: configuration.customerID, status: .connecting, connectedAt: Date())
    }

    public func fetchAccounts() async throws -> [ExternalBankAccount] {
        do {
            return try await client.accounts().map {
                try NessieMapper.account($0, customerID: configuration.customerID, syncedAt: Date())
            }
        } catch BankingError.serverError(let code, _) where code == 404 {
            throw BankingError.customerNotFound(configuration.customerID)
        }
    }

    public func fetchTransactions(for account: ExternalBankAccount) async throws -> [ExternalBankTransaction] {
        async let purchasesRequest = client.purchases(accountID: account.externalAccountID)
        async let depositsRequest = client.deposits(accountID: account.externalAccountID)
        async let withdrawalsRequest = client.withdrawals(accountID: account.externalAccountID)
        async let transfersRequest = client.transfers(accountID: account.externalAccountID)
        let (purchases, deposits, withdrawals, transfers) = try await
            (purchasesRequest, depositsRequest, withdrawalsRequest, transfersRequest)

        var normalized: [ExternalBankTransaction] = []
        for purchase in purchases {
            let merchant: MerchantDetails? = if let id = purchase.merchantID {
                await merchantCache.details(id: id, client: client)
            } else { nil }
            normalized.append(try NessieMapper.purchase(purchase, account: account,
                                                        merchantName: merchant?.name,
                                                        category: merchant?.category))
        }
        normalized += try deposits.map { try NessieMapper.deposit($0, account: account) }
        normalized += try withdrawals.map { try NessieMapper.withdrawal($0, account: account) }
        normalized += try transfers.map { try NessieMapper.transfer($0, account: account) }
        return normalized
    }
}
