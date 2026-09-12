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

struct GoalImpact: Identifiable, Equatable, Sendable {
    enum ImpactLevel: String, Sendable {
        case unaffected
        case delayed
        case atRisk
    }

    let id: UUID
    let goalID: UUID
    let goalName: String
    let impactLevel: ImpactLevel
    let originalTargetDate: Date
    let projectedTargetDate: Date
    let delayDays: Int
    let amountPulledFromGoal: Double
    let explanation: String

    init(
        id: UUID = UUID(),
        goalID: UUID,
        goalName: String,
        impactLevel: ImpactLevel,
        originalTargetDate: Date,
        projectedTargetDate: Date,
        delayDays: Int,
        amountPulledFromGoal: Double,
        explanation: String
    ) {
        self.id = id
        self.goalID = goalID
        self.goalName = goalName
        self.impactLevel = impactLevel
        self.originalTargetDate = originalTargetDate
        self.projectedTargetDate = projectedTargetDate
        self.delayDays = max(0, delayDays)
        self.amountPulledFromGoal = max(0, amountPulledFromGoal)
        self.explanation = explanation
    }
}

struct WhatIfResult: Equatable, Sendable {
    enum Status: String, Sendable {
        case safe = "SAFE"
        case tradeOff = "TRADE-OFF"
        case wait = "WAIT"
    }

    let status: Status
    let safeToSpendBeforePurchase: Double
    let remainingAfterPurchase: Double
    let recommendedDate: Date?
    let goalImpacts: [GoalImpact]
    let explanation: String
}
