import SwiftUI

struct ContentView: View {
    @State private var selectedPeriod = "This month"
    @State private var selectedTab = DashboardTab.home

    private let forecast = [
        ForecastDay(day: "Today", symbol: "sun.max.fill", amount: "+$84", color: .yellow),
        ForecastDay(day: "Tue", symbol: "cloud.sun.fill", amount: "+$22", color: .orange),
        ForecastDay(day: "Wed", symbol: "cloud.rain.fill", amount: "−$46", color: .blue),
        ForecastDay(day: "Thu", symbol: "cloud.fill", amount: "−$12", color: .gray)
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    colors: [Color.skyTop, Color.skyBottom],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                atmosphericBackground

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 22) {
                        header
                        balanceCard
                        forecastSection
                        quickActions
                        spendingCard
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 28)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .tint(Color.navy)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            bottomNavigation
        }
    }

    private var atmosphericBackground: some View {
        GeometryReader { geometry in
            ZStack {
                Circle()
                    .fill(.white.opacity(0.08))
                    .frame(width: 260, height: 260)
                    .offset(x: geometry.size.width * 0.34, y: -80)

                Image(systemName: "cloud.fill")
                    .font(.system(size: 170))
                    .foregroundStyle(.white.opacity(0.055))
                    .offset(x: -geometry.size.width * 0.32, y: geometry.size.height * 0.31)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text(greeting)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white.opacity(0.78))
                HStack(spacing: 7) {
                    Text("Your money weather")
                    Image(systemName: "sun.max.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.yellow)
                }
                    .font(.title2.bold())
                    .foregroundStyle(.white)
            }

            Spacer()

            Button(action: {}) {
                Image(systemName: "bell.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.navy)
                    .frame(width: 44, height: 44)
                    .background(.white.opacity(0.92), in: Circle())
                    .overlay(alignment: .topTrailing) {
                        Circle()
                            .fill(Color.sunOrange)
                            .frame(width: 10, height: 10)
                            .overlay(Circle().stroke(.white, lineWidth: 2))
                    }
            }
            .accessibilityLabel("Notifications")
        }
        .padding(.top, 16)
    }

    private var balanceCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("AVAILABLE BALANCE")
                        .font(.caption2.weight(.bold))
                        .tracking(1.1)
                        .foregroundStyle(Color.navy.opacity(0.55))
                    Text("$4,280.16")
                        .font(.system(size: 38, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.navy)
                }

                Spacer()

                Image(systemName: "sun.max.fill")
                    .font(.system(size: 36))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.yellow, .orange)
            }

            HStack(spacing: 8) {
                Image(systemName: "arrow.up.right")
                Text("8.4% sunnier than last month")
            }
            .font(.footnote.weight(.semibold))
            .foregroundStyle(Color.growthGreen)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.growthGreen.opacity(0.1), in: Capsule())
        }
        .padding(22)
        .background(.white.opacity(0.94), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .shadow(color: Color.navy.opacity(0.12), radius: 24, y: 12)
    }

    private var forecastSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Cash forecast")
                    .font(.title3.bold())
                    .foregroundStyle(.white)
                Spacer()
                Button("See details", action: {})
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.85))
            }

            HStack(spacing: 10) {
                ForEach(forecast) { item in
                    VStack(spacing: 9) {
                        Text(item.day)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.navy.opacity(0.6))
                        Image(systemName: item.symbol)
                            .font(.title2)
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(item.color)
                            .frame(height: 26)
                        Text(item.amount)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(Color.navy)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(.white.opacity(0.9), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                }
            }
        }
    }

    private var quickActions: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Quick actions")
                .font(.title3.bold())
                .foregroundStyle(.white)

            HStack(spacing: 12) {
                ActionButton(title: "Add income", symbol: "plus", color: Color.growthGreen)
                ActionButton(title: "Add expense", symbol: "minus", color: Color.rainBlue)
                ActionButton(title: "Transfer", symbol: "arrow.left.arrow.right", color: Color.sunOrange)
            }
        }
    }

    private var spendingCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Spending climate")
                        .font(.headline)
                        .foregroundStyle(Color.navy)
                    Text("$1,340 of $2,000")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Picker("Period", selection: $selectedPeriod) {
                    Text("This month").tag("This month")
                    Text("Last month").tag("Last month")
                }
                .labelsHidden()
                .font(.caption)
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.navy.opacity(0.08))
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [Color.growthGreen, Color.sunOrange],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: geometry.size.width * 0.67)
                }
            }
            .frame(height: 12)

            HStack {
                Label("67% used", systemImage: "umbrella.fill")
                Spacer()
                Text("$660 left")
            }
            .font(.footnote.weight(.semibold))
            .foregroundStyle(Color.navy.opacity(0.72))
        }
        .padding(20)
        .background(.white.opacity(0.94), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private var bottomNavigation: some View {
        HStack(spacing: 0) {
            ForEach(DashboardTab.allCases) { tab in
                Button {
                    selectedTab = tab
                } label: {
                    VStack(spacing: 5) {
                        Image(systemName: tab.symbol)
                            .font(.system(size: 18, weight: .semibold))
                            .frame(height: 22)
                        Text(tab.title)
                            .font(.caption2.weight(.semibold))
                    }
                    .foregroundStyle(selectedTab == tab ? Color.navy : Color.navy.opacity(0.45))
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selectedTab == tab ? .isSelected : [])
            }
        }
        .padding(.top, 12)
        .padding(.horizontal, 10)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(.white.opacity(0.5))
                .frame(height: 0.5)
        }
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12: return "Good morning"
        case 12..<17: return "Good afternoon"
        default: return "Good evening"
        }
    }
}

private enum DashboardTab: String, CaseIterable, Identifiable {
    case home
    case activity
    case goals
    case profile

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: "Home"
        case .activity: "Activity"
        case .goals: "Goals"
        case .profile: "Profile"
        }
    }

    var symbol: String {
        switch self {
        case .home: "cloud.sun.fill"
        case .activity: "chart.xyaxis.line"
        case .goals: "target"
        case .profile: "person.fill"
        }
    }
}

private struct ForecastDay: Identifiable {
    let id = UUID()
    let day: String
    let symbol: String
    let amount: String
    let color: Color
}

private struct ActionButton: View {
    let title: String
    let symbol: String
    let color: Color

    var body: some View {
        Button(action: {}) {
            VStack(spacing: 9) {
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(color, in: Circle())
                Text(title)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Color.navy)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(.white.opacity(0.9), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private extension Color {
    static let skyTop = Color(red: 0.14, green: 0.48, blue: 0.84)
    static let skyBottom = Color(red: 0.48, green: 0.75, blue: 0.91)
    static let navy = Color(red: 0.05, green: 0.16, blue: 0.27)
    static let growthGreen = Color(red: 0.10, green: 0.62, blue: 0.43)
    static let rainBlue = Color(red: 0.16, green: 0.48, blue: 0.78)
    static let sunOrange = Color(red: 0.96, green: 0.55, blue: 0.16)
}

#Preview {
    ContentView()
}
