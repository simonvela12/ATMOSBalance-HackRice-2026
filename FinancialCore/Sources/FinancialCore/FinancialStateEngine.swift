import Foundation

/// A movement the user actually made or is about to make. Negative amounts are money
/// leaving the account, positive amounts are money arriving.
public struct RecordedTransaction: Sendable, Identifiable {
    public let id: UUID
    public let amount: Double
    public let date: Date
    public let label: String
    public let category: String
    public let essential: Bool
    /// Only meaningful for incoming money: how much the plan may count on it.
    public let reliability: IncomeReliability

    public init(
        id: UUID = UUID(),
        amount: Double,
        date: Date,
        label: String,
        category: String = "Transaction",
        essential: Bool = false,
        reliability: IncomeReliability = .reliable
    ) {
        self.id = id
        self.amount = amount
        self.date = date
        self.label = label
        self.category = category
        self.essential = essential
        self.reliability = reliability
    }

    public var isSpending: Bool { amount < 0 }
    public var magnitude: Double { abs(amount) }
}

/// Something worth telling the user about. Produced from the engine's structured
/// results so the wording layer never has to work anything out for itself.
public struct FinancialWarning: Sendable, Equatable, Identifiable {
    public enum Kind: Hashable, Sendable {
        case runwayAtRisk(depletionDate: Date)
        case goalDelayed(goalID: UUID, days: Int)
        case goalUnreachable(goalID: UUID)
        case belowSafetyBuffer(date: Date)
        case dependsOnUncertainIncome(incomeID: UUID)
    }

    public let kind: Kind
    public let constraint: FinancialConstraint?

    public var id: Kind { kind }

    public init(kind: Kind, constraint: FinancialConstraint? = nil) {
        self.kind = kind
        self.constraint = constraint
    }
}

/// Everything the product knows about the user's position right now. One value so no
/// screen can drift out of step with another.
public struct FinancialStateSnapshot: Sendable {
    public let asOfDate: Date
    public let planningHorizon: Date
    public let safeToSpend: ScenarioSafeToSpend
    public let goalPortfolio: GoalPortfolioHealth
    public let dashboard: FinancialDashboardSnapshot
    public let warnings: [FinancialWarning]

    /// The conservative answer, which is the one the product leads with.
    public var primary: SafeToSpendResult { safeToSpend.primary }
    public var safeToSpendToday: Double { primary.amount }
    public var runway: RunwayAssessment { primary.runway }
    public var goalProjections: [GoalProjection] { primary.goalProjections }
}

public struct GoalDateChange: Sendable, Equatable, Identifiable {
    public let goalID: UUID
    public let name: String
    public let statusBefore: GoalProjectionStatus
    public let statusAfter: GoalProjectionStatus
    public let dateBefore: Date
    public let dateAfter: Date
    public let shiftInDays: Int

    public var id: UUID { goalID }
    public var moved: Bool { shiftInDays != 0 || statusBefore != statusAfter }
}

/// The result of recording a transaction: the new profile, the state before and after,
/// and whether any of it is worth interrupting the user for.
public struct FinancialStateChange: Sendable {
    public let transaction: RecordedTransaction
    public let profile: FinancialProfile
    public let before: FinancialStateSnapshot
    public let after: FinancialStateSnapshot
    public let safeToSpendChange: Double
    /// Negative means the money now runs out sooner.
    public let runwayShiftInDays: Int?
    public let goalDateChanges: [GoalDateChange]
    public let materiality: MaterialityDecision
    public let newWarnings: [FinancialWarning]

    /// The state is always recalculated; this says whether to actually show anything.
    public var isMaterial: Bool { materiality != .ignoreNoImpact }
}

/// Keeps the whole financial state in step with the transactions that arrive.
///
/// Recalculation is unconditional: every movement produces a fresh snapshot. Whether the
/// user *sees* anything is a separate question, answered by `MaterialityPolicy`, so a
/// six-dollar coffee updates the numbers without generating a notification.
public enum FinancialStateEngine {
    public static func snapshot(
        profile: FinancialProfile,
        calendar: Calendar = .current
    ) throws -> FinancialStateSnapshot {
        let horizon = FinancialEngine.defaultPlanningHorizon(profile: profile, calendar: calendar)
        let safeToSpend = try SafeToSpendEngine.evaluateAllScenarios(
            profile: profile,
            calendar: calendar
        )
        let portfolio = try SmartGoalEngine.evaluate(
            profile: profile,
            planningHorizon: horizon,
            calendar: calendar
        )
        let dashboard = try FinancialInsights.dashboard(
            profile: profile,
            through: horizon,
            calendar: calendar
        )

        return FinancialStateSnapshot(
            asOfDate: profile.asOfDate,
            planningHorizon: horizon,
            safeToSpend: safeToSpend,
            goalPortfolio: portfolio,
            dashboard: dashboard,
            warnings: warnings(for: safeToSpend.primary)
        )
    }

    /// Records a transaction and returns the fully recalculated state around it.
    public static func apply(
        _ transaction: RecordedTransaction,
        to profile: FinancialProfile,
        calendar: Calendar = .current
    ) throws -> FinancialStateChange {
        let before = try snapshot(profile: profile, calendar: calendar)
        let updated = profile.applying(transaction)
        let after = try snapshot(profile: updated, calendar: calendar)

        let goalChanges = goalDateChanges(
            from: before.primary.goalProjections,
            to: after.primary.goalProjections,
            calendar: calendar
        )
        let runwayShift = runwayShiftInDays(
            from: before.runway,
            to: after.runway,
            calendar: calendar
        )

        let decision = MaterialityPolicy.transactionImpactDecision(
            amount: transaction.magnitude,
            safeToSpendBefore: before.safeToSpendToday,
            safeToSpendAfter: after.safeToSpendToday,
            riskBefore: before.primary.riskState,
            riskAfter: after.primary.riskState,
            goalScheduleChanged: goalChanges.contains(where: \.moved),
            runwayChanged: (runwayShift ?? 0) != 0
        )

        let existing = Set(before.warnings.map(\.kind))

        return FinancialStateChange(
            transaction: transaction,
            profile: updated,
            before: before,
            after: after,
            safeToSpendChange: after.safeToSpendToday - before.safeToSpendToday,
            runwayShiftInDays: runwayShift,
            goalDateChanges: goalChanges,
            materiality: decision,
            newWarnings: after.warnings.filter { !existing.contains($0.kind) }
        )
    }

    /// Applies a run of transactions, recalculating after each one so intermediate
    /// states are never skipped.
    public static func apply(
        _ transactions: [RecordedTransaction],
        to profile: FinancialProfile,
        calendar: Calendar = .current
    ) throws -> [FinancialStateChange] {
        var current = profile
        var changes: [FinancialStateChange] = []
        for transaction in transactions {
            let change = try apply(transaction, to: current, calendar: calendar)
            current = change.profile
            changes.append(change)
        }
        return changes
    }

    /// Compares two states that were already computed, for callers that watch a new
    /// profile arrive — a bank sync delivering several movements at once — rather than
    /// applying one known transaction. It answers the same question `apply` does: the
    /// numbers have already changed, is the change worth showing?
    public static func materiality(
        from before: SafeToSpendResult,
        to after: SafeToSpendResult,
        netCashMovement: Double,
        calendar: Calendar = .current
    ) -> MaterialityDecision {
        let goalChanges = goalDateChanges(
            from: before.goalProjections,
            to: after.goalProjections,
            calendar: calendar
        )
        let runwayShift = runwayShiftInDays(
            from: before.runway,
            to: after.runway,
            calendar: calendar
        )

        return MaterialityPolicy.transactionImpactDecision(
            amount: abs(netCashMovement),
            safeToSpendBefore: before.amount,
            safeToSpendAfter: after.amount,
            riskBefore: before.riskState,
            riskAfter: after.riskState,
            goalScheduleChanged: goalChanges.contains(where: \.moved),
            runwayChanged: (runwayShift ?? 0) != 0
        )
    }

    // MARK: - Derivations

    public static func goalDateChanges(
        from before: [GoalProjection],
        to after: [GoalProjection],
        calendar: Calendar = .current
    ) -> [GoalDateChange] {
        let previous = Dictionary(
            before.map { ($0.goal.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        return after.compactMap { projection in
            guard let original = previous[projection.goal.id] else { return nil }
            let shift = calendar.dateComponents(
                [.day],
                from: original.projectedDate,
                to: projection.projectedDate
            ).day ?? 0

            return GoalDateChange(
                goalID: projection.goal.id,
                name: projection.goal.name,
                statusBefore: original.status,
                statusAfter: projection.status,
                dateBefore: original.projectedDate,
                dateAfter: projection.projectedDate,
                shiftInDays: shift
            )
        }
    }

    public static func runwayShiftInDays(
        from before: RunwayAssessment,
        to after: RunwayAssessment,
        calendar: Calendar = .current
    ) -> Int? {
        calendar.dateComponents(
            [.day],
            from: before.viableThrough,
            to: after.viableThrough
        ).day
    }

    public static func warnings(for result: SafeToSpendResult) -> [FinancialWarning] {
        var warnings: [FinancialWarning] = []

        if !result.runway.isSatisfied, let depletion = result.runway.projectedDepletionDate {
            warnings.append(
                FinancialWarning(
                    kind: .runwayAtRisk(depletionDate: depletion),
                    constraint: .runwayEnd(date: depletion)
                )
            )
        }

        for projection in result.goalProjections {
            switch projection.status {
            case .adjusted:
                warnings.append(
                    FinancialWarning(
                        kind: .goalDelayed(
                            goalID: projection.goal.id,
                            days: projection.delayInDays
                        ),
                        constraint: .goalDeadline(
                            goalID: projection.goal.id,
                            date: projection.projectedDate
                        )
                    )
                )
            case .unreachable:
                warnings.append(
                    FinancialWarning(
                        kind: .goalUnreachable(goalID: projection.goal.id),
                        constraint: .goalDeadline(
                            goalID: projection.goal.id,
                            date: projection.projectedDate
                        )
                    )
                )
            case .onTrack, .atRisk, .paused, .completed:
                continue
            }
        }

        if result.status == .tight {
            warnings.append(
                FinancialWarning(
                    kind: .belowSafetyBuffer(date: result.limitingDate),
                    constraint: .safetyReserve(date: result.limitingDate)
                )
            )
        }

        for dependency in result.dependsOnUncertainIncome {
            warnings.append(
                FinancialWarning(kind: .dependsOnUncertainIncome(incomeID: dependency.incomeID))
            )
        }

        return warnings
    }
}

public extension FinancialProfile {
    /// Folds a movement into the plan. Money dated today or earlier has already moved,
    /// so it changes the balance; anything later becomes a dated event.
    func applying(_ transaction: RecordedTransaction) -> FinancialProfile {
        var updated = self

        if transaction.date <= asOfDate {
            updated.currentCash += transaction.amount
            return updated
        }

        if transaction.amount < 0 {
            updated.expenseEvents.append(
                ExpenseEvent(
                    id: transaction.id,
                    amount: transaction.magnitude,
                    date: transaction.date,
                    category: transaction.category,
                    essential: transaction.essential,
                    committed: true,
                    reimbursable: false,
                    extraordinary: true
                )
            )
        } else {
            updated.incomeEvents.append(
                IncomeEvent(
                    id: transaction.id,
                    amount: transaction.amount,
                    date: transaction.date,
                    source: transaction.label,
                    type: .oneTime,
                    reliability: transaction.reliability
                )
            )
        }

        return updated
    }
}
