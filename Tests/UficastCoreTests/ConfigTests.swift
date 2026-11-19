import Foundation
import Testing
import UficastCore

@Test func aliasConflictsAreGlobalAndDisabledItemsCanShareAliases() throws {
    var config = Configuration()
    config.applications["app:fixture"] = AppOverride(alias: "K")
    config.scripts = [ScriptCommand(name: "Kibana", alias: "k", path: "/fixture/script.sh")]
    #expect(throws: ConfigError.self) { try config.validated() }
    config.scripts[0].isEnabled = false
    _ = try config.validated()
    config.scripts[0].alias = "has space"
    #expect(throws: ConfigError.self) { try config.validated() }
}

@Test func configurationRoundTripsAndRetainsMissingApplicationOverrides() throws {
    var config = Configuration()
    config.applications["app:fixture"] = AppOverride(alias: "f", isEnabled: false, lastKnownName: "Fixture", fallbackPath: "/missing/Fixture.app")
    config.scripts = [ScriptCommand(name: "Fixture", path: "~/scripts/fixture.sh", interpreter: "/bin/zsh", requiresArgument: true)]
    #expect(try Configuration.decode(config.encoded()) == config)
    let entries = config.entries(catalog: [])
    #expect(entries.count == 2)
    #expect(entries.first?.name == "Fixture")
    #expect(entries.first?.isEnabled == false)
}

@Test func atomicSaveBackupAndExplicitRecoveryPreserveInvalidOriginal() async throws {
    let files = FileManager.default
    let directory = files.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? files.removeItem(at: directory) }
    let store = ConfigStore(directory: directory)
    let first = Configuration()
    try await store.save(first)
    var second = first
    second.applicationRoots = ["/fixture"]
    try await store.save(second)
    #expect(try await store.load() == second)
    let backup = await store.backupURL
    #expect(try Configuration.decode(Data(contentsOf: backup)) == first)
    let path = await store.configURL
    let invalid = Data("broken json".utf8)
    try invalid.write(to: path)
    do { try await store.save(second); Issue.record("Invalid data was overwritten") } catch {}
    #expect(try Data(contentsOf: path) == invalid)
    #expect(try await store.restoreBackup() == first)
    let recovered = try files.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).filter { $0.lastPathComponent.hasPrefix("config.recovered-") }
    #expect(recovered.count == 1)
    #expect(try Data(contentsOf: #require(recovered.first)) == invalid)
}

@Test func futureSchemaIsProtectedDuringLoadSaveAndRecovery() async throws {
    let files = FileManager.default
    let directory = files.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? files.removeItem(at: directory) }
    let store = ConfigStore(directory: directory)
    try await store.save(Configuration())
    try await store.save(Configuration())
    let path = await store.configURL
    let future = Data("{\"schemaVersion\":999}".utf8)
    try future.write(to: path)
    for operation in 0..<3 {
        do {
            switch operation {
            case 0: _ = try await store.load()
            case 1: try await store.save(Configuration())
            default: _ = try await store.restoreBackup()
            }
            Issue.record("Future config was accepted")
        } catch { #expect(error as? ConfigError == .unsupportedVersion(999)) }
    }
    #expect(try Data(contentsOf: path) == future)
}
