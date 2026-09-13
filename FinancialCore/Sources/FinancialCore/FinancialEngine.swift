import Foundation

public enum FinancialEngine {
    public static func median(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[middle - 1] + sorted[middle]) / 2
        }
        return sorted[middle]
    }

    public static func eligibleWeeklySpendingValues(
        profile: FinancialProfile,
        calendar: Calendar = .current
    ) -> [Double] {
        let lookbackWeeks = max(0, profile.spendingPolicy.lookbackWeeks)
        guard lookbackWeeks > 0 else { return [] }

        let earliestDate = calendar.date(
            byAdding: .day,
            value: -(lookbackWeeks * 7),
            to: profile.asOfDate
        ) ?? .distantPast

        return profile.weeklySpendingHistory
            .filter {
                !$0.excludedFromBaseline &&
                $0.weekStart <= profile.asOfDate &&
                $0.weekStart >= earliestDate
            }
            .map { max(0, $0.totalVariableSpending) }
    }

    public static func typicalWeeklySpending(
        profile: FinancialProfile,
        calendar: Calendar = .current
    ) -> Double {
        median(eligibleWeeklySpendingValues(profile: profile, calendar: calendar))
    }

    public static func safetyBuffer(
        profile: FinancialProfile,
        calendar: Calendar = .current
    ) -> Double {
        let historyBased = typicalWeeklySpending(profile: profile, calendar: calendar)
            * max(0, profile.spendingPolicy.bufferWeeks)
        return max(max(0, profile.spendingPolicy.manualMinimumBuffer), historyBased)
    }

    public static func personalReserve(profile: FinancialProfile, on date: Date) -> Double {
        let applicable = profile.personalReserveSteps
            .filter { $0.effectiveDate <= date }
            .max { $0.effectiveDate < $1.effectiveDate }
        return max(0, applicable?.minimumCash ?? 0)
    }

    public static func institutionalMinimum(profile: FinancialProfile, on date: Date) -> Double {
        profile.institutionalMinimums
            .filter { $0.isActive(on: date) }
            .reduce(0) { $0 + max(0, $1.minimumBalance) }
    }

    public static func hardFloor(profile: FinancialProfile, on date: Date) -> Double {
        max(
            personalReserve(profile: profile, on: date),
            institutionalMinimum(profile: profile, on: date)
        )
    }

    public static func expectedIncome(profile: FinancialProfile, targetDate: Date) -> Double {
        profile.incomeEvents
            .filter { $0.date > profile.asOfDate && $0.date <= targetDate }
            .reduce(0) { $0 + max(0, $1.adjustedAmount) }
    }

    public static func committedExpenses(profile: FinancialProfile, targetDate: Date) -> Double {
        profile.expenseEvents
            .filter {
                $0.committed &&
                $0.date > profile.asOfDate &&
                $0.date <= targetDate
            }
            .reduce(0) { $0 + max(0, $1.amount) }
    }

    /// Remaining mandatory goals are future obligations even when their deadline has
    /// already passed. An overdue unpaid goal is therefore treated as immediately due
    /// rather than disappearing from the forecast.
    public static func mandatoryGoalPayments(profile: FinancialProfile, targetDate: Date) -> Double {
        profile.goals
            .filter {
                $0.priority == .mandatory &&
                $0.remainingAmount > 0 &&
                $0.deadline <= targetDate
            }
            .reduce(0) { $0 + $1.remainingAmount }
    }

    public static func projectedVariableSpending(
        profile: FinancialProfile,
        targetDate: Date,
        calendar: Calendar = .current
    ) -> Double {
        guard targetDate > profile.asOfDate else { return 0 }
        let days = max(
            0,
            calendar.dateComponents([.day], from: profile.asOfDate, to: targetDate).day ?? 0
        )
        return typicalWeeklySpending(profile: profile, calendar: calendar)
            * Double(days) / 7.0
    }

    public static func forecast(
        profile: FinancialProfile,
        targetDate: Date,
        calendar: Calendar = .current
    ) throws -> ForecastResult {
        guard targetDate >= profile.asOfDate else {
            throw FinancialEngineError.targetDateBeforeProfileDate
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
        let buffer = safetyBuffer(profile: profile, calendar: calendar)
        let hardHeadroom = cash - floor
        let recommendedHeadroom = hardHeadroom - buffer

        return ForecastResult(
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

    public static func minimumHeadroom(
        profile: FinancialProfile,
        from startDate: Date,
        through endDate: Date,
        calendar: Calendar = .current
    ) throws -> HorizonHeadroom {
        guard endDate >= startDate else {
            throw FinancialEngineError.invalidDateRange
        }
        guard startDate >= profile.asOfDate else {
            throw FinancialEngineError.targetDateBeforeProfileDate
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

        return HorizonHeadroom(
            startDate: startDate,
            endDate: endDate,
            minimumHardHeadroom: minHard,
            minimumRecommendedHeadroom: minRecommended,
            tightestHardDate: minHardDate,
            tightestRecommendedDate: minRecommendedDate
        )
    }

    public static func safeToSpend(
        profile: FinancialProfile,
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

    public static func assessPurchase(
        profile: FinancialProfile,
        amount: Double,
        purchaseDate: Date,
        planningHorizon: Date,
        calendar: Calendar = .current
    ) throws -> PurchaseAssessment {
        guard amount >= 0 else {
            throw FinancialEngineError.negativeAmount
        }
        guard planningHorizon >= purchaseDate else {
            throw FinancialEngineError.invalidDateRange
        }
        guard purchaseDate >= profile.asOfDate else {
            throw FinancialEngineError.targetDateBeforeProfileDate
        }

        let baseline = try minimumHeadroom(
            profile: profile,
            from: purchaseDate,
            through: planningHorizon,
            calendar: calendar
        )

        let hardAfter = baseline.minimumHardHeadroom - amount
        let recommendedAfter = baseline.minimumRecommendedHeadroom - amount

        let status: PurchaseStatus
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

        return PurchaseAssessment(
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
            tightestHardDate: baseline.tightestHardDate,
            tightestRecommendedDate: baseline.tightestRecommendedDate,
            recommendedDate: recommendedDate
        )
    }

    public static func earliestSafePurchaseDate(
        profile: FinancialProfile,
        amount: Double,
        startDate: Date,
        planningHorizon: Date,
        calendar: Calendar = .current
    ) throws -> Date? {
        guard amount >= 0 else {
            throw FinancialEngineError.negativeAmount
        }
        guard planningHorizon >= startDate else {
            throw FinancialEngineError.invalidDateRange
        }
        guard startDate >= profile.asOfDate else {
            throw FinancialEngineError.targetDateBeforeProfileDate
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

    public static func assessFlexibleGoal(
        profile: FinancialProfile,
        goal: Goal,
        planningHorizon: Date,
        calendar: Calendar = .current
    ) throws -> FlexibleGoalAssessment {
        // An overdue flexible goal is a decision the user can make now; it should not
        // become impossible to assess merely because its preferred date has passed.
        let effectiveDate = max(goal.deadline, profile.asOfDate)
        let assessment = try assessPurchase(
            profile: profile,
            amount: goal.remainingAmount,
            purchaseDate: effectiveDate,
            planningHorizon: max(effectiveDate, planningHorizon),
            calendar: calendar
        )
        return FlexibleGoalAssessment(goal: goal, purchaseAssessment: assessment)
    }
}

