import AppKit
import SwiftUI
import UficastCore

struct AliasEditor: NSViewRepresentable {
    var entry: LauncherEntry
    var onCommit: (String) -> Bool

    func makeNSView(context: Context) -> AliasEditorView { AliasEditorView() }
    func updateNSView(_ view: AliasEditorView, context: Context) {
        view.onCommit = onCommit
        view.configure(entry: entry, enabled: context.environment.isEnabled)
    }
    static func dismantleNSView(_ view: AliasEditorView, coordinator: ()) { view.cancelEditing() }
}

final class AliasEditorView: NSView, NSTextFieldDelegate {
    private let label = AliasDisplayButton()
    private let field = NSTextField()
    private let clear = NSButton()
    private var representedID = ""
    private var value: String?
    private var editing = false
    var onCommit: ((String) -> Bool)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        label.isBordered = false
        label.alignment = .left
        label.lineBreakMode = .byTruncatingTail
        label.target = self
        label.action = #selector(beginEditing)
        label.onDoubleClick = { [weak self] in self?.beginEditing() }
        label.toolTip = "Double-click to edit. Enter saves; Escape cancels."
        field.isHidden = true
        field.placeholderString = "Alias"
        field.bezelStyle = .roundedBezel
        field.delegate = self
        clear.image = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: "Remove alias")
        clear.isBordered = false
        clear.contentTintColor = .secondaryLabelColor
        clear.target = self
        clear.action = #selector(removeAlias)
        clear.toolTip = "Remove alias"
        for child in [label, field, clear] {
            child.translatesAutoresizingMaskIntoConstraints = false
            addSubview(child)
        }
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor),
            label.trailingAnchor.constraint(equalTo: clear.leadingAnchor, constant: -4),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            field.leadingAnchor.constraint(equalTo: leadingAnchor),
            field.trailingAnchor.constraint(equalTo: clear.leadingAnchor, constant: -4),
            field.centerYAnchor.constraint(equalTo: centerYAnchor),
            clear.trailingAnchor.constraint(equalTo: trailingAnchor),
            clear.centerYAnchor.constraint(equalTo: centerYAnchor),
            clear.widthAnchor.constraint(equalToConstant: 18),
            clear.heightAnchor.constraint(equalToConstant: 18),
        ])
    }
    convenience init() { self.init(frame: .zero) }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(entry: LauncherEntry, enabled: Bool) {
        if representedID != entry.id || value != entry.alias || !enabled { cancelEditing() }
        representedID = entry.id
        value = entry.alias
        label.isEnabled = enabled
        field.isEnabled = enabled
        clear.isEnabled = enabled
        label.setAccessibilityLabel("Alias for \(entry.name)")
        field.setAccessibilityLabel("Edit alias for \(entry.name)")
        clear.setAccessibilityLabel("Remove alias for \(entry.name)")
        refresh()
    }

    private func refresh() {
        label.title = value ?? "Add Alias"
        label.contentTintColor = value == nil ? .secondaryLabelColor : .labelColor
        label.isHidden = editing
        field.isHidden = !editing
        clear.isHidden = value == nil
    }

    @objc private func beginEditing() {
        guard label.isEnabled, !editing, let window else { return }
        editing = true
        field.stringValue = value ?? ""
        refresh()
        guard window.makeFirstResponder(field) else { cancelEditing(); return }
        field.selectText(nil)
    }

    func cancelEditing() {
        guard editing else { return }
        editing = false
        field.abortEditing()
        refresh()
    }

    @objc private func removeAlias() {
        guard clear.isEnabled else { return }
        cancelEditing()
        _ = onCommit?("")
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        if selector == #selector(NSResponder.cancelOperation(_:)) {
            cancelEditing()
            window?.makeFirstResponder(label)
            return true
        }
        if selector == #selector(NSResponder.insertNewline(_:)) {
            let draft = field.stringValue
            // Reject invalid/duplicate aliases without discarding the draft.
            if onCommit?(draft) == true {
                cancelEditing()
                window?.makeFirstResponder(label)
            }
            return true
        }
        return false
    }
    func controlTextDidEndEditing(_ notification: Notification) { cancelEditing() }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow !== window {
            cancelEditing()
            NotificationCenter.default.removeObserver(self)
        }
        super.viewWillMove(toWindow: newWindow)
    }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        NotificationCenter.default.removeObserver(self)
        if let window {
            NotificationCenter.default.addObserver(self, selector: #selector(cancelForWindow), name: NSWindow.didResignKeyNotification, object: window)
            NotificationCenter.default.addObserver(self, selector: #selector(cancelForWindow), name: NSWindow.willCloseNotification, object: window)
        }
    }
    @objc private func cancelForWindow() { cancelEditing() }
}

private final class AliasDisplayButton: NSButton {
    var onDoubleClick: (() -> Void)?
    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        if let table = enclosingScrollView?.documentView as? NSTableView {
            let row = table.row(at: table.convert(event.locationInWindow, from: nil))
            if row >= 0 { table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false) }
        }
        if event.clickCount == 2 { onDoubleClick?() }
    }
}
