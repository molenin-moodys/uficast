import Foundation

public struct GlobalShortcut: Codable, Hashable, Sendable {
    public static let command: UInt32 = 1 << 8
    public static let shift: UInt32 = 1 << 9
    public static let option: UInt32 = 1 << 11
    public static let control: UInt32 = 1 << 12
    public var keyCode: UInt32
    public var modifiers: UInt32
    public var keyLabel: String
    public static let launcher = GlobalShortcut(keyCode: 49, modifiers: command, keyLabel: "Space")

    public init(keyCode: UInt32, modifiers: UInt32, keyLabel: String) {
        self.keyCode = keyCode; self.modifiers = modifiers; self.keyLabel = keyLabel
    }
    public var signature: UInt64 { UInt64(modifiers) << 32 | UInt64(keyCode) }
    public var display: String {
        [(Self.control, "⌃"), (Self.option, "⌥"), (Self.shift, "⇧"), (Self.command, "⌘")]
            .filter { modifiers & $0.0 != 0 }.map(\.1).joined() + keyLabel
    }
    public func validate() throws {
        let mask = Self.command | Self.shift | Self.option | Self.control
        guard keyCode <= 127, modifiers & ~mask == 0,
              modifiers & (Self.command | Self.option | Self.control) != 0, !keyLabel.isEmpty else {
            throw ConfigError.invalid("Use a shortcut with Command, Control or Option.")
        }
    }
}
