import Foundation
import FinanceCore
import FinancialCore

struct AppFinancialModel {
    var optionalExpenseIsCommitted = false
    var goalIsMandatory = false
    var bankAccounts: [FinanceCore.FinancialAccount] = []
    var bankTransactions: [FinanceCore.FinancialTransaction] = []

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    var asOfDate: Date { date(2026, 9, 12) }

    var usesLinkedAccount: Bool { !bankAccounts.isEmpty }

    func usingBankData(
        accounts: [FinanceCore.FinancialAccount],
        transactions: [FinanceCore.FinancialTransaction]
    ) -> AppFinancialModel {
        var copy = self
        copy.bankAccounts = accounts
        copy.bankTransactions = transactions
        return copy
    }

    var profile: FinancialProfile {
        FinancialProfileAdapter.makeProfile(
            currentCash: linkedCashBalance,
            asOfDate: asOfDate,
            personalReserve: 7_000,
            incomes: usesLinkedAccount ? inferredIncomeEvents : [
                QualitativeIncomeInput(
                    amount: 1_000,
                    date: date(2026, 11, 1),
                    source: "Campus job",
                    kind: .recurring,
                    confidence: 1
                ),
                QualitativeIncomeInput(
                    amount: 300,
                    date: date(2026, 10, 1),
                    source: "Tutoring",
                    kind: .irregular,
                    confidence: 0.7
                )
            ],
            expenses: (usesLinkedAccount ? inferredExpenseEvents : [
                QualitativeExpenseInput(
                    amount: 500,
                    date: date(2026, 11, 15),
                    category: "Essential expenses",
                    need: .essential,
                    committed: true,
                    reimbursable: false,
                    extraordinary: false
                )
            ]) + [
                QualitativeExpenseInput(
                    amount: 300,
                    date: date(2026, 9, 20),
                    category: "Optional purchase",
                    need: optionalExpenseIsCommitted ? .essential : .optional,
                    committed: optionalExpenseIsCommitted,
                    reimbursable: false,
                    extraordinary: false
                )
            ],
            goals: [
                QualitativeGoalInput(
                    name: "Trip goal",
                    targetAmount: 300,
                    amountAlreadyPaid: 0,
                    deadline: date(2026, 10, 15),
                    priority: goalIsMandatory ? .mandatory : .flexible
                )
            ],
            weeklySpendingHistory: linkedWeeklySpendingHistory,
            spendingPolicy: SpendingPolicy(
                lookbackWeeks: 6,
                bufferWeeks: 0,
                manualMinimumBuffer: 250
            )
        )
    }

    func snapshot(through requestedHorizon: Date) throws -> AppFinancialSnapshot {
        let horizon = max(requestedHorizon, asOfDate)
        let forecast = try FinancialEngine.forecast(
            profile: profile,
            targetDate: horizon,
            calendar: calendar
        )
        let dashboard = try FinancialInsights.dashboard(
            profile: profile,
            through: horizon,
            calendar: calendar
        )

        return AppFinancialSnapshot(
            projectedCash: forecast.projectedCash,
            safeToSpendNow: dashboard.safeToSpendNow,
            currentStatus: dashboard.currentStatus,
            horizonStatus: dashboard.horizonStatus,
            expectedIncome: forecast.expectedIncome,
            committedExpenses: forecast.committedExpenses,
            mandatoryGoals: forecast.mandatoryGoalPayments,
            recommendedWeeklySpendingLimit: dashboard.recommendedWeeklySpendingLimit,
            tightestDate: dashboard.tightestDate
        )
    }

    func assessPurchase(amount: Double, through requestedHorizon: Date) throws -> AppPurchaseResult {
        let horizon = max(requestedHorizon, asOfDate)
        let result = try FinancialInsights.assessAndExplainPurchase(
            profile: profile,
            amount: amount,
            purchaseDate: asOfDate,
            planningHorizon: horizon,
            calendar: calendar
        )

        return AppPurchaseResult(
            status: result.assessment.status,
            projectedCashAfterPurchase: result.explanation.projectedCashAfterPurchase,
            hardHeadroomAfterPurchase: result.assessment.minimumHardHeadroomAfterPurchase,
            recommendedHeadroomAfterPurchase: result.assessment.minimumRecommendedHeadroomAfterPurchase,
            reason: result.explanation.reason,
            limitingDate: result.explanation.limitingDate
        )
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    private var linkedCashBalance: Double {
        guard usesLinkedAccount else { return 8_000 }
        let minorUnits = bankAccounts
            .filter { $0.accountType != .creditCard }
            .reduce(Int64(0)) { $0 + $1.balanceMinorUnits }
        return Double(minorUnits) / 100
    }

    private var inferredIncomeEvents: [QualitativeIncomeInput] {
        recurringCandidates(direction: .inflow).flatMap { candidate in
            nextMonthlyDates(after: candidate.latestDate, count: 4).map { projectedDate in
                QualitativeIncomeInput(
                    amount: candidate.averageAmount,
                    date: projectedDate,
                    source: candidate.name,
                    kind: .recurring,
                    confidence: 1
                )
            }
        }
    }

    private var inferredExpenseEvents: [QualitativeExpenseInput] {
        recurringCandidates(direction: .outflow).flatMap { candidate in
            nextMonthlyDates(after: candidate.latestDate, count: 4).map { projectedDate in
                let essential = isEssential(category: candidate.category, description: candidate.name)
                return QualitativeExpenseInput(
                    amount: candidate.averageAmount,
                    date: projectedDate,
                    category: candidate.category ?? candidate.name,
                    need: essential ? .essential : .important,
                    committed: true,
                    reimbursable: false,
                    extraordinary: false
                )
            }
        }
    }

    private var linkedWeeklySpendingHistory: [WeeklySpendingSample] {
        guard usesLinkedAccount else { return [] }
        let startOfAsOfWeek = calendar.dateInterval(of: .weekOfYear, for: asOfDate)?.start ?? asOfDate
        let grouped = Dictionary(grouping: bankTransactions.filter {
            $0.direction == .outflow && !$0.isTransfer && !$0.isPending && $0.transactionDate <= asOfDate
        }) { transaction in
            calendar.dateInterval(of: .weekOfYear, for: transaction.transactionDate)?.start ?? transaction.transactionDate
        }

        return grouped
            .filter { week, _ in
                week >= (calendar.date(byAdding: .day, value: -42, to: startOfAsOfWeek) ?? .distantPast)
            }
            .map { week, transactions in
                WeeklySpendingSample(
                    weekStart: week,
                    totalVariableSpending: transactions.reduce(0) {
                        $0 + Double($1.amountMinorUnits) / 100
                    }
                )
            }
            .sorted { $0.weekStart < $1.weekStart }
    }

    private struct RecurringCandidate {
        let name: String
        let category: String?
        let averageAmount: Double
        let latestDate: Date
    }

    private func recurringCandidates(direction: TransactionDirection) -> [RecurringCandidate] {
        let eligible = bankTransactions.filter {
            $0.direction == direction &&
            !$0.isTransfer &&
            !$0.isPending &&
            (direction != .inflow || $0.sourceType != .refund) &&
            $0.transactionDate <= asOfDate
        }
        let grouped = Dictionary(grouping: eligible) { transaction in
            (transaction.merchantName ?? transaction.transactionDescription)
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
        }

        return grouped.compactMap { _, transactions in
            let sorted = transactions.sorted { $0.transactionDate < $1.transactionDate }
            guard sorted.count >= 2,
                  let latest = sorted.last,
                  let previous = sorted.dropLast().last else { return nil }
            let gap = calendar.dateComponents([.day], from: previous.transactionDate, to: latest.transactionDate).day ?? 0
            guard (20...40).contains(gap) else { return nil }
            let average = sorted.reduce(0.0) { $0 + Double($1.amountMinorUnits) / 100 } / Double(sorted.count)
            return RecurringCandidate(
                name: latest.merchantName ?? latest.transactionDescription,
                category: latest.category,
                averageAmount: average,
                latestDate: latest.transactionDate
            )
        }
    }

    private func nextMonthlyDates(after lastDate: Date, count: Int) -> [Date] {
        var next = lastDate
        while next <= asOfDate {
            next = calendar.date(byAdding: .month, value: 1, to: next) ?? .distantFuture
        }
        return (0..<count).compactMap { calendar.date(byAdding: .month, value: $0, to: next) }
    }

    private func isEssential(category: String?, description: String) -> Bool {
        let text = "\(category ?? "") \(description)".lowercased()
        return ["rent", "housing", "utility", "utilities", "health", "medical", "education", "tuition"]
            .contains { text.contains($0) }
    }
}

struct AppFinancialSnapshot {
    let projectedCash: Double
    let safeToSpendNow: Double
    let currentStatus: FinancialHealthStatus
    let horizonStatus: FinancialHealthStatus
    let expectedIncome: Double
    let committedExpenses: Double
    let mandatoryGoals: Double
    let recommendedWeeklySpendingLimit: Double
    let tightestDate: Date
}

struct AppPurchaseResult {
    let status: PurchaseStatus
    let projectedCashAfterPurchase: Double
    let hardHeadroomAfterPurchase: Double
    let recommendedHeadroomAfterPurchase: Double
    let reason: PurchaseDecisionReason
    let limitingDate: Date
}

struct QualitativeIncomeInput {
    enum Kind { case recurring, irregular, oneTime }
    let amount: Double
    let date: Date
    let source: String
    let kind: Kind
    let confidence: Double
}

struct QualitativeExpenseInput {
    enum Need { case essential, important, optional }
    let amount: Double
    let date: Date
    let category: String
    let need: Need
    let committed: Bool
    let reimbursable: Bool
    let extraordinary: Bool
}

struct QualitativeGoalInput {
    enum Priority { case mandatory, flexible }
    let name: String
    let targetAmount: Double
    let amountAlreadyPaid: Double
    let deadline: Date
    let priority: Priority
}

enum FinancialProfileAdapter {
    static func makeProfile(
        currentCash: Double,
        asOfDate: Date,
        personalReserve: Double,
        incomes: [QualitativeIncomeInput],
        expenses: [QualitativeExpenseInput],
        goals: [QualitativeGoalInput],
        weeklySpendingHistory: [WeeklySpendingSample],
        spendingPolicy: SpendingPolicy
    ) -> FinancialProfile {
        FinancialProfile(
            currentCash: currentCash,
            asOfDate: asOfDate,
            personalReserveSteps: [
                PersonalReserveStep(
                    effectiveDate: asOfDate,
                    minimumCash: personalReserve,
                    note: "User-confirmed runway"
                )
            ],
            incomeEvents: incomes.map {
                FinancialCore.IncomeEvent(
                    amount: $0.amount,
                    date: $0.date,
                    source: $0.source,
                    type: $0.kind.financialCoreType,
                    confidence: $0.confidence
                )
            },
            expenseEvents: expenses.map {
                FinancialCore.ExpenseEvent(
                    amount: $0.amount,
                    date: $0.date,
                    category: $0.category,
                    essential: $0.need == .essential,
                    committed: $0.committed || $0.need == .essential,
                    reimbursable: $0.reimbursable,
                    extraordinary: $0.extraordinary
                )
            },
            goals: goals.map {
                Goal(
                    name: $0.name,
                    targetAmount: $0.targetAmount,
                    amountAlreadyPaid: $0.amountAlreadyPaid,
                    deadline: $0.deadline,
                    priority: $0.priority == .mandatory ? .mandatory : .flexible
                )
            },
            weeklySpendingHistory: weeklySpendingHistory,
            spendingPolicy: spendingPolicy
        )
    }
}

private extension QualitativeIncomeInput.Kind {
    var financialCoreType: FinancialCore.IncomeType {
        switch self {
        case .recurring: .recurring
        case .irregular: .irregular
        case .oneTime: .oneTime
        }
    }
}

// App-only compatibility keeps the legacy Context cadence explicit without
// reintroducing an ambiguous overload inside FinancialCore itself.
extension RecurrenceRule {
    init(cadence: RecurrenceCadence, firstOccurrence: Date, endDate: Date? = nil, isPaused: Bool = false) {
        self.init(
            cadence: PlanningRecurrenceCadence(cadence),
            firstOccurrence: firstOccurrence,
            endDate: endDate,
            isPaused: isPaused
        )
    }
}
