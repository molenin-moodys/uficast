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
        try require(button.image != nil, "Calendar icon missing")
        preferences.showsIcon = false
        controller.configure(preferences)
        try require(button.image?.size.width == 16 && !button.title.isEmpty, "Show Icon must hide only the calendar and retain the power indicator")
        preferences.isEnabled = false
        controller.configure(preferences)
        try require(button.image != nil && button.title.isEmpty, "Clock-off fallback missing")
        preferences.isEnabled = true
        preferences.showsIcon = true
        controller.configure(preferences)
        let decafIcon = button.image
        controller.setKeepAwake(active: true)
        try require(button.image !== decafIcon && button.image?.size.width == 44, "Power change must update the combined icon without waiting for a date change")
        controller.setKeepAwake(active: false)

        let picker = controller.calendarView.datePicker
        try require(picker.datePickerStyle == .clockAndCalendar, "Expected the native graphical NSDatePicker")
        try require(controller.calendarView.frame.width < 200, "Calendar must keep native compact sizing")
        picker.dateValue = Date(timeIntervalSince1970: 0)
        controller.menuWillOpen(menu)
        try require(abs(picker.dateValue.timeIntervalSinceNow) < 1, "Reopening must reset to today")

        let formatter = DateFormatter()
        formatter.dateFormat = "ss"
        var previous = button.title
        var phases: [Double] = []
        let deadline = Date.now.addingTimeInterval(5)
        while phases.count < 3 && Date.now < deadline {
            // Exercise the same run-loop mode used by an open menu.
            RunLoop.main.run(mode: .eventTracking, before: Date.now.addingTimeInterval(0.005))
            let now = Date.now
            if button.title != previous {
                try require(button.title == formatter.string(from: now), "Clock differs from current system second")
                let phase = now.timeIntervalSince1970.truncatingRemainder(dividingBy: 1)
                phases.append(phase)
                previous = button.title
            }
        }
        try require(phases.count == 3, "Clock did not tick during menu tracking")
        try require(phases.allSatisfy { $0 < 0.1 }, "Clock ticks must follow system-second boundaries within 100 ms")
        NotificationCenter.default.post(name: .NSSystemClockDidChange, object: nil)
        try require(button.title == formatter.string(from: .now), "Clock-change resynchronization failed")
        print("PASS: native calendar, compact sizing, today reset, icon/fallback preferences and 3 system-aligned menu-tracking ticks (ms: \(phases.map { Int($0 * 1000) })).")
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
