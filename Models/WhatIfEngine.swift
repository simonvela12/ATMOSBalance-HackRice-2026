import Foundation

/// Temporary What-If engine used while the full FinancialEngine is being integrated.
/// The UI talks only to this type, so we can later swap the internals without rewriting the screen.
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

    func evaluate(scenario: WhatIfScenario, summary: FinancialSummary) -> WhatIfResult {
        // Temporary rule: use the November discretionary budget already exposed by FinancialSummary.
        // Lucas's FinancialEngine will replace this calculation later.
        let available = max(0, summary.safeToSpendThroughNovember)
        let remaining = available - scenario.amount
        let isSafe = remaining >= 0

        let recommendation: Date?
        if isSafe {
            recommendation = nil
        } else {
            recommendation = Calendar.current.date(byAdding: .day, value: 30, to: scenario.intendedDate ?? Date())
        }

        let explanation: String
        if isSafe {
            explanation = "This fits inside your current safe-to-spend amount and leaves \(money(remaining)) of discretionary room."
        } else {
            let shortfall = abs(remaining)
            explanation = "This is \(money(shortfall)) above your current safe-to-spend amount. Waiting protects the money already reserved for your plan."
        }

        return WhatIfResult(
            status: isSafe ? .safe : .wait,
            safeToSpendBeforePurchase: available,
            remainingAfterPurchase: remaining,
            recommendedDate: recommendation,
            explanation: explanation
        )
    }

    func analyze(question: String, summary: FinancialSummary, now: Date = Date()) throws -> (WhatIfScenario, WhatIfResult) {
        let scenario = try parse(question: question, now: now)
        return (scenario, evaluate(scenario: scenario, summary: summary))
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
