import AppKit
import UficastCore

/// Development-only native checks for AI text. Uses private pasteboards and fakes;
/// never runs a real AI command, reads the general clipboard or registers services.
@MainActor
enum AITextVerification {
    static func run() throws {
        try richTextRoundTrip()
        try panelControls()
        try coordinatorFlows()
        try reviewRegressions()
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

    /// Scripted runner: answers in order after a delay; cancel makes a pending run throw.
    private actor FakeRunner: AITextRunning {
        private var answers: [Result<String, AITextError>]
        private let delay: Duration
        private var generation = 0
        private(set) var calls = 0
        private(set) var cancels = 0
        init(_ answers: [Result<String, AITextError>], delay: Duration = .milliseconds(50)) {
            self.answers = answers
            self.delay = delay
        }
        func run(command: String, prompt: String, timeout: Double) async throws -> String {
            calls += 1
            let started = generation
            let answer = answers.isEmpty ? .success("ok") : answers.removeFirst()
            try? await Task.sleep(for: delay)
            guard generation == started else { throw AITextError.cancelled }
            return try answer.get()
        }
        func cancel() { cancels += 1; generation += 1 }
    }

    private static func spin(_ seconds: Double = 2, until condition: () -> Bool) {
        let deadline = Date().addingTimeInterval(seconds)
        while !condition(), Date() < deadline { RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.01)) }
    }

    /// Fires `action` from inside the coordinator's nested service loop once `ready` holds.
    private static func whenReady(_ ready: @escaping @MainActor () -> Bool, _ action: @escaping @MainActor () -> Void) -> Timer {
        Timer.scheduledTimer(withTimeInterval: 0.02, repeats: true) { timer in
            let fired = MainActor.assumeIsolated { () -> Bool in
                guard ready() else { return false }
                action()
                return true
            }
            if fired { timer.invalidate() }
        }
    }

    private static func make(_ runner: FakeRunner, deadline: TimeInterval = 5) -> (AITextCoordinator, AITextPanelController, NSPasteboard) {
        let panel = AITextPanelController()
        panel.presentsWindow = false
        let general = privatePasteboard()
        return (AITextCoordinator(panel: panel, runner: runner, general: general, serviceDeadline: deadline, timeout: 5), panel, general)
    }

    private static func coordinatorFlows() throws {
        let replace = "↩ Replace  ·  Esc Cancel", copy = "↩ Copy  ·  Esc Cancel"
        do { // Empty clipboard and an image-only clipboard never run the command.
            let runner = FakeRunner([])
            let (coordinator, panel, general) = make(runner)
            general.clearContents()
            coordinator.runFromClipboard(.rewrite)
            try require(panel.shownText == "Copy text first." && panel.hint == "Esc Close", "Empty clipboard message")
            general.clearContents()
            let pixel = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1, pixelsHigh: 1, bitsPerSample: 8, samplesPerPixel: 4,
                                         hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
            general.setData(pixel?.tiffRepresentation ?? Data(), forType: .tiff)
            coordinator.runFromClipboard(.translate)
            try require(panel.shownText == "Copy text first.", "Image-only clipboard message")
            spin(0.2) { false }
            try require(Task.awaitValue { await runner.calls } == 0, "No command may run without text")
        }
        do { // Clipboard rewrite: Enter copies the result.
            let (coordinator, panel, general) = make(FakeRunner([.success("We were here.")]))
            general.clearContents()
            general.setString("we was here", forType: .string)
            coordinator.runFromClipboard(.rewrite)
            spin { panel.hint == copy }
            try require(panel.shownText == "We were here.", "Clipboard result shown")
            panel.performConfirm()
            try require(general.string(forType: .string) == "We were here." && !panel.isVisible, "Enter copies and closes")
        }
        do { // Esc while working cancels; the late result neither shows nor writes.
            let runner = FakeRunner([.success("late")], delay: .milliseconds(300))
            let (coordinator, panel, general) = make(runner)
            general.clearContents()
            general.setString("source", forType: .string)
            coordinator.runFromClipboard(.rewrite)
            panel.performCancel()
            spin(0.6) { false }
            try require(Task.awaitValue { await runner.cancels } >= 1, "Esc cancels the command")
            try require(!panel.isVisible && general.string(forType: .string) == "source", "Late result ignored")
        }
        do { // Failure, then an explicit retry.
            let runner = FakeRunner([.failure(.failed("Boom")), .success("second")])
            let (coordinator, panel, general) = make(runner)
            general.clearContents()
            general.setString("text", forType: .string)
            coordinator.runFromClipboard(.translate)
            spin { panel.hint == "↩ Retry  ·  Esc Close" }
            try require(panel.shownText == "Boom", "Failure text shown")
            panel.performConfirm()
            spin { panel.hint == copy }
            try require(panel.shownText == "second" && Task.awaitValue { await runner.calls } == 2, "Retry runs again")
        }
        do { // Service with a rich source: Enter replaces with formatting and copies.
            let (coordinator, panel, general) = make(FakeRunner([.success("Kindly <s1>review</s1> the <s2>file</s2>")]))
            let service = privatePasteboard()
            defer { service.releaseGlobally() }
            RichTextBridge.write(sample(), rich: true, to: service)
            let timer = whenReady({ panel.hint == replace }) { panel.performConfirm() }
            var message: NSString = ""
            coordinator.rewriteText(service, userData: "", error: &message)
            timer.invalidate()
            guard let replaced = RichTextBridge.read(service) else { throw ConfigError.invalid("Service got no result") }
            try require(replaced.string == "Kindly review the file" && isBold(replaced, word: "review"), "Replacement keeps bold")
            try require(general.string(forType: .string) == "Kindly review the file", "Replacement also copied")
        }
        do { // Service cancel leaves the selection unchanged.
            let (coordinator, panel, _) = make(FakeRunner([.success("never")], delay: .milliseconds(300)))
            let service = privatePasteboard()
            defer { service.releaseGlobally() }
            RichTextBridge.write(NSAttributedString(string: "hello"), rich: false, to: service)
            let timer = whenReady({ panel.hint == "Working…  ·  Esc Cancel" }) { panel.performCancel() }
            var message: NSString = ""
            coordinator.translateText(service, userData: "", error: &message)
            timer.invalidate()
            try require(service.string(forType: .string) == "hello", "Cancelled service must not write")
        }
        do { // Deadline with a result shown: return without writing, switch to copy mode.
            let (coordinator, panel, general) = make(FakeRunner([.success("Done.")]), deadline: 0.5)
            let service = privatePasteboard()
            defer { service.releaseGlobally() }
            general.clearContents()
            RichTextBridge.write(NSAttributedString(string: "done"), rich: false, to: service)
            let start = Date()
            var message: NSString = ""
            coordinator.rewriteText(service, userData: "", error: &message)
            try require(Date().timeIntervalSince(start) < 1, "Service must return at its deadline")
            try require(service.string(forType: .string) == "done", "Deadline must not write")
            try require(panel.hint == copy && panel.note == "Time ran out for replacing.", "Deadline switches to copy mode")
            panel.performConfirm()
            try require(general.string(forType: .string) == "Done." && service.string(forType: .string) == "done", "Later Enter only copies")
        }
        do { // Broken markers fall back to the base style with a note.
            let (coordinator, panel, general) = make(FakeRunner([.success("Kindly <s3>review</s3>")]))
            let service = privatePasteboard()
            defer { service.releaseGlobally() }
            RichTextBridge.write(sample(), rich: true, to: service)
            var note = ""
            let timer = whenReady({ panel.hint == replace }) { note = panel.note; panel.performConfirm() }
            var message: NSString = ""
            coordinator.rewriteText(service, userData: "", error: &message)
            timer.invalidate()
            try require(note == "Formatting could not be kept.", "Fallback note")
            try require(service.string(forType: .string) == "Kindly review" && general.string(forType: .string) == "Kindly review",
                        "Fallback writes text without markers")
        }
    }
}

extension AITextVerification {
    /// Findings from the final review; each check failed before its fix.
    fileprivate static func reviewRegressions() throws {
        func check(_ condition: Bool, _ message: String) throws { if !condition { throw ConfigError.invalid(message) } }
        let replace = "↩ Replace  ·  Esc Cancel"
        do { // A Service delivered from a main-queue block must still receive the result.
            let panel = AITextPanelController()
            panel.presentsWindow = false
            let general = privatePasteboard()
            let coordinator = AITextCoordinator(panel: panel, runner: FakeRunnerForReview(answer: "Fixed."), general: general,
                                                serviceDeadline: 3, timeout: 5)
            let service = privatePasteboard()
            defer { service.releaseGlobally() }
            RichTextBridge.write(NSAttributedString(string: "fix me"), rich: false, to: service)
            let timer = Timer.scheduledTimer(withTimeInterval: 0.02, repeats: true) { timer in
                let fired = MainActor.assumeIsolated { () -> Bool in
                    guard panel.hint == replace else { return false }
                    panel.performConfirm()
                    return true
                }
                if fired { timer.invalidate() }
            }
            var done = false
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    var message: NSString = ""
                    coordinator.rewriteText(service, userData: "", error: &message)
                    done = true
                }
            }
            let deadline = Date().addingTimeInterval(5)
            while !done, Date() < deadline { RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.01)) }
            timer.invalidate()
            try check(service.string(forType: .string) == "Fixed.", "Service called from a main-queue block never got its result")
        }
        do { // An attachment-only selection (an image) is not text.
            let pixel = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1, pixelsHigh: 1, bitsPerSample: 8, samplesPerPixel: 4,
                                         hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
            let png = pixel.representation(using: .png, properties: [:])!.base64EncodedString()
            let board = privatePasteboard()
            defer { board.releaseGlobally() }
            board.clearContents()
            board.setData(Data("<img src=\"data:image/png;base64,\(png)\">".utf8), forType: .html)
            try check(RichTextBridge.read(board) == nil, "An image-only HTML selection must read as no text")
        }
        do { // An answer that is empty after cleaning is a failure, not an empty result.
            let panel = AITextPanelController()
            panel.presentsWindow = false
            let general = privatePasteboard()
            let coordinator = AITextCoordinator(panel: panel, runner: FakeRunnerForReview(answer: "<text></text>"), general: general,
                                                serviceDeadline: 3, timeout: 5)
            general.clearContents()
            general.setString("text", forType: .string)
            coordinator.runFromClipboard(.rewrite)
            let deadline = Date().addingTimeInterval(2)
            while panel.hint == "Working…  ·  Esc Cancel", Date() < deadline { RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.01)) }
            try check(panel.hint == "↩ Retry  ·  Esc Close" && panel.shownText == AITextError.emptyOutput.localizedDescription,
                      "An empty cleaned answer must be shown as a failure")
        }
        do { // Pasteboard HTML is UTF-8 even without a charset declaration.
            let board = privatePasteboard()
            defer { board.releaseGlobally() }
            board.clearContents()
            board.setData(Data("<p>Привет, мир</p>".utf8), forType: .html)
            try check(RichTextBridge.read(board)?.string.trimmingCharacters(in: .whitespacesAndNewlines) == "Привет, мир",
                      "HTML without a charset must decode as UTF-8")
        }
    }

    private actor FakeRunnerForReview: AITextRunning {
        let answer: String
        init(answer: String) { self.answer = answer }
        func run(command: String, prompt: String, timeout: Double) async throws -> String {
            try? await Task.sleep(for: .milliseconds(50))
            return answer
        }
        func cancel() {}
    }
}

private extension Task where Failure == Never {
    /// Reads an actor value from the verification's synchronous main-thread code.
    @MainActor static func awaitValue(_ body: @escaping @Sendable () async -> Success) -> Success {
        var value: Success?
        Task<Void, Never> { @MainActor in value = await body() }
        while value == nil { RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.01)) }
        return value!
    }
}

