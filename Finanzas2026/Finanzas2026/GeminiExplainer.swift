import Foundation
import FinancialCore

/// Where the Gemini key lives.
///
/// Deliberately entered at runtime rather than compiled in: a key baked into the
/// app binary can be extracted from it, and committing one would share a single
/// quota across everyone with the repository.
///
/// Note this is UserDefaults, not the Keychain. It is per-app and does not leave
/// the device, but it is not encrypted at rest — fine for a sandbox key, not for
/// anything billable at scale.
enum GeminiSettings {
    private static let apiKeyDefault = "gemini.apiKey"
    private static let modelDefault = "gemini.model"

    /// Current fast tier. Model IDs move; this is overridable without a rebuild.
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

/// A decision the engine has already made, flattened for explanation.
///
/// Every number here comes from `FinancialCore`. The language model is given this
/// and asked only to put it into words — it never decides whether a purchase is
/// affordable.
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

    /// Everything below comes straight from the engine's structured result. The model
    /// is never given room to work out affordability for itself.
    struct GoalMove {
        let name: String
        let from: Date
        let to: Date
    }

    struct ScenarioOutcome {
        let name: String
        let summary: String
    }

    let recommendation: PurchaseRecommendation
    let safeToSpendBefore: Double
    let safeToSpendAfter: Double
    let runwayRequestedDate: Date?
    let runwayEndsBefore: Date?
    let runwayStillHolds: Bool
    let movedGoals: [GoalMove]
    let scenarios: [ScenarioOutcome]
    let uncertainIncome: (source: String, amount: Double, date: Date)?

    private static let money = FloatingPointFormatStyle<Double>.Currency(code: "USD")
        .precision(.fractionLength(0))

    private static func date(_ value: Date) -> String {
        value.formatted(.dateTime.month(.wide).day())
    }

    /// The facts handed to the model. Written as statements, not questions, so
    /// there is nothing for it to work out.
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

        lines.append("Recommendation: \(recommendation.rawValue)")
        lines.append(
            "Safe to spend today falls from \(Self.money.format(safeToSpendBefore)) to \(Self.money.format(safeToSpendAfter))."
        )

        if let runwayRequestedDate {
            if runwayStillHolds {
                lines.append("The user asked their money to last until \(Self.date(runwayRequestedDate)), and it still does.")
            } else if let runwayEndsBefore {
                lines.append("The user asked their money to last until \(Self.date(runwayRequestedDate)), but with this purchase it runs out on \(Self.date(runwayEndsBefore)).")
            }
        }

        for goal in movedGoals {
            lines.append("Goal '\(goal.name)' moves from \(Self.date(goal.from)) to \(Self.date(goal.to)).")
        }

        for scenario in scenarios {
            lines.append("Under the \(scenario.name) assumptions: \(scenario.summary).")
        }

        if let uncertainIncome {
            lines.append(
                "This only works if \(Self.money.format(uncertainIncome.amount)) from '\(uncertainIncome.source)' arrives on \(Self.date(uncertainIncome.date)); that money is not guaranteed."
            )
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
    case network(String)

    var errorDescription: String? {
        switch self {
        case .missingKey: return "Add a Gemini API key to get an explanation."
        case .invalidKey: return "That Gemini API key was rejected. Check it and try again."
        case .rateLimited: return "Gemini is rate limiting right now. Wait a moment and try again."
        case .server(let code): return "Gemini returned an error (\(code))."
        case .emptyResponse: return "Gemini returned no explanation."
        case .truncated: return "Gemini ran out of room before finishing. The figures above are unaffected."
        case .rejectedRequest: return "Gemini rejected the request."
        case .network(let message): return message
        }
    }
}

enum GeminiExplainer {

    /// Turns the engine's verdict into plain language.
    ///
    /// The model is explicitly told the decision is already made. If it is
    /// unreachable, the caller still has the engine's own numbers to show.
    static func explain(_ verdict: PurchaseVerdict) async throws -> String {
        guard let apiKey = GeminiSettings.apiKey else { throw GeminiError.missingKey }

        let prompt = """
        You are explaining a financial decision that has ALREADY been made by a \
        deterministic engine. Do not re-judge it, do not calculate anything, and do \
        not introduce any number that is not listed below.

        Write 2 to 3 short sentences, second person, plain language, no bullet \
        points, no headings, no emoji. Lead with what the verdict means for the \
        person. If a goal changes status, say which one and what changed. If there \
        is an earliest safe date, mention it. Do not give investment advice.

        FACTS
        \(verdict.factSheet)
        """

        var components = URLComponents(
            string: "https://generativelanguage.googleapis.com/v1beta/models/\(GeminiSettings.model):generateContent"
        )
        components?.queryItems = [URLQueryItem(name: "key", value: apiKey)]
        guard let url = components?.url else { throw GeminiError.network("Could not build the Gemini URL.") }

        // Current flash models reason before answering, and those thought tokens are
        // billed against maxOutputTokens. A tight cap gets spent on reasoning and the
        // visible answer is cut mid-sentence, so the budget is generous and thinking
        // is turned down.
        //
        // `thinkingConfig` is not accepted by every model generation. If the API
        // rejects the request because of it, the call is retried once without it
        // rather than leaving the user with no explanation at all.
        do {
            return try await send(prompt: prompt, url: url, disableThinking: true)
        } catch GeminiError.rejectedRequest {
            return try await send(prompt: prompt, url: url, disableThinking: false)
        }
    }

    private static func send(
        prompt: String,
        url: URL,
        disableThinking: Bool
    ) async throws -> String {
        var generationConfig: [String: Any] = [
            "temperature": 0.2,
            "maxOutputTokens": 2048
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

        // Never show a sentence that stops mid-number.
        if finishReason == "MAX_TOKENS" {
            throw GeminiError.truncated
        }
        guard !text.isEmpty else { throw GeminiError.emptyResponse }

        return text
    }
}
