import Foundation

public enum CashFlowDirection: String, Codable, Sendable {
    case income
    case expense
}

public struct AmountRange: Codable, Equatable, Sendable {
    public let minimum: Double
    public let expected: Double
    public let maximum: Double

    public init(minimum: Double, expected: Double, maximum: Double) {
        let low = max(0, min(minimum, maximum))
        let high = max(low, max(minimum, maximum))
        self.minimum = low
        self.maximum = high
        self.expected = min(max(max(0, expected), low), high)
    }

    public func amount(for scenario: FinancialScenario, direction: CashFlowDirection) -> Double {
        switch (direction, scenario) {
        case (.income, .conservative): return minimum
        case (.income, .expected): return expected
        case (.income, .optimistic): return maximum
        case (.expense, .conservative): return maximum
        case (.expense, .expected): return expected
        case (.expense, .optimistic): return minimum
        }
    }
}

public struct DateWindow: Codable, Equatable, Sendable {
    public let earliest: Date
    public let expected: Date
    public let latest: Date

    public init(earliest: Date, expected: Date, latest: Date) {
        let low = min(earliest, latest)
        let high = max(earliest, latest)
        self.earliest = low
        self.latest = high
        self.expected = min(max(expected, low), high)
    }

    public func date(for scenario: FinancialScenario, direction: CashFlowDirection) -> Date {
        switch (direction, scenario) {
        case (.income, .conservative): return latest
        case (.income, .expected): return expected
        case (.income, .optimistic): return earliest
        case (.expense, .conservative): return earliest
        case (.expense, .expected): return expected
        case (.expense, .optimistic): return latest
        }
    }

    public func contains(_ date: Date) -> Bool {
        date >= earliest && date <= latest
    }
}

public enum RecurrenceUnit: String, Codable, Sendable {
    case day
    case week
    case month
}

public struct RecurrenceInterval: Codable, Equatable, Sendable {
    public let unit: RecurrenceUnit
    public let value: Int

    public init(unit: RecurrenceUnit, value: Int) {
        self.unit = unit
        self.value = max(1, value)
    }
}

public enum RecurrenceCadence: Codable, Equatable, Sendable {
    case weekly
    case biweekly
    case monthly
    case custom(RecurrenceInterval)

    fileprivate func nextDate(after date: Date, calendar: Calendar) -> Date? {
        switch self {
        case .weekly:
            return calendar.date(byAdding: .day, value: 7, to: date)
        case .biweekly:
            return calendar.date(byAdding: .day, value: 14, to: date)
        case .monthly:
            return calendar.date(byAdding: .month, value: 1, to: date)
        case .custom(let interval):
            switch interval.unit {
            case .day:
                return calendar.date(byAdding: .day, value: interval.value, to: date)
            case .week:
                return calendar.date(byAdding: .day, value: interval.value * 7, to: date)
            case .month:
                return calendar.date(byAdding: .month, value: interval.value, to: date)
            }
        }
    }
}

public struct RecurrenceRule: Codable, Equatable, Sendable {
    public let cadence: RecurrenceCadence
    public let firstOccurrence: Date
    public let endDate: Date?
    public let isPaused: Bool

    public init(cadence: RecurrenceCadence, firstOccurrence: Date, endDate: Date? = nil, isPaused: Bool = false) {
        self.cadence = cadence
        self.firstOccurrence = firstOccurrence
        self.endDate = endDate
        self.isPaused = isPaused
    }

    public func occurrenceDates(through horizon: Date, calendar: Calendar = .current) -> [Date] {
        guard !isPaused, horizon >= firstOccurrence else { return [] }
        var dates: [Date] = []
        var current = firstOccurrence

        while current <= horizon {
            if let endDate, current > endDate { break }
            dates.append(current)
            guard let next = cadence.nextDate(after: current, calendar: calendar), next > current else { break }
            current = next
        }
        return dates
    }
}

public struct IncomeAllocation: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let amount: Double
    public let purpose: String
    public let linkedGoalID: UUID?

    public init(id: UUID = UUID(), amount: Double, purpose: String, linkedGoalID: UUID? = nil) {
        self.id = id
        self.amount = max(0, amount)
        self.purpose = purpose
        self.linkedGoalID = linkedGoalID
    }
}

public enum PlanningEventSource: String, Codable, Sendable { case bank, manual, planned, derivedMatch }
public enum PlanningEventStatus: String, Codable, Sendable { case planned, pending, completed, overdue, missed, cancelled }
public enum MaterialityDecision: String, Codable, Sendable { case autoApply, askUser, ignoreNoImpact }
public enum PlanningRiskState: String, Codable, Sendable { case normal, belowRecommendedBuffer, belowHardFloor, negativeCash, mandatoryObligationShortfall }

public extension IncomeEvent {
    func scenarioNominalAmount(for scenario: FinancialScenario) -> Double {
        amountRange?.amount(for: scenario, direction: .income) ?? max(0, amount)
    }
    func scenarioDate(for scenario: FinancialScenario) -> Date {
        dateWindow?.date(for: scenario, direction: .income) ?? date
    }
}

public extension ExpenseEvent {
    func scenarioAmount(for scenario: FinancialScenario) -> Double {
        amountRange?.amount(for: scenario, direction: .expense) ?? max(0, amount)
    }
    func scenarioDate(for scenario: FinancialScenario) -> Date {
        dateWindow?.date(for: scenario, direction: .expense) ?? date
    }
}
