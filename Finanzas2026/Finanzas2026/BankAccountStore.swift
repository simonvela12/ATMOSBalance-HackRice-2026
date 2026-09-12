import Combine
import FinanceCore
import Foundation

@MainActor
final class BankAccountStore: ObservableObject {
    enum Phase: Equatable {
        case idle
        case loadingCache
        case connecting
        case connected
        case failed(String)
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var accounts: [FinanceCore.FinancialAccount] = []
    @Published private(set) var transactions: [FinanceCore.FinancialTransaction] = []
    @Published private(set) var lastSyncResult: SyncResult?

    private let repository: FileFinancialRepository

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let storeURL = support
            .appendingPathComponent("Finanzas2026", isDirectory: true)
            .appendingPathComponent("nessie-store.json")
        repository = try! FileFinancialRepository(fileURL: storeURL)

        Task { [weak self] in
            await self?.reloadCachedData()
        }
    }

    var isLinked: Bool { !accounts.isEmpty }

    var totalAvailableCash: Double {
        Double(
            accounts
                .filter { $0.accountType != .creditCard }
                .reduce(Int64(0)) { $0 + $1.balanceMinorUnits }
        ) / 100
    }

    func linkNessieAccount(apiKey: String, customerID: String) async {
        phase = .connecting

        do {
            let configuration = try NessieConfiguration(
                baseURL: URL(string: "https://api.nessieisreal.com"),
                apiKey: apiKey,
                customerID: customerID
            )
            let provider = NessieBankingProvider(configuration: configuration)
            let service = BankSyncService(provider: provider, repository: repository)
            lastSyncResult = try await service.syncAll()
            try await reloadFromRepository()
            phase = .connected
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    func reloadCachedData() async {
        phase = .loadingCache
        do {
            try await repository.load()
            try await reloadFromRepository()
            phase = accounts.isEmpty ? .idle : .connected
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    private func reloadFromRepository() async throws {
        accounts = try await repository.accounts()
        transactions = try await repository.transactions(from: nil, to: nil)
    }
}
