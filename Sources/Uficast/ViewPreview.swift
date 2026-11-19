import AppKit
import UficastCore

/// Development-only offscreen rendering. Does not register hotkeys or operate other apps.
@MainActor
enum ViewPreview {
    /// Public documentation fixtures only: never discover apps or load user config.
    static let applications: [LauncherEntry] = [
        LauncherEntry(id: "preview-calculator", name: "Calculator", fileURL: URL(fileURLWithPath: "/System/Applications/Calculator.app"), alias: "calc"),
        LauncherEntry(id: "preview-calendar", name: "Calendar", fileURL: URL(fileURLWithPath: "/System/Applications/Calendar.app"), alias: "cal"),
        LauncherEntry(id: "preview-notes", name: "Notes", fileURL: URL(fileURLWithPath: "/System/Applications/Notes.app"), alias: "notes"),
        LauncherEntry(id: "preview-safari", name: "Safari", fileURL: URL(fileURLWithPath: "/Applications/Safari.app"), alias: "web"),
        LauncherEntry(id: "preview-terminal", name: "Terminal", fileURL: URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app"), alias: "term"),
    ]

    static var command: ScriptCommand {
        ScriptCommand(id: "preview-search", name: "Search Example", alias: "search",
                      path: "/tmp/uficast-example/browser-search.py", interpreter: "/usr/bin/python3",
                      requiresArgument: true, argumentPlaceholder: "Search text", resultMode: .openURL)
    }

    static func settingsModel() -> SettingsModel {
        let model = SettingsModel()
        model.isBusy = false
        model.status = "Settings ready."
        model.shortcutStatus = "Release matching Spotlight/Raycast shortcuts if needed."
        model.configuration.scripts = [command]
        model.catalogEntries = applications
        for entry in applications {
            model.configuration.applications[entry.id] = AppOverride(alias: entry.alias)
        }
        model.configuration.applications["preview-terminal"]?.hotkey = GlobalShortcut(
            keyCode: 17, modifiers: GlobalShortcut.control | GlobalShortcut.option, keyLabel: "T")
        model.selectedID = "preview-terminal"
        return model
    }

    static func write(_ view: NSView, to url: URL) throws {
        view.layoutSubtreeIfNeeded()
        // Allow hosted views to lay out and serial background icon loads to finish.
        RunLoop.current.run(until: Date().addingTimeInterval(1))
        view.layoutSubtreeIfNeeded()
        view.displayIfNeeded()
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
            throw ConfigError.invalid("Could not allocate a native view preview.")
        }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        guard let data = bitmap.representation(using: .png, properties: [:]) else {
            throw ConfigError.invalid("Could not encode the native view preview.")
        }
        try data.write(to: url, options: .atomic)
    }
}
