import AppKit
import UficastCore

/// Native responder/table regression check with in-memory public fixtures only.
@MainActor
enum ShortcutRecorderVerification {
    static func run() throws {
        let model = ViewPreview.settingsModel()
        var saves: [Configuration] = []
        var begins = 0
        var ends = 0
        model.onSave = { saves.append($0) }
        model.onBeginShortcutRecording = { begins += 1 }
        model.onEndShortcutRecording = { ends += 1 }
        let controller = SettingsWindowController(model: model)
        guard let window = controller.window, let content = window.contentView else {
            throw ConfigError.invalid("Could not construct fixture Settings.")
        }
        content.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        content.layoutSubtreeIfNeeded()
        func buttons(_ view: NSView) -> [ShortcutRecorderButton] {
            (view as? ShortcutRecorderButton).map { [$0] } ?? view.subviews.flatMap(buttons)
        }
        guard var cell = buttons(content).first(where: { $0.requiresDoubleClick && $0.shortcut != nil }) else {
            throw ConfigError.invalid("The application Hotkey column has no inline recorder.")
        }
        let original = cell.shortcut
        func check(_ condition: Bool, _ message: String) throws {
            if !condition { throw ConfigError.invalid(message) }
        }
        func click(_ count: Int) throws {
            let point = cell.convert(NSPoint(x: cell.bounds.midX, y: cell.bounds.midY), to: nil)
            guard let event = NSEvent.mouseEvent(with: .leftMouseDown, location: point, modifierFlags: [],
                timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: count,
                clickCount: count, pressure: 1) else { throw ConfigError.invalid("Could not create fixture click.") }
            cell.mouseDown(with: event)
        }
        func key(_ code: UInt16, flags: NSEvent.ModifierFlags = [], text: String = "") throws {
            guard let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags,
                timestamp: 0, windowNumber: window.windowNumber, context: nil, characters: text,
                charactersIgnoringModifiers: text, isARepeat: false, keyCode: code) else {
                throw ConfigError.invalid("Could not create fixture key.")
            }
            if !cell.performKeyEquivalent(with: event) { cell.keyDown(with: event) }
        }

        try click(1)
        try check(begins == 0 && saves.isEmpty, "Single click began recording or saved a shortcut.")
        try click(2)
        try check(begins == 1 && cell.title == "Press shortcut…" && cell.isBordered,
                  "Double click did not open the inline recording field.")
        try key(0, text: "a")
        try check(saves.isEmpty && ends == 0, "An invalid bare key was saved.")
        try key(53)
        try check(saves.isEmpty && ends == 1 && cell.shortcut == original && cell.title == original?.display,
                  "Escape saved a change or failed to restore the original shortcut.")

        try click(2)
        try key(45, flags: [.control, .option], text: "n")
        try check(saves.count == 1 && saves[0].applications["app:preview-terminal"]?.hotkey?.keyCode == 45 && ends == 2,
                  "A valid shortcut was not committed exactly once to the correct app.")
        try click(2)
        try key(51)
        try check(saves.count == 2 && saves[1].applications["app:preview-terminal"]?.hotkey == nil && ends == 3,
                  "Delete did not explicitly clear the shortcut.")
        try click(2)
        window.makeFirstResponder(nil)
        try check(ends == 4 && saves.count == 2, "Focus loss failed to cancel without saving.")
        try click(2)
        NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: window)
        try check(begins == ends && saves.count == 2, "Window deactivation left recording active.")
        try click(2)
        cell.removeFromSuperview()
        try check(begins == ends && saves.count == 2, "Removing a table cell left recording active.")
        guard let emptyCell = buttons(content).first(where: { $0.requiresDoubleClick && $0.shortcut == nil }) else {
            throw ConfigError.invalid("Unassigned application hotkey cells are missing.")
        }
        cell = emptyCell
        try click(1)
        try check(begins == ends, "An unassigned cell began recording on a single click.")
        try click(2)
        try key(53)
        try check(begins == ends && saves.count == 2 && cell.shortcut == nil && cell.title == "Add Hotkey",
                  "Escape changed an unassigned hotkey.")
    }
}
