import Foundation

/// Why the plan cannot allow more spending today. Deterministic and structured on
/// purpose: a language model may turn one of these into a sentence, but it must never
/// be the thing that decides whether a purchase is affordable.
public enum FinancialConstraint: Hashable, Sendable {
    /// A goal has to be payable on its date.
    case goalDeadline(goalID: UUID, date: Date)
    /// Spending more would eat into the buffer the user wants to keep.
    case safetyReserve(date: Date)
    /// A dated bill or committed expense.
    case datedPayment(expenseID: UUID, date: Date)
    /// The money simply runs out on this date.
    case cashFlowShortfall(date: Date)
    /// The balance would not last until the date the user asked it to last.
    case runwayEnd(date: Date)

    public var date: Date {
        switch self {
        case .goalDeadline(_, let date),
             .safetyReserve(let date),
             .datedPayment(_, let date),
             .cashFlowShortfall(let date),
             .runwayEnd(let date):
            return date
        }
    }
}

public enum GoalProjectionStatus: String, Codable, CaseIterable, Sendable {
    /// Fundable on its original date.
    case onTrack
    /// Fundable, but only after moving the date within the flexibility the user allowed.
    case adjusted
    /// Fundable on paper, yet it leaves the plan below the safety buffer.
    case atRisk
    /// Cannot be funded, even after using all the slack the user allowed.
    case unreachable
    case paused
    case completed
}

/// What the plan intends to do about one goal. This replaces "save $47 per week":
/// a goal is a dated requirement, so the answer is a date, not a contribution.
public struct GoalProjection: Sendable, Identifiable {
    public let goal: Goal
    public let status: GoalProjectionStatus
    public let originalDeadline: Date
    /// The date the plan now expects to meet this goal.
    public let projectedDate: Date
    public let amountRequired: Double
    /// How far the date had to move, in days. Zero when the goal is untouched.
    public let delayInDays: Int

    public var id: UUID { goal.id }
    public var wasDelayed: Bool { delayInDays > 0 }

    public init(
        goal: Goal,
        status: GoalProjectionStatus,
        originalDeadline: Date,
        projectedDate: Date,
        amountRequired: Double,
        delayInDays: Int
    ) {
        self.goal = goal
        self.status = status
        self.originalDeadline = originalDeadline
        self.projectedDate = projectedDate
        self.amountRequired = amountRequired
        self.delayInDays = delayInDays
    }
}

/// One goal that had to give way, and what it gave way for.
public struct FinancialConflict: Sendable, Equatable {
    public enum Resolution: Hashable, Sendable {
        case delayed(days: Int)
        case unreachable
    }

    public let goalID: UUID
    public let resolution: Resolution
    /// Goals that kept their original date at this goal's expense, most protected first.
    public let preservedGoalIDs: [UUID]
    public let amount: Double

    public init(goalID: UUID, resolution: Resolution, preservedGoalIDs: [UUID], amount: Double) {
        self.goalID = goalID
        self.resolution = resolution
        self.preservedGoalIDs = preservedGoalIDs
        self.amount = amount
    }
}

/// "My money has to last until X." Evaluated across the whole period, never modelled
/// as a payment on that date.
public struct RunwayAssessment: Sendable, Equatable {
    /// The date the user asked their money to last until, when they set one.
    public let requestedDate: Date?
    /// The first day the plan drops below the hard floor, if it ever does.
    public let projectedDepletionDate: Date?
    /// The last day the plan is still viable within the window that was examined.
    public let viableThrough: Date
    public let isSatisfied: Bool
    /// Extra cash that would be needed to reach `requestedDate`. Zero when satisfied.
    public let shortfall: Double

    public init(
        requestedDate: Date?,
        projectedDepletionDate: Date?,
        viableThrough: Date,
        isSatisfied: Bool,
        shortfall: Double
    ) {
        self.requestedDate = requestedDate
        self.projectedDepletionDate = projectedDepletionDate
        self.viableThrough = viableThrough
        self.isSatisfied = isSatisfied
        self.shortfall = shortfall
    }
}

/// Future money the answer leans on that is not guaranteed to arrive.
public struct IncomeDependency: Sendable, Equatable, Identifiable {
    public let incomeID: UUID
    public let source: String
    public let amount: Double
    public let date: Date
    public let reliability: IncomeReliability

    public var id: UUID { incomeID }

    public init(
        incomeID: UUID,
        source: String,
        amount: Double,
        date: Date,
        reliability: IncomeReliability
    ) {
        self.incomeID = incomeID
        self.source = source
        self.amount = amount
        self.date = date
        self.reliability = reliability
    }
}

/// The single answer to "how much can I spend today?". Everything the product shows
/// about affordability is derived from this, so the number can never disagree with
/// itself between screens.
public struct SafeToSpendResult: Sendable {
    public let scenario: FinancialScenario
    public let asOfDate: Date
    public let planningHorizon: Date

    /// The headline number: the most that can leave the account today while the whole
    /// plan stays viable and the safety buffer survives.
    public let amount: Double
    /// The same figure ignoring the optional buffer: spending beyond this breaks a hard
    /// requirement rather than a preference.
    public let hardCapacity: Double

    public let totalBalance: Double
    /// Minimums the user must keep plus the buffer that stops them landing near zero.
    public let safetyReserve: Double
    /// The part of today's balance the future has already spoken for.
    public let futureCommitments: Double

    public let status: FinancialHealthStatus
    public let limitingDate: Date
    public let limitingConstraint: FinancialConstraint?

    public let goalProjections: [GoalProjection]
    public let conflicts: [FinancialConflict]
    public let runway: RunwayAssessment
    /// Non-empty when this answer would be worse without money that may not arrive.
    public let dependsOnUncertainIncome: [IncomeDependency]

    public var preservedGoals: [GoalProjection] {
        goalProjections.filter { $0.status == .onTrack || $0.status == .atRisk }
    }

    public var delayedGoals: [GoalProjection] {
        goalProjections.filter { $0.status == .adjusted }
    }

    public var unreachableGoals: [GoalProjection] {
        goalProjections.filter { $0.status == .unreachable }
    }

    public var allGoalsOnTrack: Bool {
        goalProjections.allSatisfy {
            $0.status == .onTrack || $0.status == .completed || $0.status == .paused
        }
    }

    /// How the result maps onto the planning risk vocabulary the rest of the app uses.
    public var riskState: PlanningRiskState {
        if totalBalance - amount < 0 { return .negativeCash }
        if !unreachableGoals.isEmpty { return .mandatoryObligationShortfall }
        switch status {
        case .notSafe: return .belowHardFloor
        case .tight: return .belowRecommendedBuffer
        case .safe: return .normal
        }
    }
}

/// The same question answered under three sets of assumptions. Conservative is the
/// number the product leads with; the other two exist so the user can see the spread.
public struct ScenarioSafeToSpend: Sendable {
    public let conservative: SafeToSpendResult
    public let expected: SafeToSpendResult
    public let optimistic: SafeToSpendResult

    public init(
        conservative: SafeToSpendResult,
        expected: SafeToSpendResult,
        optimistic: SafeToSpendResult
    ) {
        self.conservative = conservative
        self.expected = expected
        self.optimistic = optimistic
    }

    /// The recommendation the product shows by default.
    public var primary: SafeToSpendResult { conservative }

    public func result(for scenario: FinancialScenario) -> SafeToSpendResult {
        switch scenario {
        case .conservative: return conservative
        case .expected: return expected
        case .optimistic: return optimistic
        }
    }

    public var all: [SafeToSpendResult] { [conservative, expected, optimistic] }
}

/// The one place affordability is decided.
///
/// A goal is not a savings bucket and no money is ever moved into one. Each goal is a
/// requirement on a date, the engine simulates the cash path that has to satisfy every
/// requirement, and Safe to Spend is whatever is left over today after that simulation
/// still works.
public enum SafeToSpendEngine {
    private static let epsilon = 0.005

    // MARK: - Entry points

    /// - Parameter planningHorizon: a date the plan must stay viable through, for
    ///   callers that already have a window in mind. The engine still extends past it
    ///   when a goal or the user's runway falls later; it never simulates less.
    public static func evaluate(
        profile: FinancialProfile,
        scenario: FinancialScenario = .conservative,
        planningHorizon: Date? = nil,
        calendar: Calendar = .current
    ) throws -> SafeToSpendResult {
        let adjusted = FinancialScenarioEngine.adjustedProfile(
            profile,
            for: scenario,
            calendar: calendar
        )
        return try solve(
            base: adjusted,
            originalProfile: profile,
            scenario: scenario,
            requestedHorizon: planningHorizon,
            calendar: calendar
        )
    }

    /// Conservative, expected and optimistic in one call. The financial logic is not
    /// duplicated: only the assumptions differ.
    public static func evaluateAllScenarios(
        profile: FinancialProfile,
        planningHorizon: Date? = nil,
        calendar: Calendar = .current
    ) throws -> ScenarioSafeToSpend {
        ScenarioSafeToSpend(
            conservative: try evaluate(
                profile: profile,
                scenario: .conservative,
                planningHorizon: planningHorizon,
                calendar: calendar
            ),
            expected: try evaluate(
                profile: profile,
                scenario: .expected,
                planningHorizon: planningHorizon,
                calendar: calendar
            ),
            optimistic: try evaluate(
                profile: profile,
                scenario: .optimistic,
                planningHorizon: planningHorizon,
                calendar: calendar
            )
        )
    }

    // MARK: - Solver

    private struct DayPoint {
        let date: Date
        let hardHeadroom: Double
        let recommendedHeadroom: Double
    }

    private struct Outcome {
        let points: [DayPoint]
        let minimumHard: Double
        let minimumRecommended: Double
        let tightestHardDate: Date
        let tightestRecommendedDate: Date

        var isFeasible: Bool { minimumHard >= -0.005 }
    }

    private static func solve(
        base: FinancialProfile,
        originalProfile: FinancialProfile,
        scenario: FinancialScenario,
        requestedHorizon: Date?,
        calendar: Calendar
    ) throws -> SafeToSpendResult {
        let asOf = base.asOfDate
        let active = base.goals.filter {
            $0.lifecycleState == .active && !$0.isCompleted && $0.remainingAmount > epsilon
        }

        var schedule: [UUID: Date] = [:]
        for goal in active {
            schedule[goal.id] = max(goal.deadline, asOf)
        }

        let horizonCap = calendar.date(
            byAdding: .day,
            value: FinancialEngine.maximumPlanningHorizonInDays,
            to: asOf
        ) ?? asOf

        func horizon(for schedule: [UUID: Date]) -> Date {
            var value = FinancialEngine.defaultPlanningHorizon(profile: base, calendar: calendar)
            if let requestedHorizon {
                value = max(value, requestedHorizon)
            }
            for date in schedule.values {
                value = max(value, date)
            }
            return min(max(value, asOf), horizonCap)
        }

        func run(_ schedule: [UUID: Date]) throws -> Outcome {
            try scan(
                profile: constraintProfile(base: base, active: active, schedule: schedule),
                from: asOf,
                through: horizon(for: schedule),
                calendar: calendar
            )
        }

        var outcome = try run(schedule)

        // Resolve conflicts by moving dates, never by inventing capacity. The least
        // protected goal yields first: low priority, high flexibility, distant deadline.
        var exhausted: Set<UUID> = []
        var delayed: [UUID: Date] = [:]
        // Each pass either settles a goal or marks one exhausted, so one pass per goal
        // is enough. The bound also stops rounding noise from looping forever.
        var passesLeft = active.count + 1

        while !outcome.isFeasible && passesLeft > 0 {
            passesLeft -= 1
            let movable = active
                .filter { goal in
                    guard !exhausted.contains(goal.id) else { return false }
                    guard let current = schedule[goal.id] else { return false }
                    return latestAllowedDate(
                        for: goal,
                        asOf: asOf,
                        cap: horizonCap,
                        calendar: calendar
                    ) > current
                }
                .sorted {
                    protectionRank($0, asOf: asOf, calendar: calendar)
                        < protectionRank($1, asOf: asOf, calendar: calendar)
                }

            guard let candidate = movable.first,
                  let currentDate = schedule[candidate.id] else { break }

            let latest = latestAllowedDate(
                for: candidate,
                asOf: asOf,
                cap: horizonCap,
                calendar: calendar
            )

            var trial = schedule
            trial[candidate.id] = latest
            let pushed = try run(trial)

            guard pushed.isFeasible else {
                // This goal has given all the slack it has and the plan is still short;
                // keep the slack and let the next goal try.
                schedule[candidate.id] = latest
                delayed[candidate.id] = currentDate
                exhausted.insert(candidate.id)
                outcome = pushed
                continue
            }

            // Do not delay further than necessary: find the earliest date that works.
            let settled = try earliestFeasibleDate(
                for: candidate,
                between: currentDate,
                and: latest,
                schedule: schedule,
                run: run,
                calendar: calendar
            )
            schedule[candidate.id] = settled
            if settled > currentDate {
                delayed[candidate.id] = currentDate
            }
            outcome = try run(schedule)
        }

        let planningHorizon = horizon(for: schedule)
        let finalProfile = constraintProfile(base: base, active: active, schedule: schedule)

        let status: FinancialHealthStatus
        if outcome.minimumHard < -epsilon {
            status = .notSafe
        } else if outcome.minimumRecommended < -epsilon {
            status = .tight
        } else {
            status = .safe
        }

        let hardCapacity = max(0, outcome.minimumHard)
        let amount = max(0, outcome.minimumRecommended)
        let limitingDate = status == .notSafe
            ? outcome.tightestHardDate
            : outcome.tightestRecommendedDate

        let projections = goalProjections(
            base: base,
            active: active,
            schedule: schedule,
            delayedFrom: delayed,
            feasible: outcome.isFeasible,
            status: status,
            limitingDate: limitingDate,
            asOf: asOf,
            calendar: calendar
        )

        let conflicts = self.conflicts(
            projections: projections,
            active: active,
            asOf: asOf,
            calendar: calendar
        )

        let runway = runwayAssessment(
            profile: base,
            points: outcome.points,
            planningHorizon: planningHorizon,
            calendar: calendar
        )

        let safetyReserve = FinancialEngine.hardFloor(profile: base, on: asOf)
            + FinancialEngine.safetyBuffer(profile: base, calendar: calendar)

        let constraint = limitingConstraint(
            profile: finalProfile,
            schedule: schedule,
            active: active,
            status: status,
            limitingDate: limitingDate,
            runway: runway,
            calendar: calendar
        )

        let dependencies = try uncertainIncomeDependencies(
            originalProfile: originalProfile,
            scenario: scenario,
            active: active,
            schedule: schedule,
            planningHorizon: planningHorizon,
            achievedAmount: amount,
            calendar: calendar
        )

        return SafeToSpendResult(
            scenario: scenario,
            asOfDate: asOf,
            planningHorizon: planningHorizon,
            amount: amount,
            hardCapacity: hardCapacity,
            totalBalance: base.currentCash,
            safetyReserve: safetyReserve,
            futureCommitments: max(0, base.currentCash - safetyReserve - amount),
            status: status,
            limitingDate: limitingDate,
            limitingConstraint: constraint,
            goalProjections: projections,
            conflicts: conflicts,
            runway: runway,
            dependsOnUncertainIncome: dependencies
        )
    }

    // MARK: - Simulation

    /// Walks the plan day by day. Goals are already dated obligations in `profile`, so
    /// nothing here needs to know what a goal is.
    private static func scan(
        profile: FinancialProfile,
        from startDate: Date,
        through endDate: Date,
        calendar: Calendar
    ) throws -> Outcome {
        var points: [DayPoint] = []
        var minimumHard = Double.greatestFiniteMagnitude
        var minimumRecommended = Double.greatestFiniteMagnitude
        var tightestHard = startDate
        var tightestRecommended = startDate
        var date = startDate

        while date <= endDate {
            let forecast = try FinancialEngine.forecast(
                profile: profile,
                targetDate: date,
                calendar: calendar
            )
            points.append(
                DayPoint(
                    date: date,
                    hardHeadroom: forecast.hardHeadroom,
                    recommendedHeadroom: forecast.recommendedHeadroom
                )
            )

            if forecast.hardHeadroom < minimumHard {
                minimumHard = forecast.hardHeadroom
                tightestHard = date
            }
            if forecast.recommendedHeadroom < minimumRecommended {
                minimumRecommended = forecast.recommendedHeadroom
                tightestRecommended = date
            }

            guard let next = calendar.date(byAdding: .day, value: 1, to: date) else { break }
            date = next
        }

        return Outcome(
            points: points,
            minimumHard: minimumHard == .greatestFiniteMagnitude ? 0 : minimumHard,
            minimumRecommended: minimumRecommended == .greatestFiniteMagnitude ? 0 : minimumRecommended,
            tightestHardDate: tightestHard,
            tightestRecommendedDate: tightestRecommended
        )
    }

    /// Rewrites every preserved goal as a dated obligation on the date the plan intends
    /// to meet it. Nothing is reserved from today's balance: the obligation only bites on
    /// its own date, which is what makes future income able to cover it.
    private static func constraintProfile(
        base: FinancialProfile,
        active: [Goal],
        schedule: [UUID: Date]
    ) -> FinancialProfile {
        var profile = base
        profile.goals = active.compactMap { goal in
            guard let date = schedule[goal.id] else { return nil }
            return Goal(
                id: goal.id,
                name: goal.name,
                targetAmount: goal.remainingAmount,
                amountAlreadyPaid: 0,
                deadline: date,
                priority: .mandatory,
                flexibility: goal.flexibility,
                lifecycleState: .active
            )
        }
        return profile
    }

    // MARK: - Conflict resolution

    /// Higher means "protect this one". Priority dominates, then how rigid the date is,
    /// then how soon it falls.
    private static func protectionRank(
        _ goal: Goal,
        asOf: Date,
        calendar: Calendar
    ) -> Double {
        let days = max(1, calendar.dateComponents([.day], from: asOf, to: goal.deadline).day ?? 1)
        let urgency = min(2, 30 / Double(days))
        return goal.priority.weight * 2
            + goal.flexibility.protectionWeight * 1.5
            + urgency
    }

    private static func latestAllowedDate(
        for goal: Goal,
        asOf: Date,
        cap: Date,
        calendar: Calendar
    ) -> Date {
        let start = max(goal.deadline, asOf)
        guard let allowance = goal.flexibility.maximumDelayInDays else {
            // Open-ended: it may move as far as the plan is simulated.
            return max(start, cap)
        }
        guard allowance > 0,
              let moved = calendar.date(byAdding: .day, value: allowance, to: start) else {
            return start
        }
        return min(max(moved, start), cap)
    }

    /// Binary search for the smallest delay that restores feasibility, so a goal is never
    /// pushed further than the conflict actually requires.
    private static func earliestFeasibleDate(
        for goal: Goal,
        between earliest: Date,
        and latest: Date,
        schedule: [UUID: Date],
        run: ([UUID: Date]) throws -> Outcome,
        calendar: Calendar
    ) throws -> Date {
        var low = 0
        var high = max(0, calendar.dateComponents([.day], from: earliest, to: latest).day ?? 0)
        guard high > 0 else { return latest }

        var best = high
        while low <= high {
            let middle = (low + high) / 2
            guard let candidate = calendar.date(byAdding: .day, value: middle, to: earliest) else {
                break
            }
            var trial = schedule
            trial[goal.id] = candidate
            if try run(trial).isFeasible {
                best = middle
                high = middle - 1
            } else {
                low = middle + 1
            }
        }

        return calendar.date(byAdding: .day, value: best, to: earliest) ?? latest
    }

    private static func goalProjections(
        base: FinancialProfile,
        active: [Goal],
        schedule: [UUID: Date],
        delayedFrom: [UUID: Date],
        feasible: Bool,
        status: FinancialHealthStatus,
        limitingDate: Date,
        asOf: Date,
        calendar: Calendar
    ) -> [GoalProjection] {
        // When the plan still does not close, the goals that cannot be honoured are the
        // least protected ones falling on or before the pinch point. They stay in the
        // plan and are reported as unreachable: abandoning them to free up cash would be
        // inventing spending capacity the user does not have.
        var unreachable: Set<UUID> = []
        if !feasible {
            let candidates = active
                .filter { (schedule[$0.id] ?? $0.deadline) <= limitingDate }
                .sorted {
                    protectionRank($0, asOf: asOf, calendar: calendar)
                        < protectionRank($1, asOf: asOf, calendar: calendar)
                }
            for goal in candidates {
                unreachable.insert(goal.id)
                break
            }
        }

        return base.goals.map { goal in
            let original = max(goal.deadline, asOf)

            if goal.isCompleted {
                return GoalProjection(
                    goal: goal,
                    status: .completed,
                    originalDeadline: original,
                    projectedDate: original,
                    amountRequired: 0,
                    delayInDays: 0
                )
            }
            if goal.lifecycleState == .paused {
                return GoalProjection(
                    goal: goal,
                    status: .paused,
                    originalDeadline: original,
                    projectedDate: original,
                    amountRequired: goal.remainingAmount,
                    delayInDays: 0
                )
            }

            let projected = schedule[goal.id] ?? original
            let delay = max(0, calendar.dateComponents([.day], from: original, to: projected).day ?? 0)

            let projectionStatus: GoalProjectionStatus
            if unreachable.contains(goal.id) {
                projectionStatus = .unreachable
            } else if delay > 0 {
                projectionStatus = .adjusted
            } else if status == .tight && projected <= limitingDate {
                projectionStatus = .atRisk
            } else {
                projectionStatus = .onTrack
            }

            return GoalProjection(
                goal: goal,
                status: projectionStatus,
                originalDeadline: original,
                projectedDate: projected,
                amountRequired: goal.remainingAmount,
                delayInDays: delay
            )
        }
    }

    private static func conflicts(
        projections: [GoalProjection],
        active: [Goal],
        asOf: Date,
        calendar: Calendar
    ) -> [FinancialConflict] {
        let affected = projections.filter { $0.status == .adjusted || $0.status == .unreachable }
        guard !affected.isEmpty else { return [] }

        return affected.map { projection in
            let rank = protectionRank(projection.goal, asOf: asOf, calendar: calendar)
            let preserved = active
                .filter { candidate in
                    candidate.id != projection.goal.id &&
                    protectionRank(candidate, asOf: asOf, calendar: calendar) > rank
                }
                .sorted {
                    protectionRank($0, asOf: asOf, calendar: calendar)
                        > protectionRank($1, asOf: asOf, calendar: calendar)
                }
                .map(\.id)

            return FinancialConflict(
                goalID: projection.goal.id,
                resolution: projection.status == .unreachable
                    ? .unreachable
                    : .delayed(days: projection.delayInDays),
                preservedGoalIDs: preserved,
                amount: projection.amountRequired
            )
        }
    }

    // MARK: - Runway

    private static func runwayAssessment(
        profile: FinancialProfile,
        points: [DayPoint],
        planningHorizon: Date,
        calendar: Calendar
    ) -> RunwayAssessment {
        let depletion = points.first { $0.hardHeadroom < -epsilon }?.date
        let viableThrough = depletion.flatMap {
            calendar.date(byAdding: .day, value: -1, to: $0)
        } ?? planningHorizon

        guard let requested = profile.cashMustLastUntil else {
            return RunwayAssessment(
                requestedDate: nil,
                projectedDepletionDate: depletion,
                viableThrough: max(viableThrough, profile.asOfDate),
                isSatisfied: depletion == nil,
                shortfall: 0
            )
        }

        let satisfied = depletion.map { $0 > requested } ?? true
        let worstWithinWindow = points
            .filter { $0.date <= requested }
            .map(\.hardHeadroom)
            .min() ?? 0

        return RunwayAssessment(
            requestedDate: requested,
            projectedDepletionDate: depletion,
            viableThrough: max(viableThrough, profile.asOfDate),
            isSatisfied: satisfied,
            shortfall: satisfied ? 0 : max(0, -worstWithinWindow)
        )
    }

    // MARK: - Explanation

    private static func limitingConstraint(
        profile: FinancialProfile,
        schedule: [UUID: Date],
        active: [Goal],
        status: FinancialHealthStatus,
        limitingDate: Date,
        runway: RunwayAssessment,
        calendar: Calendar
    ) -> FinancialConstraint? {
        // Something binds the number even when the plan is comfortable: the answer is
        // lower than today's balance for a reason, and the user deserves to know which.
        // Only a plan where nothing in the future bites at all is unconstrained.
        // A goal due on or before the pinch point is the most specific explanation there
        // is, so it wins. The largest one is the one worth naming.
        let dueGoals = active
            .filter { (schedule[$0.id] ?? $0.deadline) <= limitingDate }
            .sorted { $0.remainingAmount > $1.remainingAmount }
        if let goal = dueGoals.first {
            return .goalDeadline(goalID: goal.id, date: schedule[goal.id] ?? goal.deadline)
        }

        if status == .tight {
            return .safetyReserve(date: limitingDate)
        }

        if let requested = runway.requestedDate, !runway.isSatisfied, limitingDate <= requested {
            return .runwayEnd(date: runway.projectedDepletionDate ?? limitingDate)
        }

        let day = calendar.startOfDay(for: limitingDate)
        let dueExpense = profile.expenseEvents
            .filter { $0.committed && calendar.startOfDay(for: $0.date) == day }
            .max { $0.amount < $1.amount }
        if let dueExpense {
            return .datedPayment(expenseID: dueExpense.id, date: dueExpense.date)
        }

        if status == .safe && calendar.isDate(limitingDate, inSameDayAs: profile.asOfDate) {
            return nil
        }

        return .cashFlowShortfall(date: limitingDate)
    }

    /// Re-runs the same plan counting only money that is certain to arrive. When the
    /// answer gets worse, the difference is exactly what the user is betting on.
    private static func uncertainIncomeDependencies(
        originalProfile: FinancialProfile,
        scenario: FinancialScenario,
        active: [Goal],
        schedule: [UUID: Date],
        planningHorizon: Date,
        achievedAmount: Double,
        calendar: Calendar
    ) throws -> [IncomeDependency] {
        let risky = originalProfile.incomeEvents.filter {
            !$0.reliability.isGuaranteed &&
            $0.date > originalProfile.asOfDate &&
            $0.date <= planningHorizon &&
            $0.amount > epsilon
        }
        guard !risky.isEmpty else { return [] }

        var reliableOnly = originalProfile
        reliableOnly.incomeEvents = originalProfile.incomeEvents.filter(\.reliability.isGuaranteed)

        let adjusted = FinancialScenarioEngine.adjustedProfile(
            reliableOnly,
            for: scenario,
            calendar: calendar
        )
        let withoutRisky = try scan(
            profile: constraintProfile(base: adjusted, active: active, schedule: schedule),
            from: adjusted.asOfDate,
            through: planningHorizon,
            calendar: calendar
        )

        guard max(0, withoutRisky.minimumRecommended) < achievedAmount - epsilon else {
            return []
        }

        return risky.map {
            IncomeDependency(
                incomeID: $0.id,
                source: $0.source,
                amount: $0.amount,
                date: $0.date,
                reliability: $0.reliability
            )
        }
    }
}
