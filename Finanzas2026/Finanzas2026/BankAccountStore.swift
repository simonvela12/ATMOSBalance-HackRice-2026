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
    private var syncServices: [String: BankSyncService] = [:]
    private var automaticRefreshTask: Task<Void, Never>?
    private let automaticRefreshInterval: Duration

    init(automaticRefreshInterval: Duration = .seconds(15 * 60)) {
        self.automaticRefreshInterval = automaticRefreshInterval
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let storeURL = support
            .appendingPathComponent("Finanzas2026", isDirectory: true)
            .appendingPathComponent("nessie-store.json")
        repository = try! FileFinancialRepository(fileURL: storeURL)

        Task { [weak self] in
            await self?.reloadCachedData()
        }
    }

    deinit {
        automaticRefreshTask?.cancel()
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
            syncServices["nessie|\(customerID)"] = service
            lastSyncResult = try await service.syncAll()
            try await reloadFromRepository()
            phase = .connected
            startAutomaticRefreshIfNeeded()
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    func refreshLinkedAccounts() async {
        guard !syncServices.isEmpty else { return }
        phase = .connecting

        var errors: [String] = []
        for (connectionID, service) in syncServices.sorted(by: { $0.key < $1.key }) {
            do {
                lastSyncResult = try await service.syncAll()
            } catch {
                errors.append("\(connectionID): \(error.localizedDescription)")
            }
        }

        do {
            try await reloadFromRepository()
            phase = errors.isEmpty ? .connected : .failed(errors.joined(separator: "\n"))
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

    private func startAutomaticRefreshIfNeeded() {
        guard automaticRefreshTask == nil else { return }
        automaticRefreshTask = Task { [weak self, automaticRefreshInterval] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: automaticRefreshInterval)
                } catch {
                    return
                }
                guard !Task.isCancelled else { return }
                await self?.refreshLinkedAccounts()
            }
        }
    }
}
