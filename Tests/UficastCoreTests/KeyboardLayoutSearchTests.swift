import Foundation
import Testing
import UficastCore

private func app(_ id: String, _ name: String, alias: String? = nil) -> LauncherEntry {
    LauncherEntry(id: id, name: name, fileURL: URL(fileURLWithPath: "/fixture/\(id).app"), alias: alias)
}

@Test func russianKeystrokesFindEnglishNamesAndAliases() {
    let index = SearchIndex(entries: [app("chrome", "Google Chrome"), app("firefox", "Firefox"), app("alias", "Terminal", alias: "calc")])
    #expect(index.search("сркщьу").first?.id == "chrome")
    #expect(index.search("ашкуащч").first?.id == "firefox")
    #expect(index.search("сфдс").first?.id == "alias")
    #expect(index.search("СHROME").first?.id == "chrome") // Mixed Cyrillic/Latin.
}

@Test func englishKeystrokesFindRussianNames() {
    let index = SearchIndex(entries: [app("telegram", "Телеграм")])
    #expect(index.search("ntktuhfv").first?.id == "telegram")
}

@Test func nativeAliasWinsBeforeConvertedAliasAndBothBeatNames() {
    let index = SearchIndex(entries: [
        app("name", "Calc"), app("converted", "Terminal", alias: "calc"), app("native", "Other", alias: "сфдс"),
    ])
    #expect(index.search("сфдс").map(\.id) == ["native", "converted", "name"])
}

@Test func variantsAreUniqueAndPreserveKeyboardMappingBeforeFolding() {
    #expect(KeyboardLayoutSearch.variants("123") == ["123"])
    #expect(KeyboardLayoutSearch.variants("Ё").contains("`"))
    #expect(KeyboardLayoutSearch.variants("Й").contains("q"))
    #expect(KeyboardLayoutSearch.variants("  ") == [""])
}
