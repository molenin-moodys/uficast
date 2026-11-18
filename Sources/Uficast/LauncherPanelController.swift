import AppKit

private final class LauncherPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class LauncherPanelController: NSObject, NSWindowDelegate, NSTextFieldDelegate {
    private let panel: LauncherPanel
    private let field = NSTextField()
    private var previousApplication: NSRunningApplication?
    private var localMonitor: Any?
    private var globalMonitor: Any?

    override init() {
        panel = LauncherPanel(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 270),
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
        let heading = NSTextField(labelWithString: "Uficast")
        heading.font = .systemFont(ofSize: 18, weight: .semibold)
        let detail = NSTextField(wrappingLabelWithString: "The native launcher is ready. Application search is the next implementation stage.")
        detail.textColor = .secondaryLabelColor
        let hint = NSTextField(labelWithString: "⌘ Space to toggle  ·  Esc to close")
        hint.font = .systemFont(ofSize: 12)
        hint.textColor = .tertiaryLabelColor
        for view in [field, line, heading, detail, hint] {
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
            heading.leadingAnchor.constraint(equalTo: field.leadingAnchor),
            heading.topAnchor.constraint(equalTo: line.bottomAnchor, constant: 24),
            detail.leadingAnchor.constraint(equalTo: field.leadingAnchor),
            detail.trailingAnchor.constraint(equalTo: field.trailingAnchor),
            detail.topAnchor.constraint(equalTo: heading.bottomAnchor, constant: 10),
            hint.leadingAnchor.constraint(equalTo: field.leadingAnchor),
            hint.bottomAnchor.constraint(equalTo: background.bottomAnchor, constant: -20),
        ])
    }

    func toggle() {
        if panel.isVisible { dismiss() } else { show() }
    }

    func show() {
        guard !panel.isVisible else { return }
        previousApplication = NSWorkspace.shared.frontmostApplication
        let point = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(point) } ?? NSScreen.main
        if let frame = screen?.visibleFrame {
            panel.setFrameOrigin(NSPoint(x: frame.midX - panel.frame.width / 2,
                                         y: frame.minY + frame.height * 0.65 - panel.frame.height / 2))
        }
        field.stringValue = ""
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
