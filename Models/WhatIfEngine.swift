import Foundation

/// Temporary What-If engine used while the full FinancialEngine is being integrated.
/// The UI talks only to this type, so Lucas's final forecasting math can replace
/// the internals without rewriting the screen or the LLM parsing layer.
struct WhatIfEngine: Sendable {
    enum EngineError: LocalizedError, Equatable {
        case emptyQuestion
        case missingAmount

        var errorDescription: String? {
            switch self {
            case .emptyQuestion:
                return "Type a question first."
            case .missingAmount:
                return "Include a dollar amount, for example: Can I buy F1 tickets for $450?"
            }
        }
    }

    func parse(question: String, now: Date = Date(), calendar: Calendar = .current) throws -> WhatIfScenario {
        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw EngineError.emptyQuestion }

        guard let amount = extractAmount(from: trimmed) else {
            throw EngineError.missingAmount
        }

        let name = extractName(from: trimmed)
        let intendedDate = inferDate(from: trimmed, now: now, calendar: calendar)

        return WhatIfScenario(
            type: .purchase,
            name: name,
            amount: amount,
            intendedDate: intendedDate
        )
    }

    func evaluate(
        scenario: WhatIfScenario,
        summary: FinancialSummary,
        goals: [FinancialGoal] = [],
        calendar: Calendar = .current
    ) -> WhatIfResult {
        let available = max(0, summary.safeToSpendThroughNovember)
        let remaining = available - scenario.amount
        let shortfall = max(0, -remaining)

        let impacts = calculateGoalImpacts(
            shortfall: shortfall,
            goals: goals,
            calendar: calendar
        )

        let accessibleGoalFunds = goals
            .filter { !$0.isProtected }
            .reduce(0) { $0 + $1.currentSaved }

        let status: WhatIfResult.Status
        if shortfall == 0 {
            status = .safe
        } else if accessibleGoalFunds >= shortfall {
            status = .tradeOff
        } else {
            status = .wait
        }

        let recommendedDate: Date?
        if status == .wait {
            recommendedDate = calendar.date(byAdding: .day, value: 30, to: scenario.intendedDate ?? Date())
        } else {
            recommendedDate = nil
        }

        let explanation: String
        switch status {
        case .safe:
            explanation = "This fits inside your current safe-to-spend amount and leaves \(money(max(0, remaining))) of discretionary room without touching your savings goals."
        case .tradeOff:
            let delayed = impacts.filter { $0.impactLevel != .unaffected }
            if let biggest = delayed.max(by: { $0.delayDays < $1.delayDays }) {
                explanation = "You can make this purchase, but it uses money currently supporting your goals. The biggest projected impact is on \(biggest.goalName)."
            } else {
                explanation = "You can make this purchase, but it requires using money currently assigned to savings goals."
            }
        case .wait:
            let uncovered = max(0, shortfall - accessibleGoalFunds)
            explanation = "This purchase is beyond your current safe-to-spend amount, and even using unprotected goal savings would still leave about \(money(uncovered)) uncovered."
        }

        return WhatIfResult(
            status: status,
            safeToSpendBeforePurchase: available,
            remainingAfterPurchase: remaining,
            recommendedDate: recommendedDate,
            goalImpacts: impacts,
            explanation: explanation
        )
    }

    func analyze(
        question: String,
        summary: FinancialSummary,
        goals: [FinancialGoal] = [],
        now: Date = Date()
    ) throws -> (WhatIfScenario, WhatIfResult) {
        let scenario = try parse(question: question, now: now)
        return (scenario, evaluate(scenario: scenario, summary: summary, goals: goals))
    }

    /// Temporary goal-impact heuristic for the hackathon prototype.
    /// If a purchase exceeds safe-to-spend, the shortfall is allocated against
    /// unprotected goals starting with the lowest-priority goal. The delay is
    /// estimated from each goal's planned monthly contribution.
    /// Lucas's full engine should replace this heuristic later.
    private func calculateGoalImpacts(
        shortfall: Double,
        goals: [FinancialGoal],
        calendar: Calendar
    ) -> [GoalImpact] {
        guard !goals.isEmpty else { return [] }

        var amountStillNeeded = shortfall
        var impactsByGoalID: [UUID: GoalImpact] = [:]

        let sacrificeOrder = goals.sorted {
            if $0.isProtected != $1.isProtected {
                return !$0.isProtected && $1.isProtected
            }
            return $0.priority.rawValue > $1.priority.rawValue
        }

        for goal in sacrificeOrder {
            guard amountStillNeeded > 0, !goal.isProtected, goal.currentSaved > 0 else {
                impactsByGoalID[goal.id] = unaffectedImpact(for: goal)
                continue
            }

            let amountPulled = min(goal.currentSaved, amountStillNeeded)
            amountStillNeeded -= amountPulled

            if goal.plannedMonthlyContribution > 0 {
                let delayMonths = max(1, Int(ceil(amountPulled / goal.plannedMonthlyContribution)))
                let projectedDate = calendar.date(byAdding: .month, value: delayMonths, to: goal.targetDate) ?? goal.targetDate
                let delayDays = max(0, calendar.dateComponents([.day], from: goal.targetDate, to: projectedDate).day ?? 0)

                impactsByGoalID[goal.id] = GoalImpact(
                    goalID: goal.id,
                    goalName: goal.name,
                    impactLevel: .delayed,
                    originalTargetDate: goal.targetDate,
                    projectedTargetDate: projectedDate,
                    delayDays: delayDays,
                    amountPulledFromGoal: amountPulled,
                    explanation: "Using \(money(amountPulled)) from this goal is estimated to delay it by about \(delayMonths) month\(delayMonths == 1 ? "" : "s")."
                )
            } else {
                impactsByGoalID[goal.id] = GoalImpact(
                    goalID: goal.id,
                    goalName: goal.name,
                    impactLevel: .atRisk,
                    originalTargetDate: goal.targetDate,
                    projectedTargetDate: goal.targetDate,
                    delayDays: 0,
                    amountPulledFromGoal: amountPulled,
                    explanation: "This purchase would use \(money(amountPulled)) from this goal, and there is no contribution pace yet to estimate when it recovers."
                )
            }
        }

        return goals.map { goal in
            impactsByGoalID[goal.id] ?? unaffectedImpact(for: goal)
        }
    }

    private func unaffectedImpact(for goal: FinancialGoal) -> GoalImpact {
        GoalImpact(
            goalID: goal.id,
            goalName: goal.name,
            impactLevel: .unaffected,
            originalTargetDate: goal.targetDate,
            projectedTargetDate: goal.targetDate,
            delayDays: 0,
            amountPulledFromGoal: 0,
            explanation: goal.isProtected
                ? "This goal is protected and is not used to fund hypothetical purchases."
                : "This purchase does not currently affect this goal."
        )
    }

    private func extractAmount(from text: String) -> Double? {
        let patterns = [
            #"\$\s*([0-9]+(?:,[0-9]{3})*(?:\.[0-9]{1,2})?)"#,
            #"(?:for|costs?|spend|pay)\s+\$?\s*([0-9]+(?:,[0-9]{3})*(?:\.[0-9]{1,2})?)"#
        ]

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
            let range = NSRange(text.startIndex..., in: text)
            guard let match = regex.firstMatch(in: text, range: range),
                  match.numberOfRanges > 1,
                  let amountRange = Range(match.range(at: 1), in: text) else { continue }

            let raw = text[amountRange].replacingOccurrences(of: ",", with: "")
            if let value = Double(raw) { return value }
        }

        return nil
    }

    private func extractName(from text: String) -> String {
        let prefixes = ["can i buy ", "can i afford ", "what if i buy ", "what if i spend on ", "should i buy "]
        let lower = text.lowercased()
        var candidate = text

        for prefix in prefixes {
            if lower.hasPrefix(prefix) {
                candidate = String(text.dropFirst(prefix.count))
                break
            }
        }

        if let dollarIndex = candidate.firstIndex(of: "$") {
            candidate = String(candidate[..<dollarIndex])
        } else if let forRange = candidate.range(of: " for ", options: [.caseInsensitive]) {
            candidate = String(candidate[..<forRange.lowerBound])
        }

        let cleaned = candidate
            .replacingOccurrences(of: "?", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return cleaned.isEmpty ? "Purchase" : cleaned.capitalized
    }

    private func inferDate(from text: String, now: Date, calendar: Calendar) -> Date? {
        let lower = text.lowercased()

        if lower.contains("today") || lower.contains("now") {
            return now
        }
        if lower.contains("tomorrow") {
            return calendar.date(byAdding: .day, value: 1, to: now)
        }
        if lower.contains("next week") {
            return calendar.date(byAdding: .day, value: 7, to: now)
        }
        if lower.contains("next month") {
            return calendar.date(byAdding: .month, value: 1, to: now)
        }
        if lower.contains("this weekend") {
            let weekday = calendar.component(.weekday, from: now)
            let daysUntilSaturday = (7 - weekday + 7) % 7
            return calendar.date(byAdding: .day, value: daysUntilSaturday, to: now)
        }

        return nil
    }

    private func money(_ value: Double) -> String {
        value.formatted(.currency(code: "USD").precision(.fractionLength(0)))
    }
}
