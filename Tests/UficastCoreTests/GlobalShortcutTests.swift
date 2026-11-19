import Foundation
import Testing
import UficastCore

@Test func applicationShortcutsAreUniqueByKeysNotDisplayLabels() throws {
    var config = Configuration()
    let shortcut = GlobalShortcut(keyCode: 40, modifiers: GlobalShortcut.command | GlobalShortcut.option, keyLabel: "K")
    config.applications["app:first"] = AppOverride(hotkey: shortcut)
    var renamed = shortcut
    renamed.keyLabel = "К"
    config.applications["app:second"] = AppOverride(hotkey: renamed)
    #expect(throws: ConfigError.self) { try config.validated() }
    config.applications["app:second"]?.isEnabled = false
    _ = try config.validated()
    #expect(try Configuration.decode(config.encoded()) == config)
    config.applications["app:first"]?.hotkey = .launcher
    #expect(throws: ConfigError.self) { try config.validated() }
}

@Test func bareLettersAndUnsupportedModifierBitsCannotBecomeGlobalBindings() {
    for modifiers: UInt32 in [0, GlobalShortcut.shift, 1 << 31] {
        #expect(throws: ConfigError.self) { try GlobalShortcut(keyCode: 40, modifiers: modifiers, keyLabel: "K").validate() }
    }
}
