import SwiftUI

struct FinancialCalendarView: View {
    let incomeEvents: [IncomeEvent]
    let expenseEvents: [ExpenseEvent]

    var body: some View {
        NavigationStack {
            List {
                Section("Money in") {
                    ForEach(incomeEvents) { event in
                        eventRow(name: event.name, amount: event.amount, date: event.date, color: .green)
                    }
                }
                Section("Money out") {
                    ForEach(expenseEvents) { event in
                        eventRow(name: event.name, amount: event.amount, date: event.date, color: .orange)
                    }
                }
            }
            .navigationTitle("Calendar")
        }
    }

    private func eventRow(name: String, amount: Double, date: Date, color: Color) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(name).font(.headline)
                Text(date, format: .dateTime.month(.abbreviated).day()).font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
            Text(amount, format: .currency(code: "USD").precision(.fractionLength(0)))
                .fontWeight(.semibold)
                .foregroundStyle(color)
        }
    }
}
