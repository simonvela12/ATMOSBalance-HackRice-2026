import Foundation

/// Applies a confirmed qualitative interpretation to the structured inputs used by the
/// deterministic financial engine.
///
/// The updater is intentionally idempotent: confirming the same interpretation twice does
/// not manufacture new events or claim that the plan changed when the resulting financial
/// inputs are identical.
public struct QualitativeProfileApplication: Sendable {
    public let profile: FinancialProfile
    public let didChange: Bool

    public init(profile: FinancialProfile, didChange: Bool) {
        self.profile = profile
        self.didChange = didChange
    }
}

public enum QualitativeProfileUpdater {
    public static func apply(
        _ result: QualitativeParseResult,
        to profile: FinancialProfile,
        context: QualitativeNoteContext,
        goalID: UUID? = nil,
        through horizon: Date,
        reserveNote: String = "Confirmed qualitative context",
        calendar: Calendar = .current
    ) -> QualitativeProfileApplication {
        guard result.isActionable else {
            return QualitativeProfileApplication(profile: profile, didChange: false)
        }

        var updated = profile
        var didChange = false
        let label = context.label

        for directive in result.directives {
            switch directive {
            case .setIncomeType(let type):
                guard label != nil else { break }

                var rewritten: [IncomeEvent] = []
                for event in updated.incomeEvents {
                    guard matchesIncomeSeries(event, context: context) else {
                        rewritten.append(event)
                        continue
                    }

                    if type == .oneTime && event.date > updated.asOfDate {
                        didChange = true
                        continue
                    }

                    if event.type.rawValue != type.rawValue {
                        didChange = true
                        rewritten.append(copy(event, type: type))
                    } else {
                        rewritten.append(event)
                    }
                }
                updated.incomeEvents = rewritten

            case .setIrregularIncomeConfidence(let confidence):
                guard label != nil else { break }
                let clamped = min(max(confidence, 0), 1)
                updated.incomeEvents = updated.incomeEvents.map { event in
                    guard matchesIncomeSeries(event, context: context) else { return event }
                    if event.type.rawValue != IncomeType.irregular.rawValue ||
                        abs(event.confidence - clamped) > 0.000_001 {
                        didChange = true
                        return copy(event, type: .irregular, confidence: clamped)
                    }
                    return event
                }

            case .setExpenseCommitted(let committed):
                updated.expenseEvents = updated.expenseEvents.map { event in
                    guard matchesSelectedExpense(event, context: context) else { return event }
                    if event.committed != committed {
                        didChange = true
                        return copy(event, committed: committed)
                    }
                    return event
                }

            case .setExpenseEssential(let essential):
                updated.expenseEvents = updated.expenseEvents.map { event in
                    guard matchesSelectedExpense(event, context: context) else { return event }
                    if event.essential != essential {
                        didChange = true
                        return copy(event, essential: essential)
                    }
                    return event
                }

            case .setGoalPriority(let priority):
                guard let goalID,
                      let index = updated.goals.firstIndex(where: { $0.id == goalID }) else { break }
                let goal = updated.goals[index]
                if goal.priority.rawValue != priority.rawValue {
                    didChange = true
                    updated.goals[index] = Goal(
                        id: goal.id,
                        name: goal.name,
                        targetAmount: goal.targetAmount,
                        amountAlreadyPaid: goal.amountAlreadyPaid,
                        deadline: goal.deadline,
                        priority: priority
                    )
                }

            case .expectReimbursement, .setRecurrence, .setPersonalReserve:
                break
            }
        }

        // Transaction-specific context is allowed to annotate linked financial data, not create
        // a transaction that the profile never contained. This prevents stale/demo UI context from
        // manufacturing future cash when its referenced bank transaction is missing.
        let hasSelectedExpense = updated.expenseEvents.contains {
            matchesSelectedExpense($0, context: context)
        }
        if hasSelectedExpense,
           let reimbursement = QualitativeDirectiveMaterializer.reimbursementIncome(
                from: result,
                context: context
           ) {
            let matches = updated.incomeEvents.filter {
                $0.source == reimbursement.source && $0.date == reimbursement.date
            }
            if matches.count != 1 || !sameFinancialIncome(matches[0], reimbursement) {
                updated.incomeEvents.removeAll {
                    $0.source == reimbursement.source && $0.date == reimbursement.date
                }
                updated.incomeEvents.append(reimbursement)
                didChange = true
            }
        }

        let hasSelectedIncome = updated.incomeEvents.contains {
            matchesSelectedIncome($0, context: context)
        }
        if context.subject == .income,
           hasSelectedIncome,
           let recurring = try? QualitativeDirectiveMaterializer.recurringIncomeEvents(
                from: result,
                context: context,
                asOfDate: updated.asOfDate,
                through: horizon,
                calendar: calendar
           ),
           !recurring.isEmpty,
           label != nil {
            let existing = updated.incomeEvents.filter {
                $0.date > updated.asOfDate && matchesIncomeSeries($0, context: context)
            }
            if !sameIncomeSchedule(existing, recurring) {
                updated.incomeEvents.removeAll {
                    $0.date > updated.asOfDate && matchesIncomeSeries($0, context: context)
                }
                updated.incomeEvents.append(contentsOf: recurring)
                didChange = true
            }
        }

        if context.subject == .expense,
           label != nil,
           let template = matchingExpenseTemplate(
                in: updated.expenseEvents,
                context: context
           ) {
            if let recurring = try? QualitativeDirectiveMaterializer.recurringExpenseEvents(
                from: result,
                context: context,
                asOfDate: updated.asOfDate,
                through: horizon,
                essential: template.essential,
                committed: template.committed,
                calendar: calendar
            ),
               !recurring.isEmpty {
                let existing = updated.expenseEvents.filter {
                    $0.date > updated.asOfDate && matchesExpenseSeries($0, context: context)
                }
                if !sameExpenseSchedule(existing, recurring) {
                    updated.expenseEvents.removeAll {
                        $0.date > updated.asOfDate && matchesExpenseSeries($0, context: context)
                    }
                    updated.expenseEvents.append(contentsOf: recurring)
                    didChange = true
                }
            }
        }

        let reserveSteps = QualitativeDirectiveMaterializer.reserveSteps(
            from: result,
            note: reserveNote
        )
        if !reserveSteps.isEmpty {
            let replacementDates = Set(reserveSteps.map(\.effectiveDate))
            var candidate = updated.personalReserveSteps
            candidate.removeAll {
                $0.note == reserveNote || replacementDates.contains($0.effectiveDate)
            }
            candidate.append(contentsOf: reserveSteps)

            if !sameFinancialReserveSchedule(updated.personalReserveSteps, candidate) {
                updated.personalReserveSteps = candidate
                didChange = true
            }
        }

        return QualitativeProfileApplication(profile: updated, didChange: didChange)
    }

    private static func copy(
        _ event: IncomeEvent,
        type: IncomeType? = nil,
        confidence: Double? = nil
    ) -> IncomeEvent {
        IncomeEvent(
            id: event.id,
            amount: event.amount,
            date: event.date,
            source: event.source,
            type: type ?? event.type,
            confidence: confidence ?? event.confidence
        )
    }

    private static func copy(
        _ event: ExpenseEvent,
        essential: Bool? = nil,
        committed: Bool? = nil
    ) -> ExpenseEvent {
        ExpenseEvent(
            id: event.id,
            amount: event.amount,
            date: event.date,
            category: event.category,
            essential: essential ?? event.essential,
            committed: committed ?? event.committed,
            reimbursable: event.reimbursable,
            extraordinary: event.extraordinary
        )
    }

    /// Direct expense directives describe the selected transaction, not every transaction that
    /// happens to share its display label/category. Reference date and amount narrow the target
    /// when the caller has them; label-only matching remains the fallback for legacy callers.
    private static func matchesSelectedExpense(
        _ event: ExpenseEvent,
        context: QualitativeNoteContext
    ) -> Bool {
        guard let label = context.label, event.category == label else { return false }

        if let referenceDate = context.referenceDate, event.date != referenceDate {
            return false
        }
        if let referenceAmount = context.referenceAmount,
           abs(event.amount - referenceAmount) > 0.000_001 {
            return false
        }
        return true
    }

    /// Income transaction-specific context must be anchored to the selected linked transaction
    /// when a reference date is available. Series operations can still use label + amount after
    /// that anchor has been verified.
    private static func matchesSelectedIncome(
        _ event: IncomeEvent,
        context: QualitativeNoteContext
    ) -> Bool {
        guard matchesIncomeSeries(event, context: context) else { return false }
        guard let referenceDate = context.referenceDate else { return true }
        return event.date == referenceDate
    }

    /// A generated recurring series is scoped by label and amount. This prevents confirming a
    /// cadence for one selected transaction from deleting a different future event that happens
    /// to use the same category/source label.
    private static func matchesExpenseSeries(
        _ event: ExpenseEvent,
        context: QualitativeNoteContext
    ) -> Bool {
        guard let label = context.label, event.category == label else { return false }
        guard let referenceAmount = context.referenceAmount else { return true }
        return abs(event.amount - referenceAmount) <= 0.000_001
    }

    /// Income classification and confidence describe the selected income series. Amount narrows
    /// the series when the caller has it so two deposits with the same bank/source label cannot
    /// accidentally reclassify or delete each other. Label-only matching remains the fallback for
    /// legacy callers that do not provide an amount.
    private static func matchesIncomeSeries(
        _ event: IncomeEvent,
        context: QualitativeNoteContext
    ) -> Bool {
        guard let label = context.label, event.source == label else { return false }
        guard let referenceAmount = context.referenceAmount else { return true }
        return abs(event.amount - referenceAmount) <= 0.000_001
    }

    private static func matchingExpenseTemplate(
        in events: [ExpenseEvent],
        context: QualitativeNoteContext
    ) -> ExpenseEvent? {
        let matches = events.filter { matchesExpenseSeries($0, context: context) }
        guard let referenceDate = context.referenceDate else { return matches.first }

        return matches.min { lhs, rhs in
            abs(lhs.date.timeIntervalSince(referenceDate)) < abs(rhs.date.timeIntervalSince(referenceDate))
        }
    }

    private static func sameIncomeSchedule(_ lhs: [IncomeEvent], _ rhs: [IncomeEvent]) -> Bool {
        let left = lhs.sorted { $0.date < $1.date }
        let right = rhs.sorted { $0.date < $1.date }
        guard left.count == right.count else { return false }
        return zip(left, right).allSatisfy { sameFinancialIncome($0.0, $0.1) }
    }

    private static func sameExpenseSchedule(_ lhs: [ExpenseEvent], _ rhs: [ExpenseEvent]) -> Bool {
        let left = lhs.sorted { $0.date < $1.date }
        let right = rhs.sorted { $0.date < $1.date }
        guard left.count == right.count else { return false }
        return zip(left, right).allSatisfy { a, b in
            a.date == b.date &&
            abs(a.amount - b.amount) <= 0.000_001 &&
            a.category == b.category &&
            a.essential == b.essential &&
            a.committed == b.committed &&
            a.reimbursable == b.reimbursable &&
            a.extraordinary == b.extraordinary
        }
    }

    private static func sameFinancialReserveSchedule(
        _ lhs: [PersonalReserveStep],
        _ rhs: [PersonalReserveStep]
    ) -> Bool {
        let left = lhs.sorted { $0.effectiveDate < $1.effectiveDate }
        let right = rhs.sorted { $0.effectiveDate < $1.effectiveDate }
        guard left.count == right.count else { return false }
        return zip(left, right).allSatisfy { a, b in
            a.effectiveDate == b.effectiveDate &&
            abs(a.minimumCash - b.minimumCash) <= 0.000_001
        }
    }

    private static func sameFinancialIncome(_ lhs: IncomeEvent, _ rhs: IncomeEvent) -> Bool {
        lhs.date == rhs.date &&
        abs(lhs.amount - rhs.amount) <= 0.000_001 &&
        lhs.source == rhs.source &&
        lhs.type.rawValue == rhs.type.rawValue &&
        abs(lhs.confidence - rhs.confidence) <= 0.000_001
    }
}
