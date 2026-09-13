import Foundation

public enum FinancialDiagnosticSeverity: String, Codable, Sendable {
    case info = "INFO"
    case warning = "WARNING"
    case error = "ERROR"
}

public enum FinancialDiagnosticCode: String, Codable, Sendable {
    case longPlanningHorizon
    case noRecentSpendingHistory
    case sparseRecentSpendingHistory
    case irregularIncomeConfidenceClamped
    case negativeIncomeAmount
    case negativeExpenseAmount
    case invalidGoalAmount
    case goalPaidExceedsTarget
    case negativeReserve
    case duplicateReserveEffectiveDate
    case negativeInstitutionalMinimum
    case invalidInstitutionalMinimumRange
    case negativeWeeklySpending
    case invalidSpendingPolicy
    case overdueMandatoryGoal
    case overdueFlexibleGoal
}

public struct FinancialDiagnostic: Sendable {
    public let severity: FinancialDiagnosticSeverity
    public let code: FinancialDiagnosticCode
    public let message: String

    public init(
        severity: FinancialDiagnosticSeverity,
        code: FinancialDiagnosticCode,
        message: String
    ) {
        self.severity = severity
        self.code = code
        self.message = message
    }
}

public struct FinancialProfileDiagnosticReport: Sendable {
    public let planningHorizon: Date
    public let horizonDays: Int
    public let operationalHorizonDays: Int
    public let recentSpendingSampleCount: Int
    public let issues: [FinancialDiagnostic]

    public var hasErrors: Bool {
        issues.contains { $0.severity == .error }
    }

    public var hasWarnings: Bool {
        issues.contains { $0.severity == .warning }
    }

    /// `false` means the upstream normalization layer supplied malformed values that
    /// should be fixed before presenting an affordability decision to the user.
    public var isReadyForForecast: Bool {
        !hasErrors
    }
}

/// Diagnostics for the boundary between the app's qualitative/normalization layer and
/// the deterministic engine. These checks do not silently change the user's data.
/// They expose assumptions and malformed inputs so the UI or debug tooling can react.
public enum FinancialProfileDiagnostics {
    public static func report(
        profile: FinancialProfile,
        planningHorizon: Date,
        operationalHorizonDays: Int = 180,
        minimumRecentSpendingSamples: Int = 3,
        calendar: Calendar = .current
    ) -> FinancialProfileDiagnosticReport {
        let safeOperationalDays = max(1, operationalHorizonDays)
        let safeMinimumSamples = max(1, minimumRecentSpendingSamples)
        let horizonDays = max(
            0,
            calendar.dateComponents(
                [.day],
                from: profile.asOfDate,
                to: max(profile.asOfDate, planningHorizon)
            ).day ?? 0
        )

        var issues: [FinancialDiagnostic] = []

        if planningHorizon > profile.asOfDate && horizonDays > safeOperationalDays {
            issues.append(
                FinancialDiagnostic(
                    severity: .warning,
                    code: .longPlanningHorizon,
                    message: "Planning horizon is \(horizonDays) days. Treat recent spending history as a rolling forecast, not a precise long-range prediction."
                )
            )
        }

        let recentSpending = FinancialEngine.eligibleWeeklySpendingValues(
            profile: profile,
            calendar: calendar
        )

        if profile.spendingPolicy.lookbackWeeks > 0 && recentSpending.isEmpty {
            issues.append(
                FinancialDiagnostic(
                    severity: .warning,
                    code: .noRecentSpendingHistory,
                    message: "No eligible recent weekly spending samples are available, so projected variable spending is currently zero."
                )
            )
        } else if !recentSpending.isEmpty && recentSpending.count < safeMinimumSamples {
            issues.append(
                FinancialDiagnostic(
                    severity: .warning,
                    code: .sparseRecentSpendingHistory,
                    message: "Only \(recentSpending.count) recent spending sample(s) are available; the spending baseline may move materially as more history arrives."
                )
            )
        }

        for income in profile.incomeEvents {
            if income.amount < 0 {
                issues.append(
                    FinancialDiagnostic(
                        severity: .error,
                        code: .negativeIncomeAmount,
                        message: "Income event '\(income.source)' has a negative amount. Represent cash outflows as expenses instead."
                    )
                )
            }

            if income.type == .irregular && (income.confidence < 0 || income.confidence > 1) {
                issues.append(
                    FinancialDiagnostic(
                        severity: .warning,
                        code: .irregularIncomeConfidenceClamped,
                        message: "Irregular income '\(income.source)' has confidence outside 0...1. The engine clamps it, but the upstream value should be normalized."
                    )
                )
            }
        }

        for expense in profile.expenseEvents where expense.amount < 0 {
            issues.append(
                FinancialDiagnostic(
                    severity: .error,
                    code: .negativeExpenseAmount,
                    message: "Expense category '\(expense.category)' has a negative amount. Represent cash inflows as income instead."
                )
            )
        }

        for goal in profile.goals {
            if goal.targetAmount < 0 || goal.amountAlreadyPaid < 0 {
                issues.append(
                    FinancialDiagnostic(
                        severity: .error,
                        code: .invalidGoalAmount,
                        message: "Goal '\(goal.name)' contains a negative target or paid amount."
                    )
                )
            }

            if goal.amountAlreadyPaid > goal.targetAmount && goal.targetAmount >= 0 {
                issues.append(
                    FinancialDiagnostic(
                        severity: .warning,
                        code: .goalPaidExceedsTarget,
                        message: "Goal '\(goal.name)' reports more already paid than its target."
                    )
                )
            }

            if goal.remainingAmount > 0 && goal.deadline <= profile.asOfDate {
                let code: FinancialDiagnosticCode = goal.priority == .mandatory
                    ? .overdueMandatoryGoal
                    : .overdueFlexibleGoal
                let severity: FinancialDiagnosticSeverity = goal.priority == .mandatory
                    ? .warning
                    : .info
                issues.append(
                    FinancialDiagnostic(
                        severity: severity,
                        code: code,
                        message: "Goal '\(goal.name)' is overdue with \(goal.remainingAmount) remaining; the engine treats it as an immediate obligation/decision according to its priority."
                    )
                )
            }
        }

        for reserve in profile.personalReserveSteps where reserve.minimumCash < 0 {
            issues.append(
                FinancialDiagnostic(
                    severity: .error,
                    code: .negativeReserve,
                    message: "A personal reserve step contains a negative minimum cash value."
                )
            )
        }

        let groupedReserveDates = Dictionary(grouping: profile.personalReserveSteps, by: \.effectiveDate)
        if groupedReserveDates.values.contains(where: { $0.count > 1 }) {
            issues.append(
                FinancialDiagnostic(
                    severity: .warning,
                    code: .duplicateReserveEffectiveDate,
                    message: "Multiple personal reserve steps share the same effective date; normalize them to one value to avoid ambiguous intent."
                )
            )
        }

        for minimum in profile.institutionalMinimums {
            if minimum.minimumBalance < 0 {
                issues.append(
                    FinancialDiagnostic(
                        severity: .error,
                        code: .negativeInstitutionalMinimum,
                        message: "Institutional minimum '\(minimum.name)' has a negative minimum balance."
                    )
                )
            }

            if let endDate = minimum.endDate, endDate < minimum.startDate {
                issues.append(
                    FinancialDiagnostic(
                        severity: .error,
                        code: .invalidInstitutionalMinimumRange,
                        message: "Institutional minimum '\(minimum.name)' ends before it starts."
                    )
                )
            }
        }

        if profile.weeklySpendingHistory.contains(where: { $0.totalVariableSpending < 0 }) {
            issues.append(
                FinancialDiagnostic(
                    severity: .error,
                    code: .negativeWeeklySpending,
                    message: "Weekly spending history contains a negative value. Refunds/reimbursements should be normalized separately rather than stored as negative spending."
                )
            )
        }

        if profile.spendingPolicy.lookbackWeeks < 0 ||
            profile.spendingPolicy.bufferWeeks < 0 ||
            profile.spendingPolicy.manualMinimumBuffer < 0 {
            issues.append(
                FinancialDiagnostic(
                    severity: .error,
                    code: .invalidSpendingPolicy,
                    message: "Spending-policy lookback, buffer weeks, and manual buffer must be non-negative."
                )
            )
        }

        return FinancialProfileDiagnosticReport(
            planningHorizon: planningHorizon,
            horizonDays: horizonDays,
            operationalHorizonDays: safeOperationalDays,
            recentSpendingSampleCount: recentSpending.count,
            issues: issues
        )
    }
}

