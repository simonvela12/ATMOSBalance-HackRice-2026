import Foundation

enum V2IncomeType: String, Codable {
    case recurring
    case irregular
    case oneTime
}

enum V2GoalPriority: String, Codable {
    case mandatory
    case flexible
}

enum V2PurchaseStatus: String, Codable {
    case safe = "SAFE"
    case tight = "TIGHT"
    case notSafe = "NOT_SAFE"
}

struct V2IncomeEvent: Codable, Identifiable {
    let id: UUID
    let amount: Double
    let date: Date
    let source: String
    let type: V2IncomeType
    let confidence: Double

    init(
        id: UUID = UUID(),
        amount: Double,
        date: Date,
        source: String,
        type: V2IncomeType,
        confidence: Double = 1.0
    ) {
        self.id = id
        self.amount = amount
        self.date = date
        self.source = source
        self.type = type
        self.confidence = confidence
    }

    var adjustedAmount: Double {
        switch type {
        case .irregular:
            return amount * min(max(confidence, 0), 1)
        case .recurring, .oneTime:
            return amount
        }
    }
}

struct V2ExpenseEvent: Codable, Identifiable {
    let id: UUID
    let amount: Double
    let date: Date
    let category: String
    let essential: Bool
    let committed: Bool
    let reimbursable: Bool
    let extraordinary: Bool

    init(
        id: UUID = UUID(),
        amount: Double,
        date: Date,
        category: String,
        essential: Bool = true,
        committed: Bool = true,
        reimbursable: Bool = false,
        extraordinary: Bool = false
    ) {
        self.id = id
        self.amount = amount
        self.date = date
        self.category = category
        self.essential = essential
        self.committed = committed
        self.reimbursable = reimbursable
        self.extraordinary = extraordinary
    }
}

struct V2Goal: Codable, Identifiable {
    let id: UUID
    let name: String
    let targetAmount: Double
    let amountAlreadyPaid: Double
    let deadline: Date
    let priority: V2GoalPriority

    init(
        id: UUID = UUID(),
        name: String,
        targetAmount: Double,
        amountAlreadyPaid: Double = 0,
        deadline: Date,
        priority: V2GoalPriority
    ) {
        self.id = id
        self.name = name
        self.targetAmount = targetAmount
        self.amountAlreadyPaid = amountAlreadyPaid
        self.deadline = deadline
        self.priority = priority
    }

    var remainingAmount: Double {
        max(0, targetAmount - amountAlreadyPaid)
    }
}

struct PersonalReserveStep: Codable, Identifiable {
    let id: UUID
    let effectiveDate: Date
    let minimumCash: Double
    let note: String

    init(
        id: UUID = UUID(),
        effectiveDate: Date,
        minimumCash: Double,
        note: String = ""
    ) {
        self.id = id
        self.effectiveDate = effectiveDate
        self.minimumCash = minimumCash
        self.note = note
    }
}

struct InstitutionalMinimum: Codable, Identifiable {
    let id: UUID
    let name: String
    let minimumBalance: Double
    let startDate: Date
    let endDate: Date?

    init(
        id: UUID = UUID(),
        name: String,
        minimumBalance: Double,
        startDate: Date,
        endDate: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.minimumBalance = minimumBalance
        self.startDate = startDate
        self.endDate = endDate
    }

    func isActive(on date: Date) -> Bool {
        guard date >= startDate else { return false }
        if let endDate, date > endDate { return false }
        return true
    }
}

struct WeeklySpendingSample: Codable, Identifiable {
    let id: UUID
    let weekStart: Date
    let totalVariableSpending: Double
    let excludedFromBaseline: Bool

    init(
        id: UUID = UUID(),
        weekStart: Date,
        totalVariableSpending: Double,
        excludedFromBaseline: Bool = false
    ) {
        self.id = id
        self.weekStart = weekStart
        self.totalVariableSpending = totalVariableSpending
        self.excludedFromBaseline = excludedFromBaseline
    }
}

struct SafetyBufferPolicy: Codable {
    var weeksOfCoverage: Double
    var manualMinimum: Double

    init(weeksOfCoverage: Double = 2.0, manualMinimum: Double = 0) {
        self.weeksOfCoverage = weeksOfCoverage
        self.manualMinimum = manualMinimum
    }
}

struct FinancialProfileV2: Codable {
    var currentCash: Double
    var asOfDate: Date
    var personalReserveSteps: [PersonalReserveStep]
    var institutionalMinimums: [InstitutionalMinimum]
    var incomeEvents: [V2IncomeEvent]
    var expenseEvents: [V2ExpenseEvent]
    var goals: [V2Goal]
    var weeklySpendingHistory: [WeeklySpendingSample]
    var safetyBufferPolicy: SafetyBufferPolicy
}

struct ForecastResultV2 {
    let targetDate: Date
    let expectedIncome: Double
    let committedExpenses: Double
    let projectedVariableSpending: Double
    let mandatoryGoalPayments: Double
    let projectedCash: Double
    let personalReserve: Double
    let institutionalMinimum: Double
    let hardFloor: Double
    let safetyBuffer: Double
    let hardHeadroom: Double
    let recommendedHeadroom: Double
}

struct HorizonHeadroomV2 {
    let startDate: Date
    let endDate: Date
    let minimumHardHeadroom: Double
    let minimumRecommendedHeadroom: Double
    let tightestHardDate: Date
    let tightestRecommendedDate: Date
}

struct PurchaseAssessmentV2 {
    let status: V2PurchaseStatus
    let purchaseAmount: Double
    let purchaseDate: Date
    let planningHorizon: Date
    let minimumHardHeadroomBeforePurchase: Double
    let minimumRecommendedHeadroomBeforePurchase: Double
    let minimumHardHeadroomAfterPurchase: Double
    let minimumRecommendedHeadroomAfterPurchase: Double
    let shortfallToHardFloor: Double
    let shortfallToRecommendedFloor: Double
    let recommendedDate: Date?
}

struct FlexibleGoalAssessmentV2 {
    let goal: V2Goal
    let purchaseAssessment: PurchaseAssessmentV2
}

enum FinancialEngineV2Error: Error {
    case targetDateBeforeProfileDate
    case invalidDateRange
    case negativeAmount
}

enum FinancialEngineV2 {
    static func median(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[middle - 1] + sorted[middle]) / 2
        }
        return sorted[middle]
    }

    static func typicalWeeklySpending(profile: FinancialProfileV2) -> Double {
        let eligible = profile.weeklySpendingHistory
            .filter { !$0.excludedFromBaseline }
            .map { max(0, $0.totalVariableSpending) }
        return median(eligible)
    }

    static func safetyBuffer(profile: FinancialProfileV2) -> Double {
        let historyBased = typicalWeeklySpending(profile: profile)
            * max(0, profile.safetyBufferPolicy.weeksOfCoverage)
        return max(max(0, profile.safetyBufferPolicy.manualMinimum), historyBased)
    }

    static func personalReserve(profile: FinancialProfileV2, on date: Date) -> Double {
        let applicable = profile.personalReserveSteps
            .filter { $0.effectiveDate <= date }
            .max { $0.effectiveDate < $1.effectiveDate }
        return max(0, applicable?.minimumCash ?? 0)
    }

    static func institutionalMinimum(profile: FinancialProfileV2, on date: Date) -> Double {
        profile.institutionalMinimums
            .filter { $0.isActive(on: date) }
            .reduce(0) { $0 + max(0, $1.minimumBalance) }
    }

    static func hardFloor(profile: FinancialProfileV2, on date: Date) -> Double {
        max(
            personalReserve(profile: profile, on: date),
            institutionalMinimum(profile: profile, on: date)
        )
    }

    static func expectedIncome(profile: FinancialProfileV2, targetDate: Date) -> Double {
        profile.incomeEvents
            .filter { $0.date > profile.asOfDate && $0.date <= targetDate }
            .reduce(0) { $0 + $1.adjustedAmount }
    }

    static func committedExpenses(profile: FinancialProfileV2, targetDate: Date) -> Double {
        profile.expenseEvents
            .filter {
                $0.committed &&
                $0.date > profile.asOfDate &&
                $0.date <= targetDate
            }
            .reduce(0) { $0 + max(0, $1.amount) }
    }

    static func mandatoryGoalPayments(profile: FinancialProfileV2, targetDate: Date) -> Double {
        profile.goals
            .filter {
                $0.priority == .mandatory &&
                $0.deadline > profile.asOfDate &&
                $0.deadline <= targetDate
            }
            .reduce(0) { $0 + $1.remainingAmount }
    }

    static func projectedVariableSpending(
        profile: FinancialProfileV2,
        targetDate: Date,
        calendar: Calendar = .current
    ) -> Double {
        guard targetDate > profile.asOfDate else { return 0 }
        let days = max(
            0,
            calendar.dateComponents([.day], from: profile.asOfDate, to: targetDate).day ?? 0
        )
        return typicalWeeklySpending(profile: profile) * Double(days) / 7.0
    }

    static func forecast(
        profile: FinancialProfileV2,
        targetDate: Date,
        calendar: Calendar = .current
    ) throws -> ForecastResultV2 {
        guard targetDate >= profile.asOfDate else {
            throw FinancialEngineV2Error.targetDateBeforeProfileDate
        }

        let income = expectedIncome(profile: profile, targetDate: targetDate)
        let expenses = committedExpenses(profile: profile, targetDate: targetDate)
        let variableSpending = projectedVariableSpending(
            profile: profile,
            targetDate: targetDate,
            calendar: calendar
        )
        let mandatoryGoals = mandatoryGoalPayments(profile: profile, targetDate: targetDate)
        let cash = profile.currentCash
            + income
            - expenses
            - variableSpending
            - mandatoryGoals
        let personal = personalReserve(profile: profile, on: targetDate)
        let institutional = institutionalMinimum(profile: profile, on: targetDate)
        let floor = max(personal, institutional)
        let buffer = safetyBuffer(profile: profile)
        let hardHeadroom = cash - floor
        let recommendedHeadroom = hardHeadroom - buffer

        return ForecastResultV2(
            targetDate: targetDate,
            expectedIncome: income,
            committedExpenses: expenses,
            projectedVariableSpending: variableSpending,
            mandatoryGoalPayments: mandatoryGoals,
            projectedCash: cash,
            personalReserve: personal,
            institutionalMinimum: institutional,
            hardFloor: floor,
            safetyBuffer: buffer,
            hardHeadroom: hardHeadroom,
            recommendedHeadroom: recommendedHeadroom
        )
    }

    static func minimumHeadroom(
        profile: FinancialProfileV2,
        from startDate: Date,
        through endDate: Date,
        calendar: Calendar = .current
    ) throws -> HorizonHeadroomV2 {
        guard endDate >= startDate else {
            throw FinancialEngineV2Error.invalidDateRange
        }
        guard startDate >= profile.asOfDate else {
            throw FinancialEngineV2Error.targetDateBeforeProfileDate
        }

        var date = startDate
        var minHard = Double.greatestFiniteMagnitude
        var minRecommended = Double.greatestFiniteMagnitude
        var minHardDate = startDate
        var minRecommendedDate = startDate

        while date <= endDate {
            let result = try forecast(profile: profile, targetDate: date, calendar: calendar)
            if result.hardHeadroom < minHard {
                minHard = result.hardHeadroom
                minHardDate = date
            }
            if result.recommendedHeadroom < minRecommended {
                minRecommended = result.recommendedHeadroom
                minRecommendedDate = date
            }

            guard let next = calendar.date(byAdding: .day, value: 1, to: date) else {
                break
            }
            date = next
        }

        return HorizonHeadroomV2(
            startDate: startDate,
            endDate: endDate,
            minimumHardHeadroom: minHard,
            minimumRecommendedHeadroom: minRecommended,
            tightestHardDate: minHardDate,
            tightestRecommendedDate: minRecommendedDate
        )
    }

    static func safeToSpend(
        profile: FinancialProfileV2,
        from startDate: Date,
        through endDate: Date,
        calendar: Calendar = .current
    ) throws -> Double {
        let horizon = try minimumHeadroom(
            profile: profile,
            from: startDate,
            through: endDate,
            calendar: calendar
        )
        return max(0, horizon.minimumRecommendedHeadroom)
    }

    static func assessPurchase(
        profile: FinancialProfileV2,
        amount: Double,
        purchaseDate: Date,
        planningHorizon: Date,
        calendar: Calendar = .current
    ) throws -> PurchaseAssessmentV2 {
        guard amount >= 0 else {
            throw FinancialEngineV2Error.negativeAmount
        }
        guard planningHorizon >= purchaseDate else {
            throw FinancialEngineV2Error.invalidDateRange
        }

        let baseline = try minimumHeadroom(
            profile: profile,
            from: purchaseDate,
            through: planningHorizon,
            calendar: calendar
        )

        let hardAfter = baseline.minimumHardHeadroom - amount
        let recommendedAfter = baseline.minimumRecommendedHeadroom - amount

        let status: V2PurchaseStatus
        if recommendedAfter >= 0 {
            status = .safe
        } else if hardAfter >= 0 {
            status = .tight
        } else {
            status = .notSafe
        }

        let recommendedDate: Date?
        if status == .safe {
            recommendedDate = purchaseDate
        } else {
            recommendedDate = try earliestSafePurchaseDate(
                profile: profile,
                amount: amount,
                startDate: purchaseDate,
                planningHorizon: planningHorizon,
                calendar: calendar
            )
        }

        return PurchaseAssessmentV2(
            status: status,
            purchaseAmount: amount,
            purchaseDate: purchaseDate,
            planningHorizon: planningHorizon,
            minimumHardHeadroomBeforePurchase: baseline.minimumHardHeadroom,
            minimumRecommendedHeadroomBeforePurchase: baseline.minimumRecommendedHeadroom,
            minimumHardHeadroomAfterPurchase: hardAfter,
            minimumRecommendedHeadroomAfterPurchase: recommendedAfter,
            shortfallToHardFloor: max(0, -hardAfter),
            shortfallToRecommendedFloor: max(0, -recommendedAfter),
            recommendedDate: recommendedDate
        )
    }

    static func earliestSafePurchaseDate(
        profile: FinancialProfileV2,
        amount: Double,
        startDate: Date,
        planningHorizon: Date,
        calendar: Calendar = .current
    ) throws -> Date? {
        guard amount >= 0 else {
            throw FinancialEngineV2Error.negativeAmount
        }
        guard planningHorizon >= startDate else {
            throw FinancialEngineV2Error.invalidDateRange
        }

        var candidate = startDate
        while candidate <= planningHorizon {
            let horizon = try minimumHeadroom(
                profile: profile,
                from: candidate,
                through: planningHorizon,
                calendar: calendar
            )
            if horizon.minimumRecommendedHeadroom >= amount {
                return candidate
            }

            guard let next = calendar.date(byAdding: .day, value: 1, to: candidate) else {
                break
            }
            candidate = next
        }

        return nil
    }

    static func assessFlexibleGoal(
        profile: FinancialProfileV2,
        goal: V2Goal,
        planningHorizon: Date,
        calendar: Calendar = .current
    ) throws -> FlexibleGoalAssessmentV2 {
        let assessment = try assessPurchase(
            profile: profile,
            amount: goal.remainingAmount,
            purchaseDate: goal.deadline,
            planningHorizon: max(goal.deadline, planningHorizon),
            calendar: calendar
        )
        return FlexibleGoalAssessmentV2(goal: goal, purchaseAssessment: assessment)
    }
}
