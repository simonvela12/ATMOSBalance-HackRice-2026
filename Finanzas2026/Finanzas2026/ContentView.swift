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

    /// Rebuilding the profile and the projected path is expensive, and the forecast
    /// views read `month` many times per render, so it is cached and refreshed only
    /// when the linked-bank data actually changes.
    private var currentPlan: UserPlan {
        UserPlan(
            goals: goals,
            entries: addedEntries,
            minimumCashReserve: minimumCashReserve,
            deletedForecastDays: deletedForecastDays,
            excludedOccurrences: excludedOccurrences,
            occurrenceNameOverrides: occurrenceNameOverrides
        )
    }

    private func restorePlan() {
        let plan = PlanPersistence.load()
        goals = plan.goals
        addedEntries = plan.entries
        minimumCashReserve = plan.minimumCashReserve
        deletedForecastDays = plan.deletedForecastDays
        excludedOccurrences = plan.excludedOccurrences
        occurrenceNameOverrides = plan.occurrenceNameOverrides
    }

    /// The user's own goals and scheduled entries, translated into the engine's
    /// vocabulary. Goals the user adds are flexible by default; nothing is assumed
    /// on their behalf.
    private var engineGoals: [FinancialCore.Goal] {
        goals.map { goal in
            FinancialCore.Goal(
                id: goal.id,
                name: goal.name,
                targetAmount: Double(goal.targetAmount),
                amountAlreadyPaid: Double(goal.saved),
                deadline: goal.targetDate,
                priority: .flexible
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
        let profile = AppFinancialData.profile(
            currentCash: bankStore.totalAvailableCash,
            transactions: bankStore.transactions,
            goals: engineGoals,
            plannedIncome: planned.income,
            plannedExpenses: planned.expenses,
            minimumCashReserve: minimumCashReserve
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
            timeline: timeline
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
            WhatIfSheet(accountBalance: month.accountBalance, goals: goals)
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

            Text("DEMO")
                .font(.helvetica(.caption2, weight: .bold))
                .tracking(0.8)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.white.opacity(0.12), in: Capsule())

            Button(action: {}) {
                Image(systemName: "person.crop.circle.fill")
                    .font(.system(size: 30))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.white.opacity(0.92))
            }
            .accessibilityLabel("Profile")
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
            goals: goals,
            onAdd: {
                goalBeingEdited = nil
                showingAddGoal = true
            },
            onEdit: { goal in
                goalBeingEdited = goal
                showingAddGoal = true
            },
            onDelete: { goal in
                goalPendingDeletion = goal
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
    let onAdd: () -> Void
    let onEdit: (FinancialGoal) -> Void
    let onDelete: (FinancialGoal) -> Void

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
                                onEdit: { onEdit(goal) },
                                onDelete: { onDelete(goal) }
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

private struct GoalProgressTile: View {
    let goal: FinancialGoal
    let onEdit: () -> Void
    let onDelete: () -> Void

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

            Text(goal.name)
                .font(.helvetica(.headline, weight: .semibold))
                .lineLimit(1)

            Text(goal.targetDate, format: .dateTime.month(.abbreviated).day().year())
                .font(.helvetica(.caption2, weight: .medium))
                .foregroundStyle(.white.opacity(0.48))

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

    init(existingGoal: FinancialGoal? = nil, onSave: @escaping (FinancialGoal) -> Void) {
        self.existingGoal = existingGoal
        self.onSave = onSave
        _name = State(initialValue: existingGoal?.name ?? "")
        _amountText = State(initialValue: existingGoal.map { String($0.targetAmount) } ?? "")
        _savedText = State(initialValue: existingGoal.map { String($0.saved) } ?? "")
        _targetDate = State(initialValue: existingGoal?.targetDate ?? Calendar.current.date(byAdding: .month, value: 4, to: MockForecast.todayDate) ?? MockForecast.todayDate)
        _symbol = State(initialValue: existingGoal?.symbol ?? "airplane")
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
                            symbol: symbol
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

private struct WhatIfSheet: View {
    let accountBalance: Int
    let goals: [FinancialGoal]

    @State private var amountText = ""
    @State private var schedule = EntrySchedule.oneTime
    @State private var repeatEvery = 1
    @State private var repeatUnit = RepeatUnit.month

    private var amount: Int { Int(amountText.filter(\.isNumber)) ?? 0 }
    private var threeMonthCost: Int {
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
    private var projectedBalance: Int { accountBalance - threeMonthCost }
    private var resultWeather: MoneyWeather {
        if projectedBalance >= 1500 { return .partlySunny }
        if projectedBalance >= 900 { return .cloudy }
        if projectedBalance >= 300 { return .rain }
        return .storm
    }

    var body: some View {
        ZStack {
            LinearGradient(colors: resultWeather.backgroundColors, startPoint: .topLeading, endPoint: .bottomTrailing)
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 18) {
                    SheetTitle(eyebrow: "WHAT IF?", title: schedule == .recurring ? "Try a recurring payment" : "Try a purchase", symbol: resultWeather.symbol)

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

                    if amount > 0 {
                        VStack(spacing: 0) {
                            ScenarioMetric(title: "Balance now", value: "$\(accountBalance.formatted())")
                            Divider().overlay(.white.opacity(0.12))
                            ScenarioMetric(title: schedule == .recurring ? "Balance after 90 days" : "Balance after purchase", value: "$\(projectedBalance.formatted())")
                            if schedule == .recurring {
                                Divider().overlay(.white.opacity(0.12))
                                ScenarioMetric(title: "Estimated 90-day cost", value: "−$\(threeMonthCost.formatted())")
                            }
                        }
                        .padding(.horizontal, 16)
                        .background(.black.opacity(0.16), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                        VStack(alignment: .leading, spacing: 14) {
                            Text("GOAL IMPACT")
                                .font(.helvetica(.caption, weight: .bold))
                                .tracking(1.1)
                                .foregroundStyle(.white.opacity(0.6))
                            ForEach(goals) { goal in
                                WhatIfGoalRow(goal: goal, purchaseImpact: threeMonthCost)
                            }
                        }
                        .padding(16)
                        .background(.black.opacity(0.16), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    } else {
                        Text("Enter an amount to see the effect on your balance and goals. Nothing here changes your real forecast.")
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
    }
}

private struct WhatIfGoalRow: View {
    let goal: FinancialGoal
    let purchaseImpact: Int

    private var delayDays: Int { max(1, Int(ceil(Double(purchaseImpact) / 18.0))) }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: goal.symbol)
                .frame(width: 34, height: 34)
                .background(.white.opacity(0.1), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(goal.name).font(.helvetica(.subheadline, weight: .semibold))
                Text("Could delay this goal by about \(delayDays) days")
                    .font(.helvetica(.caption))
                    .foregroundStyle(.white.opacity(0.54))
            }
            Spacer()
            Text("−$\(min(purchaseImpact, goal.remaining).formatted())")
                .font(.helvetica(.caption, weight: .bold))
                .foregroundStyle(Color.sunGold)
        }
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

private struct FinancialGoal: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    let targetAmount: Int
    let saved: Int
    let targetDate: Date
    let symbol: String

    var progress: Double {
        guard targetAmount > 0 else { return 0 }
        return min(1, Double(saved) / Double(targetAmount))
    }

    var remaining: Int { max(0, targetAmount - saved) }

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

/// Real financial data, shaped for Marc's forecast views.
///
/// Marc's forecast UI is kept exactly as-is; this supplies the numbers it used to
/// take from demo data. Recorded days come from linked-bank transactions, future
/// days come from FinancialCore's projected cash path.
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

private struct LiveFinancialContext {
    let profile: FinancialProfile?
    let transactions: [FinanceCore.FinancialTransaction]
    let timeline: [CashFlowPoint]

    /// Grouped once at construction: these lookups run for every rendered day.
    private let transactionsByDay: [Date: [FinanceCore.FinancialTransaction]]
    private let timelineByDay: [Date: CashFlowPoint]

    init(
        profile: FinancialProfile?,
        transactions: [FinanceCore.FinancialTransaction],
        timeline: [CashFlowPoint]
    ) {
        self.profile = profile
        self.transactions = transactions
        self.timeline = timeline

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

    func overallWeather(for month: ForecastMonth) -> MoneyWeather? {
        guard profile != nil else { return nil }
        let statuses = timeline
            .filter {
                calendar.component(.year, from: $0.date) == month.year &&
                calendar.component(.month, from: $0.date) == month.monthNumber
            }
            .map(\.status)

        guard !statuses.isEmpty else { return nil }
        if statuses.contains(.notSafe) { return .storm }
        if statuses.contains(.tight) { return .rain }
        return .sunny
    }

    // MARK: Labels

    private static func label(_ items: [FinanceCore.FinancialTransaction]) -> String {
        let sorted = items.sorted { $0.amountMinorUnits > $1.amountMinorUnits }
        guard let first = sorted.first else { return "Nothing recorded" }
        let name = AppFinancialData.label(first)
        return sorted.count > 1 ? "\(name) + \(sorted.count - 1) more" : name
    }

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
            adjustedWeather = live.overallWeather(for: month) ?? comfortWeather(for: adjustedBalance)
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
