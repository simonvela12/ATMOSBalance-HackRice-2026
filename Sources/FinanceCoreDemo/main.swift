import Foundation
import FinanceCore

@main
struct FinanceCoreDemo {
    static func main() async throws {
        let values = loadEnvironmentFile(at: URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(".env"))
        let process = ProcessInfo.processInfo.environment
        let apiKey = process["NESSIE_API_KEY"] ?? values["NESSIE_API_KEY"] ?? ""
        let baseURLText = process["NESSIE_BASE_URL"] ?? values["NESSIE_BASE_URL"]
            ?? "https://api.nessieisreal.com"
        var customerID = process["NESSIE_CUSTOMER_ID"] ?? values["NESSIE_CUSTOMER_ID"] ?? ""

        if customerID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            print("FinanceCore está listo. Introduce un Nessie customer ID para conectar el sandbox.")
            print("Customer ID (Enter para salir): ", terminator: "")
            customerID = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        }
        guard !customerID.isEmpty else {
            print("Sincronización omitida. Añade NESSIE_CUSTOMER_ID a .env y ejecuta swift run.")
            return
        }
        guard let baseURL = URL(string: baseURLText) else {
            throw BankingError.invalidConfiguration("NESSIE_BASE_URL is invalid")
        }

        let configuration = try NessieConfiguration(baseURL: baseURL, apiKey: apiKey, customerID: customerID)
        let repositoryURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(".finance-data/finance-store.json")
        let repository = try FileFinancialRepository(fileURL: repositoryURL)
        try await repository.load()
        let diagnostics = BankingDiagnostics.console
        let provider = NessieBankingProvider(configuration: configuration, diagnostics: diagnostics)
        let service = BankSyncService(provider: provider, repository: repository,
                                      diagnostics: diagnostics)

        print("Conectando con Capital One — Nessie Sandbox…")
        print("Sincronizando cuentas y transacciones…")
        let result = try await service.syncAll()
        let storedAccounts = try await repository.accounts()
        let storedTransactions = try await repository.transactions(from: nil, to: nil)

        print("\nSincronización completa")
        print("Cuentas encontradas: \(result.accountsFetched)")
        print("Cuentas nuevas: \(result.accountsInserted), actualizadas: \(result.accountsUpdated)")
        print("Transacciones obtenidas: \(result.transactionsFetched)")
        print("Nuevas: \(result.transactionsInserted), actualizadas: \(result.transactionsUpdated)")
        print("Duplicados ignorados: \(result.duplicatesIgnored)")
        if result.isPartial {
            print("Aviso: \(result.accountFailures.count) cuenta(s) conservaron sus datos locales por errores de sincronización:")
            for failure in result.accountFailures {
                print("- \(failure.externalAccountID): \(failure.error.localizedDescription)")
            }
        }
        print("Total local: \(storedAccounts.count) cuentas, \(storedTransactions.count) transacciones")
        print("Datos guardados en: \(repositoryURL.path)")
    }

    private static func loadEnvironmentFile(at url: URL) -> [String: String] {
        guard let contents = try? String(contentsOf: url, encoding: .utf8) else { return [:] }
        var values: [String: String] = [:]
        for rawLine in contents.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("#"), let separator = line.firstIndex(of: "=") else { continue }
            let key = String(line[..<separator]).trimmingCharacters(in: .whitespaces)
            let value = String(line[line.index(after: separator)...]).trimmingCharacters(in: .whitespaces)
            values[key] = value
        }
        return values
    }
}
