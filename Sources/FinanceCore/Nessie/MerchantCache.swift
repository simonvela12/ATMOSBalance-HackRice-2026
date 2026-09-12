import Foundation

struct MerchantDetails: Sendable {
    let name: String?
    let category: String?
}

actor MerchantCache {
    private var values: [String: MerchantDetails] = [:]

    func details(id: String, client: NessieAPIClient) async -> MerchantDetails? {
        if let cached = values[id] { return cached }
        do {
            let merchant = try await client.merchant(id: id)
            let details = MerchantDetails(
                name: merchant.name,
                category: merchant.category?.joined(separator: ", ")
            )
            values[id] = details
            return details
        } catch {
            #if DEBUG
            print("Merchant enrichment failed for merchant \(id); transaction will still be stored.")
            #endif
            return nil
        }
    }
}
