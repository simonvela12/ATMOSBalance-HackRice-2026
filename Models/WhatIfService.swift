import Foundation

protocol WhatIfParsing: Sendable {
    func parseScenario(from text: String) async throws -> WhatIfScenario
}

enum WhatIfParserFactory {
    static func makeDefault() -> any WhatIfParsing {
        if let key = ProcessInfo.processInfo.environment["GEMINI_API_KEY"], !key.isEmpty {
            return GeminiWhatIfParser(apiKey: key)
        }
        return LocalWhatIfParser()
    }
}

/// Offline fallback. It keeps the demo usable even if Gemini is not configured or the network is unavailable.
struct LocalWhatIfParser: WhatIfParsing {
    private let engine = WhatIfEngine()

    func parseScenario(from text: String) async throws -> WhatIfScenario {
        try engine.parse(question: text)
    }
}

/// Lightweight Gemini REST client whose only job is to turn natural language into a structured scenario.
/// It does NOT decide whether the user can afford the purchase.
struct GeminiWhatIfParser: WhatIfParsing {
    enum ServiceError: LocalizedError {
        case invalidResponse
        case httpError(Int)
        case invalidScenario

        var errorDescription: String? {
            switch self {
            case .invalidResponse:
                return "Gemini returned an unreadable response."
            case .httpError(let code):
                return "Gemini request failed with HTTP \(code)."
            case .invalidScenario:
                return "I couldn't identify a valid purchase amount from that question."
            }
        }
    }

    private let apiKey: String
    private let session: URLSession
    private let model = "gemini-3.8-flash"

    init(apiKey: String, session: URLSession = .shared) {
        self.apiKey = apiKey
        self.session = session
    }

    func parseScenario(from text: String) async throws -> WhatIfScenario {
        let today = Self.dayFormatter.string(from: Date())
        let prompt = """
        Today is \(today).

        Extract a single hypothetical purchase from the user's finance question.
        Do not give financial advice and do not decide whether the purchase is affordable.
        Your only job is data extraction.

        User question: \(text)

        For intendedDate:
        - resolve relative dates such as today, next week, next month, or this weekend using today's date;
        - return an empty string when no date is specified.
        """

        guard let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent") else {
            throw ServiceError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        request.httpBody = try JSONSerialization.data(withJSONObject: Self.requestBody(prompt: prompt))

        let (data, response) = try await session.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw ServiceError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw ServiceError.httpError(http.statusCode)
        }

        let envelope = try JSONDecoder().decode(GeminiEnvelope.self, from: data)
        guard let jsonText = envelope.candidates.first?.content.parts.first?.text,
              let scenarioData = jsonText.data(using: .utf8) else {
            throw ServiceError.invalidResponse
        }

        let payload = try JSONDecoder().decode(ScenarioPayload.self, from: scenarioData)
        guard payload.amount > 0 else { throw ServiceError.invalidScenario }

        let date: Date?
        if payload.intendedDate.isEmpty {
            date = nil
        } else {
            date = Self.dayFormatter.date(from: payload.intendedDate)
        }

        return WhatIfScenario(
            type: .purchase,
            name: payload.name.isEmpty ? "Purchase" : payload.name,
            amount: payload.amount,
            intendedDate: date
        )
    }

    private static func requestBody(prompt: String) -> [String: Any] {
        [
            "contents": [
                ["parts": [["text": prompt]]]
            ],
            "generationConfig": [
                "responseMimeType": "application/json",
                "responseSchema": [
                    "type": "OBJECT",
                    "properties": [
                        "name": ["type": "STRING", "description": "Short name of the item or purchase"],
                        "amount": ["type": "NUMBER", "description": "Purchase price in USD"],
                        "intendedDate": ["type": "STRING", "description": "YYYY-MM-DD, or empty string if unspecified"]
                    ],
                    "required": ["name", "amount", "intendedDate"]
                ]
            ]
        ]
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
            let text: String
        }
    }

    private struct ScenarioPayload: Decodable {
        let name: String
        let amount: Double
        let intendedDate: String
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}

struct WhatIfEvaluator {
    let summary: FinancialSummary
    private let engine = WhatIfEngine()

    func evaluate(_ scenario: WhatIfScenario) -> WhatIfResult {
        engine.evaluate(scenario: scenario, summary: summary)
    }
}
