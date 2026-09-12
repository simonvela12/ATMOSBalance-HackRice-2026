import SwiftUI

struct PlansView: View {
    let goals: [FinancialGoal]

    var body: some View {
        NavigationStack {
            List(goals) { goal in
                HStack(spacing: 14) {
                    Image(systemName: "flag.checkered")
                        .foregroundStyle(.indigo)
                        .frame(width: 36, height: 36)
                        .background(.indigo.opacity(0.12), in: Circle())
                    VStack(alignment: .leading, spacing: 4) {
                        Text(goal.name).font(.headline)
                        Text(goal.targetDate, format: .dateTime.month(.abbreviated).day()).font(.subheadline).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(goal.targetAmount, format: .currency(code: "USD").precision(.fractionLength(0))).fontWeight(.semibold)
                }
                .padding(.vertical, 4)
            }
            .navigationTitle("Plans")
        }
    }
}
