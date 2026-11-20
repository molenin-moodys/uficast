import Foundation
import Testing
import UficastCore

private func value(_ text: String) -> Double? { Calculator.evaluate(text) }

@Test func evaluatesArithmeticWithPrecedenceParenthesesAndPowers() {
    #expect(value("2+2*3") == 8)
    #expect(value("(2+2)*3") == 12)
    #expect(value("10/4") == 2.5)
    #expect(value("-5+2") == -3)
    #expect(value("-2^2") == -4)
    #expect(value("2^3^2") == 512)
    #expect(value("2^-1") == 0.5)
    #expect(value("2 × 3 ÷ 4") == 1.5)
    #expect(value("5 − 2") == 3)
    #expect(value("  ( 1 + 2 ) * ( 3 + 4 )  ") == 21)
}

@Test func acceptsDotAndCommaAsDecimalSeparator() {
    #expect(value("1.5*2") == 3)
    #expect(value("1,5*2") == 3)
    #expect(value(".5+.5") == 1)
    #expect(value("0,25*4") == 1)
}

@Test func percentIsRelativeInSumsAndPlainElsewhere() {
    #expect(value("50%") == 0.5)
    #expect(value("200+10%") == 220)
    #expect(value("200-10%") == 180)
    #expect(value("200*10%") == 20)
    #expect(value("(100+100)+10%") == 220)
}

@Test func rejectsIncompleteOrAmbiguousInputInsteadOfGuessing() {
    for text in ["", "   ", "2+", "2**3", "(2+3", "2+3)", "abc", "2+a", "1/0", "0/0", "1.2.3",
                 "1,000+1", "1 000", "()", "2 3", "10^400", "%"] {
        #expect(value(text) == nil, "\(text) must not produce a result")
    }
    #expect(value(String(repeating: "(", count: 500) + "1" + String(repeating: ")", count: 500)) == nil)
    #expect(value(String(repeating: "1+", count: 300) + "1") == nil)
}

@Test func commaWithThreeFractionDigitsIsOnlyRejectedWhenAmbiguous() {
    #expect(value("1,25+1") == 2.25)
    #expect(Calculator.format(value("1,2345+1")!) == "2.2345")
}

@Test func formatsResultsWithoutBinaryNoiseOrScientificNotation() {
    #expect(Calculator.format(value("0.1+0.2")!) == "0.3")
    #expect(Calculator.format(8) == "8")
    #expect(Calculator.format(-3) == "-3")
    #expect(Calculator.format(value("1/3")!) == "0.333333333333333")
    #expect(Calculator.format(value("5/100000")!) == "0.00005")
    #expect(Calculator.format(value("1000000*1000000")!) == "1000000000000")
    #expect(Calculator.format(-0.0) == "0")
}

@Test func queryRecognizesFormulasAndTheCalcKeyword() {
    #expect(CalculatorQuery.parse("2+2") == CalculatorQuery(mode: .formula, expression: "2+2"))
    #expect(CalculatorQuery.parse("  (1+2)*3 ") == CalculatorQuery(mode: .formula, expression: "(1+2)*3"))
    #expect(CalculatorQuery.parse("2+") == CalculatorQuery(mode: .formula, expression: "2+"))
    #expect(CalculatorQuery.parse("1,5 × 2") == CalculatorQuery(mode: .formula, expression: "1,5 × 2"))
    #expect(CalculatorQuery.parse("calc") == CalculatorQuery(mode: .keyword, expression: ""))
    #expect(CalculatorQuery.parse("CALC  5*5") == CalculatorQuery(mode: .keyword, expression: "5*5"))
    #expect(CalculatorQuery.parse("calc 12") == CalculatorQuery(mode: .keyword, expression: "12"))
}

@Test func queryLeavesOrdinaryApplicationSearchesAlone() {
    for text in ["", "2", "1password", "7-zip", "calculator", "calendar", "(", "+", "-", "notes", "3 body"] {
        #expect(CalculatorQuery.parse(text) == nil, "\(text) is an application search")
    }
}

@Test func onlyAnActualFormulaIsWorthRememberingAsADraft() {
    #expect(CalculatorQuery.isDraft("2+") == true)
    #expect(CalculatorQuery.isDraft("calc 4*") == true)
    #expect(CalculatorQuery.isDraft("calc") == false)
    #expect(CalculatorQuery.isDraft("calc   ") == false)
    #expect(CalculatorQuery.isDraft("safari") == false)
    #expect(CalculatorQuery.isDraft("") == false)
}

@Test func historyRecordsNewestFirstAndMergesEquivalentExpressions() {
    var state = CalculatorState()
    let early = Date(timeIntervalSince1970: 100)
    state.record(expression: "2+2", result: "4", date: early)
    state.record(expression: "3*3", result: "9", date: early)
    state.record(expression: "2 + 2", result: "4", date: Date(timeIntervalSince1970: 200))
    #expect(state.history.map(\.expression) == ["2 + 2", "3*3"])
    #expect(state.history.first?.date == Date(timeIntervalSince1970: 200))
}

@Test func historyKeepsOnlyTheMostRecentFiftyAndIgnoresEmptyEntries() {
    var state = CalculatorState()
    for number in 0..<60 { state.record(expression: "\(number)+1", result: "\(number + 1)") }
    state.record(expression: "  ", result: "0")
    #expect(state.history.count == CalculatorState.historyLimit)
    #expect(state.history.first?.expression == "59+1")
    #expect(state.history.last?.expression == "10+1")
}

@Test func suggestionsMatchTheTypedPrefixIgnoringSpacesAndSkipTheExactMatch() {
    var state = CalculatorState()
    state.record(expression: "12*12", result: "144")
    state.record(expression: "12 + 30", result: "42")
    state.record(expression: "(5+5)*2", result: "20")
    #expect(state.suggestions(for: "12").map(\.expression) == ["12 + 30", "12*12"])
    #expect(state.suggestions(for: "12+").map(\.expression) == ["12 + 30"])
    #expect(state.suggestions(for: "12+30").isEmpty)
    #expect(state.suggestions(for: "(5").map(\.result) == ["20"])
    #expect(state.suggestions(for: "9").isEmpty)
}

@Test func suggestionsForAnEmptyExpressionAreTheRecentEntriesUpToTheLimit() {
    var state = CalculatorState()
    for number in 0..<10 { state.record(expression: "\(number)+1", result: "\(number + 1)") }
    #expect(state.suggestions(for: "").count == CalculatorState.suggestionLimit)
    #expect(state.suggestions(for: "").first?.expression == "9+1")
    #expect(state.suggestions(for: "", limit: 3).count == 3)
}

@Test func stateRoundTripsAndToleratesCorruptData() throws {
    var state = CalculatorState()
    state.record(expression: "2+2", result: "4", date: Date(timeIntervalSince1970: 5))
    state.draft = "7*"
    let data = try JSONEncoder().encode(state)
    #expect(try JSONDecoder().decode(CalculatorState.self, from: data) == state)
    #expect(CalculatorState.decode(data) == state)
    #expect(CalculatorState.decode(Data("not json".utf8)) == CalculatorState())
    #expect(CalculatorState.decode(nil) == CalculatorState())
}

@Test func calculatorRowsCarryTheResultAndTheExpression() {
    let live = LauncherEntry.calculatorResult(expression: "2+2*3", result: "8")
    #expect(live.kind == .calculator)
    #expect(live.name == "8")
    #expect(live.alias == "2+2*3")
    #expect(live.id == LauncherEntry.calculatorResultID)
    let entry = CalculatorState.Entry(expression: "(1+2)*3", result: "9", date: .distantPast)
    let history = LauncherEntry.calculatorHistory(entry)
    #expect(history.kind == .history)
    #expect(history.name == "9")
    #expect(history.alias == "(1+2)*3")
    #expect(history.id != live.id)
    #expect(LauncherEntry.Kind.calculator.title == "Calculator")
    #expect(LauncherEntry.Kind.history.title == "History")
}
