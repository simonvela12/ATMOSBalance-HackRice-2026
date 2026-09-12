import Foundation

public enum SpendingCategory: String, Codable, CaseIterable, Sendable {
    case housing
    case food
    case transportation
    case education
    case entertainment
    case shopping
    case travel
    case health
    case subscriptions
    case utilities
    case social
    case personalCare
    case fees
    case other
}

public enum NeedLevel: String, Codable, CaseIterable, Sendable {
    case essential
    case important
    case optional
}

public enum ExpenseFlexibility: String, Codable, CaseIterable, Sendable {
    case fixed
    case semiFlexible
    case flexible
}

public enum PlanningStatus: String, Codable, CaseIterable, Sendable {
    case planned
    case unplanned
    case emergency
}

public enum ExpenseFrequency: String, Codable, CaseIterable, Sendable {
    case recurring
    case occasional
    case oneTime
}

public enum UserPriority: String, Codable, CaseIterable, Sendable {
    case high
    case medium
    case low
}

public enum IncomeSourceKind: String, Codable, CaseIterable, Sendable {
    case job
    case campusWork
    case family
    case freelance
    case tutoring
    case refund
    case other
}

public enum IncomeConfidenceBand: String, Codable, CaseIterable, Sendable {
    case confirmed
    case likely
    case possible

    public var confidence: Double {
        switch self {
        case .confirmed: 1.0
        case .likely: 0.7
        case .possible: 0.3
        }
    }
}

/// Structured qualitative context that can be attached to an expense without changing
/// the deterministic cash-flow formulas. The engine continues to use explicit fields
/// such as `essential` and `committed`; this metadata exists to improve user context,
/// explanations, and future adapters without introducing an opaque score.
public struct ExpenseQualitativeMetadata: Codable, Equatable, Sendable {
    public var category: SpendingCategory
    public var needLevel: NeedLevel
    public var flexibility: ExpenseFlexibility
    public var planningStatus: PlanningStatus
    public var frequency: ExpenseFrequency
    public var priority: UserPriority?

    public init(
        category: SpendingCategory,
        needLevel: NeedLevel,
        flexibility: ExpenseFlexibility,
        planningStatus: PlanningStatus,
        frequency: ExpenseFrequency,
        priority: UserPriority? = nil
    ) {
        self.category = category
        self.needLevel = needLevel
        self.flexibility = flexibility
        self.planningStatus = planningStatus
        self.frequency = frequency
        self.priority = priority
    }

    public var isExplicitSavingsCandidate: Bool {
        needLevel == .optional && flexibility == .flexible && planningStatus != .emergency
    }
}

public struct IncomeQualitativeMetadata: Codable, Equatable, Sendable {
    public var sourceKind: IncomeSourceKind
    public var confidenceBand: IncomeConfidenceBand

    public init(sourceKind: IncomeSourceKind, confidenceBand: IncomeConfidenceBand) {
        self.sourceKind = sourceKind
        self.confidenceBand = confidenceBand
    }
}

/// Deterministic suggestions only. These are defaults for a confirmation UI, never
/// silent financial decisions. The user must confirm qualitative context before it
/// changes the planning profile.
public enum QualitativeMetadataSuggester {
    public static func category(for merchant: String) -> SpendingCategory {
        let value = merchant.lowercased()
        if value.contains("restaurant") || value.contains("chipotle") || value.contains("starbucks") || value.contains("h-e-b") || value.contains("heb") {
            return .food
        }
        if value.contains("uber") || value.contains("lyft") { return .transportation }
        if value.contains("netflix") || value.contains("spotify") { return .subscriptions }
        if value.contains("ticketmaster") || value.contains("formula 1") || value.contains("f1") { return .entertainment }
        if value.contains("united") || value.contains("american airlines") || value.contains("hotel") || value.contains("airbnb") { return .travel }
        return .other
    }

    public static func needLevel(for category: SpendingCategory) -> NeedLevel {
        switch category {
        case .housing, .utilities, .health, .education:
            return .essential
        case .transportation, .food:
            return .important
        case .entertainment, .shopping, .travel, .subscriptions, .social, .personalCare, .fees, .other:
            return .optional
        }
    }

    public static func flexibility(for category: SpendingCategory) -> ExpenseFlexibility {
        switch category {
        case .housing, .education:
            return .fixed
        case .food, .transportation, .utilities, .health:
            return .semiFlexible
        case .entertainment, .shopping, .travel, .subscriptions, .social, .personalCare, .fees, .other:
            return .flexible
        }
    }
}
