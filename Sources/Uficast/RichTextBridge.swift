import AppKit
import UficastCore

/// Attributed text split into styled runs for SpanMarkup, with the attribute tables
/// needed to restore it. A plain source has no styles and is never marked.
struct RichText {
    var segments: [StyledSegment]
    var styles: [[NSAttributedString.Key: Any]]
    var base: [NSAttributedString.Key: Any]
    var isRich: Bool
}

@MainActor
enum RichTextBridge {
    /// RTF, then HTML, then plain text; nil when the pasteboard holds no usable text.
    static func read(_ pasteboard: NSPasteboard) -> NSAttributedString? {
        if let data = pasteboard.data(forType: .rtf), let text = NSAttributedString(rtf: data, documentAttributes: nil), hasText(text) {
            return text
        }
        // Pasteboard HTML is UTF-8; without this the importer guesses and garbles Cyrillic
        // when the snippet has no charset declaration.
        if let data = pasteboard.data(forType: .html),
           let text = try? NSAttributedString(data: data, options: [.documentType: NSAttributedString.DocumentType.html,
                                                                     .characterEncoding: String.Encoding.utf8.rawValue],
                                              documentAttributes: nil), hasText(text) {
            return text
        }
        if let string = pasteboard.string(forType: .string), !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return NSAttributedString(string: string)
        }
        return nil
    }

    static func isRich(_ pasteboard: NSPasteboard) -> Bool { pasteboard.availableType(from: [.rtf, .html]) != nil }

    /// The base style is the one at the start; runs equal to it are unmarked, and runs
    /// with equal attributes share one style index.
    static func split(_ text: NSAttributedString, isRich: Bool) -> RichText {
        guard isRich, text.length > 0 else {
            return RichText(segments: [StyledSegment(text: text.string, style: nil)], styles: [], base: [:], isRich: false)
        }
        let base = text.attributes(at: 0, effectiveRange: nil)
        var styles: [[NSAttributedString.Key: Any]] = []
        var segments: [StyledSegment] = []
        let string = text.string as NSString
        text.enumerateAttributes(in: NSRange(location: 0, length: text.length)) { attributes, range, _ in
            let style: Int?
            if NSDictionary(dictionary: attributes).isEqual(to: base) { style = nil }
            else if let index = styles.firstIndex(where: { NSDictionary(dictionary: $0).isEqual(to: attributes) }) { style = index }
            else { styles.append(attributes); style = styles.count - 1 }
            let piece = string.substring(with: range)
            if let last = segments.last, last.style == style { segments[segments.count - 1].text += piece }
            else { segments.append(StyledSegment(text: piece, style: style)) }
        }
        return RichText(segments: segments, styles: styles, base: base, isRich: true)
    }

    static func join(_ segments: [StyledSegment], from source: RichText) -> NSAttributedString {
        let result = NSMutableAttributedString()
        for segment in segments {
            let attributes = segment.style.flatMap { source.styles.indices.contains($0) ? source.styles[$0] : nil } ?? source.base
            result.append(NSAttributedString(string: segment.text, attributes: attributes))
        }
        return result
    }

    /// Plain text always; RTF only for a rich source, so a plain field keeps its own style.
    static func write(_ text: NSAttributedString, rich: Bool, to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        pasteboard.declareTypes(rich ? [.rtf, .string] : [.string], owner: nil)
        if rich, let data = text.rtf(from: NSRange(location: 0, length: text.length), documentAttributes: [:]) {
            pasteboard.setData(data, forType: .rtf)
        }
        pasteboard.setString(text.string, forType: .string)
    }

    /// Images arrive as attachment characters (U+FFFC); a selection of only those is not text.
    private static func hasText(_ text: NSAttributedString) -> Bool {
        let attachment = String(Character(UnicodeScalar(NSTextAttachment.character)!))
        return !text.string.replacingOccurrences(of: attachment, with: "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
