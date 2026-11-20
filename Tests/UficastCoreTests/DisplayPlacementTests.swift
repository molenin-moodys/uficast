import Foundation
import Testing
import UficastCore

// Cocoa screen frames: a 1512×982 built-in primary display and a 2560×1440
// external display placed to its left, bottom edges aligned.
private let primary = CGRect(x: 0, y: 0, width: 1512, height: 982)
private let external = CGRect(x: -2560, y: 0, width: 2560, height: 1440)
private let screens = [primary, external]

@Test func quartzWindowBoundsConvertToCocoaCoordinates() {
    // Quartz measures y downward from the top of the primary display.
    let quartz = CGRect(x: 100, y: 50, width: 400, height: 300)
    let cocoa = DisplayPlacement.cocoaRect(fromQuartz: quartz, primaryScreenHeight: 982)
    #expect(cocoa == CGRect(x: 100, y: 982 - 50 - 300, width: 400, height: 300))
}

@Test func focusedWindowChoosesTheScreenItMostlyCovers() {
    let mostlyExternal = CGRect(x: -900, y: 100, width: 1000, height: 600)
    #expect(DisplayPlacement.screenIndex(window: mostlyExternal, pointer: CGPoint(x: 700, y: 400), screens: screens) == 1)
    let mostlyPrimary = CGRect(x: -100, y: 100, width: 1000, height: 600)
    #expect(DisplayPlacement.screenIndex(window: mostlyPrimary, pointer: CGPoint(x: -700, y: 400), screens: screens) == 0)
}

@Test func pointerIsTheFallbackWithoutAUsableWindow() {
    let pointerOnExternal = CGPoint(x: -1000, y: 700)
    #expect(DisplayPlacement.screenIndex(window: nil, pointer: pointerOnExternal, screens: screens) == 1)
    // A window entirely off every screen gives no answer of its own.
    let offscreen = CGRect(x: 5000, y: 5000, width: 100, height: 100)
    #expect(DisplayPlacement.screenIndex(window: offscreen, pointer: pointerOnExternal, screens: screens) == 1)
    #expect(DisplayPlacement.screenIndex(window: nil, pointer: CGPoint(x: 9000, y: 9000), screens: screens) == nil)
}
