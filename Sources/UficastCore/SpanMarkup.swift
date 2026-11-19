import Foundation

/// A piece of text in one style: nil is the base style, otherwise a 0-based index
/// into the caller's table of styles.
public struct StyledSegment: Equatable, Sendable {
    public var text: String
    public var style: Int?

    public init(text: String, style: Int?) {
        self.text = text
        self.style = style
    }
}

/// Carries inline formatting through a text model as `<sN>…</sN>` markers
/// (N = style index + 1). Decoding is strict: anything unexpected returns nil,
/// so the caller falls back to the base style instead of guessing.
public enum SpanMarkup {
    private static let entities: [(entity: String, character: Character)] = [("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">")]

    /// Text without any styled segment is returned unescaped and without markers.
    public static func encode(_ segments: [StyledSegment]) -> (text: String, hasMarkers: Bool) {
        guard segments.contains(where: { $0.style != nil }) else { return (segments.map(\.text).joined(), false) }
        var text = ""
        for segment in segments {
            let escaped = segment.text
                .replacingOccurrences(of: "&", with: "&amp;")
                .replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;")
            if let style = segment.style { text += "<s\(style + 1)>\(escaped)</s\(style + 1)>" } else { text += escaped }
        }
        return (text, true)
    }

    public static func decode(_ output: String, styleCount: Int) -> [StyledSegment]? {
        guard styleCount > 0 else { return [StyledSegment(text: output, style: nil)] }
        var segments: [StyledSegment] = []
        var open: Int?
        var buffer = ""
        func flush() {
            guard !buffer.isEmpty else { return }
            if let last = segments.last, last.style == open { segments[segments.count - 1].text += buffer }
            else { segments.append(StyledSegment(text: buffer, style: open)) }
            buffer = ""
        }
        var index = output.startIndex
        scan: while index < output.endIndex {
            let character = output[index]
            if character == "<" {
                guard let end = output[index...].firstIndex(of: ">") else { return nil }
                var name = output[output.index(after: index)..<end]
                let closing = name.hasPrefix("/")
                if closing { name = name.dropFirst() }
                guard name.hasPrefix("s"), let number = Int(name.dropFirst()), String(number) == name.dropFirst(),
                      (1...styleCount).contains(number) else { return nil }
                if closing {
                    guard open == number - 1 else { return nil }
                    flush()
                    open = nil
                } else {
                    guard open == nil else { return nil }
                    flush()
                    open = number - 1
                }
                index = output.index(after: end)
                continue
            }
            if character == "&" {
                for (entity, replacement) in entities where output[index...].hasPrefix(entity) {
                    buffer.append(replacement)
                    index = output.index(index, offsetBy: entity.count)
                    continue scan
                }
            }
            buffer.append(character)
            index = output.index(after: index)
        }
        guard open == nil else { return nil }
        flush()
        return segments
    }
}
