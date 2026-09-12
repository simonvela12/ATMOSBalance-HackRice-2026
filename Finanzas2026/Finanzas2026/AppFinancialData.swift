import Foundation
import FinanceCore
import FinancialCore

/// Shared, UI-free construction of the `FinancialProfile` the engine consumes.
///
/// This was previously private to `ProductRootView`. It lives here so Marc's
/// forecast UI and the product screens build the same profile from the same
/// linked-bank data rather than each inventing their own.
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

    static let tuitionID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
    static let miamiID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!

    static func label(_ tx: FinanceCore.FinancialTransaction) -> String {
        let value = (tx.merchantName ?? tx.transactionDescription)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? "Bank transaction" : value
    }

    static func profile(
        currentCash: Double?,
        transactions: [FinanceCore.FinancialTransaction]
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

        let scheduled = [
            ExpenseEvent(amount: 900, date: calendar.date(byAdding: .day, value: 3, to: asOf) ?? asOf,
                         category: "Rent", essential: true, committed: true),
            ExpenseEvent(amount: 80, date: calendar.date(byAdding: .day, value: 6, to: asOf) ?? asOf,
                         category: "Phone", essential: true, committed: true),
            ExpenseEvent(amount: 25, date: calendar.date(byAdding: .day, value: 18, to: asOf) ?? asOf,
                         category: "Streaming subscription", essential: false, committed: true)
        ]

        return FinancialProfile(
            currentCash: currentCash ?? 0,
            asOfDate: asOf,
            personalReserveSteps: [
                PersonalReserveStep(effectiveDate: asOf, minimumCash: 500,
                                    note: "Confirmed personal reserve")
            ],
            institutionalMinimums: [],
            incomeEvents: bankIncomes,
            expenseEvents: bankExpenses + scheduled,
            goals: [
                Goal(id: tuitionID, name: "Tuition installment", targetAmount: 350,
                     deadline: calendar.date(byAdding: .day, value: 16, to: asOf) ?? asOf,
                     priority: .mandatory),
                Goal(id: miamiID, name: "Miami", targetAmount: 900,
                     deadline: calendar.date(byAdding: .day, value: 38, to: asOf) ?? asOf,
                     priority: .flexible)
            ],
            weeklySpendingHistory: history(usable, asOf),
            spendingPolicy: SpendingPolicy(lookbackWeeks: 6, bufferWeeks: 2, manualMinimumBuffer: 200)
        )
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
