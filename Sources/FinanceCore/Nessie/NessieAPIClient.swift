import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public protocol NessieTransport: Sendable {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

public actor URLSessionNessieTransport: NessieTransport {
    private let session: URLSession

    public init(session: URLSession = .shared) { self.session = session }

    public func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw BankingError.networkError("Response was not HTTP")
        }
        return (data, http)
    }
}

public struct NessieAPIClient: Sendable {
    private let configuration: NessieConfiguration
    private let transport: any NessieTransport
    private let decoder: JSONDecoder

    public init(configuration: NessieConfiguration, transport: any NessieTransport = URLSessionNessieTransport()) {
        self.configuration = configuration; self.transport = transport; self.decoder = JSONDecoder()
    }

    func accounts() async throws -> [NessieAccount] {
        try await get("customers/\(configuration.customerID)/accounts")
    }

    func purchases(accountID: String) async throws -> [NessiePurchase] {
        try await getCollection("accounts/\(accountID)/purchases")
    }

    func deposits(accountID: String) async throws -> [NessieDeposit] {
        try await getCollection("accounts/\(accountID)/deposits")
    }

    func withdrawals(accountID: String) async throws -> [NessieWithdrawal] {
        try await getCollection("accounts/\(accountID)/withdrawals")
    }

    func transfers(accountID: String) async throws -> [NessieTransfer] {
        try await getCollection("accounts/\(accountID)/transfers")
    }

    func merchant(id: String) async throws -> NessieMerchant {
        try await get("merchants/\(id)")
    }

    private func getCollection<T: Decodable>(_ path: String) async throws -> [T] {
        do {
            return try await get(path)
        } catch BankingError.serverError(let statusCode, let message)
            where statusCode == 404 && Self.isEmptyCollectionResponse(message) {
            return []
        }
    }

    private static func isEmptyCollectionResponse(_ message: String?) -> Bool {
        let normalized = message?.lowercased() ?? ""
        return normalized.contains("no ") && normalized.contains(" found")
    }

    private func get<T: Decodable>(_ path: String) async throws -> T {
        let encodedPath = path.split(separator: "/").map(String.init)
            .map { $0.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? $0 }
            .joined(separator: "/")
        var components = URLComponents(url: configuration.baseURL.appendingPathComponent(encodedPath),
                                       resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "key", value: configuration.apiKey)]
        guard let url = components?.url else { throw BankingError.invalidConfiguration("Invalid Nessie URL") }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let data: Data
        let response: HTTPURLResponse
        do { (data, response) = try await transport.data(for: request) }
        catch let error as BankingError { throw error }
        catch { throw BankingError.networkError(error.localizedDescription) }

        switch response.statusCode {
        case 200..<300: break
        case 401, 403: throw BankingError.invalidAPIKey
        case 429: throw BankingError.rateLimited
        default:
            let message = String(data: data.prefix(500), encoding: .utf8)
            throw BankingError.serverError(statusCode: response.statusCode, message: message)
        }

        do { return try decoder.decode(T.self, from: data) }
        catch { throw BankingError.decodingError(error.localizedDescription) }
    }
}
