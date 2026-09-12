import SwiftUI
import FinanceCore
import FinancialCore

struct ProductRootView: View {
    @EnvironmentObject private var bankStore: BankAccountStore
    @State private var profile = V2Data.profile(currentCash: nil, transactions: [])
    @State private var hasConfirmedContext = false

    var body: some View {
        TabView {
            V2Home(profile: profile, linked: bankStore.isLinked, phase: bankStore.phase)
                .tabItem { Label("Home", systemImage: "house.fill") }
            V2Calendar(profile: profile)
                .tabItem { Label("Calendar", systemImage: "calendar") }
            V2Plans(profile: profile)
                .tabItem { Label("Plans", systemImage: "target") }
            V2WhatIf(profile: profile)
                .tabItem { Label("What If", systemImage: "slider.horizontal.3") }
            V2Context(
                profile: $profile,
                items: V2Data.contextItems(transactions: bankStore.transactions),
                onConfirmed: { hasConfirmedContext = true }
            )
            .tabItem { Label("Context", systemImage: "text.bubble.fill") }
        }
        .tint(.white)
        .preferredColorScheme(.dark)
        .task { refreshProfile() }
        .onChange(of: bankStore.accounts) { _, _ in refreshProfile() }
        .onChange(of: bankStore.transactions) { _, _ in refreshProfile() }
    }

    private func refreshProfile() {
        guard !hasConfirmedContext else { return }
        profile = V2Data.profile(
            currentCash: bankStore.isLinked ? bankStore.totalAvailableCash : nil,
            transactions: bankStore.transactions
        )
    }
}

private struct V2Home: View {
    let profile: FinancialProfile
    let linked: Bool
    let phase: BankAccountStore.Phase

    private var dashboard: FinancialDashboardSnapshot? {
        try? FinancialInsights.dashboard(
            profile: profile,
            through: V2Data.horizon(from: profile.asOfDate),
            calendar: V2Data.calendar
        )
    }

    var body: some View {
        V2Screen(eyebrow: linked ? "LINKED PLAN" : "PLAN PREVIEW", title: "What can you safely do?", subtitle: linked ? "Linked-bank history and confirmed context feed one explainable plan." : "Sample data is clearly separated until a bank is connected.") {
            sourceCard
            if let dashboard {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Label("SAFE TO SPEND", systemImage: "checkmark.shield.fill")
                            .font(.caption.weight(.bold))
                            .tracking(1)
                            .foregroundStyle(.white.opacity(0.65))
                        Spacer()
                        V2Pill(status: dashboard.horizonStatus)
                    }
                    Text(dashboard.safeToSpendNow, format: .currency(code: "USD").precision(.fractionLength(0)))
                        .font(.system(size: 56, weight: .light, design: .rounded))
                        .monospacedDigit()
                    Text(healthExplanation(dashboard.horizonStatus))
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.62))
                }
                .padding(20)
                .background(healthColor(dashboard.horizonStatus).opacity(0.13), in: RoundedRectangle(cornerRadius: 24))
                .overlay { RoundedRectangle(cornerRadius: 24).stroke(healthColor(dashboard.horizonStatus).opacity(0.32)) }

                HStack(spacing: 12) {
                    metric("This week", dashboard.recommendedWeeklySpendingLimit, "recommended limit")
                    metric("Protected", max(0, profile.currentCash - dashboard.safeToSpendNow), "not free cash")
                }

                if let change = V2Data.upcoming(profile: profile).first {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("NEXT IMPORTANT CHANGE").v2Eyebrow()
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(change.label).font(.headline)
                                Text(change.date, format: .dateTime.month(.abbreviated).day())
                                    .font(.caption).foregroundStyle(.white.opacity(0.5))
                            }
                            Spacer()
                            Text(abs(change.amount), format: .currency(code: "USD").precision(.fractionLength(0)))
                                .font(.headline.weight(.bold))
                                .foregroundStyle(change.amount >= 0 ? .green : .orange)
                        }
                    }
                    .padding(18).v2Card()
                }

                V2Explain(icon: "point.3.connected.trianglepath.dotted", title: "Why this number?", text: "Safe to spend checks the dated cash path, including known bills, goals, ordinary spending, reserves, and confirmed context.")
            } else {
                V2Explain(icon: "exclamationmark.triangle", title: "Plan unavailable", text: "The current inputs are not ready for a forecast yet.")
            }
        }
    }

    private var sourceCard: some View {
        HStack(spacing: 12) {
            Image(systemName: linked ? "building.columns.fill" : "doc.text.magnifyingglass")
                .font(.title2).frame(width: 40, height: 40)
                .background(.white.opacity(0.08), in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(linked ? "Bank data connected" : "Bank connection required").font(.headline)
                Text(sourceText).font(.caption).foregroundStyle(.white.opacity(0.52))
            }
            Spacer()
        }
        .padding(16).v2Card()
    }

    private var sourceText: String {
        switch phase {
        case .connecting: return "Refreshing linked accounts…"
        case .loadingCache: return "Loading saved bank history…"
        case .failed(_): return "Using saved data; refresh needs attention."
        case .connected: return "Normalized bank data is feeding the plan."
        case .idle: return linked ? "Linked data is available." : "Connect Nessie to load balances and transactions."
        }
    }

    private func metric(_ title: String, _ value: Double, _ caption: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(value, format: .currency(code: "USD").precision(.fractionLength(0))).font(.title3.weight(.bold)).monospacedDigit()
            Text(title).font(.subheadline.weight(.semibold))
            Text(caption).font(.caption).foregroundStyle(.white.opacity(0.5))
        }
        .frame(maxWidth: .infinity, minHeight: 105, alignment: .topLeading)
        .padding(16).v2Card()
    }
}

private struct V2Calendar: View {
    let profile: FinancialProfile

    private var points: [CashFlowPoint] {
        let end = min(V2Data.horizon(from: profile.asOfDate), V2Data.calendar.date(byAdding: .day, value: 30, to: profile.asOfDate) ?? profile.asOfDate)
        return (try? FinancialInsights.cashFlowTimeline(profile: profile, from: profile.asOfDate, through: end, calendar: V2Data.calendar)) ?? []
    }

    var body: some View {
        V2Screen(eyebrow: "CALENDAR", title: "Future cash health", subtitle: "Risk follows the cash path, not the size of a transaction.") {
            VStack(spacing: 0) {
                ForEach(Array(points.enumerated()), id: \.offset) { index, point in
                    HStack(spacing: 12) {
                        VStack(spacing: 2) {
                            Text(point.date, format: .dateTime.weekday(.abbreviated)).font(.caption2.weight(.bold)).foregroundStyle(.white.opacity(0.45))
                            Text(point.date, format: .dateTime.day()).font(.headline)
                        }.frame(width: 42)
                        Image(systemName: healthSymbol(point.status)).font(.title2).foregroundStyle(healthColor(point.status)).frame(width: 32)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(healthTitle(point.status)).font(.headline)
                            Text("Projected cash after dated activity").font(.caption).foregroundStyle(.white.opacity(0.48))
                        }
                        Spacer()
                        Text(point.projectedCash, format: .currency(code: "USD").precision(.fractionLength(0))).font(.headline).monospacedDigit()
                    }
                    .padding(.horizontal, 16).padding(.vertical, 12)
                    if index < points.count - 1 { Divider().overlay(.white.opacity(0.08)).padding(.leading, 66) }
                }
            }.v2Card()
            V2Explain(icon: "calendar.badge.exclamationmark", title: "Path risk, not transaction size", text: "A large bill can remain healthy if enough cash remains. A smaller purchase can become risky when it lands before another obligation or reserve boundary.")
        }
    }
}

private struct V2Plans: View {
    let profile: FinancialProfile

    private var assessments: [GoalPlanAssessment] {
        (try? FinancialInsights.assessAllGoals(profile: profile, planningHorizon: V2Data.horizon(from: profile.asOfDate), calendar: V2Data.calendar)) ?? []
    }

    var body: some View {
        V2Screen(eyebrow: "PLANS", title: "Protect what matters", subtitle: "Goals share the same cash path as bills and spending.") {
            ForEach(assessments, id: \.goal.id) { item in
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.goal.name).font(.title3.weight(.bold))
                            Text("Due \(item.effectiveDeadline.formatted(.dateTime.month(.abbreviated).day()))").font(.caption).foregroundStyle(.white.opacity(0.5))
                        }
                        Spacer(); V2Pill(status: item.status)
                    }
                    Text(item.remainingAmount, format: .currency(code: "USD").precision(.fractionLength(0))).font(.title2.weight(.bold))
                    Text(item.includedInBaseline ? "Protected in the baseline plan." : "Flexible: trade-offs remain visible before another choice harms it.")
                        .font(.caption).foregroundStyle(.white.opacity(0.55))
                }
                .padding(18)
                .background(healthColor(item.status).opacity(0.1), in: RoundedRectangle(cornerRadius: 20))
            }
        }
    }
}

private struct V2WhatIf: View {
    let profile: FinancialProfile
    @State private var amount = 500.0

    private var analysis: PurchaseWhatIfAnalysis? {
        try? FinancialInsights.analyzePurchaseWhatIf(profile: profile, amount: amount, purchaseDate: profile.asOfDate, planningHorizon: V2Data.horizon(from: profile.asOfDate), calendar: V2Data.calendar)
    }

    var body: some View {
        V2Screen(eyebrow: "WHAT IF", title: "What happens if I buy it?", subtitle: "Test a choice without changing your plan.") {
            VStack(alignment: .leading, spacing: 14) {
                Text(amount, format: .currency(code: "USD").precision(.fractionLength(0))).font(.system(size: 50, weight: .light, design: .rounded)).monospacedDigit()
                Slider(value: $amount, in: 0...1_500, step: 25).tint(.white)
            }.padding(20).v2Card()

            if let analysis {
                VStack(alignment: .leading, spacing: 12) {
                    Text(purchaseTitle(analysis.purchaseAssessment.status)).font(.title2.weight(.bold))
                    Text(purchaseReason(analysis.purchaseExplanation.reason)).font(.subheadline).foregroundStyle(.white.opacity(0.64))
                    HStack {
                        Text("Tightest date").font(.caption).foregroundStyle(.white.opacity(0.5))
                        Spacer()
                        Text(analysis.purchaseExplanation.limitingDate, format: .dateTime.month(.abbreviated).day()).font(.headline)
                    }
                }.padding(18).v2Card()

                if !analysis.goalImpacts.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("GOAL TRADE-OFFS").v2Eyebrow()
                        ForEach(analysis.goalImpacts, id: \.goal.id) { impact in
                            HStack {
                                Text(impact.goal.name).font(.subheadline.weight(.semibold))
                                Spacer()
                                Text(healthTitle(impact.after.status)).font(.caption.weight(.bold)).foregroundStyle(healthColor(impact.after.status))
                            }
                        }
                    }.padding(18).v2Card()
                }
            }
        }
    }
}

private struct V2Context: View {
    @Binding var profile: FinancialProfile
    let items: [V2Data.ContextItem]
    let onConfirmed: () -> Void
    @State private var selectedID: String?
    @State private var note = ""
    @State private var parsed: QualitativeParseResult?
    @State private var message: String?

    private var selected: V2Data.ContextItem? {
        guard let first = items.first else { return nil }
        guard let selectedID else { return first }
        return items.first(where: { $0.id == selectedID }) ?? first
    }

    var body: some View {
        V2Screen(eyebrow: "CONTEXT", title: "Tell us what the bank can't know", subtitle: "Choose a real transaction or plan item. Nothing changes until you confirm.") {
            if let selected {
                VStack(alignment: .leading, spacing: 10) {
                    Picker("Item", selection: Binding(get: { selectedID ?? selected.id }, set: { id in select(id) })) {
                        ForEach(items) { Text($0.title).tag($0.id) }
                    }.pickerStyle(.menu).tint(.white)
                    Text(selected.subtitle).font(.caption).foregroundStyle(.white.opacity(0.52))
                }.padding(18).v2Card()

                VStack(alignment: .leading, spacing: 12) {
                    TextEditor(text: $note).frame(minHeight: 105).scrollContentBackground(.hidden).padding(10).background(.black.opacity(0.16), in: RoundedRectangle(cornerRadius: 14))
                    Button("Interpret") {
                        parsed = QualitativeNoteInterpreter.parse(note, context: selected.context, asOfDate: profile.asOfDate, calendar: V2Data.calendar)
                        message = nil
                    }.buttonStyle(V2ButtonStyle())
                }.padding(18).v2Card()

                if let parsed {
                    VStack(alignment: .leading, spacing: 10) {
                        if !parsed.recognizedSomething {
                            Label("Not recognized, so the plan will not change.", systemImage: "questionmark.circle").foregroundStyle(.yellow)
                        }
                        ForEach(parsed.missingFields, id: \.rawValue) { field in
                            Label(missingQuestion(field), systemImage: "questionmark.circle.fill").foregroundStyle(.yellow)
                        }
                        if parsed.isActionable {
                            Button("Confirm interpretation") {
                                let result = QualitativeProfileUpdater.apply(parsed, to: profile, context: selected.context, goalID: selected.goalID, through: V2Data.horizon(from: profile.asOfDate), reserveNote: "Confirmed context: \(selected.title)", calendar: V2Data.calendar)
                                profile = result.profile
                                message = result.didChange ? "Plan updated across the product." : "No change needed; the plan already reflects this."
                                onConfirmed(); self.parsed = nil
                            }.buttonStyle(V2ButtonStyle())
                        }
                    }.padding(18).v2Card()
                }
                if let message { Label(message, systemImage: "checkmark.circle.fill").padding(16).frame(maxWidth: .infinity, alignment: .leading).v2Card() }
            }
            V2Explain(icon: "lock.shield.fill", title: "Constrained and confirm-first", text: "The local interpreter only maps supported financial meanings. Missing dates, cadence, or amounts are requested instead of guessed.")
        }
        .task { if selectedID == nil, let first = items.first { selectedID = first.id; note = first.suggestedText } }
        .onChange(of: items.map(\.id)) { _, ids in
            if let first = items.first, selectedID == nil || !ids.contains(selectedID ?? "") { selectedID = first.id; note = first.suggestedText; parsed = nil; message = nil }
        }
    }

    private func select(_ id: String) {
        selectedID = id
        if let item = items.first(where: { $0.id == id }) { note = item.suggestedText }
        parsed = nil; message = nil
    }
}

private enum V2Data {
    static var calendar: Calendar { var value = Calendar(identifier: .gregorian); value.timeZone = TimeZone(secondsFromGMT: 0)!; return value }
    static func day(_ date: Date) -> Date { calendar.startOfDay(for: date) }
    static func horizon(from date: Date) -> Date { calendar.date(byAdding: .day, value: 79, to: date) ?? date }
    struct ContextItem: Identifiable {
        let id: String; let title: String; let subtitle: String; let amount: Double?; let date: Date?; let subject: QualitativeNoteSubject; let suggestedText: String; let goalID: UUID?
        var context: QualitativeNoteContext { QualitativeNoteContext(subject: subject, referenceAmount: amount, referenceDate: date, label: title) }
    }
    struct Change { let date: Date; let label: String; let amount: Double }

    static func profile(currentCash: Double?, transactions: [FinanceCore.FinancialTransaction]) -> FinancialProfile {
        let asOf = day(Date())
        let usable = transactions.filter { !$0.isPending && !$0.isTransfer && $0.transactionDate <= asOf }
        let bankIncomes = usable.filter { $0.direction == .inflow }.map { tx in
            IncomeEvent(amount: Double(tx.amountMinorUnits) / 100, date: day(tx.transactionDate), source: label(tx), type: tx.sourceType == .refund ? .oneTime : .irregular, confidence: 1)
        }
        let bankExpenses = usable.filter { $0.direction == .outflow }.map { tx in
            ExpenseEvent(amount: Double(tx.amountMinorUnits) / 100, date: day(tx.transactionDate), category: label(tx), essential: false, committed: false)
        }
        return FinancialProfile(
            currentCash: currentCash ?? 0,
            asOfDate: asOf,
            personalReserveSteps: [],
            institutionalMinimums: [],
            incomeEvents: bankIncomes,
            expenseEvents: bankExpenses,
            goals: [],
            weeklySpendingHistory: history(usable, asOf),
            spendingPolicy: SpendingPolicy(lookbackWeeks: 6, bufferWeeks: 2, manualMinimumBuffer: 0)
        )
    }

    static func contextItems(transactions: [FinanceCore.FinancialTransaction]) -> [ContextItem] {
        let usable = transactions.filter { !$0.isPending && !$0.isTransfer }.sorted { $0.transactionDate > $1.transactionDate }
        var result: [ContextItem] = []
        if let tx = usable.first(where: { $0.direction == .inflow }) {
            result.append(ContextItem(id: "income-\(tx.id)", title: label(tx), subtitle: "+\(money(tx)) · \(dateText(tx.transactionDate))", amount: Double(tx.amountMinorUnits) / 100, date: day(tx.transactionDate), subject: .income, suggestedText: "I get this every two weeks.", goalID: nil))
        }
        if let tx = usable.first(where: { $0.direction == .outflow }) {
            result.append(ContextItem(id: "expense-\(tx.id)", title: label(tx), subtitle: "-\(money(tx)) · \(dateText(tx.transactionDate))", amount: Double(tx.amountMinorUnits) / 100, date: day(tx.transactionDate), subject: .expense, suggestedText: "They owe me for this and will pay me next Friday.", goalID: nil))
        }
        return result
    }

    static func upcoming(profile: FinancialProfile) -> [Change] {
        let incomes = profile.incomeEvents.filter { $0.date > profile.asOfDate }.map { Change(date: $0.date, label: $0.source, amount: $0.adjustedAmount) }
        let expenses = profile.expenseEvents.filter { $0.committed && $0.date > profile.asOfDate }.map { Change(date: $0.date, label: $0.category, amount: -$0.amount) }
        let goals = profile.goals.filter { $0.priority == .mandatory && $0.deadline > profile.asOfDate && $0.remainingAmount > 0 }.map { Change(date: $0.deadline, label: $0.name, amount: -$0.remainingAmount) }
        return (incomes + expenses + goals).sorted { $0.date < $1.date }
    }

    private static func history(_ transactions: [FinanceCore.FinancialTransaction], _ asOf: Date) -> [WeeklySpendingSample] {
        let grouped = Dictionary(grouping: transactions.filter { $0.direction == .outflow }) { calendar.dateInterval(of: .weekOfYear, for: $0.transactionDate)?.start ?? day($0.transactionDate) }
        let earliest = calendar.date(byAdding: .day, value: -42, to: asOf) ?? .distantPast
        return grouped.filter { $0.key >= earliest && $0.key <= asOf }.map { WeeklySpendingSample(weekStart: $0.key, totalVariableSpending: $0.value.reduce(0) { $0 + Double($1.amountMinorUnits) / 100 }) }.sorted { $0.weekStart < $1.weekStart }
    }

    private static func label(_ tx: FinanceCore.FinancialTransaction) -> String { let value = (tx.merchantName ?? tx.transactionDescription).trimmingCharacters(in: .whitespacesAndNewlines); return value.isEmpty ? "Bank transaction" : value }
    private static func money(_ tx: FinanceCore.FinancialTransaction) -> String { (Double(tx.amountMinorUnits) / 100).formatted(.currency(code: "USD").precision(.fractionLength(0))) }
    private static func dateText(_ date: Date) -> String { date.formatted(.dateTime.month(.abbreviated).day()) }
}

private struct V2Screen<Content: View>: View {
    let eyebrow: String; let title: String; let subtitle: String; @ViewBuilder let content: Content
    init(eyebrow: String, title: String, subtitle: String, @ViewBuilder content: () -> Content) { self.eyebrow = eyebrow; self.title = title; self.subtitle = subtitle; self.content = content() }
    var body: some View {
        NavigationStack { ZStack { V2Background(); ScrollView { VStack(alignment: .leading, spacing: 16) { VStack(alignment: .leading, spacing: 7) { Text(eyebrow).v2Eyebrow(); Text(title).font(.largeTitle.weight(.bold)); Text(subtitle).font(.subheadline).foregroundStyle(.white.opacity(0.6)) }; content }.padding(20).padding(.bottom, 30) } }.navigationBarHidden(true) }
    }
}
private struct V2Background: View { var body: some View { LinearGradient(colors: [Color(red: 0.035, green: 0.07, blue: 0.13), Color(red: 0.055, green: 0.13, blue: 0.20), Color(red: 0.025, green: 0.05, blue: 0.10)], startPoint: .topLeading, endPoint: .bottomTrailing).ignoresSafeArea() } }
private struct V2Explain: View { let icon: String; let title: String; let text: String; var body: some View { HStack(alignment: .top, spacing: 12) { Image(systemName: icon).frame(width: 34, height: 34).background(.white.opacity(0.08), in: Circle()); VStack(alignment: .leading, spacing: 5) { Text(title).font(.subheadline.weight(.semibold)); Text(text).font(.caption).foregroundStyle(.white.opacity(0.52)) } }.padding(16).v2Card() } }
private struct V2Pill: View { let status: FinancialHealthStatus; var body: some View { Text(healthTitle(status)).font(.caption.weight(.bold)).padding(.horizontal, 10).padding(.vertical, 6).foregroundStyle(healthColor(status)).background(healthColor(status).opacity(0.12), in: Capsule()) } }
private struct V2ButtonStyle: ButtonStyle { func makeBody(configuration: Configuration) -> some View { configuration.label.font(.headline).frame(maxWidth: .infinity).padding(.vertical, 13).foregroundStyle(.black).background(.white.opacity(configuration.isPressed ? 0.78 : 1), in: RoundedRectangle(cornerRadius: 12)) } }
private extension View { func v2Card() -> some View { background(.white.opacity(0.065), in: RoundedRectangle(cornerRadius: 20)).overlay { RoundedRectangle(cornerRadius: 20).stroke(.white.opacity(0.08)) } }; func v2Eyebrow() -> some View { font(.caption.weight(.bold)).tracking(1.2).foregroundStyle(.white.opacity(0.55)) } }
private func healthColor(_ status: FinancialHealthStatus) -> Color { switch status { case .safe: .green; case .tight: .orange; case .notSafe: .red } }
private func healthSymbol(_ status: FinancialHealthStatus) -> String { switch status { case .safe: "checkmark.circle.fill"; case .tight: "exclamationmark.circle.fill"; case .notSafe: "xmark.octagon.fill" } }
private func healthTitle(_ status: FinancialHealthStatus) -> String { switch status { case .safe: "Safe"; case .tight: "Tight"; case .notSafe: "Not safe" } }
private func healthExplanation(_ status: FinancialHealthStatus) -> String { switch status { case .safe: "Your projected path stays above the recommended protection level."; case .tight: "The plan stays above the hard minimum, but the recommended cushion gets thin."; case .notSafe: "At least one point drops below a protected minimum." } }
private func purchaseTitle(_ status: PurchaseStatus) -> String { switch status { case .safe: "This purchase fits the plan"; case .tight: "Possible, but it makes the plan tight"; case .notSafe: "This purchase breaks a protected boundary" } }
private func purchaseReason(_ reason: PurchaseDecisionReason) -> String { switch reason { case .preservesRecommendedBuffer: "The full future cash path remains above the recommended buffer."; case .usesSafetyBuffer: "The purchase uses part of the safety cushion but stays above the hard minimum."; case .violatesPersonalReserve: "The purchase pushes the plan below your personal reserve."; case .violatesInstitutionalMinimum: "The purchase pushes the plan below an account minimum."; case .violatesMultipleHardConstraints: "The purchase crosses more than one protected minimum." } }
private func missingQuestion(_ field: QualitativeMissingField) -> String { switch field { case .repaymentDate: "When do you expect to be paid back?"; case .recurrenceCadence: "How often does this repeat?"; case .reserveAmount: "How much cash do you want to keep untouched?" } }
