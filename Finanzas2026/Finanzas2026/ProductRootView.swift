import SwiftUI
import FinancialCore

struct ProductRootView: View {
    @State private var profile = ProductDemo.makeProfile()

    var body: some View {
        TabView {
            HomeProductView(profile: profile)
                .tabItem { Label("Home", systemImage: "house.fill") }

            CalendarProductView(profile: profile)
                .tabItem { Label("Calendar", systemImage: "calendar") }

            PlansProductView(profile: profile)
                .tabItem { Label("Plans", systemImage: "target") }

            WhatIfProductView(profile: profile)
                .tabItem { Label("What If", systemImage: "slider.horizontal.3") }

            ContextProductView(profile: $profile)
                .tabItem { Label("Context", systemImage: "text.bubble.fill") }
        }
        .tint(.white)
        .preferredColorScheme(.dark)
    }
}

// MARK: - Home

private struct HomeProductView: View {
    let profile: FinancialProfile

    private var dashboard: FinancialDashboardSnapshot? {
        try? FinancialInsights.dashboard(
            profile: profile,
            through: ProductDemo.horizon,
            calendar: ProductDemo.calendar
        )
    }

    private var nextChange: ProductDemo.UpcomingChange? {
        ProductDemo.upcomingChanges(profile: profile).first
    }

    var body: some View {
        NavigationStack {
            ZStack {
                ProductBackground()

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        productHeader(
                            eyebrow: "YOUR PLAN",
                            title: "What can you safely do?",
                            subtitle: "Your bank balance matters. Your future obligations matter more."
                        )

                        if let dashboard {
                            safeToSpendCard(dashboard)

                            HStack(spacing: 12) {
                                metricCard(
                                    title: "This week",
                                    value: dashboard.recommendedWeeklySpendingLimit,
                                    caption: "recommended spending limit",
                                    symbol: "calendar.badge.checkmark"
                                )

                                metricCard(
                                    title: "Protected",
                                    value: max(0, profile.currentCash - dashboard.safeToSpendNow),
                                    caption: "not safe to treat as free cash",
                                    symbol: "shield.fill"
                                )
                            }

                            if let nextChange {
                                nextChangeCard(nextChange)
                            }

                            tightestPointCard(dashboard)

                            explanationCard(
                                icon: "checkmark.shield.fill",
                                title: "Why this number?",
                                text: "Safe to spend checks your whole cash path, including future bills, goals, normal spending, and your safety buffer. It is not just your current balance minus one expense."
                            )
                        } else {
                            unavailableCard("We couldn't calculate the plan from the current inputs yet.")
                        }
                    }
                    .padding(20)
                    .padding(.bottom, 24)
                }
            }
            .navigationBarHidden(true)
        }
    }

    private func safeToSpendCard(_ dashboard: FinancialDashboardSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("SAFE TO SPEND", systemImage: "checkmark.shield.fill")
                    .font(.caption.weight(.bold))
                    .tracking(1.1)
                    .foregroundStyle(.white.opacity(0.7))

                Spacer()

                statusPill(dashboard.horizonStatus)
            }

            Text(dashboard.safeToSpendNow, format: .currency(code: "USD").precision(.fractionLength(0)))
                .font(.system(size: 58, weight: .light, design: .rounded))
                .monospacedDigit()

            Text(homeStatusExplanation(dashboard.horizonStatus))
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.68))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
        .background(healthColor(dashboard.horizonStatus).opacity(0.16), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(healthColor(dashboard.horizonStatus).opacity(0.42), lineWidth: 1)
        }
    }

    private func metricCard(title: String, value: Double, caption: String, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: symbol)
                .font(.headline)
                .foregroundStyle(.white.opacity(0.8))

            Text(value, format: .currency(code: "USD").precision(.fractionLength(0)))
                .font(.title3.weight(.bold))
                .monospacedDigit()

            Text(title)
                .font(.subheadline.weight(.semibold))

            Text(caption)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.5))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: 142, alignment: .topLeading)
        .padding(16)
        .productCard()
    }

    private func nextChangeCard(_ change: ProductDemo.UpcomingChange) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("NEXT IMPORTANT CHANGE")
                .font(.caption.weight(.bold))
                .tracking(1.1)
                .foregroundStyle(.white.opacity(0.58))

            HStack(spacing: 12) {
                Image(systemName: change.amount >= 0 ? "arrow.down.left.circle.fill" : "arrow.up.right.circle.fill")
                    .font(.title2)
                    .foregroundStyle(change.amount >= 0 ? .green : .orange)

                VStack(alignment: .leading, spacing: 3) {
                    Text(change.label)
                        .font(.headline)
                    Text(change.date, format: .dateTime.month(.abbreviated).day())
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.55))
                }

                Spacer()

                Text(abs(change.amount), format: .currency(code: "USD").precision(.fractionLength(0)))
                    .font(.headline.weight(.bold))
                    .foregroundStyle(change.amount >= 0 ? .green : .orange)
            }
        }
        .padding(18)
        .productCard()
    }

    private func tightestPointCard(_ dashboard: FinancialDashboardSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("TIGHTEST POINT")
                .font(.caption.weight(.bold))
                .tracking(1.1)
                .foregroundStyle(.white.opacity(0.58))

            HStack(alignment: .firstTextBaseline) {
                Text(dashboard.tightestDate, format: .dateTime.month(.abbreviated).day())
                    .font(.title3.weight(.bold))
                Spacer()
                Text(dashboard.minimumRecommendedHeadroom, format: .currency(code: "USD").precision(.fractionLength(0)))
                    .font(.headline.weight(.bold))
                    .monospacedDigit()
            }

            Text("This is the point where your plan has the least room above the recommended buffer.")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.52))
        }
        .padding(18)
        .productCard()
    }
}

// MARK: - Calendar

private struct CalendarProductView: View {
    let profile: FinancialProfile

    private var timeline: [CashFlowPoint] {
        guard let end = ProductDemo.calendar.date(byAdding: .day, value: 20, to: profile.asOfDate) else { return [] }
        return (try? FinancialInsights.cashFlowTimeline(
            profile: profile,
            from: profile.asOfDate,
            through: min(end, ProductDemo.horizon),
            calendar: ProductDemo.calendar
        )) ?? []
    }

    var body: some View {
        NavigationStack {
            ZStack {
                ProductBackground()

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        productHeader(
                            eyebrow: "CALENDAR",
                            title: "Financial weather",
                            subtitle: "Weather describes the health of your plan — not whether spending itself is good or bad."
                        )

                        HStack(spacing: 10) {
                            legend(status: .safe, label: "Safe")
                            legend(status: .tight, label: "Tight")
                            legend(status: .notSafe, label: "Not safe")
                        }

                        VStack(spacing: 0) {
                            ForEach(Array(timeline.enumerated()), id: \.offset) { index, point in
                                HStack(spacing: 14) {
                                    VStack(spacing: 2) {
                                        Text(point.date, format: .dateTime.weekday(.abbreviated))
                                            .font(.caption2.weight(.bold))
                                            .foregroundStyle(.white.opacity(0.48))
                                        Text(point.date, format: .dateTime.day())
                                            .font(.headline)
                                    }
                                    .frame(width: 44)

                                    Image(systemName: healthSymbol(point.status))
                                        .font(.title2)
                                        .foregroundStyle(healthColor(point.status))
                                        .frame(width: 36)

                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(healthTitle(point.status))
                                            .font(.headline)
                                        Text("Projected cash")
                                            .font(.caption)
                                            .foregroundStyle(.white.opacity(0.48))
                                    }

                                    Spacer()

                                    Text(point.projectedCash, format: .currency(code: "USD").precision(.fractionLength(0)))
                                        .font(.headline.weight(.semibold))
                                        .monospacedDigit()
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 13)

                                if index < timeline.count - 1 {
                                    Divider().overlay(.white.opacity(0.08)).padding(.leading, 72)
                                }
                            }
                        }
                        .productCard()

                        explanationCard(
                            icon: "cloud.sun.fill",
                            title: "A big bill can still be a sunny day",
                            text: "Rent or tuition does not turn a day red just because the amount is large. A day becomes tight or not safe only when the payment pushes your plan through a financial boundary."
                        )
                    }
                    .padding(20)
                    .padding(.bottom, 24)
                }
            }
            .navigationBarHidden(true)
        }
    }

    private func legend(status: FinancialHealthStatus, label: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: healthSymbol(status))
                .foregroundStyle(healthColor(status))
            Text(label)
                .font(.caption.weight(.semibold))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(.white.opacity(0.07), in: Capsule())
    }
}

// MARK: - Plans

private struct PlansProductView: View {
    let profile: FinancialProfile

    private var assessments: [GoalPlanAssessment] {
        (try? FinancialInsights.assessAllGoals(
            profile: profile,
            planningHorizon: ProductDemo.horizon,
            calendar: ProductDemo.calendar
        )) ?? []
    }

    var body: some View {
        NavigationStack {
            ZStack {
                ProductBackground()

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        productHeader(
                            eyebrow: "PLANS",
                            title: "Protect what matters",
                            subtitle: "Goals are part of the same cash path as your spending — not a separate savings screen."
                        )

                        ForEach(assessments, id: \.goal.id) { assessment in
                            goalCard(assessment)
                        }

                        explanationCard(
                            icon: "target",
                            title: "Mandatory vs flexible",
                            text: "A mandatory goal is treated like a future obligation. A flexible goal stays visible, but the app can show when another choice makes it harder to reach."
                        )
                    }
                    .padding(20)
                    .padding(.bottom, 24)
                }
            }
            .navigationBarHidden(true)
        }
    }

    private func goalCard(_ assessment: GoalPlanAssessment) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(assessment.goal.name)
                        .font(.title3.weight(.bold))
                    Text("Due \(assessment.effectiveDeadline.formatted(.dateTime.month(.abbreviated).day()))")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.55))
                }

                Spacer()
                statusPill(assessment.status)
            }

            HStack(alignment: .firstTextBaseline) {
                Text(assessment.remainingAmount, format: .currency(code: "USD").precision(.fractionLength(0)))
                    .font(.title2.weight(.bold))
                    .monospacedDigit()
                Text("remaining")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.5))
            }

            Text(assessment.includedInBaseline
                 ? "Protected in your baseline plan."
                 : "Flexible: the app will show trade-offs before another choice harms it.")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.56))
        }
        .padding(18)
        .background(healthColor(assessment.status).opacity(0.12), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(healthColor(assessment.status).opacity(0.3), lineWidth: 1)
        }
    }
}

// MARK: - What If

private struct WhatIfProductView: View {
    let profile: FinancialProfile
    @State private var purchaseAmount = 500.0

    private var analysis: PurchaseWhatIfAnalysis? {
        try? FinancialInsights.analyzePurchaseWhatIf(
            profile: profile,
            amount: purchaseAmount,
            purchaseDate: profile.asOfDate,
            planningHorizon: ProductDemo.horizon,
            calendar: ProductDemo.calendar
        )
    }

    var body: some View {
        NavigationStack {
            ZStack {
                ProductBackground()

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        productHeader(
                            eyebrow: "WHAT IF",
                            title: "What happens if I buy it?",
                            subtitle: "Test a choice without changing your plan."
                        )

                        VStack(alignment: .leading, spacing: 16) {
                            Text("PURCHASE")
                                .font(.caption.weight(.bold))
                                .tracking(1.1)
                                .foregroundStyle(.white.opacity(0.58))

                            Text(purchaseAmount, format: .currency(code: "USD").precision(.fractionLength(0)))
                                .font(.system(size: 50, weight: .light, design: .rounded))
                                .monospacedDigit()

                            Slider(value: $purchaseAmount, in: 0...1_500, step: 25)
                                .tint(.white)
                        }
                        .padding(20)
                        .productCard()

                        if let analysis {
                            purchaseResultCard(analysis)
                            goalImpactCard(analysis)
                        } else {
                            unavailableCard("This scenario could not be calculated from the current plan.")
                        }
                    }
                    .padding(20)
                    .padding(.bottom, 24)
                }
            }
            .navigationBarHidden(true)
        }
    }

    private func purchaseResultCard(_ analysis: PurchaseWhatIfAnalysis) -> some View {
        let status = analysis.purchaseAssessment.status
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("PURCHASE RESULT")
                    .font(.caption.weight(.bold))
                    .tracking(1.1)
                    .foregroundStyle(.white.opacity(0.58))
                Spacer()
                purchaseStatusPill(status)
            }

            Text(purchaseReasonText(analysis.purchaseExplanation.reason))
                .font(.headline)

            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Tightest date")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.5))
                    Text(analysis.purchaseExplanation.limitingDate, format: .dateTime.month(.abbreviated).day())
                        .font(.headline)
                }

                Spacer()

                if let recommended = analysis.purchaseExplanation.recommendedDate {
                    VStack(alignment: .trailing, spacing: 3) {
                        Text("Fully safe on")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.5))
                        Text(recommended, format: .dateTime.month(.abbreviated).day())
                            .font(.headline)
                    }
                }
            }
        }
        .padding(18)
        .background(purchaseStatusColor(status).opacity(0.14), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(purchaseStatusColor(status).opacity(0.34), lineWidth: 1)
        }
    }

    private func goalImpactCard(_ analysis: PurchaseWhatIfAnalysis) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("GOAL IMPACT")
                .font(.caption.weight(.bold))
                .tracking(1.1)
                .foregroundStyle(.white.opacity(0.58))

            if analysis.worsenedGoals.isEmpty {
                Label("No current goal gets worse in this scenario.", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.subheadline.weight(.semibold))
            } else {
                ForEach(analysis.worsenedGoals, id: \.goal.id) { impact in
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(impact.goal.name)
                                .font(.headline)
                            Text("\(healthTitle(impact.before.status)) → \(healthTitle(impact.after.status))")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(healthColor(impact.after.status))
                        }
                        Spacer()
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(healthColor(impact.after.status))
                    }
                }
            }

            Text("A purchase can be technically affordable and still make an important plan less comfortable. That trade-off is shown explicitly.")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.52))
        }
        .padding(18)
        .productCard()
    }
}

// MARK: - Context

private struct ContextProductView: View {
    @Binding var profile: FinancialProfile

    @State private var selectedItemID = ProductDemo.contextItems[0].id
    @State private var noteText = ProductDemo.contextItems[0].suggestedText
    @State private var interpretation: QualitativeParseResult?
    @State private var confirmationMessage: String?

    private var selectedItem: ProductDemo.ContextItem {
        ProductDemo.contextItems.first(where: { $0.id == selectedItemID }) ?? ProductDemo.contextItems[0]
    }

    var body: some View {
        NavigationStack {
            ZStack {
                ProductBackground()

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        productHeader(
                            eyebrow: "CONTEXT",
                            title: "Tell us what the bank can't know",
                            subtitle: "Use normal words. The app only applies rules it can explain back to you."
                        )

                        contextTargetCard
                        noteCard

                        if let interpretation {
                            interpretationCard(interpretation)
                        }

                        if let confirmationMessage {
                            Label(confirmationMessage, systemImage: "checkmark.circle.fill")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.green)
                                .padding(16)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .productCard()
                        }

                        explanationCard(
                            icon: "lock.shield.fill",
                            title: "No AI required",
                            text: "The interpreter recognizes a limited set of financial meanings, asks when something is missing, and shows its interpretation before changing your plan. Unknown sentences are not guessed."
                        )
                    }
                    .padding(20)
                    .padding(.bottom, 24)
                }
            }
            .navigationBarHidden(true)
            .onChange(of: selectedItemID) { _, newValue in
                guard let item = ProductDemo.contextItems.first(where: { $0.id == newValue }) else { return }
                noteText = item.suggestedText
                interpretation = nil
                confirmationMessage = nil
            }
        }
    }

    private var contextTargetCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("WHAT ARE YOU EXPLAINING?")
                .font(.caption.weight(.bold))
                .tracking(1.1)
                .foregroundStyle(.white.opacity(0.58))

            Picker("Context item", selection: $selectedItemID) {
                ForEach(ProductDemo.contextItems) { item in
                    Text(item.title).tag(item.id)
                }
            }
            .pickerStyle(.menu)
            .tint(.white)

            Divider().overlay(.white.opacity(0.1))

            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(selectedItem.title)
                        .font(.headline)
                    Text(selectedItem.subtitle)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.5))
                }

                Spacer()

                if let amount = selectedItem.amount {
                    Text(amount, format: .currency(code: "USD").precision(.fractionLength(0)))
                        .font(.headline.weight(.bold))
                }
            }
        }
        .padding(18)
        .productCard()
    }

    private var noteCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("IN YOUR WORDS")
                .font(.caption.weight(.bold))
                .tracking(1.1)
                .foregroundStyle(.white.opacity(0.58))

            TextEditor(text: $noteText)
                .frame(minHeight: 110)
                .scrollContentBackground(.hidden)
                .padding(10)
                .background(.black.opacity(0.16), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            Button {
                confirmationMessage = nil
                interpretation = QualitativeNoteInterpreter.parse(
                    noteText,
                    context: selectedItem.context,
                    asOfDate: profile.asOfDate,
                    calendar: ProductDemo.calendar
                )
            } label: {
                Label("Interpret", systemImage: "text.magnifyingglass")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .foregroundStyle(.black)
                    .background(.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(18)
        .productCard()
    }

    private func interpretationCard(_ result: QualitativeParseResult) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("WE UNDERSTOOD")
                .font(.caption.weight(.bold))
                .tracking(1.1)
                .foregroundStyle(.white.opacity(0.58))

            if !result.recognizedSomething {
                Label("We don't know what this means yet, so we won't change your plan.", systemImage: "questionmark.circle")
                    .font(.subheadline)
                    .foregroundStyle(.yellow)
            } else {
                ForEach(Array(result.directives.enumerated()), id: \.offset) { _, directive in
                    Label(humanMeaning(directive, item: selectedItem), systemImage: "checkmark.circle")
                        .font(.subheadline)
                }

                ForEach(result.missingFields, id: \.rawValue) { field in
                    Label(missingQuestion(field), systemImage: "questionmark.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.yellow)
                }
            }

            if result.isActionable {
                Button {
                    apply(result, to: selectedItem)
                } label: {
                    Text("Confirm and update my plan")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .foregroundStyle(.black)
                        .background(.green, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(18)
        .productCard()
    }

    private func apply(_ result: QualitativeParseResult, to item: ProductDemo.ContextItem) {
        var updated = profile

        for directive in result.directives {
            switch directive {
            case .setIncomeType(let type):
                if type == .oneTime {
                    updated.incomeEvents.removeAll { $0.source == item.title && $0.date > updated.asOfDate }
                }

            case .setIrregularIncomeConfidence(let confidence):
                updated.incomeEvents = updated.incomeEvents.map { event in
                    guard event.source == item.title else { return event }
                    return IncomeEvent(
                        id: event.id,
                        amount: event.amount,
                        date: event.date,
                        source: event.source,
                        type: .irregular,
                        confidence: confidence
                    )
                }

            case .setExpenseCommitted(let committed):
                updated.expenseEvents = updated.expenseEvents.map { event in
                    guard event.category == item.title else { return event }
                    return ExpenseEvent(
                        id: event.id,
                        amount: event.amount,
                        date: event.date,
                        category: event.category,
                        essential: event.essential,
                        committed: committed,
                        reimbursable: event.reimbursable,
                        extraordinary: event.extraordinary
                    )
                }

            case .setExpenseEssential(let essential):
                updated.expenseEvents = updated.expenseEvents.map { event in
                    guard event.category == item.title else { return event }
                    return ExpenseEvent(
                        id: event.id,
                        amount: event.amount,
                        date: event.date,
                        category: event.category,
                        essential: essential,
                        committed: event.committed,
                        reimbursable: event.reimbursable,
                        extraordinary: event.extraordinary
                    )
                }

            case .setGoalPriority(let priority):
                guard let goalID = item.goalID,
                      let index = updated.goals.firstIndex(where: { $0.id == goalID }) else { break }
                let goal = updated.goals[index]
                updated.goals[index] = Goal(
                    id: goal.id,
                    name: goal.name,
                    targetAmount: goal.targetAmount,
                    amountAlreadyPaid: goal.amountAlreadyPaid,
                    deadline: goal.deadline,
                    priority: priority
                )

            case .expectReimbursement, .setRecurrence, .setPersonalReserve:
                break
            }
        }

        if let reimbursement = QualitativeDirectiveMaterializer.reimbursementIncome(
            from: result,
            context: item.context
        ) {
            updated.incomeEvents.removeAll {
                $0.source == reimbursement.source && $0.date == reimbursement.date
            }
            updated.incomeEvents.append(reimbursement)
        }

        if item.kind == .income,
           let recurring = try? QualitativeDirectiveMaterializer.recurringIncomeEvents(
                from: result,
                context: item.context,
                asOfDate: updated.asOfDate,
                through: ProductDemo.horizon,
                calendar: ProductDemo.calendar
           ),
           !recurring.isEmpty {
            updated.incomeEvents.removeAll { $0.source == item.title && $0.date > updated.asOfDate }
            updated.incomeEvents.append(contentsOf: recurring)
        }

        if item.kind == .expense,
           let recurring = try? QualitativeDirectiveMaterializer.recurringExpenseEvents(
                from: result,
                context: item.context,
                asOfDate: updated.asOfDate,
                through: ProductDemo.horizon,
                essential: true,
                committed: true,
                calendar: ProductDemo.calendar
           ),
           !recurring.isEmpty {
            updated.expenseEvents.removeAll { $0.category == item.title && $0.date > updated.asOfDate }
            updated.expenseEvents.append(contentsOf: recurring)
        }

        let reserveNote = "Confirmed context: \(item.title)"
        let steps = QualitativeDirectiveMaterializer.reserveSteps(from: result, note: reserveNote)
        if !steps.isEmpty {
            updated.personalReserveSteps.removeAll { $0.note == reserveNote }
            updated.personalReserveSteps.append(contentsOf: steps)
        }

        profile = updated
        interpretation = nil
        confirmationMessage = "Plan updated. Home, Calendar, Plans, and What If now use this context."
    }
}

// MARK: - Demo data / integration seam

private enum ContextKind {
    case income
    case expense
    case goal
    case general

    var subject: QualitativeNoteSubject {
        switch self {
        case .income: return .income
        case .expense: return .expense
        case .goal: return .goal
        case .general: return .general
        }
    }
}

private enum ProductDemo {
    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    static func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    static let asOf = date(2026, 9, 12)
    static let horizon = date(2026, 11, 30)
    static let miamiGoalID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    static let tuitionGoalID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!

    struct ContextItem: Identifiable {
        let id: String
        let title: String
        let subtitle: String
        let kind: ContextKind
        let amount: Double?
        let referenceDate: Date?
        let suggestedText: String
        let goalID: UUID?

        var context: QualitativeNoteContext {
            QualitativeNoteContext(
                subject: kind.subject,
                referenceAmount: amount,
                referenceDate: referenceDate,
                label: title
            )
        }
    }

    static let contextItems: [ContextItem] = [
        ContextItem(
            id: "campus-job",
            title: "Campus job",
            subtitle: "+$650 deposit · Sep 6",
            kind: .income,
            amount: 650,
            referenceDate: date(2026, 9, 6),
            suggestedText: "I get this every two weeks.",
            goalID: nil
        ),
        ContextItem(
            id: "group-dinner",
            title: "Group dinner",
            subtitle: "-$180 · Sep 10",
            kind: .expense,
            amount: 180,
            referenceDate: date(2026, 9, 10),
            suggestedText: "They owe me for this and will pay me next Friday.",
            goalID: nil
        ),
        ContextItem(
            id: "subscription",
            title: "Streaming subscription",
            subtitle: "-$25 scheduled · Sep 30",
            kind: .expense,
            amount: 25,
            referenceDate: date(2026, 9, 30),
            suggestedText: "This is optional and I can cancel it.",
            goalID: nil
        ),
        ContextItem(
            id: "miami",
            title: "Miami",
            subtitle: "$900 goal · Oct 20",
            kind: .goal,
            amount: 900,
            referenceDate: date(2026, 10, 20),
            suggestedText: "This goal can wait if I really need it to.",
            goalID: miamiGoalID
        ),
        ContextItem(
            id: "reserve",
            title: "Cash reserve",
            subtitle: "Personal rule",
            kind: .general,
            amount: nil,
            referenceDate: nil,
            suggestedText: "I need to keep at least $500 untouched.",
            goalID: nil
        )
    ]

    static func makeProfile() -> FinancialProfile {
        FinancialProfile(
            currentCash: 3_200,
            asOfDate: asOf,
            personalReserveSteps: [
                PersonalReserveStep(
                    effectiveDate: asOf,
                    minimumCash: 500,
                    note: "Current personal reserve"
                )
            ],
            institutionalMinimums: [],
            incomeEvents: [],
            expenseEvents: [
                ExpenseEvent(
                    amount: 900,
                    date: date(2026, 9, 15),
                    category: "Rent",
                    essential: true,
                    committed: true
                ),
                ExpenseEvent(
                    amount: 80,
                    date: date(2026, 9, 18),
                    category: "Phone",
                    essential: true,
                    committed: true
                ),
                ExpenseEvent(
                    amount: 25,
                    date: date(2026, 9, 30),
                    category: "Streaming subscription",
                    essential: false,
                    committed: true
                )
            ],
            goals: [
                Goal(
                    id: tuitionGoalID,
                    name: "Tuition installment",
                    targetAmount: 350,
                    deadline: date(2026, 9, 28),
                    priority: .mandatory
                ),
                Goal(
                    id: miamiGoalID,
                    name: "Miami",
                    targetAmount: 900,
                    deadline: date(2026, 10, 20),
                    priority: .flexible
                )
            ],
            weeklySpendingHistory: [
                WeeklySpendingSample(weekStart: date(2026, 8, 3), totalVariableSpending: 220),
                WeeklySpendingSample(weekStart: date(2026, 8, 10), totalVariableSpending: 260),
                WeeklySpendingSample(weekStart: date(2026, 8, 17), totalVariableSpending: 245),
                WeeklySpendingSample(weekStart: date(2026, 8, 24), totalVariableSpending: 275),
                WeeklySpendingSample(weekStart: date(2026, 8, 31), totalVariableSpending: 230),
                WeeklySpendingSample(weekStart: date(2026, 9, 7), totalVariableSpending: 255)
            ],
            spendingPolicy: SpendingPolicy(
                lookbackWeeks: 6,
                bufferWeeks: 2,
                manualMinimumBuffer: 200
            )
        )
    }

    struct UpcomingChange {
        let date: Date
        let label: String
        let amount: Double
    }

    static func upcomingChanges(profile: FinancialProfile) -> [UpcomingChange] {
        let income = profile.incomeEvents
            .filter { $0.date > profile.asOfDate }
            .map { UpcomingChange(date: $0.date, label: $0.source, amount: $0.adjustedAmount) }

        let expenses = profile.expenseEvents
            .filter { $0.committed && $0.date > profile.asOfDate }
            .map { UpcomingChange(date: $0.date, label: $0.category, amount: -$0.amount) }

        let goals = profile.goals
            .filter { $0.priority == .mandatory && $0.deadline > profile.asOfDate && $0.remainingAmount > 0 }
            .map { UpcomingChange(date: $0.deadline, label: $0.name, amount: -$0.remainingAmount) }

        return (income + expenses + goals).sorted { $0.date < $1.date }
    }
}

// MARK: - Shared presentation

private struct ProductBackground: View {
    var body: some View {
        LinearGradient(
            colors: [
                Color(red: 0.04, green: 0.08, blue: 0.15),
                Color(red: 0.07, green: 0.16, blue: 0.24),
                Color(red: 0.03, green: 0.06, blue: 0.12)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }
}

private func productHeader(eyebrow: String, title: String, subtitle: String) -> some View {
    VStack(alignment: .leading, spacing: 7) {
        Text(eyebrow)
            .font(.caption.weight(.bold))
            .tracking(1.5)
            .foregroundStyle(.white.opacity(0.58))
        Text(title)
            .font(.largeTitle.weight(.bold))
        Text(subtitle)
            .font(.subheadline)
            .foregroundStyle(.white.opacity(0.6))
            .fixedSize(horizontal: false, vertical: true)
    }
    .foregroundStyle(.white)
    .padding(.top, 8)
}

private func explanationCard(icon: String, title: String, text: String) -> some View {
    HStack(alignment: .top, spacing: 12) {
        Image(systemName: icon)
            .font(.headline)
            .foregroundStyle(.white.opacity(0.8))
            .frame(width: 32, height: 32)
            .background(.white.opacity(0.08), in: Circle())

        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            Text(text)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.52))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
    .padding(16)
    .productCard()
}

private func unavailableCard(_ text: String) -> some View {
    Label(text, systemImage: "exclamationmark.triangle.fill")
        .font(.subheadline)
        .foregroundStyle(.yellow)
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .productCard()
}

private func statusPill(_ status: FinancialHealthStatus) -> some View {
    Label(healthTitle(status), systemImage: healthSymbol(status))
        .font(.caption.weight(.bold))
        .foregroundStyle(healthColor(status))
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(healthColor(status).opacity(0.13), in: Capsule())
}

private func purchaseStatusPill(_ status: PurchaseStatus) -> some View {
    Label(purchaseStatusTitle(status), systemImage: purchaseStatusSymbol(status))
        .font(.caption.weight(.bold))
        .foregroundStyle(purchaseStatusColor(status))
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(purchaseStatusColor(status).opacity(0.13), in: Capsule())
}

private func healthTitle(_ status: FinancialHealthStatus) -> String {
    switch status {
    case .safe: return "SAFE"
    case .tight: return "TIGHT"
    case .notSafe: return "NOT SAFE"
    }
}

private func healthSymbol(_ status: FinancialHealthStatus) -> String {
    switch status {
    case .safe: return "sun.max.fill"
    case .tight: return "cloud.sun.fill"
    case .notSafe: return "cloud.bolt.rain.fill"
    }
}

private func healthColor(_ status: FinancialHealthStatus) -> Color {
    switch status {
    case .safe: return .green
    case .tight: return .yellow
    case .notSafe: return .red
    }
}

private func homeStatusExplanation(_ status: FinancialHealthStatus) -> String {
    switch status {
    case .safe:
        return "Your current plan stays above the recommended safety buffer across the planning horizon."
    case .tight:
        return "Your plan stays above the hard minimum, but uses part of the safety buffer at its tightest point."
    case .notSafe:
        return "At least one future point falls below a protected minimum. The plan needs attention before extra spending."
    }
}

private func purchaseStatusTitle(_ status: PurchaseStatus) -> String {
    switch status {
    case .safe: return "SAFE"
    case .tight: return "TIGHT"
    case .notSafe: return "NOT SAFE"
    }
}

private func purchaseStatusSymbol(_ status: PurchaseStatus) -> String {
    switch status {
    case .safe: return "checkmark.circle.fill"
    case .tight: return "exclamationmark.circle.fill"
    case .notSafe: return "xmark.octagon.fill"
    }
}

private func purchaseStatusColor(_ status: PurchaseStatus) -> Color {
    switch status {
    case .safe: return .green
    case .tight: return .yellow
    case .notSafe: return .red
    }
}

private func purchaseReasonText(_ reason: PurchaseDecisionReason) -> String {
    switch reason {
    case .preservesRecommendedBuffer:
        return "You can make this purchase and still preserve the recommended buffer."
    case .usesSafetyBuffer:
        return "You can technically cover it, but this purchase uses part of your safety buffer."
    case .violatesPersonalReserve:
        return "This purchase would push your plan below the cash reserve you asked us to protect."
    case .violatesInstitutionalMinimum:
        return "This purchase would violate a required account minimum."
    case .violatesMultipleHardConstraints:
        return "This purchase would break more than one protected financial constraint."
    }
}

private func humanMeaning(_ directive: QualitativeDirective, item: ProductDemo.ContextItem) -> String {
    switch directive {
    case .setIncomeType(.recurring):
        return "Treat this income as recurring."
    case .setIncomeType(.irregular):
        return "Treat this income as irregular, not guaranteed."
    case .setIncomeType(.oneTime):
        return "Treat this as one-time income and do not project it again."
    case .setIrregularIncomeConfidence(let confidence):
        return "Use \(Int((confidence * 100).rounded()))% confidence for this irregular income."
    case .setExpenseCommitted(true):
        return "Keep this expense in the baseline plan."
    case .setExpenseCommitted(false):
        return "Do not treat this as a committed future expense."
    case .setExpenseEssential(true):
        return "Treat this expense as essential."
    case .setExpenseEssential(false):
        return "Treat this expense as non-essential."
    case .expectReimbursement(let date):
        let amount = item.amount ?? 0
        return "Expect a \(amount.formatted(.currency(code: "USD").precision(.fractionLength(0)))) reimbursement on \(date.formatted(.dateTime.month(.abbreviated).day()))."
    case .setRecurrence(let cadence, _):
        switch cadence {
        case .weekly: return "Repeat this every week."
        case .biweekly: return "Repeat this every two weeks."
        case .monthly: return "Repeat this every month."
        }
    case .setGoalPriority(.mandatory):
        return "Protect this goal as a required obligation."
    case .setGoalPriority(.flexible):
        return "Keep this goal flexible if another decision forces a trade-off."
    case .setPersonalReserve(let amount, let date):
        return "Keep at least \(amount.formatted(.currency(code: "USD").precision(.fractionLength(0)))) protected starting \(date.formatted(.dateTime.month(.abbreviated).day()))."
    }
}

private func missingQuestion(_ field: QualitativeMissingField) -> String {
    switch field {
    case .repaymentDate:
        return "When do you expect to be paid back?"
    case .recurrenceCadence:
        return "How often does this repeat?"
    case .reserveAmount:
        return "How much cash do you want to keep protected?"
    }
}

private extension View {
    func productCard() -> some View {
        self
            .background(.black.opacity(0.18), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(.white.opacity(0.12), lineWidth: 0.8)
            }
    }
}
