import SwiftUI

struct WhatIfView: View {
    let summary: FinancialSummary

    @State private var question = "Can I buy F1 tickets for $450 next month?"
    @State private var parsedScenario: WhatIfScenario?
    @State private var result: WhatIfResult?
    @State private var isAnalyzing = false
    @State private var errorMessage: String?

    private let parser: WhatIfParsing = MockWhatIfParser()

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
                }

                Section("Current plan") {
                    LabeledContent("Safe through November") {
                        Text(summary.safeToSpendThroughNovember, format: .currency(code: "USD").precision(.fractionLength(0)))
                    }
                }

                if let scenario = parsedScenario {
                    Section("Parsed scenario") {
                        LabeledContent("Purchase", value: scenario.name)
                        LabeledContent("Amount") {
                            Text(scenario.amount, format: .currency(code: "USD"))
                        }
                    }
                }

                if let result {
                    Section("Result") {
                        HStack {
                            Image(systemName: result.status == .safe ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            Text(result.status.rawValue)
                                .font(.headline)
                        }

                        LabeledContent("Safe before purchase") {
                            Text(result.safeToSpendBeforePurchase, format: .currency(code: "USD"))
                        }

                        LabeledContent("Remaining after purchase") {
                            Text(result.remainingAfterPurchase, format: .currency(code: "USD"))
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

        Task {
            do {
                let scenario = try await parser.parseScenario(from: question)
                let evaluator = MockWhatIfEvaluator(safeToSpend: summary.safeToSpendThroughNovember)
                let evaluation = evaluator.evaluate(scenario)

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
