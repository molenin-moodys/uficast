import AppKit
import UficastCore
import UniformTypeIdentifiers

@MainActor
final class AppController: NSObject, NSApplicationDelegate, NSMenuItemValidation {
    private let hotkey = HotkeyService()
    private let launcher = LauncherPanelController()
    private let catalog = CatalogService()
    private let actionStatus = NSMenuItem(title: "No recent errors", action: nil, keyEquivalent: "")
    private var statusItem: NSStatusItem!
    private let statusLine = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let configStore = ConfigStore()
    private let scriptRunner = ScriptRunner()
    private let keyboard = KeyboardRemapService()
    private let devices = KeyboardDeviceObserver()
    private let keepAwake = KeepAwakeService()
    private let keepAwakeToggle = NSMenuItem(title: "Keep Awake", action: nil, keyEquivalent: "")
    private let keepAwakeDetail = NSMenuItem(title: "Automatic sleep allowed", action: nil, keyEquivalent: "")
    private var powerRevision: UInt64 = 0
    private var restoringPower = true
    private let savedPowerKey = "keepAwakeSession.v1"
    private var didLoadConfiguration = false
    private var didReconcileKeyboard = false
    private var isTerminating = false
    private var cancelledScripts: Set<String> = []
    private let settingsModel = SettingsModel()
    private lazy var settings = SettingsWindowController(model: settingsModel)

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        installMainMenu()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName: "zzz", accessibilityDescription: "Uficast — Keep Awake off")
        let menu = NSMenu()
        menu.addItem(item("Open Launcher", #selector(openLauncher)))
        menu.addItem(item("Settings…", #selector(openSettings), key: ","))
        menu.addItem(item("Refresh Applications", #selector(refreshCatalog)))
        menu.addItem(actionStatus)
        menu.addItem(.separator())
        keepAwakeToggle.target = self
        keepAwakeToggle.action = #selector(toggleKeepAwake)
        menu.addItem(keepAwakeToggle)
        menu.addItem(keepAwakeDetail)
        let durationItem = NSMenuItem(title: "Keep Awake For", action: nil, keyEquivalent: "")
        let durations = NSMenu()
        for (title, seconds) in [("30 Minutes", 1800), ("1 Hour", 3600), ("Until Stopped", 0)] {
            let choice = item(title, #selector(keepAwakeFor(_:)))
            choice.representedObject = NSNumber(value: seconds)
            durations.addItem(choice)
        }
        durationItem.submenu = durations
        menu.addItem(durationItem)
        menu.addItem(.separator())
        menu.addItem(statusLine)
        menu.addItem(item("Retry Shortcut", #selector(retryShortcut)))
        menu.addItem(.separator())
        menu.addItem(item("Quit Uficast", #selector(quit), key: "q"))
        statusItem.menu = menu
        hotkey.onToggle = { [weak self] in self?.launcher.toggle() }
        hotkey.onAppToggle = { [weak self] in self?.toggleApplication($0) }
        hotkey.onStatusChange = { [weak self] in self?.updateStatus() }
        hotkey.start()
        catalog.onChange = { [weak self] in
            guard let self else { return }
            self.updateEntries()
        }
        launcher.beforeShow = { [weak self] in self?.catalog.refreshIfStale() }
        launcher.onSelect = { [weak self] entry in self?.launch(entry) }
        launcher.onArgumentSelection = { [weak self] entry in self?.selectArgumentCommand(entry) }
        launcher.onArgumentSubmit = { [weak self] id, argument in self?.runScript(id: id, argument: argument) }
        launcher.onOpenSettings = { [weak self] in self?.openSettings() }
        settingsModel.onSave = { [weak self] in self?.saveConfiguration($0) }
        settingsModel.onRefresh = { [weak self] in self?.catalog.refresh() }
        settingsModel.onRetryShortcut = { [weak self] in self?.hotkey.start() }
        settingsModel.onAddApp = { [weak self] in self?.addApplication() }
        settingsModel.onAddScriptFolder = { [weak self] in self?.addScriptFolder() }
        settingsModel.onRefreshScripts = { [weak self] in self?.refreshScriptFolders() }
        settingsModel.onImport = { [weak self] in self?.importConfiguration() }
        settingsModel.onExport = { [weak self] in self?.exportConfiguration() }
        settingsModel.onRestore = { [weak self] in self?.restoreConfiguration() }
        settingsModel.onCancelScript = { [weak self] id in
            self?.cancelledScripts.insert(id)
            Task { await self?.scriptRunner.cancel(id) }
        }
        settingsModel.onSetCapsLock = { [weak self] enabled in
            guard let self else { return }
            var config = self.settingsModel.configuration
            config.capsLockToF19Enabled = enabled
            self.saveConfiguration(config)
        }
        settingsModel.onCheckKeyboard = { [weak self] in self?.checkKeyboard() }
        settingsModel.onSetLoginItem = { [weak self] in self?.setLoginItem($0) }
        settingsModel.onBeginShortcutRecording = { [weak self] in self?.hotkey.stop() }
        settingsModel.onEndShortcutRecording = { [weak self] in self?.hotkey.start() }
        settingsModel.onSetKeepAwake = { [weak self] in self?.changeKeepAwake(enabled: $0) }
        settingsModel.onKeepAwakeFor = { [weak self] in self?.changeKeepAwake(enabled: true, seconds: $0) }
        let savedPower = UserDefaults.standard.data(forKey: savedPowerKey)
            .flatMap { try? JSONDecoder().decode(SavedKeepAwakeSession.self, from: $0) } ?? SavedKeepAwakeSession()
        settingsModel.isKeepAwakeBusy = true
        Task {
            await keepAwake.setObserver { [weak self] state, error in
                Task { @MainActor [weak self] in self?.updateKeepAwake(state, error: error) }
            }
            guard !isTerminating else { return }
            var restoreError: String?
            do { try await keepAwake.restore(savedPower) }
            catch { restoreError = error.localizedDescription }
            guard !isTerminating else { return }
            let state = await keepAwake.state
            restoringPower = false
            updateKeepAwake(state, error: restoreError)
            settingsModel.isKeepAwakeBusy = false
        }
        updateLoginItemStatus()
        devices.onChange = { [weak self] in self?.reconcileKeyboard(reapplyOwned: true) }
        devices.start()
        loadConfiguration()
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(resumeServices), name: NSWorkspace.didWakeNotification, object: nil
        )
        launcher.show()
    }

    func applicationWillTerminate(_ notification: Notification) { hotkey.stop(); devices.stop() }

    func applicationDidBecomeActive(_ notification: Notification) { updateLoginItemStatus() }
    func applicationDidHide(_ notification: Notification) { launcher.dismiss(restoreFocus: false) }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        launcher.show()
        return false
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !isTerminating else { return .terminateLater }
        isTerminating = true
        devices.stop()
        Task {
            await scriptRunner.cancelAll()
            await scriptRunner.waitUntilIdle()
            await keepAwake.waitUntilIdle()
            if !restoringPower { rememberPower(await keepAwake.state) }
            _ = try? await keepAwake.disable()
            await keyboard.waitUntilIdle()
            if !settingsModel.isReadOnly { _ = try? await keyboard.reconcile(enabled: false) }
            NSApp.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    @objc private func openLauncher() { launcher.show() }
    func revealLauncher() { launcher.show() }
    @objc private func quit() { NSApp.terminate(nil) }
    @objc private func retryShortcut() { hotkey.start() }
    @objc private func refreshCatalog() { catalog.refresh() }
    @objc private func resumeServices() { hotkey.start(); reconcileKeyboard(reapplyOwned: true) }

    @objc private func toggleKeepAwake() { changeKeepAwake(enabled: !settingsModel.keepAwakeActive) }
    @objc private func keepAwakeFor(_ sender: NSMenuItem) {
        let seconds = (sender.representedObject as? NSNumber)?.doubleValue ?? 0
        changeKeepAwake(enabled: true, seconds: seconds > 0 ? seconds : nil)
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(focusSearch) || menuItem.action == #selector(openSettings) {
            return NSApp.keyWindow?.sheetParent == nil && NSApp.keyWindow?.attachedSheet == nil
        }
        if menuItem.action == #selector(toggleKeepAwake) || menuItem.action == #selector(keepAwakeFor(_:)) {
            return !settingsModel.isKeepAwakeBusy && !isTerminating
        }
        return true
    }

    private func changeKeepAwake(enabled: Bool, seconds: TimeInterval? = nil) {
        guard !settingsModel.isKeepAwakeBusy, !isTerminating else { return }
        settingsModel.isKeepAwakeBusy = true
        Task {
            do {
                if enabled { try await keepAwake.enable(for: seconds) }
                else { try await keepAwake.disable() }
                actionStatus.title = enabled ? "Keep Awake enabled." : "Automatic idle sleep is allowed."
            } catch {
                settingsModel.status = error.localizedDescription
                actionStatus.title = "Keep Awake failed: \(error.localizedDescription)"
            }
            settingsModel.isKeepAwakeBusy = false
        }
    }

    private func updateKeepAwake(_ state: KeepAwakeState, error: String?) {
        guard state.revision >= powerRevision else { return }
        powerRevision = state.revision
        if !restoringPower && !isTerminating { rememberPower(state) }
        settingsModel.keepAwakeActive = state.isActive
        keepAwakeToggle.state = state.isActive ? .on : .off
        let detail: String
        if state.isActive {
            detail = state.expiresAt.map { "Awake until \($0.formatted(date: .omitted, time: .shortened))" } ?? "Awake until stopped"
        } else { detail = "Automatic idle sleep is allowed." }
        keepAwakeDetail.title = detail
        settingsModel.keepAwakeStatus = error.map { "\(detail) \($0)" } ?? detail
        statusItem.button?.image = NSImage(systemSymbolName: state.isActive ? "cup.and.saucer.fill" : "zzz",
                                          accessibilityDescription: state.isActive ? "Uficast — Keep Awake on" : "Uficast — Keep Awake off")
    }

    private func rememberPower(_ state: KeepAwakeState) {
        if let data = try? JSONEncoder().encode(SavedKeepAwakeSession(state: state)) {
            UserDefaults.standard.set(data, forKey: savedPowerKey)
        }
    }

    private func reconcileKeyboard(reapplyOwned: Bool = false) {
        guard didLoadConfiguration, !isTerminating, !settingsModel.isReadOnly, !settingsModel.isKeyboardBusy else { return }
        settingsModel.isKeyboardBusy = true
        let enabled = settingsModel.configuration.capsLockToF19Enabled
        Task {
            do {
                settingsModel.keyboardStatus = try await keyboard.reconcile(enabled: enabled, reapplyOwned: reapplyOwned)
                if enabled { settingsModel.keyboardStatus += ModifierMappingDiagnostics.warning }
            }
            catch { settingsModel.keyboardStatus = error.localizedDescription }
            settingsModel.isKeyboardBusy = false
        }
    }

    private func checkKeyboard() {
        guard !settingsModel.isKeyboardBusy else { return }
        settingsModel.isKeyboardBusy = true
        Task {
            do { settingsModel.keyboardStatus = try await keyboard.checkStatus() + ModifierMappingDiagnostics.warning }
            catch { settingsModel.keyboardStatus = error.localizedDescription }
            settingsModel.isKeyboardBusy = false
        }
    }

    private func updateLoginItemStatus() {
        let status = LoginItemService.status()
        settingsModel.loginItemRegistered = status.registered
        settingsModel.loginItemStatus = status.message
    }

    private func setLoginItem(_ enabled: Bool) {
        guard !settingsModel.isLoginItemBusy else { return }
        settingsModel.isLoginItemBusy = true
        Task {
            do { try await LoginItemService.setEnabled(enabled) }
            catch { settingsModel.status = "Login-item update failed: \(error.localizedDescription)" }
            updateLoginItemStatus()
            settingsModel.isLoginItemBusy = false
        }
    }

    private func launch(_ entry: LauncherEntry) {
        if entry.kind == .builtIn {
            guard let command = BuiltInCommand(entryID: entry.id) else { return }
            guard !settingsModel.isKeepAwakeBusy, !isTerminating else {
                launcher.showInputError("Keep Awake is updating. Try again.")
                return
            }
            launcher.dismiss()
            changeKeepAwake(enabled: command.keepsAwake)
            return
        }
        if entry.kind == .script {
            guard let command = settingsModel.configuration.scripts.first(where: { $0.entry.id == entry.id && $0.isEnabled }) else { return }
            if command.requiresArgument { launcher.enterArgument(command) }
            else { runScript(id: command.id, argument: nil) }
            return
        }
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

    private func selectArgumentCommand(_ entry: LauncherEntry) {
        guard let command = settingsModel.configuration.scripts.first(where: { $0.entry.id == entry.id && $0.isEnabled }),
              command.requiresArgument else { return }
        launcher.enterArgument(command)
    }

    private func runScript(id: String, argument: String?) {
        guard let command = settingsModel.configuration.scripts.first(where: { $0.id == id && $0.isEnabled }) else {
            launcher.showInputError("This command is no longer enabled."); return
        }
        guard settingsModel.activeScripts[id] == nil else {
            launcher.showInputError("This command is already running."); return
        }
        guard command.requiresArgument == (argument != nil) else {
            launcher.showInputError("The command's argument settings changed. Select it again."); return
        }
        settingsModel.activeScripts[id] = command.name
        cancelledScripts.remove(id)
        actionStatus.title = "Running \(command.name)…"
        let presentation = launcher.beginScriptRun(command)
        Task {
            let message: String
            var failure: String?
            do {
                let result = try await scriptRunner.run(command, argument: argument)
                if isTerminating || cancelledScripts.contains(id) {
                    message = "\(command.name): cancelled."
                } else if result.succeeded {
                    if command.resultMode == .openURL {
                        let url = try result.outputURL()
                        guard NSWorkspace.shared.open(url) else { throw ScriptRunError.invalidURL }
                    }
                    var usage = launcher.usage[command.entry.id] ?? UsageRecord()
                    usage.count += 1
                    usage.lastUsed = .now
                    launcher.usage[command.entry.id] = usage
                    message = "\(command.name): completed."
                } else {
                    message = "\(command.name): \(result.failureDescription ?? "Failed")"
                    if result.termination != .cancelled { failure = message }
                }
            } catch {
                message = "\(command.name): \(error.localizedDescription)"
                failure = message
            }
            settingsModel.activeScripts[id] = nil
            cancelledScripts.remove(id)
            if !isTerminating { launcher.finishScriptRun(presentation, command: command, argument: argument, error: failure) }
            settingsModel.recentRuns.insert(message, at: 0)
            settingsModel.recentRuns = Array(settingsModel.recentRuns.prefix(10))
            actionStatus.title = String(message.prefix(180))
        }
    }

    private func updateStatus() {
        statusLine.title = hotkey.status
        settingsModel.shortcutStatus = hotkey.status
        settingsModel.hotkeyErrors = hotkey.appErrors
    }

    private func toggleApplication(_ id: String) {
        guard let entry = settingsModel.configuration.entries(catalog: catalog.entries).first(where: { $0.id == id && $0.isEnabled }) else { return }
        let running = NSWorkspace.shared.runningApplications.first {
            if id.hasPrefix("app:") { return $0.bundleIdentifier == String(id.dropFirst(4)) }
            return $0.bundleURL?.standardizedFileURL == entry.fileURL.standardizedFileURL
        }
        guard let running else { launch(entry); return }
        if running.isActive && !running.isHidden {
            if !running.hide() { actionStatus.title = "Could not hide \(entry.name)." }
        } else {
            running.unhide()
            if !running.activate() { actionStatus.title = "Could not activate \(entry.name)." }
        }
    }

    @objc private func openSettings() {
        launcher.dismiss(restoreFocus: false)
        settings.present()
    }

    private func updateEntries() {
        settingsModel.catalogEntries = catalog.entries
        launcher.setEntries(settingsModel.configuration.entries(catalog: catalog.entries) + BuiltInCommand.entries,
                            refreshing: catalog.isRefreshing)
    }

    private func applyConfiguration(_ configuration: Configuration) {
        let remapChanged = settingsModel.configuration.capsLockToF19Enabled != configuration.capsLockToF19Enabled
        settingsModel.configuration = configuration
        hotkey.configure(appShortcuts: configuration.applications.compactMapValues { $0.isEnabled ? $0.hotkey : nil })
        let roots = configuration.applicationRoots.map(Configuration.fileURL)
        if roots != catalog.roots || catalog.entries.isEmpty { catalog.roots = roots; catalog.refresh() }
        updateEntries()
        if remapChanged || !didReconcileKeyboard {
            didReconcileKeyboard = true
            reconcileKeyboard()
        }
    }

    private func loadConfiguration() {
        Task {
            do {
                let config = try await configStore.load()
                didLoadConfiguration = true
                applyConfiguration(config)
                settingsModel.status = "Settings ready."
            } catch {
                settingsModel.isReadOnly = true
                settingsModel.status = "Could not load settings: \(error.localizedDescription) Original file unchanged; defaults are in use."
                applyConfiguration(Configuration())
            }
            settingsModel.isBusy = false
            if !settingsModel.configuration.scriptDirectories.isEmpty { refreshScriptFolders() }
        }
    }

    private func saveConfiguration(_ configuration: Configuration) {
        guard !settingsModel.isBusy, !settingsModel.isReadOnly else { return }
        let foldersChanged = settingsModel.configuration.scriptDirectories != configuration.scriptDirectories
        settingsModel.isBusy = true
        settingsModel.status = "Saving…"
        Task {
            do {
                try await configStore.save(configuration)
                applyConfiguration(configuration)
                settingsModel.status = "Saved."
                settingsModel.saveRevision += 1
            } catch { settingsModel.status = error.localizedDescription }
            settingsModel.isBusy = false
            if foldersChanged && settingsModel.configuration == configuration { refreshScriptFolders() }
        }
    }

    private func addScriptFolder() {
        guard !settingsModel.isBusy, !settingsModel.isReadOnly else { return }
        let picker = NSOpenPanel()
        picker.title = "Add Script Folder"
        picker.prompt = "Add Folder"
        picker.message = "Connect shell, Python or AppleScript files from this folder. Raycast titles and one text argument are imported. Files are not copied or run."
        picker.canChooseFiles = false
        picker.canChooseDirectories = true
        guard picker.runModal() == .OK, let url = picker.url else { return }
        var config = settingsModel.configuration
        let path = url.resolvingSymlinksInPath().standardizedFileURL.path
        if !config.scriptDirectories.contains(path) { config.scriptDirectories.append(path) }
        refreshScriptFolders(configuration: config)
    }

    private func refreshScriptFolders(configuration: Configuration? = nil) {
        guard !settingsModel.isBusy, !settingsModel.isReadOnly, !isTerminating else { return }
        let config = configuration ?? settingsModel.configuration
        settingsModel.isBusy = true
        settingsModel.status = "Reading script folders…"
        Task {
            let result = await Task.detached(priority: .utility) { ScriptFolderCatalog.refresh(config) }.value
            guard !isTerminating else { return }
            do {
                if result.configuration != settingsModel.configuration {
                    try await configStore.save(result.configuration)
                    applyConfiguration(result.configuration)
                    settingsModel.saveRevision += 1
                }
                let summary = "Scripts refreshed: \(result.found) found."
                settingsModel.status = result.notices.isEmpty ? summary : summary + " " + String(result.notices.joined(separator: " ").prefix(600))
            } catch { settingsModel.status = "Could not refresh scripts: \(error.localizedDescription)" }
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
            var restored = false
            do {
                let config = try await configStore.restoreBackup()
                settingsModel.isReadOnly = false
                didLoadConfiguration = true
                didReconcileKeyboard = false
                applyConfiguration(config)
                restored = true
                settingsModel.status = "Backup restored. The previous file was preserved."
            } catch { settingsModel.status = "Recovery failed: \(error.localizedDescription)" }
            settingsModel.isBusy = false
            if restored, !settingsModel.configuration.scriptDirectories.isEmpty { refreshScriptFolders() }
        }
    }

    private func item(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let result = NSMenuItem(title: title, action: action, keyEquivalent: key)
        result.target = self
        return result
    }

    private func installMainMenu() {
        let main = AppMenu.make(target: self, settings: #selector(openSettings), quit: #selector(quit), find: #selector(focusSearch))
        NSApp.mainMenu = main
        NSApp.windowsMenu = main.item(withTitle: "Window")?.submenu
    }

    @objc private func focusSearch() {
        if settings.window?.isKeyWindow == true {
            settingsModel.section = "Commands"
            settingsModel.searchFocusRequest += 1
        } else { launcher.focusSearch() }
    }
}
