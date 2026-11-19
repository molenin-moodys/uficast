import AppKit

/// Escape first cancels an inline edit, then closes Settings on the next press.
class SettingsWindow: NSWindow {
    private func cancelInlineEdit(in view: NSView?) -> Bool {
        guard let view else { return false }
        if let alias = view as? AliasEditorView, alias.isEditing { alias.cancelEditing(); return true }
        if let recorder = view as? ShortcutRecorderButton, recorder.isRecording { recorder.endRecording(); return true }
        for child in view.subviews where cancelInlineEdit(in: child) { return true }
        return false
    }
    override func sendEvent(_ event: NSEvent) {
        let modifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])
        if event.type == .keyDown, event.keyCode == 53, modifiers.isEmpty, attachedSheet == nil {
            cancelOperation(nil)
            return
        }
        super.sendEvent(event)
    }
    override func cancelOperation(_ sender: Any?) {
        guard attachedSheet == nil else { super.cancelOperation(sender); return }
        if !cancelInlineEdit(in: contentView) { performClose(sender) }
    }
}
