import AppKit
import UficastCore

private final class AITextPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Read-only, selectable result view that turns Return/Enter and Esc into decisions.
private final class AIResultTextView: NSTextView {
    var onReturn: (() -> Void)?
    var onEscape: (() -> Void)?
    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 36, 76: onReturn?()
        case 53: onEscape?()
        default: super.keyDown(with: event)
        }
    }
    override func cancelOperation(_ sender: Any?) { onEscape?() }
}

/// Shows an AI text request: working, result, failure or message. It looks like the
/// launcher but keeps its own state, so launcher runs and AI requests never mix.
@MainActor
final class AITextPanelController: NSObject, NSWindowDelegate {
    enum Mode { case replace, copy }
    private enum State { case hidden, working, result, failure, message }

    var onConfirm: ((NSAttributedString) -> Void)?
    var onCancel: (() -> Void)?
    var onRetry: (() -> Void)?
    /// Verification turns this off so checks never put a window on screen.
    var presentsWindow = true

    private let panel: AITextPanel
    private let titleLabel = NSTextField(labelWithString: "")
    private let textView = AIResultTextView(frame: NSRect(x: 0, y: 0, width: 660, height: 200))
    private let noteLabel = NSTextField(labelWithString: "")
    private let hintLabel = NSTextField(labelWithString: "")
    private let spinner = NSProgressIndicator()
    private var state = State.hidden
    private var mode = Mode.copy
    private var result = NSAttributedString()

    var isVisible: Bool { state != .hidden }
    var hint: String { hintLabel.stringValue }
    var note: String { noteLabel.stringValue }
    var title: String { titleLabel.stringValue }

    override init() {
        panel = AITextPanel(contentRect: NSRect(x: 0, y: 0, width: 720, height: 340),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        super.init()
        panel.delegate = self
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.title = "Uficast AI Text"
        let background = NSVisualEffectView()
        background.material = .popover
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 18
        background.layer?.masksToBounds = true
        panel.contentView = background

        titleLabel.font = .systemFont(ofSize: 25)
        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isDisplayedWhenStopped = false
        let line = NSBox()
        line.boxType = .separator
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.documentView = textView
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = true
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 4, height: 6)
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.setAccessibilityLabel("AI text result")
        textView.onReturn = { [weak self] in self?.performConfirm() }
        textView.onEscape = { [weak self] in self?.performCancel() }
        for label in [noteLabel, hintLabel] {
            label.font = .systemFont(ofSize: 12)
            label.textColor = .secondaryLabelColor
            label.lineBreakMode = .byTruncatingTail
        }
        for view in [titleLabel, spinner, line, scroll, noteLabel, hintLabel] {
            view.translatesAutoresizingMaskIntoConstraints = false
            background.addSubview(view)
        }
        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: background.leadingAnchor, constant: 24),
            titleLabel.topAnchor.constraint(equalTo: background.topAnchor, constant: 22),
            spinner.leadingAnchor.constraint(equalTo: titleLabel.trailingAnchor, constant: 12),
            spinner.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            line.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 16),
            line.leadingAnchor.constraint(equalTo: background.leadingAnchor),
            line.trailingAnchor.constraint(equalTo: background.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: line.bottomAnchor, constant: 12),
            scroll.leadingAnchor.constraint(equalTo: background.leadingAnchor, constant: 20),
            scroll.trailingAnchor.constraint(equalTo: background.trailingAnchor, constant: -20),
            scroll.bottomAnchor.constraint(equalTo: noteLabel.topAnchor, constant: -8),
            noteLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            noteLabel.trailingAnchor.constraint(lessThanOrEqualTo: background.trailingAnchor, constant: -24),
            noteLabel.bottomAnchor.constraint(equalTo: hintLabel.topAnchor, constant: -6),
            hintLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            hintLabel.trailingAnchor.constraint(lessThanOrEqualTo: background.trailingAnchor, constant: -24),
            hintLabel.bottomAnchor.constraint(equalTo: background.bottomAnchor, constant: -16),
        ])
    }

    func showWorking(action: AITextAction, mode: Mode) {
        self.mode = mode
        result = NSAttributedString()
        titleLabel.stringValue = action.title
        display(.working, text: NSAttributedString(string: "Working…", attributes: secondaryText), note: "",
                hint: "Working…  ·  Esc Cancel")
        spinner.startAnimation(nil)
    }

    func showResult(_ text: NSAttributedString, note: String?) {
        result = text
        display(.result, text: Self.displayCopy(text), note: note ?? "", hint: resultHint)
    }

    func showFailure(_ message: String) {
        display(.failure, text: NSAttributedString(string: message, attributes: [.font: NSFont.systemFont(ofSize: 13), .foregroundColor: NSColor.systemRed]),
                note: "", hint: "↩ Retry  ·  Esc Close")
    }

    func showMessage(_ message: String) {
        titleLabel.stringValue = "Uficast"
        display(.message, text: NSAttributedString(string: message, attributes: secondaryText), note: "", hint: "Esc Close")
    }

    func switchToCopyMode(note: String) {
        mode = .copy
        noteLabel.stringValue = note
        if state == .result { hintLabel.stringValue = resultHint }
    }

    func performConfirm() {
        switch state {
        case .result: onConfirm?(result)
        case .failure: onRetry?()
        case .hidden, .working, .message: break
        }
    }

    /// Esc, an outside click or losing key: reports once, then hides.
    func performCancel() {
        guard state != .hidden else { return }
        hide()
        onCancel?()
    }

    func dismiss() { hide() }

    func windowDidResignKey(_ notification: Notification) { performCancel() }

    private var resultHint: String { mode == .replace ? "↩ Replace  ·  Esc Cancel" : "↩ Copy  ·  Esc Cancel" }
    private var secondaryText: [NSAttributedString.Key: Any] {
        [.font: NSFont.systemFont(ofSize: 15), .foregroundColor: NSColor.secondaryLabelColor]
    }

    private func display(_ state: State, text: NSAttributedString, note: String, hint: String) {
        let wasHidden = self.state == .hidden
        self.state = state
        spinner.stopAnimation(nil)
        textView.textStorage?.setAttributedString(text)
        noteLabel.stringValue = note
        hintLabel.stringValue = hint
        guard presentsWindow else { return }
        if wasHidden, let frame = LauncherPanelController.targetScreen(for: NSWorkspace.shared.frontmostApplication)?.visibleFrame {
            panel.setFrameOrigin(NSPoint(x: frame.midX - panel.frame.width / 2,
                                         y: frame.minY + frame.height * 0.6 - panel.frame.height / 2))
        }
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(textView)
    }

    private func hide() {
        state = .hidden
        spinner.stopAnimation(nil)
        if panel.isVisible { panel.orderOut(nil) }
    }

    /// Source text colors can be unreadable on the panel's material; the copy that is
    /// shown drops them, while the inserted or copied result keeps every attribute.
    private static func displayCopy(_ text: NSAttributedString) -> NSAttributedString {
        let copy = NSMutableAttributedString(attributedString: text)
        let range = NSRange(location: 0, length: copy.length)
        copy.removeAttribute(.foregroundColor, range: range)
        copy.removeAttribute(.backgroundColor, range: range)
        copy.addAttribute(.foregroundColor, value: NSColor.labelColor, range: range)
        return copy
    }
}
