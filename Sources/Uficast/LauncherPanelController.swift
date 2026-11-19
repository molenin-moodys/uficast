import AppKit
import UficastCore

private final class LauncherPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class LauncherPanelController: NSObject, NSWindowDelegate, NSTextFieldDelegate, NSTextViewDelegate, NSTableViewDataSource, NSTableViewDelegate {
    private let panel: LauncherPanel
    private let field = NSTextField()
    private let table = NSTableView()
    private let emptyLabel = NSTextField(labelWithString: "Discovering applications…")
    private let icons = IconStore()
    private let hint = NSTextField(labelWithString: "↑↓ Select  ·  ↩ Open  ·  Tab Argument  ·  Esc Close")
    private let token = NSButton()
    private let argumentScroll = NSScrollView()
    private let argumentInput = NSTextView(frame: NSRect(x: 0, y: 0, width: 500, height: 38))
    private let placeholder = ClickThroughLabel(labelWithString: "")
    private var argumentCommand: ScriptCommand?
    private var previousQuery = ""
    private var isDismissing = false
    private var index = SearchIndex()
    private var results: [LauncherEntry] = []
    var usage: [String: UsageRecord] = [:]
    var onSelect: ((LauncherEntry) -> Void)?
    var onArgumentSelection: ((LauncherEntry) -> Void)?
    var onArgumentSubmit: ((String, String) -> Void)?
    var beforeShow: (() -> Void)?
    private var previousApplication: NSRunningApplication?
    private var localMonitor: Any?
    private var globalMonitor: Any?

    override init() {
        panel = LauncherPanel(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 470),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false
        )
        super.init()
        panel.delegate = self
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.title = "Uficast Launcher"
        let background = NSVisualEffectView()
        background.material = .popover
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 18
        background.layer?.masksToBounds = true
        panel.contentView = background

        field.font = .systemFont(ofSize: 26)
        field.placeholderString = "Search applications and commands…"
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.delegate = self
        field.setAccessibilityLabel("Search applications and commands")
        let line = NSBox()
        line.boxType = .separator
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        table.backgroundColor = .clear
        table.headerView = nil
        table.rowHeight = 56
        table.intercellSpacing = NSSize(width: 0, height: 4)
        table.style = .plain
        table.addTableColumn(NSTableColumn(identifier: NSUserInterfaceItemIdentifier("result")))
        table.delegate = self
        table.dataSource = self
        table.target = self
        table.doubleAction = #selector(activateSelected)
        table.setAccessibilityLabel("Search results")
        scroll.documentView = table
        icons.onLoad = { [weak self] in self?.table.reloadData() }
        emptyLabel.textColor = .secondaryLabelColor
        token.target = self
        token.action = #selector(returnToSearch)
        token.bezelStyle = .regularSquare
        token.isBordered = false
        token.font = .systemFont(ofSize: 25, weight: .regular)
        token.contentTintColor = .labelColor
        token.isHidden = true
        argumentScroll.documentView = argumentInput
        argumentScroll.drawsBackground = true
        argumentScroll.backgroundColor = .controlBackgroundColor
        argumentScroll.wantsLayer = true
        argumentScroll.layer?.cornerRadius = 8
        argumentScroll.isHidden = true
        argumentInput.isRichText = false
        argumentInput.importsGraphics = false
        argumentInput.allowsUndo = true
        argumentInput.font = .systemFont(ofSize: 25)
        argumentInput.textColor = .labelColor
        argumentInput.drawsBackground = false
        argumentInput.textContainerInset = NSSize(width: 6, height: 2)
        argumentInput.isVerticallyResizable = true
        argumentInput.isHorizontallyResizable = false
        argumentInput.autoresizingMask = [.width]
        argumentInput.textContainer?.widthTracksTextView = true
        argumentInput.isAutomaticQuoteSubstitutionEnabled = false
        argumentInput.isAutomaticDashSubstitutionEnabled = false
        argumentInput.isAutomaticTextReplacementEnabled = false
        argumentInput.isAutomaticSpellingCorrectionEnabled = false
        argumentInput.delegate = self
        placeholder.font = .systemFont(ofSize: 25)
        placeholder.textColor = .placeholderTextColor
        placeholder.isHidden = true
        hint.font = .systemFont(ofSize: 12)
        hint.textColor = .secondaryLabelColor
        for view in [field, line, scroll, emptyLabel, hint, token, argumentScroll, placeholder] {
            view.translatesAutoresizingMaskIntoConstraints = false
            background.addSubview(view)
        }
        NSLayoutConstraint.activate([
            field.leadingAnchor.constraint(equalTo: background.leadingAnchor, constant: 24),
            field.trailingAnchor.constraint(equalTo: background.trailingAnchor, constant: -24),
            field.topAnchor.constraint(equalTo: background.topAnchor, constant: 24),
            field.heightAnchor.constraint(equalToConstant: 38),
            line.topAnchor.constraint(equalTo: field.bottomAnchor, constant: 20),
            line.leadingAnchor.constraint(equalTo: background.leadingAnchor),
            line.trailingAnchor.constraint(equalTo: background.trailingAnchor),
            scroll.leadingAnchor.constraint(equalTo: background.leadingAnchor, constant: 12),
            scroll.trailingAnchor.constraint(equalTo: background.trailingAnchor, constant: -12),
            scroll.topAnchor.constraint(equalTo: line.bottomAnchor, constant: 12),
            scroll.bottomAnchor.constraint(equalTo: hint.topAnchor, constant: -12),
            emptyLabel.centerXAnchor.constraint(equalTo: scroll.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: scroll.centerYAnchor),
            hint.leadingAnchor.constraint(equalTo: field.leadingAnchor),
            hint.bottomAnchor.constraint(equalTo: background.bottomAnchor, constant: -16),
            token.leadingAnchor.constraint(equalTo: field.leadingAnchor),
            token.centerYAnchor.constraint(equalTo: field.centerYAnchor),
            token.widthAnchor.constraint(lessThanOrEqualToConstant: 220),
            argumentScroll.leadingAnchor.constraint(equalTo: token.trailingAnchor, constant: 12),
            argumentScroll.trailingAnchor.constraint(equalTo: field.trailingAnchor),
            argumentScroll.topAnchor.constraint(equalTo: field.topAnchor),
            argumentScroll.heightAnchor.constraint(equalTo: field.heightAnchor),
            placeholder.leadingAnchor.constraint(equalTo: argumentScroll.leadingAnchor, constant: 6),
            placeholder.trailingAnchor.constraint(lessThanOrEqualTo: argumentScroll.trailingAnchor, constant: -6),
            placeholder.centerYAnchor.constraint(equalTo: argumentScroll.centerYAnchor),
        ])
    }

    func setEntries(_ entries: [LauncherEntry], refreshing: Bool = false) {
        index = SearchIndex(entries: entries)
        reloadResults()
        if results.isEmpty && refreshing { emptyLabel.stringValue = "Discovering applications…" }
    }

    func renderPreview(to url: URL, argumentMode: Bool) throws {
        let command = ScriptCommand(name: "Kibana", alias: "k", path: "/tmp/kibana-example.py",
                                    requiresArgument: true, argumentPlaceholder: "log_stream")
        field.stringValue = "k"
        setEntries([command.entry,
                    LauncherEntry(id: "fixture-kitty", name: "kitty", fileURL: URL(fileURLWithPath: "/tmp/kitty.app")),
                    LauncherEntry(id: "fixture-keyboard", name: "Keyboard", fileURL: URL(fileURLWithPath: "/tmp/Keyboard.app"))])
        if argumentMode { enterArgument(command) }
        guard let view = panel.contentView else { return }
        try ViewPreview.write(view, to: url)
    }

    private func reloadResults(preserveSelection: Bool = true) {
        let previousID = preserveSelection && results.indices.contains(table.selectedRow) ? results[table.selectedRow].id : nil
        results = argumentCommand.map { [$0.entry] } ?? index.search(field.stringValue, usage: usage)
        table.reloadData()
        emptyLabel.isHidden = !results.isEmpty
        emptyLabel.stringValue = "No matching applications or commands"
        if !results.isEmpty {
            let selection = previousID.flatMap { id in results.firstIndex { $0.id == id } } ?? 0
            table.selectRowIndexes(IndexSet(integer: selection), byExtendingSelection: false)
        }
    }

    func controlTextDidChange(_ notification: Notification) { reloadResults(preserveSelection: false) }

    func numberOfRows(in tableView: NSTableView) -> Int { results.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let item = results[row]
        let cell = EntryRow()
        cell.configure(item, icon: icons.icon(for: item.fileURL))
        return cell
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? { RoundedResultRow() }

    @objc private func activateSelected() {
        if argumentCommand != nil { submitArgument(); return }
        guard results.indices.contains(table.selectedRow) else { return }
        onSelect?(results[table.selectedRow])
    }

    func toggle() {
        if panel.isVisible { dismiss() } else { show() }
    }

    func show() {
        guard !panel.isVisible else { return }
        beforeShow?()
        previousApplication = NSWorkspace.shared.frontmostApplication
        let point = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(point) } ?? NSScreen.main
        if let frame = screen?.visibleFrame {
            panel.setFrameOrigin(NSPoint(x: frame.midX - panel.frame.width / 2,
                                         y: frame.minY + frame.height * 0.65 - panel.frame.height / 2))
        }
        field.stringValue = ""
        reloadResults(preserveSelection: false)
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(field)
        startMonitors()
    }

    func dismiss(restoreFocus: Bool = true) {
        guard panel.isVisible, !isDismissing else { return }
        isDismissing = true
        defer { isDismissing = false }
        stopMonitors()
        panel.orderOut(nil)
        if restoreFocus, let previousApplication, !previousApplication.isTerminated,
           NSWorkspace.shared.frontmostApplication?.processIdentifier == ProcessInfo.processInfo.processIdentifier {
            previousApplication.activate()
        }
        previousApplication = nil
        clearArgument()
    }

    func windowDidResignKey(_ notification: Notification) { dismiss(restoreFocus: false) }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            dismiss()
            return true
        }
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            activateSelected()
            return true
        }
        if commandSelector == #selector(NSResponder.moveDown(_:)) || commandSelector == #selector(NSResponder.moveUp(_:)) {
            guard !results.isEmpty else { return true }
            let delta = commandSelector == #selector(NSResponder.moveDown(_:)) ? 1 : -1
            let row = max(0, min(results.count - 1, table.selectedRow + delta))
            table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            table.scrollRowToVisible(row)
            return true
        }
        if commandSelector == #selector(NSResponder.insertTab(_:)) {
            if results.indices.contains(table.selectedRow) { onArgumentSelection?(results[table.selectedRow]) }
            return true
        }
        return false
    }

    func enterArgument(_ command: ScriptCommand) {
        previousQuery = field.stringValue
        argumentCommand = command
        token.title = command.alias ?? command.name
        placeholder.stringValue = command.argumentPlaceholder
        argumentInput.string = ""
        argumentInput.undoManager?.removeAllActions()
        argumentInput.setAccessibilityLabel("Argument for \(command.name): \(command.argumentPlaceholder)")
        field.isHidden = true
        token.isHidden = false
        argumentScroll.isHidden = false
        placeholder.isHidden = false
        hint.stringValue = "Paste one argument  ·  ↩ Run  ·  Esc Back"
        hint.textColor = .secondaryLabelColor
        reloadResults()
        panel.makeFirstResponder(argumentInput)
    }

    func showInputError(_ message: String) {
        hint.stringValue = message
        hint.textColor = .systemRed
    }

    @objc private func returnToSearch() {
        clearArgument()
        field.stringValue = previousQuery
        reloadResults()
        panel.makeFirstResponder(field)
        if let editor = field.currentEditor() { editor.selectedRange = NSRange(location: field.stringValue.utf16.count, length: 0) }
    }

    private func clearArgument() {
        argumentCommand = nil
        argumentInput.string = ""
        argumentInput.undoManager?.removeAllActions()
        field.isHidden = false
        token.isHidden = true
        argumentScroll.isHidden = true
        placeholder.isHidden = true
        hint.stringValue = "↑↓ Select  ·  ↩ Open  ·  Tab Argument  ·  Esc Close"
        hint.textColor = .secondaryLabelColor
    }

    private func submitArgument() {
        guard let command = argumentCommand else { return }
        let value = argumentInput.string
        guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            showInputError("Enter an argument before running."); return
        }
        guard !value.contains("\0") else { showInputError("The argument contains a null character."); return }
        onArgumentSubmit?(command.id, value)
    }

    func textDidChange(_ notification: Notification) { placeholder.isHidden = !argumentInput.string.isEmpty }

    func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            returnToSearch(); return true
        }
        if commandSelector == #selector(NSResponder.deleteBackward(_:)), textView.string.isEmpty {
            returnToSearch(); return true
        }
        if commandSelector == #selector(NSResponder.insertNewline(_:)) { submitArgument(); return true }
        if commandSelector == #selector(NSResponder.insertTab(_:)) { return true }
        return false
    }

    private func startMonitors() {
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            MainActor.assumeIsolated {
                guard let self else { return }
                if event.window !== self.panel { self.dismiss(restoreFocus: false) }
            }
            return event
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.dismiss(restoreFocus: false) }
        }
    }

    private func stopMonitors() {
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        localMonitor = nil
        globalMonitor = nil
    }
}

private final class ClickThroughLabel: NSTextField {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}


@MainActor
private final class RoundedResultRow: NSTableRowView {
    override func drawSelection(in dirtyRect: NSRect) {
        NSColor.quaternaryLabelColor.setFill()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 3, dy: 1), xRadius: 12, yRadius: 12).fill()
    }
}

@MainActor
private final class EntryRow: NSTableCellView {
    private let icon = NSImageView()
    private let name = NSTextField(labelWithString: "")
    private let alias = NSTextField(labelWithString: "")
    private let kind = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        name.font = .systemFont(ofSize: 18, weight: .medium)
        name.lineBreakMode = .byTruncatingTail
        alias.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        alias.textColor = .secondaryLabelColor
        kind.font = .systemFont(ofSize: 14)
        kind.textColor = .secondaryLabelColor
        for view in [icon, name, alias, kind] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        name.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            icon.centerYAnchor.constraint(equalTo: centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 30), icon.heightAnchor.constraint(equalToConstant: 30),
            name.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 14),
            name.centerYAnchor.constraint(equalTo: centerYAnchor),
            alias.leadingAnchor.constraint(equalTo: name.trailingAnchor, constant: 12),
            alias.centerYAnchor.constraint(equalTo: centerYAnchor),
            alias.trailingAnchor.constraint(lessThanOrEqualTo: kind.leadingAnchor, constant: -16),
            kind.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            kind.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(_ entry: LauncherEntry, icon image: NSImage?) {
        icon.image = image
        name.stringValue = entry.name
        alias.stringValue = entry.alias ?? ""
        kind.stringValue = entry.kind == .application ? "Application" : "Script"
        setAccessibilityLabel("\(entry.name), \(kind.stringValue)")
    }
}
