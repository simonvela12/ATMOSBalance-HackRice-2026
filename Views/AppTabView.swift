import SwiftUI

struct AppTabView: View {
    var body: some View {
        TabView {
            HomeView(summary: MockData.summary)
                .tabItem { Label("Home", systemImage: "house.fill") }

            FinancialCalendarView(incomeEvents: MockData.incomeEvents, expenseEvents: MockData.expenseEvents)
                .tabItem { Label("Calendar", systemImage: "calendar") }

            PlansView(goals: MockData.goals)
                .tabItem { Label("Plans", systemImage: "target") }

            WhatIfView(summary: MockData.summary)
                .tabItem { Label("What If", systemImage: "slider.horizontal.3") }
        }
        .tint(.indigo)
    }
}
