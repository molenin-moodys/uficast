import Foundation

/// A small, total arithmetic evaluator: + - × ÷ ^ % and parentheses. Anything it
/// cannot read exactly returns nil, so partially typed input shows nothing
/// instead of a guess. It never traps and never evaluates host-language code.
public enum Calculator {
    static let maximumLength = 200
    static let maximumDepth = 64

    public static func evaluate(_ text: String) -> Double? {
        guard text.count <= maximumLength else { return nil }
        var parser = Parser(Array(text))
        guard let value = parser.parseExpression(depth: 0)?.value, parser.isAtEnd(),
              value.isFinite else { return nil }
        return value
    }

    /// At most 15 significant digits, so binary noise such as 0.30000000000000004
    /// disappears. Always a dot decimal separator, no grouping.
    public static func format(_ value: Double) -> String {
        let text = String(format: "%.15g", value)
        if text.contains("e"), let decimal = Decimal(string: text), decimal.isFinite { return "\(decimal)" }
        return text == "-0" ? "0" : text
    }

    private struct Operand {
        var value: Double
        /// True only for a lone `n%`, which is relative to the left side of + or −.
        var isPercent = false
    }

    private struct Parser {
        let characters: [Character]
        var position = 0

        init(_ characters: [Character]) { self.characters = characters }

        mutating func isAtEnd() -> Bool { peek() == nil }

        mutating func peek() -> Character? {
            while position < characters.count, characters[position].isWhitespace { position += 1 }
            return position < characters.count ? characters[position] : nil
        }

        mutating func parseExpression(depth: Int) -> Operand? {
            guard depth <= Calculator.maximumDepth, var result = parseTerm(depth: depth) else { return nil }
            while let character = peek(), "+-−–".contains(character) {
                position += 1
                guard let right = parseTerm(depth: depth) else { return nil }
                let amount = right.isPercent ? result.value * right.value : right.value
                result = Operand(value: character == "+" ? result.value + amount : result.value - amount)
            }
            return result
        }

        mutating func parseTerm(depth: Int) -> Operand? {
            guard var result = parseUnary(depth: depth) else { return nil }
            while let character = peek(), "*/×÷".contains(character) {
                position += 1
                guard let right = parseUnary(depth: depth) else { return nil }
                if "*×".contains(character) { result = Operand(value: result.value * right.value) }
                else {
                    guard right.value != 0 else { return nil }
                    result = Operand(value: result.value / right.value)
                }
            }
            return result
        }

        mutating func parseUnary(depth: Int) -> Operand? {
            guard depth <= Calculator.maximumDepth else { return nil }
            if let character = peek(), "+-−–".contains(character) {
                position += 1
                guard let operand = parseUnary(depth: depth + 1) else { return nil }
                return Operand(value: "+".contains(character) ? operand.value : -operand.value)
            }
            return parsePower(depth: depth)
        }

        mutating func parsePower(depth: Int) -> Operand? {
            guard let base = parsePostfix(depth: depth) else { return nil }
            guard peek() == "^" else { return base }
            position += 1
            guard let exponent = parseUnary(depth: depth + 1) else { return nil }
            return Operand(value: pow(base.value, exponent.value))
        }

        mutating func parsePostfix(depth: Int) -> Operand? {
            guard var result = parsePrimary(depth: depth) else { return nil }
            while peek() == "%" {
                position += 1
                result = Operand(value: result.value / 100, isPercent: true)
            }
            return result
        }

        mutating func parsePrimary(depth: Int) -> Operand? {
            guard let character = peek() else { return nil }
            if character == "(" {
                position += 1
                guard let inner = parseExpression(depth: depth + 1), peek() == ")" else { return nil }
                position += 1
                return Operand(value: inner.value)
            }
            return parseNumber()
        }

        mutating func parseNumber() -> Operand? {
            var integer = ""
            var fraction = ""
            var hasSeparator = false
            var usedComma = false
            while position < characters.count {
                let character = characters[position]
                if character.isASCII, character.isNumber {
                    if hasSeparator { fraction.append(character) } else { integer.append(character) }
                } else if (character == "." || character == ","), !hasSeparator {
                    hasSeparator = true
                    usedComma = character == ","
                } else { break }
                position += 1
            }
            guard !integer.isEmpty || !fraction.isEmpty else { return nil }
            // "1,000" could be a thousands separator: refuse it rather than read 1.
            if usedComma && fraction.count == 3 && !integer.isEmpty { return nil }
            guard let value = Double("\(integer.isEmpty ? "0" : integer).\(fraction.isEmpty ? "0" : fraction)") else { return nil }
            return Operand(value: value)
        }
    }
}

/// Decides whether launcher text is a calculation, as opposed to an application search.
public struct CalculatorQuery: Equatable, Sendable {
    public enum Mode: Sendable { case formula, keyword }
    public var mode: Mode
    public var expression: String

    public init(mode: Mode, expression: String) {
        self.mode = mode
        self.expression = expression
    }

    private static let formulaCharacters = Set("0123456789.,+-−–*/×÷^%() \t")
    private static let operatorCharacters = Set("+-−–*/×÷^%()")

    public static func parse(_ text: String) -> CalculatorQuery? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowered = trimmed.lowercased()
        if lowered.hasPrefix("calc") {
            let rest = trimmed.dropFirst(4)
            if rest.isEmpty { return CalculatorQuery(mode: .keyword, expression: "") }
            if rest.first?.isWhitespace == true {
                return CalculatorQuery(mode: .keyword, expression: rest.trimmingCharacters(in: .whitespacesAndNewlines))
            }
            return nil
        }
        guard trimmed.allSatisfy({ formulaCharacters.contains($0) }),
              trimmed.contains(where: { $0.isASCII && $0.isNumber }),
              trimmed.contains(where: { operatorCharacters.contains($0) }) else { return nil }
        return CalculatorQuery(mode: .formula, expression: trimmed)
    }

    /// Worth restoring on the next open: a formula or `calc` followed by something.
    public static func isDraft(_ text: String) -> Bool {
        guard let query = parse(text) else { return false }
        return query.mode == .formula || !query.expression.isEmpty
    }
}

/// Remembered calculations and the unfinished formula. Local state only; it is
/// deliberately not part of the exported configuration.
public struct CalculatorState: Codable, Equatable, Sendable {
    public struct Entry: Codable, Equatable, Sendable {
        public var expression: String
        public var result: String
        public var date: Date
        public init(expression: String, result: String, date: Date) {
            self.expression = expression
            self.result = result
            self.date = date
        }
    }

    public static let historyLimit = 50
    public static let suggestionLimit = 6

    public var history: [Entry] = []
    public var draft: String?

    public init(history: [Entry] = [], draft: String? = nil) {
        self.history = history
        self.draft = draft
    }

    public static func decode(_ data: Data?) -> CalculatorState {
        data.flatMap { try? JSONDecoder().decode(CalculatorState.self, from: $0) } ?? CalculatorState()
    }

    public mutating func record(expression: String, result: String, date: Date = Date()) {
        let trimmed = expression.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = Self.key(trimmed)
        guard !key.isEmpty else { return }
        history.removeAll { Self.key($0.expression) == key }
        history.insert(Entry(expression: trimmed, result: result, date: date), at: 0)
        if history.count > Self.historyLimit { history.removeLast(history.count - Self.historyLimit) }
    }

    /// Entries whose expression starts with what has been typed so far (spaces
    /// ignored), newest first. The exact expression is skipped; the live result
    /// row already stands for it. An empty prefix gives the most recent entries.
    public func suggestions(for expression: String, limit: Int = CalculatorState.suggestionLimit) -> [Entry] {
        let key = Self.key(expression)
        let matches = history.filter { key.isEmpty || (Self.key($0.expression).hasPrefix(key) && Self.key($0.expression) != key) }
        return Array(matches.prefix(max(0, limit)))
    }

    private static func key(_ expression: String) -> String {
        expression.filter { !$0.isWhitespace }.lowercased()
    }
}

extension LauncherEntry {
    public static let calculatorResultID = "calc:result"

    public static func calculatorResult(expression: String, result: String) -> LauncherEntry {
        LauncherEntry(id: calculatorResultID, name: result, kind: .calculator,
                      fileURL: URL(string: "uficast://calculator/result")!, alias: expression)
    }

    public static func calculatorHistory(_ entry: CalculatorState.Entry) -> LauncherEntry {
        LauncherEntry(id: "calc:history:\(entry.expression)", name: entry.result, kind: .history,
                      fileURL: URL(string: "uficast://calculator/history")!, alias: entry.expression)
    }
}
