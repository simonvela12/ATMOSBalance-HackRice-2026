import Foundation

protocol WhatIfNarrating: Sendable {
    func explain(scenario: WhatIfScenario, result: WhatIfResult) async -> String
}

enum WhatIfNarratorFactory {
    static func makeDefault() -> any WhatIfNarrating {
        let local = LocalWhatIfNarrator()
        if let key = ProcessInfo.processInfo.environment["GEMINI_API_KEY"], !key.isEmpty {
            return FallbackWhatIfNarrator(
                primary: GeminiWhatIfNarrator(apiKey: key),
                fallback: local
            )
        }
        return local
    }
}

struct FallbackWhatIfNarrator: WhatIfNarrating {
    let primary: any WhatIfNarrating
    let fallback: any WhatIfNarrating

    func explain(scenario: WhatIfScenario, result: WhatIfResult) async -> String {
        let online = await primary.explain(scenario: scenario, result: result)
        if online.isEmpty {
            return await fallback.explain(scenario: scenario, result: result)
        }
        return online
    }
}

struct LocalWhatIfNarrator: WhatIfNarrating {
    func explain(scenario: WhatIfScenario, result: WhatIfResult) async -> String {
        let affected = result.goalImpacts.filter { $0.impactLevel != .unaffected }
        let protectedOrUnaffected = result.goalImpacts.filter { $0.impactLevel == .unaffected }

        var parts = [result.explanation]

        if let biggest = affected.max(by: { $0.delayDays < $1.delayDays }) {
            if biggest.delayDays > 0 {
                let months = max(1, Int(ceil(Double(biggest.delayDays) / 30.0)))
                parts.append("That would push your \(biggest.goalName) goal back by about \(months) month\(months == 1 ? "" : "s").")
            } else {
                parts.append("Your \(biggest.goalName) goal would be at risk.")
            }
        }

        let protectedNames = protectedOrUnaffected
            .filter { $0.explanation.lowercased().contains("protected") }
            .map(\.goalName)

        if !protectedNames.isEmpty {
            parts.append("\(protectedNames.joined(separator: " and ")) remain protected and on track.")
        }

        return parts.joined(separator: " ")
    }
}

struct GeminiWhatIfNarrator: WhatIfNarrating {
    private let apiKey: String
    private let session: URLSession
    private let model = "gemini-3.8-flash"

    init(apiKey: String, session: URLSession = .shared) {
        self.apiKey = apiKey
        self.session = session
    }

    func explain(scenario: WhatIfScenario, result: WhatIfResult) async -> String {
        guard let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent") else {
            return ""
        }

        let impacts = result.goalImpacts.map { impact in
            """
            - goal: \(impact.goalName)
              impact: \(impact.impactLevel.rawValue)
              delayDays: \(impact.delayDays)
              amountPulledFromGoal: \(impact.amountPulledFromGoal)
              originalTargetDate: \(Self.formatDay(impact.originalTargetDate))
              projectedTargetDate: \(Self.formatDay(impact.projectedTargetDate))
            """
        }.joined(separator: "\n")

        let prompt = """
        You are explaining a financial simulation result to a college student.

        IMPORTANT RULES:
        - Do not perform new financial calculations.
        - Do not invent balances, dates, delays, recommendations, or goal impacts.
        - Only use the structured result below.
        - Be concise, direct, and non-judgmental.
        - First state whether the purchase is SAFE, a TRADE-OFF, or should WAIT.
        - If a savings goal is delayed, name it and explain the delay in natural language.
        - If a goal is unaffected/protected, you may mention that briefly when useful.
        - Prefer explaining the consequence rather than telling the user what they must do.
        - Use at most 3 short sentences.

        Purchase: \(scenario.name)
        Purchase amount: \(scenario.amount)
        Status: \(result.status.rawValue)
        Safe-to-spend before purchase: \(result.safeToSpendBeforePurchase)
        Remaining safe cash after purchase: \(result.remainingAfterPurchase)
        Recommended date: \(result.recommendedDate.map(Self.formatDay) ?? "none")

        Goal impacts:
        \(impacts.isEmpty ? "none" : impacts)
        """

        let body: [String: Any] = [
            "contents": [
                ["parts": [["text": prompt]]]
            ],
            "generationConfig": [
                "temperature": 0.2,
                "maxOutputTokens": 160
            ]
        ]

        do {
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)

            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode) else {
                return ""
            }

            let envelope = try JSONDecoder().decode(GeminiEnvelope.self, from: data)
            return envelope.candidates.first?.content.parts.first?.text?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        } catch {
            return ""
        }
    }

    private static func formatDay(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private struct GeminiEnvelope: Decodable {
        let candidates: [Candidate]

        struct Candidate: Decodable {
            let content: Content
        }

        struct Content: Decodable {
            let parts: [Part]
        }

        struct Part: Decodable {
            let text: String?
        }
    }
}
