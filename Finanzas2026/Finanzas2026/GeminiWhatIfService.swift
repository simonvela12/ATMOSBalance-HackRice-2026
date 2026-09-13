import Foundation
import FinancialCore

enum GeminiWhatIfSettings {
    private static let keyName = "gemini.apiKey"
    private static let workingModelKey = "gemini.workingModel"
    private static let developmentAPIKey = "AQ.Ab8RN6K-285QUngGc_L_IVMeVKUqPHJDWFbcJuSqJ4Id-bfp9g"
    static let models = ["gemini-3.8-flash", "gemini-3.7-flash", "gemini-3.5-flash", "gemini-2.0-flash"]

    static var orderedModels: [String] {
        guard let saved = UserDefaults.standard.string(forKey: workingModelKey), models.contains(saved) else { return models }
        return [saved] + models.filter { $0 != saved }
    }

    static func rememberWorkingModel(_ model: String) {
        UserDefaults.standard.set(model, forKey: workingModelKey)
    }

    static var apiKey: String? {
        get {
            let value = UserDefaults.standard.string(forKey: keyName)?.trimmingCharacters(in: .whitespacesAndNewlines)
            return value?.isEmpty == false ? value : developmentAPIKey
        }
        set {
            let value = newValue?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let value, !value.isEmpty { UserDefaults.standard.set(value, forKey: keyName) }
            else { UserDefaults.standard.removeObject(forKey: keyName) }
        }
    }
}

enum GeminiWhatIfError: LocalizedError {
    case missingKey, invalidKey, rateLimited, serviceUnavailable, invalidScenario, emptyResponse, server(Int), network(String)

    var errorDescription: String? {
        switch self {
        case .missingKey: return "Add a Gemini API key to use natural-language scenarios."
        case .invalidKey: return "Gemini rejected that API key."
        case .rateLimited: return "Gemini is busy right now. Try again shortly."
        case .serviceUnavailable: return "Gemini is temporarily unavailable across its fallback models. Your financial calculation has not been changed; try Analyze again shortly."
        case .invalidScenario: return "Include each amount and when it starts so Gemini can understand the scenario."
        case .emptyResponse: return "Gemini returned an empty response."
        case .server(let code): return "Gemini returned an error (\(code))."
        case .network(let message): return message
        }
    }
}

private struct GeminiScenarioEnvelope: Decodable {
    let title: String
    let changes: [GeminiScenarioChange]
}

private struct GeminiScenarioChange: Decodable {
    let direction: String
    let amount: Double
    let startDate: String
    let label: String
    let essential: Bool?
    let confidence: Double?
    let recurrence: GeminiScenarioRecurrence?
}

private struct GeminiScenarioRecurrence: Decodable {
    let every: Int
    let unit: String
    let endDate: String?
    let maxOccurrences: Int?
}

struct GeminiAdviceSource: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let url: URL
}

struct GeminiWhatIfAdvice {
    let text: String
    let sources: [GeminiAdviceSource]
    let usedLiveSearch: Bool
}

private struct GeminiGeneratedResponse {
    let text: String
    let sources: [GeminiAdviceSource]
}

enum GeminiWhatIfService {
    static func interpret(_ text: String, asOfDate: Date, horizon: Date, calendar: Calendar = .current) async throws -> WhatIfScenario {
        let formatter = dayFormatter(calendar)
        let prompt = """
        Convert the user's hypothetical financial plan into structured JSON. You only interpret intent: do not judge affordability or calculate any financial result.
        Today is \(formatter.string(from: asOfDate)); the analysis horizon is \(formatter.string(from: horizon)).
        Return JSON only: {"title":"short title","changes":[{"direction":"expense|income","amount":100.00,"startDate":"YYYY-MM-DD","label":"short label","essential":false,"confidence":1.0,"recurrence":null OR {"every":1,"unit":"day|week|month|year","endDate":null,"maxOccurrences":null}}]}.
        Split compound plans into separate changes. Keep recurring items recurring; never multiply them into a lump sum. Use today when no start date is given. For a named month without a day use its first day. Only explicitly uncertain income may have confidence below 1. Never invent an amount; if one is missing, return an empty changes array.
        USER PLAN: \(text)
        """
        let raw = try await generate(prompt, temperature: 0).text
        let cleaned = raw.replacingOccurrences(of: "```json", with: "").replacingOccurrences(of: "```", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = cleaned.data(using: .utf8), let envelope = try? JSONDecoder().decode(GeminiScenarioEnvelope.self, from: data), !envelope.changes.isEmpty else { throw GeminiWhatIfError.invalidScenario }

        let changes = try envelope.changes.map { item -> WhatIfCashFlowChange in
            guard item.amount > 0,
                  let direction = WhatIfCashFlowDirection(rawValue: item.direction.lowercased()),
                  let start = formatter.date(from: item.startDate) else { throw GeminiWhatIfError.invalidScenario }
            let recurrence: WhatIfRecurrence?
            if let raw = item.recurrence {
                guard raw.every > 0, let unit = WhatIfRecurrenceUnit(rawValue: raw.unit.lowercased()) else { throw GeminiWhatIfError.invalidScenario }
                recurrence = WhatIfRecurrence(every: raw.every, unit: unit, endDate: raw.endDate.flatMap { formatter.date(from: $0) }, maxOccurrences: raw.maxOccurrences)
            } else { recurrence = nil }
            return WhatIfCashFlowChange(direction: direction, amount: item.amount, startDate: calendar.startOfDay(for: start), recurrence: recurrence, label: item.label.isEmpty ? "What-if change" : item.label, essential: item.essential ?? false, confidence: item.confidence ?? 1)
        }
        return WhatIfScenario(title: envelope.title.isEmpty ? "What-if scenario" : envelope.title, sourceText: text, changes: changes)
    }

    static func explain(_ analysis: WhatIfScenarioAnalysis) async throws -> GeminiWhatIfAdvice {
        let money = FloatingPointFormatStyle<Double>.Currency(code: "USD").precision(.fractionLength(0...2))
        var facts = [
            "Scenario: \(analysis.scenario.title)",
            "Health: \(analysis.baseline.horizonStatus.rawValue) to \(analysis.projected.horizonStatus.rawValue)",
            "Safe to spend: \(money.format(analysis.baseline.safeToSpendNow)) to \(money.format(analysis.projected.safeToSpendNow))",
            "Weekly spending limit: \(money.format(analysis.baseline.recommendedWeeklySpendingLimit)) to \(money.format(analysis.projected.recommendedWeeklySpendingLimit))",
            "Hypothetical income through horizon: \(money.format(analysis.totalIncome))",
            "Hypothetical expenses through horizon: \(money.format(analysis.totalExpenses))"
        ]
        facts += analysis.scenarioOutcomes.map { "\($0.financialScenario.rawValue): health \($0.beforeStatus.rawValue) to \($0.afterStatus.rawValue), safe to spend \(money.format($0.safeToSpendBefore)) to \(money.format($0.safeToSpendAfter))" }
        facts += analysis.smartGoalImpacts.map { impact in
            let timing = impact.projectedCompletionDateChangeInDays.map { $0 == Int.max ? "no projected completion" : "\($0) days later" } ?? "no ETA change"
            return "Goal \(impact.goal.name): \(impact.statusBefore.rawValue) to \(impact.statusAfter.rawValue), shortfall change \(money.format(impact.shortfallChange)), \(timing)"
        }
        facts.append("Deterministic maximum currently safe for an additional one-time discretionary purchase: \(money.format(analysis.baseline.safeToSpendNow))")
        if let original = analysis.scenario.sourceText { facts.append("User's original scenario: \(original)") }
        let prompt = """
        Turn results already calculated by a deterministic financial engine into genuinely useful next-step advice. Never recalculate, override, or independently decide affordability. The deterministic maximum safe purchase is a hard ceiling.

        Do not summarize the dashboard and do not simply repeat its numbers. Use at most one number when it is essential to the recommendation. Briefly infer the practical tradeoff, then give 2–3 concrete paths the person could consider: waiting for a discount, deciding whether the purchase is needed now, buying used or refurbished, choosing a lower tier or substitute, saving first, delaying the purchase, or reducing/cancelling another optional commitment. Tailor the suggestions to the item and the person's goal impact. Do not invent products, prices, discounts, dates, or links, and do not recommend financing or debt. Write 4–6 concise, conversational sentences with no heading or bullets.
        FACTS:
        \(facts.joined(separator: "\n"))
        """
        let response = try await generate(prompt, temperature: 0.2)
        return GeminiWhatIfAdvice(text: response.text, sources: [], usedLiveSearch: false)
    }

    private static func dayFormatter(_ calendar: Calendar) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }

    private static func generate(_ prompt: String, temperature: Double) async throws -> GeminiGeneratedResponse {
        guard let key = GeminiWhatIfSettings.apiKey else { throw GeminiWhatIfError.missingKey }
        var onlyUnavailableResponses = true
        let candidateModels = GeminiWhatIfSettings.orderedModels
        for (index, model) in candidateModels.enumerated() {
            var components = URLComponents(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent")
            components?.queryItems = [URLQueryItem(name: "key", value: key)]
            guard let url = components?.url else { continue }
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.timeoutInterval = 75
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            var payload: [String: Any] = ["contents": [["parts": [["text": prompt]]]], "generationConfig": ["temperature": temperature, "maxOutputTokens": 2048]]
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)

            for attempt in 0..<3 {
                let data: Data
                let response: URLResponse
                do {
                    (data, response) = try await URLSession.shared.data(for: request)
                } catch let error as URLError where error.code == .timedOut {
                    if attempt == 0 { continue }
                    break
                } catch {
                    throw GeminiWhatIfError.network(error.localizedDescription)
                }
                guard let http = response as? HTTPURLResponse else { throw GeminiWhatIfError.network("Gemini returned an invalid response.") }
                if http.statusCode == 404 { break }
                if http.statusCode == 503 {
                    if attempt == 0 { try? await Task.sleep(for: .milliseconds(700)) }
                    continue
                }
                onlyUnavailableResponses = false
                if http.statusCode == 401 || http.statusCode == 403 { throw GeminiWhatIfError.invalidKey }
                if http.statusCode == 429 {
                    if attempt < 2 {
                        let defaultWait = attempt == 0 ? 15.0 : 30.0
                        let retrySeconds = min(60, max(2, http.value(forHTTPHeaderField: "Retry-After").flatMap(Double.init) ?? defaultWait))
                        try? await Task.sleep(for: .seconds(retrySeconds))
                        continue
                    }
                    throw GeminiWhatIfError.rateLimited
                }
                guard (200..<300).contains(http.statusCode) else { throw GeminiWhatIfError.server(http.statusCode) }
                let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
                let candidate = (root?["candidates"] as? [[String: Any]])?.first
                let text = ((candidate?["content"] as? [String: Any])?["parts"] as? [[String: Any]])?.compactMap { $0["text"] as? String }.joined().trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                guard !text.isEmpty else { throw GeminiWhatIfError.emptyResponse }
                GeminiWhatIfSettings.rememberWorkingModel(model)
                let metadata = candidate?["groundingMetadata"] as? [String: Any]
                let chunks = metadata?["groundingChunks"] as? [[String: Any]] ?? []
                var seen = Set<String>()
                let sources = chunks.compactMap { chunk -> GeminiAdviceSource? in
                    guard let web = chunk["web"] as? [String: Any],
                          let rawURL = web["uri"] as? String,
                          let url = URL(string: rawURL),
                          seen.insert(rawURL).inserted else { return nil }
                    let rawTitle = (web["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                    return GeminiAdviceSource(title: rawTitle?.isEmpty == false ? rawTitle! : url.host ?? "Source", url: url)
                }
                return GeminiGeneratedResponse(text: text, sources: sources)
            }
            if index < candidateModels.count - 1 { continue }
        }
        if onlyUnavailableResponses { throw GeminiWhatIfError.serviceUnavailable }
        throw GeminiWhatIfError.rateLimited
    }
}
