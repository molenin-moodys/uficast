import Testing
import UficastCore

@Test func repeatedNotificationsAndReleaseOrderToggleOnlyOnce() {
    var hotkey = LauncherHotkey()
    #expect(hotkey.press() == true)
    #expect(hotkey.press() == false)
    #expect(hotkey.press() == false)
    hotkey.release()
    hotkey.release() // An unmatched release is harmless.
    #expect(hotkey.press() == true)
}

@Test func reregisteringClearsAnInterruptedPress() {
    var hotkey = LauncherHotkey()
    #expect(hotkey.press() == true)
    hotkey.reset()
    #expect(hotkey.press() == true)
}
