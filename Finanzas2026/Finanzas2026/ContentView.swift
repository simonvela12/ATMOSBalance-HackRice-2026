import SwiftUI
import Charts

struct ContentView: View {
    @State private var selectedMonth = ForecastMonth.september
    @State private var selectedDay: ForecastDay?
    @State private var showingAddEntry = false
    @State private var showingWhatIf = false
    @State private var showingAddGoal = false
    @State private var showingGoals = false
    @State private var showingSpendableDetails = false
    @State private var showingCalendar = false
    @State private var showingFullMonth = false
    @State private var addedEntries: [FinancialEntry] = []
    @State private var goals: [FinancialGoal] = []
    @State private var goalBeingEdited: FinancialGoal?
    @State private var goalBeingAllocated: FinancialGoal?
    @State private var goalPendingDeletion: FinancialGoal?
    @State private var deletedForecastDays: Set<String> = []
    @State private var excludedOccurrences: Set<String> = []
    @State private var occurrenceNameOverrides: [String: String] = [:]

    private var month: MonthForecast {
        MockForecast.data(
            for: selectedMonth,
            including: addedEntries,
            excludingForecastDays: deletedForecastDays,
            excludingOccurrences: excludedOccurrences,
            occurrenceNameOverrides: occurrenceNameOverrides
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

    private var currentGoals: [FinancialGoal] {
        goals
            .filter { !$0.isCompleted }
            .sorted {
                if $0.priority.rank == $1.priority.rank { return $0.targetDate < $1.targetDate }
                return $0.priority.rank < $1.priority.rank
            }
    }

    private var reservedForGoals: Double {
        currentGoals.reduce(0) { $0 + $1.saved }
    }

    private var upcomingPaymentActivities: [ForecastActivity] {
        guard selectedMonth.isCurrent else { return [] }
        return month.days
            .filter { $0.status == .forecast }
            .flatMap(\.activities)
            .filter { $0.kind == .payment }
    }

    private var reservedForPayments: Double {
        upcomingPaymentActivities.reduce(0) { $0 + $1.amount }
    }

    private var spendableBalance: Double {
        month.accountBalance - reservedForGoals - reservedForPayments
    }

    private var presentationWeather: MoneyWeather {
        guard selectedMonth.isCurrent,
              let today = month.days.first(where: { $0.status == .today && $0.amount != 0 }) else {
            return month.overallWeather
        }
        return MoneyWeather.blended(monthly: month.overallWeather, daily: today.weather)
    }

    private var presentationConditionTitle: String {
        presentationWeather == month.overallWeather ? month.conditionTitle : presentationWeather.conditionTitle
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
            AtmosphericBackground(weather: presentationWeather)

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
            WhatIfSheet(
                accountBalance: month.accountBalance,
                spendableBalance: spendableBalance,
                goals: currentGoals
            )
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
        .sheet(isPresented: $showingGoals) {
            ExpandedGoalsSheet(goals: $goals, accountBalance: month.accountBalance)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showingSpendableDetails) {
            SpendableBreakdownSheet(
                totalBalance: month.accountBalance,
                goals: currentGoals,
                payments: upcomingPaymentActivities
            )
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .sheet(item: $goalBeingAllocated) { goal in
            AllocateMoneySheet(
                goal: goal,
                spendableBalance: max(0, spendableBalance)
            ) { amount in
                if let index = goals.firstIndex(where: { $0.id == goal.id }) {
                    goals[index].saved = min(goals[index].targetAmount, max(0, amount))
                }
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
                goals: currentGoals,
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

            Text(month.accountBalance.currencyText)
                .font(.helvetica(size: 74, weight: .thin))
                .tracking(-4)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
                .contentTransition(.numericText(value: month.accountBalance))

            Text(month.balanceLabel)
                .font(.helvetica(.title3, weight: .medium))
                .foregroundStyle(.white.opacity(0.9))

            HStack(spacing: 5) {
                Text("\(spendableBalance.currencyText) spendable")
                    .font(.helvetica(.headline, weight: .semibold))
                    .monospacedDigit()
                Button {
                    showingSpendableDetails = true
                } label: {
                    Image(systemName: "questionmark.circle")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.62))
                }
                .accessibilityLabel("Explain spendable money")
            }
            .foregroundStyle(.white.opacity(0.7))

            HStack(spacing: 8) {
                Image(systemName: presentationWeather.symbol)
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(
                        presentationWeather.primaryColor,
                        presentationWeather.secondaryColor
                    )
                Text(presentationConditionTitle)
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
                                    .fill(forecastMonth.isCurrent ? Color.sunGold : .clear)
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
            goals: currentGoals,
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
            },
            onAllocate: { goal in
                goalBeingAllocated = goal
            },
            onComplete: { goal in
                if let index = goals.firstIndex(where: { $0.id == goal.id }) {
                    goals[index].isCompleted = true
                }
            },
            onExpand: { showingGoals = true }
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
        .padding(.top, 8)
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
                    .padding(.horizontal, 12)
                    .padding(.top, 12)
                    .padding(.bottom, 20)
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
        case .custom(let entryID, let occurrenceKey, let occurrenceDate):
            if scope == .onlyThis {
                occurrenceNameOverrides[occurrenceKey] = name
            } else if let index = addedEntries.firstIndex(where: { $0.id == entryID }) {
                let entry = addedEntries[index]
                for date in entry.occurrenceDates(through: MockForecast.horizon) where date >= occurrenceDate {
                    occurrenceNameOverrides[entry.occurrenceKey(for: date)] = name
                }
            }
        case .forecastDay:
            break
        }
        selectedDay = nil
    }

    private func deleteEntry(_ target: ForecastEntryTarget, scope: OccurrenceScope) {
        switch target {
        case .custom(let entryID, let occurrenceKey, let occurrenceDate):
            if scope == .onlyThis {
                excludedOccurrences.insert(occurrenceKey)
            } else if let entry = addedEntries.first(where: { $0.id == entryID }) {
                for date in entry.occurrenceDates(through: MockForecast.horizon) where date >= occurrenceDate {
                    excludedOccurrences.insert(entry.occurrenceKey(for: date))
                }
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

            MiniMetric(
                icon: "calendar.badge.clock",
                value: "\(scheduledChanges)",
                label: "scheduled changes"
            )
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
    let onAllocate: (FinancialGoal) -> Void
    let onComplete: (FinancialGoal) -> Void
    let onExpand: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Text("GOALS")
                    .font(.helvetica(.caption, weight: .bold))
                    .tracking(1.2)
                    .foregroundStyle(.white.opacity(0.62))

                Spacer()

                HStack(spacing: 8) {
                    Button(action: onExpand) {
                        Label("View all", systemImage: "rectangle.stack")
                            .font(.helvetica(.caption, weight: .semibold))
                            .padding(.horizontal, 11)
                            .padding(.vertical, 8)
                            .background(.white.opacity(0.09), in: Capsule())
                    }
                    Button(action: onAdd) {
                        Label("Add", systemImage: "plus")
                            .font(.helvetica(.caption, weight: .semibold))
                            .padding(.horizontal, 11)
                            .padding(.vertical, 8)
                            .background(.white.opacity(0.11), in: Capsule())
                    }
                }
                .buttonStyle(.plain)
            }

            Text("What you’re working toward")
                .font(.helvetica(.title3, weight: .semibold))

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
                                onDelete: { onDelete(goal) },
                                onAllocate: { onAllocate(goal) },
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

private struct GoalProgressTile: View {
    let goal: FinancialGoal
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onAllocate: () -> Void
    let onComplete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: goal.symbol)
                    .foregroundStyle(.white.opacity(0.9))
                PriorityBadge(priority: goal.priority)
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
                .tint(goal.priority.color)

            HStack(alignment: .firstTextBaseline) {
                Text(goal.saved.currencyText)
                    .font(.helvetica(.subheadline, weight: .bold))
                Text("of \(goal.targetAmount.currencyText)")
                    .font(.helvetica(.caption2))
                    .foregroundStyle(.white.opacity(0.5))
                Spacer()
                Text("\(Int(goal.progress * 100))%")
                    .font(.helvetica(.caption, weight: .bold))
                    .foregroundStyle(goal.priority.color)
            }

            HStack(spacing: 8) {
                Button(action: onAllocate) {
                    Label(goal.saved > 0 ? "Manage" : "Allocate", systemImage: goal.saved > 0 ? "slider.horizontal.3" : "plus.circle.fill")
                        .font(.helvetica(.caption, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.78))
                }

                Spacer(minLength: 4)

                Button(action: onComplete) {
                    Label("Complete", systemImage: "checkmark.circle.fill")
                        .font(.helvetica(.caption, weight: .semibold))
                        .foregroundStyle(Color.rainMist)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 6)
                        .background(.white.opacity(0.08), in: Capsule())
                }
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .frame(width: 230, alignment: .leading)
        .background(.white.opacity(0.075), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct PriorityBadge: View {
    let priority: GoalPriority

    var body: some View {
        Label(priority.title, systemImage: priority.symbol)
            .font(.helvetica(.caption2, weight: .bold))
            .foregroundStyle(priority.color)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(priority.color.opacity(0.12), in: Capsule())
    }
}

private struct ExpandedGoalsSheet: View {
    @Binding var goals: [FinancialGoal]
    let accountBalance: Double
    @State private var tab = GoalListTab.current
    @State private var editingGoal: FinancialGoal?
    @State private var allocatingGoal: FinancialGoal?
    @State private var showingGoalEditor = false
    @State private var pendingDeletion: FinancialGoal?

    private var visibleGoals: [FinancialGoal] {
        goals
            .filter { tab == .current ? !$0.isCompleted : $0.isCompleted }
            .sorted {
                if $0.priority.rank == $1.priority.rank { return $0.targetDate < $1.targetDate }
                return $0.priority.rank < $1.priority.rank
            }
    }

    private var reservedAmount: Double {
        goals.filter { !$0.isCompleted }.reduce(0) { $0 + $1.saved }
    }

    var body: some View {
        ZStack {
            LinearGradient(colors: MoneyWeather.partlySunny.backgroundColors, startPoint: .topLeading, endPoint: .bottomTrailing)
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 18) {
                    SheetTitle(eyebrow: "GOAL CENTER", title: "Your objectives", symbol: "target")

                    Picker("Goal list", selection: $tab) {
                        ForEach(GoalListTab.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)

                    if visibleGoals.isEmpty {
                        VStack(spacing: 10) {
                            Image(systemName: tab == .current ? "target" : "clock.arrow.circlepath")
                                .font(.system(size: 30, weight: .light))
                            Text(tab == .current ? "No current goals" : "No previous goals")
                                .font(.helvetica(.headline, weight: .semibold))
                            Text(tab == .current ? "Add a goal to start building your priority plan." : "Goals marked complete will stay here for your history.")
                                .font(.helvetica(.caption))
                                .foregroundStyle(.white.opacity(0.52))
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 42)
                        .background(.black.opacity(0.14), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    } else {
                        LazyVStack(spacing: 10) {
                            ForEach(visibleGoals) { goal in
                                ExpandedGoalRow(
                                    goal: goal,
                                    allocation: goal.saved,
                                    onEdit: {
                                        editingGoal = goal
                                        showingGoalEditor = true
                                    },
                                    onDelete: { pendingDeletion = goal },
                                    onAllocate: tab == .current ? { allocatingGoal = goal } : nil,
                                    onToggleCompletion: {
                                        if let index = goals.firstIndex(where: { $0.id == goal.id }) {
                                            goals[index].isCompleted.toggle()
                                        }
                                    }
                                )
                            }
                        }
                    }

                    if tab == .current {
                        PrimarySheetButton(title: "Add goal", enabled: true) {
                            editingGoal = nil
                            showingGoalEditor = true
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 28)
            }
            .scrollIndicators(.hidden)
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showingGoalEditor) {
            AddGoalSheet(existingGoal: editingGoal) { goal in
                if let index = goals.firstIndex(where: { $0.id == goal.id }) {
                    goals[index] = goal
                } else {
                    goals.append(goal)
                }
                editingGoal = nil
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .sheet(item: $allocatingGoal) { goal in
            AllocateMoneySheet(
                goal: goal,
                spendableBalance: max(0, accountBalance - reservedAmount)
            ) { amount in
                if let index = goals.firstIndex(where: { $0.id == goal.id }) {
                    goals[index].saved = min(goals[index].targetAmount, max(0, amount))
                }
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .confirmationDialog(
            "Delete goal?",
            isPresented: Binding(get: { pendingDeletion != nil }, set: { if !$0 { pendingDeletion = nil } }),
            titleVisibility: .visible,
            presenting: pendingDeletion
        ) { goal in
            Button("Delete \(goal.name)", role: .destructive) {
                goals.removeAll { $0.id == goal.id }
                pendingDeletion = nil
            }
            Button("Cancel", role: .cancel) { }
        }
    }
}

private struct ExpandedGoalRow: View {
    let goal: FinancialGoal
    let allocation: Double
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onAllocate: (() -> Void)?
    let onToggleCompletion: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: goal.symbol)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
                    .frame(width: 42, height: 42)
                    .background(goal.priority.color.opacity(0.16), in: Circle())
                VStack(alignment: .leading, spacing: 4) {
                    Text(goal.name).font(.helvetica(.headline, weight: .semibold))
                    PriorityBadge(priority: goal.priority)
                }
                Spacer()
                Menu {
                    Button(action: onEdit) { Label("Edit goal", systemImage: "pencil") }
                    Button(action: onToggleCompletion) {
                        Label(goal.isCompleted ? "Restore goal" : "Complete goal", systemImage: goal.isCompleted ? "arrow.uturn.backward.circle" : "checkmark.circle")
                    }
                    Button(role: .destructive, action: onDelete) { Label("Delete goal", systemImage: "trash") }
                } label: {
                    Image(systemName: "ellipsis")
                        .frame(width: 34, height: 34)
                        .background(.white.opacity(0.08), in: Circle())
                }
            }

            ProgressView(value: goal.progress).tint(goal.priority.color)

            HStack {
                Text("\(goal.saved.currencyText) of \(goal.targetAmount.currencyText)")
                Spacer()
                Text("\(Int(goal.progress * 100))%")
                    .foregroundStyle(goal.priority.color)
            }
            .font(.helvetica(.caption, weight: .semibold))

            HStack {
                Label(goal.targetDate.formatted(date: .abbreviated, time: .omitted), systemImage: "calendar")
                Spacer()
                if goal.isCompleted {
                    Label("Completed", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(Color.rainMist)
                } else if allocation > 0 {
                    Text("\(allocation.currencyText) reserved")
                }
            }
            .font(.helvetica(.caption2, weight: .medium))
            .foregroundStyle(.white.opacity(0.54))

            if let onAllocate {
                Button(action: onAllocate) {
                    Label(goal.saved > 0 ? "Manage allocation" : "Allocate money", systemImage: goal.saved > 0 ? "slider.horizontal.3" : "plus.circle.fill")
                        .font(.helvetica(.caption, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(.white.opacity(0.09), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
            }

            Button(action: onToggleCompletion) {
                Label(
                    goal.isCompleted ? "Bring back to current goals" : "Mark goal completed",
                    systemImage: goal.isCompleted ? "arrow.uturn.backward.circle" : "checkmark.circle.fill"
                )
                .font(.helvetica(.caption, weight: .semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .foregroundStyle(goal.isCompleted ? Color.rainMist : .white.opacity(0.78))
                .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .background(.black.opacity(0.16), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(.white.opacity(0.12), lineWidth: 0.75)
        }
    }
}

private struct AddGoalSheet: View {
    @Environment(\.dismiss) private var dismiss
    let existingGoal: FinancialGoal?
    let onSave: (FinancialGoal) -> Void

    @State private var name = ""
    @State private var amountText = ""
    @State private var targetDate = Calendar.current.date(byAdding: .month, value: 4, to: MockForecast.todayDate) ?? MockForecast.todayDate
    @State private var symbol = "airplane"
    @State private var priority = GoalPriority.important
    @State private var isCompleted = false

    init(existingGoal: FinancialGoal? = nil, onSave: @escaping (FinancialGoal) -> Void) {
        self.existingGoal = existingGoal
        self.onSave = onSave
        _name = State(initialValue: existingGoal?.name ?? "")
        _amountText = State(initialValue: existingGoal.map { $0.targetAmount.editingText } ?? "")
        _targetDate = State(initialValue: existingGoal?.targetDate ?? Calendar.current.date(byAdding: .month, value: 4, to: MockForecast.todayDate) ?? MockForecast.todayDate)
        _symbol = State(initialValue: existingGoal?.symbol ?? "airplane")
        _priority = State(initialValue: existingGoal?.priority ?? .important)
        _isCompleted = State(initialValue: existingGoal?.isCompleted ?? false)
    }

    private var targetAmount: Double { amountText.moneyValue ?? 0 }
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

                    EntryCard(title: "TARGET DATE") {
                        DatePicker("Goal date", selection: $targetDate, displayedComponents: .date)
                            .tint(.white)
                    }

                    EntryCard(title: "PRIORITY") {
                        Picker("Goal priority", selection: $priority) {
                            ForEach(GoalPriority.allCases) { option in
                                Label(option.title, systemImage: option.symbol).tag(option)
                            }
                        }
                        .pickerStyle(.segmented)

                        Label(priority.explanation, systemImage: priority.symbol)
                            .font(.helvetica(.caption))
                            .foregroundStyle(.white.opacity(0.58))
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
                            saved: min(existingGoal?.saved ?? 0, targetAmount),
                            targetDate: targetDate,
                            symbol: symbol,
                            priority: priority,
                            isCompleted: isCompleted
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

private struct AllocateMoneySheet: View {
    @Environment(\.dismiss) private var dismiss
    let goal: FinancialGoal
    let spendableBalance: Double
    let onAllocate: (Double) -> Void
    @State private var amountText: String

    init(goal: FinancialGoal, spendableBalance: Double, onAllocate: @escaping (Double) -> Void) {
        self.goal = goal
        self.spendableBalance = spendableBalance
        self.onAllocate = onAllocate
        _amountText = State(initialValue: goal.saved.editingText)
    }

    private var amount: Double { amountText.moneyValue ?? 0 }
    private var maximumAllocation: Double { min(goal.targetAmount, goal.saved + spendableBalance).roundedToCents }
    private var canAllocate: Bool {
        amountText.moneyValue != nil && amount >= 0 && amount <= maximumAllocation && amount != goal.saved
    }
    private var spendableAfterSaving: Double { spendableBalance + goal.saved - amount }

    var body: some View {
        ZStack {
            LinearGradient(colors: MoneyWeather.partlySunny.backgroundColors, startPoint: .topLeading, endPoint: .bottomTrailing)
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 18) {
                    SheetTitle(eyebrow: "MANAGE ALLOCATION", title: goal.name, symbol: goal.symbol)

                    HStack(spacing: 8) {
                        PriorityBadge(priority: goal.priority)
                        Spacer()
                        Text("\(goal.saved.currencyText) of \(goal.targetAmount.currencyText)")
                            .font(.helvetica(.caption, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.68))
                    }

                    EntryCard(title: "TOTAL AMOUNT TO RESERVE") {
                        CurrencyField(text: $amountText, placeholder: "0.00")
                        Button("Use maximum available") {
                            amountText = maximumAllocation.editingText
                        }
                        .font(.helvetica(.caption, weight: .semibold))
                        .foregroundStyle(Color.rainMist)
                        .disabled(maximumAllocation <= 0)
                    }

                    VStack(spacing: 0) {
                        ScenarioMetric(title: "Spendable now", value: spendableBalance.currencyText)
                        Divider().overlay(.white.opacity(0.12))
                        ScenarioMetric(title: "Currently allocated", value: goal.saved.currencyText)
                        Divider().overlay(.white.opacity(0.12))
                        ScenarioMetric(title: "Spendable after saving", value: spendableAfterSaving.currencyText)
                    }
                    .padding(.horizontal, 16)
                    .background(.black.opacity(0.16), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                    if amount > maximumAllocation {
                        Label("This is more than your available spendable money or the goal target.", systemImage: "exclamationmark.triangle.fill")
                            .font(.helvetica(.caption))
                            .foregroundStyle(Color.sunGold)
                    }

                }
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
            }
            .scrollIndicators(.hidden)
        }
        .preferredColorScheme(.dark)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            PrimarySheetButton(title: "Save allocation", enabled: canAllocate) {
                onAllocate(amount.roundedToCents)
                dismiss()
            }
            .padding(.horizontal, 20)
            .padding(.top, 10)
            .padding(.bottom, 8)
            .background(.ultraThinMaterial)
        }
    }
}

private struct SpendableBreakdownSheet: View {
    let totalBalance: Double
    let goals: [FinancialGoal]
    let payments: [ForecastActivity]

    private var fundedGoals: [FinancialGoal] {
        goals.filter { $0.saved > 0 }
    }

    private var reservedAmount: Double {
        fundedGoals.reduce(0) { $0 + $1.saved }
    }

    private var reservedPayments: Double {
        payments.reduce(0) { $0 + $1.amount }
    }

    private var spendableBalance: Double {
        totalBalance - reservedAmount - reservedPayments
    }

    var body: some View {
        ZStack {
            LinearGradient(colors: MoneyWeather.partlySunny.backgroundColors, startPoint: .topLeading, endPoint: .bottomTrailing)
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 18) {
                    SheetTitle(eyebrow: "SPENDABLE MONEY", title: "Where your balance goes", symbol: "questionmark.circle")

                    VStack(spacing: 0) {
                        ScenarioMetric(title: "Total account balance", value: totalBalance.currencyText)
                        Divider().overlay(.white.opacity(0.12))
                        ScenarioMetric(title: "Goal allocations", value: reservedAmount.negativeCurrencyText)
                        Divider().overlay(.white.opacity(0.12))
                        ScenarioMetric(title: "Upcoming payments", value: reservedPayments.negativeCurrencyText)
                        Divider().overlay(.white.opacity(0.12))
                        ScenarioMetric(title: "Spendable money", value: spendableBalance.currencyText)
                    }
                    .padding(.horizontal, 16)
                    .background(.black.opacity(0.16), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                    if fundedGoals.isEmpty && payments.isEmpty {
                        Label("Nothing is currently reducing your spendable money.", systemImage: "checkmark.circle")
                            .font(.helvetica(.subheadline))
                            .foregroundStyle(.white.opacity(0.58))
                            .frame(maxWidth: .infinity)
                            .padding(18)
                    } else {
                        VStack(spacing: 16) {
                            if !fundedGoals.isEmpty {
                                VStack(alignment: .leading, spacing: 10) {
                                    Text("GOAL ALLOCATIONS")
                                        .font(.helvetica(.caption, weight: .bold))
                                        .tracking(1.1)
                                        .foregroundStyle(.white.opacity(0.6))

                                    ForEach(fundedGoals) { goal in
                                        HStack(spacing: 11) {
                                            Image(systemName: goal.symbol)
                                                .font(.system(size: 14, weight: .semibold))
                                                .foregroundStyle(.white.opacity(0.9))
                                                .frame(width: 34, height: 34)
                                                .background(goal.priority.color.opacity(0.16), in: Circle())
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(goal.name)
                                                    .font(.helvetica(.subheadline, weight: .semibold))
                                                Text(goal.priority.title)
                                                    .font(.helvetica(.caption2))
                                                    .foregroundStyle(.white.opacity(0.5))
                                            }
                                            Spacer()
                                            Text(goal.saved.negativeCurrencyText)
                                                .font(.helvetica(.subheadline, weight: .bold))
                                                .monospacedDigit()
                                        }
                                        .padding(12)
                                        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                    }
                                }
                            }

                            if !payments.isEmpty {
                                VStack(alignment: .leading, spacing: 10) {
                                    Text("UPCOMING PAYMENTS")
                                        .font(.helvetica(.caption, weight: .bold))
                                        .tracking(1.1)
                                        .foregroundStyle(.white.opacity(0.6))

                                    ForEach(payments) { payment in
                                        HStack(spacing: 11) {
                                            Image(systemName: payment.isRecurring ? "arrow.triangle.2.circlepath" : "calendar.badge.clock")
                                                .font(.system(size: 13, weight: .semibold))
                                                .frame(width: 34, height: 34)
                                                .background(.white.opacity(0.09), in: Circle())
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(payment.name)
                                                    .font(.helvetica(.subheadline, weight: .semibold))
                                                Text(payment.date, format: .dateTime.month(.abbreviated).day())
                                                    .font(.helvetica(.caption2))
                                                    .foregroundStyle(.white.opacity(0.5))
                                            }
                                            Spacer()
                                            Text(payment.amount.negativeCurrencyText)
                                                .font(.helvetica(.subheadline, weight: .bold))
                                                .monospacedDigit()
                                        }
                                        .padding(12)
                                        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                    }
                                }
                            }
                        }
                    }

                    Text("Spendable money protects goal allocations and upcoming forecast payments while leaving your total bank balance unchanged.")
                        .font(.helvetica(.caption))
                        .foregroundStyle(.white.opacity(0.54))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 14)
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
    let accountBalance: Double
    let spendableBalance: Double
    let goals: [FinancialGoal]

    @State private var amountText = ""
    @State private var schedule = EntrySchedule.oneTime
    @State private var repeatEvery = 1
    @State private var repeatUnit = RepeatUnit.month

    private var amount: Double { amountText.moneyValue ?? 0 }
    private var threeMonthCost: Double {
        guard schedule == .recurring else { return amount }
        let occurrences: Double
        switch repeatUnit {
        case .day: occurrences = 90 / Double(repeatEvery)
        case .week: occurrences = 13 / Double(repeatEvery)
        case .month: occurrences = 3 / Double(repeatEvery)
        case .year: occurrences = 1
        }
        return amount * Double(max(1, Int(occurrences.rounded(.up))))
    }
    private var projectedBalance: Double { accountBalance - threeMonthCost }
    private var currentAllocations: [UUID: Double] {
        GoalAllocation.plan(for: goals, availableBalance: spendableBalance)
    }
    private var projectedAllocations: [UUID: Double] {
        GoalAllocation.plan(for: goals, availableBalance: spendableBalance - threeMonthCost)
    }
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
                            ScenarioMetric(title: "Balance now", value: accountBalance.currencyText)
                            Divider().overlay(.white.opacity(0.12))
                            ScenarioMetric(title: schedule == .recurring ? "Balance after 90 days" : "Balance after purchase", value: projectedBalance.currencyText)
                            if schedule == .recurring {
                                Divider().overlay(.white.opacity(0.12))
                                ScenarioMetric(title: "Estimated 90-day cost", value: threeMonthCost.negativeCurrencyText)
                            }
                        }
                        .padding(.horizontal, 16)
                        .background(.black.opacity(0.16), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                        VStack(alignment: .leading, spacing: 14) {
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("GOAL IMPACT")
                                        .font(.helvetica(.caption, weight: .bold))
                                        .tracking(1.1)
                                        .foregroundStyle(.white.opacity(0.68))
                                    Text("How your priorities would move")
                                        .font(.helvetica(.headline, weight: .semibold))
                                }
                                Spacer()
                                Image(systemName: "target")
                                    .font(.system(size: 24, weight: .semibold))
                                    .foregroundStyle(Color.sunGold)
                            }
                            ForEach(goals) { goal in
                                WhatIfGoalRow(
                                    goal: goal,
                                    currentAllocation: currentAllocations[goal.id] ?? 0,
                                    projectedAllocation: projectedAllocations[goal.id] ?? 0
                                )
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
    let currentAllocation: Double
    let projectedAllocation: Double

    private var allocationLoss: Double { max(0, currentAllocation - projectedAllocation) }
    private var daysUntilGoal: Double {
        max(1, Calendar.current.dateComponents([.day], from: MockForecast.todayDate, to: goal.targetDate).day.map(Double.init) ?? 1)
    }
    private var dailyFundingRate: Double { max(18, currentAllocation / daysUntilGoal) }
    private var delayDays: Int { allocationLoss == 0 ? 0 : Int(ceil(allocationLoss / dailyFundingRate)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 12) {
                Image(systemName: goal.symbol)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
                    .frame(width: 38, height: 38)
                    .background(goal.priority.color.opacity(0.18), in: Circle())
                VStack(alignment: .leading, spacing: 3) {
                    Text(goal.name).font(.helvetica(.headline, weight: .semibold))
                    PriorityBadge(priority: goal.priority)
                }
                Spacer()
                Text(allocationLoss.negativeCurrencyText)
                    .font(.helvetica(.headline, weight: .bold))
                    .foregroundStyle(allocationLoss > 0 ? Color.sunGold : .white.opacity(0.5))
            }

            HStack {
                Label(
                    delayDays == 0 ? "No expected delay" : "About \(delayDays) day\(delayDays == 1 ? "" : "s") later",
                    systemImage: delayDays == 0 ? "checkmark.circle.fill" : "calendar.badge.clock"
                )
                .font(.helvetica(.subheadline, weight: .bold))
                .foregroundStyle(delayDays == 0 ? Color.rainMist : Color.sunGold)
                Spacer()
                Text("\(projectedAllocation.currencyText) still allocated")
                    .font(.helvetica(.caption2))
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
        .padding(14)
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
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
    let goals: [FinancialGoal]
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

    private var monthlyNet: Double {
        month.days.reduce(0) { $0 + $1.amount }
    }

    private func goals(on day: ForecastDay) -> [FinancialGoal] {
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.year = month.month.year
        components.month = month.month.monthNumber
        components.day = day.day
        guard let date = components.date else { return [] }

        return goals
            .filter { Calendar.current.isDate($0.targetDate, inSameDayAs: date) }
            .sorted {
                if $0.priority.rank == $1.priority.rank { return $0.name < $1.name }
                return $0.priority.rank < $1.priority.rank
            }
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
                                CalendarDayCell(day: day, goals: goals(on: day))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 12)
                    .padding(.bottom, 18)
                    .background(.black.opacity(0.18), in: RoundedRectangle(cornerRadius: 18, style: .continuous))

                    HStack(spacing: 7) {
                        Image(systemName: monthlyNet >= 0 ? "arrow.up.right" : "arrow.down.right")
                        Text("Monthly net")
                        Text(monthlyNet.signedCalendarCurrencyText)
                            .fontWeight(.bold)
                            .monospacedDigit()
                    }
                    .font(.helvetica(.caption))
                    .foregroundStyle(.white.opacity(0.62))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.white.opacity(0.07), in: Capsule())

                    Text("Tap any day to view each entry separately.")
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
    let goals: [FinancialGoal]

    private var visibleGoals: [FinancialGoal] {
        Array(goals.prefix(goals.count > 2 ? 2 : goals.count))
    }

    private var goalIconSize: CGFloat {
        goals.count <= 1 ? 13 : 9
    }

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 2) {
                Text("\(day.day)")
                    .font(.helvetica(.caption, weight: day.status == .today ? .bold : .medium))
                Spacer(minLength: 1)
                ForEach(visibleGoals) { goal in
                    Image(systemName: goal.symbol)
                        .font(.system(size: goalIconSize, weight: .semibold))
                        .foregroundStyle(Color.rainMist)
                }
                if goals.count > visibleGoals.count {
                    Text("+\(goals.count - visibleGoals.count)")
                        .font(.helvetica(size: 7, weight: .bold))
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
            .frame(maxWidth: .infinity, minHeight: 14)

            if day.amount != 0 {
                Image(systemName: day.weather.symbol)
                    .font(.system(size: 15))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(day.weather.primaryColor, day.weather.secondaryColor)
                Text(day.amount.signedCalendarCurrencyText)
                    .font(.helvetica(.caption2, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.35)
                    .allowsTightening(true)
                    .frame(maxWidth: .infinity)
            } else {
                Spacer().frame(height: 26)
                Text("—").font(.helvetica(.caption2)).foregroundStyle(.white.opacity(0.28))
            }
        }
        .padding(.horizontal, 3)
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, minHeight: 72)
        .background(day.status == .today ? Color.sunGold.opacity(0.18) : .white.opacity(day.amount == 0 ? 0.035 : 0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            if day.status == .today {
                RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Color.sunGold.opacity(0.65))
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityHint(goals.isEmpty ? "" : "Goal deadline")
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
            TextField(placeholder, text: $text).keyboardType(.decimalPad)
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

    @State private var editedName = ""
    @State private var selectedActivity: ForecastActivity?
    @State private var editingActivityID: String?
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
                            amount: day.income > 0 ? day.income.signedCurrencyText : 0.0.currencyText
                        )
                        Divider().overlay(.white.opacity(0.12))
                        DetailRow(
                            icon: "arrow.up.right",
                            title: day.expenses > 0 ? "Spending & payments" : "No scheduled spending",
                            subtitle: day.expenseSource,
                            amount: day.expenses > 0 ? day.expenses.negativeCurrencyText : 0.0.currencyText
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

                    if !day.activities.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(day.activities.count == 1 ? "ENTRY" : "ENTRIES")
                                .font(.helvetica(.caption, weight: .bold))
                                .tracking(1.1)
                                .foregroundStyle(.white.opacity(0.62))

                            ForEach(day.activities) { activity in
                                VStack(alignment: .leading, spacing: 12) {
                                    HStack(spacing: 11) {
                                        Image(systemName: activity.kind.symbol)
                                            .font(.system(size: 13, weight: .bold))
                                            .frame(width: 32, height: 32)
                                            .background(.white.opacity(0.1), in: Circle())
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(activity.name)
                                                .font(.helvetica(.subheadline, weight: .semibold))
                                            if activity.isRecurring {
                                                Label("Recurring", systemImage: "arrow.triangle.2.circlepath")
                                                    .font(.helvetica(.caption2, weight: .medium))
                                                    .foregroundStyle(.white.opacity(0.52))
                                            }
                                        }
                                        Spacer()
                                        Text(activity.signedAmount.signedCurrencyText)
                                            .font(.helvetica(.subheadline, weight: .bold))
                                            .monospacedDigit()
                                    }

                                    if editingActivityID == activity.id {
                                        TextField("Entry name", text: $editedName)
                                            .padding(11)
                                            .background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                                    }

                                    HStack(spacing: 10) {
                                        Button(editingActivityID == activity.id ? "Save name" : "Edit") {
                                            if editingActivityID == activity.id {
                                                selectedActivity = activity
                                                if activity.isRecurring {
                                                    showingRenameScope = true
                                                } else {
                                                    onRename(activity.target, editedName, .onlyThis)
                                                    dismiss()
                                                }
                                            } else {
                                                selectedActivity = activity
                                                editedName = activity.name
                                                editingActivityID = activity.id
                                            }
                                        }
                                        .buttonStyle(.bordered)
                                        .tint(.white)

                                        Button(role: .destructive) {
                                            selectedActivity = activity
                                            if activity.isRecurring {
                                                showingDeleteScope = true
                                            } else {
                                                onDelete(activity.target, .onlyThis)
                                                dismiss()
                                            }
                                        } label: {
                                            Label("Delete", systemImage: "trash")
                                        }
                                        .buttonStyle(.bordered)
                                        .tint(Color.stormLavender)
                                    }
                                }
                                .padding(14)
                                .background(.black.opacity(0.16), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .stroke(.white.opacity(0.11), lineWidth: 0.75)
                                }
                            }
                        }
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
            if let activity = selectedActivity {
                Button("Only this entry") {
                    onRename(activity.target, editedName, .onlyThis)
                    dismiss()
                }
                Button("All future occurrences") {
                    onRename(activity.target, editedName, .allFuture)
                    dismiss()
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Choose whether this change applies once or to the recurring series.")
        }
        .confirmationDialog("Delete recurring entry", isPresented: $showingDeleteScope, titleVisibility: .visible) {
            if let activity = selectedActivity {
                Button("Only this entry", role: .destructive) {
                    onDelete(activity.target, .onlyThis)
                    dismiss()
                }
                Button("All future occurrences", role: .destructive) {
                    onDelete(activity.target, .allFuture)
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
        amountText.moneyValue
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
                            amount: amount.roundedToCents,
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

private enum EntryKind: String, CaseIterable, Identifiable {
    case payment
    case income

    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var symbol: String { self == .payment ? "arrow.up.right" : "arrow.down.left" }
}

private enum EntrySchedule: String, CaseIterable, Identifiable {
    case oneTime
    case recurring

    var id: String { rawValue }
    var title: String { self == .oneTime ? "One-time" : "Recurring" }
}

private enum RepeatUnit: String, CaseIterable, Identifiable {
    case day
    case week
    case month
    case year

    var id: String { rawValue }
    var singular: String { rawValue.capitalized }
    var plural: String { "\(rawValue.capitalized)s" }
}

private enum RepeatEnding: String, CaseIterable, Identifiable {
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

private enum GoalPriority: String, CaseIterable, Identifiable {
    case essential
    case important
    case flexible

    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var rank: Int {
        switch self {
        case .essential: return 0
        case .important: return 1
        case .flexible: return 2
        }
    }
    var symbol: String {
        switch self {
        case .essential: return "exclamationmark.shield.fill"
        case .important: return "star.fill"
        case .flexible: return "wind"
        }
    }
    var color: Color {
        switch self {
        case .essential: return Color.sunGold
        case .important: return Color.rainMist
        case .flexible: return Color.cloudSilver
        }
    }
    var explanation: String {
        switch self {
        case .essential: return "Funded first before other goals."
        case .important: return "Funded after essential goals."
        case .flexible: return "Funded after essential and important goals."
        }
    }
}

private enum GoalListTab: String, CaseIterable, Identifiable {
    case current
    case previous

    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

private struct FinancialGoal: Identifiable {
    let id: UUID
    var name: String
    let targetAmount: Double
    var saved: Double
    let targetDate: Date
    let symbol: String
    let priority: GoalPriority
    var isCompleted: Bool

    var progress: Double {
        guard targetAmount > 0 else { return 0 }
        return min(1, Double(saved) / Double(targetAmount))
    }

    var remaining: Double { max(0, targetAmount - saved) }

}

private enum GoalAllocation {
    static func plan(for goals: [FinancialGoal], availableBalance: Double) -> [UUID: Double] {
        var available = max(0, availableBalance)
        var result: [UUID: Double] = [:]
        let orderedGoals = goals
            .filter { !$0.isCompleted }
            .sorted {
                if $0.priority.rank == $1.priority.rank { return $0.targetDate < $1.targetDate }
                return $0.priority.rank < $1.priority.rank
            }

        for goal in orderedGoals {
            let allocation = min(goal.remaining, available)
            result[goal.id] = allocation.roundedToCents
            available = max(0, available - allocation)
        }
        return result
    }
}

private struct FinancialEntry: Identifiable {
    let id: UUID
    var name: String
    let kind: EntryKind
    let amount: Double
    let startDate: Date
    let schedule: EntrySchedule
    let repeatEvery: Int
    let repeatUnit: RepeatUnit
    let repeatEnding: RepeatEnding
    let occurrenceCount: Int
    let endDate: Date

    var signedAmount: Double {
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
    case custom(entryID: UUID, occurrenceKey: String, occurrenceDate: Date)
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

    var isPast: Bool { rawValue < ForecastMonth.september.rawValue }
    var isCurrent: Bool { self == .september }
    var isFuture: Bool { rawValue > ForecastMonth.september.rawValue }

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

    private var comfortIndex: Int {
        switch self {
        case .storm: return 0
        case .rain: return 1
        case .cloudy: return 2
        case .partlySunny: return 3
        case .sunny: return 4
        }
    }

    static func blended(monthly: MoneyWeather, daily: MoneyWeather) -> MoneyWeather {
        let blendedIndex = Int((Double(monthly.comfortIndex + daily.comfortIndex) / 2).rounded())
        switch blendedIndex {
        case 4: return .sunny
        case 3: return .partlySunny
        case 2: return .cloudy
        case 1: return .rain
        default: return .storm
        }
    }

    var conditionTitle: String {
        switch self {
        case .sunny: return "Clear"
        case .partlySunny: return "Mostly Clear"
        case .cloudy: return "A Little Cloudy"
        case .rain: return "Rain Possible"
        case .storm: return "High Pressure"
        }
    }

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
    let amount: Double
    let weather: MoneyWeather
    let status: DayStatus
    let income: Double
    let expenses: Double
    let incomeSource: String
    let expenseSource: String
    let entryTitle: String?
    let entryTarget: ForecastEntryTarget?
    let activities: [ForecastActivity]
    let isRecurring: Bool
    let isBankImported: Bool

    var formattedAmount: String {
        amount.signedCurrencyText
    }

    var activityTitle: String {
        entryTitle ?? (amount == 0 ? "No activity" : weather.dailyTitle)
    }
}

private struct ForecastActivity: Identifiable {
    let id: String
    let name: String
    let date: Date
    let kind: EntryKind
    let amount: Double
    let isRecurring: Bool
    let target: ForecastEntryTarget

    var signedAmount: Double { kind == .income ? amount : -amount }
}

private struct MonthForecast {
    let month: ForecastMonth
    let accountBalance: Double
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
    static let todayDate = makeDate(year: 2026, month: 9, day: 11)
    static let horizon = makeDate(year: 2027, month: 9, day: 30)
    static let balancePoints: [BalancePoint] = []

    static func balancePoints(
        including entries: [FinancialEntry],
        excludingForecastDays: Set<String> = [],
        excludingOccurrences: Set<String> = []
    ) -> [BalancePoint] {
        let occurrences = entryOccurrences(
            for: entries,
            through: Self.horizon,
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
        occurrenceNameOverrides: [String: String] = [:]
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
        let outlookAdjustment = occurrences
            .filter { $0.date <= monthEnd }
            .reduce(0) { $0 + $1.entry.signedAmount }
            + deletedAdjustments
                .filter { $0.date <= monthEnd }
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
        let adjustedBalance = balanceAdjustment
        let adjustedWeather = entries.isEmpty ? MoneyWeather.cloudy : comfortWeather(for: outlookAdjustment)

        return MonthForecast(
            month: month,
            accountBalance: adjustedBalance,
            balanceLabel: balanceLabel,
            overallWeather: adjustedWeather,
            conditionTitle: entries.isEmpty ? "No Data Yet" : conditionTitle(for: adjustedWeather),
            summary: "Connect a bank account or add an entry to begin your financial forecast.",
            averageDailySpending: max(
                0,
                Double(addedSpending - removedSpending) / Double(month.dayCount)
            ),
            previousMonthDelta: 0,
            allTimeDelta: 0,
            days: makeDays(
                for: month,
                occurrences: monthOccurrences,
                excludingForecastDays: excludingForecastDays
            )
        )
    }

    private static func makeDays(
        for month: ForecastMonth,
        occurrences: [EntryOccurrence] = [],
        excludingForecastDays: Set<String> = []
    ) -> [ForecastDay] {
        (1...month.dayCount).map { day in
            let matchingEntries = occurrences.filter {
                Calendar.current.component(.day, from: $0.date) == day
            }
            let customAmount = matchingEntries.reduce(0) { $0 + $1.entry.signedAmount }
            let dayID = "\(month.rawValue)-\(day)"
            let originalBaseAmount = mockAmount(month: month, day: day)
            let baseAmount = excludingForecastDays.contains(dayID) ? 0 : originalBaseAmount
            let amount = baseAmount + customAmount
            let weather = weather(for: amount)
            let status = status(for: month, day: day)
            let routineSpending = Double(18 + ((day * 7) % 38))
            let baseIncome = baseAmount > 0 ? baseAmount + routineSpending : 0
            let baseExpenses = baseAmount > 0 ? routineSpending : abs(baseAmount)
            let income = baseIncome + matchingEntries
                .filter { $0.entry.kind == .income }
                .reduce(0) { $0 + $1.entry.amount }
            let expenses = baseExpenses + matchingEntries
                .filter { $0.entry.kind == .payment }
                .reduce(0) { $0 + $1.entry.amount }
            let entryTitle: String?
            if matchingEntries.count == 1 && baseAmount == 0 {
                entryTitle = matchingEntries[0].displayName
            } else if !matchingEntries.isEmpty {
                entryTitle = "\(matchingEntries.count + (baseAmount == 0 ? 0 : 1)) entries"
            } else {
                entryTitle = nil
            }
            let customNames = matchingEntries.map(\.displayName).joined(separator: ", ")
            let entryTarget: ForecastEntryTarget?
            if matchingEntries.count == 1 {
                entryTarget = .custom(
                    entryID: matchingEntries[0].entry.id,
                    occurrenceKey: matchingEntries[0].key,
                    occurrenceDate: matchingEntries[0].date
                )
            } else if status == .forecast && baseAmount != 0 {
                entryTarget = .forecastDay(dayID: dayID)
            } else {
                entryTarget = nil
            }
            let isRecurring = matchingEntries.contains { $0.entry.schedule == .recurring } || baseAmount == -620
            let activities = matchingEntries.map { occurrence in
                ForecastActivity(
                    id: occurrence.key,
                    name: occurrence.displayName,
                    date: occurrence.date,
                    kind: occurrence.entry.kind,
                    amount: occurrence.entry.amount,
                    isRecurring: occurrence.entry.schedule == .recurring,
                    target: .custom(
                        entryID: occurrence.entry.id,
                        occurrenceKey: occurrence.key,
                        occurrenceDate: occurrence.date
                    )
                )
            }

            return ForecastDay(
                id: dayID,
                month: month,
                day: day,
                weekday: weekday(month: month, day: day),
                amount: amount,
                weather: weather,
                status: status,
                income: income,
                expenses: expenses,
                incomeSource: matchingEntries.contains(where: { $0.entry.kind == .income }) ? customNames : (income == 0 ? "Nothing scheduled" : (income >= 300 ? "Campus job deposit" : "Transfer or side income")),
                expenseSource: matchingEntries.contains(where: { $0.entry.kind == .payment }) ? customNames : (expenses == 0 ? "Nothing scheduled" : (expenses >= 300 ? "Rent and scheduled bills" : "Dining, transit, and daily spending")),
                entryTitle: entryTitle,
                entryTarget: entryTarget,
                activities: activities,
                isRecurring: isRecurring,
                isBankImported: status != .forecast && matchingEntries.isEmpty
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
    ) -> [(date: Date, amount: Double)] {
        ForecastMonth.allCases.flatMap { month in
            (1...month.dayCount).compactMap { day in
                let dayID = "\(month.rawValue)-\(day)"
                let amount = mockAmount(month: month, day: day)
                guard deletedDayIDs.contains(dayID), amount != 0 else { return nil }
                return (makeDate(year: month.year, month: month.monthNumber, day: day), -amount)
            }
        }
    }

    private static func comfortWeather(for balance: Double) -> MoneyWeather {
        if balance >= 2000 { return .sunny }
        if balance >= 1400 { return .partlySunny }
        if balance >= 900 { return .cloudy }
        if balance >= 300 { return .rain }
        return .storm
    }

    private static func conditionTitle(for weather: MoneyWeather) -> String {
        weather.conditionTitle
    }

    private static func mockAmount(month: ForecastMonth, day: Int) -> Double {
        0
    }

    private static func weather(for amount: Double) -> MoneyWeather {
        if amount >= 150 { return .sunny }
        if amount > 10 { return .partlySunny }
        if amount >= -25 { return .cloudy }
        if amount > -200 { return .rain }
        return .storm
    }

    private static func status(for month: ForecastMonth, day: Int) -> DayStatus {
        if month.isPast { return .recorded }
        if month.isCurrent {
            if day < 11 { return .recorded }
            if day == 11 { return .today }
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

private extension String {
    var moneyValue: Double? {
        let normalized = replacingOccurrences(of: ",", with: ".")
            .filter { $0.isNumber || $0 == "." }
        guard normalized.filter({ $0 == "." }).count <= 1 else { return nil }
        return Double(normalized)?.roundedToCents
    }
}

private extension Double {
    var roundedToCents: Double { (self * 100).rounded() / 100 }

    var currencyText: String {
        formatted(.currency(code: "USD").precision(.fractionLength(2)))
    }

    var signedCurrencyText: String {
        if self > 0 { return "+\(currencyText)" }
        if self < 0 { return "−\(abs(self).currencyText)" }
        return 0.0.currencyText
    }

    var signedCalendarCurrencyText: String {
        let wholeDollarText = abs(self).formatted(
            .currency(code: "USD").precision(.fractionLength(0))
        )
        if self > 0 { return "+\(wholeDollarText)" }
        if self < 0 { return "−\(wholeDollarText)" }
        return 0.0.formatted(.currency(code: "USD").precision(.fractionLength(0)))
    }

    var negativeCurrencyText: String {
        self == 0 ? 0.0.currencyText : "−\(abs(self).currencyText)"
    }

    var editingText: String {
        formatted(.number.grouping(.never).precision(.fractionLength(0...2)))
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
