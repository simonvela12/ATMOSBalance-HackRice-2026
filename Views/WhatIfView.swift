import SwiftUI

struct WhatIfView: View {
    let summary: FinancialSummary
    let goals: [FinancialGoal]

    @State private var question = "Can I buy a new PC for $1500 now?"
    @State private var parsedScenario: WhatIfScenario?
    @State private var result: WhatIfResult?
    @State private var narrative: String?
    @State private var isAnalyzing = false
    @State private var errorMessage: String?

    private let parser: any WhatIfParsing = WhatIfParserFactory.makeDefault()
    private let narrator: any WhatIfNarrating = WhatIfNarratorFactory.makeDefault()

    var body: some View {
        NavigationStack {
            Form {
                Section("Ask a what-if question") {
                    TextField("Can I buy F1 tickets for $450?", text: $question, axis: .vertical)
                        .lineLimit(2...5)

                    Button {
                        analyze()
                    } label: {
                        if isAnalyzing {
                            HStack {
                                ProgressView()
                                Text("Analyzing…")
                            }
                        } else {
                            Label("Analyze", systemImage: "sparkles")
                        }
                    }
                    .disabled(question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isAnalyzing)

                    Text("Gemini extracts the scenario and explains the result when configured. The actual financial decision stays in the local engine, with offline fallbacks if the API is unavailable.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Current plan") {
                    LabeledContent("Safe through November") {
                        Text(summary.safeToSpendThroughNovember, format: .currency(code: "USD").precision(.fractionLength(0)))
                    }
                    LabeledContent("Protected cash") {
                        Text(summary.protectedCash, format: .currency(code: "USD").precision(.fractionLength(0)))
                    }
                    LabeledContent("Savings goals", value: "\(goals.count)")
                }

                if let scenario = parsedScenario {
                    Section("Parsed scenario") {
                        LabeledContent("Purchase", value: scenario.name)
                        LabeledContent("Amount") {
                            Text(scenario.amount, format: .currency(code: "USD").precision(.fractionLength(0)))
                        }

                        if let intendedDate = scenario.intendedDate {
                            LabeledContent("When") {
                                Text(intendedDate, format: .dateTime.month(.abbreviated).day().year())
                            }
                        } else {
                            LabeledContent("When", value: "Not specified")
                        }
                    }
                }

                if let result {
                    Section("Result") {
                        HStack(spacing: 8) {
                            Image(systemName: statusIcon(result.status))
                                .foregroundStyle(statusColor(result.status))
                            Text(result.status.rawValue)
                                .font(.headline)
                        }

                        LabeledContent("Safe before purchase") {
                            Text(result.safeToSpendBeforePurchase, format: .currency(code: "USD").precision(.fractionLength(0)))
                        }

                        LabeledContent("Remaining safe cash") {
                            Text(result.remainingAfterPurchase, format: .currency(code: "USD").precision(.fractionLength(0)))
                                .foregroundStyle(result.remainingAfterPurchase >= 0 ? Color.primary : Color.red)
                        }

                        if let recommendedDate = result.recommendedDate {
                            LabeledContent("Try again around") {
                                Text(recommendedDate, format: .dateTime.month(.abbreviated).day().year())
                            }
                        }

                        Text(narrative ?? result.explanation)
                            .foregroundStyle(.secondary)
                    }

                    if !result.goalImpacts.isEmpty {
                        Section("Goal impact") {
                            ForEach(result.goalImpacts) { impact in
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack {
                                        Image(systemName: impactIcon(impact.impactLevel))
                                            .foregroundStyle(impactColor(impact.impactLevel))
                                        Text(impact.goalName)
                                            .fontWeight(.semibold)
                                        Spacer()
                                        Text(impactLabel(impact))
                                            .font(.caption)
                                            .foregroundStyle(impactColor(impact.impactLevel))
                                    }

                                    if impact.delayDays > 0 {
                                        HStack {
                                            Text(impact.originalTargetDate, format: .dateTime.month(.abbreviated).day())
                                            Image(systemName: "arrow.right")
                                            Text(impact.projectedTargetDate, format: .dateTime.month(.abbreviated).day())
                                        }
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    }

                                    Text(impact.explanation)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.vertical, 3)
                            }
                        }
                    }
                }

                if let errorMessage {
                    Section("Error") {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("What If")
        }
    }

    private func analyze() {
        isAnalyzing = true
        errorMessage = nil
        parsedScenario = nil
        result = nil
        narrative = nil

        let input = question
        let parser = parser
        let narrator = narrator
        let summary = summary
        let goals = goals

        Task {
            do {
                let scenario = try await parser.parseScenario(from: input)
                let evaluation = WhatIfEvaluator(summary: summary, goals: goals).evaluate(scenario)
                let explanation = await narrator.explain(scenario: scenario, result: evaluation)

                await MainActor.run {
                    parsedScenario = scenario
                    result = evaluation
                    narrative = explanation
                    isAnalyzing = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isAnalyzing = false
                }
            }
        }
    }

    private func statusIcon(_ status: WhatIfResult.Status) -> String {
        switch status {
        case .safe: return "checkmark.circle.fill"
        case .tradeOff: return "arrow.triangle.branch"
        case .wait: return "clock.fill"
        }
    }

    private func statusColor(_ status: WhatIfResult.Status) -> Color {
        switch status {
        case .safe: return .green
        case .tradeOff: return .orange
        case .wait: return .red
        }
    }

    private func impactIcon(_ level: GoalImpact.ImpactLevel) -> String {
        switch level {
        case .unaffected: return "checkmark.circle"
        case .delayed: return "calendar.badge.clock"
        case .atRisk: return "exclamationmark.triangle"
        }
    }

    private func impactColor(_ level: GoalImpact.ImpactLevel) -> Color {
        switch level {
        case .unaffected: return .green
        case .delayed: return .orange
        case .atRisk: return .red
        }
    }

    private func impactLabel(_ impact: GoalImpact) -> String {
        switch impact.impactLevel {
        case .unaffected:
            return "On track"
        case .delayed:
            let months = max(1, Int(ceil(Double(impact.delayDays) / 30.0)))
            return "+\(months) mo"
        case .atRisk:
            return "At risk"
        }
    }
}
