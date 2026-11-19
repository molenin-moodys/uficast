import AppKit
import UficastCore

/// Day-O uses this same AppKit control in clockAndCalendar mode.
/// Keep native calendar drawing and interaction rather than reproducing its grid.
@MainActor
final class MenuBarCalendarView: NSView {
    let datePicker = MenuDatePicker()

    init() {
        super.init(frame: .zero)
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 2
        calendar.locale = Locale(identifier: "en_US")
        datePicker.calendar = calendar
        datePicker.locale = calendar.locale
        datePicker.timeZone = .autoupdatingCurrent
        datePicker.datePickerElements = [.yearMonthDay]
        datePicker.datePickerStyle = .clockAndCalendar
        datePicker.datePickerMode = .single
        datePicker.isBordered = false
        datePicker.isBezeled = false
        datePicker.drawsBackground = false
        datePicker.sizeToFit()
        datePicker.frame.origin = NSPoint(x: 12, y: 8)
        datePicker.autoresizingMask = [.minXMargin, .maxXMargin]
        frame.size = NSSize(width: datePicker.frame.width + 24, height: datePicker.frame.height + 16)
        addSubview(datePicker)
        reset()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func reset(to date: Date = .now) {
        datePicker.timeZone = .autoupdatingCurrent
        datePicker.dateValue = date
    }
}

@MainActor
final class MenuDatePicker: NSDatePicker {
    override var allowsVibrancy: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Updates the existing Uficast status button, preserving one menu-bar entry.
@MainActor
final class MenuBarClockController: NSObject, NSMenuDelegate {
    let calendarView = MenuBarCalendarView()
    private let statusItem: NSStatusItem
    private let formatter = DateFormatter()
    private var preferences = MenuBarClockPreferences()
    private var keepAwakeActive = false
    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []
    private var lastIconDay: Int?

    init(statusItem: NSStatusItem, menu: NSMenu) {
        self.statusItem = statusItem
        super.init()
        let calendarItem = NSMenuItem()
        calendarItem.view = calendarView
        menu.insertItem(calendarItem, at: 0)
        menu.insertItem(.separator(), at: 1)
        menu.delegate = self
        statusItem.button?.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .medium)
        statusItem.button?.imagePosition = .imageLeading
        for name in [NSLocale.currentLocaleDidChangeNotification, NSNotification.Name.NSSystemTimeZoneDidChange,
                     NSNotification.Name.NSSystemClockDidChange, NSApplication.didChangeScreenParametersNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.synchronize() }
            })
        }
        synchronize()
    }

    func configure(_ preferences: MenuBarClockPreferences) { self.preferences = preferences; lastIconDay = nil; refresh() }
    func setKeepAwake(active: Bool) { keepAwakeActive = active; refresh() }
    func stop() {
        timer?.invalidate()
        timer = nil
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        observers = []
    }

    func menuWillOpen(_ menu: NSMenu) { calendarView.reset(); refresh() }

    func synchronize() {
        refresh()
        timer?.invalidate()
        // Recalculate from wall time on every tick, rather than inheriting
        // launch-time phase or accumulating delays from menu tracking/wake.
        let nextSecond = Date(timeIntervalSince1970: floor(Date.now.timeIntervalSince1970) + 1)
        let timer = Timer(fire: nextSecond, interval: 0, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.synchronize() }
        }
        timer.tolerance = 0
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
        RunLoop.main.add(timer, forMode: .eventTracking)
    }

    private func refresh() {
        guard let button = statusItem.button else { return }
        let now = Date.now
        formatter.locale = .autoupdatingCurrent
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = .autoupdatingCurrent
        formatter.dateFormat = preferences.dateFormat
        let title = formatter.string(from: now)
        button.title = preferences.isEnabled ? (title.isEmpty ? now.formatted(date: .abbreviated, time: .standard) : String(title.prefix(100))) : ""
        if preferences.isEnabled {
            if preferences.showsIcon {
                let day = Calendar(identifier: .gregorian).component(.day, from: now)
                if lastIconDay != day { button.image = Self.calendarIcon(day: day); lastIconDay = day }
            } else { button.image = nil; lastIconDay = nil }
        } else {
            button.image = NSImage(systemSymbolName: keepAwakeActive ? "cup.and.saucer.fill" : "zzz", accessibilityDescription: nil)
            lastIconDay = nil
        }
        let state = keepAwakeActive ? "Keep Awake on" : "Keep Awake off"
        button.toolTip = "Uficast — \(state) · Click for calendar and commands"
        button.setAccessibilityLabel("Uficast, \(button.title), \(state)")
    }

    private static func calendarIcon(day: Int) -> NSImage {
        // Match Day-O's 22×18 calendar geometry with 2 pt image-side padding.
        // Its date is centered at y=3 in 9 pt bold system type; no header rule.
        let image = NSImage(size: NSSize(width: 26, height: 18), flipped: true) { _ in
            NSColor.black.setFill()
            let frame = NSBezierPath(roundedRect: NSRect(x: 3, y: 1, width: 20, height: 15), xRadius: 2, yRadius: 2)
            frame.append(NSBezierPath(roundedRect: NSRect(x: 4.5, y: 2.5, width: 17, height: 12), xRadius: 1, yRadius: 1))
            frame.windingRule = .evenOdd
            frame.fill()
            for x in [7, 12, 17] {
                NSBezierPath(ovalIn: NSRect(x: x, y: 0, width: 2, height: 2)).fill()
            }
            let style = NSMutableParagraphStyle()
            style.alignment = .center
            (String(day) as NSString).draw(in: NSRect(x: 2, y: 3, width: 22, height: 15), withAttributes: [
                .font: NSFont.boldSystemFont(ofSize: 9), .foregroundColor: NSColor.black, .paragraphStyle: style
            ])
            return true
        }
        image.isTemplate = true
        return image
    }
}
