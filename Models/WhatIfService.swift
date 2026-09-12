import Foundation

protocol WhatIfParsing {
    func parseScenario(from text: String) async throws -> WhatIfScenario
}

/// Temporary local parser used so the What-If flow works before an LLM API is connected.
/// Replace this with an LLM-backed implementation later without changing the UI.
struct MockWhatIfParser: WhatIfParsing {
    func parseScenario(from text: String) async throws -> WhatIfScenario {
        let amount = extractAmount(from: text) ?? 0
        let name = extractName(from: text)
        return WhatIfScenario(type: .purchase, name: name, amount: amount, intendedDate: nil)
    }

    private func extractAmount(from text: String) -> Double? {
        let pattern = #"\$?([0-9]+(?:\.[0-9]{1,2})?)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else { return nil }
        return Double(text[range])
    }

    private func extractName(from text: String) -> String {
        let cleaned = text
            .replacingOccurrences(of: "can i buy", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "can i afford", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "what if i buy", with: "", options: .caseInsensitive)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "Purchase" : cleaned
    }
}

struct MockWhatIfEvaluator {
    let safeToSpend: Double

    func evaluate(_ scenario: WhatIfScenario) -> WhatIfResult {
        let remaining = safeToSpend - scenario.amount
        if remaining >= 0 {
            return WhatIfResult(
                status: .safe,
                safeToSpendBeforePurchase: safeToSpend,
                remainingAfterPurchase: remaining,
                recommendedDate: nil,
                explanation: "This purchase fits inside your current safe-to-spend amount."
            )
        }

        return WhatIfResult(
            status: .wait,
            safeToSpendBeforePurchase: safeToSpend,
            remainingAfterPurchase: remaining,
            recommendedDate: nil,
            explanation: "This purchase is above your current safe-to-spend amount by \(abs(remaining).formatted(.currency(code: \"USD\")))."
        )
    }
}
