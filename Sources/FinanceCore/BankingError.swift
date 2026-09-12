import Foundation

public enum BankingError: Error, Equatable, Sendable {
    case invalidConfiguration(String)
    case invalidAPIKey
    case customerNotFound(String)
    case networkError(String)
    case decodingError(String)
    case rateLimited
    case serverError(statusCode: Int, message: String?)
    case malformedTransaction(String)
    case persistenceError(String)
    case syncAlreadyInProgress
}

extension BankingError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidConfiguration(let message): "Invalid configuration: \(message)"
        case .invalidAPIKey: "The Nessie API key is missing or invalid."
        case .customerNotFound(let id): "Nessie customer not found: \(id)"
        case .networkError(let message): "Network error: \(message)"
        case .decodingError(let message): "Could not decode the Nessie response: \(message)"
        case .rateLimited: "Nessie rate limit reached. Try again later."
        case .serverError(let statusCode, let message):
            "Nessie server error (HTTP \(statusCode))\(message.map { ": \($0)" } ?? "")"
        case .malformedTransaction(let message): "Malformed Nessie transaction: \(message)"
        case .persistenceError(let message): "Persistence error: \(message)"
        case .syncAlreadyInProgress: "A bank synchronization is already running."
        }
    }
}
