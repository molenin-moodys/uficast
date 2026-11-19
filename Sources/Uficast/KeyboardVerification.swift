import AppKit
import UficastCore

@MainActor
enum KeyboardVerification {
    private final class Probe: NSObject {
        var settings = 0
        var finds = 0
        @objc func openSettings() { settings += 1 }
        @objc func find() { finds += 1 }
        @objc func quit() {}
    }
    private final class Window: SettingsWindow {
        var closeRequests = 0
        override func performClose(_ sender: Any?) { closeRequests += 1 }
    }

    static func run() throws {
        let probe = Probe()
        let menu = AppMenu.make(target: probe, settings: #selector(Probe.openSettings), quit: #selector(Probe.quit), find: #selector(Probe.find))
        let window = Window(contentRect: NSRect(x: 0, y: 0, width: 400, height: 120),
                            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let content = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 120))
        window.contentView = content
        func key(_ code: UInt16, _ text: String, _ flags: NSEvent.ModifierFlags = []) throws -> NSEvent {
            guard let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags,
                timestamp: 0, windowNumber: window.windowNumber, context: nil, characters: text,
                charactersIgnoringModifiers: text, isARepeat: false, keyCode: code) else { throw ConfigError.invalid("Could not create fixture key.") }
            return event
        }
        func check(_ value: Bool, _ message: String) throws { if !value { throw ConfigError.invalid(message) } }
        for (code, text): (UInt16, String) in [(43, ","), (35, "p")] {
            try check(menu.performKeyEquivalent(with: key(code, text, .command)), "A Settings shortcut was not handled.")
        }
        try check(probe.settings == 2, "Cmd+, and Cmd+P did not both open Settings.")
        try check(menu.performKeyEquivalent(with: key(3, "f", .command)) && probe.finds == 1, "Cmd+F did not invoke Find.")
        let alias = AliasEditorView(frame: NSRect(x: 20, y: 20, width: 180, height: 24))
        var commits = 0
        alias.onCommit = { _ in commits += 1; return true }
        alias.configure(entry: ViewPreview.applications[0], enabled: true)
        content.addSubview(alias)
        alias.layoutSubtreeIfNeeded()
        let label = try alias.subviews.compactMap { $0 as? NSButton }.first(where: { $0.toolTip != "Remove alias" })
            .unwrap("Missing fixture alias label.")
        label.performClick(nil)
        try check(alias.isEditing, "Alias editing did not start.")
        window.sendEvent(try key(53, "\u{1b}"))
        try check(!alias.isEditing && commits == 0 && window.closeRequests == 0, "Escape closed Settings or saved instead of cancelling an alias edit.")
        let recorder = ShortcutRecorderButton()
        recorder.frame = NSRect(x: 20, y: 60, width: 180, height: 24)
        var captured: GlobalShortcut?
        recorder.onCapture = { captured = $0 }
        content.addSubview(recorder)
        recorder.performClick(nil)
        window.sendEvent(try key(53, "\u{1b}"))
        try check(!recorder.isRecording && captured == nil && window.closeRequests == 0, "Escape failed to cancel hotkey recording first.")
        recorder.performClick(nil)
        let cmdP = try key(35, "p", .command)
        try check(window.performKeyEquivalent(with: cmdP) && captured?.keyCode == 35 && probe.settings == 2,
                  "An app shortcut stole Cmd+P from the active hotkey recorder.")
        let search = NSTextField(frame: NSRect(x: 220, y: 20, width: 150, height: 24))
        content.addSubview(search)
        window.makeFirstResponder(search)
        window.sendEvent(try key(53, "\u{1b}"))
        try check(window.closeRequests == 1, "Escape in an ordinary Settings field did not close its window.")
    }
}

private extension Optional {
    func unwrap(_ message: String) throws -> Wrapped {
        guard let value = self else { throw ConfigError.invalid(message) }
        return value
    }
}
