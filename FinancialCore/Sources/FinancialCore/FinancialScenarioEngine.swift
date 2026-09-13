import Foundation

public enum FinancialScenarioEngine {
    public static func percentile(_ values: [Double], p: Double) -> Double {
        guard !values.isEmpty else { return 0 }

        let sorted = values.sorted()
        let boundedP = min(max(p, 0), 1)
        let position = boundedP * Double(sorted.count - 1)
        let lowerIndex = Int(floor(position))
        let upperIndex = Int(ceil(position))

        if lowerIndex == upperIndex {
            return sorted[lowerIndex]
        }

        let weight = position - Double(lowerIndex)
        return sorted[lowerIndex] * (1 - weight) + sorted[upperIndex] * weight
    }

    public static func weeklySpendingAssumption(
        profile: FinancialProfile,
        scenario: FinancialScenario,
        calendar: Calendar = .current
    ) -> Double {
        let eligible = FinancialEngine.eligibleWeeklySpendingValues(
            profile: profile,
            calendar: calendar
        )

        switch scenario {
        case .conservative:
            return percentile(eligible, p: 0.75)
        case .expected:
            return percentile(eligible, p: 0.50)
        case .optimistic:
            return percentile(eligible, p: 0.25)
        }
    }

    public static func adjustedProfile(
        _ profile: FinancialProfile,
        for scenario: FinancialScenario,
        calendar: Calendar = .current
    ) -> FinancialProfile {
        var adjusted = profile

        // Reliability, not the raw income type, decides how much of a future payment a
        // scenario may count on. The discount is folded into the amount once here so no
        // downstream consumer discounts the same money a second time.
        adjusted.incomeEvents = profile.incomeEvents.map { event in
            let weight = event.reliability.multiplier(
                for: scenario,
                confidence: event.confidence
            )

            return IncomeEvent(
                id: event.id,
                amount: event.scenarioNominalAmount(for: scenario) * weight,
                date: event.scenarioDate(for: scenario),
                source: event.source,
                type: event.type,
                confidence: 1,
                reliability: .reliable,
                recurrenceRule: event.recurrenceRule,
                allocations: event.allocations,
                planningSource: event.planningSource,
                planningStatus: event.planningStatus
            )
        }

        adjusted.expenseEvents = profile.expenseEvents.map { event in
            ExpenseEvent(
                id: event.id,
                amount: event.scenarioAmount(for: scenario),
                date: event.scenarioDate(for: scenario),
                category: event.category,
                essential: event.essential,
                committed: event.committed,
                reimbursable: event.reimbursable,
                extraordinary: event.extraordinary,
                recurrenceRule: event.recurrenceRule,
                merchantIdentity: event.merchantIdentity,
                planningSource: event.planningSource,
                planningStatus: event.planningStatus
            )
        }

        let eligible = FinancialEngine.eligibleWeeklySpendingValues(
            profile: profile,
            calendar: calendar
        )

        if eligible.isEmpty {
            adjusted.weeklySpendingHistory = []
        } else {
            let weekly = weeklySpendingAssumption(
                profile: profile,
                scenario: scenario,
                calendar: calendar
            )
            adjusted.weeklySpendingHistory = [
                WeeklySpendingSample(
                    weekStart: profile.asOfDate,
                    totalVariableSpending: weekly
                )
            ]
        }

        return adjusted
    }

    public static func forecast(
        profile: FinancialProfile,
        targetDate: Date,
        scenario: FinancialScenario,
        calendar: Calendar = .current
    ) throws -> ScenarioForecastResult {
        let adjusted = adjustedProfile(profile, for: scenario, calendar: calendar)
        let result = try FinancialEngine.forecast(
            profile: adjusted,
            targetDate: targetDate,
            calendar: calendar
        )

        return ScenarioForecastResult(
            scenario: scenario,
            weeklySpendingAssumption: weeklySpendingAssumption(
                profile: profile,
                scenario: scenario,
                calendar: calendar
            ),
            forecast: result
        )
    }

    public static func forecastAll(
        profile: FinancialProfile,
        targetDate: Date,
        calendar: Calendar = .current
    ) throws -> [ScenarioForecastResult] {
        try FinancialScenario.allCases.map { scenario in
            try forecast(
                profile: profile,
                targetDate: targetDate,
                scenario: scenario,
                calendar: calendar
            )
        }
    }

    public static func assessPurchase(
        profile: FinancialProfile,
        amount: Double,
        purchaseDate: Date,
        planningHorizon: Date,
        scenario: FinancialScenario,
        calendar: Calendar = .current
    ) throws -> ScenarioPurchaseResult {
        let adjusted = adjustedProfile(profile, for: scenario, calendar: calendar)
        let assessment = try FinancialEngine.assessPurchase(
            profile: adjusted,
            amount: amount,
            purchaseDate: purchaseDate,
            planningHorizon: planningHorizon,
            calendar: calendar
        )

        return ScenarioPurchaseResult(
            scenario: scenario,
            weeklySpendingAssumption: weeklySpendingAssumption(
                profile: profile,
                scenario: scenario,
                calendar: calendar
            ),
            assessment: assessment
        )
    }

    public static func assessPurchaseAll(
        profile: FinancialProfile,
        amount: Double,
        purchaseDate: Date,
        planningHorizon: Date,
        calendar: Calendar = .current
    ) throws -> [ScenarioPurchaseResult] {
        try FinancialScenario.allCases.map { scenario in
            try assessPurchase(
                profile: profile,
                amount: amount,
                purchaseDate: purchaseDate,
                planningHorizon: planningHorizon,
                scenario: scenario,
                calendar: calendar
            )
        }
    }
}
