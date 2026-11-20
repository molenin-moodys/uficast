import AppKit
import UficastCore

@MainActor
enum MenuBarClockVerification {
    static func run() throws {
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let menu = NSMenu()
        let controller = MenuBarClockController(statusItem: statusItem, menu: menu)
        defer { controller.stop(); NSStatusBar.system.removeStatusItem(statusItem) }
        func require(_ condition: Bool, _ message: String) throws {
            if !condition { throw ConfigError.invalid(message) }
        }
        var preferences = MenuBarClockPreferences()
        preferences.dateFormat = "ss"
        controller.configure(preferences)
        let button = statusItem.button!
        try require(button.image != nil && controller.iconWidth == 44, "Calendar icon missing")
        try require(button.image?.isTemplate == false && button.title.isEmpty,
                    "Clock must be one explicit-color image, not a template image plus a system-styled title")
        try require((button.image?.size.width ?? 0) > 44 + 4, "Clock text must be drawn inside the status image")
        preferences.showsIcon = false
        controller.configure(preferences)
        try require(controller.iconWidth == 16 && !controller.displayedTitle.isEmpty, "Show Icon must hide only the calendar and retain the power indicator")
        preferences.isEnabled = false
        controller.configure(preferences)
        try require(button.image?.size.width == 16 && controller.displayedTitle.isEmpty, "Clock-off fallback missing")
        preferences.isEnabled = true
        preferences.showsIcon = true
        controller.configure(preferences)
        let decafIcon = button.image
        controller.setKeepAwake(active: true)
        try require(button.image !== decafIcon && controller.iconWidth == 44, "Power change must update the combined icon without waiting for a date change")
        controller.setKeepAwake(active: false)
        for (name, expected) in [(NSAppearance.Name.aqua, CGFloat(0)), (.darkAqua, CGFloat(1))] {
            let brightness = try StatusClockPreview.inkBrightness(of: button.image!, appearance: name)
            try require(abs(brightness - expected) < 0.05, "\(name.rawValue) menu bar must draw at full contrast (brightness \(brightness))")
        }

        let picker = controller.calendarView.datePicker
        try require(picker.datePickerStyle == .clockAndCalendar, "Expected the native graphical NSDatePicker")
        try require(controller.calendarView.frame.width < 200, "Calendar must keep native compact sizing")
        picker.dateValue = Date(timeIntervalSince1970: 0)
        controller.menuWillOpen(menu)
        try require(abs(picker.dateValue.timeIntervalSinceNow) < 1, "Reopening must reset to today")

        let formatter = DateFormatter()
        formatter.dateFormat = "ss"
        var previous = controller.displayedTitle
        var phases: [Double] = []
        let deadline = Date.now.addingTimeInterval(5)
        while phases.count < 3 && Date.now < deadline {
            // Exercise the same run-loop mode used by an open menu.
            RunLoop.main.run(mode: .eventTracking, before: Date.now.addingTimeInterval(0.005))
            let now = Date.now
            if controller.displayedTitle != previous {
                try require(controller.displayedTitle == formatter.string(from: now), "Clock differs from current system second")
                let phase = now.timeIntervalSince1970.truncatingRemainder(dividingBy: 1)
                phases.append(phase)
                previous = controller.displayedTitle
            }
        }
        try require(phases.count == 3, "Clock did not tick during menu tracking")
        try require(phases.allSatisfy { $0 < 0.1 }, "Clock ticks must follow system-second boundaries within 100 ms")
        NotificationCenter.default.post(name: .NSSystemClockDidChange, object: nil)
        try require(controller.displayedTitle == formatter.string(from: .now), "Clock-change resynchronization failed")
        print("PASS: native calendar, compact sizing, today reset, icon/fallback preferences, full-contrast light/dark status image and 3 system-aligned menu-tracking ticks (ms: \(phases.map { Int($0 * 1000) })).")
    }
}

/// Offscreen rendering of the status image for visual review. Fixed text only.
@MainActor
enum StatusClockPreview {
    static func write(to url: URL) throws {
        let image = MenuBarClockController.statusImage(title: "Thu 18 Jul 12:34:56", day: 18, awake: false)
        let awake = MenuBarClockController.statusImage(title: "Thu 18 Jul 12:34:56", day: 18, awake: true)
        let rows: [(NSAppearance.Name, NSColor)] = [(.aqua, NSColor(white: 0.93, alpha: 1)), (.darkAqua, NSColor(white: 0.16, alpha: 1))]
        let scale: CGFloat = 2, padding: CGFloat = 8
        let rowHeight = image.size.height + padding * 2
        let size = NSSize(width: image.size.width + awake.size.width + padding * 3, height: rowHeight * CGFloat(rows.count))
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
                                            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else {
            throw ConfigError.invalid("Could not allocate the status clock preview.")
        }
        bitmap.size = size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        for (index, row) in rows.enumerated() {
            let y = size.height - rowHeight * CGFloat(index + 1)
            row.1.setFill()
            NSRect(x: 0, y: y, width: size.width, height: rowHeight).fill()
            NSAppearance(named: row.0)!.performAsCurrentDrawingAppearance {
                image.draw(at: NSPoint(x: padding, y: y + padding), from: .zero, operation: .sourceOver, fraction: 1)
                awake.draw(at: NSPoint(x: padding * 2 + image.size.width, y: y + padding), from: .zero, operation: .sourceOver, fraction: 1)
            }
        }
        NSGraphicsContext.restoreGraphicsState()
        guard let data = bitmap.representation(using: .png, properties: [:]) else {
            throw ConfigError.invalid("Could not encode the status clock preview.")
        }
        try data.write(to: url, options: .atomic)
    }

    /// Average brightness of the image's opaque pixels when drawn on transparency.
    static func inkBrightness(of image: NSImage, appearance: NSAppearance.Name) throws -> CGFloat {
        let width = Int(ceil(image.size.width)), height = Int(ceil(image.size.height))
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8,
                                            samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                            bytesPerRow: 0, bitsPerPixel: 0) else {
            throw ConfigError.invalid("Could not allocate a measurement bitmap.")
        }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        NSAppearance(named: appearance)!.performAsCurrentDrawingAppearance {
            image.draw(in: NSRect(x: 0, y: 0, width: width, height: height))
        }
        NSGraphicsContext.restoreGraphicsState()
        var total: CGFloat = 0, count: CGFloat = 0
        for x in 0..<width {
            for y in 0..<height {
                guard let color = bitmap.colorAt(x: x, y: y), color.alphaComponent > 0.9 else { continue }
                total += color.brightnessComponent
                count += 1
            }
        }
        guard count > 0 else { throw ConfigError.invalid("Status image drew no opaque pixels.") }
        return total / count
    }
}

/// Interactive native menu fixture. No user config, registrations or services.
@MainActor
final class CalendarMenuPreview: NSObject {
    private let menu = NSMenu()
    private let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 600),
                                  styleMask: [.titled, .closable], backing: .buffered, defer: false)
    private var controller: MenuBarClockController!
    private var statusItem: NSStatusItem!

    func run() {
        window.title = "Calendar Menu Preview"
        window.isReleasedWhenClosed = false
        let button = NSButton(title: "Open Calendar Menu", target: self, action: #selector(openMenu(_:)))
        button.frame = NSRect(x: 55, y: 520, width: 210, height: 32)
        window.contentView?.addSubview(button)
        menu.minimumWidth = 190
        for title in ["Open Launcher", "Settings…", "Date & Time…", "Keep Awake"] {
            let item = NSMenuItem(title: title, action: #selector(noAction), keyEquivalent: "")
            item.target = self
            if title == "Keep Awake" {
                item.submenu = NSMenu()
                item.submenu?.addItem(withTitle: "Until Stopped", action: #selector(noAction), keyEquivalent: "").target = self
            }
            menu.addItem(item)
        }
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit Uficast", action: #selector(quitPreview), keyEquivalent: "")
        quit.target = self
        menu.addItem(quit)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        controller = MenuBarClockController(statusItem: statusItem, menu: menu)
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
        NSApp.run()
        controller.stop()
        NSStatusBar.system.removeStatusItem(statusItem)
    }

    @objc private func noAction() {}
    @objc private func quitPreview() { NSApp.terminate(nil) }
    @objc private func openMenu(_ sender: NSButton) {
        let measurement = Timer(timeInterval: 0.2, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let view = self?.controller.calendarView, let content = view.window?.contentView else { return }
                view.layoutSubtreeIfNeeded()
                let picker = view.datePicker.convert(view.datePicker.bounds, to: content)
                print("Native menu width \(content.bounds.width): calendar margins \(picker.minX), \(content.bounds.maxX - picker.maxX)")
                fflush(stdout)
            }
        }
        RunLoop.main.add(measurement, forMode: .eventTracking)
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.minY), in: sender)
        measurement.invalidate()
    }
}
