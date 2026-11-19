import AppKit
import UficastCore

/// Exercises actual table controls and the field editor using fixture state.
@MainActor
enum AliasEditorVerification {
    static func run() throws {
        let model = ViewPreview.settingsModel()
        model.selectedID = nil
        var saves = 0
        model.onSave = { model.configuration = $0; saves += 1 }
        let controller = SettingsWindowController(model: model)
        guard let window = controller.window, let content = window.contentView else {
            throw ConfigError.invalid("Could not construct fixture Settings.")
        }
        func layout() {
            content.layoutSubtreeIfNeeded()
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
            content.layoutSubtreeIfNeeded()
        }
        func editors(_ view: NSView) -> [AliasEditorView] {
            (view as? AliasEditorView).map { [$0] } ?? view.subviews.flatMap(editors)
        }
        func controls(_ name: String) throws -> (AliasEditorView, NSButton, NSTextField, NSButton) {
            layout()
            for editor in editors(content) {
                guard let field = editor.subviews.compactMap({ $0 as? NSTextField }).first,
                      field.accessibilityLabel() == "Edit alias for \(name)",
                      let label = editor.subviews.compactMap({ $0 as? NSButton }).first(where: { $0.toolTip != "Remove alias" }),
                      let clear = editor.subviews.compactMap({ $0 as? NSButton }).first(where: { $0.toolTip == "Remove alias" }) else { continue }
                return (editor, label, field, clear)
            }
            throw ConfigError.invalid("Missing alias controls for \(name).")
        }
        func click(_ label: NSButton, count: Int) throws {
            let point = label.convert(NSPoint(x: label.bounds.midX, y: label.bounds.midY), to: nil)
            guard let event = NSEvent.mouseEvent(with: .leftMouseDown, location: point, modifierFlags: [],
                timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: count, clickCount: count, pressure: 1) else {
                throw ConfigError.invalid("Could not create alias click.")
            }
            label.mouseDown(with: event)
        }
        func type(_ text: String, into field: NSTextField) throws {
            guard let editor = field.currentEditor() as? NSTextView else { throw ConfigError.invalid("Alias field has no native editor.") }
            editor.selectAll(nil)
            editor.insertText(text, replacementRange: editor.selectedRange())
        }
        func key(_ code: UInt16, field: NSTextField) throws {
            guard let editor = field.currentEditor() as? NSTextView,
                  let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                    windowNumber: window.windowNumber, context: nil, characters: code == 36 ? "\r" : "\u{1b}",
                    charactersIgnoringModifiers: code == 36 ? "\r" : "\u{1b}", isARepeat: false, keyCode: code) else {
                throw ConfigError.invalid("Could not create alias key.")
            }
            editor.keyDown(with: event)
        }
        func check(_ condition: Bool, _ message: String) throws {
            if !condition { throw ConfigError.invalid(message) }
        }
        var (_, label, field, clear) = try controls("Terminal")
        try click(label, count: 1)
        try check(field.isHidden && saves == 0, "Single click edited or saved an alias.")
        try click(label, count: 2)
        (_, label, field, clear) = try controls("Terminal")
        try type("discarded", into: field)
        try key(53, field: field)
        try check(field.isHidden && saves == 0 && model.configuration.applications["app:preview-terminal"]?.alias == "term",
                  "Escape failed to cancel an assigned alias without saving.")
        try click(label, count: 2)
        try type("notes", into: field)
        try key(36, field: field)
        try check(!field.isHidden && saves == 0, "Duplicate alias was accepted or its draft discarded.")
        try type("terminal2", into: field)
        try key(36, field: field)
        try check(saves == 1 && model.configuration.applications["app:preview-terminal"]?.alias == "terminal2"
                  && model.configuration.applications["app:preview-terminal"]?.hotkey != nil, "Enter did not save exactly once while preserving the hotkey.")
        (_, label, field, clear) = try controls("Terminal")
        clear.performClick(nil)
        try check(saves == 2 && model.configuration.applications["app:preview-terminal"]?.alias == nil, "The cross did not remove the alias.")
        (_, label, field, clear) = try controls("Terminal")
        try check(clear.isHidden && label.title == "Add Alias", "An unassigned alias still has a removal control.")
        try click(label, count: 2)
        try type("discarded", into: field)
        NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: window)
        try check(field.isHidden && saves == 2, "Window deactivation saved a draft.")
        try click(label, count: 2)
        try type("discarded", into: field)
        model.filter = "Scripts"
        layout()
        try check(saves == 2, "Filtering out a cell saved an unfinished draft.")
        (_, label, field, _) = try controls("Search Example")
        try click(label, count: 2)
        try type("find", into: field)
        try key(36, field: field)
        try check(saves == 3 && model.configuration.scripts[0].alias == "find"
                  && model.configuration.scripts[0].requiresArgument, "Script alias editing changed execution settings or failed to save.")
    }
}
