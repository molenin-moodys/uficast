import AppKit
import SwiftUI
import UficastCore

@main
struct UficastMain {
    @MainActor
    static func main() {
        if CommandLine.arguments.contains("--verify-native-icons") {
            let application = NSApplication.shared
            application.setActivationPolicy(.prohibited)
            application.finishLaunching()
            do {
                try LauncherPanelController().verifyNativeIconRefresh()
                print("PASS: catalog icons updated existing launcher cells without moving rows.")
            } catch {
                FileHandle.standardError.write(Data("\(error.localizedDescription)\n".utf8))
                exit(1)
            }
            return
        }
        if let flag = CommandLine.arguments.firstIndex(where: { ["--preview-launcher", "--preview-settings", "--preview-script-editor"].contains($0) }) {
            guard CommandLine.arguments.indices.contains(flag + 1) else {
                print("Provide an output PNG path for the preview.")
                exit(2)
            }
            let application = NSApplication.shared
            application.setActivationPolicy(.prohibited)
            application.finishLaunching()
            if CommandLine.arguments.contains("--dark") { application.appearance = NSAppearance(named: .darkAqua) }
            let path = URL(fileURLWithPath: CommandLine.arguments[flag + 1])
            do {
                if CommandLine.arguments[flag] == "--preview-launcher" {
                    try LauncherPanelController().renderPreview(to: path, argumentMode: CommandLine.arguments.contains("--argument"))
                } else {
                    let model = SettingsModel()
                    model.isBusy = false
                    model.status = "Settings ready."
                    if CommandLine.arguments.contains("--general") { model.section = "General" }
                    model.configuration.scripts = [ScriptCommand(name: "Kibana", alias: "k", path: "/tmp/fixture.py")]
                    model.catalogEntries = [
                        LauncherEntry(id: "fixture-kitty", name: "kitty", fileURL: URL(fileURLWithPath: "/tmp/kitty.app")),
                        LauncherEntry(id: "fixture-browser", name: "Browser", fileURL: URL(fileURLWithPath: "/tmp/Browser.app")),
                    ]
                    if CommandLine.arguments[flag] == "--preview-script-editor" {
                        var command = model.configuration.scripts[0]
                        command.requiresArgument = true
                        command.argumentPlaceholder = "log_stream"
                        command.interpreter = "/usr/bin/python3"
                        command.resultMode = .openURL
                        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 680, height: 720),
                                              styleMask: [.borderless], backing: .buffered, defer: false)
                        window.contentView = NSHostingView(rootView: ScriptEditor(model: model, script: command))
                        try ViewPreview.write(window.contentView!, to: path)
                    } else { try SettingsWindowController(model: model).renderPreview(to: path) }
                }
                print("Wrote offscreen preview: \(path.path)")
            } catch { fputs("\(error.localizedDescription)\n", stderr); exit(1) }
            return
        }
        if CommandLine.arguments.contains("--catalog-summary") {
            let start = ContinuousClock.now
            let snapshot = ApplicationCatalog.discover(roots: ApplicationCatalog.defaultRoots)
            print("Applications: \(snapshot.entries.count); unavailable roots: \(snapshot.unavailableRoots.count); discovery: \(start.duration(to: .now))")
            return
        }
        if CommandLine.arguments.contains("--diagnostics") {
            let values: [String: Any] = [
                "bundleIdentifier": Bundle.main.bundleIdentifier ?? "unbundled",
                "bundlePath": Bundle.main.bundlePath,
                "shortcut": "Command + Space",
                "requiresAccessibility": false,
                "osVersion": ProcessInfo.processInfo.operatingSystemVersionString,
            ]
            if let data = try? JSONSerialization.data(withJSONObject: values, options: [.prettyPrinted, .sortedKeys]),
               let value = String(data: data, encoding: .utf8) { print(value) }
            return
        }
        let coordinator = InstanceCoordinator()
        do {
            guard try coordinator.becomePrimary() else { coordinator.revealPrimary(); return }
        } catch {
            NSApplication.shared.setActivationPolicy(.regular)
            NSAlert(error: error).runModal()
            return
        }
        let application = NSApplication.shared
        let controller = AppController()
        coordinator.onReopen = { [weak controller] in controller?.revealLauncher() }
        application.delegate = controller
        withExtendedLifetime((controller, coordinator)) { application.run() }
        coordinator.stop()
    }
}
