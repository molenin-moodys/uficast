import Foundation
import Testing
import UficastCore

@Test func clockConfigurationPreservesLegacySettingsAndValidatesFormat() throws {
    let legacy = Data(#"{"schemaVersion":1,"applicationRoots":["/Applications"],"applications":{},"scripts":[]}"#.utf8)
    var config = try Configuration.decode(legacy)
    #expect(config.menuBarClock == MenuBarClockPreferences())
    config.menuBarClock.isEnabled = false
    config.menuBarClock.showsIcon = false
    config.menuBarClock.dateFormat = "E h:mm:ss a"
    #expect(try Configuration.decode(config.encoded()) == config)
    for invalid in ["", "   ", "HH\nmm", String(repeating: "H", count: 129)] {
        config.menuBarClock.dateFormat = invalid
        #expect(throws: ConfigError.self) { try config.validated() }
    }
}
