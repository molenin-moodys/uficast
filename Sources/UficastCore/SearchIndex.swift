import Foundation

public struct SearchIndex: Sendable {
    private struct Indexed: Sendable {
        var entry: LauncherEntry
        var name: String
        var characters: [Character]
        var alias: String?
    }
    private struct Match {
        var indexed: Indexed
        var tier: Int
        var score: Int
        var usage: UsageRecord
    }
    private var items: [Indexed]

    public init(entries: [LauncherEntry] = []) {
        items = entries.filter(\.isEnabled).map {
            let name = SearchText.normalize($0.name)
            return Indexed(entry: $0, name: name, characters: Array(name), alias: $0.alias.map(SearchText.normalize))
        }
    }

    public func search(_ text: String, usage: [String: UsageRecord] = [:], limit: Int = 50) -> [LauncherEntry] {
        guard limit > 0 else { return [] }
        let query = SearchText.normalize(text.trimmingCharacters(in: .whitespacesAndNewlines))
        let queryCharacters = Array(query)
        var matches = [Match]()
        for item in items {
            let tier: Int
            let score: Int
            if query.isEmpty { tier = 6; score = 0 }
            else if item.alias == query { tier = 0; score = 0 }
            else if let alias = item.alias, alias.hasPrefix(query) { tier = 1; score = 0 }
            else if item.name == query { tier = 2; score = 0 }
            else if item.name.hasPrefix(query) { tier = 3; score = 0 }
            else if item.name.contains(query) { tier = 4; score = 0 }
            else if let fuzzy = Self.fuzzyScore(query: queryCharacters, name: item.characters) { tier = 5; score = fuzzy }
            else { continue }
            matches.append(Match(indexed: item, tier: tier, score: score, usage: usage[item.entry.id] ?? UsageRecord()))
        }
        matches.sort {
            if $0.tier != $1.tier { return $0.tier < $1.tier }
            if $0.score != $1.score { return $0.score > $1.score }
            if $0.usage.count != $1.usage.count { return $0.usage.count > $1.usage.count }
            if $0.usage.lastUsed != $1.usage.lastUsed { return $0.usage.lastUsed > $1.usage.lastUsed }
            if $0.indexed.name != $1.indexed.name { return $0.indexed.name < $1.indexed.name }
            return $0.indexed.entry.id < $1.indexed.entry.id
        }
        return matches.prefix(limit).map(\.indexed.entry)
    }

    private static func fuzzyScore(query: [Character], name: [Character]) -> Int? {
        var next = 0
        var previous = -2
        var score = 0
        for (index, character) in name.enumerated() where next < query.count {
            guard character == query[next] else { continue }
            score += previous == index - 1 ? 12 : 0
            if index == 0 || !name[index - 1].isLetter && !name[index - 1].isNumber { score += 10 }
            score -= index - previous - 1
            previous = index
            next += 1
        }
        return next == query.count ? score : nil
    }
}
