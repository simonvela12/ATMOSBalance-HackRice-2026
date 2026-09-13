import SwiftUI
import FinancialCore

struct AdvancedWhatIfSheet: View {
    let profile: FinancialProfile?

    @State private var scenarioText = ""
    @State private var analysis: WhatIfScenarioAnalysis?
    @State private var explanation: String?
    @State private var errorMessage: String?
    @State private var isAnalyzing = false
    @State private var apiKey = GeminiSettings.apiKey ?? ""
    @State private var hasGeminiKey = GeminiSettings.apiKey != nil

    private static let money = FloatingPointFormatStyle<Double>.Currency(code: "USD")
        .precision(.fractionLength(0))

    private var accent: Color {
        guard let status = analysis?.projected.horizonStatus else { return .white }
        switch status {
        case .safe: return Color(red: 1.00, green: 0.83, blue: 0.35)
        case .tight: return Color(red: 0.54, green: 0.78, blue: 0.94)
        case .notSafe: return Color(red: 0.76, green: 0.79, blue: 1.00)
        }
    }

    private var headline: String {
        guard let status = analysis?.projected.horizonStatus else {
            return "Describe the future you want to test"
        }
        switch status {
        case .safe: return "This scenario fits your broader plan"
        case .tight: return "This works, but reduces your margin"
        case .notSafe: return "This scenario puts the plan at risk"
        }
    }

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

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    scenarioComposer

                    if !hasGeminiKey {
                        keyCard
                    }

                    if let errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(Color(red: 1.00, green: 0.83, blue: 0.35))
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(.black.opacity(0.18), in: RoundedRectangle(cornerRadius: 14))
                    }

                    if let analysis {
                        understoodCard(analysis)
                        impactCard(analysis)
                        profileSensitivityCard(analysis)
                        goalImpactCard(analysis)
                        explanationCard
                    } else if profile == nil {
                        Text("Connect your bank account first so What If can test scenarios against your actual cash path, spending history, goals and confirmed context.")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.62))
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                            .padding(24)
                    } else {
                        examples
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 30)
            }
            .scrollIndicators(.hidden)
        }
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 5) {
                Text("AI WHAT IF")
                    .font(.caption.weight(.bold))
                    .tracking(1.4)
                    .foregroundStyle(.white.opacity(0.58))
                Text(headline)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.white)
            }
            Spacer()
            Image(systemName: "wand.and.stars")
                .font(.system(size: 34, weight: .medium))
                .foregroundStyle(accent)
        }
        .padding(.top, 16)
    }

    private var scenarioComposer: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("SCENARIO")
                .font(.caption.weight(.bold))
                .tracking(1.1)
                .foregroundStyle(.white.opacity(0.58))

            TextEditor(text: $scenarioText)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 105)
                .padding(10)
                .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                .foregroundStyle(.white)
                .overlay(alignment: .topLeading) {
                    if scenarioText.isEmpty {
                        Text("What if I buy a car for $6,000 and start paying $250 every month in November?")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.36))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 18)
                            .allowsHitTesting(false)
                    }
                }

            Text("Gemini only interprets your scenario. The financial engine calculates the result from your full profile.")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.48))

            Button {
                analyze()
            } label: {
                HStack(spacing: 8) {
                    if isAnalyzing { ProgressView().tint(Color(red: 0.03, green: 0.08, blue: 0.15)) }
                    Text(isAnalyzing ? "Analyzing…" : "Run scenario")
                        .font(.headline)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .foregroundStyle(Color(red: 0.03, green: 0.08, blue: 0.15))
                .background(.white, in: RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
            .disabled(!canAnalyze)
            .opacity(canAnalyze ? 1 : 0.45)
        }
        .padding(16)
        .background(.black.opacity(0.18), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(0.12)))
    }

    private var keyCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("GEMINI KEY")
                .font(.caption.weight(.bold))
                .tracking(1.1)
                .foregroundStyle(.white.opacity(0.58))
            SecureField("Paste Gemini API key", text: $apiKey)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(12)
                .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
            Button("Save key") {
                GeminiSettings.apiKey = apiKey
                hasGeminiKey = GeminiSettings.apiKey != nil
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Color(red: 1.00, green: 0.83, blue: 0.35))
            .disabled(apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(16)
        .background(.black.opacity(0.18), in: RoundedRectangle(cornerRadius: 16))
    }

    private func understoodCard(_ analysis: WhatIfScenarioAnalysis) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("WHAT I UNDERSTOOD")
                .font(.caption.weight(.bold))
                .tracking(1.1)
                .foregroundStyle(.white.opacity(0.58))
            Text(analysis.scenario.title)
                .font(.headline)
                .foregroundStyle(.white)

            ForEach(Array(analysis.scenario.changes.enumerated()), id: \.element.id) { _, change in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: change.direction == .expense ? "arrow.up.right" : "arrow.down.left")
                        .foregroundStyle(change.direction == .expense ? Color(red: 0.68, green: 0.84, blue: 0.96) : Color(red: 1.00, green: 0.83, blue: 0.35))
                        .frame(width: 24)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(change.label)
                            .font(.subheadline.weight(.semibold))
                        Text(changeSummary(change))
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.52))
                    }
                    Spacer()
                    Text(Self.money.format(change.amount))
                        .font(.subheadline.weight(.bold))
                        .monospacedDigit()
                }
            }
        }
        .foregroundStyle(.white)
        .padding(16)
        .background(.black.opacity(0.18), in: RoundedRectangle(cornerRadius: 16))
    }

    private func impactCard(_ analysis: WhatIfScenarioAnalysis) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("PROFILE IMPACT")
                .font(.caption.weight(.bold))
                .tracking(1.1)
                .foregroundStyle(.white.opacity(0.58))

            metric("Financial weather", value: "\(healthTitle(analysis.baseline.horizonStatus)) → \(healthTitle(analysis.projected.horizonStatus))")
            Divider().overlay(.white.opacity(0.1))
            metric("Safe to spend", value: "\(Self.money.format(analysis.baseline.safeToSpendNow)) → \(Self.money.format(analysis.projected.safeToSpendNow))")
            Divider().overlay(.white.opacity(0.1))
            metric("Weekly spending limit", value: "\(Self.money.format(analysis.baseline.recommendedWeeklySpendingLimit)) → \(Self.money.format(analysis.projected.recommendedWeeklySpendingLimit))")
            Divider().overlay(.white.opacity(0.1))
            metric("Tightest date", value: analysis.projected.tightestDate.formatted(.dateTime.month(.abbreviated).day()))

            Text("This result already includes your current cash, recent spending behavior, safety buffer, confirmed income/expenses, protected reserves and goals.")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.48))
                .padding(.top, 3)
        }
        .padding(16)
        .background(.black.opacity(0.18), in: RoundedRectangle(cornerRadius: 16))
    }

    private func profileSensitivityCard(_ analysis: WhatIfScenarioAnalysis) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("IF YOUR FINANCES RUN DIFFERENTLY")
                .font(.caption.weight(.bold))
                .tracking(1.1)
                .foregroundStyle(.white.opacity(0.58))

            ForEach(analysis.scenarioOutcomes, id: \.financialScenario.rawValue) { outcome in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(scenarioTitle(outcome.financialScenario))
                            .font(.subheadline.weight(.semibold))
                        Text("\(healthTitle(outcome.beforeStatus)) → \(healthTitle(outcome.afterStatus))")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.52))
                    }
                    Spacer()
                    Text(Self.money.format(outcome.safeToSpendAfter))
                        .font(.subheadline.weight(.bold))
                        .monospacedDigit()
                }
            }
        }
        .foregroundStyle(.white)
        .padding(16)
        .background(.black.opacity(0.18), in: RoundedRectangle(cornerRadius: 16))
    }

    private func goalImpactCard(_ analysis: WhatIfScenarioAnalysis) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("GOAL IMPACT")
                .font(.caption.weight(.bold))
                .tracking(1.1)
                .foregroundStyle(.white.opacity(0.58))

            if analysis.smartGoalImpacts.isEmpty {
                Text("No active goals to compare.")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.55))
            } else {
                ForEach(analysis.smartGoalImpacts, id: \.goal.id) { impact in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: impact.worsened ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                            .foregroundStyle(impact.worsened ? Color(red: 1.00, green: 0.83, blue: 0.35) : .white.opacity(0.38))
                            .frame(width: 22)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(impact.goal.name)
                                .font(.subheadline.weight(.semibold))
                            Text(goalImpactText(impact))
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.52))
                        }
                        Spacer()
                    }
                }
            }
        }
        .foregroundStyle(.white)
        .padding(16)
        .background(.black.opacity(0.18), in: RoundedRectangle(cornerRadius: 16))
    }

    private var explanationCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("WHAT THIS MEANS")
                .font(.caption.weight(.bold))
                .tracking(1.1)
                .foregroundStyle(.white.opacity(0.58))
            if let explanation {
                Text(explanation)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.88))
            } else {
                Text("The deterministic result above stands even if Gemini's explanation is unavailable.")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.52))
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.black.opacity(0.18), in: RoundedRectangle(cornerRadius: 16))
    }

    private var examples: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("TRY SOMETHING LIKE")
                .font(.caption.weight(.bold))
                .tracking(1.1)
                .foregroundStyle(.white.opacity(0.52))
            exampleButton("What if I buy a $1,200 laptop today?")
            exampleButton("What if my rent increases by $250 every month starting October?")
            exampleButton("What if I get a $500 monthly side income starting next month?")
            exampleButton("What if I put $4,000 down on a car and pay $300 per month starting November?")
        }
    }

    private func exampleButton(_ text: String) -> some View {
        Button {
            scenarioText = text
        } label: {
            Text(text)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.72))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }

    private var canAnalyze: Bool {
        profile != nil && hasGeminiKey && !scenarioText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isAnalyzing
    }

    private func analyze() {
        guard let profile else { return }
        let text = scenarioText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        isAnalyzing = true
        errorMessage = nil
        analysis = nil
        explanation = nil

        Task {
            do {
                let horizon = AppFinancialData.horizon(from: profile.asOfDate)
                let scenario = try await GeminiExplainer.parseWhatIfScenario(
                    text,
                    asOfDate: profile.asOfDate,
                    planningHorizon: horizon,
                    calendar: AppFinancialData.calendar
                )
                let result = try FinancialInsights.analyzeWhatIfScenario(
                    profile: profile,
                    scenario: scenario,
                    planningHorizon: horizon,
                    calendar: AppFinancialData.calendar
                )
                analysis = result
                do {
                    explanation = try await GeminiExplainer.explain(WhatIfVerdict(analysis: result))
                } catch {
                    explanation = nil
                }
            } catch {
                errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
            isAnalyzing = false
        }
    }

    @ViewBuilder
    private func metric(_ title: String, value: String) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(.white.opacity(0.62))
            Spacer()
            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .monospacedDigit()
                .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 5)
    }

    private func changeSummary(_ change: WhatIfCashFlowChange) -> String {
        let start = change.startDate.formatted(.dateTime.month(.abbreviated).day().year())
        guard let recurrence = change.recurrence else { return "One time · \(start)" }
        let unit = recurrence.every == 1 ? recurrence.unit.rawValue : "\(recurrence.unit.rawValue)s"
        return "Every \(recurrence.every) \(unit) · starts \(start)"
    }

    private func healthTitle(_ status: FinancialHealthStatus) -> String {
        switch status {
        case .safe: return "Safe"
        case .tight: return "Tight"
        case .notSafe: return "At risk"
        }
    }

    private func scenarioTitle(_ scenario: FinancialScenario) -> String {
        switch scenario {
        case .conservative: return "Conservative"
        case .expected: return "Expected"
        case .optimistic: return "Optimistic"
        }
    }

    private func goalImpactText(_ impact: WhatIfSmartGoalImpact) -> String {
        if let days = impact.projectedCompletionDateChangeInDays, days > 0, days < Int.max {
            return "Projected completion moves about \(days) days later."
        }
        if impact.shortfallChange > 0.005 {
            return "Adds \(Self.money.format(impact.shortfallChange)) to the projected shortfall."
        }
        if impact.statusBefore != impact.statusAfter {
            return "\(impact.statusBefore.rawValue.capitalized) → \(impact.statusAfter.rawValue.capitalized)"
        }
        return "No meaningful change to this goal."
    }
}
