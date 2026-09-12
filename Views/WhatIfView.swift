import SwiftUI

struct WhatIfView: View {
    let summary: FinancialSummary
    @State private var hypotheticalExpense = 250.0

    var body: some View {
        NavigationStack {
            Form {
                Section("Try a scenario") {
                    Text("Explore a future purchase without changing your plan.").foregroundStyle(.secondary)
                    Slider(value: $hypotheticalExpense, in: 0...2_000, step: 50)
                    LabeledContent("Hypothetical expense") {
                        Text(hypotheticalExpense, format: .currency(code: "USD").precision(.fractionLength(0)))
                    }
                }
                Section("Current plan") {
                    LabeledContent("Safe through November") {
                        Text(summary.safeToSpendThroughNovember, format: .currency(code: "USD").precision(.fractionLength(0)))
                    }
                    Text("Scenario results will connect to FinancialEngine when it is available.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("What If")
        }
    }
}
