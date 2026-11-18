import AppKit

@MainActor
final class AppController: NSObject, NSApplicationDelegate {
    private let hotkey = HotkeyService()
    private let launcher = LauncherPanelController()
    private var statusItem: NSStatusItem!
    private let statusLine = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private var settingsWindow: NSWindow?
    private let settingsStatus = NSTextField(wrappingLabelWithString: "")

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        installMainMenu()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName: "command.square", accessibilityDescription: "Uficast")
        let menu = NSMenu()
        menu.addItem(item("Open Launcher", #selector(openLauncher)))
        menu.addItem(item("Settings…", #selector(openSettings), key: ","))
        menu.addItem(.separator())
        menu.addItem(statusLine)
        menu.addItem(item("Retry Shortcut", #selector(retryShortcut)))
        menu.addItem(.separator())
        menu.addItem(item("Quit Uficast", #selector(quit), key: "q"))
        statusItem.menu = menu
        hotkey.onToggle = { [weak self] in self?.launcher.toggle() }
        hotkey.onStatusChange = { [weak self] in self?.updateStatus() }
        hotkey.start()
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(retryShortcut), name: NSWorkspace.didWakeNotification, object: nil
        )
        if CommandLine.arguments.contains("--show") { launcher.show() }
    }

    func applicationWillTerminate(_ notification: Notification) { hotkey.stop() }

    @objc private func openLauncher() { launcher.show() }
    @objc private func quit() { NSApp.terminate(nil) }
    @objc private func retryShortcut() { hotkey.start() }

    private func updateStatus() {
        statusLine.title = hotkey.status
        settingsStatus.stringValue = hotkey.status
    }

    @objc private func openSettings() {
        launcher.dismiss(restoreFocus: false)
        if settingsWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 620, height: 330),
                                  styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
            window.title = "Uficast Settings"
            window.isReleasedWhenClosed = false
            let title = NSTextField(labelWithString: "General")
            title.font = .systemFont(ofSize: 25, weight: .semibold)
            let shortcut = NSTextField(labelWithString: "Launcher shortcut: Command + Space")
            let retry = NSButton(title: "Retry Shortcut", target: self, action: #selector(retryShortcut))
            let info = NSTextField(wrappingLabelWithString: "No Accessibility or Input Monitoring access is required. Release Spotlight's and Raycast's matching shortcuts before testing. A successful registration does not prove a system shortcut is free. Commands and aliases will be added in the next stages.")
            info.textColor = .secondaryLabelColor
            let stack = NSStackView(views: [title, shortcut, settingsStatus, retry, info])
            stack.orientation = .vertical
            stack.alignment = .leading
            stack.spacing = 16
            stack.translatesAutoresizingMaskIntoConstraints = false
            window.contentView!.addSubview(stack)
            NSLayoutConstraint.activate([
                stack.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor, constant: 28),
                stack.trailingAnchor.constraint(equalTo: window.contentView!.trailingAnchor, constant: -28),
                stack.topAnchor.constraint(equalTo: window.contentView!.topAnchor, constant: 24),
            ])
            settingsWindow = window
            window.center()
        }
        updateStatus()
        NSApp.activate()
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    private func item(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let result = NSMenuItem(title: title, action: action, keyEquivalent: key)
        result.target = self
        return result
    }

    private func installMainMenu() {
        let main = NSMenu()
        let app = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(item("Settings…", #selector(openSettings), key: ","))
        appMenu.addItem(item("Quit Uficast", #selector(quit), key: "q"))
        app.submenu = appMenu
        main.addItem(app)
        let edit = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        for (title, action, key) in [
            ("Undo", "undo:", "z"), ("Redo", "redo:", "Z"),
            ("Cut", "cut:", "x"), ("Copy", "copy:", "c"),
            ("Paste", "paste:", "v"), ("Select All", "selectAll:", "a"),
        ] {
            let menuItem = NSMenuItem(title: title, action: NSSelectorFromString(action), keyEquivalent: key.lowercased())
            if title == "Redo" { menuItem.keyEquivalentModifierMask = [.command, .shift] }
            editMenu.addItem(menuItem)
        }
        edit.submenu = editMenu
        main.addItem(edit)
        NSApp.mainMenu = main
    }
}
