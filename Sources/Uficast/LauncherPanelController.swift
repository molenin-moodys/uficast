import AppKit
import UficastCore

private final class LauncherPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class LauncherPanelController: NSObject, NSWindowDelegate, NSTextFieldDelegate, NSTableViewDataSource, NSTableViewDelegate {
    private let panel: LauncherPanel
    private let field = NSTextField()
    private let table = NSTableView()
    private let emptyLabel = NSTextField(labelWithString: "Discovering applications…")
    private let icons = IconStore()
    private var index = SearchIndex()
    private var results: [LauncherEntry] = []
    var usage: [String: UsageRecord] = [:]
    var onSelect: ((LauncherEntry) -> Void)?
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
        background.material = .hudWindow
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
        let hint = NSTextField(labelWithString: "↑↓ Select  ·  ↩ Open  ·  ⌘ Space Toggle  ·  Esc Close")
        hint.font = .systemFont(ofSize: 12)
        hint.textColor = .secondaryLabelColor
        for view in [field, line, scroll, emptyLabel, hint] {
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
        ])
    }

    func setEntries(_ entries: [LauncherEntry], refreshing: Bool = false) {
        index = SearchIndex(entries: entries)
        reloadResults()
        if results.isEmpty && refreshing { emptyLabel.stringValue = "Discovering applications…" }
    }

    private func reloadResults() {
        let previousID = results.indices.contains(table.selectedRow) ? results[table.selectedRow].id : nil
        results = index.search(field.stringValue, usage: usage)
        table.reloadData()
        emptyLabel.isHidden = !results.isEmpty
        emptyLabel.stringValue = "No matching applications or commands"
        if !results.isEmpty {
            let selection = previousID.flatMap { id in results.firstIndex { $0.id == id } } ?? 0
            table.selectRowIndexes(IndexSet(integer: selection), byExtendingSelection: false)
        }
    }

    func controlTextDidChange(_ notification: Notification) { reloadResults() }

    func numberOfRows(in tableView: NSTableView) -> Int { results.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let item = results[row]
        let cell = EntryRow()
        cell.configure(item, icon: icons.icon(for: item.fileURL))
        return cell
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? { RoundedResultRow() }

    @objc private func activateSelected() {
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
        reloadResults()
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(field)
        startMonitors()
    }

    func dismiss(restoreFocus: Bool = true) {
        guard panel.isVisible else { return }
        stopMonitors()
        panel.orderOut(nil)
        if restoreFocus, let previousApplication, !previousApplication.isTerminated,
           NSWorkspace.shared.frontmostApplication?.processIdentifier == ProcessInfo.processInfo.processIdentifier {
            previousApplication.activate()
        }
        previousApplication = nil
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
