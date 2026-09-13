import Foundation

public enum FinancialHealthStatus: String, Codable, Sendable {
    case safe = "SAFE"
    case tight = "TIGHT"
    case notSafe = "NOT_SAFE"
}

public struct CashFlowPoint: Sendable {
    public let date: Date
    public let projectedCash: Double
    public let hardFloor: Double
    public let recommendedFloor: Double
    public let safetyBuffer: Double
    public let hardHeadroom: Double
    public let recommendedHeadroom: Double
    public let status: FinancialHealthStatus
}

public struct WeeklyBudgetRecommendation: Sendable {
    public let startDate: Date
    public let planningHorizon: Date
    public let typicalWeeklySpending: Double
    public let additionalWeeklyCapacity: Double
    public let recommendedWeeklySpendingLimit: Double
    public let limitingDate: Date
}

public struct FinancialDashboardSnapshot: Sendable {
    public let asOfDate: Date
    public let planningHorizon: Date
    public let currentStatus: FinancialHealthStatus
    public let horizonStatus: FinancialHealthStatus
    public let safeToSpendNow: Double
    public let typicalWeeklySpending: Double
    public let additionalWeeklyCapacity: Double
    public let recommendedWeeklySpendingLimit: Double
    public let minimumHardHeadroom: Double
    public let minimumRecommendedHeadroom: Double
    public let tightestDate: Date
}

public enum FinancialInsights {
    public static func healthStatus(for forecast: ForecastResult) -> FinancialHealthStatus {
        if forecast.hardHeadroom < 0 {
            return .notSafe
        }
        if forecast.recommendedHeadroom < 0 {
            return .tight
        }
        return .safe
    }

    public static func healthStatus(for horizon: HorizonHeadroom) -> FinancialHealthStatus {
        if horizon.minimumHardHeadroom < 0 {
            return .notSafe
        }
        if horizon.minimumRecommendedHeadroom < 0 {
            return .tight
        }
        return .safe
    }

    public static func cashFlowPoint(from forecast: ForecastResult) -> CashFlowPoint {
        CashFlowPoint(
            date: forecast.targetDate,
            projectedCash: forecast.projectedCash,
            hardFloor: forecast.hardFloor,
            recommendedFloor: forecast.hardFloor + forecast.safetyBuffer,
            safetyBuffer: forecast.safetyBuffer,
            hardHeadroom: forecast.hardHeadroom,
            recommendedHeadroom: forecast.recommendedHeadroom,
            status: healthStatus(for: forecast)
        )
    }

    /// Returns UI-ready daily cash-flow points. This is intentionally simple for the MVP
    /// so SwiftUI can render a financial-health calendar or line chart without duplicating
    /// the math engine's rules.
    public static func cashFlowTimeline(
        profile: FinancialProfile,
        from startDate: Date,
        through endDate: Date,
        calendar: Calendar = .current
    ) throws -> [CashFlowPoint] {
        guard endDate >= startDate else {
            throw FinancialEngineError.invalidDateRange
        }
        guard startDate >= profile.asOfDate else {
            throw FinancialEngineError.targetDateBeforeProfileDate
        }

        var points: [CashFlowPoint] = []
        var date = startDate

        while date <= endDate {
            let forecast = try FinancialEngine.forecast(
                profile: profile,
                targetDate: date,
                calendar: calendar
            )
            points.append(cashFlowPoint(from: forecast))

            guard let next = calendar.date(byAdding: .day, value: 1, to: date) else {
                break
            }
            date = next
        }

        return points
    }

    /// Maximum constant amount of *additional* discretionary spending that can be used
    /// at the beginning of each 7-day block while preserving the recommended floor.
    ///
    /// Normal projected variable spending is already included in the baseline engine, so
    /// this value is extra capacity above the user's recent typical weekly spending.
    public static func weeklyBudgetRecommendation(
        profile: FinancialProfile,
        from startDate: Date,
        through planningHorizon: Date,
        calendar: Calendar = .current
    ) throws -> WeeklyBudgetRecommendation {
        let timeline = try cashFlowTimeline(
            profile: profile,
            from: startDate,
            through: planningHorizon,
            calendar: calendar
        )

        guard let first = timeline.first else {
            throw FinancialEngineError.invalidDateRange
        }

        var limitingDate = first.date
        var maxAdditionalWeekly = Double.greatestFiniteMagnitude

        for point in timeline {
            let days = max(
                0,
                calendar.dateComponents([.day], from: startDate, to: point.date).day ?? 0
            )
            let weeklyDebitsSoFar = (days / 7) + 1
            let capacityAtPoint = point.recommendedHeadroom / Double(weeklyDebitsSoFar)

            if capacityAtPoint < maxAdditionalWeekly {
                maxAdditionalWeekly = capacityAtPoint
                limitingDate = point.date
            }
        }

        let additional = max(0, maxAdditionalWeekly)
        let typical = FinancialEngine.typicalWeeklySpending(
            profile: profile,
            calendar: calendar
        )

        return WeeklyBudgetRecommendation(
            startDate: startDate,
            planningHorizon: planningHorizon,
            typicalWeeklySpending: typical,
            additionalWeeklyCapacity: additional,
            recommendedWeeklySpendingLimit: typical + additional,
            limitingDate: limitingDate
        )
    }

    /// One-call summary intended for the app's home screen.
    /// It keeps the UI thin: SwiftUI renders these outputs rather than reimplementing math.
    public static func dashboard(
        profile: FinancialProfile,
        through planningHorizon: Date,
        calendar: Calendar = .current
    ) throws -> FinancialDashboardSnapshot {
        guard planningHorizon >= profile.asOfDate else {
            throw FinancialEngineError.invalidDateRange
        }

        let currentForecast = try FinancialEngine.forecast(
            profile: profile,
            targetDate: profile.asOfDate,
            calendar: calendar
        )
        let horizon = try FinancialEngine.minimumHeadroom(
            profile: profile,
            from: profile.asOfDate,
            through: planningHorizon,
            calendar: calendar
        )
        let safeNow = try FinancialEngine.safeToSpend(
            profile: profile,
            from: profile.asOfDate,
            through: planningHorizon,
            calendar: calendar
        )
        let weekly = try weeklyBudgetRecommendation(
            profile: profile,
            from: profile.asOfDate,
            through: planningHorizon,
            calendar: calendar
        )

        return FinancialDashboardSnapshot(
            asOfDate: profile.asOfDate,
            planningHorizon: planningHorizon,
            currentStatus: healthStatus(for: currentForecast),
            horizonStatus: healthStatus(for: horizon),
            safeToSpendNow: safeNow,
            typicalWeeklySpending: weekly.typicalWeeklySpending,
            additionalWeeklyCapacity: weekly.additionalWeeklyCapacity,
            recommendedWeeklySpendingLimit: weekly.recommendedWeeklySpendingLimit,
            minimumHardHeadroom: horizon.minimumHardHeadroom,
            minimumRecommendedHeadroom: horizon.minimumRecommendedHeadroom,
            tightestDate: horizon.tightestRecommendedDate
        )
    }
}
