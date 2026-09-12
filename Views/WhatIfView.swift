import SwiftUI

struct WhatIfView: View {
    let summary: FinancialSummary

    @State private var question = "Can I buy F1 tickets for $450 next month?"
    @State private var parsedScenario: WhatIfScenario?
    @State private var result: WhatIfResult?
    @State private var isAnalyzing = false
    @State private var errorMessage: String?

    private let parser: any WhatIfParsing = WhatIfParserFactory.makeDefault()

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

                    Text("If GEMINI_API_KEY is configured in Xcode, Gemini parses the question. Otherwise the app automatically uses an offline parser.")
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
                            Image(systemName: result.status == .safe ? "checkmark.circle.fill" : "clock.fill")
                                .foregroundStyle(result.status == .safe ? .green : .orange)
                            Text(result.status.rawValue)
                                .font(.headline)
                        }

                        LabeledContent("Safe before purchase") {
                            Text(result.safeToSpendBeforePurchase, format: .currency(code: "USD").precision(.fractionLength(0)))
                        }

                        LabeledContent("Remaining after purchase") {
                            Text(result.remainingAfterPurchase, format: .currency(code: "USD").precision(.fractionLength(0)))
                                .foregroundStyle(result.remainingAfterPurchase >= 0 ? .primary : .red)
                        }

                        if let recommendedDate = result.recommendedDate {
                            LabeledContent("Try again around") {
                                Text(recommendedDate, format: .dateTime.month(.abbreviated).day().year())
                            }
                        }

                        Text(result.explanation)
                            .foregroundStyle(.secondary)
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

        let input = question
        let parser = parser
        let summary = summary

        Task {
            do {
                let scenario = try await parser.parseScenario(from: input)
                let evaluation = WhatIfEvaluator(summary: summary).evaluate(scenario)

                await MainActor.run {
                    parsedScenario = scenario
                    result = evaluation
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
}
