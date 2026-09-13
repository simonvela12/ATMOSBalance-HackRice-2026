import Foundation

extension QualitativeMissingField: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(rawValue)
    }
}

/// Converts structured qualitative directives into the concrete dated events that
/// `FinancialCore` already understands. The selected transaction itself remains owned by
/// the app/normalization layer; these helpers create only the future consequences.
public enum QualitativeDirectiveMaterializer {
    public static func reimbursementIncome(
        from result: QualitativeParseResult,
        context: QualitativeNoteContext
    ) -> IncomeEvent? {
        guard context.subject == .expense,
              let amount = context.referenceAmount,
              amount >= 0,
              let repaymentDate = result.directives.compactMap({ directive -> Date? in
                  if case let .expectReimbursement(on: date) = directive { return date }
                  return nil
              }).first else {
            return nil
        }

        return IncomeEvent(
            amount: amount,
            date: repaymentDate,
            source: "Reimbursement: \(context.label ?? "expense")",
            type: .oneTime,
            confidence: 1.0
        )
    }

    public static func recurringIncomeEvents(
        from result: QualitativeParseResult,
        context: QualitativeNoteContext,
        asOfDate: Date,
        through horizon: Date,
        calendar: Calendar = .current
    ) throws -> [IncomeEvent] {
        guard context.subject == .income,
              let amount = context.referenceAmount,
              amount >= 0,
              let anchor = context.referenceDate,
              let recurrence = recurrence(from: result) else {
            return []
        }

        let firstDate = recurrence.firstDate
            ?? firstOccurrence(after: asOfDate, anchoredAt: anchor, cadence: recurrence.cadence, calendar: calendar)

        guard let firstDate, firstDate <= horizon else { return [] }

        return try FinancialScheduleBuilder.recurringIncome(
            amount: amount,
            firstDate: firstDate,
            through: horizon,
            source: context.label ?? "Recurring income",
            cadence: recurrence.cadence,
            calendar: calendar
        ).filter { $0.date > asOfDate }
    }

    public static func recurringExpenseEvents(
        from result: QualitativeParseResult,
        context: QualitativeNoteContext,
        asOfDate: Date,
        through horizon: Date,
        essential: Bool = true,
        committed: Bool = true,
        calendar: Calendar = .current
    ) throws -> [ExpenseEvent] {
        guard context.subject == .expense,
              let amount = context.referenceAmount,
              amount >= 0,
              let anchor = context.referenceDate,
              let recurrence = recurrence(from: result) else {
            return []
        }

        let interpretedEssential = booleanDirective(
            in: result,
            matching: { directive in
                if case let .setExpenseEssential(value) = directive { return value }
                return nil
            }
        ) ?? essential

        let interpretedCommitted = booleanDirective(
            in: result,
            matching: { directive in
                if case let .setExpenseCommitted(value) = directive { return value }
                return nil
            }
        ) ?? committed

        let firstDate = recurrence.firstDate
            ?? firstOccurrence(after: asOfDate, anchoredAt: anchor, cadence: recurrence.cadence, calendar: calendar)

        guard let firstDate, firstDate <= horizon else { return [] }

        return try FinancialScheduleBuilder.recurringExpense(
            amount: amount,
            firstDate: firstDate,
            through: horizon,
            category: context.label ?? "Recurring expense",
            cadence: recurrence.cadence,
            essential: interpretedEssential,
            committed: interpretedCommitted,
            calendar: calendar
        ).filter { $0.date > asOfDate }
    }

    public static func reserveSteps(
        from result: QualitativeParseResult,
        note: String = "Qualitative note"
    ) -> [PersonalReserveStep] {
        result.directives.compactMap { directive in
            guard case let .setPersonalReserve(amount: amount, effectiveDate: date) = directive else {
                return nil
            }
            return PersonalReserveStep(
                effectiveDate: date,
                minimumCash: amount,
                note: note
            )
        }
    }

    private static func recurrence(
        from result: QualitativeParseResult
    ) -> (cadence: RecurrenceCadence, firstDate: Date?)? {
        result.directives.compactMap { directive in
            if case let .setRecurrence(cadence: cadence, firstDate: firstDate) = directive {
                return (cadence, firstDate)
            }
            return nil
        }.first
    }

    private static func booleanDirective(
        in result: QualitativeParseResult,
        matching: (QualitativeDirective) -> Bool?
    ) -> Bool? {
        for directive in result.directives {
            if let value = matching(directive) { return value }
        }
        return nil
    }

    private static func firstOccurrence(
        after asOfDate: Date,
        anchoredAt anchor: Date,
        cadence: RecurrenceCadence,
        calendar: Calendar
    ) -> Date? {
        if anchor > asOfDate { return anchor }

        var current = anchor
        var safetyCounter = 0
        while current <= asOfDate && safetyCounter < 10_000 {
            let next: Date?
            switch cadence {
            case .weekly:
                next = calendar.date(byAdding: .day, value: 7, to: current)
            case .biweekly:
                next = calendar.date(byAdding: .day, value: 14, to: current)
            case .monthly:
                next = calendar.date(byAdding: .month, value: 1, to: current)
            }

            guard let next, next > current else { return nil }
            current = next
            safetyCounter += 1
        }

        return current > asOfDate ? current : nil
    }
}

