import AppKit
import UficastCore

@main
struct UficastMain {
    @MainActor
    static func main() {
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
