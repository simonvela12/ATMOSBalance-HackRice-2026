import Foundation

struct MerchantDetails: Sendable {
    let name: String?
    let category: String?
}

actor MerchantCache {
    private var values: [String: MerchantDetails] = [:]
    private var failedIDs: Set<String> = []
    private let diagnostics: BankingDiagnostics

    init(diagnostics: BankingDiagnostics = .disabled) {
        self.diagnostics = diagnostics
    }

    func details(id: String, client: NessieAPIClient) async -> MerchantDetails? {
        if let cached = values[id] { return cached }
        if failedIDs.contains(id) { return nil }
        do {
            let merchant = try await client.merchant(id: id)
            let details = MerchantDetails(
                name: merchant.name,
                category: merchant.category?.joined(separator: ", ")
            )
            values[id] = details
            return details
        } catch {
            failedIDs.insert(id)
            await diagnostics.record(.warning, details: [
                "component": "merchant-enrichment",
                "result": "transaction-stored-without-enrichment"
            ])
            return nil
        }
    }
}
