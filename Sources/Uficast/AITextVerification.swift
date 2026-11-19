import AppKit
import UficastCore

/// Development-only native checks for AI text. Uses private pasteboards and fakes;
/// never runs a real AI command, reads the general clipboard or registers services.
@MainActor
enum AITextVerification {
    static func run() throws {
        try richTextRoundTrip()
        try panelControls()
    }

    private static func require(_ condition: Bool, _ message: String) throws {
        if !condition { throw ConfigError.invalid(message) }
    }

    static func privatePasteboard() -> NSPasteboard {
        NSPasteboard(name: NSPasteboard.Name("dev.ufian.Uficast.verify.\(UUID().uuidString)"))
    }

    static func sample() -> NSAttributedString {
        let body = NSFont.systemFont(ofSize: 13), bold = NSFont.boldSystemFont(ofSize: 13)
        let text = NSMutableAttributedString(string: "Please ", attributes: [.font: body])
        text.append(NSAttributedString(string: "review", attributes: [.font: bold]))
        text.append(NSAttributedString(string: " the ", attributes: [.font: body]))
        text.append(NSAttributedString(string: "file", attributes: [.font: body, .link: URL(string: "https://example.com")!]))
        return text
    }

    static func isBold(_ text: NSAttributedString, word: String) -> Bool {
        let range = (text.string as NSString).range(of: word)
        guard range.location != NSNotFound,
              let font = text.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont else { return false }
        return font.fontDescriptor.symbolicTraits.contains(.bold)
    }

    private static func richTextRoundTrip() throws {
        let source = sample()
        let rich = RichTextBridge.split(source, isRich: true)
        try require(rich.styles.count == 2, "Expected bold and link styles, got \(rich.styles.count)")
        let encoded = SpanMarkup.encode(rich.segments)
        try require(encoded.hasMarkers, "Styled text must be marked")
        guard let decoded = SpanMarkup.decode(encoded.text, styleCount: rich.styles.count) else {
            throw ConfigError.invalid("Own markers must decode")
        }
        let joined = RichTextBridge.join(decoded, from: rich)
        try require(joined.string == source.string, "Round trip changed the text")
        try require(isBold(joined, word: "review"), "Bold run lost")
        let link = (joined.string as NSString).range(of: "file")
        try require((joined.attribute(.link, at: link.location, effectiveRange: nil) as? URL)?.absoluteString == "https://example.com",
                    "Link lost")

        let board = privatePasteboard()
        defer { board.releaseGlobally() }
        RichTextBridge.write(joined, rich: true, to: board)
        try require(board.types?.contains(.rtf) == true && board.types?.contains(.string) == true, "Rich write needs RTF and plain text")
        try require(RichTextBridge.isRich(board) && RichTextBridge.read(board)?.string == source.string, "Rich read failed")
        RichTextBridge.write(NSAttributedString(string: "plain"), rich: false, to: board)
        try require(board.types?.contains(.rtf) != true, "A plain source must not gain RTF")
        try require(!RichTextBridge.isRich(board) && RichTextBridge.read(board)?.string == "plain", "Plain read failed")
        board.clearContents()
        try require(RichTextBridge.read(board) == nil, "An empty pasteboard must read as nil")
        let plain = RichTextBridge.split(NSAttributedString(string: "a < b"), isRich: false)
        try require(plain.styles.isEmpty && !plain.isRich && SpanMarkup.encode(plain.segments).text == "a < b", "Plain split must stay unmarked")
    }

    private static func panelControls() throws {
        let panel = AITextPanelController()
        panel.presentsWindow = false
        var confirms = 0, cancels = 0, retries = 0
        panel.onConfirm = { _ in confirms += 1 }
        panel.onCancel = { cancels += 1 }
        panel.onRetry = { retries += 1 }
        panel.showWorking(action: .rewrite, mode: .replace)
        try require(panel.hint == "Working…  ·  Esc Cancel" && panel.title == "Rewrite", "Working state")
        panel.performConfirm()
        try require(confirms == 0, "Enter while working must do nothing")
        panel.showResult(sample(), note: nil)
        try require(panel.hint == "↩ Replace  ·  Esc Cancel", "Replace hint")
        panel.performConfirm()
        try require(confirms == 1, "Enter on a result confirms once")
        panel.showWorking(action: .translate, mode: .copy)
        panel.showResult(NSAttributedString(string: "Готово"), note: "Formatting could not be kept.")
        try require(panel.hint == "↩ Copy  ·  Esc Cancel" && panel.note == "Formatting could not be kept.", "Copy hint and note")
        panel.showFailure("Boom")
        try require(panel.hint == "↩ Retry  ·  Esc Close", "Failure hint")
        panel.performConfirm()
        try require(retries == 1 && confirms == 1, "Enter on a failure retries")
        panel.showMessage("Copy text first.")
        try require(panel.hint == "Esc Close", "Message hint")
        panel.performConfirm()
        try require(retries == 1 && confirms == 1, "Enter on a message does nothing")
        panel.showWorking(action: .rewrite, mode: .replace)
        panel.showResult(sample(), note: nil)
        panel.switchToCopyMode(note: "Time ran out for replacing.")
        try require(panel.hint == "↩ Copy  ·  Esc Cancel" && panel.note == "Time ran out for replacing.", "Switch to copy mode")
        panel.performCancel()
        panel.performCancel()
        try require(cancels == 1, "Esc cancels once")
    }
}
