import SwiftUI
import FinanceCore
import FinancialCore

struct ContentView: View {
    @EnvironmentObject private var bankStore: BankAccountStore
    @State private var profile: FinancialProfile
    @State private var selectedTab = CleanTab.home

    init() {
        let base = CleanData.profile(currentCash: nil, transactions: [], preserving: nil)
        _profile = State(initialValue: CleanPlanningStore.restore(into: base))
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            CleanHomeView(profile: profile, linked: bankStore.isLinked, phase: bankStore.phase) {
                selectedTab = .context
            }
            .tabItem { Label("Home", systemImage: "house.fill") }
            .tag(CleanTab.home)

            CleanCalendarView(profile: profile, linked: bankStore.isLinked)
                .tabItem { Label("Calendar", systemImage: "calendar") }
                .tag(CleanTab.calendar)

            CleanPlanView(profile: $profile) {
                selectedTab = .context
            }
            .tabItem { Label("Plan", systemImage: "list.bullet.rectangle") }
            .tag(CleanTab.plan)

            CleanWhatIfView(profile: profile, linked: bankStore.isLinked)
                .tabItem { Label("What If", systemImage: "slider.horizontal.3") }
                .tag(CleanTab.whatIf)

            CleanContextView(profile: $profile)
                .tabItem { Label("Context", systemImage: "text.bubble.fill") }
                .tag(CleanTab.context)
        }
        .tint(.white)
        .preferredColorScheme(.dark)
        .task { syncFromBank() }
        .onChange(of: bankStore.accounts) { _, _ in syncFromBank() }
        .onChange(of: bankStore.transactions) { _, _ in syncFromBank() }
        .onChange(of: CleanPlanningStore.fingerprint(profile)) { _, data in
            guard let data else { return }
            CleanPlanningStore.save(data)
        }
    }

    private func syncFromBank() {
        profile = CleanData.profile(
            currentCash: bankStore.isLinked ? bankStore.totalAvailableCash : nil,
            transactions: bankStore.transactions,
            preserving: profile
        )
    }
}

private enum CleanTab: Hashable {
    case home
    case calendar
    case plan
    case whatIf
    case context
}

private struct CleanHomeView: View {
    let profile: FinancialProfile
    let linked: Bool
    let phase: BankAccountStore.Phase
    let addContext: () -> Void

    private var dashboard: FinancialDashboardSnapshot? {
        guard linked else { return nil }
        return try? FinancialInsights.dashboard(
            profile: profile,
            through: CleanData.horizon(from: profile.asOfDate),
            calendar: CleanData.calendar
        )
    }

    var body: some View {
        CleanScreen(
            title: "Your money, with context",
            subtitle: linked
                ? "Your bank gives us the facts. Your plan adds what the bank cannot know yet."
                : "Connect a bank, then add what you expect to happen next."
        ) {
            bankStatusCard

            if let dashboard {
                VStack(alignment: .leading, spacing: 12) {
                    Text("SAFE TO SPEND").cleanEyebrow()
                    Text(dashboard.safeToSpendNow, format: .currency(code: "USD").precision(.fractionLength(0)))
                        .font(.system(size: 58, weight: .light, design: .rounded))
                        .monospacedDigit()
                    Text(cleanHealthExplanation(dashboard.horizonStatus))
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.62))
                }
                .padding(20)
                .cleanCard()

                HStack(spacing: 12) {
                    CleanMetric(title: "Bank cash", value: profile.currentCash)
                    CleanMetric(
                        title: "Protected",
                        value: max(0, profile.currentCash - dashboard.safeToSpendNow)
                    )
                }

                if dashboard.typicalWeeklySpending > 0 {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("WEEKLY PACE").cleanEyebrow()
                        Text(dashboard.recommendedWeeklySpendingLimit, format: .currency(code: "USD").precision(.fractionLength(0)))
                            .font(.title2.weight(.bold))
                        Text("Suggested weekly ceiling based on your recent spending and the plan ahead.")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.52))
                    }
                    .padding(18)
                    .cleanCard()
                }

                let upcoming = CleanData.upcoming(profile: profile)
                if upcoming.isEmpty {
                    CleanEmptyCard(
                        icon: "calendar.badge.plus",
                        title: "Nothing planned yet",
                        text: "Add rent, support from family, a reimbursement, a goal, or anything else you expect."
                    )
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("COMING UP").cleanEyebrow()
                        ForEach(Array(upcoming.prefix(4))) { item in
                            HStack(spacing: 12) {
                                Image(systemName: item.amount >= 0 ? "arrow.down.circle.fill" : "arrow.up.circle.fill")
                                    .foregroundStyle(item.amount >= 0 ? .green : .orange)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.title).font(.subheadline.weight(.semibold))
                                    Text("\(item.date.formatted(.dateTime.month(.abbreviated).day())) · \(item.detail)")
                                        .font(.caption)
                                        .foregroundStyle(.white.opacity(0.5))
                                }
                                Spacer()
                                Text(abs(item.amount), format: .currency(code: "USD").precision(.fractionLength(0)))
                                    .font(.headline)
                                    .monospacedDigit()
                            }
                        }
                    }
                    .padding(18)
                    .cleanCard()
                }

                Button(action: addContext) {
                    Label("Tell the app what's coming", systemImage: "plus.bubble.fill")
                }
                .buttonStyle(CleanPrimaryButtonStyle())
            } else {
                CleanEmptyCard(
                    icon: "building.columns.fill",
                    title: "Connect your bank first",
                    text: "Once connected, your real balance and transaction history become the base. No demo balance is shown as if it were yours."
                )
            }
        }
    }

    private var bankStatusCard: some View {
        HStack(spacing: 12) {
            Image(systemName: linked ? "checkmark.circle.fill" : "link.circle")
                .font(.title2)
                .foregroundStyle(linked ? .green : .white.opacity(0.75))
            VStack(alignment: .leading, spacing: 3) {
                Text(linked ? "Bank connected" : "No bank connected")
                    .font(.headline)
                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.52))
            }
            Spacer()
        }
        .padding(16)
        .cleanCard()
    }

    private var statusText: String {
        switch phase {
        case .idle: return "Use the bank button above to connect."
        case .loadingCache: return "Loading saved bank activity…"
        case .connecting: return "Refreshing accounts and transactions…"
        case .connected: return "Your bank data is feeding the plan."
        case .failed: return "Saved data is still available, but refresh needs attention."
        }
    }
}

private struct CleanCalendarView: View {
    let profile: FinancialProfile
    let linked: Bool

    private var points: [CashFlowPoint] {
        guard linked else { return [] }
        let end = min(
            CleanData.horizon(from: profile.asOfDate),
            CleanData.calendar.date(byAdding: .day, value: 30, to: profile.asOfDate) ?? profile.asOfDate
        )
        return (try? FinancialInsights.cashFlowTimeline(
            profile: profile,
            from: profile.asOfDate,
            through: end,
            calendar: CleanData.calendar
        )) ?? []
    }

    var body: some View {
        CleanScreen(
            title: "Future cash path",
            subtitle: "See what is coming and where your plan becomes comfortable, tight, or unsafe."
        ) {
            if !linked {
                CleanEmptyCard(
                    icon: "calendar",
                    title: "Connect a bank to build the path",
                    text: "The calendar uses your real cash balance plus the future items you add."
                )
            } else if CleanData.upcoming(profile: profile).isEmpty {
                CleanEmptyCard(
                    icon: "calendar.badge.plus",
                    title: "No future items yet",
                    text: "Add expected money, bills, reimbursements, or goals from Context."
                )
            } else {
                ForEach(CleanData.upcoming(profile: profile)) { item in
                    HStack(spacing: 12) {
                        VStack(spacing: 2) {
                            Text(item.date, format: .dateTime.month(.abbreviated))
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.white.opacity(0.48))
                            Text(item.date, format: .dateTime.day())
                                .font(.headline)
                        }
                        .frame(width: 42)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.title).font(.headline)
                            Text(item.detail)
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.5))
                        }
                        Spacer()
                        Text(item.amount, format: .currency(code: "USD").precision(.fractionLength(0)))
                            .font(.headline)
                            .foregroundStyle(item.amount >= 0 ? .green : .orange)
                            .monospacedDigit()
                    }
                    .padding(16)
                    .cleanCard()
                }

                if let tightest = points.min(by: { $0.projectedCash < $1.projectedCash }) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("LOWEST PROJECTED CASH").cleanEyebrow()
                        Text(tightest.projectedCash, format: .currency(code: "USD").precision(.fractionLength(0)))
                            .font(.title2.weight(.bold))
                        Text("Around \(tightest.date.formatted(.dateTime.month(.wide).day())). \(cleanHealthExplanation(tightest.status))")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.58))
                    }
                    .padding(18)
                    .cleanCard()
                }
            }
        }
    }
}

private struct CleanPlanView: View {
    @Binding var profile: FinancialProfile
    let addContext: () -> Void
    @State private var editing: PlanEditorTarget?

    private var futureIncome: [IncomeEvent] {
        profile.incomeEvents
            .filter { $0.date > profile.asOfDate && CleanData.isUserPlan($0.planningSource) }
            .sorted { $0.date < $1.date }
    }

    private var futureExpenses: [ExpenseEvent] {
        profile.expenseEvents
            .filter { $0.date > profile.asOfDate && CleanData.isUserPlan($0.planningSource) }
            .sorted { $0.date < $1.date }
    }

    var body: some View {
        CleanScreen(
            title: "Your editable plan",
            subtitle: "Future assumptions are yours. Change them whenever reality changes."
        ) {
            reserveCard

            if futureIncome.isEmpty && futureExpenses.isEmpty && profile.goals.isEmpty {
                CleanEmptyCard(
                    icon: "list.bullet.rectangle",
                    title: "Your plan is empty",
                    text: "Add what you expect to happen with your money in normal language."
                )
            }

            if !futureIncome.isEmpty {
                planSection(title: "EXPECTED MONEY") {
                    ForEach(futureIncome) { event in
                        planRow(
                            title: event.source,
                            amount: event.amount,
                            date: event.date,
                            positive: true,
                            detail: CleanData.incomeDetail(event)
                        ) {
                            editing = .income(event.id)
                        }
                    }
                }
            }

            if !futureExpenses.isEmpty {
                planSection(title: "UPCOMING EXPENSES") {
                    ForEach(futureExpenses) { event in
                        planRow(
                            title: event.category,
                            amount: event.amount,
                            date: event.date,
                            positive: false,
                            detail: CleanData.expenseDetail(event)
                        ) {
                            editing = .expense(event.id)
                        }
                    }
                }
            }

            if !profile.goals.isEmpty {
                planSection(title: "GOALS") {
                    ForEach(profile.goals) { goal in
                        planRow(
                            title: goal.name,
                            amount: goal.remainingAmount,
                            date: goal.deadline,
                            positive: false,
                            detail: goal.priority == .mandatory ? "Must happen" : "Flexible"
                        ) {
                            editing = .goal(goal.id)
                        }
                    }
                }
            }

            Button(action: addContext) {
                Label("Add something in Context", systemImage: "plus")
            }
            .buttonStyle(CleanPrimaryButtonStyle())
        }
        .sheet(item: $editing) { target in
            CleanPlanEditor(profile: $profile, target: target)
        }
    }

    private var reserveCard: some View {
        let amount = FinancialEngine.personalReserve(profile: profile, on: profile.asOfDate)
        return Button { editing = .reserve } label: {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("PERSONAL RESERVE").cleanEyebrow()
                    Text(amount, format: .currency(code: "USD").precision(.fractionLength(0)))
                        .font(.title2.weight(.bold))
                    Text(amount > 0
                         ? "Tap to edit the cash you do not want to touch."
                         : "Tap to set money you want to keep untouched.")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.52))
                }
                Spacer()
                Image(systemName: "pencil.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.white.opacity(0.7))
            }
            .padding(18)
            .cleanCard()
        }
        .buttonStyle(.plain)
    }

    private func planSection<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).cleanEyebrow()
            content()
        }
    }

    private func planRow(
        title: String,
        amount: Double,
        date: Date,
        positive: Bool,
        detail: String,
        edit: @escaping () -> Void
    ) -> some View {
        Button(action: edit) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.headline)
                    Text("\(date.formatted(.dateTime.month(.abbreviated).day())) · \(detail)")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.5))
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 5) {
                    Text(amount, format: .currency(code: "USD").precision(.fractionLength(0)))
                        .font(.headline)
                        .foregroundStyle(positive ? .green : .orange)
                    Text("Edit")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.55))
                }
            }
            .padding(16)
            .cleanCard()
        }
        .buttonStyle(.plain)
    }
}

private struct CleanWhatIfView: View {
    let profile: FinancialProfile
    let linked: Bool
    @State private var amountText = "500"

    private var amount: Double {
        Double(amountText.replacingOccurrences(of: ",", with: "")) ?? 0
    }

    private var analysis: PurchaseWhatIfAnalysis? {
        guard linked, amount >= 0 else { return nil }
        return try? FinancialInsights.analyzePurchaseWhatIf(
            profile: profile,
            amount: amount,
            purchaseDate: profile.asOfDate,
            planningHorizon: CleanData.horizon(from: profile.asOfDate),
            calendar: CleanData.calendar
        )
    }

    var body: some View {
        CleanScreen(
            title: "What if I spend this?",
            subtitle: "Try a purchase without changing your real plan."
        ) {
            if !linked {
                CleanEmptyCard(
                    icon: "cart",
                    title: "Connect a bank first",
                    text: "What If needs a real current cash balance."
                )
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    Text("PURCHASE AMOUNT").cleanEyebrow()
                    HStack {
                        Text("$")
                            .font(.title2)
                            .foregroundStyle(.white.opacity(0.55))
                        TextField("500", text: $amountText)
                            .keyboardType(.decimalPad)
                            .font(.system(size: 44, weight: .light, design: .rounded))
                            .monospacedDigit()
                    }
                }
                .padding(20)
                .cleanCard()

                if let analysis {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(cleanPurchaseTitle(analysis.purchaseAssessment.status))
                            .font(.title2.weight(.bold))
                        Text(cleanPurchaseReason(analysis.purchaseExplanation.reason))
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.62))

                        Divider().overlay(.white.opacity(0.08))

                        HStack {
                            Text("Tightest date")
                                .foregroundStyle(.white.opacity(0.55))
                            Spacer()
                            Text(
                                analysis.purchaseExplanation.limitingDate,
                                format: .dateTime.month(.abbreviated).day()
                            )
                            .fontWeight(.semibold)
                        }
                        .font(.subheadline)

                        if let goal = analysis.worsenedGoals.first?.goal {
                            Text("This would also make your \(goal.name) goal harder to reach.")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }
                    .padding(18)
                    .cleanCard()
                }
            }
        }
    }
}

private struct CleanContextView: View {
    @Binding var profile: FinancialProfile
    @State private var text = ""
    @State private var form: ContextForm?
    @State private var message: String?

    var body: some View {
        CleanScreen(
            title: "Tell us what the bank can't know",
            subtitle: "Write what you expect in English or Spanish. Review the details before anything changes."
        ) {
            VStack(alignment: .leading, spacing: 12) {
                Text("WHAT'S GOING TO HAPPEN?").cleanEyebrow()
                TextEditor(text: $text)
                    .frame(minHeight: 120)
                    .scrollContentBackground(.hidden)
                    .padding(10)
                    .background(.black.opacity(0.18), in: RoundedRectangle(cornerRadius: 14))

                Text("Examples: “Mi familia me manda $2,000 el 15 de octubre, probablemente 70%.” · “Tengo que pagar $900 de renta el 1 de octubre cada mes.”")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.48))

                Button("Review what I wrote") { analyze() }
                    .buttonStyle(CleanPrimaryButtonStyle())
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(18)
            .cleanCard()

            if let binding = Binding($form) {
                ContextReviewCard(form: binding, asOfDate: profile.asOfDate) {
                    save(binding.wrappedValue)
                }
            }

            if let message {
                Label(message, systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .cleanCard()
            }

            CleanEmptyCard(
                icon: "lock.shield.fill",
                title: "Important details stay explicit",
                text: "If the amount, date, or type is unclear, you fill it in before saving. Small wording differences never change bank facts."
            )
        }
    }

    private func analyze() {
        let draft = NaturalLanguagePlanningInterpreter.parse(
            text,
            asOfDate: profile.asOfDate,
            calendar: CleanData.calendar
        )
        form = ContextForm(draft: draft, asOfDate: profile.asOfDate)
        message = nil
    }

    private func save(_ form: ContextForm) {
        guard CleanData.apply(form: form, to: &profile) else { return }
        message = "Saved. Your plan and safe-to-spend now use this context."
        text = ""
        self.form = nil
    }
}

private struct ContextReviewCard: View {
    @Binding var form: ContextForm
    let asOfDate: Date
    let save: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("REVIEW BEFORE SAVING").cleanEyebrow()

            Picker("Type", selection: $form.kind) {
                Text("Choose type").tag(Optional<NaturalPlanKind>.none)
                Text("Money coming in").tag(Optional(NaturalPlanKind.income))
                Text("Expense").tag(Optional(NaturalPlanKind.expense))
                Text("Goal").tag(Optional(NaturalPlanKind.goal))
                Text("Cash reserve").tag(Optional(NaturalPlanKind.reserve))
            }
            .pickerStyle(.menu)

            TextField("Name", text: $form.title)
                .textFieldStyle(.roundedBorder)
            TextField("Amount", text: $form.amountText)
                .keyboardType(.decimalPad)
                .textFieldStyle(.roundedBorder)

            if form.kind != .reserve {
                if form.hasDate {
                    DatePicker(
                        "When",
                        selection: $form.date,
                        in: CleanData.tomorrow(after: asOfDate)...,
                        displayedComponents: .date
                    )
                } else {
                    HStack {
                        Label("A future date is still needed", systemImage: "calendar.badge.exclamationmark")
                            .font(.subheadline)
                            .foregroundStyle(.yellow)
                        Spacer()
                        Button("Add date") {
                            form.date = CleanData.tomorrow(after: asOfDate)
                            form.hasDate = true
                        }
                    }
                }
            }

            if form.kind == .income || form.kind == .expense {
                Picker("Repeats", selection: $form.cadence) {
                    Text("One time").tag(Optional<RecurrenceCadence>.none)
                    Text("Every week").tag(Optional(RecurrenceCadence.weekly))
                    Text("Every 2 weeks").tag(Optional(RecurrenceCadence.biweekly))
                    Text("Every month").tag(Optional(RecurrenceCadence.monthly))
                }
                .pickerStyle(.menu)

                if form.cadence != nil {
                    Toggle("Set an end date", isOn: $form.hasEndDate)
                    if form.hasEndDate {
                        DatePicker(
                            "Ends",
                            selection: $form.endDate,
                            in: form.date...,
                            displayedComponents: .date
                        )
                    }
                }
            }

            if form.kind == .income {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("How certain is it?")
                        Spacer()
                        Text(form.confidence, format: .percent.precision(.fractionLength(0)))
                            .fontWeight(.semibold)
                    }
                    Slider(value: $form.confidence, in: 0...1, step: 0.05)
                    HStack {
                        Button("Possible 30%") { form.confidence = 0.3 }
                        Spacer()
                        Button("Likely 70%") { form.confidence = 0.7 }
                        Spacer()
                        Button("Confirmed") { form.confidence = 1 }
                    }
                    .font(.caption)
                }
            }

            if form.kind == .expense {
                Toggle("Include this payment in my baseline plan", isOn: $form.committed)
                Toggle("This is essential", isOn: $form.essential)
                if !form.committed {
                    Text("Optional items stay visible in your plan but do not reduce Safe to Spend until you include them in the baseline.")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.5))
                }
            }

            if form.kind == .goal {
                Picker("Priority", selection: $form.goalPriority) {
                    Text("Flexible").tag(GoalPriority.flexible)
                    Text("Must happen").tag(GoalPriority.mandatory)
                }
                .pickerStyle(.segmented)
            }

            Button("Save to my plan", action: save)
                .buttonStyle(CleanPrimaryButtonStyle())
                .disabled(!form.canSave(asOfDate: asOfDate))
        }
        .padding(18)
        .cleanCard()
    }
}

private enum PlanEditorTarget: Identifiable {
    case income(UUID)
    case expense(UUID)
    case goal(UUID)
    case reserve

    var id: String {
        switch self {
        case .income(let id): return "income-\(id)"
        case .expense(let id): return "expense-\(id)"
        case .goal(let id): return "goal-\(id)"
        case .reserve: return "reserve"
        }
    }
}

private struct CleanPlanEditor: View {
    @Binding var profile: FinancialProfile
    let target: PlanEditorTarget
    @Environment(\.dismiss) private var dismiss

    @State private var title: String
    @State private var amountText: String
    @State private var date: Date
    @State private var cadence: RecurrenceCadence?
    @State private var hasEndDate: Bool
    @State private var endDate: Date
    @State private var confidence: Double
    @State private var committed: Bool
    @State private var essential: Bool
    @State private var goalPriority: GoalPriority

    init(profile: Binding<FinancialProfile>, target: PlanEditorTarget) {
        self._profile = profile
        self.target = target
        let p = profile.wrappedValue
        let fallbackDate = CleanData.tomorrow(after: p.asOfDate)

        switch target {
        case .income(let id):
            let event = p.incomeEvents.first(where: { $0.id == id })!
            let end = event.recurrenceRule?.endDate
            _title = State(initialValue: event.source)
            _amountText = State(initialValue: cleanNumber(event.amount))
            _date = State(initialValue: event.recurrenceRule?.firstOccurrence ?? event.date)
            _cadence = State(initialValue: event.recurrenceRule.flatMap { CleanData.legacyCadence($0.cadence) })
            _hasEndDate = State(initialValue: end != nil)
            _endDate = State(initialValue: end ?? event.date)
            _confidence = State(initialValue: event.confidence)
            _committed = State(initialValue: true)
            _essential = State(initialValue: false)
            _goalPriority = State(initialValue: .flexible)

        case .expense(let id):
            let event = p.expenseEvents.first(where: { $0.id == id })!
            let end = event.recurrenceRule?.endDate
            _title = State(initialValue: event.category)
            _amountText = State(initialValue: cleanNumber(event.amount))
            _date = State(initialValue: event.recurrenceRule?.firstOccurrence ?? event.date)
            _cadence = State(initialValue: event.recurrenceRule.flatMap { CleanData.legacyCadence($0.cadence) })
            _hasEndDate = State(initialValue: end != nil)
            _endDate = State(initialValue: end ?? event.date)
            _confidence = State(initialValue: 1)
            _committed = State(initialValue: event.committed)
            _essential = State(initialValue: event.essential)
            _goalPriority = State(initialValue: .flexible)

        case .goal(let id):
            let goal = p.goals.first(where: { $0.id == id })!
            _title = State(initialValue: goal.name)
            _amountText = State(initialValue: cleanNumber(goal.targetAmount))
            _date = State(initialValue: max(goal.deadline, fallbackDate))
            _cadence = State(initialValue: nil)
            _hasEndDate = State(initialValue: false)
            _endDate = State(initialValue: fallbackDate)
            _confidence = State(initialValue: 1)
            _committed = State(initialValue: true)
            _essential = State(initialValue: true)
            _goalPriority = State(initialValue: goal.priority)

        case .reserve:
            let reserve = p.personalReserveSteps.last
            _title = State(initialValue: "Cash reserve")
            _amountText = State(initialValue: cleanNumber(FinancialEngine.personalReserve(profile: p, on: p.asOfDate)))
            _date = State(initialValue: reserve?.effectiveDate ?? p.asOfDate)
            _cadence = State(initialValue: nil)
            _hasEndDate = State(initialValue: false)
            _endDate = State(initialValue: fallbackDate)
            _confidence = State(initialValue: 1)
            _committed = State(initialValue: true)
            _essential = State(initialValue: true)
            _goalPriority = State(initialValue: .mandatory)
        }
    }

    private var amount: Double? {
        Double(amountText.replacingOccurrences(of: ",", with: ""))
    }

    var body: some View {
        NavigationStack {
            Form {
                if case .reserve = target {
                    Section("Reserve") {
                        TextField("Amount", text: $amountText)
                            .keyboardType(.decimalPad)
                        DatePicker("Effective from", selection: $date, displayedComponents: .date)
                    }
                } else {
                    Section("Details") {
                        TextField("Name", text: $title)
                        TextField("Amount", text: $amountText)
                            .keyboardType(.decimalPad)
                        DatePicker(
                            "Date",
                            selection: $date,
                            in: CleanData.tomorrow(after: profile.asOfDate)...,
                            displayedComponents: .date
                        )
                    }
                }

                switch target {
                case .income:
                    recurrenceSection
                    Section("Income") {
                        Slider(value: $confidence, in: 0...1, step: 0.05) {
                            Text("Confidence")
                        }
                        Text("Confidence: \(confidence.formatted(.percent.precision(.fractionLength(0))))")
                    }

                case .expense:
                    recurrenceSection
                    Section("Expense") {
                        Toggle("Include in baseline plan", isOn: $committed)
                        Toggle("This is essential", isOn: $essential)
                    }

                case .goal:
                    Section("Goal") {
                        Picker("Priority", selection: $goalPriority) {
                            Text("Flexible").tag(GoalPriority.flexible)
                            Text("Must happen").tag(GoalPriority.mandatory)
                        }
                    }

                case .reserve:
                    EmptyView()
                }

                Section {
                    Button("Save changes") { saveChanges() }
                        .disabled(!canSave)

                    if case .reserve = target {
                        Button("Clear reserve", role: .destructive) {
                            profile.personalReserveSteps.removeAll()
                            dismiss()
                        }
                    } else {
                        Button("Delete from plan", role: .destructive) {
                            deleteTarget()
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle("Edit plan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private var recurrenceSection: some View {
        Section("Repeats") {
            Picker("Frequency", selection: $cadence) {
                Text("One time").tag(Optional<RecurrenceCadence>.none)
                Text("Every week").tag(Optional(RecurrenceCadence.weekly))
                Text("Every 2 weeks").tag(Optional(RecurrenceCadence.biweekly))
                Text("Every month").tag(Optional(RecurrenceCadence.monthly))
            }

            if cadence != nil {
                Toggle("Set an end date", isOn: $hasEndDate)
                if hasEndDate {
                    DatePicker("Ends", selection: $endDate, in: date..., displayedComponents: .date)
                }
            }
        }
    }

    private var targetNeedsTitle: Bool {
        if case .reserve = target { return false }
        return true
    }

    private var canSave: Bool {
        guard let amount, amount >= 0 else { return false }
        if targetNeedsTitle && title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return false }
        if cadence != nil && hasEndDate && endDate < date { return false }
        return true
    }

    private func saveChanges() {
        guard let amount, amount >= 0 else { return }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let recurrenceEnd = cadence == nil || !hasEndDate ? nil : endDate

        switch target {
        case .income(let id):
            guard let old = profile.incomeEvents.first(where: { $0.id == id }) else { return }
            CleanData.removeIncomeSeries(old, from: &profile)
            CleanData.addIncome(
                title: trimmed,
                amount: amount,
                date: date,
                cadence: cadence,
                endDate: recurrenceEnd,
                confidence: confidence,
                to: &profile
            )

        case .expense(let id):
            guard let old = profile.expenseEvents.first(where: { $0.id == id }) else { return }
            CleanData.removeExpenseSeries(old, from: &profile)
            CleanData.addExpense(
                title: trimmed,
                amount: amount,
                date: date,
                cadence: cadence,
                endDate: recurrenceEnd,
                committed: committed,
                essential: essential,
                to: &profile
            )

        case .goal(let id):
            guard let index = profile.goals.firstIndex(where: { $0.id == id }) else { return }
            profile.goals[index] = Goal(
                id: id,
                name: trimmed,
                targetAmount: amount,
                amountAlreadyPaid: profile.goals[index].amountAlreadyPaid,
                deadline: date,
                priority: goalPriority
            )

        case .reserve:
            profile.personalReserveSteps = [
                PersonalReserveStep(
                    effectiveDate: CleanData.day(date),
                    minimumCash: amount,
                    note: "Personal reserve"
                )
            ]
        }

        dismiss()
    }

    private func deleteTarget() {
        switch target {
        case .income(let id):
            if let event = profile.incomeEvents.first(where: { $0.id == id }) {
                CleanData.removeIncomeSeries(event, from: &profile)
            }
        case .expense(let id):
            if let event = profile.expenseEvents.first(where: { $0.id == id }) {
                CleanData.removeExpenseSeries(event, from: &profile)
            }
        case .goal(let id):
            profile.goals.removeAll { $0.id == id }
        case .reserve:
            profile.personalReserveSteps.removeAll()
        }
    }
}

private struct ContextForm {
    var kind: NaturalPlanKind?
    var title: String
    var amountText: String
    var date: Date
    var hasDate: Bool
    var cadence: RecurrenceCadence?
    var hasEndDate: Bool
    var endDate: Date
    var confidence: Double
    var committed: Bool
    var essential: Bool
    var goalPriority: GoalPriority

    init(draft: NaturalPlanDraft, asOfDate: Date) {
        kind = draft.kind
        title = draft.title
        amountText = draft.amount.map(cleanNumber) ?? ""

        let tomorrow = CleanData.tomorrow(after: asOfDate)
        if let draftDate = draft.date, draftDate > asOfDate {
            date = CleanData.day(draftDate)
            hasDate = true
        } else {
            date = tomorrow
            hasDate = draft.kind == .reserve
        }

        cadence = draft.cadence
        hasEndDate = false
        endDate = CleanData.calendar.date(byAdding: .month, value: 3, to: date) ?? date
        confidence = draft.confidence
        committed = draft.committed
        essential = draft.essential
        goalPriority = draft.goalPriority
    }

    var amount: Double? {
        Double(amountText.replacingOccurrences(of: ",", with: ""))
    }

    func canSave(asOfDate: Date) -> Bool {
        guard let kind, let amount, amount >= 0 else { return false }
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        if kind != .reserve {
            guard hasDate, date > asOfDate else { return false }
        }
        if cadence != nil && hasEndDate && endDate < date { return false }
        return true
    }
}

private enum CleanPlanningStore {
    private static let key = "finanzas2026.user-planning.v1"

    private struct Snapshot: Codable {
        let version: Int
        let personalReserveSteps: [PersonalReserveStep]
        let institutionalMinimums: [InstitutionalMinimum]
        let incomeEvents: [IncomeEvent]
        let expenseEvents: [ExpenseEvent]
        let goals: [Goal]
        let spendingPolicy: SpendingPolicy
    }

    static func fingerprint(_ profile: FinancialProfile) -> Data? {
        try? JSONEncoder().encode(snapshot(from: profile))
    }

    static func save(_ data: Data) {
        UserDefaults.standard.set(data, forKey: key)
    }

    static func restore(into base: FinancialProfile) -> FinancialProfile {
        guard
            let data = UserDefaults.standard.data(forKey: key),
            let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data),
            snapshot.version == 1
        else {
            return base
        }

        var restored = base
        restored.personalReserveSteps = snapshot.personalReserveSteps
        restored.institutionalMinimums = snapshot.institutionalMinimums
        restored.incomeEvents += snapshot.incomeEvents.filter { $0.date > base.asOfDate }
        restored.expenseEvents += snapshot.expenseEvents.filter { $0.date > base.asOfDate }
        restored.goals = snapshot.goals
        restored.spendingPolicy = snapshot.spendingPolicy
        return restored
    }

    private static func snapshot(from profile: FinancialProfile) -> Snapshot {
        Snapshot(
            version: 1,
            personalReserveSteps: profile.personalReserveSteps,
            institutionalMinimums: profile.institutionalMinimums,
            incomeEvents: profile.incomeEvents.filter {
                $0.date > profile.asOfDate && CleanData.isUserPlan($0.planningSource)
            },
            expenseEvents: profile.expenseEvents.filter {
                $0.date > profile.asOfDate && CleanData.isUserPlan($0.planningSource)
            },
            goals: profile.goals,
            spendingPolicy: profile.spendingPolicy
        )
    }
}

private enum CleanData {
    static var calendar: Calendar {
        var value = Calendar.autoupdatingCurrent
        value.timeZone = .autoupdatingCurrent
        return value
    }

    static func day(_ date: Date) -> Date {
        calendar.startOfDay(for: date)
    }

    static func tomorrow(after date: Date) -> Date {
        calendar.date(byAdding: .day, value: 1, to: day(date)) ?? date
    }

    static func horizon(from date: Date) -> Date {
        calendar.date(byAdding: .day, value: 90, to: day(date)) ?? date
    }

    static func isUserPlan(_ source: PlanningEventSource?) -> Bool {
        source == .manual || source == .planned
    }

    struct UpcomingItem: Identifiable {
        let id: String
        let date: Date
        let title: String
        let amount: Double
        let detail: String
    }

    static func profile(
        currentCash: Double?,
        transactions: [FinanceCore.FinancialTransaction],
        preserving old: FinancialProfile?
    ) -> FinancialProfile {
        let asOf = day(Date())
        let nextDay = tomorrow(after: asOf)
        let usable = transactions.filter {
            !$0.isPending &&
            !$0.isTransfer &&
            $0.transactionDate < nextDay
        }

        let historicalIncome = usable
            .filter { $0.direction == .inflow }
            .map { tx in
                IncomeEvent(
                    amount: abs(Double(tx.amountMinorUnits)) / 100,
                    date: day(tx.transactionDate),
                    source: label(tx),
                    type: .oneTime,
                    confidence: 1,
                    planningSource: .bank,
                    planningStatus: .completed
                )
            }

        let historicalExpenses = usable
            .filter { $0.direction == .outflow }
            .map { tx in
                ExpenseEvent(
                    amount: abs(Double(tx.amountMinorUnits)) / 100,
                    date: day(tx.transactionDate),
                    category: label(tx),
                    essential: false,
                    committed: false,
                    merchantIdentity: tx.merchantName,
                    planningSource: .bank,
                    planningStatus: .completed
                )
            }

        let manualIncome = old?.incomeEvents.filter {
            $0.date > asOf && isUserPlan($0.planningSource)
        } ?? []
        let manualExpenses = old?.expenseEvents.filter {
            $0.date > asOf && isUserPlan($0.planningSource)
        } ?? []

        return FinancialProfile(
            currentCash: currentCash ?? 0,
            asOfDate: asOf,
            personalReserveSteps: old?.personalReserveSteps ?? [],
            institutionalMinimums: old?.institutionalMinimums ?? [],
            incomeEvents: historicalIncome + manualIncome,
            expenseEvents: historicalExpenses + manualExpenses,
            goals: old?.goals ?? [],
            weeklySpendingHistory: history(usable, asOf),
            spendingPolicy: old?.spendingPolicy
                ?? SpendingPolicy(lookbackWeeks: 6, bufferWeeks: 2, manualMinimumBuffer: 0)
        )
    }

    static func apply(form: ContextForm, to profile: inout FinancialProfile) -> Bool {
        guard let kind = form.kind, let amount = form.amount, amount >= 0 else { return false }
        let title = form.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let recurrenceEnd = form.cadence == nil || !form.hasEndDate ? nil : form.endDate

        switch kind {
        case .income:
            guard form.hasDate, form.date > profile.asOfDate else { return false }
            addIncome(
                title: title,
                amount: amount,
                date: form.date,
                cadence: form.cadence,
                endDate: recurrenceEnd,
                confidence: form.confidence,
                to: &profile
            )

        case .expense:
            guard form.hasDate, form.date > profile.asOfDate else { return false }
            addExpense(
                title: title,
                amount: amount,
                date: form.date,
                cadence: form.cadence,
                endDate: recurrenceEnd,
                committed: form.committed,
                essential: form.essential,
                to: &profile
            )

        case .goal:
            guard form.hasDate, form.date > profile.asOfDate else { return false }
            profile.goals.append(
                Goal(
                    name: title,
                    targetAmount: amount,
                    deadline: day(form.date),
                    priority: form.goalPriority
                )
            )

        case .reserve:
            profile.personalReserveSteps = [
                PersonalReserveStep(
                    effectiveDate: profile.asOfDate,
                    minimumCash: amount,
                    note: "Personal reserve"
                )
            ]
        }

        return true
    }

    static func addIncome(
        title: String,
        amount: Double,
        date: Date,
        cadence: RecurrenceCadence?,
        endDate: Date?,
        confidence: Double,
        to profile: inout FinancialProfile
    ) {
        let first = day(date)
        let dates = occurrenceDates(
            first: first,
            cadence: cadence,
            through: min(endDate ?? horizon(from: profile.asOfDate), horizon(from: profile.asOfDate))
        )
        let rule = cadence.map {
            RecurrenceRule(
                cadence: PlanningRecurrenceCadence($0),
                firstOccurrence: first,
                endDate: endDate.map(day)
            )
        }

        for occurrence in dates where occurrence > profile.asOfDate {
            profile.incomeEvents.append(
                IncomeEvent(
                    amount: amount,
                    date: occurrence,
                    source: title,
                    type: cadence == nil ? (confidence < 0.999 ? .irregular : .oneTime) : .recurring,
                    confidence: confidence,
                    recurrenceRule: rule,
                    planningSource: .manual,
                    planningStatus: .planned
                )
            )
        }
    }

    static func addExpense(
        title: String,
        amount: Double,
        date: Date,
        cadence: RecurrenceCadence?,
        endDate: Date?,
        committed: Bool,
        essential: Bool,
        to profile: inout FinancialProfile
    ) {
        let first = day(date)
        let dates = occurrenceDates(
            first: first,
            cadence: cadence,
            through: min(endDate ?? horizon(from: profile.asOfDate), horizon(from: profile.asOfDate))
        )
        let rule = cadence.map {
            RecurrenceRule(
                cadence: PlanningRecurrenceCadence($0),
                firstOccurrence: first,
                endDate: endDate.map(day)
            )
        }

        for occurrence in dates where occurrence > profile.asOfDate {
            profile.expenseEvents.append(
                ExpenseEvent(
                    amount: amount,
                    date: occurrence,
                    category: title,
                    essential: essential,
                    committed: committed,
                    recurrenceRule: rule,
                    planningSource: .manual,
                    planningStatus: .planned
                )
            )
        }
    }

    static func removeIncomeSeries(_ event: IncomeEvent, from profile: inout FinancialProfile) {
        if let first = event.recurrenceRule?.firstOccurrence {
            profile.incomeEvents.removeAll {
                isUserPlan($0.planningSource) &&
                $0.source == event.source &&
                $0.recurrenceRule?.firstOccurrence == first
            }
        } else {
            profile.incomeEvents.removeAll { $0.id == event.id }
        }
    }

    static func removeExpenseSeries(_ event: ExpenseEvent, from profile: inout FinancialProfile) {
        if let first = event.recurrenceRule?.firstOccurrence {
            profile.expenseEvents.removeAll {
                isUserPlan($0.planningSource) &&
                $0.category == event.category &&
                $0.recurrenceRule?.firstOccurrence == first
            }
        } else {
            profile.expenseEvents.removeAll { $0.id == event.id }
        }
    }

    static func legacyCadence(_ cadence: PlanningRecurrenceCadence) -> RecurrenceCadence? {
        switch cadence {
        case .weekly: return .weekly
        case .biweekly: return .biweekly
        case .monthly: return .monthly
        case .custom: return nil
        }
    }

    static func occurrenceDates(
        first: Date,
        cadence: RecurrenceCadence?,
        through end: Date
    ) -> [Date] {
        guard end >= first else { return [] }
        guard let cadence else { return [day(first)] }
        return (try? FinancialScheduleBuilder.dates(
            startingOn: day(first),
            through: day(end),
            cadence: cadence,
            calendar: calendar
        )) ?? [day(first)]
    }

    static func upcoming(profile: FinancialProfile) -> [UpcomingItem] {
        let incomes = profile.incomeEvents
            .filter { $0.date > profile.asOfDate && isUserPlan($0.planningSource) }
            .map {
                UpcomingItem(
                    id: "i-\($0.id)",
                    date: $0.date,
                    title: $0.source,
                    amount: $0.adjustedAmount,
                    detail: incomeDetail($0)
                )
            }

        let expenses = profile.expenseEvents
            .filter { $0.date > profile.asOfDate && isUserPlan($0.planningSource) }
            .map {
                UpcomingItem(
                    id: "e-\($0.id)",
                    date: $0.date,
                    title: $0.category,
                    amount: -$0.amount,
                    detail: expenseDetail($0)
                )
            }

        let goals = profile.goals
            .filter { $0.remainingAmount > 0 }
            .map {
                UpcomingItem(
                    id: "g-\($0.id)",
                    date: $0.deadline,
                    title: $0.name,
                    amount: -$0.remainingAmount,
                    detail: $0.priority == .mandatory ? "Must happen" : "Flexible goal"
                )
            }

        return (incomes + expenses + goals).sorted { $0.date < $1.date }
    }

    static func incomeDetail(_ event: IncomeEvent) -> String {
        if event.type == .recurring {
            return recurrenceText(event.recurrenceRule)
        }
        if event.confidence < 0.999 {
            return "\(event.confidence.formatted(.percent.precision(.fractionLength(0)))) confidence"
        }
        return "One time"
    }

    static func expenseDetail(_ event: ExpenseEvent) -> String {
        let payment = event.committed ? "Included in baseline" : "Optional"
        if event.recurrenceRule != nil {
            return "\(payment) · \(recurrenceText(event.recurrenceRule))"
        }
        return payment
    }

    private static func recurrenceText(_ rule: RecurrenceRule?) -> String {
        guard let rule else { return "One time" }
        let cadence: String
        switch rule.cadence {
        case .weekly: cadence = "Every week"
        case .biweekly: cadence = "Every 2 weeks"
        case .monthly: cadence = "Every month"
        case .custom: cadence = "Repeating"
        }

        if let endDate = rule.endDate {
            return "\(cadence) until \(endDate.formatted(.dateTime.month(.abbreviated).day()))"
        }
        return cadence
    }

    private static func history(
        _ transactions: [FinanceCore.FinancialTransaction],
        _ asOf: Date
    ) -> [WeeklySpendingSample] {
        let outgoing = transactions.filter { $0.direction == .outflow }
        let grouped = Dictionary(grouping: outgoing) {
            calendar.dateInterval(of: .weekOfYear, for: $0.transactionDate)?.start
                ?? day($0.transactionDate)
        }
        let earliest = calendar.date(byAdding: .day, value: -42, to: asOf) ?? .distantPast

        return grouped
            .filter { $0.key >= earliest && $0.key <= asOf }
            .map { key, values in
                WeeklySpendingSample(
                    weekStart: key,
                    totalVariableSpending: values.reduce(0) {
                        $0 + abs(Double($1.amountMinorUnits)) / 100
                    }
                )
            }
            .sorted { $0.weekStart < $1.weekStart }
    }

    private static func label(_ transaction: FinanceCore.FinancialTransaction) -> String {
        if let merchant = transaction.merchantName,
           !merchant.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return merchant
        }
        if !transaction.description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return transaction.description
        }
        return transaction.direction == .inflow ? "Money received" : "Purchase"
    }
}

private struct CleanScreen<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let content: Content

    init(
        title: String,
        subtitle: String,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.035, green: 0.055, blue: 0.09),
                    Color(red: 0.02, green: 0.03, blue: 0.055)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(title)
                            .font(.system(size: 31, weight: .bold, design: .rounded))
                        Text(subtitle)
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.58))
                    }
                    .padding(.top, 22)

                    content
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 120)
            }
        }
    }
}

private struct CleanMetric: View {
    let title: String
    let value: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title.uppercased()).cleanEyebrow()
            Text(value, format: .currency(code: "USD").precision(.fractionLength(0)))
                .font(.title3.weight(.bold))
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .cleanCard()
    }
}

private struct CleanEmptyCard: View {
    let icon: String
    let title: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.white.opacity(0.72))
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(text)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.54))
            }
            Spacer()
        }
        .padding(18)
        .cleanCard()
    }
}

private struct CleanPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.black)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(.white.opacity(configuration.isPressed ? 0.72 : 0.96))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private extension View {
    func cleanCard() -> some View {
        background(
            .white.opacity(0.07),
            in: RoundedRectangle(cornerRadius: 20, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(.white.opacity(0.08), lineWidth: 1)
        }
    }

    func cleanEyebrow() -> some View {
        font(.caption2.weight(.bold))
            .tracking(1.1)
            .foregroundStyle(.white.opacity(0.48))
    }
}

private func cleanNumber(_ value: Double) -> String {
    if value.rounded() == value {
        return String(Int(value))
    }
    return String(format: "%.2f", value)
}

private func cleanHealthExplanation(_ status: FinancialHealthStatus) -> String {
    switch status {
    case .safe:
        return "Your current plan stays above the buffer you need."
    case .tight:
        return "Your plan stays above the hard floor, but part of your safety buffer gets used."
    case .notSafe:
        return "At least one point in the plan drops below money that should stay protected."
    }
}

private func cleanPurchaseTitle(_ status: PurchaseStatus) -> String {
    switch status {
    case .safe: return "This fits your plan"
    case .tight: return "Possible, but tight"
    case .notSafe: return "This breaks the plan"
    }
}

private func cleanPurchaseReason(_ reason: PurchaseDecisionReason) -> String {
    switch reason {
    case .preservesRecommendedBuffer:
        return "You would still keep your planned obligations and safety buffer covered."
    case .usesSafetyBuffer:
        return "You can cover it, but it would eat into the buffer that protects you from normal surprises."
    case .violatesPersonalReserve:
        return "It would push projected cash below the reserve you chose not to touch."
    case .violatesInstitutionalMinimum:
        return "It would push projected cash below a required minimum balance."
    case .violatesMultipleHardConstraints:
        return "It would push projected cash below more than one protected minimum."
    }
}
