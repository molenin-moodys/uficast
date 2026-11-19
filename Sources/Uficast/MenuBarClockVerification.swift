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
        try require(button.image == nil && !button.title.isEmpty, "Show Icon must retain the clock button")
        preferences.isEnabled = false
        controller.configure(preferences)
        try require(button.image != nil && button.title.isEmpty, "Clock-off fallback missing")
        preferences.isEnabled = true
        controller.configure(preferences)

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
