import SwiftUI
import Charts
import FinanceCore
import FinancialCore

struct ContentView: View {
    @EnvironmentObject private var bankStore: BankAccountStore
    @State private var selectedMonth = ForecastMonth.september
    @State private var selectedDay: ForecastDay?
    @State private var showingAffordability = false
    @State private var showingFullMonth = false
    @State private var showingIntegrationControls = false
    @State private var financialModel = AppFinancialModel()

    private var month: MonthForecast {
        MockForecast.data(for: selectedMonth, transactions: bankStore.transactions)
    }

    private var financialSnapshot: AppFinancialSnapshot {
        try! effectiveFinancialModel.snapshot(through: selectedMonth.horizonDate)
    }

    private var effectiveFinancialModel: AppFinancialModel {
        financialModel.usingBankData(
            accounts: bankStore.accounts,
            transactions: bankStore.transactions
        )
    }

    private var displayedWeather: MoneyWeather {
        selectedMonth.isHistorical ? month.overallWeather : financialSnapshot.horizonStatus.moneyWeather
    }

    private var displayedBalance: Int {
        selectedMonth.isHistorical ? month.accountBalance : Int(financialSnapshot.projectedCash.rounded())
    }

    private var isInsightsPreview: Bool {
#if DEBUG
        ProcessInfo.processInfo.arguments.contains("--preview-insights")
#else
        false
#endif
    }

    private var displayedDays: [ForecastDay] {
        if showingFullMonth { return month.days }

        if let todayIndex = month.days.firstIndex(where: { $0.status == .today }) {
            return Array(month.days[todayIndex...].prefix(7))
        }

        if selectedMonth.isHistorical {
            return Array(month.days.suffix(7))
        }

        return Array(month.days.prefix(7))
    }

    var body: some View {
        ZStack {
            AtmosphericBackground(weather: displayedWeather)

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
                        monthSelector
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
            affordabilityButton
        }
        .sheet(item: $selectedDay) { day in
            DayDetailSheet(day: day)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showingAffordability) {
            AffordabilitySheet(
                model: effectiveFinancialModel,
                planningHorizon: selectedMonth.horizonDate,
                startingWeather: displayedWeather
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showingIntegrationControls) {
            IntegrationControlsSheet(
                model: $financialModel,
                bankStore: bankStore,
                planningHorizon: selectedMonth.horizonDate
            )
            .presentationDetents([.medium, .large])
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
                    .foregroundStyle(Color.sunGold, .white.opacity(0.9))
            }
            .frame(width: 42, height: 42)

            VStack(alignment: .leading, spacing: 1) {
                Text("FINANZAS")
                    .font(.caption.weight(.heavy))
                    .tracking(1.6)
                Text("Financial weather")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.62))
            }

            Spacer()

            Text(bankStore.isLinked ? "NESSIE" : "DEMO")
                .font(.caption2.weight(.bold))
                .tracking(0.8)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.white.opacity(0.12), in: Capsule())

            Button { showingIntegrationControls = true } label: {
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
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white.opacity(0.82))

            Text("$\(displayedBalance.formatted(.number.grouping(.automatic)))")
                .font(.system(size: 74, weight: .thin, design: .rounded))
                .tracking(-4)
                .contentTransition(.numericText(value: Double(displayedBalance)))

            Text(selectedMonth.isHistorical ? month.balanceLabel : "FinancialCore projected balance")
                .font(.title3.weight(.medium))
                .foregroundStyle(.white.opacity(0.9))

            HStack(spacing: 8) {
                Image(systemName: displayedWeather.symbol)
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(
                        displayedWeather.primaryColor,
                        displayedWeather.secondaryColor
                    )
                Text(selectedMonth.isHistorical ? month.conditionTitle : financialSnapshot.horizonStatus.rawValue)
                    .fontWeight(.semibold)
            }
            .font(.headline)
            .padding(.top, 6)

            Text(selectedMonth.isHistorical ? month.summary : "\(financialSnapshot.safeToSpendNow.formatted(.currency(code: "USD").precision(.fractionLength(0)))) safe to spend while preserving your reserve and commitments.")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.68))
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .frame(maxWidth: 315)
                .padding(.top, 3)

            if let today = month.days.first(where: { $0.status == .today }) {
                HStack(spacing: 7) {
                    Text("TODAY")
                        .font(.caption2.weight(.bold))
                        .tracking(0.7)
                    Image(systemName: today.weather.symbol)
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(today.weather.primaryColor, today.weather.secondaryColor)
                    Text(today.formattedAmount)
                        .font(.subheadline.weight(.semibold))
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
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(ForecastMonth.allCases) { forecastMonth in
                    let isSelected = forecastMonth == selectedMonth

                    Button {
                        withAnimation(.easeInOut(duration: 0.4)) {
                            selectedMonth = forecastMonth
                            showingFullMonth = false
                        }
                    } label: {
                        VStack(spacing: 5) {
                            Image(systemName: forecastMonth.mockWeather.symbol)
                                .font(.system(size: 17, weight: .semibold))
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(
                                    forecastMonth.mockWeather.primaryColor,
                                    forecastMonth.mockWeather.secondaryColor
                                )
                            Text(forecastMonth.abbreviation)
                                .font(.subheadline.weight(isSelected ? .bold : .semibold))
                            Circle()
                                .fill(isSelected ? Color.sunGold : .clear)
                                .frame(width: 5, height: 5)
                        }
                        .foregroundStyle(isSelected ? .white : .white.opacity(0.5))
                        .frame(width: 57, height: 70)
                        .background(
                            isSelected ? .white.opacity(0.16) : .clear,
                            in: RoundedRectangle(cornerRadius: 17, style: .continuous)
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(forecastMonth.displayName)
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
        .background(.black.opacity(0.14), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(.white.opacity(0.12), lineWidth: 0.75)
        }
        .padding(.horizontal, 20)
        .sensoryFeedback(.selection, trigger: selectedMonth)
    }

    private var forecastCard: some View {
        VStack(spacing: 0) {
            forecastHeader

            Divider()
                .overlay(.white.opacity(0.14))
                .padding(.horizontal, 16)

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

            Divider()
                .overlay(.white.opacity(0.12))
                .padding(.horizontal, 16)

            Button {
                withAnimation(.easeInOut(duration: 0.3)) {
                    showingFullMonth.toggle()
                }
            } label: {
                HStack(spacing: 7) {
                    Text(showingFullMonth ? "Show fewer days" : "Show all \(month.days.count) days")
                    Image(systemName: showingFullMonth ? "chevron.up" : "chevron.down")
                        .font(.caption2.weight(.bold))
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white.opacity(0.72))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
            }
            .buttonStyle(.plain)
        }
        .background(.black.opacity(0.18), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(.white.opacity(0.13), lineWidth: 0.75)
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
    }

    private var forecastHeader: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("DAILY CHANGES")
                        .font(.caption.weight(.bold))
                        .tracking(1.2)
                        .foregroundStyle(.white.opacity(0.62))
                    Text("\(month.month.displayName) activity")
                        .font(.title3.weight(.semibold))
                }

                Spacer()

                Text("\(month.days.count) days")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.white.opacity(0.5))
            }

            HStack(spacing: 14) {
                ForecastLegendItem(title: "Recorded", style: .recorded)
                ForecastLegendItem(title: "Today", style: .today)
                ForecastLegendItem(title: "Forecast", style: .forecast)
            }
        }
        .padding(18)
    }

    private var balanceChart: some View {
        BalanceChartCard(points: MockForecast.balancePoints)
            .padding(.horizontal, 20)
            .padding(.top, 16)
    }

    private var spendingMetrics: some View {
        SpendingMetricsCard(month: month, snapshot: financialSnapshot)
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
        .font(.caption)
        .foregroundStyle(.white.opacity(0.55))
        .padding(.horizontal, 28)
        .padding(.top, 14)
    }

    private var affordabilityButton: some View {
        Button {
            showingAffordability = true
        } label: {
            HStack(spacing: 13) {
                Image(systemName: "sparkles")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color.sunGold)
                    .frame(width: 38, height: 38)
                    .background(.white.opacity(0.1), in: Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text("Can I afford this?")
                        .font(.headline)
                    Text("Preview a purchase in your forecast")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.58))
                }

                Spacer()

                Image(systemName: "chevron.up")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white.opacity(0.55))
            }
            .foregroundStyle(.white)
            .padding(12)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(.white.opacity(0.18), lineWidth: 0.75)
            }
            .shadow(color: .black.opacity(0.2), radius: 16, y: 8)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 6)
    }
}

private struct ForecastDayRow: View {
    let day: ForecastDay

    var body: some View {
        HStack(spacing: 12) {
            VStack(spacing: 1) {
                Text(day.weekday.uppercased())
                    .font(.caption2.weight(.bold))
                    .tracking(0.7)
                    .foregroundStyle(.white.opacity(0.48))
                Text("\(day.day)")
                    .font(.title3.weight(.semibold))
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
                Text(day.activityTitle)
                    .font(.subheadline.weight(.semibold))
                Label(day.status.label, systemImage: day.status.symbol)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(day.status.foregroundColor)
            }

            Spacer(minLength: 8)

            Text(day.formattedAmount)
                .font(.headline.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(day.weather.amountColor)

            Image(systemName: "chevron.right")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.white.opacity(0.28))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background {
            if day.status == .today {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(.white.opacity(0.12))
                    .overlay {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
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
        .font(.caption2.weight(.medium))
        .foregroundStyle(style.foregroundColor)
    }
}

private struct BalanceChartCard: View {
    let points: [BalancePoint]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("BALANCE TRAJECTORY")
                        .font(.caption.weight(.bold))
                        .tracking(1.2)
                        .foregroundStyle(.white.opacity(0.62))
                    Text("Where your balance is heading")
                        .font(.title3.weight(.semibold))
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
            .chartYScale(domain: 750...2300)
            .chartXAxis {
                AxisMarks(values: .stride(by: .month)) { _ in
                    AxisGridLine().foregroundStyle(.white.opacity(0.08))
                    AxisValueLabel(format: .dateTime.month(.abbreviated))
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.48))
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { _ in
                    AxisGridLine().foregroundStyle(.white.opacity(0.09))
                    AxisValueLabel()
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.48))
                }
            }
            .frame(height: 220)

            HStack(spacing: 8) {
                Image(systemName: "circle.fill")
                    .font(.system(size: 6))
                    .foregroundStyle(.white.opacity(0.55))
                Text("Each point represents a recorded or expected account change.")
            }
            .font(.caption2)
            .foregroundStyle(.white.opacity(0.48))
        }
        .foregroundStyle(.white)
        .padding(18)
        .background(.black.opacity(0.18), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
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
        .font(.caption2.weight(.medium))
        .foregroundStyle(.white.opacity(0.58))
    }
}

private struct SpendingMetricsCard: View {
    let month: MonthForecast
    let snapshot: AppFinancialSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 3) {
                Text("FINANCIALCORE OUTLOOK")
                    .font(.caption.weight(.bold))
                    .tracking(1.2)
                    .foregroundStyle(.white.opacity(0.62))
                Text("Safe to spend now")
                    .font(.title3.weight(.semibold))
            }

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(snapshot.safeToSpendNow, format: .currency(code: "USD").precision(.fractionLength(0)))
                    .font(.system(size: 42, weight: .light, design: .rounded))
                    .monospacedDigit()
                Text("through \(month.month.displayName)")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.5))
            }

            Text("Recommended weekly limit: \(snapshot.recommendedWeeklySpendingLimit.formatted(.currency(code: "USD").precision(.fractionLength(0))))")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white.opacity(0.72))

            Divider().overlay(.white.opacity(0.12))

            HStack(spacing: 0) {
                MiniMetric(
                    icon: "arrow.down.left",
                    value: snapshot.expectedIncome.formatted(.currency(code: "USD").precision(.fractionLength(0))),
                    label: "expected income"
                )

                Divider()
                    .overlay(.white.opacity(0.12))
                    .frame(height: 42)

                MiniMetric(
                    icon: "arrow.up.right",
                    value: snapshot.committedExpenses.formatted(.currency(code: "USD").precision(.fractionLength(0))),
                    label: "committed expenses"
                )
            }
        }
        .foregroundStyle(.white)
        .padding(18)
        .background(.black.opacity(0.18), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
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
                .font(.caption2.weight(.bold))
                .foregroundStyle(delta <= 0 ? Color.rainMist : Color.sunGold)
            VStack(alignment: .leading, spacing: 1) {
                Text(directionText)
                    .font(.caption.weight(.semibold))
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.46))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
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
                    .font(.headline)
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.48))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct DayDetailSheet: View {
    let day: ForecastDay

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
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.68))

                        Image(systemName: day.weather.symbol)
                            .font(.system(size: 64, weight: .medium))
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(day.weather.primaryColor, day.weather.secondaryColor)

                        Text(day.activityTitle)
                            .font(.title2.bold())

                        Text(day.formattedAmount)
                            .font(.system(size: 50, weight: .light, design: .rounded))
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
                            subtitle: "Daily total",
                            amount: day.formattedAmount
                        )
                    }
                    .padding(.horizontal, 16)
                    .background(.black.opacity(0.16), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .stroke(.white.opacity(0.12), lineWidth: 0.75)
                    }

                    Text("This breakdown uses demonstration data and will be replaced by the team’s financial model.")
                        .font(.caption)
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
                    .font(.subheadline.weight(.semibold))
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.55))
            }

            Spacer()

            Text(amount)
                .font(.subheadline.weight(.bold))
                .monospacedDigit()
        }
        .padding(.vertical, 14)
    }
}

private struct AffordabilitySheet: View {
    let model: AppFinancialModel
    let planningHorizon: Date
    let startingWeather: MoneyWeather

    @State private var amountText = ""
    @State private var result: AppPurchaseResult?
    @State private var errorText: String?
    @FocusState private var amountIsFocused: Bool

    private var purchaseAmount: Double? {
        Double(amountText.filter { $0.isNumber || $0 == "." })
    }

    private var resultWeather: MoneyWeather {
        result?.status.moneyWeather ?? startingWeather
    }

    private var resultTitle: String {
        switch result?.status {
        case .safe: "Forecast stays clear"
        case .tight: "Possible, but tight"
        case .notSafe: "Not safe right now"
        case nil: "Try a purchase"
        }
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: resultWeather.backgroundColors,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 22) {
                    Text("PURCHASE OUTLOOK")
                        .font(.caption.weight(.bold))
                        .tracking(1.4)
                        .foregroundStyle(.white.opacity(0.62))
                        .padding(.top, 16)

                    Image(systemName: resultWeather.symbol)
                        .font(.system(size: 70, weight: .medium))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(resultWeather.primaryColor, resultWeather.secondaryColor)
                        .contentTransition(.symbolEffect(.replace))

                    VStack(spacing: 7) {
                        Text(resultTitle)
                            .font(.title.bold())

                        if let result {
                            Text(result.status.rawValue)
                                .font(.headline.bold())
                                .tracking(1.2)
                            Text("\(result.projectedCashAfterPurchase.formatted(.currency(code: "USD").precision(.fractionLength(0)))) at the limiting point")
                                .foregroundStyle(.white.opacity(0.72))
                            Text("Reason: \(result.reason.displayName) · \(result.limitingDate.formatted(date: .abbreviated, time: .omitted))")
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.58))
                                .multilineTextAlignment(.center)
                        } else {
                            Text("FinancialCore checks the full cash-flow horizon, reserve and buffer—not just today’s balance.")
                                .font(.subheadline)
                                .foregroundStyle(.white.opacity(0.68))
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: 310)
                        }
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Can I spend…")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.72))

                        HStack(spacing: 6) {
                            Text("$").foregroundStyle(.white.opacity(0.5))
                            TextField("450", text: $amountText)
                                .keyboardType(.decimalPad)
                                .focused($amountIsFocused)
                                .onChange(of: amountText) { _, _ in result = nil }
                        }
                        .font(.system(size: 42, weight: .semibold, design: .rounded))
                        .padding(.horizontal, 18)
                        .padding(.vertical, 14)
                        .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 20, style: .continuous))

                        Button("Run FinancialCore") {
                            guard let purchaseAmount, purchaseAmount > 0 else { return }
                            amountIsFocused = false
                            do {
                                result = try model.assessPurchase(amount: purchaseAmount, through: planningHorizon)
                                errorText = nil
                            } catch {
                                errorText = String(describing: error)
                            }
                        }
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .foregroundStyle(Color.deepNavy)
                        .background(.white, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
                        .disabled((purchaseAmount ?? 0) <= 0)
                    }
                    .padding(18)
                    .background(.black.opacity(0.16), in: RoundedRectangle(cornerRadius: 26, style: .continuous))

                    if let errorText {
                        Text(errorText).font(.caption).foregroundStyle(.red)
                    }

                    Label("Deterministic FinancialCore result", systemImage: "checkmark.shield")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.52))
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 28)
            }
            .scrollIndicators(.hidden)
        }
        .preferredColorScheme(.dark)
        .animation(.easeInOut(duration: 0.45), value: resultWeather)
    }
}

private struct LegacyAffordabilitySheet: View {
    let accountBalance: Int
    let startingWeather: MoneyWeather

    @State private var amountText = ""
    @State private var evaluatedAmount: Int?
    @FocusState private var amountIsFocused: Bool

    private var purchaseAmount: Int? {
        Int(amountText.filter(\.isNumber))
    }

    private var remaining: Int {
        accountBalance - (evaluatedAmount ?? 0)
    }

    private var resultWeather: MoneyWeather {
        guard evaluatedAmount != nil else { return startingWeather }
        if remaining >= 1500 { return .sunny }
        if remaining >= 1000 { return .partlySunny }
        if remaining >= 500 { return .cloudy }
        if remaining >= 0 { return .rain }
        return .storm
    }

    private var resultTitle: String {
        guard evaluatedAmount != nil else { return "Try a purchase" }
        if remaining >= 1500 { return "Forecast stays clear" }
        if remaining >= 1000 { return "Mostly clear afterward" }
        if remaining >= 500 { return "Clouds move in" }
        if remaining >= 0 { return "Balance gets tight" }
        return "High pressure ahead"
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: resultWeather.backgroundColors,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 22) {
                    Text("PURCHASE OUTLOOK")
                        .font(.caption.weight(.bold))
                        .tracking(1.4)
                        .foregroundStyle(.white.opacity(0.62))
                        .padding(.top, 16)

                    Image(systemName: resultWeather.symbol)
                        .font(.system(size: 70, weight: .medium))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(resultWeather.primaryColor, resultWeather.secondaryColor)
                        .contentTransition(.symbolEffect(.replace))

                    VStack(spacing: 6) {
                        Text(resultTitle)
                            .font(.title.bold())
                            .multilineTextAlignment(.center)

                        if evaluatedAmount != nil {
                            Text(remaining >= 0 ? "$\(remaining) projected balance" : "$\(abs(remaining)) beyond the account balance")
                                .font(.headline.weight(.medium))
                                .foregroundStyle(.white.opacity(0.72))
                                .multilineTextAlignment(.center)
                                .contentTransition(.numericText(value: Double(remaining)))
                        } else {
                            Text("See how a hypothetical purchase changes the projected account balance and financial weather.")
                                .font(.subheadline)
                                .foregroundStyle(.white.opacity(0.68))
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: 310)
                        }
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Can I spend…")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.72))

                        HStack(spacing: 6) {
                            Text("$")
                                .foregroundStyle(.white.opacity(0.5))
                            TextField("80", text: $amountText)
                                .keyboardType(.numberPad)
                                .focused($amountIsFocused)
                                .onChange(of: amountText) { _, _ in
                                    evaluatedAmount = nil
                                }
                        }
                        .font(.system(size: 42, weight: .semibold, design: .rounded))
                        .padding(.horizontal, 18)
                        .padding(.vertical, 14)
                        .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .stroke(.white.opacity(amountIsFocused ? 0.4 : 0.14), lineWidth: 1)
                        }

                        Button {
                            guard let purchaseAmount, purchaseAmount > 0 else { return }
                            amountIsFocused = false
                            withAnimation(.easeInOut(duration: 0.45)) {
                                evaluatedAmount = purchaseAmount
                            }
                        } label: {
                            Text("Update forecast")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 15)
                                .foregroundStyle(Color.deepNavy)
                                .background(.white, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .disabled((purchaseAmount ?? 0) <= 0)
                        .opacity((purchaseAmount ?? 0) <= 0 ? 0.48 : 1)
                    }
                    .padding(18)
                    .background(.black.opacity(0.16), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 26, style: .continuous)
                            .stroke(.white.opacity(0.13), lineWidth: 0.75)
                    }

                    Label("Demo estimate — not financial advice", systemImage: "wand.and.stars")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.52))
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 28)
            }
            .scrollIndicators(.hidden)
        }
        .preferredColorScheme(.dark)
        .animation(.easeInOut(duration: 0.45), value: resultWeather)
    }
}

private struct IntegrationControlsSheet: View {
    @Binding var model: AppFinancialModel
    @ObservedObject var bankStore: BankAccountStore
    let planningHorizon: Date
    @State private var showingLinkAccount = false

    private var effectiveModel: AppFinancialModel {
        model.usingBankData(accounts: bankStore.accounts, transactions: bankStore.transactions)
    }

    private var snapshot: AppFinancialSnapshot {
        try! effectiveModel.snapshot(through: planningHorizon)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Linked account") {
                    if bankStore.isLinked {
                        ForEach(bankStore.accounts) { account in
                            LabeledContent(account.name) {
                                Text(
                                    Double(account.balanceMinorUnits) / 100,
                                    format: .currency(code: account.currencyCode).precision(.fractionLength(2))
                                )
                            }
                        }
                        LabeledContent("Imported transactions", value: "\(bankStore.transactions.count)")
                        Button("Sync another Nessie customer") { showingLinkAccount = true }
                    } else {
                        Button {
                            showingLinkAccount = true
                        } label: {
                            Label("Link a Nessie account", systemImage: "link.circle.fill")
                        }
                        Text("Balances and transactions from the linked account become the source for the entire forecast.")
                            .font(.footnote)
                    }
                }

                Section("Qualitative decisions") {
                    Toggle("Expense is essential / committed", isOn: $model.optionalExpenseIsCommitted)
                    Toggle("Goal is mandatory", isOn: $model.goalIsMandatory)
                }

                Section("FinancialCore result") {
                    LabeledContent("Projected cash") {
                        Text(snapshot.projectedCash, format: .currency(code: "USD").precision(.fractionLength(0)))
                    }
                    LabeledContent("Safe to spend") {
                        Text(snapshot.safeToSpendNow, format: .currency(code: "USD").precision(.fractionLength(0)))
                    }
                    LabeledContent("Current", value: snapshot.currentStatus.rawValue)
                    LabeledContent("Horizon", value: snapshot.horizonStatus.rawValue)
                    LabeledContent("Mandatory goals") {
                        Text(snapshot.mandatoryGoals, format: .currency(code: "USD").precision(.fractionLength(0)))
                    }
                }

                Section("Mapped income") {
                    Text("Recurring income enters at full value. Irregular income enters as amount × confidence; the demo maps $300 tutoring at 70% to $210.")
                        .font(.footnote)
                }

                Section("Integration note") {
                    Text("These controls change qualitative inputs only. SAFE, TIGHT and NOT_SAFE always come from FinancialCore.")
                        .font(.footnote)
                }
            }
            .navigationTitle("Financial profile")
            .sheet(isPresented: $showingLinkAccount) {
                LinkBankAccountSheet(store: bankStore)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
        }
    }
}

private struct LinkBankAccountSheet: View {
    @ObservedObject var store: BankAccountStore
    @Environment(\.dismiss) private var dismiss
    @State private var customerID = ""
    @State private var apiKey = ""

    private var canConnect: Bool {
        !customerID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Nessie credentials") {
                    TextField("Customer ID", text: $customerID)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("API key", text: $apiKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                Section {
                    Button {
                        Task {
                            await store.linkNessieAccount(apiKey: apiKey, customerID: customerID)
                            if store.isLinked {
                                apiKey = ""
                                dismiss()
                            }
                        }
                    } label: {
                        HStack {
                            if store.phase == .connecting { ProgressView() }
                            Text(store.phase == .connecting ? "Connecting…" : "Connect & sync")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .disabled(!canConnect || store.phase == .connecting)
                } footer: {
                    Text("The API key stays in memory only. Normalized account and transaction data is cached on this iPhone.")
                }

                if case let .failed(message) = store.phase {
                    Section("Couldn’t connect") {
                        Text(message).foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Link account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
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
    case january = 1
    case february = 2
    case march = 3
    case april = 4
    case may = 5
    case june = 6
    case july = 7
    case august = 8
    case september = 9
    case october = 10
    case november = 11
    case december = 12

    var id: Int { rawValue }

    var displayName: String {
        switch self {
        case .january: return "January"
        case .february: return "February"
        case .march: return "March"
        case .april: return "April"
        case .may: return "May"
        case .june: return "June"
        case .july: return "July"
        case .august: return "August"
        case .september: return "September"
        case .october: return "October"
        case .november: return "November"
        case .december: return "December"
        }
    }

    var abbreviation: String {
        String(displayName.prefix(3)).uppercased()
    }

    var dayCount: Int {
        switch self {
        case .january, .march, .may, .july, .august, .october, .december: return 31
        case .april, .june, .september, .november: return 30
        case .february: return 28
        }
    }

    var mockWeather: MoneyWeather {
        switch self {
        case .january, .february, .march, .april, .may, .june, .july: return .cloudy
        case .august: return .sunny
        case .september: return .partlySunny
        case .october: return .cloudy
        case .november: return .rain
        case .december: return .storm
        }
    }

    var previousName: String {
        switch self {
        case .january: return "December"
        case .february: return "January"
        case .march: return "February"
        case .april: return "March"
        case .may: return "April"
        case .june: return "May"
        case .july: return "June"
        case .august: return "July"
        case .september: return "August"
        case .october: return "September"
        case .november: return "October"
        case .december: return "November"
        }
    }

    var isHistorical: Bool { rawValue <= ForecastMonth.august.rawValue }

    var horizonDate: Date {
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.year = 2026
        components.month = rawValue
        components.day = dayCount
        return components.date ?? Date(timeIntervalSince1970: 0)
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

private enum MoneyWeather: String {
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
        case .partlySunny: return Color.sunGold
        case .cloudy: return Color.cloudSilver
        case .rain: return Color.rainBlue
        case .storm: return Color.stormLavender
        }
    }

    var secondaryColor: Color {
        switch self {
        case .sunny: return Color.sunOrange
        case .partlySunny: return Color.cloudCream
        case .cloudy: return Color.cloudSlate
        case .rain: return Color.rainMist
        case .storm: return Color.stormBlue
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

private extension FinancialHealthStatus {
    var moneyWeather: MoneyWeather {
        switch self {
        case .safe: .sunny
        case .tight: .rain
        case .notSafe: .storm
        }
    }
}

private extension PurchaseStatus {
    var moneyWeather: MoneyWeather {
        switch self {
        case .safe: .sunny
        case .tight: .rain
        case .notSafe: .storm
        }
    }
}

private extension PurchaseDecisionReason {
    var displayName: String {
        switch self {
        case .preservesRecommendedBuffer: "Preserves the recommended buffer"
        case .usesSafetyBuffer: "Uses part of the safety buffer"
        case .violatesPersonalReserve: "Would cross the personal reserve"
        case .violatesInstitutionalMinimum: "Would cross an account minimum"
        case .violatesMultipleHardConstraints: "Would cross multiple hard constraints"
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

    var formattedAmount: String {
        if amount > 0 { return "+$\(amount)" }
        if amount < 0 { return "−$\(abs(amount))" }
        return "$0"
    }

    var activityTitle: String {
        amount == 0 ? "No activity" : weather.dailyTitle
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
    static let todayDate = makeDate(month: 9, day: 11)

    static let balancePoints: [BalancePoint] = [
        point("jun-start", 6, 1, 1180, .actual, true),
        point("jun-income", 6, 8, 1500, .actual),
        point("jun-rent", 6, 15, 880, .actual),
        point("jun-work", 6, 24, 1330, .actual),
        point("jun-close", 6, 30, 1280, .actual),
        point("jul-income", 7, 5, 1600, .actual),
        point("jul-rent", 7, 15, 980, .actual),
        point("jul-work", 7, 25, 1430, .actual),
        point("jul-close", 7, 31, 1480, .actual),
        point("aug-spend", 8, 4, 1435, .actual),
        point("aug-income", 8, 9, 1755, .actual),
        point("aug-rent", 8, 15, 1135, .actual),
        point("aug-work", 8, 24, 1585, .actual),
        point("aug-close", 8, 31, 1530, .actual, true),
        point("sep-spend-a", 9, 3, 1502, .actual),
        point("sep-spend-b", 9, 8, 1456, .actual),
        point("today-actual", 9, 11, 1842, .actual, true),
        point("today-expected", 9, 11, 1842, .expected, true),
        point("sep-rent", 9, 15, 1222, .expected),
        point("sep-work", 9, 17, 1672, .expected),
        point("sep-close", 9, 28, 1648, .expected),
        point("oct-income", 10, 5, 1968, .expected),
        point("oct-rent", 10, 15, 1348, .expected),
        point("oct-work", 10, 22, 1798, .expected),
        point("nov-income", 11, 8, 2078, .expected),
        point("nov-rent", 11, 18, 1458, .expected),
        point("nov-work", 11, 25, 1908, .expected),
        point("dec-income", 12, 8, 2228, .expected),
        point("dec-rent", 12, 18, 1608, .expected),
        point("dec-work", 12, 23, 2058, .expected),
        point("dec-close", 12, 28, 1973, .expected, true)
    ]

    static func data(for month: ForecastMonth, transactions: [FinanceCore.FinancialTransaction] = []) -> MonthForecast {
        let overview: (
            balance: Int,
            balanceLabel: String,
            weather: MoneyWeather,
            title: String,
            summary: String,
            averageSpending: Double,
            previousDelta: Int,
            allTimeDelta: Int
        )

        switch month {
        case .january, .february, .march, .april, .may, .june, .july:
            let monthTransactions = transactions.filter {
                let parts = Calendar(identifier: .gregorian).dateComponents([.year, .month], from: $0.transactionDate)
                return parts.year == 2026 && parts.month == month.rawValue
            }
            let net = monthTransactions.reduce(Int64(0)) { $0 + $1.signedAmountMinorUnits }
            let spending = monthTransactions.filter { $0.direction == .outflow }.reduce(Int64(0)) { $0 + $1.amountMinorUnits }
            overview = (
                Int(net / 100),
                transactions.isEmpty ? "Demo monthly movement" : "Nessie net movement",
                weather(for: Int(net / 100)),
                monthTransactions.isEmpty ? "No activity" : "Recorded activity",
                transactions.isEmpty ? "Connect Nessie to inspect this month’s bank history." : "Showing \(monthTransactions.count) normalized Nessie transactions from this month.",
                Double(spending) / 100 / Double(month.dayCount),
                0,
                0
            )
        case .august:
            overview = (1530, "Closing account balance", .sunny, "Clear", "Income comfortably covered scheduled bills and everyday spending.", 34.60, 7, 4)
        case .september:
            overview = (1842, "Current account balance", .partlySunny, "Mostly Clear", "Your current balance has room for scheduled bills and normal daily spending.", 31.20, -10, -6)
        case .october:
            overview = (1770, "Projected closing balance", .cloudy, "A Little Cloudy", "Expected income covers the major payments, with less room between them.", 32.80, 5, -1)
        case .november:
            overview = (1435, "Projected closing balance", .rain, "Rain Possible", "Travel and recurring payments create a tighter stretch ahead.", 39.10, 19, 18)
        case .december:
            overview = (1180, "Projected closing balance", .storm, "High Pressure", "Large seasonal expenses call for more careful day-to-day spending.", 44.70, 14, 34)
        }

        return MonthForecast(
            month: month,
            accountBalance: overview.balance,
            balanceLabel: overview.balanceLabel,
            overallWeather: overview.weather,
            conditionTitle: overview.title,
            summary: overview.summary,
            averageDailySpending: overview.averageSpending,
            previousMonthDelta: overview.previousDelta,
            allTimeDelta: overview.allTimeDelta,
            days: makeDays(for: month, transactions: transactions)
        )
    }

    private static func makeDays(for month: ForecastMonth, transactions: [FinanceCore.FinancialTransaction]) -> [ForecastDay] {
        (1...month.dayCount).map { day in
            let dayTransactions = transactions.filter {
                let parts = Calendar(identifier: .gregorian).dateComponents([.year, .month, .day], from: $0.transactionDate)
                return parts.year == 2026 && parts.month == month.rawValue && parts.day == day
            }
            let useBankHistory = !transactions.isEmpty && month.isHistorical
            let bankAmount = Int(dayTransactions.reduce(Int64(0)) { $0 + $1.signedAmountMinorUnits } / 100)
            let amount = useBankHistory ? bankAmount : mockAmount(month: month, day: day)
            let weather = weather(for: amount)
            let status = status(for: month, day: day)
            let routineSpending = 18 + ((day * 7) % 38)
            let income = useBankHistory ? Int(dayTransactions.filter { $0.direction == .inflow }.reduce(Int64(0)) { $0 + $1.amountMinorUnits } / 100) : (amount > 0 ? amount + routineSpending : 0)
            let expenses = useBankHistory ? Int(dayTransactions.filter { $0.direction == .outflow }.reduce(Int64(0)) { $0 + $1.amountMinorUnits } / 100) : (amount > 0 ? routineSpending : abs(amount))
            let sources = dayTransactions.compactMap { $0.merchantName ?? $0.transactionDescription }.prefix(2).joined(separator: ", ")

            return ForecastDay(
                id: "\(month.rawValue)-\(day)",
                month: month,
                day: day,
                weekday: weekday(month: month, day: day),
                amount: amount,
                weather: weather,
                status: status,
                income: income,
                expenses: expenses,
                incomeSource: useBankHistory ? (sources.isEmpty ? "Nessie deposit" : sources) : (income == 0 ? "Nothing scheduled" : (income >= 300 ? "Campus job deposit" : "Transfer or side income")),
                expenseSource: useBankHistory ? (sources.isEmpty ? "Nessie transaction" : sources) : (expenses == 0 ? "Nothing scheduled" : (expenses >= 300 ? "Rent and scheduled bills" : "Dining, transit, and daily spending"))
            )
        }
    }

    private static func mockAmount(month: ForecastMonth, day: Int) -> Int {
        let scheduledChanges: [ForecastMonth: [Int: Int]] = [
            .august: [3: -18, 7: -42, 9: 320, 12: -24, 15: -620, 20: -74, 24: 450, 29: -38],
            .september: [2: -12, 4: -28, 8: -46, 11: 320, 15: -620, 17: 450, 22: -74, 28: -24],
            .october: [3: -45, 5: 320, 10: -18, 15: -620, 22: 450, 28: -92],
            .november: [4: -36, 8: 280, 14: -88, 18: -620, 25: 450],
            .december: [2: -55, 8: 320, 12: -110, 18: -620, 23: 450, 28: -85]
        ]

        return scheduledChanges[month]?[day] ?? 0
    }

    private static func weather(for amount: Int) -> MoneyWeather {
        if amount >= 150 { return .sunny }
        if amount > 10 { return .partlySunny }
        if amount >= -25 { return .cloudy }
        if amount > -200 { return .rain }
        return .storm
    }

    private static func status(for month: ForecastMonth, day: Int) -> DayStatus {
        if month.isHistorical { return .recorded }
        if month == .september {
            if day < 11 { return .recorded }
            if day == 11 { return .today }
        }
        return .forecast
    }

    private static func weekday(month: ForecastMonth, day: Int) -> String {
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.year = 2026
        components.month = month.rawValue
        components.day = day

        guard let date = components.date else { return "Day" }
        return date.formatted(.dateTime.weekday(.abbreviated))
    }

    private static func point(
        _ id: String,
        _ month: Int,
        _ day: Int,
        _ balance: Double,
        _ series: BalanceSeries,
        _ isAnchor: Bool = false
    ) -> BalancePoint {
        BalancePoint(
            id: id,
            date: makeDate(month: month, day: day),
            balance: balance,
            series: series,
            isAnchor: isAnchor
        )
    }

    private static func makeDate(month: Int, day: Int) -> Date {
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.year = 2026
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

#Preview {
    ContentView()
}
