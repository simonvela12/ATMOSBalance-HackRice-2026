import Foundation

public enum QualitativeNoteSubject: String, Codable, Sendable {
    case income
    case expense
    case goal
    case general
}

public struct QualitativeNoteContext: Sendable {
    public let subject: QualitativeNoteSubject
    public let referenceAmount: Double?
    public let referenceDate: Date?
    public let label: String?

    public init(
        subject: QualitativeNoteSubject,
        referenceAmount: Double? = nil,
        referenceDate: Date? = nil,
        label: String? = nil
    ) {
        self.subject = subject
        self.referenceAmount = referenceAmount
        self.referenceDate = referenceDate
        self.label = label
    }
}

public enum QualitativeMissingField: String, Codable, Equatable, Sendable {
    case repaymentDate
    case recurrenceCadence
    case reserveAmount
}

public enum QualitativeDirective: Equatable, Sendable {
    case setIncomeType(IncomeType)
    case setIrregularIncomeConfidence(Double)
    case setExpenseCommitted(Bool)
    case setExpenseEssential(Bool)
    case expectReimbursement(on: Date)
    case setRecurrence(cadence: RecurrenceCadence, firstDate: Date?)
    case setGoalPriority(GoalPriority)
    case setPersonalReserve(amount: Double, effectiveDate: Date)
}

public struct QualitativeParseResult: Sendable {
    public let originalText: String
    public let directives: [QualitativeDirective]
    public let missingFields: [QualitativeMissingField]
    public let matchedRules: [String]

    public init(
        originalText: String,
        directives: [QualitativeDirective],
        missingFields: [QualitativeMissingField],
        matchedRules: [String]
    ) {
        self.originalText = originalText
        self.directives = directives
        self.missingFields = missingFields
        self.matchedRules = matchedRules
    }

    public var recognizedSomething: Bool {
        !matchedRules.isEmpty
    }

    public var isActionable: Bool {
        !directives.isEmpty && missingFields.isEmpty
    }
}

/// A deterministic, local interpreter for the app's free-text "miscellaneous context" box.
///
/// It intentionally does not try to understand arbitrary prose. It recognizes a compact set
/// of financially meaningful phrases and converts them into structured directives that the
/// app can show back to the user for confirmation before changing `FinancialProfile` inputs.
///
/// This keeps affordability decisions auditable and avoids requiring an LLM or network call.
public enum QualitativeNoteInterpreter {
    public static func parse(
        _ rawText: String,
        context: QualitativeNoteContext,
        asOfDate: Date,
        calendar: Calendar = .current
    ) -> QualitativeParseResult {
        let text = normalized(rawText)
        var directives: [QualitativeDirective] = []
        var missingFields: [QualitativeMissingField] = []
        var matchedRules: [String] = []

        let parsedDate = extractDate(from: text, asOfDate: asOfDate, calendar: calendar)
        let cadence = detectCadence(in: text)

        if context.subject == .expense {
            if containsAny(text, reimbursementPhrases) {
                matchedRules.append("expense-reimbursement")
                if let parsedDate {
                    directives.append(.expectReimbursement(on: parsedDate))
                } else {
                    missingFields.append(.repaymentDate)
                }
            }

            if containsAny(text, committedTruePhrases) {
                matchedRules.append("expense-committed")
                directives.append(.setExpenseCommitted(true))
            } else if containsAny(text, committedFalsePhrases) {
                matchedRules.append("expense-not-committed")
                directives.append(.setExpenseCommitted(false))
            }

            if containsAny(text, essentialTruePhrases) {
                matchedRules.append("expense-essential")
                directives.append(.setExpenseEssential(true))
            } else if containsAny(text, essentialFalsePhrases) {
                matchedRules.append("expense-nonessential")
                directives.append(.setExpenseEssential(false))
            }

            if let cadence {
                matchedRules.append("expense-recurrence")
                directives.append(.setRecurrence(cadence: cadence, firstDate: parsedDate))
            } else if containsAny(text, genericRecurringPhrases) {
                matchedRules.append("expense-recurring-missing-cadence")
                missingFields.append(.recurrenceCadence)
            }
        }

        if context.subject == .income {
            let explicitOneTime = containsAny(text, oneTimeIncomePhrases)
            let explicitIrregular = containsAny(text, irregularIncomePhrases)
            let explicitRecurring = cadence != nil || containsAny(text, genericRecurringPhrases)

            if explicitOneTime {
                matchedRules.append("income-one-time")
                directives.append(.setIncomeType(.oneTime))
            } else if explicitIrregular {
                matchedRules.append("income-irregular")
                directives.append(.setIncomeType(.irregular))
            } else if explicitRecurring {
                matchedRules.append("income-recurring")
                directives.append(.setIncomeType(.recurring))
            }

            if let cadence {
                matchedRules.append("income-recurrence")
                directives.append(.setRecurrence(cadence: cadence, firstDate: parsedDate))
            } else if containsAny(text, genericRecurringPhrases) && !explicitOneTime && !explicitIrregular {
                matchedRules.append("income-recurring-missing-cadence")
                missingFields.append(.recurrenceCadence)
            }

            if let confidence = extractConfidence(from: text) {
                matchedRules.append("income-confidence")
                directives.append(.setIrregularIncomeConfidence(confidence))
            }
        }

        if context.subject == .goal {
            if containsAny(text, goalMandatoryPhrases) {
                matchedRules.append("goal-mandatory")
                directives.append(.setGoalPriority(.mandatory))
            } else if containsAny(text, goalFlexiblePhrases) {
                matchedRules.append("goal-flexible")
                directives.append(.setGoalPriority(.flexible))
            }
        }

        if context.subject == .general && containsAny(text, reservePhrases) {
            matchedRules.append("personal-reserve")
            if let amount = extractMoneyAmount(from: text) {
                directives.append(
                    .setPersonalReserve(
                        amount: amount,
                        effectiveDate: parsedDate ?? asOfDate
                    )
                )
            } else {
                missingFields.append(.reserveAmount)
            }
        }

        return QualitativeParseResult(
            originalText: rawText,
            directives: deduplicated(directives),
            missingFields: Array(Set(missingFields)).sorted { $0.rawValue < $1.rawValue },
            matchedRules: matchedRules
        )
    }

    // MARK: - Phrase catalog

    private static let reimbursementPhrases = [
        "me deben",
        "me lo deben",
        "me van a devolver",
        "me devolveran",
        "reembolso",
        "reembolsar",
        "reimburse",
        "reimbursement",
        "pay me back",
        "paid back",
        "owes me",
        "owe me"
    ]

    private static let oneTimeIncomePhrases = [
        "solo una vez",
        "una sola vez",
        "no volvera a pasar",
        "no espero recibirlo de nuevo",
        "no planeo recibirlo de nuevo",
        "one time",
        "one-time",
        "only once",
        "never again",
        "do not expect to receive this again",
        "dont expect to receive this again"
    ]

    private static let irregularIncomePhrases = [
        "no frecuentemente",
        "no frecuente",
        "no es frecuente",
        "de vez en cuando",
        "irregular",
        "no fijo",
        "no es fijo",
        "not often",
        "not frequently",
        "not recurring",
        "occasional",
        "not fixed",
        "varies"
    ]

    private static let genericRecurringPhrases = [
        "recurrente",
        "recurrent",
        "recurring",
        "regularmente",
        "regularly",
        "se repite",
        "repeats"
    ]

    private static let committedTruePhrases = [
        "tengo que pagarlo",
        "tengo que pagar esto",
        "es obligatorio",
        "ya esta comprometido",
        "ya lo debo",
        "must pay",
        "have to pay",
        "obligatory",
        "already committed",
        "already owe"
    ]

    private static let committedFalsePhrases = [
        "puedo cancelarlo",
        "puedo evitarlo",
        "no esta comprometido",
        "es opcional",
        "can cancel",
        "can skip",
        "not committed",
        "optional"
    ]

    private static let essentialTruePhrases = [
        "es esencial",
        "es necesario",
        "lo necesito",
        "essential",
        "necessary",
        "need this"
    ]

    private static let essentialFalsePhrases = [
        "no es esencial",
        "no lo necesito",
        "es un gusto",
        "nonessential",
        "non-essential",
        "not essential",
        "nice to have"
    ]

    private static let goalMandatoryPhrases = [
        "es obligatorio",
        "tiene que cumplirse",
        "lo tengo que pagar",
        "no puedo posponerlo",
        "mandatory",
        "must happen",
        "must fund",
        "cannot postpone",
        "cant postpone"
    ]

    private static let goalFlexiblePhrases = [
        "puedo posponerlo",
        "puede esperar",
        "es flexible",
        "no es obligatorio",
        "can postpone",
        "can wait",
        "flexible",
        "not mandatory"
    ]

    private static let reservePhrases = [
        "quiero guardar",
        "necesito guardar",
        "no quiero tocar",
        "quiero mantener al menos",
        "necesito mantener al menos",
        "reserva",
        "colchon",
        "keep at least",
        "need to keep",
        "do not touch",
        "dont touch",
        "reserve",
        "minimum cash"
    ]

    // MARK: - Recognition helpers

    private static func detectCadence(in text: String) -> RecurrenceCadence? {
        if containsAny(text, [
            "cada dos semanas",
            "cada 2 semanas",
            "quincenal",
            "quincenalmente",
            "every two weeks",
            "every 2 weeks",
            "biweekly",
            "bi-weekly"
        ]) {
            return .biweekly
        }

        if containsAny(text, [
            "cada mes",
            "mensual",
            "mensualmente",
            "every month",
            "monthly"
        ]) {
            return .monthly
        }

        if containsAny(text, [
            "cada semana",
            "semanal",
            "semanalmente",
            "every week",
            "weekly"
        ]) {
            return .weekly
        }

        return nil
    }

    private static func extractConfidence(from text: String) -> Double? {
        let confidenceWords = [
            "probabilidad",
            "chance",
            "confidence",
            "seguro",
            "likely",
            "probable"
        ]
        guard containsAny(text, confidenceWords) else { return nil }

        if let captures = captures(#"([0-9]{1,3})\s*(?:%|percent|por ciento)"#, in: text),
           let value = Double(captures[1]) {
            return min(max(value / 100.0, 0), 1)
        }

        if let captures = captures(#"(?:confidence|probabilidad)\s*(?:de|of|=|:)?\s*(0(?:\.[0-9]+)?|1(?:\.0+)?)"#, in: text),
           let value = Double(captures[1]) {
            return min(max(value, 0), 1)
        }

        return nil
    }

    private static func extractMoneyAmount(from text: String) -> Double? {
        let pattern = #"(?:\$\s*|usd\s*)?([0-9]{1,3}(?:,[0-9]{3})*(?:\.[0-9]{1,2})?|[0-9]+(?:\.[0-9]{1,2})?)"#
        guard let match = captures(pattern, in: text) else { return nil }
        let normalizedNumber = match[1].replacingOccurrences(of: ",", with: "")
        return Double(normalizedNumber)
    }

    private static func extractDate(
        from text: String,
        asOfDate: Date,
        calendar: Calendar
    ) -> Date? {
        if containsAny(text, ["manana", "tomorrow"]) {
            return calendar.date(byAdding: .day, value: 1, to: asOfDate)
        }

        if containsAny(text, ["hoy", "today"]) {
            return asOfDate
        }

        if let match = captures(#"(?:en|in)\s+([0-9]+)\s+(?:dias|dia|days|day)"#, in: text),
           let days = Int(match[1]) {
            return calendar.date(byAdding: .day, value: days, to: asOfDate)
        }

        if containsAny(text, ["la semana que viene", "proxima semana", "next week"]) {
            return calendar.date(byAdding: .day, value: 7, to: asOfDate)
        }

        if let iso = captures(#"\b(20[0-9]{2})-([0-9]{1,2})-([0-9]{1,2})\b"#, in: text),
           let year = Int(iso[1]),
           let month = Int(iso[2]),
           let day = Int(iso[3]) {
            return calendar.date(from: DateComponents(year: year, month: month, day: day))
        }

        if let monthDate = extractNamedMonthDate(from: text, asOfDate: asOfDate, calendar: calendar) {
            return monthDate
        }

        let weekdayMap: [(String, Int)] = [
            ("domingo", 1), ("sunday", 1),
            ("lunes", 2), ("monday", 2),
            ("martes", 3), ("tuesday", 3),
            ("miercoles", 4), ("wednesday", 4),
            ("jueves", 5), ("thursday", 5),
            ("viernes", 6), ("friday", 6),
            ("sabado", 7), ("saturday", 7)
        ]

        for (word, targetWeekday) in weekdayMap where text.contains(word) {
            let currentWeekday = calendar.component(.weekday, from: asOfDate)
            var delta = (targetWeekday - currentWeekday + 7) % 7
            if delta == 0 { delta = 7 }
            return calendar.date(byAdding: .day, value: delta, to: asOfDate)
        }

        return nil
    }

    private static func extractNamedMonthDate(
        from text: String,
        asOfDate: Date,
        calendar: Calendar
    ) -> Date? {
        let monthNumbers: [String: Int] = [
            "enero": 1, "january": 1,
            "febrero": 2, "february": 2,
            "marzo": 3, "march": 3,
            "abril": 4, "april": 4,
            "mayo": 5, "may": 5,
            "junio": 6, "june": 6,
            "julio": 7, "july": 7,
            "agosto": 8, "august": 8,
            "septiembre": 9, "setiembre": 9, "september": 9,
            "octubre": 10, "october": 10,
            "noviembre": 11, "november": 11,
            "diciembre": 12, "december": 12
        ]
        let monthPattern = monthNumbers.keys.sorted { $0.count > $1.count }.joined(separator: "|")

        let dayFirstPattern = #"\b([0-9]{1,2})(?:st|nd|rd|th)?\s+(?:de\s+)?("# + monthPattern + #")(?:\s+(?:de\s+)?(20[0-9]{2}))?\b"#
        if let match = captures(dayFirstPattern, in: text),
           let day = Int(match[1]),
           let month = monthNumbers[match[2]] {
            let explicitYear = Int(match[3])
            return futureDate(
                day: day,
                month: month,
                explicitYear: explicitYear,
                asOfDate: asOfDate,
                calendar: calendar
            )
        }

        let monthFirstPattern = #"\b("# + monthPattern + #")\s+([0-9]{1,2})(?:st|nd|rd|th)?(?:,?\s+(20[0-9]{2}))?\b"#
        if let match = captures(monthFirstPattern, in: text),
           let month = monthNumbers[match[1]],
           let day = Int(match[2]) {
            let explicitYear = Int(match[3])
            return futureDate(
                day: day,
                month: month,
                explicitYear: explicitYear,
                asOfDate: asOfDate,
                calendar: calendar
            )
        }

        return nil
    }

    private static func futureDate(
        day: Int,
        month: Int,
        explicitYear: Int?,
        asOfDate: Date,
        calendar: Calendar
    ) -> Date? {
        let currentYear = calendar.component(.year, from: asOfDate)
        var year = explicitYear ?? currentYear
        guard var candidate = calendar.date(from: DateComponents(year: year, month: month, day: day)) else {
            return nil
        }

        if explicitYear == nil && candidate < calendar.startOfDay(for: asOfDate) {
            year += 1
            guard let nextYear = calendar.date(from: DateComponents(year: year, month: month, day: day)) else {
                return nil
            }
            candidate = nextYear
        }

        return candidate
    }

    private static func normalized(_ text: String) -> String {
        text
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .lowercased()
            .replacingOccurrences(of: "’", with: "'")
    }

    private static func containsAny(_ text: String, _ phrases: [String]) -> Bool {
        phrases.contains { text.contains($0) }
    }

    private static func captures(_ pattern: String, in text: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let fullRange = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: fullRange) else { return nil }

        return (0..<match.numberOfRanges).map { index in
            let range = match.range(at: index)
            guard range.location != NSNotFound,
                  let swiftRange = Range(range, in: text) else {
                return ""
            }
            return String(text[swiftRange])
        }
    }

    private static func deduplicated(_ directives: [QualitativeDirective]) -> [QualitativeDirective] {
        var result: [QualitativeDirective] = []
        for directive in directives where !result.contains(directive) {
            result.append(directive)
        }
        return result
    }
}

/// Ready-to-show examples for the qualitative text box. Keeping these close to the parser
/// makes it less likely that the UI suggests language the deterministic interpreter cannot
/// actually understand.
public enum QualitativeNoteExamples {
    public static func examples(for subject: QualitativeNoteSubject) -> [String] {
        switch subject {
        case .income:
            return [
                "I don't expect to receive this frequently.",
                "This is a one-time payment.",
                "I get this every two weeks.",
                "There's about a 60% chance I receive this."
            ]
        case .expense:
            return [
                "I have to pay this every month.",
                "This is optional and I can cancel it.",
                "They owe me for this and will pay me next Friday.",
                "This isn't essential, but I already committed to it."
            ]
        case .goal:
            return [
                "I can't postpone this.",
                "This goal can wait.",
                "This is mandatory."
            ]
        case .general:
            return [
                "I need to keep at least $500 untouched.",
                "I want a $1,000 reserve starting October 1."
            ]
        }
    }
}
