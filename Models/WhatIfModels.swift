import Foundation

struct WhatIfScenario: Codable, Equatable, Sendable {
    enum ScenarioType: String, Codable, Sendable {
        case purchase
    }

    let type: ScenarioType
    let name: String
    let amount: Double
    let intendedDate: Date?
}

struct WhatIfResult: Equatable, Sendable {
    enum Status: String, Sendable {
        case safe = "SAFE"
        case wait = "WAIT"
    }

    let status: Status
    let safeToSpendBeforePurchase: Double
    let remainingAfterPurchase: Double
    let recommendedDate: Date?
    let explanation: String
}
