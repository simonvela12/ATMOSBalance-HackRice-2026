import SwiftUI
import FinanceCore
import FinancialCore

struct ProductRootView: View {
    @EnvironmentObject private var bankStore: BankAccountStore
    @State private var profile = ProductV2Data.makeProfile(accounts: [], transactions: [])
    @State private var contextEdited = false

    var body: some View {
        TabView {
            HomeV2View(profile: profile, isLinked: bankStore.isLinked, syncPhase: bankStore.phase)
                .tabItem { Label("Home", systemImage: "house.fill") }

            CalendarV2View(profile: profile)
                .tabItem { Label("Calendar", systemImage: "calendar") }

            PlansV2View(profile: profile)
                .tabItem { Label("Plans", systemImage: "target") }

            WhatIfV2View(profile: profile)
                .tabItem { Label("What If", systemImage: "slider.horizontal.3") }

            ContextV2View(
                profile: $profile,
                items: ProductV2Data.contextItems(from: bankStore.transactions),
                onApplied: { contextEdited = true }
            )
            .tabItem { Label("Context", systemImage: "text.bubble.fill") }
        }
        .tint(.white)
        .preferredColorScheme(.dark)
        .task { syncProfileFromBankIfSafe() }
        .onChange(of: bankStore.accounts) { _, _ in syncProfileFromBankIfSafe() }
        .onChange(of: bankStore.transactions) { _, _ in syncProfileFromBankIfSafe() }
    }

    private func syncProfileFromBankIfSafe() {
        guard !contextEdited else { return }
        profile = ProductV2Data.makeProfile(
            accounts: bankStore.accounts,
            transactions: bankStore.transactions
        )
    }
}

// MARK: - Home

private struct HomeV2View: View {
    let profile: FinancialProfile
    let isLinked: Bool
    let syncPhase: BankAccountStore.Phase

    private var dashboard: FinancialDashboardSnapshot? {
        try? FinancialInsights.dashboard(
            profile: profile,
            through: ProductV2Data.horizon(for: profile.asOfDate),
            calendar: ProductV2Data.calendar
        )
    }

    private var nextChange: ProductV2Data.UpcomingChange? {
        ProductV2Data.upcomingChanges(profile: profile).first
    }

    var body: some View {
        NavigationStack {
            ZStack {
                V2Background()
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        V2Header(
                            eyebrow: isLinked ? "LINKED PLAN" : "PLAN PREVIEW",
                            title: "What can you safely do?",
                            subtitle: isLinked
                                ? "Your linked-bank history and confirmed context feed one explainable cash plan."
                                : "Connect a bank account when ready. Until then, this preview uses clearly separated sample data."
                        )

                        sourceCard

                        if let dashboard {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack {
                                    Label("SAFE TO SPEND", systemImage: "checkmark.shield.fill")
                                        .font(.caption.weight(.bold))
                                        .tracking(1.1)
                                        .foregroundStyle(.white.opacity(0.68))
                                    Spacer()
                                    V2StatusPill(status: dashboard.horizonStatus)
                                }

                                Text(dashboard.safeToSpendNow, format: .currency(code: "USD").precision(.fractionLength(0)))
                                    .font(.system(size: 58, weight: .light, design: .rounded))
                                    .monospacedDigit()

                                Text(statusExplanation(dashboard.horizonStatus))
                                    .font(.subheadline)
                                    .foregroundStyle(.white.opacity(0.65))
                            }
                            .padding(20)
                            .background(v2HealthColor(dashboard.horizonStatus).opacity(0.14), in: RoundedRectangle(cornerRadius: 24))
                            .overlay {
                                RoundedRectangle(cornerRadius: 24)
                                    .stroke(v2HealthColor(dashboard.horizonStatus).opacity(0.35), lineWidth: 1)
                            }

                            HStack(spacing: 12) {
                                metricCard(
                                    title: "This week",
                                    value: dashboard.recommendedWeeklySpendingLimit,
                                    caption: "recommended spending limit"
                                )
                                metricCard(
                                    title: "Protected",
                                    value: max(0, profile.currentCash - dashboard.safeToSpendNow),
                                    caption: "not treated as free cash"
                                )
                            }

                            if let nextChange {
                                VStack(alignment: .leading, spacing: 10) {
                                    Text("NEXT IMPORTANT CHANGE")
                                        .font(.caption.weight(.bold))
                                        .tracking(1.1)
                                        .foregroundStyle(.white.opacity(0.55))
                                    HStack {
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(nextChange.label).font(.headline)
                                            Text(nextChange.date, format: .dateTime.month(.abbreviated).day())
                                                .font(.caption)
                                                .foregroundStyle(.white.opacity(0.5))
                                        }
                                        Spacer()
                                        Text(abs(nextChange.amount), format: .currency(code: "USD").precision(.fractionLength(0)))
                                            .font(.headline.weight(.bold))
                                            .foregroundStyle(nextChange.amount >= 0 ? .green : .orange)
                                    }
                                }
                                .padding(18)
                                .v2Card()
                            }

                            V2Explanation(
                                icon: "point.3.connected.trianglepath.dotted",
                                title: "Why this number?",
                                text: "Safe to spend checks the full dated cash path: linked cash, known bills, mandatory goals, ordinary spending, reserve rules, and confirmed context."
                            )
                        } else {
                            V2Unavailable(text: "The current inputs are not ready for a forecast yet.")
                        }
                    }
                    .padding(20)
                    .padding(.bottom, 30)
                }
            }
            .navigationBarHidden(true)
        }
    }

    private var sourceCard: some View {
        HStack(spacing: 12) {
            Image(systemName: isLinked ? "building.columns.fill" : "rectangle.and.pencil.and.ellipsis")
                .font(.title2)
                .frame(width: 42, height: 42)
                .background(.white.opacity(0.08), in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(isLinked ? "Bank data connected" : "Sample plan active")
                    .font(.headline)
                Text(sourceSubtitle)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.52))
            }
            Spacer()
        }
        .padding(16)
        .v2Card()
    }

    private var sourceSubtitle: String {
        switch syncPhase {
        case .connecting: return "Refreshing linked accounts…"
        case .loadingCache: return "Loading saved bank history…"
        case .failed: return "Using the latest saved data; refresh needs attention."
        default: return isLinked ? "Normalized Nessie transactions are available to the plan." : "No linked-bank values are presented as live data."
        }
    }

    private func metricCard(title: String, value: Double, caption: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(value, format: .currency(code: "USD").precision(.fractionLength(0)))
                .font(.title3.weight(.bold))
                .monospacedDigit()
            Text(title).font(.subheadline.weight(.semibold))
            Text(caption)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.5))
        }
        .frame(maxWidth: .infinity, minHeight: 112, alignment: .topLeading)
        .padding(16)
        .v2Card()
    }
}

// MARK: - Calendar

private struct CalendarV2View: View {
    let profile: FinancialProfile

    private var timeline: [CashFlowPoint] {
        let horizon = min(
            ProductV2Data.horizon(for: profile.asOfDate),
            ProductV2Data.calendar.date(byAdding: .day, value: 30, to: profile.asOfDate) ?? profile.asOfDate
        )
        return (try? FinancialInsights.cashFlowTimeline(
            profile: profile,
            from: profile.asOfDate,
            through: horizon,
            calendar: ProductV2Data.calendar
        )) ?? []
    }

    var body: some View {
        NavigationStack {
            ZStack {
                V2Background()
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        V2Header(
                            eyebrow: "CALENDAR",
                            title: "Future cash health",
                            subtitle: "Risk follows the cash path, not the size of a transaction."
                        )

                        VStack(spacing: 0) {
                            ForEach(Array(timeline.enumerated()), id: \.offset) { index, point in
                                HStack(spacing: 14) {
                                    VStack(spacing: 2) {
                                        Text(point.date, format: .dateTime.weekday(.abbreviated))
                                            .font(.caption2.weight(.bold))
                                            .foregroundStyle(.white.opacity(0.45))
                                        Text(point.date, format: .dateTime.day())
                                            .font(.headline)
                                    }
                                    .frame(width: 42)

                                    Image(systemName: v2HealthSymbol(point.status))
                                        .foregroundStyle(v2HealthColor(point.status))
                                        .font(.title2)
                                        .frame(width: 34)

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(v2HealthTitle(point.status)).font(.headline)
                                        Text("Projected cash after dated activity")
                                            .font(.caption)
                                            .foregroundStyle(.white.opacity(0.48))
                                    }
                                    Spacer()
                                    Text(point.projectedCash, format: .currency(code: "USD").precision(.fractionLength(0)))
                                        .font(.headline.weight(.semibold))
                                        .monospacedDigit()
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                                if index < timeline.count - 1 {
                                    Divider().overlay(.white.opacity(0.08)).padding(.leading, 68)
                                }
                            }
                        }
                        .v2Card()

                        V2Explanation(
                            icon: "calendar.badge.exclamationmark",
                            title: "Path risk, not transaction size",
                            text: "A large rent payment can remain healthy if enough cash remains. A smaller purchase can be risky if it lands just before another obligation or reserve boundary."
                        )
                    }
                    .padding(20)
                    .padding(.bottom, 30)
                }
            }
            .navigationBarHidden(true)
        }
    }
}

// MARK: - Plans

private struct PlansV2View: View {
    let profile: FinancialProfile

    private var goals: [GoalPlanAssessment] {
        (try? FinancialInsights.assessAllGoals(
            profile: profile,
            planningHorizon: ProductV2Data.horizon(for: profile.asOfDate),
            calendar: ProductV2Data.calendar
        )) ?? []
    }

    var body: some View {
        NavigationStack {
            ZStack {
                V2Background()
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        V2Header(
                            eyebrow: "PLANS",
                            title: "Protect what matters",
                            subtitle: "Goals share the same cash path as bills and spending."
                        )

                        ForEach(goals, id: \.goal.id) { assessment in
                            VStack(alignment: .leading, spacing: 12) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(assessment.goal.name).font(.title3.weight(.bold))
                                        Text("Due \(assessment.effectiveDeadline.formatted(.dateTime.month(.abbreviated).day()))")
                                            .font(.caption)
                                            .foregroundStyle(.white.opacity(0.5))
                                    }
                                    Spacer()
                                    V2StatusPill(status: assessment.status)
                                }
                                Text(assessment.remainingAmount, format: .currency(code: "USD").precision(.fractionLength(0)))
                                    .font(.title2.weight(.bold))
                                Text(assessment.includedInBaseline
                                     ? "Protected in the baseline plan."
                                     : "Flexible: trade-offs stay visible before another choice harms it.")
                                    .font(.caption)
                                    .foregroundStyle(.white.opacity(0.55))
                            }
                            .padding(18)
                            .background(v2HealthColor(assessment.status).opacity(0.11), in: RoundedRectangle(cornerRadius: 20))
                            .overlay {
                                RoundedRectangle(cornerRadius: 20)
                                    .stroke(v2HealthColor(assessment.status).opacity(0.28), lineWidth: 1)
                            }
                        }
                    }
                    .padding(20)
                    .padding(.bottom, 30)
                }
            }
            .navigationBarHidden(true)
        }
    }
}

// MARK: - What If

private struct WhatIfV2View: View {
    let profile: FinancialProfile
    @State private var amount = 500.0

    private var analysis: PurchaseWhatIfAnalysis? {
        try? FinancialInsights.analyzePurchaseWhatIf(
            profile: profile,
            amount: amount,
            purchaseDate: profile.asOfDate,
            planningHorizon: ProductV2Data.horizon(for: profile.asOfDate),
            calendar: ProductV2Data.calendar
        )
    }

    var body: some View {
        NavigationStack {
            ZStack {
                V2Background()
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        V2Header(
                            eyebrow: "WHAT IF",
                            title: "What happens if I buy it?",
                            subtitle: "Test the purchase without changing your plan."
                        )

                        VStack(alignment: .leading, spacing: 14) {
                            Text(amount, format: .currency(code: "USD").precision(.fractionLength(0)))
                                .font(.system(size: 50, weight: .light, design: .rounded))
                                .monospacedDigit()
                            Slider(value: $amount, in: 0...1_500, step: 25).tint(.white)
                        }
                        .padding(20)
                        .v2Card()

                        if let analysis {
                            VStack(alignment: .leading, spacing: 12) {
                                Text(v2PurchaseTitle(analysis.purchaseAssessment.status))
                                    .font(.title2.weight(.bold))
                                Text(v2PurchaseReason(analysis.purchaseExplanation.reason))
                                    .font(.subheadline)
                                    .foregroundStyle(.white.opacity(0.65))
                                HStack {
                                    Text("Tightest date")
                                        .font(.caption)
                                        .foregroundStyle(.white.opacity(0.5))
                                    Spacer()
                                    Text(analysis.purchaseExplanation.limitingDate, format: .dateTime.month(.abbreviated).day())
                                        .font(.headline)
                                }
                            }
                            .padding(18)
                            .v2Card()

                            if !analysis.goalImpacts.isEmpty {
                                VStack(alignment: .leading, spacing: 10) {
                                    Text("GOAL TRADE-OFFS")
                                        .font(.caption.weight(.bold))
                                        .tracking(1.1)
                                        .foregroundStyle(.white.opacity(0.55))
                                    ForEach(analysis.goalImpacts, id: \.goal.id) { impact in
                                        HStack {
                                            Text(impact.goal.name).font(.subheadline.weight(.semibold))
                                            Spacer()
                                            Text(impact.after.status.rawValue.replacingOccurrences(of: "_", with: " ").capitalized)
                                                .font(.caption.weight(.bold))
                                                .foregroundStyle(v2HealthColor(impact.after.status))
                                        }
                                    }
                                }
                                .padding(18)
                                .v2Card()
                            }
                        }
                    }
                    .padding(20)
                    .padding(.bottom, 30)
                }
            }
            .navigationBarHidden(true)
        }
    }
}

// MARK: - Context

private struct ContextV2View: View {
    @Binding var profile: FinancialProfile
    let items: [ProductV2Data.ContextItem]
    let onApplied: () -> Void

    @State private var selectedID: String?
    @State private var note = ""
    @State private var parsed: QualitativeParseResult?
    @State private var resultMessage: String?

    private var selected: ProductV2Data.ContextItem? {
        guard let selectedID else { return items.first }
        return items.first(where: { $0.id == selectedID }) ?? items.first
    }

    var body: some View {
        NavigationStack {
            ZStack {
                V2Background()
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        V2Header(
                            eyebrow: "CONTEXT",
                            title: "Tell us what the bank can't know",
                            subtitle: "Choose a real transaction or plan item. Nothing changes until you confirm the interpretation."
                        )

                        if let selected {
                            VStack(alignment: .leading, spacing: 10) {
                                Picker("Item", selection: Binding(
                                    get: { selectedID ?? selected.id },
                                    set: { newValue in
                                        selectedID = newValue
                                        if let item = items.first(where: { $0.id == newValue }) {
                                            note = item.suggestedText
                                        }
                                        parsed = nil
                                        resultMessage = nil
                                    }
                                )) {
                                    ForEach(items) { item in Text(item.title).tag(item.id) }
                                }
                                .pickerStyle(.menu)
                                .tint(.white)

                                Text(selected.subtitle)
                                    .font(.caption)
                                    .foregroundStyle(.white.opacity(0.52))
                            }
                            .padding(18)
                            .v2Card()

                            VStack(alignment: .leading, spacing: 12) {
                                TextEditor(text: $note)
                                    .frame(minHeight: 110)
                                    .scrollContentBackground(.hidden)
                                    .padding(10)
                                    .background(.black.opacity(0.16), in: RoundedRectangle(cornerRadius: 14))

                                Button("Interpret") {
                                    parsed = QualitativeNoteInterpreter.parse(
                                        note,
                                        context: selected.context,
                                        asOfDate: profile.asOfDate,
                                        calendar: ProductV2Data.calendar
                                    )
                                    resultMessage = nil
                                }
                                .buttonStyle(V2PrimaryButtonStyle())
                            }
                            .padding(18)
                            .v2Card()

                            if let parsed {
                                VStack(alignment: .leading, spacing: 10) {
                                    if !parsed.recognizedSomething {
                                        Label("Not recognized, so the plan will not change.", systemImage: "questionmark.circle")
                                            .foregroundStyle(.yellow)
                                    } else {
                                        ForEach(parsed.missingFields, id: \.rawValue) { field in
                                            Label(v2MissingQuestion(field), systemImage: "questionmark.circle.fill")
                                                .foregroundStyle(.yellow)
                                        }
                                    }

                                    if parsed.isActionable {
                                        Button("Confirm interpretation") {
                                            let applied = QualitativeProfileUpdater.apply(
                                                parsed,
                                                to: profile,
                                                context: selected.context,
                                                goalID: selected.goalID,
                                                through: ProductV2Data.horizon(for: profile.asOfDate),
                                                reserveNote: "Confirmed context: \(selected.title)",
                                                calendar: ProductV2Data.calendar
                                            )
                                            profile = applied.profile
                                            resultMessage = applied.didChange
                                                ? "Plan updated across Home, Calendar, Plans, and What If."
                                                : "No change was needed; the plan already reflects this."
                                            onApplied()
                                            self.parsed = nil
                                        }
                                        .buttonStyle(V2PrimaryButtonStyle())
                                    }
                                }
                                .padding(18)
                                .v2Card()
                            }

                            if let resultMessage {
                                Label(resultMessage, systemImage: "checkmark.circle.fill")
                                    .font(.subheadline.weight(.semibold))
                                    .padding(16)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .v2Card()
                            }
                        }

                        V2Explanation(
                            icon: "lock.shield.fill",
                            title: "Constrained and confirm-first",
                            text: "The local interpreter only maps supported financial meanings. Missing dates, cadence, or amounts are requested instead of guessed."
                        )
                    }
                    .padding(20)
                    .padding(.bottom, 30)
                }
            }
            .navigationBarHidden(true)
            .task {
                if selectedID == nil, let first = items.first {
                    selectedID = first.id
                    note = first.suggestedText
                }
            }
            .onChange(of: items.map(\.id)) { _, newIDs in
                guard let firstID = newIDs.first else { return }
                if selectedID == nil || !newIDs.contains(selectedID ?? "") {
                    selectedID = firstID
                    if let first = items.first { note = first.suggestedText }
                    parsed = nil
                    resultMessage = nil
                }
            }
        }
    }
}

// MARK: - Product data integration

private enum ProductV2Data {
    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    static func horizon(for asOf: Date) -> Date {
        calendar.date(byAdding: .day, value: 79, to: asOf) ?? asOf
    }

    static func normalizedDay(_ date: Date) -> Date { calendar.startOfDay(for: date) }

    static let miamiGoalID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    static let tuitionGoalID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!

    struct ContextItem: Identifiable {
        let id: String
        let title: String
        let subtitle: String
        let amount: Double?
        let referenceDate: Date?
        let subject: QualitativeNoteSubject
        let suggestedText: String
        let goalID: UUID?

        var context: QualitativeNoteContext {
            QualitativeNoteContext(
                subject: subject,
                referenceAmount: amount,
                referenceDate: referenceDate,
                label: title
            )
        }
    }

    struct UpcomingChange {
        let date: Date
        let label: String
        let amount: Double
    }

    static func makeProfile(
        accounts: [FinanceCore.FinancialAccount],
        transactions: [FinanceCore.FinancialTransaction]
    ) -> FinancialProfile {
        let today = normalizedDay(Date())
        let linked = !accounts.isEmpty
        let currentCash = linked
            ? Double(accounts.filter { $0.accountType != .creditCard }.reduce(Int64(0)) { $0 + $1.balanceMinorUnits }) / 100
            : 3_200

        let usableTransactions = transactions.filter {
            !$0.isPending && !$0.isTransfer && $0.transactionDate <= today
        }

        let historicalIncome = usableTransactions
            .filter { $0.direction == .inflow }
            .map {
                IncomeEvent(
                    amount: Double($0.amountMinorUnits) / 100,
                    date: normalizedDay($0.transactionDate),
                    source: cleanLabel($0),
                    type: $0.sourceType == .refund ? .oneTime : .irregular,
                    confidence: 1
                )
            }

        let historicalExpenses = usableTransactions
            .filter { $0.direction == .outflow }
            .map {
                ExpenseEvent(
                    amount: Double($0.amountMinorUnits) / 100,
                    date: normalizedDay($0.transactionDate),
                    category: cleanLabel($0),
                    essential: false,
                    committed: false,
                    reimbursable: false,
                    extraordinary: false
                )
            }

        let fallbackHistoricalIncome = linked ? [] : [
            IncomeEvent(amount: 650, date: calendar.date(byAdding: .day, value: -6, to: today) ?? today, source: "Campus job", type: .irregular, confidence: 1)
        ]
        let fallbackHistoricalExpense = linked ? [] : [
            ExpenseEvent(amount: 180, date: calendar.date(byAdding: .day, value: -2, to: today) ?? today, category: "Group dinner", essential: false, committed: false)
        ]

        let scheduledExpenses = [
            ExpenseEvent(amount: 900, date: calendar.date(byAdding: .day, value: 3, to: today) ?? today, category: "Rent", essential: true, committed: true),
            ExpenseEvent(amount: 80, date: calendar.date(byAdding: .day, value: 6, to: today) ?? today, category: "Phone", essential: true, committed: true),
            ExpenseEvent(amount: 25, date: calendar.date(byAdding: .day, value: 18, to: today) ?? today, category: "Streaming subscription", essential: false, committed: true)
        ]

        return FinancialProfile(
            currentCash: currentCash,
            asOfDate: today,
            personalReserveSteps: [
                PersonalReserveStep(effectiveDate: today, minimumCash: 500, note: "Confirmed personal reserve")
            ],
            institutionalMinimums: [],
            incomeEvents: historicalIncome + fallbackHistoricalIncome,
            expenseEvents: historicalExpenses + fallbackHistoricalExpense + scheduledExpenses,
            goals: [
                Goal(id: tuitionGoalID, name: "Tuition installment", targetAmount: 350, deadline: calendar.date(byAdding: .day, value: 16, to: today) ?? today, priority: .mandatory),
                Goal(id: miamiGoalID, name: "Miami", targetAmount: 900, deadline: calendar.date(byAdding: .day, value: 38, to: today) ?? today, priority: .flexible)
            ],
            weeklySpendingHistory: linked ? weeklyHistory(from: usableTransactions, asOf: today) : fallbackWeeklyHistory(asOf: today),
            spendingPolicy: SpendingPolicy(lookbackWeeks: 6, bufferWeeks: 2, manualMinimumBuffer: 200)
        )
    }

    static func contextItems(from transactions: [FinanceCore.FinancialTransaction]) -> [ContextItem] {
        let usable = transactions
            .filter { !$0.isPending && !$0.isTransfer }
            .sorted { $0.transactionDate > $1.transactionDate }

        var items: [ContextItem] = []

        if let income = usable.first(where: { $0.direction == .inflow }) {
            items.append(ContextItem(
                id: "bank-income-\(income.id)",
                title: cleanLabel(income),
                subtitle: "+\(currency(Double(income.amountMinorUnits) / 100)) · \(shortDate(income.transactionDate))",
                amount: Double(income.amountMinorUnits) / 100,
                referenceDate: normalizedDay(income.transactionDate),
                subject: .income,
                suggestedText: "I get this every two weeks.",
                goalID: nil
            ))
        }

        if let expense = usable.first(where: { $0.direction == .outflow }) {
            items.append(ContextItem(
                id: "bank-expense-\(expense.id)",
                title: cleanLabel(expense),
                subtitle: "-\(currency(Double(expense.amountMinorUnits) / 100)) · \(shortDate(expense.transactionDate))",
                amount: Double(expense.amountMinorUnits) / 100,
                referenceDate: normalizedDay(expense.transactionDate),
                subject: .expense,
                suggestedText: "They owe me for this and will pay me next Friday.",
                goalID: nil
            ))
        }

        if items.isEmpty {
            let today = normalizedDay(Date())
            items += [
                ContextItem(
                    id: "sample-campus-job",
                    title: "Campus job",
                    subtitle: "+$650 recorded deposit",
                    amount: 650,
                    referenceDate: calendar.date(byAdding: .day, value: -6, to: today),
                    subject: .income,
                    suggestedText: "I get this every two weeks.",
                    goalID: nil
                ),
                ContextItem(
                    id: "sample-group-dinner",
                    title: "Group dinner",
                    subtitle: "-$180 recorded expense",
                    amount: 180,
                    referenceDate: calendar.date(byAdding: .day, value: -2, to: today),
                    subject: .expense,
                    suggestedText: "They owe me for this and will pay me next Friday.",
                    goalID: nil
                )
            ]
        }

        items += [
            ContextItem(
                id: "subscription",
                title: "Streaming subscription",
                subtitle: "$25 scheduled expense",
                amount: 25,
                referenceDate: calendar.date(byAdding: .day, value: 18, to: normalizedDay(Date())),
                subject: .expense,
                suggestedText: "This is optional and I can cancel it.",
                goalID: nil
            ),
            ContextItem(
                id: "miami-goal",
                title: "Miami",
                subtitle: "$900 flexible goal",
                amount: 900,
                referenceDate: calendar.date(byAdding: .day, value: 38, to: normalizedDay(Date())),
                subject: .goal,
                suggestedText: "This goal can wait if I really need it to.",
                goalID: miamiGoalID
            ),
            ContextItem(
                id: "reserve",
                title: "Cash reserve",
                subtitle: "Personal rule",
                amount: nil,
                referenceDate: nil,
                subject: .general,
                suggestedText: "I need to keep at least $500 untouched.",
                goalID: nil
            )
        ]

        return items
    }

    static func upcomingChanges(profile: FinancialProfile) -> [UpcomingChange] {
        let income = profile.incomeEvents
            .filter { $0.date > profile.asOfDate }
            .map { UpcomingChange(date: $0.date, label: $0.source, amount: $0.adjustedAmount) }
        let expenses = profile.expenseEvents
            .filter { $0.committed && $0.date > profile.asOfDate }
            .map { UpcomingChange(date: $0.date, label: $0.category, amount: -$0.amount) }
        let goals = profile.goals
            .filter { $0.priority == .mandatory && $0.deadline > profile.asOfDate && $0.remainingAmount > 0 }
            .map { UpcomingChange(date: $0.deadline, label: $0.name, amount: -$0.remainingAmount) }
        return (income + expenses + goals).sorted { $0.date < $1.date }
    }

    private static func weeklyHistory(from transactions: [FinanceCore.FinancialTransaction], asOf: Date) -> [WeeklySpendingSample] {
        let outflows = transactions.filter { $0.direction == .outflow }
        let grouped = Dictionary(grouping: outflows) {
            calendar.dateInterval(of: .weekOfYear, for: $0.transactionDate)?.start ?? normalizedDay($0.transactionDate)
        }
        let earliest = calendar.date(byAdding: .day, value: -42, to: asOf) ?? .distantPast
        return grouped
            .filter { week, _ in week >= earliest && week <= asOf }
            .map { week, transactions in
                WeeklySpendingSample(
                    weekStart: week,
                    totalVariableSpending: transactions.reduce(0) { $0 + Double($1.amountMinorUnits) / 100 }
                )
            }
            .sorted { $0.weekStart < $1.weekStart }
    }

    private static func fallbackWeeklyHistory(asOf: Date) -> [WeeklySpendingSample] {
        [220, 260, 245, 275, 230, 255].enumerated().map { index, amount in
            WeeklySpendingSample(
                weekStart: calendar.date(byAdding: .day, value: -7 * (5 - index), to: asOf) ?? asOf,
                totalVariableSpending: Double(amount)
            )
        }
    }

    private static func cleanLabel(_ transaction: FinanceCore.FinancialTransaction) -> String {
        let value = transaction.merchantName ?? transaction.transactionDescription
        let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "Bank transaction" : cleaned
    }

    private static func currency(_ value: Double) -> String {
        value.formatted(.currency(code: "USD").precision(.fractionLength(0)))
    }

    private static func shortDate(_ date: Date) -> String {
        date.formatted(.dateTime.month(.abbreviated).day())
    }
}

// MARK: - Shared presentation

private struct V2Background: View {
    var body: some View {
        LinearGradient(
            colors: [
                Color(red: 0.035, green: 0.07, blue: 0.13),
                Color(red: 0.055, green: 0.13, blue: 0.20),
                Color(red: 0.025, green: 0.05, blue: 0.10)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }
}

private struct V2Header: View {
    let eyebrow: String
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(eyebrow)
                .font(.caption.weight(.bold))
                .tracking(1.5)
                .foregroundStyle(.white.opacity(0.55))
            Text(title).font(.largeTitle.weight(.bold))
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.6))
        }
        .foregroundStyle(.white)
        .padding(.top, 8)
    }
}

private struct V2Explanation: View {
    let icon: String
    let title: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .frame(width: 34, height: 34)
                .background(.white.opacity(0.08), in: Circle())
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(text)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.52))
            }
        }
        .padding(16)
        .v2Card()
    }
}

private struct V2Unavailable: View {
    let text: String
    var body: some View {
        Label(text, systemImage: "exclamationmark.triangle")
            .font(.subheadline)
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .v2Card()
    }
}

private struct V2StatusPill: View {
    let status: FinancialHealthStatus
    var body: some View {
        Text(v2HealthTitle(status))
            .font(.caption.weight(.bold))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .foregroundStyle(v2HealthColor(status))
            .background(v2HealthColor(status).opacity(0.12), in: Capsule())
    }
}

private struct V2PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .foregroundStyle(.black)
            .background(.white.opacity(configuration.isPressed ? 0.78 : 1), in: RoundedRectangle(cornerRadius: 12))
    }
}

private extension View {
    func v2Card() -> some View {
        background(.white.opacity(0.065), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(.white.opacity(0.08), lineWidth: 1)
            }
    }
}

private func v2HealthColor(_ status: FinancialHealthStatus) -> Color {
    switch status {
    case .safe: return .green
    case .tight: return .orange
    case .notSafe: return .red
    }
}

private func v2HealthSymbol(_ status: FinancialHealthStatus) -> String {
    switch status {
    case .safe: return "checkmark.circle.fill"
    case .tight: return "exclamationmark.circle.fill"
    case .notSafe: return "xmark.octagon.fill"
    }
}

private func v2HealthTitle(_ status: FinancialHealthStatus) -> String {
    switch status {
    case .safe: return "Safe"
    case .tight: return "Tight"
    case .notSafe: return "Not safe"
    }
}

private func statusExplanation(_ status: FinancialHealthStatus) -> String {
    switch status {
    case .safe: return "Your projected path stays above the recommended protection level."
    case .tight: return "The plan stays above the hard minimum, but the recommended cushion gets thin."
    case .notSafe: return "At least one point in the plan drops below a protected minimum."
    }
}

private func v2PurchaseTitle(_ status: PurchaseStatus) -> String {
    switch status {
    case .safe: return "This purchase fits the plan"
    case .tight: return "Possible, but it makes the plan tight"
    case .notSafe: return "This purchase breaks a protected boundary"
    }
}

private func v2PurchaseReason(_ reason: PurchaseDecisionReason) -> String {
    switch reason {
    case .safe: return "The full future cash path remains above the recommended buffer."
    case .belowRecommendedBuffer: return "The purchase leaves less room than the recommended buffer at the tightest point."
    case .belowHardFloor: return "The purchase pushes the cash path below a protected minimum."
    }
}

private func v2MissingQuestion(_ field: QualitativeMissingField) -> String {
    switch field {
    case .repaymentDate: return "When do you expect to be paid back?"
    case .recurrenceCadence: return "How often does this repeat?"
    case .reserveAmount: return "How much cash do you want to keep untouched?"
    }
}
