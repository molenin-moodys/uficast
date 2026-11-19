import Foundation

public struct MenuBarClockPreferences: Codable, Equatable, Sendable {
    public var isEnabled = true
    public var showsIcon = true
    public var dateFormat = "EEE HH:mm:ss"

    public init() {}

    public func validate() throws {
        guard !dateFormat.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              dateFormat.count <= 128, !dateFormat.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else {
            throw ConfigError.invalid("Use a date and time format of 1–128 characters without line breaks.")
        }
    }
}
