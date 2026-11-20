import AppKit
import UficastCore

/// Serves both AI text entry points: a clipboard hotkey and the macOS Services.
/// Exactly one request is active; anything that finishes for an older request is ignored.
@MainActor
final class AITextCoordinator: NSObject {
    private struct Request {
        var id: UUID
        let action: AITextAction
        let source: RichText
        var mode: AITextPanelController.Mode
        var service: NSPasteboard?
        var note: String?
    }
    private enum ServiceDecision { case confirm(NSAttributedString, rich: Bool), cancel }

    var command = AITextPreferences.defaultCommand
    /// Called before the panel appears, so the launcher can hide.
    var beforePresent: (() -> Void)?

    private let panel: AITextPanelController
    private let runner: AITextRunning
    private let general: NSPasteboard
    private let serviceDeadline: TimeInterval
    private let timeout: Double
    private var current: Request?
    private var isServing = false
    private var serviceDecision: ServiceDecision?

    init(panel: AITextPanelController, runner: AITextRunning, general: NSPasteboard = .general,
         serviceDeadline: TimeInterval = 85, timeout: Double = 60) {
        self.panel = panel
        self.runner = runner
        self.general = general
        self.serviceDeadline = serviceDeadline
        self.timeout = timeout
        super.init()
        panel.onConfirm = { [weak self] in self?.confirm($0) }
        panel.onCancel = { [weak self] in self?.cancelCurrent() }
        panel.onRetry = { [weak self] in self?.retry() }
    }

    func runFromClipboard(_ action: AITextAction) {
        guard let text = RichTextBridge.read(general) else {
            cancelCurrent()
            beforePresent?()
            panel.showMessage("Copy text first.")
            return
        }
        start(action, text: text, rich: RichTextBridge.isRich(general), mode: .copy, service: nil)
    }

    @objc func rewriteText(_ pboard: NSPasteboard, userData: String, error: AutoreleasingUnsafeMutablePointer<NSString>) {
        serve(.rewrite, pboard, error)
    }

    @objc func translateText(_ pboard: NSPasteboard, userData: String, error: AutoreleasingUnsafeMutablePointer<NSString>) {
        serve(.translate, pboard, error)
    }

    /// The requesting app waits for this method to return. Keep handling events until the
    /// owner decides or the deadline passes; only Enter writes back.
    private func serve(_ action: AITextAction, _ pboard: NSPasteboard, _ error: AutoreleasingUnsafeMutablePointer<NSString>) {
        guard !isServing else { error.pointee = "Uficast is already working on a request."; return }
        guard let text = RichTextBridge.read(pboard) else { error.pointee = "No text was selected."; return }
        isServing = true
        serviceDecision = nil
        defer { isServing = false; serviceDecision = nil }
        start(action, text: text, rich: RichTextBridge.isRich(pboard), mode: .replace, service: pboard)
        let deadline = Date().addingTimeInterval(serviceDeadline)
        while serviceDecision == nil, Date() < deadline {
            if let event = NSApp.nextEvent(matching: .any, until: Date().addingTimeInterval(0.05), inMode: .default, dequeue: true) {
                NSApp.sendEvent(event)
            }
        }
        switch serviceDecision {
        case .confirm(let result, let rich)?:
            RichTextBridge.write(result, rich: rich, to: pboard)
            RichTextBridge.write(result, rich: rich, to: general)
        case .cancel?:
            break
        case nil where current?.service === pboard:
            // Time ran out: keep the request, but Enter can only copy now.
            current?.service = nil
            current?.mode = .copy
            current?.note = "Time ran out for replacing."
            panel.switchToCopyMode(note: "Time ran out for replacing.")
        case nil:
            break
        }
    }

    private func start(_ action: AITextAction, text: NSAttributedString, rich: Bool,
                       mode: AITextPanelController.Mode, service: NSPasteboard?) {
        cancelCurrent()
        current = Request(id: UUID(), action: action, source: RichTextBridge.split(text, isRich: rich),
                          mode: mode, service: service, note: nil)
        beforePresent?()
        panel.showWorking(action: action, mode: mode)
        launch()
    }

    private func retry() {
        guard var request = current else { return }
        request.id = UUID()
        current = request
        panel.showWorking(action: request.action, mode: request.mode)
        if let note = request.note { panel.switchToCopyMode(note: note) }
        launch()
    }

    private func launch() {
        guard let request = current else { return }
        let encoded = SpanMarkup.encode(request.source.segments)
        let prompt = AITextPrompt.build(action: request.action, text: encoded.text, hasMarkers: encoded.hasMarkers)
        let styleCount = encoded.hasMarkers ? request.source.styles.count : 0
        let (runner, command, timeout, id) = (self.runner, self.command, self.timeout, request.id)
        // AppKit may deliver a Service request from a main-queue block. Inside that block the
        // main queue (and with it MainActor jobs) is not serviced by our nested event loop, so
        // the result comes back as a run-loop block, which every run of the default mode performs.
        Task.detached { [weak self] in
            let outcome: Result<String, Error>
            do { outcome = .success(try await runner.run(command: command, prompt: prompt, timeout: timeout)) }
            catch { outcome = .failure(error) }
            RunLoop.main.perform(inModes: [.default, .eventTracking, .modalPanel]) {
                MainActor.assumeIsolated {
                    switch outcome {
                    case .success(let output): self?.finish(id, output: output, styleCount: styleCount)
                    case .failure(let error): self?.fail(id, error)
                    }
                }
            }
        }
    }

    private func finish(_ id: UUID, output: String, styleCount: Int) {
        guard let request = current, request.id == id else { return }
        let cleaned = AITextPrompt.clean(output)
        var note = request.note
        let segments: [StyledSegment]
        if let decoded = SpanMarkup.decode(cleaned, styleCount: styleCount) {
            segments = decoded
        } else {
            segments = [StyledSegment(text: Self.withoutMarkers(cleaned), style: nil)]
            note = "Formatting could not be kept."
        }
        // Never offer an empty result: Enter in a Service would delete the selection.
        guard segments.contains(where: { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
            panel.showFailure(AITextError.emptyOutput.localizedDescription)
            return
        }
        panel.showResult(RichTextBridge.join(segments, from: request.source), note: note)
    }

    private func fail(_ id: UUID, _ error: Error) {
        guard current?.id == id, (error as? AITextError) != .cancelled else { return }
        panel.showFailure(error.localizedDescription)
    }

    private func confirm(_ result: NSAttributedString) {
        guard let request = current else { return }
        if request.service != nil, request.mode == .replace {
            serviceDecision = .confirm(result, rich: request.source.isRich)
        } else {
            RichTextBridge.write(result, rich: request.source.isRich, to: general)
        }
        current = nil
        panel.dismiss()
    }

    private func cancelCurrent() {
        guard let request = current else { return }
        if request.service != nil { serviceDecision = .cancel }
        current = nil
        panel.dismiss()
        Task { [runner] in await runner.cancel() }
    }

    /// Base-style fallback: drop every marker tag and restore escaped characters.
    private static func withoutMarkers(_ text: String) -> String {
        text.replacingOccurrences(of: #"</?s[0-9]+>"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&amp;", with: "&")
    }
}
