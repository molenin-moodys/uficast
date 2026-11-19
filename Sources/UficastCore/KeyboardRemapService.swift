import Foundation

public actor KeyboardRemapService {
    private struct Recovery: Codable {
        var version = 1
        var installed = KeyMapping.capsLockToF19
        var previous: KeyMapping?
    }
    private let backend: any KeyMappingBackend
    private let directory: URL
    private var busy = false
    private var recoveryURL: URL { directory.appendingPathComponent("keyboard-recovery.json") }

    public init(directory: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Uficast"),
                backend: any KeyMappingBackend = HidutilBackend()) {
        self.directory = directory
        self.backend = backend
    }

    public func waitUntilIdle() async {
        while busy { try? await Task.sleep(for: .milliseconds(25)) }
    }

    public func reconcile(enabled: Bool, reapplyOwned: Bool = false) async throws -> String {
        guard !busy else { throw RemapError.busy }
        busy = true
        defer { busy = false }
        let recovery = try loadRecovery()
        guard enabled || recovery != nil else { return "Disabled. External mappings are unchanged." }
        let current = try await backend.read()
        let caps = current.filter { $0.source == KeyMapping.capsLock }
        if enabled {
            guard caps.count <= 1 else { throw RemapError.conflictingCapsLock }
            if caps.first == .capsLockToF19 {
                // A new keyboard service may not have inherited the global table.
                // Re-publish only a mapping whose ownership is already durable.
                if recovery != nil, reapplyOwned {
                    try await backend.write(current)
                    guard equivalent(try await backend.read(), current) else { throw RemapError.verificationFailed }
                }
                return recovery == nil ? "Caps Lock → F19 is managed externally; Uficast will leave it unchanged." : "Caps Lock → F19 is enabled."
            }
            guard caps.isEmpty else { throw RemapError.conflictingCapsLock }
            let ownership = recovery ?? Recovery(previous: nil)
            try saveRecovery(ownership) // Record intent before the first OS mutation.
            let updated = current + [.capsLockToF19]
            try await backend.write(updated)
            guard equivalent(try await backend.read(), updated) else { throw RemapError.verificationFailed }
            return "Caps Lock → F19 is enabled. Assign F19 to the system input-source shortcut."
        }
        guard let recovery else { return "Disabled. External mappings are unchanged." }
        guard caps == [recovery.installed] else {
            try removeRecovery()
            return "Mapping changed externally; it was left unchanged."
        }
        var restored = current.filter { $0.source != KeyMapping.capsLock }
        if let previous = recovery.previous { restored.append(previous) }
        try await backend.write(restored)
        guard equivalent(try await backend.read(), restored) else { throw RemapError.verificationFailed }
        try removeRecovery()
        return "Disabled. Uficast's mapping was restored; other mappings were preserved."
    }

    public func checkStatus() async throws -> String {
        guard !busy else { throw RemapError.busy }
        busy = true
        defer { busy = false }
        let caps = try await backend.read().filter { $0.source == KeyMapping.capsLock }
        if caps == [.capsLockToF19] { return "Caps Lock currently maps to F19." }
        if caps.isEmpty { return "Caps Lock has no hidutil mapping." }
        return "Caps Lock has another mapping; Uficast will not overwrite it."
    }

    private func equivalent(_ left: [KeyMapping], _ right: [KeyMapping]) -> Bool {
        func sorted(_ items: [KeyMapping]) -> [KeyMapping] {
            items.sorted { $0.source == $1.source ? $0.destination < $1.destination : $0.source < $1.source }
        }
        return sorted(left) == sorted(right)
    }

    private func loadRecovery() throws -> Recovery? {
        guard FileManager.default.fileExists(atPath: recoveryURL.path) else { return nil }
        let record = try JSONDecoder().decode(Recovery.self, from: Data(contentsOf: recoveryURL))
        guard record.version == 1, record.installed == .capsLockToF19,
              record.previous == nil || record.previous?.source == KeyMapping.capsLock else { throw RemapError.recoveryVersion }
        return record
    }

    private func saveRecovery(_ recovery: Recovery) throws {
        let files = FileManager.default
        try files.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try files.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        try JSONEncoder().encode(recovery).write(to: recoveryURL, options: .atomic)
        try files.setAttributes([.posixPermissions: 0o600], ofItemAtPath: recoveryURL.path)
    }

    private func removeRecovery() throws { try FileManager.default.removeItem(at: recoveryURL) }
}
