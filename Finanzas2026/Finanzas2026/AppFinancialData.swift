import Foundation
import FinanceCore
import FinancialCore

/// Shared, UI-free construction of the `FinancialProfile` the engine consumes.
///
/// Marc's forecast UI, Context and the planning engines all build from this same
/// linked-bank profile. Confirmed Context decisions are reapplied here so every
/// product surface reasons over the same user-confirmed facts.
enum AppFinancialData {
    static var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 0)!
        return value
    }

    static func day(_ date: Date) -> Date { calendar.startOfDay(for: date) }

    static func horizon(from date: Date) -> Date {
        calendar.date(byAdding: .day, value: 79, to: date) ?? date
    }

    static func label(_ tx: FinanceCore.FinancialTransaction) -> String {
        let value = (tx.merchantName ?? tx.transactionDescription)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? "Bank transaction" : value
    }

    /// Builds the profile the engine reasons over.
    ///
    /// Past activity and the current balance come from the linked bank. Future
    /// activity, goals and reserve rules come only from user-entered product data
    /// or user-confirmed Context. There are no seeded bills, goals or balances.
    static func profile(
        currentCash: Double?,
        transactions: [FinanceCore.FinancialTransaction],
        goals: [Goal] = [],
        plannedIncome: [IncomeEvent] = [],
        plannedExpenses: [ExpenseEvent] = [],
        minimumCashReserve: Double? = nil,
        cashMustLastUntil: Date? = nil
    ) -> FinancialProfile {
        let asOf = day(Date())
        let usable = transactions.filter {
            !$0.isPending && !$0.isTransfer && $0.transactionDate <= asOf
        }

        let bankIncomes = usable.filter { $0.direction == .inflow }.map { tx in
            IncomeEvent(
                amount: Double(tx.amountMinorUnits) / 100,
                date: day(tx.transactionDate),
                source: label(tx),
                type: tx.sourceType == .refund ? .oneTime : .irregular,
                confidence: 1
            )
        }
        let bankExpenses = usable.filter { $0.direction == .outflow }.map { tx in
            ExpenseEvent(
                amount: Double(tx.amountMinorUnits) / 100,
                date: day(tx.transactionDate),
                category: label(tx),
                essential: false,
                committed: false
            )
        }

        let reserveSteps: [PersonalReserveStep]
        if let minimumCashReserve {
            reserveSteps = [
                PersonalReserveStep(
                    effectiveDate: asOf,
                    minimumCash: minimumCashReserve,
                    note: "Reserve set by you"
                )
            ]
        } else {
            reserveSteps = []
        }

        let baseProfile = FinancialProfile(
            currentCash: currentCash ?? 0,
            asOfDate: asOf,
            personalReserveSteps: reserveSteps,
            institutionalMinimums: [],
            incomeEvents: bankIncomes + plannedIncome,
            expenseEvents: bankExpenses + plannedExpenses,
            goals: goals,
            weeklySpendingHistory: history(usable, asOf),
            spendingPolicy: SpendingPolicy(lookbackWeeks: 6, bufferWeeks: 2, manualMinimumBuffer: 0),
            cashMustLastUntil: cashMustLastUntil
        )

        return ContextPersistence.applyConfirmedDecisions(to: baseProfile)
    }

    private static func history(
        _ transactions: [FinanceCore.FinancialTransaction],
        _ asOf: Date
    ) -> [WeeklySpendingSample] {
        let grouped = Dictionary(grouping: transactions.filter { $0.direction == .outflow }) {
            calendar.dateInterval(of: .weekOfYear, for: $0.transactionDate)?.start ?? day($0.transactionDate)
        }
        let earliest = calendar.date(byAdding: .day, value: -42, to: asOf) ?? .distantPast
        return grouped
            .filter { $0.key >= earliest && $0.key <= asOf }
            .map {
                WeeklySpendingSample(
                    weekStart: $0.key,
                    totalVariableSpending: $0.value.reduce(0) { $0 + Double($1.amountMinorUnits) / 100 }
                )
            }
            .sorted { $0.weekStart < $1.weekStart }
    }
}

/// Savings that accrue by spending less than usual.
///
/// The engine already establishes a typical weekly spending rate from real
/// transaction history. Any completed week that came in under that rate left
/// money behind. Overspending is not charged twice.
enum SavingsAccrual {
    static func accrued(
        profile: FinancialProfile,
        calendar: Calendar = AppFinancialData.calendar
    ) -> Double {
        let typical = FinancialEngine.typicalWeeklySpending(profile: profile, calendar: calendar)
        guard typical > 0 else { return 0 }

        let currentWeekStart = calendar.dateInterval(of: .weekOfYear, for: profile.asOfDate)?.start

        return profile.weeklySpendingHistory.reduce(0) { total, week in
            if let currentWeekStart, week.weekStart >= currentWeekStart { return total }
            return total + max(0, typical - week.totalVariableSpending)
        }
    }

    struct GoalNeed {
        let id: UUID
        let remaining: Double
        let deadline: Date
        let priority: GoalPriority
        let flexibility: GoalFlexibility

        var protectionScore: Double {
            priority.weight * flexibility.protectionWeight
        }
    }

    static func allocate(_ pot: Double, across goals: [GoalNeed]) -> [UUID: Double] {
        var remainingPot = max(0, pot)
        var allocation: [UUID: Double] = [:]

        for goal in goals.sorted(by: {
            if $0.protectionScore != $1.protectionScore {
                return $0.protectionScore > $1.protectionScore
            }
            return $0.deadline < $1.deadline
        }) {
            guard remainingPot > 0 else { break }
            let share = min(remainingPot, max(0, goal.remaining))
            allocation[goal.id] = share
            remainingPot -= share
        }
        return allocation
    }
}
