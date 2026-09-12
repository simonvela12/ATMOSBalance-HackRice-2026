import Foundation

public enum BankingDiagnosticKind: String, Sendable {
    case syncStart = "SYNC START"
    case nessieRequest = "NESSIE REQUEST"
    case nessieResponse = "NESSIE RESPONSE"
    case transactionsReceived = "TRANSACTIONS RECEIVED"
    case newTransactions = "NEW TRANSACTIONS"
    case duplicatesIgnored = "DUPLICATES IGNORED"
    case localStoreUpdated = "LOCAL STORE UPDATED"
    case financialStateUpdated = "UI / FINANCIAL STATE UPDATED"
    case syncEnd = "SYNC END"
    case warning = "WARNING"
}

public struct BankingDiagnosticEvent: Sendable {
    public let timestamp: Date
    public let kind: BankingDiagnosticKind
    public let details: [String: String]

    public init(timestamp: Date = Date(), kind: BankingDiagnosticKind,
                details: [String: String] = [:]) {
        self.timestamp = timestamp
        self.kind = kind
        self.details = details
    }
}

/// An opt-in diagnostic sink. Callers must only provide non-sensitive metadata.
public struct BankingDiagnostics: Sendable {
    private let handler: @Sendable (BankingDiagnosticEvent) async -> Void

    public init(handler: @escaping @Sendable (BankingDiagnosticEvent) async -> Void) {
        self.handler = handler
    }

    public func record(_ kind: BankingDiagnosticKind, details: [String: String] = [:]) async {
        await handler(BankingDiagnosticEvent(kind: kind, details: details))
    }

    public static let disabled = BankingDiagnostics { _ in }

    public static let console = BankingDiagnostics { event in
        let metadata = event.details.sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: " ")
        let suffix = metadata.isEmpty ? "" : " \(metadata)"
        print("[BANKING] \(event.timestamp.ISO8601Format()) \(event.kind.rawValue)\(suffix)")
    }
}
