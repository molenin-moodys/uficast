import Foundation

public struct AppOverride: Codable, Equatable, Sendable {
    public var alias: String?
    public var isEnabled: Bool
    public var lastKnownName: String?
    public var fallbackPath: String?
    public var hotkey: GlobalShortcut?

    public init(alias: String? = nil, isEnabled: Bool = true, lastKnownName: String? = nil, fallbackPath: String? = nil, hotkey: GlobalShortcut? = nil) {
        self.alias = alias
        self.isEnabled = isEnabled
        self.lastKnownName = lastKnownName
        self.fallbackPath = fallbackPath
        self.hotkey = hotkey
    }
}

public struct ScriptCommand: Codable, Equatable, Identifiable, Sendable {
    public enum ResultMode: String, Codable, CaseIterable, Sendable { case discard, openURL }
    public var id: String
    public var name: String
    public var alias: String?
    public var isEnabled: Bool
    public var path: String
    public var interpreter: String?
    public var requiresArgument: Bool
    public var argumentPlaceholder: String
    public var resultMode: ResultMode
    public var timeoutSeconds: Double
    public var workingDirectory: String?
    public var environment: [String: String]
    public var sourceDirectory: String?

    public init(id: String = UUID().uuidString, name: String, alias: String? = nil, isEnabled: Bool = true,
                path: String, interpreter: String? = nil, requiresArgument: Bool = false,
                argumentPlaceholder: String = "Argument", resultMode: ResultMode = .discard,
                timeoutSeconds: Double = 30, workingDirectory: String? = nil, environment: [String: String] = [:], sourceDirectory: String? = nil) {
        self.id = id
        self.name = name
        self.alias = alias
        self.isEnabled = isEnabled
        self.path = path
        self.interpreter = interpreter
        self.requiresArgument = requiresArgument
        self.argumentPlaceholder = argumentPlaceholder
        self.resultMode = resultMode
        self.timeoutSeconds = timeoutSeconds
        self.workingDirectory = workingDirectory
        self.environment = environment
        self.sourceDirectory = sourceDirectory
    }

    public var entry: LauncherEntry {
        LauncherEntry(id: "script:\(id)", name: name, kind: .script,
                      fileURL: Configuration.fileURL(path), alias: alias, isEnabled: isEnabled)
    }
}

public struct Configuration: Codable, Equatable, Sendable {
    public static let currentVersion = 1
    public var schemaVersion = currentVersion
    public var applicationRoots: [String] = ["/Applications", "/System/Applications", "~/Applications"]
    public var applications: [String: AppOverride] = [:]
    public var scripts: [ScriptCommand] = []
    public var scriptDirectories: [String] = []
    public var capsLockToF19Enabled = false
    public var menuBarClock = MenuBarClockPreferences()
    /// nil keeps the default Command+Space and is not written to disk.
    public var launcherHotkey: GlobalShortcut?

    public var effectiveLauncherHotkey: GlobalShortcut { launcherHotkey ?? .launcher }

    public init() {}

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, applicationRoots, applications, scripts, scriptDirectories, capsLockToF19Enabled, menuBarClock, launcherHotkey
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try values.decode(Int.self, forKey: .schemaVersion)
        applicationRoots = try values.decode([String].self, forKey: .applicationRoots)
        applications = try values.decode([String: AppOverride].self, forKey: .applications)
        scripts = try values.decode([ScriptCommand].self, forKey: .scripts)
        scriptDirectories = try values.decodeIfPresent([String].self, forKey: .scriptDirectories) ?? []
        capsLockToF19Enabled = try values.decodeIfPresent(Bool.self, forKey: .capsLockToF19Enabled) ?? false
        menuBarClock = try values.decodeIfPresent(MenuBarClockPreferences.self, forKey: .menuBarClock) ?? MenuBarClockPreferences()
        launcherHotkey = try values.decodeIfPresent(GlobalShortcut.self, forKey: .launcherHotkey)
    }

    public static func fileURL(_ path: String) -> URL {
        URL(fileURLWithPath: (path as NSString).expandingTildeInPath).standardizedFileURL
    }

    public func entries(catalog: [LauncherEntry]) -> [LauncherEntry] {
        var apps = catalog
        let known = Set(apps.map(\.id))
        for (id, override) in applications where !known.contains(id) {
            if let path = override.fallbackPath {
                apps.append(LauncherEntry(id: id, name: override.lastKnownName ?? Self.fileURL(path).deletingPathExtension().lastPathComponent,
                                          fileURL: Self.fileURL(path)))
            }
        }
        return apps.map { item in
            var item = item
            if let override = applications[item.id] { item.alias = override.alias; item.isEnabled = override.isEnabled }
            return item
        } + scripts.map(\.entry)
    }

    public func validated() throws -> Configuration {
        guard schemaVersion == Self.currentVersion else { throw ConfigError.unsupportedVersion(schemaVersion) }
        try menuBarClock.validate()
        var aliases: Set<String> = []
        func checkAlias(_ alias: String?, enabled: Bool) throws {
            guard let alias else { return }
            guard !alias.isEmpty, !alias.contains(where: { $0.isWhitespace || $0 == "\0" }) else {
                throw ConfigError.invalid("Aliases must be nonempty and contain no whitespace.")
            }
            if enabled, !aliases.insert(SearchText.normalize(alias)).inserted {
                throw ConfigError.invalid("Alias ‘\(alias)’ is already assigned to another enabled item.")
            }
        }
        func checkPath(_ path: String) throws {
            guard (path.hasPrefix("/") || path.hasPrefix("~/")), !path.contains("\0") else {
                throw ConfigError.invalid("Use an absolute path or a path starting with ~/.")
            }
        }
        for path in applicationRoots { try checkPath(path) }
        for path in scriptDirectories { try checkPath(path) }
        try launcherHotkey?.validate()
        var shortcuts: Set<UInt64> = [effectiveLauncherHotkey.signature]
        for (id, app) in applications {
            guard id.hasPrefix("app:") || id.hasPrefix("app-path:") else { throw ConfigError.invalid("Invalid application identity.") }
            try checkAlias(app.alias, enabled: app.isEnabled)
            if let path = app.fallbackPath { try checkPath(path) }
            if let hotkey = app.hotkey {
                try hotkey.validate()
                if app.isEnabled, !shortcuts.insert(hotkey.signature).inserted {
                    throw ConfigError.invalid("That shortcut is already assigned or reserved for the launcher.")
                }
            }
        }
        var ids: Set<String> = []
        for script in scripts {
            guard !script.id.isEmpty, ids.insert(script.id).inserted else { throw ConfigError.invalid("Script IDs must be unique and nonempty.") }
            guard !script.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw ConfigError.invalid("A script needs a name.") }
            try checkAlias(script.alias, enabled: script.isEnabled)
            try checkPath(script.path)
            if let directory = script.sourceDirectory { try checkPath(directory) }
            if let interpreter = script.interpreter { try checkPath(interpreter) }
            if let directory = script.workingDirectory { try checkPath(directory) }
            guard script.timeoutSeconds.isFinite, script.timeoutSeconds > 0, script.timeoutSeconds <= 86400 else {
                throw ConfigError.invalid("Script timeout must be between 0 and 86,400 seconds.")
            }
            for (key, value) in script.environment {
                guard !key.isEmpty, !key.contains("="), !key.contains("\0"), !value.contains("\0") else {
                    throw ConfigError.invalid("Environment variable names/values are invalid.")
                }
            }
        }
        return self
    }

    public static func decode(_ data: Data) throws -> Configuration {
        struct Version: Decodable { var schemaVersion: Int }
        let version = try JSONDecoder().decode(Version.self, from: data).schemaVersion
        guard version == currentVersion else { throw ConfigError.unsupportedVersion(version) }
        return try JSONDecoder().decode(Configuration.self, from: data).validated()
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(validated())
    }
}

public enum ConfigError: Error, LocalizedError, Equatable {
    case invalid(String)
    case unsupportedVersion(Int)

    public var errorDescription: String? {
        switch self {
        case .invalid(let message): message
        case .unsupportedVersion(let version): "Configuration version \(version) is not supported. The original file has been preserved."
        }
    }
}
