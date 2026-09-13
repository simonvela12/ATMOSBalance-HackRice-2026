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

    /// The remaining cost of active must-happen goals whose deadline is still ahead.
    ///
    /// This is a *descriptive* figure used to explain results. It is deliberately not
    /// part of the hard floor: a goal is a requirement on a future date, not money that
    /// has to sit untouched from today. Whether today's balance is actually committed to
    /// it depends on the cash-flow path between now and the deadline, which
    /// `minimumHeadroom` works out.
    public static func protectedMandatoryGoals(profile: FinancialProfile, on date: Date) -> Double {
        profile.goals
            .filter {
                $0.lifecycleState == .active &&
                $0.priority == .mandatory &&
                $0.remainingAmount > 0 &&
                $0.deadline > date
            }
            .reduce(0) { $0 + $1.remainingAmount }
    }

    /// The amount that must remain untouched on a date, i.e. the personal and
    /// institutional minimums. Goals are not added here; they enter the plan as dated
    /// obligations on their own deadline instead.
    public static func hardFloor(profile: FinancialProfile, on date: Date) -> Double {
        max(
            personalReserve(profile: profile, on: date),
            institutionalMinimum(profile: profile, on: date)
        )
    }

    /// Upper bound on how far ahead the engine will simulate. Keeps a stray far-future
    /// date from turning a daily scan into a multi-decade loop.
    public static let maximumPlanningHorizonInDays = 730

    /// The last date on which a dated obligation still has to be honoured. A caller may
    /// ask about a shorter window, but money committed to a goal beyond that window must
    /// not look spendable, so the scan always reaches at least this far.
    public static func obligationHorizon(profile: FinancialProfile) -> Date {
        profile.goals
            .filter {
                $0.lifecycleState == .active &&
                $0.priority == .mandatory &&
                $0.remainingAmount > 0
            }
            .map(\.deadline)
            .max() ?? profile.asOfDate
    }

    /// The date through which the plan has to stay viable: the furthest of the user's
    /// runway date, any active goal and any dated event, bounded by
    /// `maximumPlanningHorizonInDays`.
    public static func defaultPlanningHorizon(
        profile: FinancialProfile,
        calendar: Calendar = .current
    ) -> Date {
        var horizon = profile.asOfDate

        if let runway = profile.cashMustLastUntil {
            horizon = max(horizon, runway)
        }
        for goal in profile.goals where goal.lifecycleState == .active && goal.remainingAmount > 0 {
            horizon = max(horizon, goal.deadline)
        }
        for event in profile.incomeEvents {
            horizon = max(horizon, event.date)
        }
        for event in profile.expenseEvents where event.committed {
            horizon = max(horizon, event.date)
        }

        guard let cap = calendar.date(
            byAdding: .day,
            value: maximumPlanningHorizonInDays,
            to: profile.asOfDate
        ) else {
            return horizon
        }
        return min(horizon, cap)
    }

    /// Money that can leave the account today without breaking any hard requirement on
    /// any day of the plan. Unlike a static reservation this is forecast-aware: a goal
    /// that future income already covers stops holding today's balance hostage.
    ///
    /// It deliberately excludes the optional safety buffer, so the remainder is the
    /// user's genuinely unspoken-for balance; the buffer can still downgrade a purchase
    /// from safe to tight.
    public static func liquidCashToday(
        profile: FinancialProfile,
        through planningHorizon: Date? = nil,
        calendar: Calendar = .current
    ) throws -> Double {
        let horizon = max(
            planningHorizon ?? defaultPlanningHorizon(profile: profile, calendar: calendar),
            profile.asOfDate
        )
        let headroom = try minimumHeadroom(
            profile: profile,
            from: profile.asOfDate,
            through: horizon,
            calendar: calendar
        )
        return max(0, headroom.minimumHardHeadroom)
    }

    /// Everything in today's balance that the plan has already spoken for: minimums the
    /// user must keep plus the part of future commitments today's cash has to cover.
    public static func protectedCashToday(
        profile: FinancialProfile,
        through planningHorizon: Date? = nil,
        calendar: Calendar = .current
    ) throws -> Double {
        let liquid = try liquidCashToday(
            profile: profile,
            through: planningHorizon,
            calendar: calendar
        )
        return max(0, profile.currentCash - liquid)
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
    /// rather than disappearing from the forecast. Paused/completed goals do not move
    /// cash until they become active again.
    public static func mandatoryGoalPayments(profile: FinancialProfile, targetDate: Date) -> Double {
        profile.goals
            .filter {
                $0.lifecycleState == .active &&
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
        let floor = hardFloor(profile: profile, on: targetDate)
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

        // A caller may legitimately ask about a short window, but a must-happen goal
        // beyond that window is still committed money. Scanning to the obligation
        // horizon keeps that cash from looking spendable without turning the goal into
        // a reservation held from today.
        let scanEnd = max(endDate, obligationHorizon(profile: profile))

        var date = startDate
        var minHard = Double.greatestFiniteMagnitude
        var minRecommended = Double.greatestFiniteMagnitude
        var minHardDate = startDate
        var minRecommendedDate = startDate

        while date <= scanEnd {
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
