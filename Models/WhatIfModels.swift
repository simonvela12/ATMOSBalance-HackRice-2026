import Foundation

struct WhatIfScenario: Codable, Equatable {
    enum ScenarioType: String, Codable {
        case purchase
    }

    let type: ScenarioType
    let name: String
    let amount: Double
    let intendedDate: Date?
}

struct WhatIfResult: Equatable {
    enum Status: String {
        case safe = "SAFE"
        case wait = "WAIT"
    }

    let status: Status
    let safeToSpendBeforePurchase: Double
    let remainingAfterPurchase: Double
    let recommendedDate: Date?
    let explanation: String
}
