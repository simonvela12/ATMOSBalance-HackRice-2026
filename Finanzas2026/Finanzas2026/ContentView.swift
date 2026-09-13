import SwiftUI
import Charts
import FinanceCore
import FinancialCore

struct ContentView: View {
    @EnvironmentObject private var bankStore: BankAccountStore
    @State private var liveContext: LiveFinancialContext = .empty
    @State private var selectedMonth = ForecastMonth.current
    @State private var selectedDay: ForecastDay?
    @State private var showingAddEntry = false
    @State private var showingWhatIf = false
    @State private var showingAddGoal = false
    @State private var showingAccounts = false
    @State private var showingCalendar = false
    @State private var showingFullMonth = false
    @State private var addedEntries: [FinancialEntry] = []
    @State private var goals: [FinancialGoal] = []
    @State private var goalBeingEdited: FinancialGoal?
    @State private var goalPendingDeletion: FinancialGoal?
    @State private var deletedForecastDays: Set<String> = []
    @State private var excludedOccurrences: Set<String> = []
    @State private var occurrenceNameOverrides: [String: String] = [:]
    @State private var minimumCashReserve: Double?
    /// "My money has to last until this date." A requirement over the whole period,
    /// never a payment on that day.
    @State private var cashMustLastUntil: Date?
    @State private var savingsAllocation: [UUID: Double] = [:]
    @State private var savingsPot: Double = 0

    /// Rebuilding the profile and the projected path is expensive, and the forecast
    /// views read `month` many times per render, so it is cached and refreshed only
    /// when the linked-bank data actually changes.
    private var currentPlan: UserPlan {
        UserPlan(
            goals: goals,
            entries: addedEntries,
            minimumCashReserve: minimumCashReserve,
            cashMustLastUntil: cashMustLastUntil,
            deletedForecastDays: deletedForecastDays,
            excludedOccurrences: excludedOccurrences,
            occurrenceNameOverrides: occurrenceNameOverrides
        )
    }

    private var goalPortfolio: GoalPortfolioHealth? { liveContext.goalPortfolio }

    private func restorePlan() {
        let plan = PlanPersistence.load()
        goals = plan.goals
        addedEntries = plan.entries
        minimumCashReserve = plan.minimumCashReserve
        cashMustLastUntil = plan.cashMustLastUntil
        deletedForecastDays = plan.deletedForecastDays
        excludedOccurrences = plan.excludedOccurrences
        occurrenceNameOverrides = plan.occurrenceNameOverrides
    }

    /// Goals with savings accrued from underspending folded in, for display.
    private var displayGoals: [FinancialGoal] {
        goals.map { goal in
            let accrued = Int((savingsAllocation[goal.id] ?? 0).rounded())
            return goal.withSaved(min(goal.targetAmount, goal.saved + accrued))
        }
    }

    /// The user's goals in the engine's vocabulary. Must-happen goals are
    /// subtracted from the projected path; nice-to-have goals stay out of the
    /// baseline and appear as trade-offs instead.
    private func engineGoals(allocation: [UUID: Double]) -> [FinancialCore.Goal] {
        goals.map { goal in
            let accrued = allocation[goal.id] ?? 0
            return FinancialCore.Goal(
                id: goal.id,
                name: goal.name,
                targetAmount: Double(goal.targetAmount),
                amountAlreadyPaid: min(Double(goal.targetAmount), Double(goal.saved) + accrued),
                deadline: goal.targetDate,
                priority: goal.mustHappen ? .mandatory : goal.priority,
                flexibility: goal.flexibility,
                lifecycleState: goal.lifecycleState
            )
        }
    }

    private func plannedEvents(asOf: Date, horizon: Date)
        -> (income: [IncomeEvent], expenses: [ExpenseEvent]) {
        var income: [IncomeEvent] = []
        var expenses: [ExpenseEvent] = []

        for entry in addedEntries {
            for date in entry.occurrenceDates(through: horizon) {
                let day = AppFinancialData.day(date)
                guard day >= asOf else { continue }
                guard !excludedOccurrences.contains(entry.occurrenceKey(for: date)) else { continue }
                let name = occurrenceNameOverrides[entry.occurrenceKey(for: date)] ?? entry.name

                if entry.kind == .income {
                    income.append(
                        IncomeEvent(amount: Double(entry.amount), date: day,
                                    source: name, type: .oneTime, confidence: 1)
                    )
                } else {
                    expenses.append(
                        ExpenseEvent(amount: Double(entry.amount), date: day,
                                     category: name, essential: false, committed: true)
                    )
                }
            }
        }
        return (income, expenses)
    }

    private func rebuildLiveContext() {
        guard bankStore.isLinked else {
            liveContext = .empty
            return
        }
        let asOf = AppFinancialData.day(Date())
        let horizon = AppFinancialData.horizon(from: asOf)
        let planned = plannedEvents(asOf: asOf, horizon: horizon)

        // Savings accrue from spending history alone, so this base profile carries
        // no goals — that avoids goals depending on an allocation that depends on
        // goals.
        let base = AppFinancialData.profile(
            currentCash: bankStore.totalAvailableCash,
            transactions: bankStore.transactions
        )
        let pot = SavingsAccrual.accrued(profile: base)
        let allocation = SavingsAccrual.allocate(
            pot,
            across: goals.map {
                SavingsAccrual.GoalNeed(
                    id: $0.id,
                    remaining: Double(max(0, $0.targetAmount - $0.saved)),
                    deadline: $0.targetDate,
                    priority: $0.mustHappen ? .mandatory : $0.priority,
                    flexibility: $0.flexibility
                )
            }
        )
        savingsPot = pot
        savingsAllocation = allocation

        let profile = AppFinancialData.profile(
            currentCash: bankStore.totalAvailableCash,
            transactions: bankStore.transactions,
            goals: engineGoals(allocation: allocation),
            plannedIncome: planned.income,
            plannedExpenses: planned.expenses,
            minimumCashReserve: minimumCashReserve,
            cashMustLastUntil: cashMustLastUntil
        )
        let timeline = (try? FinancialInsights.cashFlowTimeline(
            profile: profile,
            from: profile.asOfDate,
            through: AppFinancialData.horizon(from: profile.asOfDate),
            calendar: AppFinancialData.calendar
        )) ?? []
        liveContext = LiveFinancialContext(
            profile: profile,
            transactions: bankStore.transactions,
            timeline: timeline,
            goalPortfolio: try? SmartGoalEngine.evaluate(
                profile: profile,
                planningHorizon: horizon,
                calendar: AppFinancialData.calendar
            ),
            safeToSpend: try? SafeToSpendEngine.evaluateAllScenarios(
                profile: profile,
                calendar: AppFinancialData.calendar
            )
        )
    }

    private var month: MonthForecast {
        MockForecast.data(
            for: selectedMonth,
            including: addedEntries,
            excludingForecastDays: deletedForecastDays,
            excludingOccurrences: excludedOccurrences,
            occurrenceNameOverrides: occurrenceNameOverrides,
            live: liveContext
        )
    }

    private var isInsightsPreview: Bool {
#if DEBUG
        ProcessInfo.processInfo.arguments.contains("--preview-insights")
#else
        false
#endif
    }

    private var activityDays: [ForecastDay] {
        month.days.filter { $0.amount != 0 }
    }

    private var displayedDays: [ForecastDay] {
        if showingFullMonth { return activityDays }

        if let todayIndex = activityDays.firstIndex(where: { $0.status == .today }) {
            let startIndex = max(0, todayIndex - 2)
            return Array(activityDays[startIndex...].prefix(7))
        }

        if selectedMonth.isPast {
            return Array(activityDays.suffix(7))
        }

        return Array(activityDays.prefix(7))
    }

    var body: some View {
        ZStack {
            AtmosphericBackground(weather: month.overallWeather)

            ScrollView {
                VStack(spacing: 0) {
                    if isInsightsPreview {
                        topBar
                        balanceChart
                        spendingMetrics
                        forecastNote
                    } else {
                        topBar
                        hero
                        goalsSection
                        monthSelector
                            .padding(.top, 16)
                        forecastCard
                        balanceChart
                        spendingMetrics
                        forecastNote
                    }
                }
                .padding(.bottom, 28)
            }
            .scrollIndicators(.hidden)
        }
        .preferredColorScheme(.dark)
        .task {
            restorePlan()
            rebuildLiveContext()
        }
        .onChange(of: bankStore.accounts) { _, _ in rebuildLiveContext() }
        .onChange(of: bankStore.transactions) { _, _ in rebuildLiveContext() }
        .onChange(of: currentPlan) { _, plan in
            PlanPersistence.save(plan)
            rebuildLiveContext()
        }
        .animation(.easeInOut(duration: 0.45), value: selectedMonth)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            whatIfButton
        }
        .sheet(item: $selectedDay) { day in
            DayDetailSheet(
                day: day,
                onRename: renameEntry,
                onDelete: deleteEntry
            )
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showingAddEntry) {
            AddEntrySheet { entry in
                addedEntries.append(entry)
                if let visibleMonth = ForecastMonth.containing(entry.startDate) {
                    selectedMonth = visibleMonth
                    showingFullMonth = true
                }
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showingWhatIf) {
            WhatIfSheet(profile: liveContext.profile, goals: displayGoals)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showingAccounts) {
            AccountsSheet()
                .environmentObject(bankStore)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showingAddGoal) {
            AddGoalSheet(existingGoal: goalBeingEdited) { goal in
                if let index = goals.firstIndex(where: { $0.id == goal.id }) {
                    goals[index] = goal
                } else {
                    goals.append(goal)
                }
                goalBeingEdited = nil
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .confirmationDialog(
            "Delete goal?",
            isPresented: Binding(
                get: { goalPendingDeletion != nil },
                set: { if !$0 { goalPendingDeletion = nil } }
            ),
            titleVisibility: .visible,
            presenting: goalPendingDeletion
        ) { goal in
            Button("Delete \(goal.name)", role: .destructive) {
                goals.removeAll { $0.id == goal.id }
                goalPendingDeletion = nil
            }
            Button("Cancel", role: .cancel) { }
        } message: { goal in
            Text("This removes the goal from your plan. It does not delete any bank activity.")
        }
        .sheet(isPresented: $showingCalendar) {
            CalendarForecastSheet(
                month: month,
                onRename: renameEntry,
                onDelete: deleteEntry
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(.white.opacity(0.14))
                Image(systemName: "cloud.sun.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white.opacity(0.9), Color.sunGold)
            }
            .frame(width: 42, height: 42)

            VStack(alignment: .leading, spacing: 1) {
                Text("FINANZAS")
                    .font(.helvetica(.caption, weight: .heavy))
                    .tracking(1.6)
                Text("Financial weather")
                    .font(.helvetica(.caption2))
                    .foregroundStyle(.white.opacity(0.62))
            }

            Spacer()

            Text(bankStore.isLinked ? "LINKED" : "NOT LINKED")
                .font(.helvetica(.caption2, weight: .bold))
                .tracking(0.8)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.white.opacity(0.12), in: Capsule())

            Button { showingAccounts = true } label: {
                Image(systemName: "person.crop.circle.fill")
                    .font(.system(size: 30))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.white.opacity(0.92))
            }
            .accessibilityLabel("Accounts and bank connection")
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 20)
        .padding(.top, 10)
    }

    private var hero: some View {
        VStack(spacing: 8) {
            Text(month.month.displayName)
                .font(.helvetica(.title3, weight: .semibold))
                .foregroundStyle(.white.opacity(0.82))

            Text("$\(month.accountBalance.formatted(.number.grouping(.automatic)))")
                .font(.helvetica(size: 74, weight: .thin))
                .tracking(-4)
                .contentTransition(.numericText(value: Double(month.accountBalance)))

            Text(month.balanceLabel)
                .font(.helvetica(.title3, weight: .medium))
                .foregroundStyle(.white.opacity(0.9))

            HStack(spacing: 8) {
                Image(systemName: month.overallWeather.symbol)
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(
                        month.overallWeather.primaryColor,
                        month.overallWeather.secondaryColor
                    )
                Text(month.conditionTitle)
                    .fontWeight(.semibold)
            }
            .font(.helvetica(.headline))
            .padding(.top, 6)

            if let today = month.days.first(where: { $0.status == .today && $0.amount != 0 }) {
                HStack(spacing: 7) {
                    Text("TODAY")
                        .font(.helvetica(.caption2, weight: .bold))
                        .tracking(0.7)
                    Image(systemName: today.weather.symbol)
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(today.weather.primaryColor, today.weather.secondaryColor)
                    Text(today.formattedAmount)
                        .font(.helvetica(.subheadline, weight: .semibold))
                        .monospacedDigit()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(.white.opacity(0.11), in: Capsule())
                .overlay(Capsule().stroke(.white.opacity(0.14), lineWidth: 0.75))
                .padding(.top, 5)
            }
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity)
        .padding(.top, 24)
        .padding(.bottom, 26)
        .accessibilityElement(children: .combine)
    }

    private var monthSelector: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                ForEach(ForecastMonth.allCases) { forecastMonth in
                    let isSelected = forecastMonth == selectedMonth
                    let forecastWeather = MockForecast.data(
                        for: forecastMonth,
                        including: addedEntries,
                        excludingForecastDays: deletedForecastDays,
                        excludingOccurrences: excludedOccurrences,
                        occurrenceNameOverrides: occurrenceNameOverrides
                    ).overallWeather

                    Button {
                        withAnimation(.easeInOut(duration: 0.4)) {
                            selectedMonth = forecastMonth
                            showingFullMonth = false
                        }
                    } label: {
                        VStack(spacing: 5) {
                            Image(systemName: forecastWeather.symbol)
                                .font(.system(size: 17, weight: .semibold))
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(
                                    forecastWeather.primaryColor,
                                    forecastWeather.secondaryColor
                                )
                                .frame(width: 30, height: 25)
                            Text(forecastMonth.abbreviation)
                                .font(.helvetica(.subheadline, weight: isSelected ? .bold : .semibold))
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(isSelected ? Color.sunGold : .clear)
                                    .frame(width: 5, height: 5)
                                Text(forecastMonth.yearLabel)
                                    .font(.helvetica(.caption2, weight: .medium))
                                    .foregroundStyle(.white.opacity(0.38))
                            }
                        }
                        .foregroundStyle(isSelected ? .white : .white.opacity(0.5))
                        .frame(width: 60, height: 78)
                        .background(
                            isSelected ? .white.opacity(0.16) : .clear,
                            in: RoundedRectangle(cornerRadius: 13, style: .continuous)
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(forecastMonth.displayName)
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                    .id(forecastMonth.id)
                }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
            }
            .background(.black.opacity(0.14), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(.white.opacity(0.12), lineWidth: 0.75)
            }
            .padding(.horizontal, 20)
            .sensoryFeedback(.selection, trigger: selectedMonth)
            .onAppear {
                proxy.scrollTo(selectedMonth.id, anchor: .center)
            }
            .onChange(of: selectedMonth) { _, newMonth in
                withAnimation(.easeInOut(duration: 0.3)) {
                    proxy.scrollTo(newMonth.id, anchor: .center)
                }
            }
        }
    }

    private var goalsSection: some View {
        GoalsCard(
            goals: displayGoals,
            accrued: savingsAllocation.mapValues { Int($0.rounded()) },
            portfolio: goalPortfolio,
            safeToSpend: liveContext.safeToSpend?.primary,
            cashMustLastUntil: cashMustLastUntil,
            // Saving and rebuilding are already driven by `onChange(of: currentPlan)`.
            onSetRunway: { cashMustLastUntil = $0 },
            onAdd: {
                goalBeingEdited = nil
                showingAddGoal = true
            },
            onEdit: { goal in
                // Edit the stored goal, not the display copy — the display copy has
                // accrued savings folded into `saved`, and saving that back would
                // bank the accrual as a manual contribution and count it twice.
                goalBeingEdited = goals.first { $0.id == goal.id } ?? goal
                showingAddGoal = true
            },
            onDelete: { goal in
                goalPendingDeletion = goals.first { $0.id == goal.id } ?? goal
            },
            onTogglePause: { goal in
                guard let index = goals.firstIndex(where: { $0.id == goal.id }) else { return }
                goals[index].lifecycleState = goal.lifecycleState == .paused ? .active : .paused
            },
            onComplete: { goal in
                guard let index = goals.firstIndex(where: { $0.id == goal.id }) else { return }
                goals[index].saved = goals[index].targetAmount
                goals[index].lifecycleState = .completed
            }
        )
        .padding(.horizontal, 20)
        .padding(.top, 16)
    }

    private var forecastCard: some View {
        VStack(spacing: 0) {
            forecastHeader

            Divider()
                .overlay(.white.opacity(0.14))
                .padding(.horizontal, 16)

            if displayedDays.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "tray")
                        .font(.system(size: 25, weight: .light))
                        .foregroundStyle(.white.opacity(0.55))
                    Text("No entries for this month")
                        .font(.helvetica(.headline, weight: .semibold))
                    Text("Use + to add an entry, or connect bank data later.")
                        .font(.helvetica(.caption))
                        .foregroundStyle(.white.opacity(0.5))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 28)
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(Array(displayedDays.enumerated()), id: \.element.id) { index, day in
                        Button {
                            selectedDay = day
                        } label: {
                            ForecastDayRow(day: day)
                        }
                        .buttonStyle(.plain)

                        if index < displayedDays.count - 1 {
                            Divider()
                                .overlay(.white.opacity(0.09))
                                .padding(.leading, 74)
                                .padding(.trailing, 16)
                        }
                    }
                }
            }

            if activityDays.count > 7 {
                Divider()
                    .overlay(.white.opacity(0.12))
                    .padding(.horizontal, 16)

                Button {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        showingFullMonth.toggle()
                    }
                } label: {
                    HStack(spacing: 7) {
                        Text(showingFullMonth ? "Show fewer changes" : "Show all \(activityDays.count) changes")
                        Image(systemName: showingFullMonth ? "chevron.up" : "chevron.down")
                            .font(.helvetica(.caption2, weight: .bold))
                    }
                    .font(.helvetica(.subheadline, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.72))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                }
                .buttonStyle(.plain)
            }
        }
        .background(.black.opacity(0.18), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(.white.opacity(0.13), lineWidth: 0.75)
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
    }

    private var forecastHeader: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("DAILY CHANGES")
                        .font(.helvetica(.caption, weight: .bold))
                        .tracking(1.2)
                        .foregroundStyle(.white.opacity(0.62))
                    Text("\(month.month.displayName) activity")
                        .font(.helvetica(.title3, weight: .semibold))
                }

                HStack(spacing: 8) {
                    Button {
                        showingCalendar = true
                    } label: {
                        Label("Calendar view", systemImage: "calendar")
                            .font(.helvetica(.caption, weight: .semibold))
                            .fixedSize(horizontal: true, vertical: false)
                            .padding(.horizontal, 11)
                            .frame(height: 44)
                            .background(.white.opacity(0.12), in: Capsule())
                    }
                    .accessibilityLabel("Open expanded calendar view")
                    .buttonStyle(.plain)

                    Button {
                        showingAddEntry = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Add entry")
                    .buttonStyle(ForecastToolbarButtonStyle())
                }
                .foregroundStyle(.white)
            }

            HStack(spacing: 14) {
                ForecastLegendItem(title: "Recorded", style: .recorded)
                ForecastLegendItem(title: "Today", style: .today)
                ForecastLegendItem(title: "Forecast", style: .forecast)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
    }

    private var balanceChart: some View {
        BalanceChartCard(
            points: MockForecast.balancePoints(
                including: addedEntries,
                excludingForecastDays: deletedForecastDays,
                excludingOccurrences: excludedOccurrences
            )
        )
            .padding(.horizontal, 20)
            .padding(.top, 16)
    }

    private var spendingMetrics: some View {
        SpendingMetricsCard(month: month)
            .padding(.horizontal, 20)
            .padding(.top, 16)
    }

    private var forecastNote: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "info.circle")
                .padding(.top, 1)
            Text("Daily icons show scheduled money movement. The large condition shows the selected month’s overall financial comfort.")
                .lineSpacing(2)
        }
        .font(.helvetica(.caption))
        .foregroundStyle(.white.opacity(0.55))
        .padding(.horizontal, 28)
        .padding(.top, 14)
    }

    private var whatIfButton: some View {
        Button {
            showingWhatIf = true
        } label: {
            HStack(spacing: 13) {
                Image(systemName: "wand.and.stars")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color.sunGold)
                    .frame(width: 38, height: 38)
                    .background(.white.opacity(0.1), in: Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text("What if?")
                        .font(.helvetica(.headline))
                    Text("Preview a purchase or subscription")
                        .font(.helvetica(.caption))
                        .foregroundStyle(.white.opacity(0.58))
                }

                Spacer()

                Image(systemName: "chevron.up")
                    .font(.helvetica(.caption, weight: .bold))
                    .foregroundStyle(.white.opacity(0.55))
            }
            .foregroundStyle(.white)
            .padding(12)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .background(.black.opacity(0.22), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(.white.opacity(0.18), lineWidth: 0.75)
            }
            .shadow(color: .black.opacity(0.2), radius: 16, y: 8)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 6)
    }

    private func renameEntry(_ target: ForecastEntryTarget, name: String, scope: OccurrenceScope) {
        switch target {
        case .custom(let entryID, let occurrenceKey):
            if scope == .onlyThis {
                occurrenceNameOverrides[occurrenceKey] = name
            } else if let index = addedEntries.firstIndex(where: { $0.id == entryID }) {
                addedEntries[index].name = name
            }
        case .forecastDay:
            break
        }
        selectedDay = nil
    }

    private func deleteEntry(_ target: ForecastEntryTarget, scope: OccurrenceScope) {
        switch target {
        case .custom(let entryID, let occurrenceKey):
            if scope == .onlyThis {
                excludedOccurrences.insert(occurrenceKey)
            } else {
                addedEntries.removeAll { $0.id == entryID }
                occurrenceNameOverrides = occurrenceNameOverrides.filter { !$0.key.hasPrefix(entryID.uuidString) }
            }
        case .forecastDay(let dayID):
            deletedForecastDays.insert(dayID)
        }
        selectedDay = nil
    }
}

private struct ForecastToolbarButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(width: 44, height: 44)
            .background(.white.opacity(configuration.isPressed ? 0.2 : 0.11), in: Circle())
    }
}

private struct ForecastDayRow: View {
    let day: ForecastDay

    var body: some View {
        HStack(spacing: 12) {
            VStack(spacing: 1) {
                Text(day.weekday.uppercased())
                    .font(.helvetica(.caption2, weight: .bold))
                    .tracking(0.7)
                    .foregroundStyle(.white.opacity(0.48))
                Text("\(day.day)")
                    .font(.helvetica(.title3, weight: .semibold))
                    .monospacedDigit()
            }
            .frame(width: 42)

            Image(systemName: day.weather.symbol)
                .font(.system(size: 24, weight: .medium))
                .symbolRenderingMode(.palette)
                .foregroundStyle(day.weather.primaryColor, day.weather.secondaryColor)
                .frame(width: 36, height: 34)
                .opacity(day.status == .forecast ? 0.78 : 1)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Text(day.activityTitle)
                        .font(.helvetica(.subheadline, weight: .semibold))
                    if day.isRecurring {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white.opacity(0.55))
                            .accessibilityLabel("Recurring")
                    }
                }
                Label(day.status.label, systemImage: day.status.symbol)
                    .font(.helvetica(.caption2, weight: .medium))
                    .foregroundStyle(day.status.foregroundColor)
            }

            Spacer(minLength: 8)

            Text(day.formattedAmount)
                .font(.helvetica(.headline, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(day.weather.amountColor)

            Image(systemName: "chevron.right")
                .font(.helvetica(.caption2, weight: .bold))
                .foregroundStyle(.white.opacity(0.28))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background {
            if day.status == .today {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.white.opacity(0.12))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.sunGold.opacity(0.5), lineWidth: 1)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
            }
        }
        .opacity(day.status == .recorded ? 0.72 : 1)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens the daily breakdown")
    }
}

private struct ForecastLegendItem: View {
    let title: String
    let style: DayStatus

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: style.symbol)
                .font(.system(size: 8, weight: .bold))
            Text(title)
        }
        .font(.helvetica(.caption2, weight: .medium))
        .foregroundStyle(style.foregroundColor)
    }
}

private struct BalanceChartCard: View {
    let points: [BalancePoint]

    private var yDomain: ClosedRange<Double> {
        let balances = points.map(\.balance)
        let minimum = balances.min() ?? 750
        let maximum = balances.max() ?? 2300
        let padding = max(180, (maximum - minimum) * 0.16)
        return (minimum - padding)...(maximum + padding)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("BALANCE TRAJECTORY")
                        .font(.helvetica(.caption, weight: .bold))
                        .tracking(1.2)
                        .foregroundStyle(.white.opacity(0.62))
                    Text("Where your balance is heading")
                        .font(.helvetica(.title3, weight: .semibold))
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 5) {
                    ChartLegendItem(title: "Actual", color: .white, dashed: false)
                    ChartLegendItem(title: "Expected", color: Color.sunGold, dashed: true)
                }
            }

            Chart {
                ForEach(points) { point in
                    LineMark(
                        x: .value("Date", point.date),
                        y: .value("Balance", point.balance)
                    )
                    .foregroundStyle(by: .value("Series", point.series.rawValue))
                    .lineStyle(
                        StrokeStyle(
                            lineWidth: 2.5,
                            lineCap: .round,
                            lineJoin: .round,
                            dash: point.series == .expected ? [6, 5] : []
                        )
                    )
                    .interpolationMethod(.stepEnd)

                    PointMark(
                        x: .value("Date", point.date),
                        y: .value("Balance", point.balance)
                    )
                    .foregroundStyle(point.series.color)
                    .symbolSize(point.isAnchor ? 34 : 15)
                }

                RuleMark(x: .value("Today", MockForecast.todayDate))
                    .foregroundStyle(.white.opacity(0.3))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 4]))
                    .annotation(position: .top, alignment: .leading) {
                        Text("TODAY")
                            .font(.system(size: 8, weight: .bold))
                            .tracking(0.6)
                            .foregroundStyle(.white.opacity(0.55))
                    }
            }
            .chartForegroundStyleScale([
                BalanceSeries.actual.rawValue: Color.white,
                BalanceSeries.expected.rawValue: Color.sunGold
            ])
            .chartLegend(.hidden)
            .chartYScale(domain: yDomain)
            .chartXAxis {
                AxisMarks(values: .stride(by: .month)) { _ in
                    AxisGridLine().foregroundStyle(.white.opacity(0.08))
                    AxisValueLabel(format: .dateTime.month(.abbreviated))
                            .font(.helvetica(.caption2))
                        .foregroundStyle(.white.opacity(0.48))
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { _ in
                    AxisGridLine().foregroundStyle(.white.opacity(0.09))
                    AxisValueLabel()
                        .font(.helvetica(.caption2))
                        .foregroundStyle(.white.opacity(0.48))
                }
            }
            .frame(height: 220)
            .opacity(points.isEmpty ? 0 : 1)
            .overlay {
                if points.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "chart.xyaxis.line")
                            .font(.system(size: 26, weight: .light))
                        Text("No balance history yet")
                            .font(.helvetica(.headline, weight: .semibold))
                        Text("The chart will populate from bank data and your forecast entries.")
                            .font(.helvetica(.caption))
                            .foregroundStyle(.white.opacity(0.5))
                            .multilineTextAlignment(.center)
                    }
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(.horizontal, 30)
                }
            }

            HStack(spacing: 8) {
                Image(systemName: "circle.fill")
                    .font(.system(size: 6))
                    .foregroundStyle(.white.opacity(0.55))
                Text("Each point represents a recorded or expected account change.")
            }
            .font(.helvetica(.caption2))
            .foregroundStyle(.white.opacity(0.48))
        }
        .foregroundStyle(.white)
        .padding(18)
        .background(.black.opacity(0.18), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(.white.opacity(0.13), lineWidth: 0.75)
        }
    }
}

private struct ChartLegendItem: View {
    let title: String
    let color: Color
    let dashed: Bool

    var body: some View {
        HStack(spacing: 6) {
            Capsule()
                .stroke(
                    color,
                    style: StrokeStyle(lineWidth: 2, dash: dashed ? [4, 3] : [])
                )
                .frame(width: 22, height: 2)
            Text(title)
        }
        .font(.helvetica(.caption2, weight: .medium))
        .foregroundStyle(.white.opacity(0.58))
    }
}

private struct SpendingMetricsCard: View {
    let month: MonthForecast

    private var scheduledChanges: Int {
        month.days.filter { $0.amount != 0 }.count
    }

    private var quietDays: Int {
        month.days.count - scheduledChanges
    }

    private var hasSpendingData: Bool {
        month.days.contains { $0.expenses > 0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 3) {
                Text("SPENDING CLIMATE")
                    .font(.helvetica(.caption, weight: .bold))
                    .tracking(1.2)
                    .foregroundStyle(.white.opacity(0.62))
                Text("Average daily spending")
                    .font(.helvetica(.title3, weight: .semibold))
            }

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(month.averageDailySpending, format: .currency(code: "USD").precision(.fractionLength(2)))
                    .font(.helvetica(size: 42, weight: .light))
                    .monospacedDigit()
                Text("per day")
                    .font(.helvetica(.subheadline))
                    .foregroundStyle(.white.opacity(0.5))
            }

            if hasSpendingData {
                HStack(spacing: 8) {
                    ComparisonChip(delta: month.previousMonthDelta, label: "vs \(month.month.previousName)")
                    ComparisonChip(delta: month.allTimeDelta, label: "vs all-time")
                }
            } else {
                Label("Add spending history to unlock comparisons", systemImage: "chart.bar.xaxis")
                    .font(.helvetica(.caption))
                    .foregroundStyle(.white.opacity(0.5))
            }

            Divider().overlay(.white.opacity(0.12))

            HStack(spacing: 0) {
                MiniMetric(
                    icon: "calendar.badge.clock",
                    value: "\(scheduledChanges)",
                    label: "scheduled changes"
                )

                Divider()
                    .overlay(.white.opacity(0.12))
                    .frame(height: 42)

                MiniMetric(
                    icon: "moon.stars.fill",
                    value: "\(quietDays)",
                    label: "no-change days"
                )
            }
        }
        .foregroundStyle(.white)
        .padding(18)
        .background(.black.opacity(0.18), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(.white.opacity(0.13), lineWidth: 0.75)
        }
    }
}

private struct ComparisonChip: View {
    let delta: Int
    let label: String

    private var directionText: String {
        if delta < 0 { return "\(abs(delta))% less" }
        if delta > 0 { return "\(delta)% more" }
        return "About even"
    }

    private var symbol: String {
        if delta < 0 { return "arrow.down.right" }
        if delta > 0 { return "arrow.up.right" }
        return "arrow.right"
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.helvetica(.caption2, weight: .bold))
                .foregroundStyle(delta <= 0 ? Color.rainMist : Color.sunGold)
            VStack(alignment: .leading, spacing: 1) {
                Text(directionText)
                    .font(.helvetica(.caption, weight: .semibold))
                Text(label)
                    .font(.helvetica(.caption2))
                    .foregroundStyle(.white.opacity(0.46))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
    }
}

private struct MiniMetric: View {
    let icon: String
    let value: String
    let label: String

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.cloudCream)
            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(.helvetica(.headline))
                Text(label)
                    .font(.helvetica(.caption2))
                    .foregroundStyle(.white.opacity(0.48))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct GoalsCard: View {
    let goals: [FinancialGoal]
    let accrued: [UUID: Int]
    let portfolio: GoalPortfolioHealth?
    /// The conservative answer from the engine. Nil until the bank data has loaded.
    let safeToSpend: SafeToSpendResult?
    let cashMustLastUntil: Date?
    let onSetRunway: (Date?) -> Void
    let onAdd: () -> Void
    let onEdit: (FinancialGoal) -> Void
    let onDelete: (FinancialGoal) -> Void
    let onTogglePause: (FinancialGoal) -> Void
    let onComplete: (FinancialGoal) -> Void

    /// "My money has to last until X" is a requirement over a whole period, so it
    /// lives beside the goals rather than pretending to be a payment on that date.
    @ViewBuilder
    private var runwayRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("MONEY MUST LAST UNTIL")
                    .font(.helvetica(.caption2, weight: .bold))
                    .foregroundStyle(.white.opacity(0.48))
                Spacer()
                if cashMustLastUntil != nil {
                    Button("Clear") { onSetRunway(nil) }
                        .font(.helvetica(.caption2, weight: .semibold))
                        .buttonStyle(.plain)
                        .foregroundStyle(.white.opacity(0.55))
                }
            }

            DatePicker(
                "Money must last until",
                selection: Binding(
                    get: {
                        cashMustLastUntil
                            ?? Calendar.current.date(byAdding: .month, value: 3, to: Date())
                            ?? Date()
                    },
                    set: { onSetRunway($0) }
                ),
                displayedComponents: .date
            )
            .datePickerStyle(.compact)
            .labelsHidden()
            .tint(.white)

            if let runway = safeToSpend?.runway, runway.requestedDate != nil {
                Text(
                    runway.isSatisfied
                        ? "On this plan your money lasts past that date."
                        : "On this plan your money runs out on \(runway.viableThrough.formatted(.dateTime.month(.abbreviated).day()))."
                )
                .font(.helvetica(.caption2, weight: .semibold))
                .foregroundStyle(runway.isSatisfied ? .white.opacity(0.48) : Color.sunGold)
            }
        }
        .padding(11)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 11))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("GOALS")
                        .font(.helvetica(.caption, weight: .bold))
                        .tracking(1.2)
                        .foregroundStyle(.white.opacity(0.62))
                    Text("What you’re working toward")
                        .font(.helvetica(.title3, weight: .semibold))
                }

                Spacer()

                Button(action: onAdd) {
                    Label("Add", systemImage: "plus")
                        .font(.helvetica(.caption, weight: .semibold))
                        .padding(.horizontal, 11)
                        .padding(.vertical, 8)
                        .background(.white.opacity(0.11), in: Capsule())
                }
                .buttonStyle(.plain)
            }

            if !goals.isEmpty, let safeToSpend {
                // Goals are dated requirements, so the useful pair of numbers is what is
                // spendable now and what the future has already claimed. A weekly
                // contribution figure would imply a savings jar that does not exist.
                HStack(spacing: 10) {
                    GoalPortfolioMetric(
                        title: "SAFE TO SPEND",
                        value: safeToSpend.amount.formatted(.currency(code: "USD").precision(.fractionLength(0)))
                    )
                    GoalPortfolioMetric(
                        title: "COMMITTED",
                        value: safeToSpend.futureCommitments.formatted(.currency(code: "USD").precision(.fractionLength(0)))
                    )
                }

                runwayRow

                if let moved = safeToSpend.delayedGoals.first {
                    Label(
                        "\(moved.goal.name) moves to \(moved.projectedDate.formatted(.dateTime.month(.abbreviated).day())) so more important goals stay on time.",
                        systemImage: "arrow.triangle.branch"
                    )
                    .font(.helvetica(.caption, weight: .semibold))
                    .foregroundStyle(Color.sunGold)
                } else if let stuck = safeToSpend.unreachableGoals.first {
                    Label(
                        "\(stuck.goal.name) cannot be met within the flexibility you allowed.",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .font(.helvetica(.caption, weight: .semibold))
                    .foregroundStyle(Color.sunGold)
                }
            }

            if goals.isEmpty {
                Button(action: onAdd) {
                    HStack(spacing: 12) {
                        Image(systemName: "target")
                            .font(.system(size: 22, weight: .medium))
                            .foregroundStyle(Color.sunGold)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("No goals yet")
                                .font(.helvetica(.headline, weight: .semibold))
                            Text("Add a trip, event, or purchase to start planning.")
                                .font(.helvetica(.caption))
                                .foregroundStyle(.white.opacity(0.52))
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundStyle(.white.opacity(0.35))
                    }
                    .padding(14)
                    .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(goals) { goal in
                            GoalProgressTile(
                                goal: goal,
                                accrued: accrued[goal.id] ?? 0,
                                health: portfolio?.goals.first(where: { $0.goal.id == goal.id }),
                                projection: safeToSpend?.goalProjections.first(where: { $0.goal.id == goal.id }),
                                onEdit: { onEdit(goal) },
                                onDelete: { onDelete(goal) },
                                onTogglePause: { onTogglePause(goal) },
                                onComplete: { onComplete(goal) }
                            )
                        }
                    }
                }
            }
        }
        .foregroundStyle(.white)
        .padding(18)
        .background(.black.opacity(0.18), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(.white.opacity(0.13), lineWidth: 0.75)
        }
    }
}

private struct GoalPortfolioMetric: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.helvetica(.caption2, weight: .bold))
                .foregroundStyle(.white.opacity(0.48))
            Text(value)
                .font(.helvetica(.headline, weight: .bold))
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(11)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 11))
    }
}

private struct GoalProgressTile: View {
    let goal: FinancialGoal
    let accrued: Int
    let health: GoalHealth?
    /// What the plan intends to do about this goal: keep the date, or move it.
    let projection: GoalProjection?
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onTogglePause: () -> Void
    let onComplete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: goal.symbol)
                    .foregroundStyle(.white.opacity(0.9))
                Spacer()
                Menu {
                    Button(action: onEdit) {
                        Label("Edit goal", systemImage: "pencil")
                    }
                    if goal.lifecycleState != .completed {
                        Button(action: onTogglePause) {
                            Label(goal.lifecycleState == .paused ? "Resume goal" : "Pause goal",
                                  systemImage: goal.lifecycleState == .paused ? "play.fill" : "pause.fill")
                        }
                        Button(action: onComplete) {
                            Label("Mark complete", systemImage: "checkmark.circle")
                        }
                    }
                    Button(role: .destructive, action: onDelete) {
                        Label("Delete goal", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 13, weight: .bold))
                        .frame(width: 28, height: 28)
                        .background(.white.opacity(0.08), in: Circle())
                }
                .accessibilityLabel("Goal options")
            }

            if let projection {
                HStack {
                    Text(goalProjectionTitle(projection.status))
                        .font(.helvetica(.caption2, weight: .bold))
                        .foregroundStyle(goalProjectionColor(projection.status))
                    Spacer()
                    Text("\(goal.priority.title) · \(goal.flexibility.shortTitle)")
                        .font(.helvetica(.caption2, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.45))
                }
            } else if let health {
                HStack {
                    Text(goalStatusTitle(health.status))
                        .font(.helvetica(.caption2, weight: .bold))
                        .foregroundStyle(goalStatusColor(health.status))
                    Spacer()
                    Text("\(goal.priority.title) · \(goal.flexibility.shortTitle)")
                        .font(.helvetica(.caption2, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.45))
                }
            }

            Text(goal.name)
                .font(.helvetica(.headline, weight: .semibold))
                .lineLimit(1)

            if let projection, projection.wasDelayed {
                Text("Projected \(projection.projectedDate.formatted(.dateTime.month(.abbreviated).day()))")
                    .font(.helvetica(.caption2, weight: .semibold))
                    .foregroundStyle(Color.sunGold)
            }

            HStack(spacing: 6) {
                Text(goal.targetDate, format: .dateTime.month(.abbreviated).day().year())
                    .font(.helvetica(.caption2, weight: .medium))
                    .foregroundStyle(.white.opacity(0.48))
                if goal.mustHappen {
                    Text("MUST HAPPEN")
                        .font(.helvetica(.caption2, weight: .bold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.sunGold.opacity(0.18), in: Capsule())
                        .foregroundStyle(Color.sunGold)
                }
            }

            ProgressView(value: goal.progress)
                .tint(Color.sunGold)

            HStack(alignment: .firstTextBaseline) {
                Text("$\(goal.saved.formatted())")
                    .font(.helvetica(.subheadline, weight: .bold))
                Text("of $\(goal.targetAmount.formatted())")
                    .font(.helvetica(.caption2))
                    .foregroundStyle(.white.opacity(0.5))
                Spacer()
                Text("\(Int(goal.progress * 100))%")
                    .font(.helvetica(.caption, weight: .bold))
                    .foregroundStyle(Color.sunGold)
            }

            // Makes the accrual visible, rather than it silently inflating `saved`.
            Text(accrued > 0
                 ? "Includes $\(accrued.formatted()) saved by underspending"
                 : "Spend under your usual week to build this up")
                .font(.helvetica(.caption2))
                .foregroundStyle(.white.opacity(0.45))
                .fixedSize(horizontal: false, vertical: true)

            if let health, health.status != .completed, health.status != .paused {
                Text("Save \(health.requiredWeeklySavings.formatted(.currency(code: "USD").precision(.fractionLength(0))))/week")
                    .font(.helvetica(.caption2, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.62))
                if let date = health.recommendedTargetDate {
                    Text("More realistic: \(date.formatted(.dateTime.month(.abbreviated).day().year()))")
                        .font(.helvetica(.caption2))
                        .foregroundStyle(Color.sunGold)
                } else if let date = health.projectedCompletionDate {
                    Text("Projected: \(date.formatted(.dateTime.month(.abbreviated).day().year()))")
                        .font(.helvetica(.caption2))
                        .foregroundStyle(.white.opacity(0.48))
                }
            }
        }
        .padding(14)
        .frame(width: 230, alignment: .leading)
        .background(.white.opacity(0.075), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct AddGoalSheet: View {
    @Environment(\.dismiss) private var dismiss
    let existingGoal: FinancialGoal?
    let onSave: (FinancialGoal) -> Void

    @State private var name = ""
    @State private var amountText = ""
    @State private var savedText = ""
    @State private var targetDate = Calendar.current.date(byAdding: .month, value: 4, to: MockForecast.todayDate) ?? MockForecast.todayDate
    @State private var symbol = "airplane"
    @State private var mustHappen = true
    @State private var priority = GoalPriority.medium
    @State private var flexibility = GoalFlexibility.maxDelay(days: 30)

    init(existingGoal: FinancialGoal? = nil, onSave: @escaping (FinancialGoal) -> Void) {
        self.existingGoal = existingGoal
        self.onSave = onSave
        _name = State(initialValue: existingGoal?.name ?? "")
        _amountText = State(initialValue: existingGoal.map { String($0.targetAmount) } ?? "")
        _savedText = State(initialValue: existingGoal.map { String($0.saved) } ?? "")
        _targetDate = State(initialValue: existingGoal?.targetDate ?? Calendar.current.date(byAdding: .month, value: 4, to: MockForecast.todayDate) ?? MockForecast.todayDate)
        _symbol = State(initialValue: existingGoal?.symbol ?? "airplane")
        _mustHappen = State(initialValue: existingGoal?.mustHappen ?? true)
        _priority = State(initialValue: existingGoal?.priority ?? .medium)
        _flexibility = State(initialValue: existingGoal?.flexibility ?? .maxDelay(days: 30))
    }

    private var targetAmount: Int { Int(amountText.filter(\.isNumber)) ?? 0 }
    private var saved: Int { Int(savedText.filter(\.isNumber)) ?? 0 }
    private var canSave: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty && targetAmount > 0 }

    var body: some View {
        ZStack {
            LinearGradient(colors: MoneyWeather.partlySunny.backgroundColors, startPoint: .topLeading, endPoint: .bottomTrailing)
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 18) {
                    SheetTitle(
                        eyebrow: existingGoal == nil ? "NEW GOAL" : "EDIT GOAL",
                        title: existingGoal == nil ? "Plan something worth saving for" : "Update your objective",
                        symbol: symbol
                    )

                    EntryCard(title: "GOAL NAME") {
                        TextField("Trip to Miami", text: $name)
                    }

                    EntryCard(title: "TARGET AMOUNT") {
                        CurrencyField(text: $amountText, placeholder: "1,200")
                    }

                    EntryCard(title: "ALREADY SET ASIDE") {
                        CurrencyField(text: $savedText, placeholder: "0")
                    }

                    EntryCard(title: "TARGET DATE") {
                        DatePicker("Goal date", selection: $targetDate, in: MockForecast.todayDate..., displayedComponents: .date)
                            .tint(.white)
                    }

                    EntryCard(title: "PRIORITY") {
                        Picker("Goal priority", selection: $mustHappen) {
                            Text("Nice to have").tag(false)
                            Text("Must happen").tag(true)
                        }
                        .pickerStyle(.segmented)

                        Text(mustHappen
                             ? "Set aside from safe-to-spend right away."
                             : "Shown as a trade-off instead of reducing what you can spend.")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.55))
                            .padding(.top, 6)
                    }

                    EntryCard(title: "RELATIVE PRIORITY") {
                        Picker("Relative priority", selection: $priority) {
                            Text("High").tag(GoalPriority.high)
                            Text("Medium").tag(GoalPriority.medium)
                            Text("Low").tag(GoalPriority.low)
                        }
                        .pickerStyle(.segmented)
                    }

                    EntryCard(title: "FLEXIBILITY") {
                        Picker("Flexibility", selection: $flexibility) {
                            ForEach(GoalFlexibility.presets, id: \.rawValue) { option in
                                Text(option.title).tag(option)
                            }
                        }
                        .pickerStyle(.menu)
                        .tint(.white)
                        Text("Flexibility is about the date, never the amount. A fixed date is protected first; a flexible one can move within its limit to keep more important goals on time.")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.55))
                            .padding(.top, 6)
                    }

                    EntryCard(title: "ICON") {
                        Picker("Goal icon", selection: $symbol) {
                            Label("Travel", systemImage: "airplane").tag("airplane")
                            Label("Event", systemImage: "ticket.fill").tag("ticket.fill")
                            Label("Purchase", systemImage: "bag.fill").tag("bag.fill")
                            Label("Education", systemImage: "graduationcap.fill").tag("graduationcap.fill")
                        }
                        .pickerStyle(.menu)
                        .tint(.white)
                    }

                    PrimarySheetButton(title: existingGoal == nil ? "Add goal" : "Save changes", enabled: canSave) {
                        onSave(FinancialGoal(
                            id: existingGoal?.id ?? UUID(),
                            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                            targetAmount: targetAmount,
                            saved: min(saved, targetAmount),
                            targetDate: targetDate,
                            symbol: symbol,
                            isMandatory: mustHappen,
                            priority: priority,
                            flexibility: flexibility,
                            lifecycleState: existingGoal?.lifecycleState ?? .active
                        ))
                        dismiss()
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 28)
            }
            .scrollIndicators(.hidden)
        }
        .preferredColorScheme(.dark)
    }
}

private extension FinancialScenario {
    var title: String {
        switch self {
        case .conservative: "Conservative"
        case .expected: "Expected"
        case .optimistic: "Optimistic"
        }
    }
}

private extension ScenarioPurchaseOutcome {
    /// One phrase per scenario, so the three read as a spread rather than three numbers.
    var outcomeTitle: String {
        if !runwaySatisfied { return "Runs out early" }
        switch status {
        case .safe: return "Safe"
        case .tight: return "Safe but tight"
        case .notSafe: return "Not safe"
        }
    }
}

private struct WhatIfSheet: View {
    let profile: FinancialProfile?
    let goals: [FinancialGoal]

    @State private var amountText = ""
    @State private var schedule = EntrySchedule.oneTime
    @State private var repeatEvery = 1
    @State private var repeatUnit = RepeatUnit.month

    @State private var explanation: String?
    @State private var explanationError: String?
    @State private var isExplaining = false
    @State private var showingKeyEntry = false

    private var amount: Int { Int(amountText.filter(\.isNumber)) ?? 0 }

    /// A recurring payment is assessed as its total cost over the next 90 days,
    /// applied on the first date. The engine assesses one purchase, so this is an
    /// approximation — labelled as one in the UI rather than presented as exact.
    private var assessedAmount: Int {
        guard schedule == .recurring else { return amount }
        let occurrences: Double
        switch repeatUnit {
        case .day: occurrences = 90 / Double(repeatEvery)
        case .week: occurrences = 13 / Double(repeatEvery)
        case .month: occurrences = 3 / Double(repeatEvery)
        case .year: occurrences = 1
        }
        return amount * max(1, Int(occurrences.rounded(.up)))
    }

    private var analysis: PurchaseWhatIfAnalysis? {
        guard let profile, assessedAmount > 0 else { return nil }
        return try? FinancialInsights.analyzePurchaseWhatIf(
            profile: profile,
            amount: Double(assessedAmount),
            purchaseDate: profile.asOfDate,
            planningHorizon: AppFinancialData.horizon(from: profile.asOfDate),
            calendar: AppFinancialData.calendar
        )
    }

    private var smartGoalImpact: GoalTransactionImpact? {
        guard let profile, assessedAmount > 0 else { return nil }
        return try? SmartGoalEngine.impact(
            of: GoalCashMovement(
                amount: -Double(assessedAmount),
                date: profile.asOfDate,
                label: schedule == .recurring ? "What-if recurring spending" : "What-if purchase"
            ),
            on: profile,
            planningHorizon: AppFinancialData.horizon(from: profile.asOfDate),
            calendar: AppFinancialData.calendar
        )
    }

    private var status: PurchaseStatus? { analysis?.purchaseAssessment.status }

    private var recommendation: PurchaseRecommendation? { analysis?.recommendation }

    private var resultWeather: MoneyWeather {
        switch recommendation {
        case .recommended: return .sunny
        case .possibleButTight: return .rain
        case .notRecommended: return .storm
        case nil: return .partlySunny
        }
    }

    private var headline: String {
        switch recommendation {
        case .recommended: return "This fits your plan"
        case .possibleButTight: return "Possible, but it gets tight"
        case .notRecommended: return "Not recommended"
        case nil: return schedule == .recurring ? "Try a recurring payment" : "Try a purchase"
        }
    }

    private var verdict: PurchaseVerdict? {
        guard let analysis else { return nil }
        let explanation = analysis.purchaseExplanation
        return PurchaseVerdict(
            amount: Double(assessedAmount),
            status: explanation.status,
            reason: explanation.reason,
            projectedCashBefore: explanation.projectedCashBeforePurchase,
            projectedCashAfter: explanation.projectedCashAfterPurchase,
            hardFloor: explanation.hardFloor,
            recommendedFloor: explanation.recommendedFloor,
            shortfallToHardFloor: explanation.shortfallToHardFloor,
            shortfallToRecommendedFloor: explanation.shortfallToRecommendedFloor,
            limitingDate: explanation.limitingDate,
            recommendedDate: explanation.recommendedDate,
            worsenedGoals: analysis.worsenedGoals.map {
                PurchaseVerdict.GoalChange(
                    name: $0.goal.name,
                    before: $0.before.status.rawValue,
                    after: $0.after.status.rawValue
                )
            }
        )
    }

    private static let money = FloatingPointFormatStyle<Double>.Currency(code: "USD")
        .precision(.fractionLength(0))

    var body: some View {
        ZStack {
            LinearGradient(colors: resultWeather.backgroundColors, startPoint: .topLeading, endPoint: .bottomTrailing)
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 18) {
                    SheetTitle(eyebrow: "WHAT IF?", title: headline, symbol: resultWeather.symbol)

                    EntryCard(title: "PURCHASE AMOUNT") {
                        CurrencyField(text: $amountText, placeholder: "80")
                    }

                    EntryCard(title: "TYPE") {
                        Picker("Payment type", selection: $schedule) {
                            Text("One-time").tag(EntrySchedule.oneTime)
                            Text("Recurring").tag(EntrySchedule.recurring)
                        }
                        .pickerStyle(.segmented)

                        if schedule == .recurring {
                            HStack {
                                Text("Repeat every")
                                Spacer()
                                Stepper("\(repeatEvery)", value: $repeatEvery, in: 1...30)
                                    .fixedSize()
                            }
                            Picker("Frequency", selection: $repeatUnit) {
                                ForEach(RepeatUnit.allCases) { unit in
                                    Text(repeatEvery == 1 ? unit.singular : unit.plural).tag(unit)
                                }
                            }
                            .pickerStyle(.menu)
                            .tint(.white)
                        }
                    }

                    if amount > 0, let analysis {
                        let detail = analysis.purchaseExplanation

                        VStack(spacing: 0) {
                            ScenarioMetric(
                                title: "Cash on your tightest day",
                                value: Self.money.format(detail.projectedCashBeforePurchase)
                            )
                            Divider().overlay(.white.opacity(0.12))
                            ScenarioMetric(
                                title: "Same day, after this",
                                value: Self.money.format(detail.projectedCashAfterPurchase)
                            )
                            Divider().overlay(.white.opacity(0.12))
                            ScenarioMetric(
                                title: "Your protected minimum",
                                value: Self.money.format(detail.hardFloor)
                            )
                            if schedule == .recurring {
                                Divider().overlay(.white.opacity(0.12))
                                ScenarioMetric(
                                    title: "Estimated 90-day cost",
                                    value: "−" + Self.money.format(Double(assessedAmount))
                                )
                            }
                            if let recommendedDate = detail.recommendedDate, detail.status != .safe {
                                Divider().overlay(.white.opacity(0.12))
                                ScenarioMetric(
                                    title: "Safe from",
                                    value: recommendedDate.formatted(.dateTime.month(.abbreviated).day())
                                )
                            }
                        }
                        .padding(.horizontal, 16)
                        .background(.black.opacity(0.16), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                        VStack(spacing: 0) {
                            ScenarioMetric(
                                title: "Safe to spend",
                                value: Self.money.format(analysis.safeToSpendBefore.primary.amount)
                                    + " → "
                                    + Self.money.format(analysis.safeToSpendAfter.primary.amount)
                            )

                            if let requested = analysis.runwayBefore.requestedDate {
                                Divider().overlay(.white.opacity(0.12))
                                ScenarioMetric(
                                    title: "Money lasts until",
                                    value: requested.formatted(.dateTime.month(.abbreviated).day())
                                        + " → "
                                        + analysis.runwayAfter.viableThrough
                                            .formatted(.dateTime.month(.abbreviated).day())
                                )
                            }

                            ForEach(analysis.movedGoals) { change in
                                Divider().overlay(.white.opacity(0.12))
                                ScenarioMetric(
                                    title: change.name,
                                    value: change.dateBefore.formatted(.dateTime.month(.abbreviated).day())
                                        + " → "
                                        + change.dateAfter.formatted(.dateTime.month(.abbreviated).day())
                                )
                            }

                            ForEach(analysis.scenarioOutcomes, id: \.scenario) { outcome in
                                Divider().overlay(.white.opacity(0.12))
                                ScenarioMetric(
                                    title: outcome.scenario.title,
                                    value: outcome.outcomeTitle
                                )
                            }
                        }
                        .padding(.horizontal, 16)
                        .background(.black.opacity(0.16), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                        if let dependency = analysis.dependsOnUncertainIncome.first {
                            Label(
                                "This only works if the \(Self.money.format(dependency.amount)) from \(dependency.source) actually arrives on \(dependency.date.formatted(.dateTime.month(.abbreviated).day())).",
                                systemImage: "questionmark.circle.fill"
                            )
                            .font(.helvetica(.caption, weight: .semibold))
                            .foregroundStyle(Color.sunGold)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        explanationCard

                        if !goals.isEmpty {
                            VStack(alignment: .leading, spacing: 14) {
                                Text("GOAL IMPACT")
                                    .font(.helvetica(.caption, weight: .bold))
                                    .tracking(1.1)
                                    .foregroundStyle(.white.opacity(0.6))

                                ForEach(goals) { goal in
                                    let impact = analysis.goalImpacts.first { $0.goal.id == goal.id }
                                    let smartImpact = smartGoalImpact?.goalImpacts.first { $0.goal.id == goal.id }
                                    WhatIfGoalRow(
                                        goal: goal,
                                        beforeStatus: impact?.before.status,
                                        afterStatus: impact?.after.status,
                                        worsened: impact?.worsened ?? false,
                                        smartImpact: smartImpact
                                    )
                                }
                            }
                            .padding(16)
                            .background(.black.opacity(0.16), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                    } else if amount > 0 {
                        Text("Connect an account first — there is no cash path to test this against yet.")
                            .font(.helvetica(.subheadline))
                            .foregroundStyle(.white.opacity(0.62))
                            .multilineTextAlignment(.center)
                            .padding(24)
                    } else {
                        Text("Enter an amount to see the effect on your cash path and goals. Nothing here changes your real forecast.")
                            .font(.helvetica(.subheadline))
                            .foregroundStyle(.white.opacity(0.62))
                            .multilineTextAlignment(.center)
                            .padding(24)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 28)
            }
            .scrollIndicators(.hidden)
        }
        .preferredColorScheme(.dark)
        .animation(.easeInOut(duration: 0.3), value: schedule)
        .animation(.easeInOut(duration: 0.3), value: resultWeather)
        .onChange(of: assessedAmount) { _, _ in
            explanation = nil
            explanationError = nil
        }
        .sheet(isPresented: $showingKeyEntry) {
            GeminiKeySheet()
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
    }

    /// The engine has already decided. Gemini only puts that decision into words,
    /// so if it is unavailable the numbers above still stand on their own.
    @ViewBuilder private var explanationCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("WHAT THIS MEANS")
                    .font(.helvetica(.caption, weight: .bold))
                    .tracking(1.1)
                    .foregroundStyle(.white.opacity(0.6))
                Spacer()
                if isExplaining { ProgressView().tint(.white) }
            }

            if let explanation {
                Text(explanation)
                    .font(.helvetica(.subheadline))
                    .foregroundStyle(.white.opacity(0.88))
            } else if let explanationError {
                Text(explanationError)
                    .font(.helvetica(.caption))
                    .foregroundStyle(.white.opacity(0.7))
            } else if !isExplaining {
                Text("Ask Gemini to put this in plain language. The verdict above does not change — it only gets explained.")
                    .font(.helvetica(.caption))
                    .foregroundStyle(.white.opacity(0.55))
            }

            HStack(spacing: 12) {
                Button(GeminiSettings.apiKey == nil ? "Add Gemini key" : "Explain this") {
                    if GeminiSettings.apiKey == nil {
                        showingKeyEntry = true
                    } else {
                        requestExplanation()
                    }
                }
                .font(.helvetica(.subheadline, weight: .semibold))
                .foregroundStyle(Color.sunGold)
                .disabled(isExplaining)

                if GeminiSettings.apiKey != nil {
                    Button("Change key") { showingKeyEntry = true }
                        .font(.helvetica(.caption))
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.black.opacity(0.16), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func requestExplanation() {
        guard let verdict else { return }
        isExplaining = true
        explanationError = nil
        Task {
            do {
                explanation = try await GeminiExplainer.explain(verdict)
            } catch {
                explanationError = (error as? LocalizedError)?.errorDescription
                    ?? "Could not reach Gemini."
            }
            isExplaining = false
        }
    }
}

/// Your accounts, and the connection behind them.
///
/// Previously the only way to reach the bank connection was a floating button
/// that sat underneath the profile button in the top bar, so it was effectively
/// unreachable. This is the one place for both.
private struct AccountsSheet: View {
    @EnvironmentObject private var bankStore: BankAccountStore
    @Environment(\.dismiss) private var dismiss

    @State private var apiKey = ""
    @State private var customerID = ""
    @State private var showingCredentials = false

    private static let money = FloatingPointFormatStyle<Double>.Currency(code: "USD")
        .precision(.fractionLength(2))

    private var isConnecting: Bool {
        if case .connecting = bankStore.phase { return true }
        return false
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: MoneyWeather.partlySunny.backgroundColors,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 18) {
                    SheetTitle(
                        eyebrow: "ACCOUNTS",
                        title: bankStore.isLinked ? "Your linked money" : "No accounts linked yet",
                        symbol: "building.columns.fill"
                    )

                    if bankStore.isLinked {
                        VStack(spacing: 6) {
                            Text("AVAILABLE CASH")
                                .font(.helvetica(.caption, weight: .bold))
                                .tracking(1.1)
                                .foregroundStyle(.white.opacity(0.6))
                            Text(Self.money.format(bankStore.totalAvailableCash))
                                .font(.helvetica(size: 44, weight: .thin))
                                .monospacedDigit()
                            Text("Excludes credit cards")
                                .font(.helvetica(.caption))
                                .foregroundStyle(.white.opacity(0.5))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .background(.black.opacity(0.16), in: RoundedRectangle(cornerRadius: 18, style: .continuous))

                        VStack(spacing: 0) {
                            ForEach(Array(bankStore.accounts.enumerated()), id: \.element.id) { index, account in
                                accountRow(account)
                                if index < bankStore.accounts.count - 1 {
                                    Divider().overlay(.white.opacity(0.12))
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                        .background(.black.opacity(0.16), in: RoundedRectangle(cornerRadius: 18, style: .continuous))

                        statusCard
                    }

                    credentialsCard
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 28)
            }
            .scrollIndicators(.hidden)
        }
        .preferredColorScheme(.dark)
    }

    private func accountRow(_ account: FinanceCore.FinancialAccount) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol(for: account.accountType))
                .frame(width: 34, height: 34)
                .background(.white.opacity(0.1), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(account.name).font(.helvetica(.subheadline, weight: .semibold))
                Text(label(for: account.accountType))
                    .font(.helvetica(.caption))
                    .foregroundStyle(.white.opacity(0.54))
            }
            Spacer()
            Text(Self.money.format(Double(account.balanceMinorUnits) / 100))
                .font(.helvetica(.subheadline, weight: .bold))
                .monospacedDigit()
        }
        .padding(.vertical, 14)
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("SYNC")
                .font(.helvetica(.caption, weight: .bold))
                .tracking(1.1)
                .foregroundStyle(.white.opacity(0.6))

            Text(statusText)
                .font(.helvetica(.subheadline))
                .foregroundStyle(.white.opacity(0.85))

            if let last = bankStore.accounts.map(\.lastSyncedAt).max() {
                Text("Last updated " + last.formatted(.dateTime.month(.abbreviated).day().hour().minute()))
                    .font(.helvetica(.caption))
                    .foregroundStyle(.white.opacity(0.5))
            }

            if bankStore.canRefresh {
                Button("Refresh now") {
                    Task { await bankStore.refreshLinkedAccounts() }
                }
                .font(.helvetica(.subheadline, weight: .semibold))
                .foregroundStyle(Color.sunGold)
                .disabled(isConnecting)
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.black.opacity(0.16), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var statusText: String {
        switch bankStore.phase {
        case .connecting: return "Syncing with your bank now."
        case .loadingCache: return "Loading saved bank data."
        case .cached: return "Showing saved bank data. Link again to refresh."
        case .failed(let message): return message
        case .connected:
            if bankStore.hasPartialSync {
                return "Updated, but one account could not be read in full. Its history may be incomplete."
            }
            return "Up to date."
        case .idle: return "Nothing linked yet."
        }
    }

    @ViewBuilder private var credentialsCard: some View {
        if showingCredentials || !bankStore.isLinked {
            VStack(spacing: 14) {
                EntryCard(title: "NESSIE API KEY") {
                    SecureField("API key", text: $apiKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                EntryCard(title: "CUSTOMER ID") {
                    TextField("Customer ID", text: $customerID)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                Text("Credentials stay on this device and are never committed to the repository.")
                    .font(.helvetica(.caption))
                    .foregroundStyle(.white.opacity(0.55))
                    .multilineTextAlignment(.center)

                PrimarySheetButton(
                    title: isConnecting ? "Connecting…" : "Connect",
                    enabled: !isConnecting
                        && !apiKey.trimmingCharacters(in: .whitespaces).isEmpty
                        && !customerID.trimmingCharacters(in: .whitespaces).isEmpty
                ) {
                    Task {
                        await bankStore.linkNessieAccount(
                            apiKey: apiKey.trimmingCharacters(in: .whitespacesAndNewlines),
                            customerID: customerID.trimmingCharacters(in: .whitespacesAndNewlines)
                        )
                        if bankStore.isLinked {
                            apiKey = ""
                            customerID = ""
                            showingCredentials = false
                        }
                    }
                }
            }
        } else {
            Button("Connect another account") { showingCredentials = true }
                .font(.helvetica(.subheadline, weight: .semibold))
                .foregroundStyle(Color.sunGold)
        }
    }

    private func symbol(for type: FinanceCore.AccountType) -> String {
        switch type {
        case .checking: return "banknote.fill"
        case .savings: return "chart.line.uptrend.xyaxis"
        case .creditCard: return "creditcard.fill"
        case .cash: return "dollarsign.circle.fill"
        case .other: return "building.columns.fill"
        }
    }

    private func label(for type: FinanceCore.AccountType) -> String {
        switch type {
        case .checking: return "Checking"
        case .savings: return "Savings"
        case .creditCard: return "Credit card"
        case .cash: return "Cash"
        case .other: return "Account"
        }
    }
}

private struct GeminiKeySheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var key = GeminiSettings.apiKey ?? ""

    var body: some View {
        ZStack {
            LinearGradient(colors: MoneyWeather.cloudy.backgroundColors, startPoint: .topLeading, endPoint: .bottomTrailing)
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 18) {
                    SheetTitle(eyebrow: "GEMINI", title: "Explain results in plain language", symbol: "sparkles")

                    EntryCard(title: "API KEY") {
                        SecureField("Paste your Gemini API key", text: $key)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }

                    Text("The key stays on this device and is never committed to the repository. It is used only to reword decisions the engine has already made.")
                        .font(.helvetica(.caption))
                        .foregroundStyle(.white.opacity(0.6))
                        .multilineTextAlignment(.center)

                    PrimarySheetButton(title: "Save key", enabled: !key.trimmingCharacters(in: .whitespaces).isEmpty) {
                        GeminiSettings.apiKey = key
                        dismiss()
                    }

                    if GeminiSettings.apiKey != nil {
                        Button("Remove key") {
                            GeminiSettings.apiKey = nil
                            key = ""
                            dismiss()
                        }
                        .font(.helvetica(.caption))
                        .foregroundStyle(.white.opacity(0.55))
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 28)
            }
            .scrollIndicators(.hidden)
        }
        .preferredColorScheme(.dark)
    }
}

private struct WhatIfGoalRow: View {
    let goal: FinancialGoal
    let beforeStatus: FinancialHealthStatus?
    let afterStatus: FinancialHealthStatus?
    let worsened: Bool
    let smartImpact: GoalMovementImpact?

    private func label(_ status: FinancialHealthStatus) -> String {
        switch status {
        case .safe: return "on track"
        case .tight: return "tight"
        case .notSafe: return "at risk"
        }
    }

    private var detail: String {
        if let impact = smartImpact {
            if let days = impact.projectedCompletionDateChangeInDays, days != 0 {
                return days > 0 ? "Projected completion moves about \(days) days later"
                    : "Projected completion improves by about \(abs(days)) days"
            }
            if impact.shortfallChange > 0.005 {
                return "Adds \(impact.shortfallChange.formatted(.currency(code: "USD").precision(.fractionLength(0)))) to the shortfall"
            }
            if impact.statusBefore != impact.statusAfter {
                return "Moves from \(goalStatusTitle(impact.statusBefore)) to \(goalStatusTitle(impact.statusAfter))"
            }
        }
        guard let afterStatus else { return "Not affected by this purchase" }
        guard worsened, let beforeStatus else {
            return "Stays " + label(afterStatus)
        }
        return "Moves from " + label(beforeStatus) + " to " + label(afterStatus)
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: goal.symbol)
                .frame(width: 34, height: 34)
                .background(.white.opacity(0.1), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(goal.name).font(.helvetica(.subheadline, weight: .semibold))
                Text(detail)
                    .font(.helvetica(.caption))
                    .foregroundStyle(.white.opacity(0.54))
            }
            Spacer()
            Image(systemName: isWorse ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .font(.helvetica(.caption, weight: .bold))
                .foregroundStyle(isWorse ? Color.sunGold : .white.opacity(0.4))
        }
    }

    private var isWorse: Bool {
        worsened || (smartImpact?.shortfallChange ?? 0) > 0.005
            || (smartImpact?.projectedCompletionDateChangeInDays ?? 0) > 0
    }
}

private struct ScenarioMetric: View {
    let title: String
    let value: String

    var body: some View {
        HStack {
            Text(title).foregroundStyle(.white.opacity(0.64))
            Spacer()
            Text(value).font(.helvetica(.headline, weight: .semibold)).monospacedDigit()
        }
        .padding(.vertical, 14)
    }
}

private struct CalendarForecastSheet: View {
    let month: MonthForecast
    let onRename: (ForecastEntryTarget, String, OccurrenceScope) -> Void
    let onDelete: (ForecastEntryTarget, OccurrenceScope) -> Void
    @State private var selectedDay: ForecastDay?
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)

    private var leadingSpaces: Int {
        var components = DateComponents()
        components.year = month.month.year
        components.month = month.month.monthNumber
        components.day = 1
        let date = Calendar.current.date(from: components) ?? .now
        return Calendar.current.component(.weekday, from: date) - 1
    }

    var body: some View {
        ZStack {
            LinearGradient(colors: month.overallWeather.backgroundColors, startPoint: .topLeading, endPoint: .bottomTrailing)
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 20) {
                    SheetTitle(eyebrow: "MONTHLY CALENDAR", title: month.month.displayName, symbol: "calendar")

                    LazyVGrid(columns: columns, spacing: 8) {
                        ForEach(["SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT"], id: \.self) { weekday in
                            Text(weekday)
                                .font(.helvetica(.caption2, weight: .bold))
                                .foregroundStyle(.white.opacity(0.48))
                        }

                        ForEach(0..<leadingSpaces, id: \.self) { _ in
                            Color.clear.frame(height: 76)
                        }

                        ForEach(month.days) { day in
                            Button { selectedDay = day } label: {
                                CalendarDayCell(day: day)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(12)
                    .background(.black.opacity(0.18), in: RoundedRectangle(cornerRadius: 18, style: .continuous))

                    Text("Tap any day for its income and spending breakdown.")
                        .font(.helvetica(.caption))
                        .foregroundStyle(.white.opacity(0.52))
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 28)
            }
        }
        .preferredColorScheme(.dark)
        .sheet(item: $selectedDay) { day in
            DayDetailSheet(day: day, onRename: onRename, onDelete: onDelete)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }
}

private struct CalendarDayCell: View {
    let day: ForecastDay

    var body: some View {
        VStack(spacing: 5) {
            Text("\(day.day)")
                .font(.helvetica(.caption, weight: day.status == .today ? .bold : .medium))
            if day.amount != 0 {
                Image(systemName: day.weather.symbol)
                    .font(.system(size: 15))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(day.weather.primaryColor, day.weather.secondaryColor)
                Text(day.formattedAmount)
                    .font(.helvetica(.caption2, weight: .semibold))
                    .minimumScaleFactor(0.65)
            } else {
                Spacer().frame(height: 27)
                Text("—").font(.helvetica(.caption2)).foregroundStyle(.white.opacity(0.28))
            }
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, minHeight: 70)
        .background(day.status == .today ? Color.sunGold.opacity(0.18) : .white.opacity(day.amount == 0 ? 0.035 : 0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            if day.status == .today {
                RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Color.sunGold.opacity(0.65))
            }
        }
    }
}

private struct SheetTitle: View {
    let eyebrow: String
    let title: String
    let symbol: String

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(eyebrow).font(.helvetica(.caption, weight: .bold)).tracking(1.4).foregroundStyle(.white.opacity(0.62))
                Text(title).font(.helvetica(.title2, weight: .bold))
            }
            Spacer()
            Image(systemName: symbol)
                .font(.system(size: 36, weight: .medium))
                .symbolRenderingMode(.palette)
                .foregroundStyle(
                    MoneyWeather.allCases.first(where: { $0.symbol == symbol })?.primaryColor ?? .white.opacity(0.9),
                    MoneyWeather.allCases.first(where: { $0.symbol == symbol })?.secondaryColor ?? .white.opacity(0.9)
                )
                .frame(width: 48, height: 48)
        }
        .padding(.top, 16)
    }
}

private struct CurrencyField: View {
    @Binding var text: String
    let placeholder: String

    var body: some View {
        HStack(spacing: 6) {
            Text("$").foregroundStyle(.white.opacity(0.5))
            TextField(placeholder, text: $text).keyboardType(.numberPad)
        }
        .font(.helvetica(size: 38, weight: .semibold))
    }
}

private struct PrimarySheetButton: View {
    let title: String
    let enabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.helvetica(.headline))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .foregroundStyle(Color.deepNavy)
                .background(.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.48)
    }
}

private struct DayDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    let day: ForecastDay
    let onRename: (ForecastEntryTarget, String, OccurrenceScope) -> Void
    let onDelete: (ForecastEntryTarget, OccurrenceScope) -> Void

    @State private var editedName: String
    @State private var showingRenameScope = false
    @State private var showingDeleteScope = false

    init(
        day: ForecastDay,
        onRename: @escaping (ForecastEntryTarget, String, OccurrenceScope) -> Void,
        onDelete: @escaping (ForecastEntryTarget, OccurrenceScope) -> Void
    ) {
        self.day = day
        self.onRename = onRename
        self.onDelete = onDelete
        _editedName = State(initialValue: day.activityTitle)
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: day.weather.backgroundColors,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 22) {
                    VStack(spacing: 9) {
                        Text("\(day.month.displayName) \(day.day) · \(day.status.label)")
                            .font(.helvetica(.subheadline, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.68))

                        Image(systemName: day.weather.symbol)
                            .font(.system(size: 64, weight: .medium))
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(day.weather.primaryColor, day.weather.secondaryColor)

                        Text(day.activityTitle)
                            .font(.helvetica(.title2, weight: .bold))

                        if day.isRecurring {
                            Label("Recurring", systemImage: "arrow.triangle.2.circlepath")
                                .font(.helvetica(.caption, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.62))
                        }

                        Text(day.formattedAmount)
                            .font(.helvetica(size: 50, weight: .light))
                            .monospacedDigit()
                    }
                    .padding(.top, 16)

                    VStack(spacing: 0) {
                        DetailRow(
                            icon: "arrow.down.left",
                            title: day.income > 0 ? "Income" : "No scheduled income",
                            subtitle: day.income > 0 ? day.incomeSource : "Nothing scheduled",
                            amount: day.income > 0 ? "+$\(day.income)" : "$0"
                        )
                        Divider().overlay(.white.opacity(0.12))
                        DetailRow(
                            icon: "arrow.up.right",
                            title: day.expenses > 0 ? "Spending & payments" : "No scheduled spending",
                            subtitle: day.expenseSource,
                            amount: day.expenses > 0 ? "−$\(day.expenses)" : "$0"
                        )
                        Divider().overlay(.white.opacity(0.12))
                        DetailRow(
                            icon: "equal",
                            title: "Net movement",
                            subtitle: "Mock daily total",
                            amount: day.formattedAmount
                        )
                    }
                    .padding(.horizontal, 16)
                    .background(.black.opacity(0.16), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(.white.opacity(0.12), lineWidth: 0.75)
                    }

                    if let target = day.entryTarget {
                        VStack(alignment: .leading, spacing: 12) {
                            if target.isCustom {
                                Text("ENTRY NAME")
                                    .font(.helvetica(.caption, weight: .bold))
                                    .tracking(1.1)
                                    .foregroundStyle(.white.opacity(0.58))
                                TextField("Entry name", text: $editedName)
                                    .padding(12)
                                    .background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                                Button("Save name") {
                                    if day.isRecurring {
                                        showingRenameScope = true
                                    } else {
                                        onRename(target, editedName, .onlyThis)
                                        dismiss()
                                    }
                                }
                                .buttonStyle(.bordered)
                                .tint(.white)
                            }

                            Button(role: .destructive) {
                                if day.isRecurring {
                                    showingDeleteScope = true
                                } else {
                                    onDelete(target, .onlyThis)
                                    dismiss()
                                }
                            } label: {
                                Label("Delete forecast entry", systemImage: "trash")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            .tint(Color.stormLavender)
                        }
                        .padding(16)
                        .background(.black.opacity(0.16), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    } else if day.isBankImported {
                        Label("Imported bank activity cannot be edited or deleted", systemImage: "lock.fill")
                            .font(.helvetica(.caption))
                            .foregroundStyle(.white.opacity(0.58))
                            .multilineTextAlignment(.center)
                            .padding(14)
                    }

                    Text("This breakdown uses demonstration data and will be replaced by the team’s financial model.")
                        .font(.helvetica(.caption))
                        .foregroundStyle(.white.opacity(0.52))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 28)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
        }
        .preferredColorScheme(.dark)
        .confirmationDialog("Rename recurring entry", isPresented: $showingRenameScope, titleVisibility: .visible) {
            if let target = day.entryTarget {
                Button("Only this entry") {
                    onRename(target, editedName, .onlyThis)
                    dismiss()
                }
                Button("All future occurrences") {
                    onRename(target, editedName, .allFuture)
                    dismiss()
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Choose whether this change applies once or to the recurring series.")
        }
        .confirmationDialog("Delete recurring entry", isPresented: $showingDeleteScope, titleVisibility: .visible) {
            if let target = day.entryTarget {
                Button("Only this entry", role: .destructive) {
                    onDelete(target, .onlyThis)
                    dismiss()
                }
                Button("All future occurrences", role: .destructive) {
                    onDelete(target, .allFuture)
                    dismiss()
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Bank activity is protected. This only changes your forecast.")
        }
    }
}

private struct DetailRow: View {
    let icon: String
    let title: String
    let subtitle: String
    let amount: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .bold))
                .frame(width: 32, height: 32)
                .background(.white.opacity(0.1), in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.helvetica(.subheadline, weight: .semibold))
                Text(subtitle)
                    .font(.helvetica(.caption))
                    .foregroundStyle(.white.opacity(0.55))
            }

            Spacer()

            Text(amount)
                .font(.helvetica(.subheadline, weight: .bold))
                .monospacedDigit()
        }
        .padding(.vertical, 14)
    }
}

private struct AddEntrySheet: View {
    @Environment(\.dismiss) private var dismiss
    let onSave: (FinancialEntry) -> Void

    @State private var entryKind = EntryKind.payment
    @State private var entryName = ""
    @State private var amountText = ""
    @State private var entryDate = MockForecast.todayDate
    @State private var schedule = EntrySchedule.oneTime
    @State private var repeatEvery = 1
    @State private var repeatUnit = RepeatUnit.month
    @State private var repeatEnding = RepeatEnding.never
    @State private var occurrenceCount = 6
    @State private var endDate = Calendar.current.date(byAdding: .month, value: 6, to: .now) ?? .now
    @FocusState private var amountIsFocused: Bool

    private var amount: Double? {
        Double(amountText.replacingOccurrences(of: ",", with: "."))
    }

    private var canSave: Bool {
        !entryName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && (amount ?? 0) > 0
    }

    private var accentWeather: MoneyWeather {
        entryKind == .income ? .sunny : .rain
    }

    private var recurrenceSummary: String {
        let cadence = repeatEvery == 1
            ? "Every \(repeatUnit.singular.lowercased())"
            : "Every \(repeatEvery) \(repeatUnit.plural.lowercased())"

        switch repeatEnding {
        case .never:
            return "\(cadence) · No end date"
        case .onDate:
            return "\(cadence) · Until \(endDate.formatted(date: .abbreviated, time: .omitted))"
        case .afterOccurrences:
            return "\(cadence) · \(occurrenceCount) times"
        }
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: accentWeather.backgroundColors,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 18) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("NEW ENTRY")
                                .font(.helvetica(.caption, weight: .bold))
                                .tracking(1.4)
                                .foregroundStyle(.white.opacity(0.62))
                            Text("Add to your forecast")
                                .font(.helvetica(.title2, weight: .bold))
                        }

                        Spacer()

                        Image(systemName: accentWeather.symbol)
                            .font(.system(size: 38, weight: .medium))
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(accentWeather.primaryColor, accentWeather.secondaryColor)
                            .contentTransition(.symbolEffect(.replace))
                    }
                    .padding(.top, 16)

                    EntryCard(title: "TYPE") {
                        Picker("Entry type", selection: $entryKind) {
                            ForEach(EntryKind.allCases) { kind in
                                Label(kind.title, systemImage: kind.symbol).tag(kind)
                            }
                        }
                        .pickerStyle(.segmented)
                    }

                    EntryCard(title: "ENTRY NAME") {
                        TextField(entryKind == .income ? "Campus job" : "Rent payment", text: $entryName)
                            .textInputAutocapitalization(.words)
                            .submitLabel(.next)
                    }

                    EntryCard(title: "AMOUNT") {
                        HStack(spacing: 6) {
                            Text("$")
                                .foregroundStyle(.white.opacity(0.5))
                            TextField("0.00", text: $amountText)
                                .keyboardType(.decimalPad)
                                .focused($amountIsFocused)
                        }
                        .font(.helvetica(size: 42, weight: .semibold))
                    }

                    EntryCard(title: "DATE") {
                        DatePicker(
                            "Entry date",
                            selection: $entryDate,
                            displayedComponents: .date
                        )
                        .datePickerStyle(.compact)
                        .tint(.white)
                    }

                    EntryCard(title: "SCHEDULE") {
                        Picker("Schedule", selection: $schedule) {
                            ForEach(EntrySchedule.allCases) { option in
                                Text(option.title).tag(option)
                            }
                        }
                        .pickerStyle(.segmented)

                        if schedule == .recurring {
                            Divider().overlay(.white.opacity(0.12))

                            HStack {
                                Text("Repeat every")
                                Spacer()
                                Stepper("\(repeatEvery)", value: $repeatEvery, in: 1...30)
                                    .fixedSize()
                            }

                            Picker("Frequency", selection: $repeatUnit) {
                                ForEach(RepeatUnit.allCases) { unit in
                                    Text(repeatEvery == 1 ? unit.singular : unit.plural).tag(unit)
                                }
                            }
                            .pickerStyle(.menu)
                            .tint(.white)

                            Picker("Ends", selection: $repeatEnding) {
                                ForEach(RepeatEnding.allCases) { ending in
                                    Text(ending.title).tag(ending)
                                }
                            }
                            .pickerStyle(.menu)
                            .tint(.white)

                            if repeatEnding == .onDate {
                                DatePicker("End date", selection: $endDate, in: entryDate..., displayedComponents: .date)
                                    .tint(.white)
                            } else if repeatEnding == .afterOccurrences {
                                Stepper("\(occurrenceCount) occurrences", value: $occurrenceCount, in: 2...60)
                            }

                            Text(recurrenceSummary)
                                .font(.helvetica(.caption))
                                .foregroundStyle(.white.opacity(0.56))
                        }
                    }

                    Button {
                        amountIsFocused = false
                        guard let amount, amount > 0 else { return }
                        let entry = FinancialEntry(
                            id: UUID(),
                            name: entryName.trimmingCharacters(in: .whitespacesAndNewlines),
                            kind: entryKind,
                            amount: Int(amount.rounded()),
                            startDate: entryDate,
                            schedule: schedule,
                            repeatEvery: repeatEvery,
                            repeatUnit: repeatUnit,
                            repeatEnding: repeatEnding,
                            occurrenceCount: occurrenceCount,
                            endDate: endDate
                        )
                        onSave(entry)
                        dismiss()
                    } label: {
                        Text("Add \(entryKind.title.lowercased())")
                            .font(.helvetica(.headline))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 15)
                            .foregroundStyle(Color.deepNavy)
                            .background(.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(!canSave)
                    .opacity(canSave ? 1 : 0.48)

                    Label("Entries update this demo forecast immediately", systemImage: "checkmark.circle")
                        .font(.helvetica(.caption))
                        .foregroundStyle(.white.opacity(0.52))
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 28)
            }
            .scrollIndicators(.hidden)
        }
        .preferredColorScheme(.dark)
        .animation(.easeInOut(duration: 0.35), value: entryKind)
        .animation(.easeInOut(duration: 0.25), value: schedule)
    }
}

private struct EntryCard<Content: View>: View {
    let title: String
    let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.helvetica(.caption, weight: .bold))
                .tracking(1.1)
                .foregroundStyle(.white.opacity(0.58))
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.black.opacity(0.16), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(.white.opacity(0.13), lineWidth: 0.75)
        }
    }
}

private enum EntryKind: String, CaseIterable, Identifiable, Codable {
    case payment
    case income

    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var symbol: String { self == .payment ? "arrow.up.right" : "arrow.down.left" }
}

private enum EntrySchedule: String, CaseIterable, Identifiable, Codable {
    case oneTime
    case recurring

    var id: String { rawValue }
    var title: String { self == .oneTime ? "One-time" : "Recurring" }
}

private enum RepeatUnit: String, CaseIterable, Identifiable, Codable {
    case day
    case week
    case month
    case year

    var id: String { rawValue }
    var singular: String { rawValue.capitalized }
    var plural: String { "\(rawValue.capitalized)s" }
}

private enum RepeatEnding: String, CaseIterable, Identifiable, Codable {
    case never
    case onDate
    case afterOccurrences

    var id: String { rawValue }

    var title: String {
        switch self {
        case .never: return "Never"
        case .onDate: return "On date"
        case .afterOccurrences: return "After occurrences"
        }
    }
}



/// Everything the user has told the app about their own plan: goals they added,
/// entries they scheduled, and the cash they want left untouched.
///
/// Nothing here is seeded with example data. An account with no goals and no
/// entries produces an empty plan, and the forecast shows only what the bank
/// actually reports.
private struct UserPlan: Codable, Equatable {
    var goals: [FinancialGoal] = []
    var entries: [FinancialEntry] = []
    var minimumCashReserve: Double?
    var cashMustLastUntil: Date?
    var deletedForecastDays: Set<String> = []
    var excludedOccurrences: Set<String> = []
    var occurrenceNameOverrides: [String: String] = [:]

    static let empty = UserPlan()
}

private enum PlanPersistence {
    private static var fileURL: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support
            .appendingPathComponent("Finanzas2026", isDirectory: true)
            .appendingPathComponent("user-plan.json")
    }

    static func load() -> UserPlan {
        guard let data = try? Data(contentsOf: fileURL) else { return .empty }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode(UserPlan.self, from: data)) ?? .empty
    }

    static func save(_ plan: UserPlan) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(plan) else { return }
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? data.write(to: fileURL, options: .atomic)
    }
}

private struct FinancialGoal: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    let targetAmount: Int
    var saved: Int
    let targetDate: Date
    let symbol: String
    /// Optional so plans saved before this field existed still decode.
    let isMandatory: Bool?
    let priority: GoalPriority
    let flexibility: GoalFlexibility
    var lifecycleState: GoalLifecycleState

    /// Must-happen goals are subtracted from the projected cash path, so they
    /// reduce safe-to-spend straight away. Nice-to-have goals stay out of the
    /// baseline and surface as trade-offs instead.
    var mustHappen: Bool { isMandatory ?? false }

    /// Used to show savings that accrued from underspending on top of whatever
    /// the user had already set aside.
    func withSaved(_ newSaved: Int) -> FinancialGoal {
        FinancialGoal(
            id: id,
            name: name,
            targetAmount: targetAmount,
            saved: newSaved,
            targetDate: targetDate,
            symbol: symbol,
            isMandatory: isMandatory,
            priority: priority,
            flexibility: flexibility,
            lifecycleState: lifecycleState
        )
    }

    var progress: Double {
        guard targetAmount > 0 else { return 0 }
        return min(1, Double(saved) / Double(targetAmount))
    }

    var remaining: Int { max(0, targetAmount - saved) }

    init(
        id: UUID,
        name: String,
        targetAmount: Int,
        saved: Int,
        targetDate: Date,
        symbol: String,
        isMandatory: Bool? = nil,
        priority: GoalPriority = .medium,
        flexibility: GoalFlexibility = .maxDelay(days: 30),
        lifecycleState: GoalLifecycleState = .active
    ) {
        self.id = id
        self.name = name
        self.targetAmount = targetAmount
        self.saved = saved
        self.targetDate = targetDate
        self.symbol = symbol
        self.isMandatory = isMandatory
        self.priority = priority
        self.flexibility = flexibility
        self.lifecycleState = lifecycleState
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, targetAmount, saved, targetDate, symbol, isMandatory
        case priority, flexibility, lifecycleState
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        targetAmount = try container.decode(Int.self, forKey: .targetAmount)
        saved = try container.decode(Int.self, forKey: .saved)
        targetDate = try container.decode(Date.self, forKey: .targetDate)
        symbol = try container.decode(String.self, forKey: .symbol)
        isMandatory = try container.decodeIfPresent(Bool.self, forKey: .isMandatory)
        priority = try container.decodeIfPresent(GoalPriority.self, forKey: .priority) ??
            (isMandatory == true ? .high : .medium)
        flexibility = try container.decodeIfPresent(GoalFlexibility.self, forKey: .flexibility) ??
            (isMandatory == true ? .fixed : .maxDelay(days: 30))
        lifecycleState = try container.decodeIfPresent(GoalLifecycleState.self, forKey: .lifecycleState) ?? .active
    }

}

private extension GoalPriority {
    var title: String {
        switch self {
        case .mandatory, .high: "High"
        case .medium: "Medium"
        case .low, .flexible: "Low"
        }
    }
}

private extension GoalFlexibility {
    /// Wording the user sees. `maxDelay` is expressed in the unit that reads best.
    var title: String {
        switch self {
        case .fixed:
            return "Fixed date"
        case .openEnded:
            return "Open-ended"
        case .maxDelay(let days):
            if days % 30 == 0 && days >= 30 {
                let months = days / 30
                return months == 1 ? "Up to 1 month" : "Up to \(months) months"
            }
            if days % 7 == 0 && days >= 7 {
                let weeks = days / 7
                return weeks == 1 ? "Up to 1 week" : "Up to \(weeks) weeks"
            }
            return "Up to \(days) days"
        }
    }

    /// The compact form used in dense rows.
    var shortTitle: String {
        switch self {
        case .fixed: return "Fixed"
        case .openEnded: return "Open"
        case .maxDelay(let days): return "±\(days)d"
        }
    }
}

private func goalProjectionTitle(_ status: GoalProjectionStatus) -> String {
    switch status {
    case .onTrack: "On track"
    case .adjusted: "Adjusted"
    case .atRisk: "At risk"
    case .unreachable: "Not reachable"
    case .paused: "Paused"
    case .completed: "Completed"
    }
}

private func goalProjectionColor(_ status: GoalProjectionStatus) -> Color {
    switch status {
    case .onTrack, .completed: .green
    case .adjusted, .atRisk: .orange
    case .unreachable: .red
    case .paused: .white.opacity(0.55)
    }
}

private func goalStatusTitle(_ status: GoalStatus) -> String {
    switch status {
    case .ahead: "Ahead"
    case .onTrack: "On track"
    case .behind: "Behind"
    case .atRisk: "At risk"
    case .unrealistic: "Needs a change"
    case .completed: "Completed"
    case .paused: "Paused"
    }
}

private func goalStatusColor(_ status: GoalStatus) -> Color {
    switch status {
    case .ahead, .onTrack, .completed: .green
    case .behind, .paused: .orange
    case .atRisk, .unrealistic: .red
    }
}

private struct FinancialEntry: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    let kind: EntryKind
    let amount: Int
    let startDate: Date
    let schedule: EntrySchedule
    let repeatEvery: Int
    let repeatUnit: RepeatUnit
    let repeatEnding: RepeatEnding
    let occurrenceCount: Int
    let endDate: Date

    var signedAmount: Int {
        kind == .income ? amount : -amount
    }

    func occurrenceKey(for date: Date) -> String {
        "\(id.uuidString)|\(Int(Calendar.current.startOfDay(for: date).timeIntervalSince1970))"
    }

    func occurrenceDates(through horizon: Date) -> [Date] {
        let calendar = Calendar(identifier: .gregorian)
        let firstDate = calendar.startOfDay(for: startDate)
        guard firstDate <= horizon else { return [] }
        guard schedule == .recurring else { return [firstDate] }

        var dates: [Date] = []
        var date = firstDate
        let maximumOccurrences = repeatEnding == .afterOccurrences ? occurrenceCount : 120

        while date <= horizon && dates.count < maximumOccurrences {
            if repeatEnding == .onDate && date > calendar.startOfDay(for: endDate) { break }
            dates.append(date)

            let component: Calendar.Component
            switch repeatUnit {
            case .day: component = .day
            case .week: component = .weekOfYear
            case .month: component = .month
            case .year: component = .year
            }

            guard let nextDate = calendar.date(byAdding: component, value: repeatEvery, to: date),
                  nextDate > date else { break }
            date = nextDate
        }

        return dates
    }
}

private struct EntryOccurrence {
    let entry: FinancialEntry
    let date: Date
    let key: String
    let displayName: String
}

private enum OccurrenceScope {
    case onlyThis
    case allFuture
}

private enum ForecastEntryTarget {
    case custom(entryID: UUID, occurrenceKey: String)
    case forecastDay(dayID: String)

    var isCustom: Bool {
        if case .custom = self { return true }
        return false
    }
}

private struct AtmosphericBackground: View {
    let weather: MoneyWeather

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                LinearGradient(
                    colors: weather.backgroundColors,
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                RadialGradient(
                    colors: [weather.glowColor.opacity(0.42), .clear],
                    center: .topTrailing,
                    startRadius: 12,
                    endRadius: geometry.size.width * 0.9
                )

                Image(systemName: weather.atmosphericSymbol)
                    .font(.system(size: 280, weight: .ultraLight))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.white.opacity(0.055))
                    .offset(x: geometry.size.width * 0.25, y: -geometry.size.height * 0.29)

                if weather == .rain || weather == .storm {
                    ForEach(0..<14, id: \.self) { index in
                        Capsule()
                            .fill(.white.opacity(weather == .storm ? 0.08 : 0.055))
                            .frame(width: 2, height: CGFloat(22 + (index % 3) * 9))
                            .rotationEffect(.degrees(16))
                            .position(
                                x: CGFloat((index * 47) % 430),
                                y: CGFloat(110 + ((index * 83) % 760))
                            )
                    }
                }

                LinearGradient(
                    colors: [.clear, .black.opacity(0.22)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .animation(.easeInOut(duration: 0.55), value: weather)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

private enum ForecastMonth: Int, CaseIterable, Identifiable {
    case may = 202605
    case june = 202606
    case july = 202607
    case august = 202608
    case september = 202609
    case october = 202610
    case november = 202611
    case december = 202612
    case january2027 = 202701
    case february2027 = 202702
    case march2027 = 202703
    case april2027 = 202704
    case may2027 = 202705
    case june2027 = 202706
    case july2027 = 202707
    case august2027 = 202708
    case september2027 = 202709

    var id: Int { rawValue }
    var year: Int { rawValue / 100 }
    var monthNumber: Int { rawValue % 100 }

    var displayName: String {
        year == 2026 ? monthName : "\(monthName) \(year)"
    }

    var abbreviation: String {
        String(monthName.prefix(3)).uppercased()
    }

    var dayCount: Int {
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.year = year
        components.month = monthNumber
        components.day = 1
        guard let date = components.date,
              let range = components.calendar?.range(of: .day, in: .month, for: date) else { return 30 }
        return range.count
    }

    var yearLabel: String {
        "’\(String(year).suffix(2))"
    }

    var previousName: String {
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.year = year
        components.month = monthNumber - 1
        components.day = 1
        return components.date?.formatted(.dateTime.month(.wide)) ?? "previous month"
    }

    var monthName: String {
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.year = year
        components.month = monthNumber
        components.day = 1
        return components.date?.formatted(.dateTime.month(.wide)) ?? abbreviation
    }

    /// The month containing today, falling back to September 2026 when today is
    /// outside the enumerated range.
    static var current: ForecastMonth {
        containing(Date()) ?? .september
    }

    var isPast: Bool { rawValue < ForecastMonth.current.rawValue }
    var isCurrent: Bool { self == ForecastMonth.current }
    var isFuture: Bool { rawValue > ForecastMonth.current.rawValue }

    static func containing(_ date: Date) -> ForecastMonth? {
        let calendar = Calendar(identifier: .gregorian)
        let value = calendar.component(.year, from: date) * 100 + calendar.component(.month, from: date)
        return ForecastMonth(rawValue: value)
    }
}

private enum DayStatus {
    case recorded
    case today
    case forecast

    var label: String {
        switch self {
        case .recorded: return "Recorded"
        case .today: return "Today"
        case .forecast: return "Forecast"
        }
    }

    var symbol: String {
        switch self {
        case .recorded: return "checkmark"
        case .today: return "circle.fill"
        case .forecast: return "sparkles"
        }
    }

    var foregroundColor: Color {
        switch self {
        case .recorded: return .white.opacity(0.42)
        case .today: return Color.sunGold
        case .forecast: return .white.opacity(0.5)
        }
    }
}

private enum MoneyWeather: String, CaseIterable {
    case sunny
    case partlySunny
    case cloudy
    case rain
    case storm

    var symbol: String {
        switch self {
        case .sunny: return "sun.max.fill"
        case .partlySunny: return "cloud.sun.fill"
        case .cloudy: return "cloud.fill"
        case .rain: return "cloud.rain.fill"
        case .storm: return "cloud.bolt.rain.fill"
        }
    }

    var atmosphericSymbol: String {
        switch self {
        case .sunny: return "sun.max.fill"
        case .partlySunny: return "cloud.sun.fill"
        case .cloudy: return "cloud.fill"
        case .rain: return "cloud.rain.fill"
        case .storm: return "cloud.bolt.fill"
        }
    }

    var dailyTitle: String {
        switch self {
        case .sunny: return "Income boost"
        case .partlySunny: return "Light income"
        case .cloudy: return "Nearly steady"
        case .rain: return "Money going out"
        case .storm: return "Large outflow"
        }
    }

    var primaryColor: Color {
        switch self {
        case .sunny: return Color.sunGold
        case .partlySunny: return Color.white
        case .cloudy: return Color.cloudSilver
        case .rain: return Color.cloudSilver
        case .storm: return Color.cloudSlate
        }
    }

    var secondaryColor: Color {
        switch self {
        case .sunny: return Color.sunOrange
        case .partlySunny: return Color.sunGold
        case .cloudy: return Color.cloudSlate
        case .rain: return Color.rainBlue
        case .storm: return Color.stormLavender
        }
    }

    var amountColor: Color {
        switch self {
        case .sunny: return Color.sunGold
        case .partlySunny: return Color.cloudCream
        case .cloudy: return .white.opacity(0.72)
        case .rain: return Color.rainMist
        case .storm: return Color.stormLavender
        }
    }

    var backgroundColors: [Color] {
        switch self {
        case .sunny:
            return [Color(hex: 0x1765A3), Color(hex: 0x3E94C9), Color(hex: 0xD19B4D)]
        case .partlySunny:
            return [Color(hex: 0x174D7A), Color(hex: 0x3C7DA6), Color(hex: 0x739EB3)]
        case .cloudy:
            return [Color(hex: 0x263E57), Color(hex: 0x526A7D), Color(hex: 0x6F7F8B)]
        case .rain:
            return [Color(hex: 0x162E4C), Color(hex: 0x285273), Color(hex: 0x426A82)]
        case .storm:
            return [Color(hex: 0x11172C), Color(hex: 0x202B50), Color(hex: 0x3A4168)]
        }
    }

    var glowColor: Color {
        switch self {
        case .sunny, .partlySunny: return Color.sunGold
        case .cloudy: return Color.cloudSilver
        case .rain: return Color.rainMist
        case .storm: return Color.stormLavender
        }
    }
}

private struct ForecastDay: Identifiable {
    let id: String
    let month: ForecastMonth
    let day: Int
    let weekday: String
    let amount: Int
    let weather: MoneyWeather
    let status: DayStatus
    let income: Int
    let expenses: Int
    let incomeSource: String
    let expenseSource: String
    let entryTitle: String?
    let entryTarget: ForecastEntryTarget?
    let isRecurring: Bool
    let isBankImported: Bool

    var formattedAmount: String {
        if amount > 0 { return "+$\(amount)" }
        if amount < 0 { return "−$\(abs(amount))" }
        return "$0"
    }

    var activityTitle: String {
        entryTitle ?? (amount == 0 ? "No activity" : weather.dailyTitle)
    }
}

private struct MonthForecast {
    let month: ForecastMonth
    let accountBalance: Int
    let balanceLabel: String
    let overallWeather: MoneyWeather
    let conditionTitle: String
    let summary: String
    let averageDailySpending: Double
    let previousMonthDelta: Int
    let allTimeDelta: Int
    let days: [ForecastDay]
}

private enum BalanceSeries: String {
    case actual = "Actual"
    case expected = "Expected"

    var color: Color {
        switch self {
        case .actual: return .white
        case .expected: return Color.sunGold
        }
    }
}

private struct BalancePoint: Identifiable {
    let id: String
    let date: Date
    let balance: Double
    let series: BalanceSeries
    let isAnchor: Bool
}

private enum MockForecast {
    static var todayDate: Date { Calendar(identifier: .gregorian).startOfDay(for: Date()) }
    static let balancePoints: [BalancePoint] = []

    static func balancePoints(
        including entries: [FinancialEntry],
        excludingForecastDays: Set<String> = [],
        excludingOccurrences: Set<String> = []
    ) -> [BalancePoint] {
        let horizon = makeDate(year: 2027, month: 9, day: 30)
        let occurrences = entryOccurrences(
            for: entries,
            through: horizon,
            excluding: excludingOccurrences,
            nameOverrides: [:]
        )
        let deletedAdjustments = forecastDeletionAdjustments(for: excludingForecastDays)

        let adjustedBasePoints = Self.balancePoints.map { point in
            let adjustment = occurrences
                .filter { $0.date <= point.date }
                .reduce(0) { $0 + $1.entry.signedAmount }
                + deletedAdjustments
                    .filter { $0.date <= point.date }
                    .reduce(0) { $0 + $1.amount }

            return BalancePoint(
                id: point.id,
                date: point.date,
                balance: point.balance + Double(adjustment),
                series: point.series,
                isAnchor: point.isAnchor
            )
        }

        let entryPoints = occurrences.compactMap { occurrence -> BalancePoint? in
            guard occurrence.date >= makeDate(year: 2026, month: 5, day: 1) else { return nil }
            let baseBalance = Self.balancePoints
                .filter { $0.date <= occurrence.date }
                .last?.balance ?? Self.balancePoints.first?.balance ?? 0
            let adjustment = occurrences
                .filter { $0.date <= occurrence.date }
                .reduce(0) { $0 + $1.entry.signedAmount }
                + deletedAdjustments
                    .filter { $0.date <= occurrence.date }
                    .reduce(0) { $0 + $1.amount }

            return BalancePoint(
                id: "entry-\(occurrence.entry.id.uuidString)-\(occurrence.date.timeIntervalSince1970)",
                date: occurrence.date,
                balance: baseBalance + Double(adjustment),
                series: occurrence.date <= todayDate ? .actual : .expected,
                isAnchor: true
            )
        }

        return (adjustedBasePoints + entryPoints).sorted {
            if $0.date == $1.date { return $0.series.rawValue < $1.series.rawValue }
            return $0.date < $1.date
        }
    }

    static func data(
        for month: ForecastMonth,
        including entries: [FinancialEntry] = [],
        excludingForecastDays: Set<String> = [],
        excludingOccurrences: Set<String> = [],
        occurrenceNameOverrides: [String: String] = [:],
        live: LiveFinancialContext = .empty
    ) -> MonthForecast {
        let balanceLabel: String
        if month.isPast {
            balanceLabel = "Closing account balance"
        } else if month.isCurrent {
            balanceLabel = "Current account balance"
        } else {
            balanceLabel = "Projected closing balance"
        }

        let calendar = Calendar(identifier: .gregorian)
        let monthEnd = makeDate(year: month.year, month: month.monthNumber, day: month.dayCount)
        let balanceCutoff = month.isCurrent ? todayDate : monthEnd
        let occurrences = entryOccurrences(
            for: entries,
            through: makeDate(year: 2027, month: 9, day: 30),
            excluding: excludingOccurrences,
            nameOverrides: occurrenceNameOverrides
        )
        let deletedAdjustments = forecastDeletionAdjustments(for: excludingForecastDays)
        let balanceAdjustment = occurrences
            .filter { $0.date <= balanceCutoff }
            .reduce(0) { $0 + $1.entry.signedAmount }
            + deletedAdjustments
                .filter { $0.date <= balanceCutoff }
                .reduce(0) { $0 + $1.amount }
        let monthOccurrences = occurrences.filter {
            calendar.component(.year, from: $0.date) == month.year &&
            calendar.component(.month, from: $0.date) == month.monthNumber
        }
        let addedSpending = monthOccurrences
            .filter { $0.entry.kind == .payment }
            .reduce(0) { $0 + $1.entry.amount }
        let removedSpending = (1...month.dayCount)
            .filter { excludingForecastDays.contains("\(month.rawValue)-\($0)") }
            .map { mockAmount(month: month, day: $0) }
            .filter { $0 < 0 }
            .reduce(0) { $0 + abs($1) }
        let liveBalance = live.balance(asOf: balanceCutoff).map { Int($0.rounded()) } ?? 0
        let adjustedBalance = liveBalance + balanceAdjustment
        let hasData = live.hasData || !entries.isEmpty
        let adjustedWeather: MoneyWeather
        if !hasData {
            adjustedWeather = .cloudy
        } else {
            if let health = live.health(year: month.year, month: month.monthNumber) {
                switch health {
                case .safe: adjustedWeather = .sunny
                case .tight: adjustedWeather = .rain
                case .notSafe: adjustedWeather = .storm
                }
            } else {
                adjustedWeather = comfortWeather(for: adjustedBalance)
            }
        }

        let days = makeDays(
            for: month,
            occurrences: monthOccurrences,
            excludingForecastDays: excludingForecastDays,
            live: live
        )
        let monthSpending = days.reduce(0) { $0 + $1.expenses }
        let monthIncome = days.reduce(0) { $0 + $1.income }

        let summary: String
        if !hasData {
            summary = "Connect a bank account or add an entry to begin your financial forecast."
        } else if month.isPast {
            summary = "\(month.displayName) recorded $\(monthIncome) in and $\(monthSpending) out."
        } else {
            summary = "Projected from your linked accounts, scheduled bills, and confirmed context."
        }

        return MonthForecast(
            month: month,
            accountBalance: adjustedBalance,
            balanceLabel: balanceLabel,
            overallWeather: adjustedWeather,
            conditionTitle: hasData ? conditionTitle(for: adjustedWeather) : "No Data Yet",
            summary: summary,
            averageDailySpending: max(
                0,
                Double(monthSpending + addedSpending - removedSpending) / Double(month.dayCount)
            ),
            previousMonthDelta: 0,
            allTimeDelta: 0,
            days: days
        )
    }

    private static func makeDays(
        for month: ForecastMonth,
        occurrences: [EntryOccurrence] = [],
        excludingForecastDays: Set<String> = [],
        live: LiveFinancialContext = .empty
    ) -> [ForecastDay] {
        (1...month.dayCount).map { day in
            let date = makeDate(year: month.year, month: month.monthNumber, day: day)
            let dayID = "\(month.rawValue)-\(day)"
            let status = status(for: month, day: day)
            let isExcluded = excludingForecastDays.contains(dayID)

            // Recorded days come from the bank; today and future days come from
            // the profile's scheduled events on the engine's projected path.
            let bank = live.recorded(on: date)
            let baseIncome = isExcluded ? 0 : bank.income
            let baseExpenses = isExcluded ? 0 : bank.expenses

            let matchingEntries = occurrences.filter {
                Calendar.current.component(.day, from: $0.date) == day
            }
            let entryIncome = matchingEntries
                .filter { $0.entry.kind == .income }
                .reduce(0) { $0 + $1.entry.amount }
            let entryExpenses = matchingEntries
                .filter { $0.entry.kind == .payment }
                .reduce(0) { $0 + $1.entry.amount }

            let income = baseIncome + entryIncome
            let expenses = baseExpenses + entryExpenses
            let amount = income - expenses

            // Forecast weather follows the health of the projected cash path, so a
            // large planned bill is not automatically a bad day. Recorded days have
            // no projection left to judge, so they describe what actually moved.
            let dayWeather: MoneyWeather
            if status == .recorded {
                dayWeather = weather(for: amount)
            } else if let health = live.health(on: date) {
                switch health {
                case .safe: dayWeather = .sunny
                case .tight: dayWeather = .rain
                case .notSafe: dayWeather = .storm
                }
            } else {
                dayWeather = weather(for: amount)
            }

            let customNames = matchingEntries.map(\.displayName).joined(separator: ", ")
            let entryTitle: String?
            if matchingEntries.count == 1 && baseIncome == 0 && baseExpenses == 0 {
                entryTitle = matchingEntries[0].displayName
            } else if !matchingEntries.isEmpty {
                entryTitle = "\(matchingEntries.count) entries"
            } else {
                entryTitle = nil
            }

            let entryTarget: ForecastEntryTarget?
            if matchingEntries.count == 1 {
                entryTarget = .custom(
                    entryID: matchingEntries[0].entry.id,
                    occurrenceKey: matchingEntries[0].key
                )
            } else if status == .forecast && amount != 0 {
                entryTarget = .forecastDay(dayID: dayID)
            } else {
                entryTarget = nil
            }

            let incomeSource: String
            if matchingEntries.contains(where: { $0.entry.kind == .income }) {
                incomeSource = customNames
            } else if bank.income > 0 {
                incomeSource = bank.incomeSource
            } else {
                incomeSource = status == .recorded ? "Nothing recorded" : "Nothing scheduled"
            }

            let expenseSource: String
            if matchingEntries.contains(where: { $0.entry.kind == .payment }) {
                expenseSource = customNames
            } else if bank.expenses > 0 {
                expenseSource = bank.expenseSource
            } else {
                expenseSource = status == .recorded ? "Nothing recorded" : "Nothing scheduled"
            }

            return ForecastDay(
                id: dayID,
                month: month,
                day: day,
                weekday: weekday(month: month, day: day),
                amount: amount,
                weather: dayWeather,
                status: status,
                income: income,
                expenses: expenses,
                incomeSource: incomeSource,
                expenseSource: expenseSource,
                entryTitle: entryTitle,
                entryTarget: entryTarget,
                isRecurring: matchingEntries.contains { $0.entry.schedule == .recurring },
                isBankImported: matchingEntries.isEmpty && (bank.income > 0 || bank.expenses > 0)
            )
        }
    }

    private static func entryOccurrences(
        for entries: [FinancialEntry],
        through horizon: Date,
        excluding excludedKeys: Set<String>,
        nameOverrides: [String: String]
    ) -> [EntryOccurrence] {
        entries.flatMap { entry in
            entry.occurrenceDates(through: horizon).compactMap { date in
                let key = entry.occurrenceKey(for: date)
                guard !excludedKeys.contains(key) else { return nil }
                return EntryOccurrence(
                    entry: entry,
                    date: date,
                    key: key,
                    displayName: nameOverrides[key] ?? entry.name
                )
            }
        }
    }

    private static func forecastDeletionAdjustments(
        for deletedDayIDs: Set<String>
    ) -> [(date: Date, amount: Int)] {
        ForecastMonth.allCases.flatMap { month in
            (1...month.dayCount).compactMap { day in
                let dayID = "\(month.rawValue)-\(day)"
                let amount = mockAmount(month: month, day: day)
                guard deletedDayIDs.contains(dayID), amount != 0 else { return nil }
                return (makeDate(year: month.year, month: month.monthNumber, day: day), -amount)
            }
        }
    }

    private static func comfortWeather(for balance: Int) -> MoneyWeather {
        if balance >= 2000 { return .sunny }
        if balance >= 1400 { return .partlySunny }
        if balance >= 900 { return .cloudy }
        if balance >= 300 { return .rain }
        return .storm
    }

    private static func conditionTitle(for weather: MoneyWeather) -> String {
        switch weather {
        case .sunny: return "Clear"
        case .partlySunny: return "Mostly Clear"
        case .cloudy: return "A Little Cloudy"
        case .rain: return "Rain Possible"
        case .storm: return "High Pressure"
        }
    }

    private static func mockAmount(month: ForecastMonth, day: Int) -> Int {
        0
    }

    private static func weather(for amount: Int) -> MoneyWeather {
        if amount >= 150 { return .sunny }
        if amount > 10 { return .partlySunny }
        if amount >= -25 { return .cloudy }
        if amount > -200 { return .rain }
        return .storm
    }

    private static func status(for month: ForecastMonth, day: Int) -> DayStatus {
        if month.isPast { return .recorded }
        if month.isCurrent {
            let todayDay = Calendar(identifier: .gregorian).component(.day, from: Date())
            if day < todayDay { return .recorded }
            if day == todayDay { return .today }
        }
        return .forecast
    }

    private static func weekday(month: ForecastMonth, day: Int) -> String {
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.year = month.year
        components.month = month.monthNumber
        components.day = day

        guard let date = components.date else { return "Day" }
        return date.formatted(.dateTime.weekday(.abbreviated))
    }

    private static func makeDate(year: Int, month: Int, day: Int) -> Date {
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.year = year
        components.month = month
        components.day = day
        return components.date ?? Date(timeIntervalSince1970: 0)
    }
}

private extension Color {
    static let deepNavy = Color(hex: 0x0A1D31)
    static let sunGold = Color(hex: 0xFFD45A)
    static let sunOrange = Color(hex: 0xF7A84A)
    static let cloudCream = Color(hex: 0xF4E7C5)
    static let cloudSilver = Color(hex: 0xC7D1D9)
    static let cloudSlate = Color(hex: 0x7D909F)
    static let rainBlue = Color(hex: 0x62A9E8)
    static let rainMist = Color(hex: 0xADD9F2)
    static let stormBlue = Color(hex: 0x586AA6)
    static let stormLavender = Color(hex: 0xC2C8FF)

    init(hex: UInt, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xff) / 255,
            green: Double((hex >> 8) & 0xff) / 255,
            blue: Double(hex & 0xff) / 255,
            opacity: opacity
        )
    }
}

private extension Font {
    static func helvetica(
        _ style: Font.TextStyle,
        weight: Font.Weight = .regular
    ) -> Font {
        let size: CGFloat
        switch style {
        case .largeTitle: size = 34
        case .title: size = 28
        case .title2: size = 22
        case .title3: size = 20
        case .headline: size = 17
        case .subheadline: size = 15
        case .body: size = 17
        case .callout: size = 16
        case .footnote: size = 13
        case .caption: size = 12
        case .caption2: size = 11
        @unknown default: size = 17
        }

        return .system(size: size, weight: weight, design: .default)
    }

    static func helvetica(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
}

#Preview {
    ContentView()
}
