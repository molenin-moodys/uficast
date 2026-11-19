import Foundation

public actor ConfigStore {
    public let directory: URL
    public var configURL: URL { directory.appendingPathComponent("config.json") }
    public var backupURL: URL { directory.appendingPathComponent("config.backup.json") }

    public init(directory: URL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Uficast", isDirectory: true)) {
        self.directory = directory
    }

    public func load() throws -> Configuration {
        guard FileManager.default.fileExists(atPath: configURL.path) else { return Configuration() }
        return try Configuration.decode(Data(contentsOf: configURL))
    }

    public func save(_ configuration: Configuration) throws {
        let data = try configuration.encoded()
        let files = FileManager.default
        try prepareDirectory()
        if files.fileExists(atPath: configURL.path) {
            let previous = try Data(contentsOf: configURL)
            _ = try Configuration.decode(previous) // Never clobber corrupt or future data.
            try write(previous, to: backupURL)
        } else { try write(data, to: backupURL) }
        try write(data, to: configURL)
    }

    public func restoreBackup() throws -> Configuration {
        let backup = try Data(contentsOf: backupURL)
        let configuration = try Configuration.decode(backup)
        let files = FileManager.default
        try prepareDirectory()
        if files.fileExists(atPath: configURL.path) {
            let existing = try Data(contentsOf: configURL)
            do { _ = try Configuration.decode(existing) }
            catch ConfigError.unsupportedVersion(let version) { throw ConfigError.unsupportedVersion(version) }
            catch { /* Explicit recovery preserves the invalid original below. */ }
            try write(existing, to: directory.appendingPathComponent("config.recovered-\(UUID().uuidString).json"))
        }
        try write(backup, to: configURL)
        return configuration
    }

    private func prepareDirectory() throws {
        let files = FileManager.default
        try files.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try files.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
    }

    private func write(_ data: Data, to url: URL) throws {
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
