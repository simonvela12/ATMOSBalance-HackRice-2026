import SwiftUI

struct HomeView: View {
    let summary: FinancialSummary

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    metricCard(title: "Current cash", amount: summary.currentCash, symbol: "dollarsign.circle.fill", color: .indigo)

                    HStack(spacing: 12) {
                        compactMetric(title: "Protected", amount: summary.protectedCash, color: .blue)
                        compactMetric(title: "This week", amount: summary.safeToSpendThisWeek, color: .green)
                    }

                    metricCard(title: "Safe to spend through November", amount: summary.safeToSpendThroughNovember, symbol: "checkmark.shield.fill", color: .green)
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Home")
        }
    }

    private func metricCard(title: String, amount: Double, symbol: String, color: Color) -> some View {
        HStack(spacing: 16) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(color)
                .frame(width: 44, height: 44)
                .background(color.opacity(0.12), in: Circle())
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.subheadline).foregroundStyle(.secondary)
                Text(amount, format: .currency(code: "USD").precision(.fractionLength(0))).font(.title2.bold())
            }
            Spacer()
        }
        .padding()
        .background(.background, in: RoundedRectangle(cornerRadius: 18))
    }

    private func compactMetric(title: String, amount: Double, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.subheadline).foregroundStyle(.secondary)
            Text(amount, format: .currency(code: "USD").precision(.fractionLength(0)))
                .font(.title3.bold())
                .foregroundStyle(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.background, in: RoundedRectangle(cornerRadius: 18))
    }
}
