import Foundation

/// Additional search queries for physical keys typed in standard U.S./Russian
/// layouts. This does not change the field, the system layout, or script input.
public enum KeyboardLayoutSearch {
    private static let english = Array("`qwertyuiop[]asdfghjkl;'zxcvbnm,./")
    private static let russian = Array("ёйцукенгшщзхъфывапролджэячсмитьбю.")
    private static let toEnglish = Dictionary(uniqueKeysWithValues: zip(russian, english))
    private static let toRussian = Dictionary(uniqueKeysWithValues: zip(english, russian))

    public static func variants(_ text: String) -> [String] {
        // Map before diacritic folding, which would otherwise change ё/й.
        let source = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let candidates = [source,
            String(source.map { toEnglish[$0] ?? $0 }),
            String(source.map { toRussian[$0] ?? $0 })]
        var seen: Set<String> = []
        return candidates.map(SearchText.normalize).filter { seen.insert($0).inserted }
    }
}
