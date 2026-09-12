import Foundation

enum FinancialScenarioV2: String, Codable, CaseIterable {
    case conservative = "CONSERVATIVE"
    case expected = "EXPECTED"
    case optimistic = "OPTIMISTIC"
}

struct ScenarioForecastResultV2 {
    let scenario: FinancialScenarioV2
    let weeklySpendingAssumption: Double
    let forecast: ForecastResultV2
}

struct ScenarioPurchaseResultV2 {
    let scenario: FinancialScenarioV2
    let weeklySpendingAssumption: Double
    let assessment: PurchaseAssessmentV2
}

/// A deterministic uncertainty layer on top of FinancialEngineV2.
///
/// This deliberately does not use machine learning or Monte Carlo simulation.
/// It answers a simpler question: how does the same plan behave under a
/// conservative, expected, and optimistic interpretation of uncertain inputs?
enum FinancialScenarioEngineV2 {
    static func percentile(_ values: [Double], p: Double) -> Double {
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

    static func weeklySpendingAssumption(
        profile: FinancialProfileV2,
        scenario: FinancialScenarioV2
    ) -> Double {
        let eligible = profile.weeklySpendingHistory
            .filter { !$0.excludedFromBaseline }
            .map { max(0, $0.totalVariableSpending) }

        switch scenario {
        case .conservative:
            // A higher-spending but still history-based week.
            return percentile(eligible, p: 0.75)
        case .expected:
            return percentile(eligible, p: 0.50)
        case .optimistic:
            // A lower-spending but still history-based week.
            return percentile(eligible, p: 0.25)
        }
    }

    static func adjustedProfile(
        _ profile: FinancialProfileV2,
        for scenario: FinancialScenarioV2
    ) -> FinancialProfileV2 {
        var adjusted = profile

        adjusted.incomeEvents = profile.incomeEvents.map { event in
            let scenarioConfidence: Double

            switch event.type {
            case .recurring, .oneTime:
                // Explicitly scheduled recurring and known one-time payments
                // are treated as known cash events in all three scenarios.
                scenarioConfidence = event.confidence

            case .irregular:
                switch scenario {
                case .conservative:
                    // Do not rely on uncertain irregular income.
                    scenarioConfidence = 0
                case .expected:
                    // Use the user-confirmed / upstream confidence exactly as supplied.
                    scenarioConfidence = event.confidence
                case .optimistic:
                    // Assume the explicitly entered irregular payment arrives in full.
                    scenarioConfidence = 1
                }
            }

            return V2IncomeEvent(
                id: event.id,
                amount: event.amount,
                date: event.date,
                source: event.source,
                type: event.type,
                confidence: scenarioConfidence
            )
        }

        let weekly = weeklySpendingAssumption(profile: profile, scenario: scenario)
        let hadEligibleHistory = profile.weeklySpendingHistory.contains { !$0.excludedFromBaseline }

        if hadEligibleHistory {
            // FinancialEngineV2 uses the median weekly sample. Replacing the history
            // with one derived scenario sample lets the core deterministic engine stay
            // unchanged while each scenario gets a different spending assumption.
            adjusted.weeklySpendingHistory = [
                WeeklySpendingSample(
                    weekStart: profile.asOfDate,
                    totalVariableSpending: weekly
                )
            ]
        } else {
            adjusted.weeklySpendingHistory = []
        }

        return adjusted
    }

    static func forecast(
        profile: FinancialProfileV2,
        targetDate: Date,
        scenario: FinancialScenarioV2,
        calendar: Calendar = .current
    ) throws -> ScenarioForecastResultV2 {
        let adjusted = adjustedProfile(profile, for: scenario)
        let forecast = try FinancialEngineV2.forecast(
            profile: adjusted,
            targetDate: targetDate,
            calendar: calendar
        )

        return ScenarioForecastResultV2(
            scenario: scenario,
            weeklySpendingAssumption: weeklySpendingAssumption(
                profile: profile,
                scenario: scenario
            ),
            forecast: forecast
        )
    }

    static func forecastAll(
        profile: FinancialProfileV2,
        targetDate: Date,
        calendar: Calendar = .current
    ) throws -> [ScenarioForecastResultV2] {
        try FinancialScenarioV2.allCases.map { scenario in
            try forecast(
                profile: profile,
                targetDate: targetDate,
                scenario: scenario,
                calendar: calendar
            )
        }
    }

    static func assessPurchase(
        profile: FinancialProfileV2,
        amount: Double,
        purchaseDate: Date,
        planningHorizon: Date,
        scenario: FinancialScenarioV2,
        calendar: Calendar = .current
    ) throws -> ScenarioPurchaseResultV2 {
        let adjusted = adjustedProfile(profile, for: scenario)
        let assessment = try FinancialEngineV2.assessPurchase(
            profile: adjusted,
            amount: amount,
            purchaseDate: purchaseDate,
            planningHorizon: planningHorizon,
            calendar: calendar
        )

        return ScenarioPurchaseResultV2(
            scenario: scenario,
            weeklySpendingAssumption: weeklySpendingAssumption(
                profile: profile,
                scenario: scenario
            ),
            assessment: assessment
        )
    }

    static func assessPurchaseAll(
        profile: FinancialProfileV2,
        amount: Double,
        purchaseDate: Date,
        planningHorizon: Date,
        calendar: Calendar = .current
    ) throws -> [ScenarioPurchaseResultV2] {
        try FinancialScenarioV2.allCases.map { scenario in
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
