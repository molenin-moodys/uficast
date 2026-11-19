import AppKit
import UficastCore

@main
struct UficastMain {
    @MainActor
    static func main() {
        if let flag = CommandLine.arguments.firstIndex(where: { $0 == "--preview-launcher" || $0 == "--preview-settings" }) {
            guard CommandLine.arguments.indices.contains(flag + 1) else {
                print("Provide an output PNG path for the preview.")
                exit(2)
            }
            let application = NSApplication.shared
            application.setActivationPolicy(.prohibited)
            application.finishLaunching()
            let path = URL(fileURLWithPath: CommandLine.arguments[flag + 1])
            do {
                if CommandLine.arguments[flag] == "--preview-launcher" {
                    try LauncherPanelController().renderPreview(to: path, argumentMode: CommandLine.arguments.contains("--argument"))
                } else {
                    let model = SettingsModel()
                    model.isBusy = false
                    model.status = "Settings ready."
                    model.configuration.scripts = [ScriptCommand(name: "Kibana", alias: "k", path: "/tmp/fixture.py")]
                    model.catalogEntries = [
                        LauncherEntry(id: "fixture-kitty", name: "kitty", fileURL: URL(fileURLWithPath: "/tmp/kitty.app")),
                        LauncherEntry(id: "fixture-browser", name: "Browser", fileURL: URL(fileURLWithPath: "/tmp/Browser.app")),
                    ]
                    try SettingsWindowController(model: model).renderPreview(to: path)
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
        let application = NSApplication.shared
        let controller = AppController()
        application.delegate = controller
        withExtendedLifetime(controller) { application.run() }
    }
}
