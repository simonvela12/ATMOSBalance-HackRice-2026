import SwiftUI
import FinanceCore
import FinancialCore

/// Product shell only. Marc's `ContentView` remains the financial UI; this shell adds
/// the Context surface without maintaining a second forecast/goals/What-If implementation.
struct ProductRootView: View {
    @EnvironmentObject private var bankStore: BankAccountStore
    @AppStorage("finanzas.hasSeenWelcome") private var hasSeenWelcome = false
    @State private var selectedTab: ProductTab = .forecast
    @State private var contextRevision = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            ContentView()
                .id(contextRevision)
                .tag(ProductTab.forecast)
                .tabItem { Label("Forecast", systemImage: "cloud.sun.fill") }

            ContextView {
                contextRevision += 1
            }
            .tag(ProductTab.context)
            .tabItem { Label("Context", systemImage: "text.bubble.fill") }
        }
        .tint(.white)
        .preferredColorScheme(.dark)
        .fullScreenCover(isPresented: Binding(
            get: { !hasSeenWelcome },
            set: { if !$0 { hasSeenWelcome = true } }
        )) {
            WelcomeView {
                hasSeenWelcome = true
            }
        }
    }
}

private enum ProductTab: Hashable {
    case forecast
    case context
}

private struct WelcomeView: View {
    let onContinue: () -> Void

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.03, green: 0.08, blue: 0.15),
                    Color(red: 0.08, green: 0.20, blue: 0.29),
                    Color(red: 0.02, green: 0.05, blue: 0.10)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 24) {
                Spacer()

                Image(systemName: "cloud.sun.fill")
                    .font(.system(size: 62, weight: .medium))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, Color.yellow)

                VStack(alignment: .leading, spacing: 10) {
                    Text("FINANZAS")
                        .font(.caption.weight(.heavy))
                        .tracking(1.8)
                        .foregroundStyle(.white.opacity(0.62))
                    Text("Your financial weather, grounded in your actual accounts.")
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text("Link Nessie from the profile button, add the plans that matter to you, and use Context for facts your bank cannot know.")
                        .font(.body)
                        .foregroundStyle(.white.opacity(0.68))
                        .lineSpacing(4)
                }

                VStack(alignment: .leading, spacing: 14) {
                    WelcomeRow(icon: "building.columns.fill", text: "Balances and transactions come from the linked bank data.")
                    WelcomeRow(icon: "target", text: "Goals are evaluated by the shared financial engine.")
                    WelcomeRow(icon: "text.bubble.fill", text: "Context changes the plan only after you confirm it.")
                }

                Button(action: onContinue) {
                    Text("Continue")
                        .font(.headline)
                        .foregroundStyle(Color(red: 0.03, green: 0.08, blue: 0.15))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
                .padding(.top, 6)

                Spacer()
            }
            .padding(28)
        }
        .preferredColorScheme(.dark)
    }
}

private struct WelcomeRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .frame(width: 28)
                .foregroundStyle(.white.opacity(0.9))
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.68))
        }
    }
}

private struct ContextView: View {
    @EnvironmentObject private var bankStore: BankAccountStore
    let onConfirmed: () -> Void

    @State private var selectedID: String?
    @State private var note = ""
    @State private var parsed: QualitativeParseResult?
    @State private var statusMessage: String?

    private var items: [ContextItem] {
        var result = bankStore.transactions
            .filter { !$0.isPending && !$0.isTransfer }
            .sorted { $0.transactionDate > $1.transactionDate }
            .prefix(40)
            .map { transaction in
                ContextItem(transaction: transaction)
            }

        result.append(
            ContextItem(
                id: "general-cash-reserve",
                title: "Cash reserve",
                subtitle: "A personal rule the bank cannot infer",
                context: QualitativeNoteContext(subject: .general, label: "Cash reserve")
            )
        )
        return result
    }

    private var selected: ContextItem? {
        if let selectedID, let item = items.first(where: { $0.id == selectedID }) {
            return item
        }
        return items.first
    }

    private var profileForInterpretation: FinancialProfile {
        AppFinancialData.profile(
            currentCash: bankStore.isLinked ? bankStore.totalAvailableCash : nil,
            transactions: bankStore.transactions
        )
    }

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 0.03, green: 0.08, blue: 0.15),
                        Color(red: 0.06, green: 0.16, blue: 0.23),
                        Color(red: 0.02, green: 0.05, blue: 0.10)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        VStack(alignment: .leading, spacing: 7) {
                            Text("CONTEXT")
                                .font(.caption.weight(.bold))
                                .tracking(1.3)
                                .foregroundStyle(.white.opacity(0.58))
                            Text("Tell us what the bank can't know")
                                .font(.largeTitle.weight(.bold))
                                .foregroundStyle(.white)
                            Text("Choose a real bank transaction or a personal reserve rule. Nothing changes until you confirm.")
                                .font(.subheadline)
                                .foregroundStyle(.white.opacity(0.62))
                        }

                        if !bankStore.isLinked {
                            ContextCard {
                                Label("Link Nessie from the profile button in Forecast to ground Context in your account history.", systemImage: "link.circle")
                                    .foregroundStyle(.white.opacity(0.72))
                            }
                        }

                        if let selected {
                            ContextCard {
                                VStack(alignment: .leading, spacing: 10) {
                                    Picker("Item", selection: Binding(
                                        get: { selectedID ?? selected.id },
                                        set: { choose($0) }
                                    )) {
                                        ForEach(items) { item in
                                            Text(item.title).tag(item.id)
                                        }
                                    }
                                    .pickerStyle(.menu)
                                    .tint(.white)

                                    Text(selected.subtitle)
                                        .font(.caption)
                                        .foregroundStyle(.white.opacity(0.52))
                                }
                            }

                            ContextCard {
                                VStack(alignment: .leading, spacing: 12) {
                                    TextEditor(text: $note)
                                        .frame(minHeight: 110)
                                        .scrollContentBackground(.hidden)
                                        .padding(10)
                                        .background(.black.opacity(0.18), in: RoundedRectangle(cornerRadius: 14))
                                        .foregroundStyle(.white)

                                    Button("Interpret") {
                                        parsed = QualitativeNoteInterpreter.parse(
                                            note,
                                            context: selected.context,
                                            asOfDate: profileForInterpretation.asOfDate,
                                            calendar: AppFinancialData.calendar
                                        )
                                        statusMessage = nil
                                    }
                                    .buttonStyle(ContextPrimaryButtonStyle())
                                    .disabled(note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                                }
                            }

                            if let parsed {
                                ContextCard {
                                    VStack(alignment: .leading, spacing: 10) {
                                        if !parsed.recognizedSomething {
                                            Label("Nothing supported was recognized, so the plan will not change.", systemImage: "questionmark.circle")
                                                .foregroundStyle(.yellow)
                                        }

                                        ForEach(parsed.missingFields, id: \.rawValue) { field in
                                            Label(question(for: field), systemImage: "questionmark.circle.fill")
                                                .foregroundStyle(.yellow)
                                        }

                                        if !parsed.matchedRules.isEmpty {
                                            Text(parsed.matchedRules.map { $0.replacingOccurrences(of: "-", with: " ") }.joined(separator: " · "))
                                                .font(.caption)
                                                .foregroundStyle(.white.opacity(0.5))
                                        }

                                        if parsed.isActionable {
                                            Button("Confirm interpretation") {
                                                ContextPersistence.confirm(
                                                    note: note,
                                                    context: selected.context
                                                )
                                                statusMessage = "Context saved and applied to the financial profile."
                                                self.parsed = nil
                                                onConfirmed()
                                            }
                                            .buttonStyle(ContextPrimaryButtonStyle())
                                        }
                                    }
                                }
                            }
                        }

                        if let statusMessage {
                            ContextCard {
                                Label(statusMessage, systemImage: "checkmark.circle.fill")
                                    .foregroundStyle(.white.opacity(0.78))
                            }
                        }

                        if ContextPersistence.confirmedCount > 0 {
                            ContextCard {
                                HStack {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text("Confirmed context")
                                            .font(.subheadline.weight(.semibold))
                                        Text("\(ContextPersistence.confirmedCount) saved interpretation(s)")
                                            .font(.caption)
                                            .foregroundStyle(.white.opacity(0.52))
                                    }
                                    Spacer()
                                    Button("Clear", role: .destructive) {
                                        ContextPersistence.clear()
                                        statusMessage = "Confirmed Context cleared."
                                        parsed = nil
                                        onConfirmed()
                                    }
                                }
                            }
                        }

                        ContextCard {
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: "lock.shield.fill")
                                    .foregroundStyle(.white.opacity(0.82))
                                Text("Context is confirm-first. The local interpreter only applies supported financial meanings and asks for missing dates, cadence, or amounts instead of guessing.")
                                    .font(.caption)
                                    .foregroundStyle(.white.opacity(0.55))
                            }
                        }
                    }
                    .padding(20)
                    .padding(.bottom, 32)
                }
                .scrollIndicators(.hidden)
            }
            .navigationBarHidden(true)
        }
        .task {
            if selectedID == nil, let first = items.first {
                selectedID = first.id
            }
        }
        .onChange(of: items.map(\.id)) { _, ids in
            if let selectedID, !ids.contains(selectedID) {
                self.selectedID = ids.first
                note = ""
                parsed = nil
            } else if self.selectedID == nil {
                self.selectedID = ids.first
            }
        }
    }

    private func choose(_ id: String) {
        selectedID = id
        note = ""
        parsed = nil
        statusMessage = nil
    }

    private func question(for field: QualitativeMissingField) -> String {
        switch field {
        case .repaymentDate: return "When will the reimbursement arrive?"
        case .recurrenceCadence: return "How often does this repeat?"
        case .reserveAmount: return "How much cash should stay untouched?"
        }
    }
}

private struct ContextItem: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let context: QualitativeNoteContext

    init(
        id: String,
        title: String,
        subtitle: String,
        context: QualitativeNoteContext
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.context = context
    }

    init(transaction: FinanceCore.FinancialTransaction) {
        let title = AppFinancialData.label(transaction)
        let amount = Double(transaction.amountMinorUnits) / 100
        let direction = transaction.direction == .inflow ? "+" : "−"
        self.id = "transaction-\(transaction.id)"
        self.title = title
        self.subtitle = "\(direction)\(amount.formatted(.currency(code: "USD"))) · \(transaction.transactionDate.formatted(.dateTime.month(.abbreviated).day().year()))"
        self.context = QualitativeNoteContext(
            subject: transaction.direction == .inflow ? .income : .expense,
            referenceAmount: amount,
            referenceDate: AppFinancialData.day(transaction.transactionDate),
            label: title
        )
    }
}

private struct ContextCard<Content: View>: View {
    @ViewBuilder let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(17)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.white.opacity(0.065), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(.white.opacity(0.09), lineWidth: 0.75)
            }
    }
}

private struct ContextPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .foregroundStyle(.black)
            .background(.white.opacity(configuration.isPressed ? 0.78 : 1), in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct PersistedContextDecision: Codable {
    let key: String
    let note: String
    let subject: QualitativeNoteSubject
    let referenceAmount: Double?
    let referenceDate: Date?
    let label: String?

    var context: QualitativeNoteContext {
        QualitativeNoteContext(
            subject: subject,
            referenceAmount: referenceAmount,
            referenceDate: referenceDate,
            label: label
        )
    }
}

enum ContextPersistence {
    private static var fileURL: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support
            .appendingPathComponent("Finanzas2026", isDirectory: true)
            .appendingPathComponent("context-decisions.json")
    }

    static var confirmedCount: Int { load().count }

    static func confirm(note: String, context: QualitativeNoteContext) {
        let decision = PersistedContextDecision(
            key: key(for: context),
            note: note.trimmingCharacters(in: .whitespacesAndNewlines),
            subject: context.subject,
            referenceAmount: context.referenceAmount,
            referenceDate: context.referenceDate,
            label: context.label
        )
        var decisions = load()
        decisions.removeAll { $0.key == decision.key }
        decisions.append(decision)
        save(decisions)
    }

    static func applyConfirmedDecisions(to profile: FinancialProfile) -> FinancialProfile {
        var updated = profile
        let horizon = AppFinancialData.horizon(from: profile.asOfDate)

        for decision in load() {
            let parsed = QualitativeNoteInterpreter.parse(
                decision.note,
                context: decision.context,
                asOfDate: updated.asOfDate,
                calendar: AppFinancialData.calendar
            )
            guard parsed.isActionable else { continue }
            updated = QualitativeProfileUpdater.apply(
                parsed,
                to: updated,
                context: decision.context,
                through: horizon,
                reserveNote: "Confirmed context: \(decision.label ?? decision.subject.rawValue)",
                calendar: AppFinancialData.calendar
            ).profile
        }
        return updated
    }

    static func clear() {
        try? FileManager.default.removeItem(at: fileURL)
    }

    private static func key(for context: QualitativeNoteContext) -> String {
        [
            context.subject.rawValue,
            context.label ?? "",
            context.referenceDate.map { String($0.timeIntervalSince1970) } ?? "",
            context.referenceAmount.map { String($0) } ?? ""
        ].joined(separator: "|")
    }

    private static func load() -> [PersistedContextDecision] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([PersistedContextDecision].self, from: data)) ?? []
    }

    private static func save(_ decisions: [PersistedContextDecision]) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(decisions) else { return }
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? data.write(to: fileURL, options: .atomic)
    }
}
