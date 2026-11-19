import Foundation

public enum AITextAction: String, Codable, CaseIterable, Sendable {
    case rewrite, translate

    public var title: String {
        switch self {
        case .rewrite: "Rewrite"
        case .translate: "Translate"
        }
    }
}

/// The owner-editable AI command and the clipboard hotkeys. Absent fields decode as defaults.
public struct AITextPreferences: Codable, Equatable, Sendable {
    /// Leaves out the owner's user settings (hooks, plugins) so they cannot change the answer;
    /// the Claude Code login still works. Measured in the November 19, 2026 spike.
    public static let defaultCommand = #"claude -p --model claude-haiku-5-5 --tools "" --strict-mcp-config --disable-slash-commands --no-session-persistence --setting-sources project,local"#
    public static let maximumCommandLength = 2000

    public var command = defaultCommand
    public var rewriteHotkey: GlobalShortcut?
    public var translateHotkey: GlobalShortcut?

    public init() {}

    private enum CodingKeys: String, CodingKey { case command, rewriteHotkey, translateHotkey }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        command = try values.decodeIfPresent(String.self, forKey: .command) ?? Self.defaultCommand
        rewriteHotkey = try values.decodeIfPresent(GlobalShortcut.self, forKey: .rewriteHotkey)
        translateHotkey = try values.decodeIfPresent(GlobalShortcut.self, forKey: .translateHotkey)
    }

    public func hotkey(for action: AITextAction) -> GlobalShortcut? {
        switch action {
        case .rewrite: rewriteHotkey
        case .translate: translateHotkey
        }
    }

    public func validate() throws {
        guard !command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !command.contains("\0"),
              command.count <= Self.maximumCommandLength else {
            throw ConfigError.invalid("The AI command must be non-empty, contain no null character and be at most \(Self.maximumCommandLength) characters.")
        }
        try rewriteHotkey?.validate()
        try translateHotkey?.validate()
    }
}
