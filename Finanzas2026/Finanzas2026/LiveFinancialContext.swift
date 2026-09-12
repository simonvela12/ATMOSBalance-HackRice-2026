import Foundation
import FinanceCore
import FinancialCore

/// Real financial data, shaped for the forecast views.
///
/// This is the seam between the two packages and the UI: recorded days come from
/// linked-bank transactions (FinanceCore), future days come from the projected
/// cash path (FinancialCore). It holds no view code, which is what lets the UI
/// file change without touching integration logic and vice versa.
struct LiveFinancialContext {
    let profile: FinancialProfile?
    let transactions: [FinanceCore.FinancialTransaction]
    let timeline: [CashFlowPoint]
    let goalPortfolio: GoalPortfolioHealth?

    /// Grouped once at construction: these lookups run for every rendered day.
    private let transactionsByDay: [Date: [FinanceCore.FinancialTransaction]]
    private let timelineByDay: [Date: CashFlowPoint]

    init(
        profile: FinancialProfile?,
        transactions: [FinanceCore.FinancialTransaction],
        timeline: [CashFlowPoint],
        goalPortfolio: GoalPortfolioHealth? = nil
    ) {
        self.profile = profile
        self.transactions = transactions
        self.timeline = timeline
        self.goalPortfolio = goalPortfolio

        let calendar = AppFinancialData.calendar
        self.transactionsByDay = Dictionary(
            grouping: transactions.filter { !$0.isPending && !$0.isTransfer },
            by: { calendar.startOfDay(for: $0.transactionDate) }
        )
        self.timelineByDay = Dictionary(
            timeline.map { (calendar.startOfDay(for: $0.date), $0) },
            uniquingKeysWith: { first, _ in first }
        )
    }

    static let empty = LiveFinancialContext(profile: nil, transactions: [], timeline: [])

    private var calendar: Calendar { AppFinancialData.calendar }

    var hasData: Bool { profile != nil }

    // MARK: Per-day figures

    func recorded(on date: Date) -> (income: Int, expenses: Int, incomeSource: String, expenseSource: String) {
        let day = calendar.startOfDay(for: date)
        let items = transactionsByDay[day] ?? []
        let inflow = items.filter { $0.direction == .inflow }
        let outflow = items.filter { $0.direction == .outflow }
        return (
            income: Int((inflow.reduce(0) { $0 + Double($1.amountMinorUnits) / 100 }).rounded()),
            expenses: Int((outflow.reduce(0) { $0 + Double($1.amountMinorUnits) / 100 }).rounded()),
            incomeSource: Self.label(inflow),
            expenseSource: Self.label(outflow)
        )
    }

    func health(on date: Date) -> FinancialHealthStatus? {
        timelineByDay[calendar.startOfDay(for: date)]?.status
    }

    func projectedCash(on date: Date) -> Double? {
        let day = calendar.startOfDay(for: date)
        return timeline.last { calendar.startOfDay(for: $0.date) <= day }?.projectedCash
    }

    // MARK: Month figures

    /// Balance at the end of a month. Future months read the projected path;
    /// past months are reconstructed backwards from today's cash.
    func balance(asOf cutoff: Date) -> Double? {
        guard let profile else { return nil }
        let day = calendar.startOfDay(for: cutoff)
        let today = calendar.startOfDay(for: profile.asOfDate)

        if day >= today {
            return projectedCash(on: day) ?? profile.currentCash
        }

        let since = transactions
            .filter { !$0.isPending && !$0.isTransfer }
            .filter { calendar.startOfDay(for: $0.transactionDate) > day }
            .reduce(0.0) { $0 + Double($1.signedAmountMinorUnits) / 100 }
        return profile.currentCash - since
    }

    /// Worst projected health across a calendar month. Returns the engine's own
    /// status; mapping that onto a weather symbol is the UI's business, which is
    /// what keeps this type free of any view code.
    func health(year: Int, month: Int) -> FinancialHealthStatus? {
        guard profile != nil else { return nil }
        let statuses = timeline
            .filter {
                calendar.component(.year, from: $0.date) == year &&
                calendar.component(.month, from: $0.date) == month
            }
            .map(\.status)

        guard !statuses.isEmpty else { return nil }
        if statuses.contains(.notSafe) { return .notSafe }
        if statuses.contains(.tight) { return .tight }
        return .safe
    }

    // MARK: Labels

    private static func label(_ items: [FinanceCore.FinancialTransaction]) -> String {
        let sorted = items.sorted { $0.amountMinorUnits > $1.amountMinorUnits }
        guard let first = sorted.first else { return "Nothing recorded" }
        let name = AppFinancialData.label(first)
        return sorted.count > 1 ? "\(name) + \(sorted.count - 1) more" : name
    }

}
