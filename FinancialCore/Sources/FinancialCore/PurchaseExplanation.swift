import Foundation

public enum PurchaseDecisionReason: String, Codable, Sendable {
    case preservesRecommendedBuffer
    case usesSafetyBuffer
    case violatesProtectedGoal
    case violatesPersonalReserve
    case violatesInstitutionalMinimum
    case violatesMultipleHardConstraints
}

public struct PurchaseDecisionExplanation: Sendable {
    public let status: PurchaseStatus
    public let reason: PurchaseDecisionReason
    public let limitingDate: Date
    public let projectedCashBeforePurchase: Double
    public let projectedCashAfterPurchase: Double
    public let personalReserve: Double
    public let institutionalMinimum: Double
    public let hardFloor: Double
    public let safetyBuffer: Double
    public let recommendedFloor: Double
    public let shortfallToHardFloor: Double
    public let shortfallToRecommendedFloor: Double
    public let recommendedDate: Date?
}

public extension FinancialInsights {
    /// Converts a numeric purchase assessment into structured, deterministic context
    /// that the UI can explain without asking an LLM to invent financial reasoning.
    static func explainPurchase(
        profile: FinancialProfile,
        assessment: PurchaseAssessment,
        calendar: Calendar = .current
    ) throws -> PurchaseDecisionExplanation {
        let limitingDate: Date
        switch assessment.status {
        case .notSafe:
            limitingDate = assessment.tightestHardDate
        case .safe, .tight:
            limitingDate = assessment.tightestRecommendedDate
        }

        let baseline = try FinancialEngine.forecast(
            profile: profile,
            targetDate: limitingDate,
            calendar: calendar
        )
        let cashAfter = baseline.projectedCash - assessment.purchaseAmount

        let hasProtectedGoalConstraint = FinancialEngine.protectedMandatoryGoals(profile: profile, on: limitingDate) > 0.005 || FinancialEngine.mandatoryGoalPayments(profile: profile, targetDate: limitingDate) > 0.005

        let reason: PurchaseDecisionReason
        switch assessment.status {
        case .safe:
            reason = .preservesRecommendedBuffer

        case .tight:
            reason = .usesSafetyBuffer

        case .notSafe:
            let violatesPersonal = baseline.personalReserve > 0 && cashAfter < baseline.personalReserve
            let violatesInstitutional = baseline.institutionalMinimum > 0 && cashAfter < baseline.institutionalMinimum
            let hardConstraintCount = [hasProtectedGoalConstraint, violatesPersonal, violatesInstitutional].filter { $0 }.count

            if hardConstraintCount > 1 {
                reason = .violatesMultipleHardConstraints
            } else if hasProtectedGoalConstraint {
                reason = .violatesProtectedGoal
            } else if violatesPersonal {
                reason = .violatesPersonalReserve
            } else if violatesInstitutional {
                reason = .violatesInstitutionalMinimum
            } else if baseline.personalReserve > 0 {
                reason = .violatesPersonalReserve
            } else {
                reason = .violatesInstitutionalMinimum
            }
        }

        return PurchaseDecisionExplanation(
            status: assessment.status,
            reason: reason,
            limitingDate: limitingDate,
            projectedCashBeforePurchase: baseline.projectedCash,
            projectedCashAfterPurchase: cashAfter,
            personalReserve: baseline.personalReserve,
            institutionalMinimum: baseline.institutionalMinimum,
            hardFloor: baseline.hardFloor,
            safetyBuffer: baseline.safetyBuffer,
            recommendedFloor: baseline.hardFloor + baseline.safetyBuffer,
            shortfallToHardFloor: assessment.shortfallToHardFloor,
            shortfallToRecommendedFloor: assessment.shortfallToRecommendedFloor,
            recommendedDate: assessment.recommendedDate
        )
    }

    static func assessAndExplainPurchase(
        profile: FinancialProfile,
        amount: Double,
        purchaseDate: Date,
        planningHorizon: Date,
        calendar: Calendar = .current
    ) throws -> (assessment: PurchaseAssessment, explanation: PurchaseDecisionExplanation) {
        let assessment = try FinancialEngine.assessPurchase(
            profile: profile,
            amount: amount,
            purchaseDate: purchaseDate,
            planningHorizon: planningHorizon,
            calendar: calendar
        )
        let explanation = try explainPurchase(
            profile: profile,
            assessment: assessment,
            calendar: calendar
        )
        return (assessment, explanation)
    }
}
