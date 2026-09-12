import Foundation
import FinanceCore

@main
struct FinanceCoreDemo {
    static func main() async {
        do {
            try await run()
        } catch {
            print("\nNo se pudo completar la sincronización.")
            print(error.localizedDescription)
            print("Comprueba la conexión y la configuración, o usa FINANCECORE_USE_DEMO_DATA=true para probar sin red.")
        }
    }

    private static func run() async throws {
        let values = loadEnvironmentFile(at: URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(".env"))
        let process = ProcessInfo.processInfo.environment
        let demoFlag = process["FINANCECORE_USE_DEMO_DATA"] ?? values["FINANCECORE_USE_DEMO_DATA"] ?? "false"
        let useDemoData = ["1", "true", "yes"].contains(demoFlag.lowercased())
        let provider: any BankingProvider
        let repositoryFilename: String

        if useDemoData {
            provider = DemoBankingProvider()
            repositoryFilename = "demo-finance-store.json"
            print("Usando el cliente de demostración local (sin red).")
        } else {
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
            provider = NessieBankingProvider(configuration: configuration)
            repositoryFilename = "finance-store.json"
            print("Conectando con Capital One — Nessie Sandbox…")
        }

        let repositoryURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(".finance-data")
            .appendingPathComponent(repositoryFilename)
        let repository = try FileFinancialRepository(fileURL: repositoryURL)
        try await repository.load()
        let service = BankSyncService(provider: provider, repository: repository)

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
