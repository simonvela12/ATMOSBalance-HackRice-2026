import SwiftUI
import FinancialCore

/// Temporary iPhone smoke-test screen for validating FinancialCore inside the real iOS app.
///
/// Add this file to the app target (not the FinancialCore package target), navigate to the view,
/// and replace `sampleProfile()` with the app's normalized qualitative/banking data once the wiring is ready.
struct FinancialCoreDeviceSmokeTestView: View {
    @State private var output = "Tap Run FinancialCore"

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("FinancialCore Device Smoke Test")
                        .font(.title2.bold())

                    Text("Runs the same deterministic engine used by the package tests, but from the installed iPhone app.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Button("Run FinancialCore") {
                        runSmokeTest()
                    }
                    .buttonStyle(.borderedProminent)

                    Text(output)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                }
                .padding()
            }
            .navigationTitle("Math Smoke Test")
        }
    }

    private func runSmokeTest() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!

        func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
            calendar.date(from: DateComponents(year: year, month: month, day: day))!
        }

        let asOf = date(2026, 9, 12)
        let horizon = date(2026, 11, 30)
        let purchaseDate = date(2026, 9, 15)

        let profile = FinancialProfile(
            currentCash: 8000,
            asOfDate: asOf,
            personalReserveSteps: [
                PersonalReserveStep(
                    effectiveDate: asOf,
                    minimumCash: 7000,
                    note: "User-confirmed runway"
                )
            ],
            incomeEvents: [
                IncomeEvent(
                    amount: 1000,
                    date: date(2026, 11, 1),
                    source: "Expected income",
                    type: .recurring
                )
            ],
            expenseEvents: [
                ExpenseEvent(
                    amount: 500,
                    date: date(2026, 11, 15),
                    category: "Essential expenses",
                    essential: true,
                    committed: true
                )
            ],
            spendingPolicy: SpendingPolicy(
                lookbackWeeks: 6,
                bufferWeeks: 0,
                manualMinimumBuffer: 250
            )
        )

        do {
            let forecast = try FinancialEngine.forecast(
                profile: profile,
                targetDate: horizon,
                calendar: calendar
            )

            let dashboard = try FinancialInsights.dashboard(
                profile: profile,
                through: horizon,
                calendar: calendar
            )

            let whatIf = try FinancialInsights.assessAndExplainPurchase(
                profile: profile,
                amount: 450,
                purchaseDate: purchaseDate,
                planningHorizon: horizon,
                calendar: calendar
            )

            output = """
            ✅ FinancialCore ran on device

            Projected cash: $\(String(format: "%.2f", forecast.projectedCash))
            Target headroom: $\(String(format: "%.2f", forecast.recommendedHeadroom))
            Safe to spend now: $\(String(format: "%.2f", dashboard.safeToSpendNow))
            Current health: \(dashboard.currentStatus.rawValue)
            Horizon health: \(dashboard.horizonStatus.rawValue)
            $450 What-If: \(whatIf.assessment.status.rawValue)
            Reason: \(whatIf.explanation.reason.rawValue)
            """
        } catch {
            output = "❌ FinancialCore error: \(error)"
        }
    }
}

#Preview {
    FinancialCoreDeviceSmokeTestView()
}
