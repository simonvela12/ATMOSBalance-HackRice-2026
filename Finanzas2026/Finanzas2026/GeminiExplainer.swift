import Foundation
import FinancialCore

enum GeminiSettings {
    private static let apiKeyDefault = "gemini.apiKey"
    private static let modelDefault = "gemini.model"

    static let defaultModel = "gemini-3.5-flash"

    static var apiKey: String? {
        get {
            let value = UserDefaults.standard.string(forKey: apiKeyDefault)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return (value?.isEmpty == false) ? value : nil
        }
        set {
            let trimmed = newValue?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let trimmed, !trimmed.isEmpty {
                UserDefaults.standard.set(trimmed, forKey: apiKeyDefault)
            } else {
                UserDefaults.standard.removeObject(forKey: apiKeyDefault)
            }
        }
    }

    static var model: String {
        get { UserDefaults.standard.string(forKey: modelDefault) ?? defaultModel }
        set { UserDefaults.standard.set(newValue, forKey: modelDefault) }
    }
}

struct PurchaseVerdict {
    struct GoalChange {
        let name: String
        let before: String
        let after: String
    }

    let amount: Double
    let status: PurchaseStatus
    let reason: PurchaseDecisionReason
    let projectedCashBefore: Double
    let projectedCashAfter: Double
    let hardFloor: Double
    let recommendedFloor: Double
    let shortfallToHardFloor: Double
    let shortfallToRecommendedFloor: Double
    let limitingDate: Date
    let recommendedDate: Date?
    let worsenedGoals: [GoalChange]

    private static let money = FloatingPointFormatStyle<Double>.Currency(code: "USD")
        .precision(.fractionLength(0))

    private static func date(_ value: Date) -> String {
        value.formatted(.dateTime.month(.wide).day())
    }

    var factSheet: String {
        var lines: [String] = [
            "Purchase amount: \(Self.money.format(amount))",
            "Verdict: \(status.rawValue)",
            "Reason code: \(reason.rawValue)",
            "Projected cash on the tightest day without the purchase: \(Self.money.format(projectedCashBefore))",
            "Projected cash on the tightest day with the purchase: \(Self.money.format(projectedCashAfter))",
            "Hard floor (money that must not be crossed): \(Self.money.format(hardFloor))",
            "Recommended floor (hard floor plus safety buffer): \(Self.money.format(recommendedFloor))",
            "Tightest day: \(Self.date(limitingDate))"
        ]

        switch reason {
        case .violatesProtectedGoal:
            lines.append("The purchase would use money already protected for a must-happen goal.")
        case .violatesMultipleHardConstraints:
            lines.append("The purchase would cross more than one hard protection, which can include protected goals or cash minimums.")
        case .preservesRecommendedBuffer, .usesSafetyBuffer,
             .violatesPersonalReserve, .violatesInstitutionalMinimum:
            break
        }

        if shortfallToHardFloor > 0 {
            lines.append("Amount below the hard floor: \(Self.money.format(shortfallToHardFloor))")
        }
        if shortfallToRecommendedFloor > 0 {
            lines.append("Amount below the recommended floor: \(Self.money.format(shortfallToRecommendedFloor))")
        }
        if let recommendedDate {
            lines.append("Earliest date this becomes fully safe: \(Self.date(recommendedDate))")
        }
        if worsenedGoals.isEmpty {
            lines.append("No goal changes status because of this purchase.")
        } else {
            for goal in worsenedGoals {
                lines.append("Goal '\(goal.name)' moves from \(goal.before) to \(goal.after).")
            }
        }
        return lines.joined(separator: "\n")
    }
}

struct WhatIfVerdict {
    let analysis: WhatIfScenarioAnalysis

    private static let money = FloatingPointFormatStyle<Double>.Currency(code: "USD")
        .precision(.fractionLength(0))

    var factSheet: String {
        let baseline = analysis.baseline
        let projected = analysis.projected
        var lines: [String] = [
            "Scenario: \(analysis.scenario.title)",
            "Baseline financial health: \(baseline.horizonStatus.rawValue)",
            "Financial health after scenario: \(projected.horizonStatus.rawValue)",
            "Safe to spend before: \(Self.money.format(baseline.safeToSpendNow))",
            "Safe to spend after: \(Self.money.format(projected.safeToSpendNow))",
            "Safe-to-spend change: \(Self.money.format(analysis.safeToSpendChange))",
            "Recommended weekly spending before: \(Self.money.format(baseline.recommendedWeeklySpendingLimit))",
            "Recommended weekly spending after: \(Self.money.format(projected.recommendedWeeklySpendingLimit))",
            "Total hypothetical income through the horizon: \(Self.money.format(analysis.totalIncome))",
            "Total hypothetical expenses through the horizon: \(Self.money.format(analysis.totalExpenses))",
            "Tightest date after scenario: \(projected.tightestDate.formatted(.dateTime.month(.wide).day().year()))"
        ]

        for outcome in analysis.scenarioOutcomes {
            lines.append(
                "\(outcome.financialScenario.rawValue) profile: \(outcome.beforeStatus.rawValue) -> \(outcome.afterStatus.rawValue), safe-to-spend \(Self.money.format(outcome.safeToSpendBefore)) -> \(Self.money.format(outcome.safeToSpendAfter))."
            )
        }

        if analysis.worsenedSmartGoals.isEmpty {
            lines.append("No goal meaningfully worsens under this scenario.")
        } else {
            for impact in analysis.worsenedSmartGoals {
                var detail = "Goal '\(impact.goal.name)' moves from \(impact.statusBefore.rawValue) to \(impact.statusAfter.rawValue)"
                if impact.shortfallChange > 0.005 {
                    detail += ", adding \(Self.money.format(impact.shortfallChange)) of shortfall"
                }
                if let days = impact.projectedCompletionDateChangeInDays, days > 0, days < Int.max {
                    detail += ", and projected completion moves about \(days) days later"
                }
                lines.append(detail + ".")
            }
        }

        let movements = analysis.movements.prefix(12).map {
            "\($0.direction.rawValue) \(Self.money.format($0.amount)) on \($0.date.formatted(.dateTime.month(.abbreviated).day().year())) for \($0.label)"
        }
        if !movements.isEmpty {
            lines.append("Materialized scenario events: " + movements.joined(separator: "; "))
        }
        return lines.joined(separator: "\n")
    }
}

enum GeminiError: LocalizedError {
    case missingKey
    case invalidKey
    case rateLimited
    case server(Int)
    case emptyResponse
    case truncated
    case rejectedRequest
    case invalidScenario
    case network(String)

    var errorDescription: String? {
        switch self {
        case .missingKey: return "Add a Gemini API key to use AI What If."
        case .invalidKey: return "That Gemini API key was rejected. Check it and try again."
        case .rateLimited: return "Gemini is rate limiting right now. Try again shortly."
        case .server(let code): return "Gemini returned an error (\(code))."
        case .emptyResponse: return "Gemini returned no response."
        case .truncated: return "Gemini ran out of room before finishing."
        case .rejectedRequest: return "Gemini rejected the request."
        case .invalidScenario: return "Gemini could not turn that into a complete financial scenario. Include an amount and when it starts."
        case .network(let message): return message
        }
    }
}

private struct GeminiScenarioEnvelope: Codable {
    let title: String
    let changes: [GeminiScenarioChange]
}

private struct GeminiScenarioChange: Codable {
    let direction: String
    let amount: Double
    let startDate: String
    let label: String
    let essential: Bool?
    let confidence: Double?
    let recurrence: GeminiScenarioRecurrence?
}

private struct GeminiScenarioRecurrence: Codable {
    let every: Int
    let unit: String
    let endDate: String?
    let maxOccurrences: Int?
}

enum GeminiExplainer {
    static func explain(_ verdict: PurchaseVerdict) async throws -> String {
        let prompt = """
        You are explaining a financial decision that has ALREADY been made by a deterministic engine.
        Do not re-judge it, do not calculate anything, and do not introduce any number that is not listed below.

        Write 2 to 3 short sentences, second person, plain language, no bullet points, no headings, no emoji.
        Lead with what the verdict means for the person. If a goal changes status, say which one and what changed.
        If there is an earliest safe date, mention it. Do not give investment advice.

        FACTS
        \(verdict.factSheet)
        """
        return try await generate(prompt: prompt, temperature: 0.2)
    }

    /// Gemini is used here as an intent parser only. It converts natural language
    /// into a strict scenario schema; it does not decide affordability or calculate
    /// financial outcomes. Those are exclusively FinancialCore responsibilities.
    static func parseWhatIfScenario(
        _ text: String,
        asOfDate: Date,
        planningHorizon: Date,
        calendar: Calendar = AppFinancialData.calendar
    ) async throws -> WhatIfScenario {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"

        let prompt = """
        Convert the user's hypothetical financial scenario into JSON. Do NOT judge affordability and do NOT calculate outcomes.
        Today is \(formatter.string(from: asOfDate)). The planning horizon is \(formatter.string(from: planningHorizon)).

        Return ONLY valid JSON with this exact shape:
        {
          "title": "short scenario title",
          "changes": [
            {
              "direction": "expense" or "income",
              "amount": positive number,
              "startDate": "YYYY-MM-DD",
              "label": "short human label",
              "essential": true or false,
              "confidence": number from 0 to 1,
              "recurrence": null OR {
                "every": positive integer,
                "unit": "day" or "week" or "month" or "year",
                "endDate": "YYYY-MM-DD" or null,
                "maxOccurrences": positive integer or null
              }
            }
          ]
        }

        Rules:
        - Split compound scenarios into multiple changes. Example: a $6,000 car down payment plus $250/month becomes two expense changes.
        - Recurring changes must use recurrence; never multiply them into one lump sum.
        - If the user says a recurring item starts in a named month but gives no day, use day 1 of that month.
        - If no start date is stated for a one-time purchase, use today.
        - If no start date is stated for a recurring item, use today.
        - Keep indefinite recurring items running through the planning horizon by leaving endDate and maxOccurrences null.
        - Use confidence below 1 only for explicitly uncertain income (for example 'maybe I get a $500 bonus'). Expenses stay confidence 1.
        - Never invent a monetary amount. If any required amount is missing, return {"title":"Needs details","changes":[]}.
        - Do not include commentary, markdown, or code fences.

        USER SCENARIO
        \(text)
        """

        let raw = try await generate(prompt: prompt, temperature: 0.0)
        let cleaned = raw
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = cleaned.data(using: .utf8),
              let envelope = try? JSONDecoder().decode(GeminiScenarioEnvelope.self, from: data),
              !envelope.changes.isEmpty else {
            throw GeminiError.invalidScenario
        }

        let changes: [WhatIfCashFlowChange] = try envelope.changes.map { item in
            guard item.amount > 0,
                  let direction = WhatIfCashFlowDirection(rawValue: item.direction.lowercased()),
                  let start = formatter.date(from: item.startDate) else {
                throw GeminiError.invalidScenario
            }

            let recurrence: WhatIfRecurrence?
            if let rawRecurrence = item.recurrence {
                guard let unit = WhatIfRecurrenceUnit(rawValue: rawRecurrence.unit.lowercased()) else {
                    throw GeminiError.invalidScenario
                }
                let endDate = rawRecurrence.endDate.flatMap { formatter.date(from: $0) }
                recurrence = WhatIfRecurrence(
                    every: rawRecurrence.every,
                    unit: unit,
                    endDate: endDate,
                    maxOccurrences: rawRecurrence.maxOccurrences
                )
            } else {
                recurrence = nil
            }

            return WhatIfCashFlowChange(
                direction: direction,
                amount: item.amount,
                startDate: calendar.startOfDay(for: start),
                recurrence: recurrence,
                label: item.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "What-if change" : item.label,
                essential: item.essential ?? false,
                confidence: item.confidence ?? 1
            )
        }

        return WhatIfScenario(
            title: envelope.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "What-if scenario" : envelope.title,
            sourceText: text,
            changes: changes
        )
    }

    static func explain(_ verdict: WhatIfVerdict) async throws -> String {
        let prompt = """
        Explain a hypothetical financial scenario whose results have ALREADY been calculated by a deterministic engine.
        Never recalculate, override, or invent numbers. Base your answer only on the facts below.

        In 3 to 5 short sentences, second person, explain:
        1) whether the scenario fits the user's broader financial profile, not merely today's balance;
        2) the most important cash-flow effect;
        3) any goal that becomes meaningfully harder;
        4) whether the conclusion changes materially in the conservative profile.
        If the scenario is unsafe, suggest a safer structural alternative using only facts already present (for example wait, reduce the amount, or avoid the recurring commitment) without inventing a dollar target.
        No headings, bullets, emoji, investment advice, or new figures.

        FACTS
        \(verdict.factSheet)
        """
        return try await generate(prompt: prompt, temperature: 0.2)
    }

    private static func generate(prompt: String, temperature: Double) async throws -> String {
        guard let apiKey = GeminiSettings.apiKey else { throw GeminiError.missingKey }

        var components = URLComponents(
            string: "https://generativelanguage.googleapis.com/v1beta/models/\(GeminiSettings.model):generateContent"
        )
        components?.queryItems = [URLQueryItem(name: "key", value: apiKey)]
        guard let url = components?.url else { throw GeminiError.network("Could not build the Gemini URL.") }

        do {
            return try await send(prompt: prompt, url: url, temperature: temperature, disableThinking: true)
        } catch GeminiError.rejectedRequest {
            return try await send(prompt: prompt, url: url, temperature: temperature, disableThinking: false)
        }
    }

    private static func send(
        prompt: String,
        url: URL,
        temperature: Double,
        disableThinking: Bool
    ) async throws -> String {
        var generationConfig: [String: Any] = [
            "temperature": temperature,
            "maxOutputTokens": 4096
        ]
        if disableThinking {
            generationConfig["thinkingConfig"] = ["thinkingBudget": 0]
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "contents": [["parts": [["text": prompt]]]],
            "generationConfig": generationConfig
        ])

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw GeminiError.network(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw GeminiError.network("Gemini gave a response that was not HTTP.")
        }

        switch http.statusCode {
        case 200..<300: break
        case 400: throw GeminiError.rejectedRequest
        case 401, 403: throw GeminiError.invalidKey
        case 429: throw GeminiError.rateLimited
        default: throw GeminiError.server(http.statusCode)
        }

        let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        let candidate = (root?["candidates"] as? [[String: Any]])?.first
        let finishReason = candidate?["finishReason"] as? String
        let text = ((candidate?["content"] as? [String: Any])?["parts"] as? [[String: Any]])?
            .compactMap { $0["text"] as? String }
            .joined()
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if finishReason == "MAX_TOKENS" { throw GeminiError.truncated }
        guard !text.isEmpty else { throw GeminiError.emptyResponse }
        return text
    }
}
