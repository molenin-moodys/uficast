import AppKit
import UficastCore
import UniformTypeIdentifiers

@MainActor
final class AppController: NSObject, NSApplicationDelegate {
    private let hotkey = HotkeyService()
    private let launcher = LauncherPanelController()
    private let catalog = CatalogService()
    private let actionStatus = NSMenuItem(title: "No recent errors", action: nil, keyEquivalent: "")
    private var statusItem: NSStatusItem!
    private let statusLine = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let configStore = ConfigStore()
    private let settingsModel = SettingsModel()
    private lazy var settings = SettingsWindowController(model: settingsModel)

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        installMainMenu()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName: "command.square", accessibilityDescription: "Uficast")
        let menu = NSMenu()
        menu.addItem(item("Open Launcher", #selector(openLauncher)))
        menu.addItem(item("Settings…", #selector(openSettings), key: ","))
        menu.addItem(item("Refresh Applications", #selector(refreshCatalog)))
        menu.addItem(actionStatus)
        menu.addItem(.separator())
        menu.addItem(statusLine)
        menu.addItem(item("Retry Shortcut", #selector(retryShortcut)))
        menu.addItem(.separator())
        menu.addItem(item("Quit Uficast", #selector(quit), key: "q"))
        statusItem.menu = menu
        hotkey.onToggle = { [weak self] in self?.launcher.toggle() }
        hotkey.onStatusChange = { [weak self] in self?.updateStatus() }
        hotkey.start()
        catalog.onChange = { [weak self] in
            guard let self else { return }
            self.updateEntries()
        }
        launcher.beforeShow = { [weak self] in self?.catalog.refreshIfStale() }
        launcher.onSelect = { [weak self] entry in self?.launch(entry) }
        settingsModel.onSave = { [weak self] in self?.saveConfiguration($0) }
        settingsModel.onRefresh = { [weak self] in self?.catalog.refresh() }
        settingsModel.onRetryShortcut = { [weak self] in self?.hotkey.start() }
        settingsModel.onAddApp = { [weak self] in self?.addApplication() }
        settingsModel.onImport = { [weak self] in self?.importConfiguration() }
        settingsModel.onExport = { [weak self] in self?.exportConfiguration() }
        settingsModel.onRestore = { [weak self] in self?.restoreConfiguration() }
        loadConfiguration()
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(retryShortcut), name: NSWorkspace.didWakeNotification, object: nil
        )
        if CommandLine.arguments.contains("--show") { launcher.show() }
    }

    func applicationWillTerminate(_ notification: Notification) { hotkey.stop() }

    @objc private func openLauncher() { launcher.show() }
    @objc private func quit() { NSApp.terminate(nil) }
    @objc private func retryShortcut() { hotkey.start() }
    @objc private func refreshCatalog() { catalog.refresh() }

    private func launch(_ entry: LauncherEntry) {
        guard entry.kind == .application else { return }
        launcher.dismiss(restoreFocus: false)
        Task { @MainActor in
            do {
                _ = try await NSWorkspace.shared.openApplication(at: entry.fileURL, configuration: .init())
                var usage = launcher.usage[entry.id] ?? UsageRecord()
                usage.count += 1
                usage.lastUsed = .now
                launcher.usage[entry.id] = usage
                actionStatus.title = "Opened \(entry.name)"
            } catch {
                actionStatus.title = "Could not open \(entry.name): \(error.localizedDescription)"
            }
        }
    }

    private func updateStatus() {
        statusLine.title = hotkey.status
        settingsModel.shortcutStatus = hotkey.status
    }

    @objc private func openSettings() {
        launcher.dismiss(restoreFocus: false)
        settings.present()
    }

    private func updateEntries() {
        settingsModel.catalogEntries = catalog.entries
        launcher.setEntries(settingsModel.configuration.entries(catalog: catalog.entries), refreshing: catalog.isRefreshing)
    }

    private func applyConfiguration(_ configuration: Configuration) {
        settingsModel.configuration = configuration
        let roots = configuration.applicationRoots.map(Configuration.fileURL)
        if roots != catalog.roots || catalog.entries.isEmpty { catalog.roots = roots; catalog.refresh() }
        updateEntries()
    }

    private func loadConfiguration() {
        Task {
            do {
                applyConfiguration(try await configStore.load())
                settingsModel.status = "Settings ready."
            } catch {
                settingsModel.isReadOnly = true
                settingsModel.status = "Could not load settings: \(error.localizedDescription) Original file unchanged; defaults are in use."
                applyConfiguration(Configuration())
            }
            settingsModel.isBusy = false
        }
    }

    private func saveConfiguration(_ configuration: Configuration) {
        guard !settingsModel.isBusy, !settingsModel.isReadOnly else { return }
        settingsModel.isBusy = true
        settingsModel.status = "Saving…"
        Task {
            do {
                try await configStore.save(configuration)
                applyConfiguration(configuration)
                settingsModel.status = "Saved."
            } catch { settingsModel.status = error.localizedDescription }
            settingsModel.isBusy = false
        }
    }

    private func addApplication() {
        let picker = NSOpenPanel()
        picker.title = "Add Application"
        picker.allowedContentTypes = [.applicationBundle]
        picker.canChooseDirectories = false
        guard picker.runModal() == .OK, let url = picker.url else { return }
        var config = settingsModel.configuration
        if !config.applicationRoots.contains(url.path) { config.applicationRoots.append(url.path) }
        saveConfiguration(config)
    }

    private func importConfiguration() {
        let picker = NSOpenPanel()
        picker.title = "Import Uficast Configuration"
        picker.allowedContentTypes = [.json]
        guard picker.runModal() == .OK, let url = picker.url else { return }
        do { saveConfiguration(try Configuration.decode(Data(contentsOf: url))) }
        catch { settingsModel.status = "Import failed: \(error.localizedDescription)" }
    }

    private func exportConfiguration() {
        let picker = NSSavePanel()
        picker.title = "Export Uficast Configuration"
        picker.nameFieldStringValue = "uficast-config.json"
        picker.allowedContentTypes = [.json]
        guard picker.runModal() == .OK, let url = picker.url else { return }
        do {
            try settingsModel.configuration.encoded().write(to: url, options: .atomic)
            settingsModel.status = "Configuration exported. File paths may need updating on another Mac."
        } catch { settingsModel.status = "Export failed: \(error.localizedDescription)" }
    }

    private func restoreConfiguration() {
        guard !settingsModel.isBusy else { return }
        settingsModel.isBusy = true
        Task {
            do {
                applyConfiguration(try await configStore.restoreBackup())
                settingsModel.isReadOnly = false
                settingsModel.status = "Backup restored. The previous file was preserved."
            } catch { settingsModel.status = "Recovery failed: \(error.localizedDescription)" }
            settingsModel.isBusy = false
        }
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
