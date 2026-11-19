import Foundation
import CoreFoundation

public enum ModifierMappingDiagnostics {
    public static let prefix = "com.apple.keyboard.modifiermapping."

    /// Inspect only modifier mappings, never unrelated global preferences.
    public static func conflictingProfiles() -> [String] {
        let app = kCFPreferencesAnyApplication
        let user = kCFPreferencesCurrentUser
        let host = kCFPreferencesCurrentHost
        guard let keys = CFPreferencesCopyKeyList(app, user, host) as? [String] else { return [] }
        var mappings: [String: [[String: UInt64]]] = [:]
        for key in keys where key.hasPrefix(prefix) {
            if let value = CFPreferencesCopyValue(key as CFString, app, user, host) as? [[String: UInt64]] { mappings[key] = value }
        }
        return conflictingProfiles(in: mappings)
    }

    public static func conflictingProfiles(in mappings: [String: [[String: UInt64]]]) -> [String] {
        mappings.keys.filter { key in
            key.hasPrefix(prefix) && mappings[key, default: []].contains {
                $0["HIDKeyboardModifierMappingSrc"] == KeyMapping.capsLock
                    && $0["HIDKeyboardModifierMappingDst"] != KeyMapping.capsLock
            }
        }.sorted()
    }

    public static var warning: String {
        conflictingProfiles().isEmpty ? "" : " Some macOS keyboard profiles reassign Caps Lock. In Modifier Keys, set Caps Lock to Caps Lock for each keyboard you use."
    }
}
