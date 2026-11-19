import Foundation
import Testing
import UficastCore

private actor FixtureMappings: KeyMappingBackend {
    var mappings: [KeyMapping]
    var writes = 0
    var failWrite = false
    init(_ mappings: [KeyMapping]) { self.mappings = mappings }
    func read() -> [KeyMapping] { mappings }
    func write(_ mappings: [KeyMapping]) throws {
        writes += 1
        if failWrite { throw RemapError.utilityFailed }
        self.mappings = mappings
    }
    func externallyChange(_ mappings: [KeyMapping]) { self.mappings = mappings }
    func failNextWrites() { failWrite = true }
    func allowWrites() { failWrite = false }
}

@Test func parsesBothHidutilFormatsWithoutDiscardingUnknownMetadata() throws {
    #expect(try KeyMapping.parseHidutil(Data("(null)\n".utf8)).isEmpty)
    let table = [KeyMapping.capsLockToF19]
    let json = try JSONEncoder().encode(table)
    #expect(try KeyMapping.parseHidutil(json) == table)
    let openStep = "({HIDKeyboardModifierMappingSrc = 0x700000039; HIDKeyboardModifierMappingDst = 0x70000006e;})"
    #expect(try KeyMapping.parseHidutil(Data(openStep.utf8)) == table)
    #expect(throws: RemapError.self) {
        try KeyMapping.parseHidutil(Data("[{\"HIDKeyboardModifierMappingSrc\":1,\"HIDKeyboardModifierMappingDst\":2,\"unknown\":3}]".utf8))
    }
    let encoded = try KeyMapping.hidutilJSON(table)
    #expect(encoded.contains("UserKeyMapping"))
}

@Test func ownsOnlyItsMappingAndRecoversAcrossAppRestart() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let other = KeyMapping(source: 0x700000004, destination: 0x700000005)
    let backend = FixtureMappings([other])
    let first = KeyboardRemapService(directory: directory, backend: backend)
    _ = try await first.reconcile(enabled: true)
    #expect(await backend.mappings == [other, .capsLockToF19])
    // A second instance simulates a new app process reading durable ownership.
    let next = KeyboardRemapService(directory: directory, backend: backend)
    _ = try await next.reconcile(enabled: true)
    #expect(await backend.writes == 1)
    // Keyboard attach/wake re-publishes an owned table for newly ready services.
    _ = try await next.reconcile(enabled: true, reapplyOwned: true)
    #expect(await backend.writes == 2)
    _ = try await next.reconcile(enabled: false)
    #expect(await backend.mappings == [other])
    #expect(await backend.writes == 3)
    #expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent("keyboard-recovery.json").path))
}

@Test func preexistingAndCompetingMappingsAreNeverClaimedOrOverwritten() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let backend = FixtureMappings([.capsLockToF19])
    let service = KeyboardRemapService(directory: directory, backend: backend)
    _ = try await service.reconcile(enabled: true)
    _ = try await service.reconcile(enabled: false)
    #expect(await backend.writes == 0)
    #expect(await backend.mappings == [.capsLockToF19])
    let competing = KeyMapping(source: KeyMapping.capsLock, destination: 0x7000000E0)
    await backend.externallyChange([competing])
    do { _ = try await service.reconcile(enabled: true); Issue.record("Competing map overwritten") }
    catch { #expect(error as? RemapError == .conflictingCapsLock) }
    #expect(await backend.writes == 0)
}

@Test func disablePreservesExternalChangesAndPreparedRecoverySurvivesWriteFailure() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let backend = FixtureMappings([])
    let service = KeyboardRemapService(directory: directory, backend: backend)
    await backend.failNextWrites()
    do { _ = try await service.reconcile(enabled: true); Issue.record("Write failure ignored") }
    catch { #expect(error as? RemapError == .utilityFailed) }
    #expect(FileManager.default.fileExists(atPath: directory.appendingPathComponent("keyboard-recovery.json").path))
    await backend.allowWrites()
    _ = try await service.reconcile(enabled: true)
    let external = KeyMapping(source: KeyMapping.capsLock, destination: 0x7000000E0)
    await backend.externallyChange([external])
    _ = try await service.reconcile(enabled: false)
    #expect(await backend.mappings == [external])
    #expect(await backend.writes == 2) // Failed attempt plus successful enable; no external restore.
}

@Test func additiveKeyboardPreferenceDefaultsOffForExistingSchemaOneFiles() throws {
    var json = try #require(JSONSerialization.jsonObject(with: Configuration().encoded()) as? [String: Any])
    json.removeValue(forKey: "capsLockToF19Enabled")
    let legacy = try JSONSerialization.data(withJSONObject: json)
    #expect(try Configuration.decode(legacy).capsLockToF19Enabled == false)
}
