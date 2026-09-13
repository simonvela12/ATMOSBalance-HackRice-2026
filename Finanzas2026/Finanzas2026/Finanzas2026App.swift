import Foundation
import SwiftUI
import FinancialCore

@main
struct Finanzas2026App: App {
    @StateObject private var bankStore = BankAccountStore()

    var body: some Scene {
        WindowGroup {
            ProtectedFundsRootView()
                .environmentObject(bankStore)
        }
    }
}

/// Keeps the product's most important number visible before any forecast detail:
/// how much of the bank balance is actually liquid after hard commitments.
private struct ProtectedFundsRootView: View {
    @EnvironmentObject private var bankStore: BankAccountStore

    var body: some View {
        ProductRootView()
            .safeAreaInset(edge: .top, spacing: 0) {
                if bankStore.isLinked {
                    ProtectedFundsBanner()
                        .environmentObject(bankStore)
                }
            }
    }
}

private struct ProtectedFundsBanner: View {
    @EnvironmentObject private var bankStore: BankAccountStore
    @State private var summary = ProtectedFundsSummary.empty
    @State private var showingDetails = false

    private static let money = FloatingPointFormatStyle<Double>.Currency(code: "USD")
        .precision(.fractionLength(0))

    var body: some View {
        Button {
            showingDetails = true
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 14) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("SAFE TO SPEND")
                            .font(.caption2.weight(.bold))
                            .tracking(1.1)
                            .foregroundStyle(.white.opacity(0.58))
                        Text(Self.money.format(summary.safeToSpend))
                            .font(.system(size: 30, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .contentTransition(.numericText(value: summary.safeToSpend))
                        Text("of \(Self.money.format(summary.balance)) current balance")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.50))
                    }

                    Spacer(minLength: 8)

                    VStack(alignment: .trailing, spacing: 4) {
                        HStack(spacing: 5) {
                            Image(systemName: "lock.fill")
                                .font(.caption2.weight(.bold))
                            Text("\(Self.money.format(summary.protected)) protected")
                                .font(.subheadline.weight(.semibold))
                                .monospacedDigit()
                        }
                        .foregroundStyle(Color(red: 1.00, green: 0.82, blue: 0.24))

                        HStack(spacing: 5) {
                            Text(summary.reasonLine)
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.64))
                                .multilineTextAlignment(.trailing)
                                .lineLimit(2)
                            Image(systemName: "chevron.right")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.white.opacity(0.35))
                        }
                    }
                    .frame(maxWidth: 200, alignment: .trailing)
                }

                if summary.protected > summary.balance + 0.005 {
                    Label(
                        "Protected commitments exceed the current balance by \(Self.money.format(summary.protected - summary.balance)).",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Color(red: 1.00, green: 0.82, blue: 0.24))
                }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
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
                Rectangle()
                    .fill(.white.opacity(0.10))
                    .frame(height: 0.5)
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(Self.money.format(summary.available)) available to spend. " +
            "\(Self.money.format(summary.protected)) protected. \(summary.reasonLine)"
        )
        .accessibilityHint("Opens the protected money breakdown")
        .sheet(isPresented: $showingDetails) {
            ProtectedFundsDetailSheet(summary: summary)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .task {
            while !Task.isCancelled {
                refresh()
                try? await Task.sleep(nanoseconds: 600_000_000)
            }
        }
        .onChange(of: bankStore.accounts) { _, _ in refresh() }
        .onChange(of: bankStore.transactions) { _, _ in refresh() }
    }

    private func refresh() {
        guard bankStore.isLinked else {
            summary = .empty
            return
        }

        let plan = ProtectedPlanSnapshot.load()
        let base = AppFinancialData.profile(
            currentCash: bankStore.totalAvailableCash,
            transactions: bankStore.transactions
        )
        let savingsPot = SavingsAccrual.accrued(profile: base)
        let allocation = SavingsAccrual.allocate(
            savingsPot,
            across: plan.goals.map { goal in
                SavingsAccrual.GoalNeed(
                    id: goal.id,
                    remaining: max(0, Double(goal.targetAmount - goal.saved)),
                    deadline: goal.targetDate,
                    priority: goal.mustHappen ? .mandatory : goal.effectivePriority,
                    flexibility: goal.effectiveFlexibility
                )
            }
        )

        let engineGoals = plan.goals.map { goal in
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
                lifecycleState: goal.lifecycleState
            )
        }

        let profile = AppFinancialData.profile(
            currentCash: bankStore.totalAvailableCash,
            transactions: bankStore.transactions,
            goals: engineGoals,
            minimumCashReserve: plan.minimumCashReserve
        )

        // One engine decides affordability. The banner only renders what it returns:
        // no balance arithmetic happens in SwiftUI.
        let scenarios = try? SafeToSpendEngine.evaluateAllScenarios(profile: profile)
        let state = scenarios?.primary
        let available = state?.hardCapacity ?? max(0, profile.currentCash)
        let protected = max(0, profile.currentCash - available)
        let mandatory = engineGoals
            .filter {
                $0.priority == .mandatory &&
                $0.lifecycleState == .active &&
                $0.remainingAmount > 0
            }
            .sorted { $0.deadline < $1.deadline }
            .map {
                ProtectedCommitment(
                    id: $0.id,
                    name: $0.name,
                    amount: $0.remainingAmount,
                    deadline: $0.deadline
                )
            }

        let goalProtected = mandatory.reduce(0) { $0 + $1.amount }
        let reserveProtected = max(0, protected - goalProtected)
        let newSummary = ProtectedFundsSummary(
            balance: max(0, profile.currentCash),
            protected: max(0, protected),
            available: max(0, available),
            safeToSpend: max(0, state?.amount ?? 0),
            expectedSafeToSpend: max(0, scenarios?.expected.amount ?? 0),
            optimisticSafeToSpend: max(0, scenarios?.optimistic.amount ?? 0),
            safetyBuffer: max(0, state?.safetyReserve ?? 0),
            futureCommitments: max(0, state?.futureCommitments ?? 0),
            runwayRequestedDate: state?.runway.requestedDate,
            runwayEndDate: state?.runway.projectedDepletionDate,
            commitments: mandatory,
            reserveProtected: reserveProtected
        )

        if newSummary != summary {
            summary = newSummary
        }
    }
}

private struct ProtectedFundsDetailSheet: View {
    let summary: ProtectedFundsSummary

    private static let money = FloatingPointFormatStyle<Double>.Currency(code: "USD")
        .precision(.fractionLength(0))

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.025, green: 0.075, blue: 0.13),
                    Color(red: 0.05, green: 0.17, blue: 0.24),
                    Color(red: 0.02, green: 0.05, blue: 0.09)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("PROTECTED MONEY")
                            .font(.caption.weight(.bold))
                            .tracking(1.2)
                            .foregroundStyle(.white.opacity(0.58))
                        Text("What you can actually spend")
                            .font(.title2.weight(.bold))
                        Text("Your goals are deadlines, not savings jars. Nothing is set aside: the plan is simulated forward and whatever survives that simulation is yours to spend today.")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.60))
                    }

                    HStack(spacing: 12) {
                        ProtectedMetric(
                            title: "SAFE TO SPEND",
                            value: Self.money.format(summary.safeToSpend),
                            symbol: "banknote.fill"
                        )
                        ProtectedMetric(
                            title: "PROTECTED",
                            value: Self.money.format(summary.protected),
                            symbol: "lock.fill"
                        )
                    }

                    VStack(spacing: 0) {
                        ProtectedBreakdownRow(
                            title: "Total balance",
                            value: Self.money.format(summary.balance)
                        )
                        Divider().overlay(.white.opacity(0.10))
                        ProtectedBreakdownRow(
                            title: "Future commitments",
                            value: Self.money.format(summary.futureCommitments)
                        )
                        Divider().overlay(.white.opacity(0.10))
                        ProtectedBreakdownRow(
                            title: "Safety buffer",
                            value: Self.money.format(summary.safetyBuffer)
                        )
                        Divider().overlay(.white.opacity(0.10))
                        ProtectedBreakdownRow(
                            title: "Safe to spend",
                            value: Self.money.format(summary.safeToSpend),
                            emphasised: true
                        )
                    }
                    .padding(.horizontal, 16)
                    .background(.black.opacity(0.16), in: RoundedRectangle(cornerRadius: 18, style: .continuous))

                    VStack(alignment: .leading, spacing: 0) {
                        Text("IF THINGS GO...")
                            .font(.caption.weight(.bold))
                            .tracking(1.0)
                            .foregroundStyle(.white.opacity(0.55))
                            .padding(.top, 14)
                            .padding(.bottom, 2)
                        ProtectedBreakdownRow(
                            title: "Cautiously (recommended)",
                            value: Self.money.format(summary.safeToSpend),
                            emphasised: true
                        )
                        Divider().overlay(.white.opacity(0.10))
                        ProtectedBreakdownRow(
                            title: "As expected",
                            value: Self.money.format(summary.expectedSafeToSpend)
                        )
                        Divider().overlay(.white.opacity(0.10))
                        ProtectedBreakdownRow(
                            title: "Well",
                            value: Self.money.format(summary.optimisticSafeToSpend)
                        )
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 4)
                    .background(.black.opacity(0.16), in: RoundedRectangle(cornerRadius: 18, style: .continuous))

                    if let requested = summary.runwayRequestedDate {
                        Label {
                            if let end = summary.runwayEndDate, end <= requested {
                                Text("Your money is projected to run out on \(end.formatted(.dateTime.month(.abbreviated).day())), before the \(requested.formatted(.dateTime.month(.abbreviated).day())) you asked it to last until.")
                            } else {
                                Text("Your money is projected to last past \(requested.formatted(.dateTime.month(.abbreviated).day())), as you asked.")
                            }
                        } icon: {
                            Image(systemName: summary.runwayAtRisk ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                        }
                        .font(.caption)
                        .foregroundStyle(
                            summary.runwayAtRisk
                                ? Color(red: 1.00, green: 0.72, blue: 0.30)
                                : .white.opacity(0.60)
                        )
                    }

                    VStack(alignment: .leading, spacing: 0) {
                        Text("WHY IT'S PROTECTED")
                            .font(.caption.weight(.bold))
                            .tracking(1.0)
                            .foregroundStyle(.white.opacity(0.55))
                            .padding(.bottom, 8)

                        if summary.commitments.isEmpty && summary.reserveProtected <= 0.005 {
                            Text("Nothing is protected yet. Mark a goal as Must happen when its money should stop being treated as spendable.")
                                .font(.subheadline)
                                .foregroundStyle(.white.opacity(0.65))
                                .padding(.vertical, 14)
                        } else {
                            ForEach(Array(summary.commitments.enumerated()), id: \.element.id) { index, item in
                                ProtectedCommitmentRow(item: item)
                                if index < summary.commitments.count - 1 || summary.reserveProtected > 0.005 {
                                    Divider().overlay(.white.opacity(0.10))
                                }
                            }

                            if summary.reserveProtected > 0.005 {
                                HStack(spacing: 12) {
                                    Image(systemName: "shield.fill")
                                        .frame(width: 32, height: 32)
                                        .background(.white.opacity(0.08), in: Circle())
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Cash reserve")
                                            .font(.subheadline.weight(.semibold))
                                        Text("Keep untouched")
                                            .font(.caption)
                                            .foregroundStyle(.white.opacity(0.52))
                                    }
                                    Spacer()
                                    Text(Self.money.format(summary.reserveProtected))
                                        .font(.subheadline.weight(.bold))
                                        .monospacedDigit()
                                }
                                .padding(.vertical, 12)
                            }
                        }
                    }
                    .padding(16)
                    .background(.black.opacity(0.16), in: RoundedRectangle(cornerRadius: 18, style: .continuous))

                    Text("Rule: safe to spend is the most you can spend today while every goal is still payable on its date and your balance never drops below your floor. Money a future paycheck already covers is not held back.")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.52))
                        .lineSpacing(2)
                }
                .foregroundStyle(.white)
                .padding(20)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
        }
        .preferredColorScheme(.dark)
    }
}

private struct ProtectedBreakdownRow: View {
    let title: String
    let value: String
    var emphasised = false

    var body: some View {
        HStack {
            Text(title)
                .font(emphasised ? .subheadline.weight(.bold) : .subheadline)
                .foregroundStyle(emphasised ? .white : .white.opacity(0.70))
            Spacer()
            Text(value)
                .font(.subheadline.weight(emphasised ? .bold : .semibold))
                .monospacedDigit()
        }
        .padding(.vertical, 12)
    }
}

private struct ProtectedMetric: View {
    let title: String
    let value: String
    let symbol: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: symbol)
                .font(.caption2.weight(.bold))
                .foregroundStyle(.white.opacity(0.55))
            Text(value)
                .font(.title2.weight(.bold))
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
    }
}

private struct ProtectedCommitmentRow: View {
    let item: ProtectedCommitment

    private static let money = FloatingPointFormatStyle<Double>.Currency(code: "USD")
        .precision(.fractionLength(0))

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "target")
                .frame(width: 32, height: 32)
                .background(.white.opacity(0.08), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.subheadline.weight(.semibold))
                Text("Needed " + item.deadline.formatted(.dateTime.month(.abbreviated).day().year()))
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.52))
            }
            Spacer()
            Text(Self.money.format(item.amount))
                .font(.subheadline.weight(.bold))
                .monospacedDigit()
        }
        .padding(.vertical, 12)
    }
}

private struct ProtectedFundsSummary: Equatable {
    var balance: Double
    var protected: Double
    /// Spendable without breaking a hard requirement on any day of the plan.
    var available: Double
    /// The headline number: spendable while the safety buffer also survives. This is
    /// the conservative answer, which is what the product recommends by default.
    var safeToSpend: Double
    var expectedSafeToSpend: Double
    var optimisticSafeToSpend: Double
    var safetyBuffer: Double
    var futureCommitments: Double
    var runwayRequestedDate: Date?
    var runwayEndDate: Date?
    var commitments: [ProtectedCommitment]
    var reserveProtected: Double

    static let empty = ProtectedFundsSummary(
        balance: 0,
        protected: 0,
        available: 0,
        safeToSpend: 0,
        expectedSafeToSpend: 0,
        optimisticSafeToSpend: 0,
        safetyBuffer: 0,
        futureCommitments: 0,
        runwayRequestedDate: nil,
        runwayEndDate: nil,
        commitments: [],
        reserveProtected: 0
    )

    /// True when the money is not projected to last as long as the user asked.
    var runwayAtRisk: Bool {
        guard let requested = runwayRequestedDate, let end = runwayEndDate else { return false }
        return end <= requested
    }

    var reasonLine: String {
        if let first = commitments.first {
            let due = first.deadline.formatted(.dateTime.month(.abbreviated).day())
            let otherCount = commitments.count - 1 + (reserveProtected > 0.005 ? 1 : 0)
            if otherCount > 0 {
                return "\(first.name) · needed \(due) · +\(otherCount) more"
            }
            return "\(first.name) · needed \(due)"
        }
        if reserveProtected > 0.005 {
            return "Cash reserve · keep untouched"
        }
        return "Nothing protected yet"
    }
}

private struct ProtectedCommitment: Identifiable, Equatable {
    let id: UUID
    let name: String
    let amount: Double
    let deadline: Date
}

/// Read-only mirror of the product plan. ContentView remains the owner and writer;
/// this mirror lets the global balance banner stay in sync without creating a second
/// source of truth or changing the existing plan file format.
private struct ProtectedPlanSnapshot: Decodable {
    var goals: [ProtectedGoalSnapshot]
    var minimumCashReserve: Double?

    private enum CodingKeys: String, CodingKey {
        case goals, minimumCashReserve
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        goals = try container.decodeIfPresent([ProtectedGoalSnapshot].self, forKey: .goals) ?? []
        minimumCashReserve = try container.decodeIfPresent(Double.self, forKey: .minimumCashReserve)
    }

    static func load() -> ProtectedPlanSnapshot {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let url = support
            .appendingPathComponent("Finanzas2026", isDirectory: true)
            .appendingPathComponent("user-plan.json")
        guard let data = try? Data(contentsOf: url) else {
            return ProtectedPlanSnapshot(goals: [], minimumCashReserve: nil)
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode(ProtectedPlanSnapshot.self, from: data))
            ?? ProtectedPlanSnapshot(goals: [], minimumCashReserve: nil)
    }

    private init(goals: [ProtectedGoalSnapshot], minimumCashReserve: Double?) {
        self.goals = goals
        self.minimumCashReserve = minimumCashReserve
    }
}

private struct ProtectedGoalSnapshot: Decodable {
    let id: UUID
    let name: String
    let targetAmount: Int
    let saved: Int
    let targetDate: Date
    let isMandatory: Bool?
    let priority: GoalPriority?
    let flexibility: GoalFlexibility?
    let lifecycle: GoalLifecycleState?

    private enum CodingKeys: String, CodingKey {
        case id, name, targetAmount, saved, targetDate, isMandatory
        case priority, flexibility, lifecycleState
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? "Protected goal"
        targetAmount = try container.decodeIfPresent(Int.self, forKey: .targetAmount) ?? 0
        saved = try container.decodeIfPresent(Int.self, forKey: .saved) ?? 0
        targetDate = try container.decodeIfPresent(Date.self, forKey: .targetDate) ?? Date()
        isMandatory = try container.decodeIfPresent(Bool.self, forKey: .isMandatory)
        priority = try container.decodeIfPresent(GoalPriority.self, forKey: .priority)
        flexibility = try container.decodeIfPresent(GoalFlexibility.self, forKey: .flexibility)
        lifecycle = try container.decodeIfPresent(GoalLifecycleState.self, forKey: .lifecycleState)
    }

    var mustHappen: Bool {
        isMandatory == true || priority == .mandatory
    }

    var effectivePriority: GoalPriority {
        priority ?? (mustHappen ? .high : .medium)
    }

    var effectiveFlexibility: GoalFlexibility {
        flexibility ?? (mustHappen ? .fixed : .maxDelay(days: 30))
    }

    var lifecycleState: GoalLifecycleState {
        lifecycle ?? .active
    }
}
