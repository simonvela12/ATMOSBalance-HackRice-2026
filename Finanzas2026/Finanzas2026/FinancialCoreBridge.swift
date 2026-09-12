import Foundation
import FinancialCore

struct AppFinancialModel {
    var optionalExpenseIsCommitted = false
    var goalIsMandatory = false

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    var asOfDate: Date { date(2026, 9, 12) }

    var profile: FinancialProfile {
        FinancialProfileAdapter.makeProfile(
            currentCash: 8_000,
            asOfDate: asOfDate,
            personalReserve: 7_000,
            incomes: [
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
            expenses: [
                QualitativeExpenseInput(
                    amount: 500,
                    date: date(2026, 11, 15),
                    category: "Essential expenses",
                    need: .essential,
                    committed: true,
                    reimbursable: false,
                    extraordinary: false
                ),
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
            weeklySpendingHistory: [],
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
