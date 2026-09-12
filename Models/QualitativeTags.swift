//
//  QualitativeTags.swift
//  Test
//
//  Created by Simon Velandia on 9/11/26.
//

import Foundation

// MARK: - Spending Tags

enum SpendingCategory: String, Codable, CaseIterable, Identifiable {
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

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .personalCare:
            return "Personal Care"
        default:
            return rawValue.capitalized
        }
    }
}

enum NeedLevel: String, Codable, CaseIterable, Identifiable {
    case essential
    case important
    case optional

    var id: String { rawValue }

    var displayName: String {
        rawValue.capitalized
    }
}

enum ExpenseFlexibility: String, Codable, CaseIterable, Identifiable {
    case fixed
    case semiFlexible
    case flexible

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .semiFlexible:
            return "Semi-Flexible"
        default:
            return rawValue.capitalized
        }
    }
}

enum PlanningStatus: String, Codable, CaseIterable, Identifiable {
    case planned
    case unplanned
    case emergency

    var id: String { rawValue }

    var displayName: String {
        rawValue.capitalized
    }
}

enum ExpenseFrequency: String, Codable, CaseIterable, Identifiable {
    case recurring
    case occasional
    case oneTime

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .oneTime:
            return "One-Time"
        default:
            return rawValue.capitalized
        }
    }
}

enum UserPriority: String, Codable, CaseIterable, Identifiable {
    case high
    case medium
    case low

    var id: String { rawValue }

    var displayName: String {
        rawValue.capitalized
    }
}

// MARK: - Income Tags

enum IncomeType: String, Codable, CaseIterable, Identifiable {
    case recurring
    case irregular
    case oneTime

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .oneTime:
            return "One-Time"
        default:
            return rawValue.capitalized
        }
    }
}

enum IncomeConfidence: String, Codable, CaseIterable, Identifiable {
    case confirmed
    case likely
    case possible

    var id: String { rawValue }

    var displayName: String {
        rawValue.capitalized
    }

    var numericValue: Double {
        switch self {
        case .confirmed:
            return 1.0
        case .likely:
            return 0.7
        case .possible:
            return 0.3
        }
    }
}

enum IncomeSource: String, Codable, CaseIterable, Identifiable {
    case job
    case campusWork
    case family
    case freelance
    case tutoring
    case refund
    case other

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .campusWork:
            return "Campus Work"
        default:
            return rawValue.capitalized
        }
    }
}

// MARK: - Expense Model

struct TaggedExpense: Identifiable, Codable {
    let id: UUID

    var merchant: String
    var amount: Double
    var date: Date

    var category: SpendingCategory
    var needLevel: NeedLevel
    var flexibility: ExpenseFlexibility
    var planningStatus: PlanningStatus
    var frequency: ExpenseFrequency

    var goalId: UUID?
    var priority: UserPriority?

    init(
        id: UUID = UUID(),
        merchant: String,
        amount: Double,
        date: Date,
        category: SpendingCategory,
        needLevel: NeedLevel,
        flexibility: ExpenseFlexibility,
        planningStatus: PlanningStatus,
        frequency: ExpenseFrequency,
        goalId: UUID? = nil,
        priority: UserPriority? = nil
    ) {
        self.id = id
        self.merchant = merchant
        self.amount = amount
        self.date = date
        self.category = category
        self.needLevel = needLevel
        self.flexibility = flexibility
        self.planningStatus = planningStatus
        self.frequency = frequency
        self.goalId = goalId
        self.priority = priority
    }
}

// MARK: - Income Model

struct TaggedIncome: Identifiable, Codable {
    let id: UUID

    var sourceName: String
    var amount: Double
    var date: Date

    var source: IncomeSource
    var type: IncomeType
    var confidence: IncomeConfidence

    init(
        id: UUID = UUID(),
        sourceName: String,
        amount: Double,
        date: Date,
        source: IncomeSource,
        type: IncomeType,
        confidence: IncomeConfidence
    ) {
        self.id = id
        self.sourceName = sourceName
        self.amount = amount
        self.date = date
        self.source = source
        self.type = type
        self.confidence = confidence
    }

    var expectedValue: Double {
        switch type {
        case .oneTime:
            return 0

        case .recurring:
            return amount

        case .irregular:
            return amount * confidence.numericValue
        }
    }
}

// MARK: - Recommendation Logic

extension TaggedExpense {

    /// Higher score = better candidate to reduce or delay.
    var cutPriorityScore: Int {
        var score = 0

        switch needLevel {
        case .essential:
            score += 0
        case .important:
            score += 2
        case .optional:
            score += 5
        }

        switch flexibility {
        case .fixed:
            score += 0
        case .semiFlexible:
            score += 2
        case .flexible:
            score += 5
        }

        switch planningStatus {
        case .planned:
            score += 0
        case .emergency:
            score -= 5
        case .unplanned:
            score += 3
        }

        if priority == .high {
            score -= 3
        } else if priority == .low {
            score += 2
        }

        return score
    }

    var isGoodSavingsCandidate: Bool {
        cutPriorityScore >= 7
    }
}

// MARK: - Example Classification Helper

struct QualitativeClassifier {

    static func suggestedCategory(for merchant: String) -> SpendingCategory {
        let normalized = merchant.lowercased()

        if normalized.contains("chipotle")
            || normalized.contains("restaurant")
            || normalized.contains("starbucks")
            || normalized.contains("heb")
            || normalized.contains("h-e-b") {
            return .food
        }

        if normalized.contains("uber")
            || normalized.contains("lyft") {
            return .transportation
        }

        if normalized.contains("netflix")
            || normalized.contains("spotify") {
            return .subscriptions
        }

        if normalized.contains("ticketmaster")
            || normalized.contains("formula 1")
            || normalized.contains("f1") {
            return .entertainment
        }

        if normalized.contains("united")
            || normalized.contains("american airlines")
            || normalized.contains("hotel")
            || normalized.contains("airbnb") {
            return .travel
        }

        return .other
    }

    static func suggestedNeedLevel(
        for category: SpendingCategory
    ) -> NeedLevel {

        switch category {
        case .housing,
             .utilities,
             .health,
             .education:
            return .essential

        case .transportation,
             .food:
            return .important

        case .entertainment,
             .shopping,
             .travel,
             .subscriptions,
             .social,
             .personalCare,
             .fees,
             .other:
            return .optional
        }
    }

    static func suggestedFlexibility(
        for category: SpendingCategory
    ) -> ExpenseFlexibility {

        switch category {
        case .housing,
             .education:
            return .fixed

        case .food,
             .transportation,
             .utilities,
             .health:
            return .semiFlexible

        case .entertainment,
             .shopping,
             .travel,
             .subscriptions,
             .social,
             .personalCare,
             .fees,
             .other:
            return .flexible
        }
    }
}

// MARK: - Example Data

extension TaggedExpense {

    static let exampleChipotle = TaggedExpense(
        merchant: "Chipotle",
        amount: 18,
        date: Date(),
        category: .food,
        needLevel: .optional,
        flexibility: .flexible,
        planningStatus: .unplanned,
        frequency: .occasional
    )

    static let exampleRent = TaggedExpense(
        merchant: "Apartment Rent",
        amount: 900,
        date: Date(),
        category: .housing,
        needLevel: .essential,
        flexibility: .fixed,
        planningStatus: .planned,
        frequency: .recurring
    )

    static let exampleF1 = TaggedExpense(
        merchant: "Formula 1",
        amount: 450,
        date: Date(),
        category: .entertainment,
        needLevel: .optional,
        flexibility: .flexible,
        planningStatus: .planned,
        frequency: .oneTime,
        priority: .medium
    )
}

extension TaggedIncome {

    static let exampleCampusJob = TaggedIncome(
        sourceName: "Campus Job",
        amount: 300,
        date: Date(),
        source: .campusWork,
        type: .recurring,
        confidence: .confirmed
    )

    static let exampleTutoring = TaggedIncome(
        sourceName: "Tutoring",
        amount: 300,
        date: Date(),
        source: .tutoring,
        type: .irregular,
        confidence: .likely
    )

    static let exampleFamilyTransfer = TaggedIncome(
        sourceName: "Family Transfer",
        amount: 2000,
        date: Date(),
        source: .family,
        type: .oneTime,
        confidence: .confirmed
    )
}
