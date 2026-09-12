import Foundation

public struct NessieConfiguration: Sendable {
    public let baseURL: URL
    public let apiKey: String
    public let customerID: String
    public let requestTimeout: TimeInterval

    public init(baseURL: URL? = nil,
                apiKey: String, customerID: String,
                requestTimeout: TimeInterval = 20) throws {
        guard let resolvedBaseURL = baseURL ?? URL(string: "https://api.nessieisreal.com") else {
            throw BankingError.invalidConfiguration("Default Nessie URL is invalid")
        }
        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw BankingError.invalidConfiguration("NESSIE_API_KEY is empty")
        }
        guard !customerID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw BankingError.invalidConfiguration("NESSIE_CUSTOMER_ID is empty")
        }
        guard resolvedBaseURL.scheme == "https" || resolvedBaseURL.scheme == "http" else {
            throw BankingError.invalidConfiguration("NESSIE_BASE_URL must be an HTTP(S) URL")
        }
        guard requestTimeout > 0 else {
            throw BankingError.invalidConfiguration("Nessie request timeout must be positive")
        }
        self.baseURL = resolvedBaseURL
        self.apiKey = apiKey
        self.customerID = customerID
        self.requestTimeout = requestTimeout
    }
}