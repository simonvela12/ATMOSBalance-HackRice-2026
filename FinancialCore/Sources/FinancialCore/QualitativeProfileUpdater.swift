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
                guard let label else { break }

                var rewritten: [IncomeEvent] = []
                for event in updated.incomeEvents {
                    guard event.source == label else {
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
                guard let label else { break }
                let clamped = min(max(confidence, 0), 1)
                updated.incomeEvents = updated.incomeEvents.map { event in
                    guard event.source == label else { return event }
                    if event.type.rawValue != IncomeType.irregular.rawValue ||
                        abs(event.confidence - clamped) > 0.000_001 {
                        didChange = true
                        return copy(event, type: .irregular, confidence: clamped)
                    }
                    return event
                }

            case .setExpenseCommitted(let committed):
                guard let label else { break }
                updated.expenseEvents = updated.expenseEvents.map { event in
                    guard event.category == label else { return event }
                    if event.committed != committed {
                        didChange = true
                        return copy(event, committed: committed)
                    }
                    return event
                }

            case .setExpenseEssential(let essential):
                guard let label else { break }
                updated.expenseEvents = updated.expenseEvents.map { event in
                    guard event.category == label else { return event }
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

        if let reimbursement = QualitativeDirectiveMaterializer.reimbursementIncome(
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

        if context.subject == .income,
           let recurring = try? QualitativeDirectiveMaterializer.recurringIncomeEvents(
                from: result,
                context: context,
                asOfDate: updated.asOfDate,
                through: horizon,
                calendar: calendar
           ),
           !recurring.isEmpty,
           let label {
            let existing = updated.incomeEvents.filter {
                $0.source == label && $0.date > updated.asOfDate
            }
            if !sameIncomeSchedule(existing, recurring) {
                updated.incomeEvents.removeAll {
                    $0.source == label && $0.date > updated.asOfDate
                }
                updated.incomeEvents.append(contentsOf: recurring)
                didChange = true
            }
        }

        if context.subject == .expense,
           let label {
            let template = matchingExpenseTemplate(
                in: updated.expenseEvents,
                label: label,
                referenceDate: context.referenceDate
            )
            if let recurring = try? QualitativeDirectiveMaterializer.recurringExpenseEvents(
                from: result,
                context: context,
                asOfDate: updated.asOfDate,
                through: horizon,
                essential: template?.essential ?? true,
                committed: template?.committed ?? true,
                calendar: calendar
            ),
               !recurring.isEmpty {
                let existing = updated.expenseEvents.filter {
                    $0.category == label && $0.date > updated.asOfDate
                }
                if !sameExpenseSchedule(existing, recurring) {
                    updated.expenseEvents.removeAll {
                        $0.category == label && $0.date > updated.asOfDate
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
            let existing = updated.personalReserveSteps.filter { $0.note == reserveNote }
            if !sameReserveSchedule(existing, reserveSteps) {
                updated.personalReserveSteps.removeAll { $0.note == reserveNote }
                updated.personalReserveSteps.append(contentsOf: reserveSteps)
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

    private static func matchingExpenseTemplate(
        in events: [ExpenseEvent],
        label: String,
        referenceDate: Date?
    ) -> ExpenseEvent? {
        let matches = events.filter { $0.category == label }
        guard let referenceDate else { return matches.first }

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

    private static func sameReserveSchedule(
        _ lhs: [PersonalReserveStep],
        _ rhs: [PersonalReserveStep]
    ) -> Bool {
        let left = lhs.sorted { $0.effectiveDate < $1.effectiveDate }
        let right = rhs.sorted { $0.effectiveDate < $1.effectiveDate }
        guard left.count == right.count else { return false }
        return zip(left, right).allSatisfy { a, b in
            a.effectiveDate == b.effectiveDate &&
            abs(a.minimumCash - b.minimumCash) <= 0.000_001 &&
            a.note == b.note
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