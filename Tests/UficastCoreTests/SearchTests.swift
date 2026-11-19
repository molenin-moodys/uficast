import Foundation
import Testing
import UficastCore

private func entry(_ id: String, _ name: String, alias: String? = nil, enabled: Bool = true) -> LauncherEntry {
    LauncherEntry(id: id, name: name, fileURL: URL(fileURLWithPath: "/fixture/\(id).app"), alias: alias, isEnabled: enabled)
}

@Test func exactAliasOutranksExactNameAndHeavyUsage() {
    let index = SearchIndex(entries: [entry("name", "k"), entry("alias", "Kibana", alias: "K"), entry("prefix", "Kale")])
    let results = index.search("k", usage: ["name": .init(count: 10_000, lastUsed: .now)])
    #expect(results.map(\.id) == ["alias", "name", "prefix"])
}

@Test func nameRankTiersAndFuzzyAbbreviationAreStable() {
    let index = SearchIndex(entries: [
        entry("fuzzy", "C o d e"), entry("substring", "Visual Code"),
        entry("prefix", "Code Editor"), entry("exact", "Code"),
        entry("disabled", "Code", alias: "code", enabled: false),
    ])
    #expect(index.search("códe").map(\.id) == ["exact", "prefix", "substring", "fuzzy"])
    let chrome = SearchIndex(entries: [entry("chrome", "Google Chrome"), entry("other", "Calendar")])
    #expect(chrome.search("gchr").map(\.id) == ["chrome"])
    #expect(chrome.search("nothing").isEmpty)
}

@Test func aliasPrefixAndStableTieBreaks() {
    let index = SearchIndex(entries: [entry("b", "Same"), entry("a", "Same"), entry("alias", "Other", alias: "same-app")])
    #expect(index.search("same").map(\.id) == ["alias", "a", "b"])
    #expect(index.search("", limit: 2).count == 2)
    #expect(index.search("", limit: 0).isEmpty)
    #expect(index.search("same", usage: ["b": .init(count: 1)]).map(\.id) == ["alias", "b", "a"])
}

@Test func measureWarmSearchForTwoThousandApps() {
    let index = SearchIndex(entries: (0..<2000).map { entry("app\($0)", "Google Chrome Editor \($0)") })
    let queries = ["gchr", "chrome", "editor", "no-match"]
    var samples: [Double] = []
    for i in 0..<40 {
        let start = ContinuousClock.now
        _ = index.search(queries[i % queries.count])
        let elapsed = start.duration(to: .now).components
        samples.append(Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18)
    }
    let p95 = samples.sorted()[37]
    print("Warm search, 2,000 synthetic apps, p95: \(String(format: "%.2f", p95 * 1000)) ms")
    #expect(p95 < 0.030)
}
