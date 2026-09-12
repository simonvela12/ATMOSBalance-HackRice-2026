import Foundation

public enum BankingProviderID: String, Codable, Sendable { case nessie, plaid, demo }
public enum BankConnectionStatus: String, Codable, Sendable { case connecting, connected, disconnected, failed }

public struct BankConnection: Identifiable, Codable, Hashable, Sendable {
    public let id: String
    public let provider: BankingProviderID
    public let externalCustomerID: String
    public var status: BankConnectionStatus
    public let connectedAt: Date
    public var lastSyncedAt: Date?

    public init(id: String, provider: BankingProviderID, externalCustomerID: String,
                status: BankConnectionStatus, connectedAt: Date, lastSyncedAt: Date? = nil) {
        self.id = id; self.provider = provider; self.externalCustomerID = externalCustomerID
        self.status = status; self.connectedAt = connectedAt; self.lastSyncedAt = lastSyncedAt
    }
}
