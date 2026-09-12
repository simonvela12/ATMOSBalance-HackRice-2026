import SwiftUI

struct PlansView: View {
    let goals: [FinancialGoal]

    var body: some View {
        NavigationStack {
            List(goals) { goal in
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 12) {
                        Image(systemName: goal.isProtected ? "lock.shield.fill" : "target")
                            .foregroundStyle(goal.isProtected ? .green : .indigo)
                            .frame(width: 36, height: 36)
                            .background((goal.isProtected ? Color.green : Color.indigo).opacity(0.12), in: Circle())

                        VStack(alignment: .leading, spacing: 3) {
                            Text(goal.name)
                                .font(.headline)
                            Text("Priority: \(goal.priority.label)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Text(goal.targetAmount, format: .currency(code: "USD").precision(.fractionLength(0)))
                            .fontWeight(.semibold)
                    }

                    ProgressView(value: goal.progress)

                    HStack {
                        Text("\(goal.currentSaved.formatted(.currency(code: "USD").precision(.fractionLength(0)))) saved")
                        Spacer()
                        Text("\(Int(goal.progress * 100))%")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    HStack {
                        Label {
                            Text(goal.targetDate, format: .dateTime.month(.abbreviated).day())
                        } icon: {
                            Image(systemName: "calendar")
                        }

                        Spacer()

                        if goal.plannedMonthlyContribution > 0 {
                            Text("+\(goal.plannedMonthlyContribution.formatted(.currency(code: "USD").precision(.fractionLength(0))))/mo")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .padding(.vertical, 6)
            }
            .navigationTitle("Plans")
        }
    }
}
