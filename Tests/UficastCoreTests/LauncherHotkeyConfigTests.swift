import Foundation
import Testing
import UficastCore

private let controlSpace = GlobalShortcut(keyCode: 49, modifiers: GlobalShortcut.control, keyLabel: "Space")

@Test func launcherHotkeyDefaultsToCommandSpaceAndOlderFilesStillDecode() throws {
    // A schema-1 file written before the field existed.
    let legacy = Data(#"{"schemaVersion":1,"applicationRoots":[],"applications":{},"scripts":[]}"#.utf8)
    let config = try Configuration.decode(legacy)
    #expect(config.launcherHotkey == nil)
    #expect(config.effectiveLauncherHotkey == .launcher)
    // The default is not written out, so an untouched file keeps its shape.
    #expect(!String(decoding: try config.encoded(), as: UTF8.self).contains("launcherHotkey"))
}

@Test func customLauncherHotkeyRoundTripsAndIsValidated() throws {
    var config = Configuration()
    config.launcherHotkey = controlSpace
    let decoded = try Configuration.decode(config.encoded())
    #expect(decoded == config)
    #expect(decoded.effectiveLauncherHotkey == controlSpace)
    config.launcherHotkey = GlobalShortcut(keyCode: 49, modifiers: GlobalShortcut.shift, keyLabel: "Space")
    #expect(throws: ConfigError.self) { try config.validated() }
}

@Test func applicationHotkeysConflictWithTheEffectiveLauncherHotkeyOnly() throws {
    var config = Configuration()
    config.launcherHotkey = controlSpace
    // Command+Space is free once the launcher has moved away from it.
    config.applications["app:first"] = AppOverride(hotkey: .launcher)
    _ = try config.validated()
    // The launcher's new combination is reserved, whatever its display label.
    var relabeled = controlSpace
    relabeled.keyLabel = "Пробел"
    config.applications["app:second"] = AppOverride(hotkey: relabeled)
    #expect(throws: ConfigError.self) { try config.validated() }
    // A disabled application may keep the conflicting binding.
    config.applications["app:second"]?.isEnabled = false
    _ = try config.validated()
    // Moving the launcher back onto an enabled app's binding is rejected too.
    config.launcherHotkey = nil
    #expect(throws: ConfigError.self) { try config.validated() }
}
