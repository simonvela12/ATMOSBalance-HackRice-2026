import Foundation

public enum RecurrenceCadence: String, Codable, CaseIterable, Sendable {
    case weekly
    case biweekly
    case monthly
}

/// Small deterministic helper for turning qualitative "this repeats" decisions into
/// dated events that the cash-flow engine already understands.
///
/// `IncomeType.recurring` is semantic metadata; it does not, by itself, create future
/// occurrences. Likewise, `ExpenseEvent` represents one dated cash movement. The app's
/// normalization layer can use this helper to materialize future occurrences through the
/// selected planning horizon before building a `FinancialProfile`.
public enum FinancialScheduleBuilder {
    public static func dates(
        startingOn firstDate: Date,
        through endDate: Date,
        cadence: RecurrenceCadence,
        calendar: Calendar = .current
    ) throws -> [Date] {
        guard endDate >= firstDate else {
            throw FinancialEngineError.invalidDateRange
        }

        if cadence == .monthly {
            // Anchor every occurrence to the original day instead of advancing from the
            // previous (possibly clamped) month. Jan 31 -> Feb 28 -> Mar 31, rather than
            // drifting permanently to the 28th after February.
            var result: [Date] = []
            var monthOffset = 0

            while let occurrence = calendar.date(byAdding: .month, value: monthOffset, to: firstDate),
                  occurrence <= endDate {
                result.append(occurrence)
                monthOffset += 1
            }

            return result
        }

        var result: [Date] = []
        var current = firstDate
        let dayStep = cadence == .weekly ? 7 : 14

        while current <= endDate {
            result.append(current)

            guard let next = calendar.date(byAdding: .day, value: dayStep, to: current),
                  next > current else {
                break
            }
            current = next
        }

        return result
    }

    public static func recurringIncome(
        amount: Double,
        firstDate: Date,
        through endDate: Date,
        source: String,
        cadence: RecurrenceCadence,
        confidence: Double = 1.0,
        calendar: Calendar = .current
    ) throws -> [IncomeEvent] {
        guard amount >= 0 else {
            throw FinancialEngineError.negativeAmount
        }

        return try dates(
            startingOn: firstDate,
            through: endDate,
            cadence: cadence,
            calendar: calendar
        ).map { date in
            IncomeEvent(
                amount: amount,
                date: date,
                source: source,
                type: .recurring,
                confidence: confidence
            )
        }
    }

    public static func recurringExpense(
        amount: Double,
        firstDate: Date,
        through endDate: Date,
        category: String,
        cadence: RecurrenceCadence,
        essential: Bool = true,
        committed: Bool = true,
        reimbursable: Bool = false,
        extraordinary: Bool = false,
        calendar: Calendar = .current
    ) throws -> [ExpenseEvent] {
        guard amount >= 0 else {
            throw FinancialEngineError.negativeAmount
        }

        return try dates(
            startingOn: firstDate,
            through: endDate,
            cadence: cadence,
            calendar: calendar
        ).map { date in
            ExpenseEvent(
                amount: amount,
                date: date,
                category: category,
                essential: essential,
                committed: committed,
                reimbursable: reimbursable,
                extraordinary: extraordinary
            )
        }
    }
}
