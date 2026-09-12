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
    private let diagnostics = BankingDiagnostics.console

    // Fast active-app cadence for the hackathon demo. Use a longer server-friendly
    // interval before production release.
    init(automaticRefreshInterval: Duration = .seconds(10)) {
        self.automaticRefreshInterval = automaticRefreshInterval
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let storeURL = support
            .appendingPathComponent("Finanzas2026", isDirectory: true)
            .appendingPathComponent("nessie-store.json")
        // This app store is intentionally Nessie-only. Old demo/provider records
        // from previous builds are discarded when the cache is loaded.
        repository = try! FileFinancialRepository(fileURL: storeURL, allowedProviders: [.nessie])

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
            let provider = NessieBankingProvider(configuration: configuration,
                                                 diagnostics: diagnostics)
            let service = BankSyncService(provider: provider, repository: repository,
                                          diagnostics: diagnostics)
            syncServices["nessie|\(customerID)"] = service
            lastSyncResult = try await service.syncAll()
            try await reloadFromRepository()

            // A sync can succeed and still return no accounts. Without this the app
            // reports success while `isLinked` stays false, stranding the user on the
            // connect screen with no explanation.
            guard (lastSyncResult?.accountsFetched ?? 0) > 0 else {
                syncServices.removeValue(forKey: "nessie|\(customerID)")
                phase = .failed("Connected to Nessie, but customer \(customerID) has no accounts. Check the customer ID.")
                return
            }

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
        await diagnostics.record(.financialStateUpdated, details: [
            "accounts": String(accounts.count),
            "transactions": String(transactions.count)
        ])
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
