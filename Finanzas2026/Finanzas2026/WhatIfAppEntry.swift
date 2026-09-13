import Foundation
import SwiftUI
import FinanceCore
import FinancialCore

@main
struct Finanzas2026App: App {
    @StateObject private var bankStore = BankAccountStore()

    var body: some Scene {
        WindowGroup {
            WhatIfEnabledRootView()
                .environmentObject(bankStore)
        }
    }
}

/// App-level integration for the advanced What If experience. ProductRootView still
/// owns the existing Forecast + Context product; this wrapper only adds a profile-aware
/// What If launcher and keeps the protected/liquid balance visible.
private struct WhatIfEnabledRootView: View {
    @EnvironmentObject private var bankStore: BankAccountStore
    @State private var showingAdvancedWhatIf = false
    @State private var profileRevision = 0

    private static let money = FloatingPointFormatStyle<Double>.Currency(code: "USD")
        .precision(.fractionLength(0))

    private var profile: FinancialProfile? {
        guard bankStore.isLinked else { return nil }
        return WhatIfProfileBuilder.makeProfile(
            currentCash: bankStore.totalAvailableCash,
            transactions: bankStore.transactions
        )
    }

    var body: some View {
        ProductRootView()
            .safeAreaInset(edge: .top, spacing: 0) {
                if bankStore.isLinked, let profile {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("AVAILABLE TO SPEND")
                                .font(.caption2.weight(.bold))
                                .tracking(1.0)
                                .foregroundStyle(.white.opacity(0.56))
                            Text(Self.money.format(FinancialEngine.liquidCashToday(profile: profile)))
                                .font(.title3.weight(.bold))
                                .monospacedDigit()
                            Text("\(Self.money.format(FinancialEngine.protectedCashToday(profile: profile))) protected")
                                .font(.caption2)
                                .foregroundStyle(.white.opacity(0.50))
                        }

                        Spacer()

                        Button {
                            showingAdvancedWhatIf = true
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "wand.and.stars")
                                    .foregroundStyle(Color(red: 1.00, green: 0.83, blue: 0.35))
                                VStack(alignment: .leading, spacing: 1) {
                                    Text("AI WHAT IF")
                                        .font(.caption.weight(.bold))
                                    Text("Test any scenario")
                                        .font(.caption2)
                                        .foregroundStyle(.white.opacity(0.55))
                                }
                            }
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 9)
                            .background(.white.opacity(0.09), in: RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
                    .background(
                        LinearGradient(
                            colors: [
                                Color(red: 0.025, green: 0.075, blue: 0.13),
                                Color(red: 0.04, green: 0.13, blue: 0.19)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .overlay(alignment: .bottom) {
                        Rectangle().fill(.white.opacity(0.10)).frame(height: 0.5)
                    }
                }
            }
            .sheet(isPresented: $showingAdvancedWhatIf) {
                AdvancedWhatIfSheet(profile: profile)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            }
            .onChange(of: bankStore.accounts) { _, _ in profileRevision += 1 }
            .onChange(of: bankStore.transactions) { _, _ in profileRevision += 1 }
            .id(profileRevision)
    }
}

/// Read-only mirror of ContentView's persisted plan. ContentView remains the only
/// writer. This exists solely so the global What If surface reasons over exactly the
/// user's persisted plan instead of rebuilding a weaker bank-only profile.
private enum WhatIfProfileBuilder {
    static func makeProfile(
        currentCash: Double,
        transactions: [FinanceCore.FinancialTransaction]
    ) -> FinancialProfile {
        let plan = PlanSnapshot.load()
        let asOf = AppFinancialData.day(Date())
        let horizon = AppFinancialData.horizon(from: asOf)

        let base = AppFinancialData.profile(
            currentCash: currentCash,
            transactions: transactions
        )
        let pot = SavingsAccrual.accrued(profile: base)
        let allocation = SavingsAccrual.allocate(
            pot,
            across: plan.goals.map {
                SavingsAccrual.GoalNeed(
                    id: $0.id,
                    remaining: Double(max(0, $0.targetAmount - $0.saved)),
                    deadline: $0.targetDate,
                    priority: $0.mustHappen ? .mandatory : $0.effectivePriority,
                    flexibility: $0.effectiveFlexibility
                )
            }
        )

        let goals = plan.goals.map { goal in
            FinancialCore.Goal(
                id: goal.id,
                name: goal.name,
                targetAmount: Double(goal.targetAmount),
                amountAlreadyPaid: min(
                    Double(goal.targetAmount),
                    Double(goal.saved) + (allocation[goal.id] ?? 0)
                ),
                deadline: goal.targetDate,
                priority: goal.mustHappen ? .mandatory : goal.effectivePriority,
                flexibility: goal.effectiveFlexibility,
                lifecycleState: goal.effectiveLifecycleState
            )
        }

        var plannedIncome: [IncomeEvent] = []
        var plannedExpenses: [ExpenseEvent] = []
        for entry in plan.entries {
            for date in entry.occurrenceDates(through: horizon) {
                let day = AppFinancialData.day(date)
                guard day >= asOf else { continue }
                let key = entry.occurrenceKey(for: date)
                guard !plan.excludedOccurrences.contains(key) else { continue }
                let label = plan.occurrenceNameOverrides[key] ?? entry.name

                switch entry.kind {
                case .income:
                    plannedIncome.append(
                        IncomeEvent(
                            amount: Double(entry.amount),
                            date: day,
                            source: label,
                            type: .oneTime,
                            confidence: 1,
                            planningSource: .planned,
                            planningStatus: .planned
                        )
                    )
                case .payment:
                    plannedExpenses.append(
                        ExpenseEvent(
                            amount: Double(entry.amount),
                            date: day,
                            category: label,
                            essential: false,
                            committed: true,
                            planningSource: .planned,
                            planningStatus: .planned
                        )
                    )
                }
            }
        }

        return AppFinancialData.profile(
            currentCash: currentCash,
            transactions: transactions,
            goals: goals,
            plannedIncome: plannedIncome,
            plannedExpenses: plannedExpenses,
            minimumCashReserve: plan.minimumCashReserve
        )
    }
}

private struct PlanSnapshot: Decodable {
    var goals: [GoalSnapshot]
    var entries: [EntrySnapshot]
    var minimumCashReserve: Double?
    var excludedOccurrences: Set<String>
    var occurrenceNameOverrides: [String: String]

    private enum CodingKeys: String, CodingKey {
        case goals, entries, minimumCashReserve, excludedOccurrences, occurrenceNameOverrides
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        goals = try container.decodeIfPresent([GoalSnapshot].self, forKey: .goals) ?? []
        entries = try container.decodeIfPresent([EntrySnapshot].self, forKey: .entries) ?? []
        minimumCashReserve = try container.decodeIfPresent(Double.self, forKey: .minimumCashReserve)
        excludedOccurrences = try container.decodeIfPresent(Set<String>.self, forKey: .excludedOccurrences) ?? []
        occurrenceNameOverrides = try container.decodeIfPresent([String: String].self, forKey: .occurrenceNameOverrides) ?? [:]
    }

    static func load() -> PlanSnapshot {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let url = support
            .appendingPathComponent("Finanzas2026", isDirectory: true)
            .appendingPathComponent("user-plan.json")
        guard let data = try? Data(contentsOf: url) else { return .empty }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode(PlanSnapshot.self, from: data)) ?? .empty
    }

    static var empty: PlanSnapshot {
        let json = "{\"goals\":[],\"entries\":[],\"excludedOccurrences\":[],\"occurrenceNameOverrides\":{}}".data(using: .utf8)!
        return try! JSONDecoder().decode(PlanSnapshot.self, from: json)
    }
}

private struct GoalSnapshot: Decodable {
    let id: UUID
    let name: String
    let targetAmount: Int
    let saved: Int
    let targetDate: Date
    let isMandatory: Bool?
    let priority: GoalPriority?
    let flexibility: GoalFlexibility?
    let lifecycleState: GoalLifecycleState?

    var mustHappen: Bool { isMandatory ?? false }
    var effectivePriority: GoalPriority { priority ?? (mustHappen ? .high : .medium) }
    var effectiveFlexibility: GoalFlexibility { flexibility ?? (mustHappen ? .low : .medium) }
    var effectiveLifecycleState: GoalLifecycleState { lifecycleState ?? .active }
}

private struct EntrySnapshot: Decodable {
    enum Kind: String, Decodable { case payment, income }
    enum Schedule: String, Decodable { case oneTime, recurring }
    enum Unit: String, Decodable { case day, week, month, year }
    enum Ending: String, Decodable { case never, onDate, afterOccurrences }

    let id: UUID
    let name: String
    let kind: Kind
    let amount: Int
    let startDate: Date
    let schedule: Schedule
    let repeatEvery: Int
    let repeatUnit: Unit
    let repeatEnding: Ending
    let occurrenceCount: Int
    let endDate: Date

    func occurrenceKey(for date: Date) -> String {
        "\(id.uuidString)|\(Int(Calendar.current.startOfDay(for: date).timeIntervalSince1970))"
    }

    func occurrenceDates(through horizon: Date) -> [Date] {
        let calendar = Calendar(identifier: .gregorian)
        let first = calendar.startOfDay(for: startDate)
        guard first <= horizon else { return [] }
        guard schedule == .recurring else { return [first] }

        var dates: [Date] = []
        var current = first
        let maximum = repeatEnding == .afterOccurrences ? occurrenceCount : 120

        while current <= horizon && dates.count < maximum {
            if repeatEnding == .onDate && current > calendar.startOfDay(for: endDate) { break }
            dates.append(current)

            let component: Calendar.Component
            switch repeatUnit {
            case .day: component = .day
            case .week: component = .weekOfYear
            case .month: component = .month
            case .year: component = .year
            }
            guard let next = calendar.date(byAdding: component, value: max(1, repeatEvery), to: current), next > current else { break }
            current = next
        }
        return dates
    }
}
