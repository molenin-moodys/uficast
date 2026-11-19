import AppKit
import UficastCore

/// Development-only offscreen rendering. Does not register hotkeys or operate other apps.
@MainActor
enum ViewPreview {
    static func write(_ view: NSView, to url: URL) throws {
        view.layoutSubtreeIfNeeded()
        // Give hosted SwiftUI/native controls their initial layout/display turn.
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
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
