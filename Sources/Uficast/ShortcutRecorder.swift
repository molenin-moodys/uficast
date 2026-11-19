import AppKit
import SwiftUI
import UficastCore

struct ShortcutRecorder: NSViewRepresentable {
    var shortcut: GlobalShortcut?
    var onCapture: (GlobalShortcut?) -> Void
    var onBegin: () -> Void
    var onEnd: () -> Void
    func makeNSView(context: Context) -> ShortcutRecorderButton { ShortcutRecorderButton() }
    func updateNSView(_ view: ShortcutRecorderButton, context: Context) {
        view.shortcut = shortcut
        view.onCapture = onCapture
        view.onBegin = onBegin
        view.onEnd = onEnd
        view.refreshTitle()
    }
    static func dismantleNSView(_ view: ShortcutRecorderButton, coordinator: ()) { view.endRecording() }
}

final class ShortcutRecorderButton: NSButton {
    var shortcut: GlobalShortcut?
    var onCapture: ((GlobalShortcut?) -> Void)?
    var onBegin: (() -> Void)?
    var onEnd: (() -> Void)?
    private var recording = false
    override var acceptsFirstResponder: Bool { true }
    init() {
        super.init(frame: .zero)
        bezelStyle = .rounded
        target = self
        action = #selector(beginRecording)
        toolTip = "Click, then press a shortcut. Escape cancels; Delete clears."
        setAccessibilityLabel("Record application hotkey")
        refreshTitle()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func refreshTitle() { if !recording { title = shortcut?.display ?? "Record Hotkey" } }
    @objc private func beginRecording() {
        guard !recording else { return }
        recording = true
        onBegin?()
        window?.makeFirstResponder(self)
        title = "Press shortcut…"
    }
    func endRecording() {
        guard recording else { return }
        recording = false
        onEnd?()
        refreshTitle()
    }
    override func resignFirstResponder() -> Bool { endRecording(); return super.resignFirstResponder() }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard recording, window?.firstResponder === self else { return super.performKeyEquivalent(with: event) }
        capture(event)
        return true
    }
    override func keyDown(with event: NSEvent) { if recording { capture(event) } else { super.keyDown(with: event) } }
    private func capture(_ event: NSEvent) {
        if event.keyCode == 53 { endRecording(); return }
        if event.keyCode == 51 || event.keyCode == 117 { endRecording(); onCapture?(nil); return }
        var modifiers: UInt32 = 0
        for (flag, value): (NSEvent.ModifierFlags, UInt32) in [(.command, GlobalShortcut.command), (.control, GlobalShortcut.control),
                     (.option, GlobalShortcut.option), (.shift, GlobalShortcut.shift)] where event.modifierFlags.contains(flag) {
            modifiers |= value
        }
        let names: [UInt16: String] = [49: "Space", 36: "Return", 48: "Tab", 123: "←", 124: "→", 125: "↓", 126: "↑",
            122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8",
            101: "F9", 109: "F10", 103: "F11", 111: "F12", 105: "F13", 107: "F14", 113: "F15",
            106: "F16", 64: "F17", 79: "F18", 80: "F19", 90: "F20"]
        let shortcut = GlobalShortcut(keyCode: UInt32(event.keyCode), modifiers: modifiers,
                                      keyLabel: names[event.keyCode] ?? event.charactersIgnoringModifiers?.uppercased() ?? "Key \(event.keyCode)")
        guard (try? shortcut.validate()) != nil else { title = "Use ⌘, ⌃ or ⌥…"; return }
        endRecording()
        onCapture?(shortcut)
    }
}
