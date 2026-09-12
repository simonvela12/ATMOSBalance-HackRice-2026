import Foundation

public enum NaturalPlanKind: String, Codable, CaseIterable, Sendable {
    case income
    case expense
    case goal
    case reserve
}

public enum NaturalPlanMissingField: String, Codable, CaseIterable, Sendable {
    case kind
    case amount
    case date
}

public struct NaturalPlanDraft: Sendable {
    public let originalText: String
    public let kind: NaturalPlanKind?
    public let title: String
    public let amount: Double?
    public let date: Date?
    public let cadence: RecurrenceCadence?
    public let confidence: Double
    public let committed: Bool
    public let essential: Bool
    public let goalPriority: GoalPriority
    public let missingFields: [NaturalPlanMissingField]

    public init(
        originalText: String,
        kind: NaturalPlanKind?,
        title: String,
        amount: Double?,
        date: Date?,
        cadence: RecurrenceCadence?,
        confidence: Double,
        committed: Bool,
        essential: Bool,
        goalPriority: GoalPriority,
        missingFields: [NaturalPlanMissingField]
    ) {
        self.originalText = originalText
        self.kind = kind
        self.title = title
        self.amount = amount
        self.date = date
        self.cadence = cadence
        self.confidence = min(max(confidence, 0), 1)
        self.committed = committed
        self.essential = essential
        self.goalPriority = goalPriority
        self.missingFields = missingFields
    }
}

/// Deterministic, local interpreter for the small set of planning facts the product supports.
/// It never invents a missing amount, date, or event type. The UI can ask the user to fill those
/// fields before mutating the financial profile.
public enum NaturalLanguagePlanningInterpreter {
    public static func parse(
        _ text: String,
        asOfDate: Date,
        calendar: Calendar = .current
    ) -> NaturalPlanDraft {
        let normalized = normalize(text)
        let kind = detectKind(normalized)
        let amount = extractAmount(from: text)
        let date = kind == .reserve ? asOfDate : extractDate(from: normalized, asOfDate: asOfDate, calendar: calendar)
        let cadence = detectCadence(normalized)
        let confidence = detectConfidence(normalized, original: text)
        let committed = detectCommitted(normalized, kind: kind)
        let essential = detectEssential(normalized, kind: kind)
        let priority = detectGoalPriority(normalized)
        let title = detectTitle(normalized, original: text, kind: kind)

        var missing: [NaturalPlanMissingField] = []
        if kind == nil { missing.append(.kind) }
        if amount == nil { missing.append(.amount) }
        if kind != .reserve && date == nil { missing.append(.date) }

        return NaturalPlanDraft(
            originalText: text,
            kind: kind,
            title: title,
            amount: amount,
            date: date,
            cadence: cadence,
            confidence: confidence,
            committed: committed,
            essential: essential,
            goalPriority: priority,
            missingFields: missing
        )
    }

    private static func normalize(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func detectKind(_ text: String) -> NaturalPlanKind? {
        let reservePhrases = ["keep at least", "keep a reserve", "cash reserve", "untouched", "do not touch", "dont touch", "mantener al menos", "guardar al menos", "reserva", "sin tocar", "no tocar"]
        if reservePhrases.contains(where: text.contains) { return .reserve }

        let goalPhrases = ["save for", "saving for", "goal", "quiero ahorrar", "ahorrar para", "meta", "quiero juntar", "juntar para"]
        if goalPhrases.contains(where: text.contains) { return .goal }

        let reimbursementPhrases = ["pay me back", "paid back", "reimburse", "refund", "me deben", "me devuelve", "me devuelven", "reembolso", "devolver"]
        if reimbursementPhrases.contains(where: text.contains) { return .income }

        let incomePhrases = ["will receive", "will get", "get paid", "getting paid", "income", "deposit", "family sends", "family will send", "me van a mandar", "me va a mandar", "me mandan", "me van a pagar", "me va a pagar", "me pagan", "voy a cobrar", "cobro", "ingreso", "recibo", "recibire", "transferencia de mi familia"]
        if incomePhrases.contains(where: text.contains) { return .income }

        let expensePhrases = ["will pay", "have to pay", "need to pay", "bill", "expense", "spend", "buy", "purchase", "tengo que pagar", "voy a pagar", "debo pagar", "gastar", "gasto", "comprar", "compra", "cuesta"]
        if expensePhrases.contains(where: text.contains) { return .expense }

        return nil
    }

    private static func detectCadence(_ text: String) -> RecurrenceCadence? {
        let biweekly = ["every two weeks", "every 2 weeks", "biweekly", "cada dos semanas", "cada 2 semanas", "quincenal"]
        if biweekly.contains(where: text.contains) { return .biweekly }
        let weekly = ["every week", "weekly", "cada semana", "semanal"]
        if weekly.contains(where: text.contains) { return .weekly }
        let monthly = ["every month", "monthly", "cada mes", "mensual"]
        if monthly.contains(where: text.contains) { return .monthly }
        return nil
    }

    private static func detectConfidence(_ normalized: String, original: String) -> Double {
        if let percent = firstCapture(in: original, pattern: #"([0-9]{1,3}(?:\.[0-9]+)?)\s*%"#),
           let value = Double(percent) {
            return min(max(value / 100, 0), 1)
        }
        let possible = ["maybe", "possible", "possibly", "tal vez", "quizas", "quiza", "puede que"]
        if possible.contains(where: normalized.contains) { return 0.3 }
        let likely = ["likely", "probably", "probable", "probablemente", "muy posible"]
        if likely.contains(where: normalized.contains) { return 0.7 }
        return 1
    }

    private static func detectCommitted(_ text: String, kind: NaturalPlanKind?) -> Bool {
        guard kind == .expense else { return true }
        let optional = ["optional", "can cancel", "could cancel", "can skip", "puedo cancelar", "podria cancelar", "puedo evitar", "opcional"]
        if optional.contains(where: text.contains) { return false }
        return true
    }

    private static func detectEssential(_ text: String, kind: NaturalPlanKind?) -> Bool {
        guard kind == .expense else { return false }
        let nonessential = ["optional", "can cancel", "could cancel", "can skip", "puedo cancelar", "podria cancelar", "puedo evitar", "opcional", "no es necesario"]
        if nonessential.contains(where: text.contains) { return false }
        let essential = ["must pay", "have to pay", "need to pay", "tengo que pagar", "debo pagar", "obligatorio", "essential", "esencial"]
        return essential.contains(where: text.contains)
    }

    private static func detectGoalPriority(_ text: String) -> GoalPriority {
        let mandatory = ["must happen", "cannot postpone", "cant postpone", "mandatory", "tiene que pasar", "no puedo posponer", "obligatorio"]
        return mandatory.contains(where: text.contains) ? .mandatory : .flexible
    }

    private static func extractAmount(from text: String) -> Double? {
        if let captured = firstCapture(in: text, pattern: #"\$\s*([0-9]+(?:,[0-9]{3})*(?:\.[0-9]{1,2})?)"#) {
            return Double(captured.replacingOccurrences(of: ",", with: ""))
        }
        if let captured = firstCapture(in: text, pattern: #"([0-9]+(?:,[0-9]{3})*(?:\.[0-9]{1,2})?)\s*(?:usd|dollars?|dolares?)\b"#),
           let value = Double(captured.replacingOccurrences(of: ",", with: "")) {
            return value
        }

        let ns = text as NSString
        let regex = try? NSRegularExpression(pattern: #"\b([0-9]+(?:,[0-9]{3})*(?:\.[0-9]{1,2})?)\b"#, options: [])
        let matches = regex?.matches(in: text, range: NSRange(location: 0, length: ns.length)) ?? []
        for match in matches {
            guard match.numberOfRanges > 1 else { continue }
            let token = ns.substring(with: match.range(at: 1))
            let plain = token.replacingOccurrences(of: ",", with: "")
            guard let value = Double(plain) else { continue }
            if value >= 1900 && value <= 2200 { continue }
            let fullRange = match.range(at: 0)
            let suffixLocation = min(ns.length, fullRange.location + fullRange.length)
            let suffixLength = min(2, ns.length - suffixLocation)
            if suffixLength > 0, ns.substring(with: NSRange(location: suffixLocation, length: suffixLength)).contains("%") { continue }
            return value
        }
        return nil
    }

    private static func extractDate(from text: String, asOfDate: Date, calendar: Calendar) -> Date? {
        if text.contains("today") || text.contains("hoy") { return calendar.startOfDay(for: asOfDate) }
        if text.contains("tomorrow") || text.contains("manana") {
            return calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: asOfDate))
        }

        if let number = firstCapture(in: text, pattern: #"(?:in|en)\s+([0-9]+)\s+(?:days?|dias?)"#), let days = Int(number) {
            return calendar.date(byAdding: .day, value: days, to: calendar.startOfDay(for: asOfDate))
        }
        if let number = firstCapture(in: text, pattern: #"(?:in|en)\s+([0-9]+)\s+(?:weeks?|semanas?)"#), let weeks = Int(number) {
            return calendar.date(byAdding: .day, value: weeks * 7, to: calendar.startOfDay(for: asOfDate))
        }
        if text.contains("next week") || text.contains("semana que viene") || text.contains("proxima semana") {
            return calendar.date(byAdding: .day, value: 7, to: calendar.startOfDay(for: asOfDate))
        }
        if text.contains("next month") || text.contains("mes que viene") || text.contains("proximo mes") {
            return calendar.date(byAdding: .month, value: 1, to: calendar.startOfDay(for: asOfDate))
        }

        if let iso = firstCapture(in: text, pattern: #"\b(20[0-9]{2}-[0-9]{1,2}-[0-9]{1,2})\b"#) {
            let formatter = DateFormatter()
            formatter.calendar = calendar
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = calendar.timeZone
            formatter.dateFormat = "yyyy-M-d"
            if let date = formatter.date(from: iso) { return calendar.startOfDay(for: date) }
        }

        let months: [(Int, [String])] = [
            (1, ["january", "jan", "enero"]), (2, ["february", "feb", "febrero"]),
            (3, ["march", "mar", "marzo"]), (4, ["april", "apr", "abril"]),
            (5, ["may", "mayo"]), (6, ["june", "jun", "junio"]),
            (7, ["july", "jul", "julio"]), (8, ["august", "aug", "agosto"]),
            (9, ["september", "sep", "sept", "septiembre"]), (10, ["october", "oct", "octubre"]),
            (11, ["november", "nov", "noviembre"]), (12, ["december", "dec", "diciembre"])
        ]

        for (month, names) in months {
            for name in names where text.contains(name) {
                let escaped = NSRegularExpression.escapedPattern(for: name)
                let patterns = [
                    #"\b"# + escaped + #"\s+([0-9]{1,2})\b"#,
                    #"\b([0-9]{1,2})\s+(?:de\s+)?"# + escaped + #"\b"#
                ]
                for pattern in patterns {
                    if let dayText = firstCapture(in: text, pattern: pattern), let day = Int(dayText) {
                        var components = calendar.dateComponents([.year], from: asOfDate)
                        components.month = month
                        components.day = day
                        if let candidate = calendar.date(from: components) {
                            if candidate >= calendar.startOfDay(for: asOfDate) { return candidate }
                            components.year = (components.year ?? 0) + 1
                            return calendar.date(from: components)
                        }
                    }
                }
            }
        }

        let weekdays: [(Int, [String])] = [
            (1, ["sunday", "domingo"]), (2, ["monday", "lunes"]), (3, ["tuesday", "martes"]),
            (4, ["wednesday", "miercoles"]), (5, ["thursday", "jueves"]), (6, ["friday", "viernes"]),
            (7, ["saturday", "sabado"])
        ]
        let currentWeekday = calendar.component(.weekday, from: asOfDate)
        for (weekday, names) in weekdays where names.contains(where: text.contains) {
            var delta = (weekday - currentWeekday + 7) % 7
            if delta == 0 { delta = 7 }
            return calendar.date(byAdding: .day, value: delta, to: calendar.startOfDay(for: asOfDate))
        }

        return nil
    }

    private static func detectTitle(_ normalized: String, original: String, kind: NaturalPlanKind?) -> String {
        let defaults: [NaturalPlanKind: String] = [
            .income: "Expected income",
            .expense: "Planned expense",
            .goal: "Goal",
            .reserve: "Cash reserve"
        ]
        guard let kind else { return "Planned item" }

        if kind == .goal {
            let patterns = [#"(?:for|para)\s+([A-Za-zÀ-ÿ][A-Za-zÀ-ÿ0-9 '\-]{1,40})"#]
            for pattern in patterns {
                if let captured = firstCapture(in: original, pattern: pattern) {
                    let cleaned = captured
                        .replacingOccurrences(of: #"\s+(?:by|before|para|el)\s+.*$"#, with: "", options: .regularExpression)
                        .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
                    if !cleaned.isEmpty { return cleaned.capitalized }
                }
            }
        }

        if kind == .expense {
            let common: [(String, String)] = [("rent", "Rent"), ("renta", "Rent"), ("tuition", "Tuition"), ("matricula", "Tuition"), ("phone", "Phone"), ("telefono", "Phone"), ("books", "Books"), ("libros", "Books"), ("subscription", "Subscription"), ("suscripcion", "Subscription")]
            if let match = common.first(where: { normalized.contains($0.0) }) { return match.1 }
        }

        if kind == .income {
            if normalized.contains("family") || normalized.contains("familia") { return "Family support" }
            if normalized.contains("refund") || normalized.contains("reembolso") || normalized.contains("devuel") { return "Reimbursement" }
            if normalized.contains("tutor") { return "Tutoring" }
            if normalized.contains("job") || normalized.contains("trabajo") { return "Work income" }
        }

        return defaults[kind] ?? "Planned item"
    }

    private static func firstCapture(in text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let ns = text as NSString
        let range = NSRange(location: 0, length: ns.length)
        guard let match = regex.firstMatch(in: text, options: [], range: range), match.numberOfRanges > 1 else { return nil }
        let capture = match.range(at: 1)
        guard capture.location != NSNotFound else { return nil }
        return ns.substring(with: capture)
    }
}
