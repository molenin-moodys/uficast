import Foundation

public struct KeyMapping: Codable, Equatable, Sendable {
    public var source: UInt64
    public var destination: UInt64
    public init(source: UInt64, destination: UInt64) { self.source = source; self.destination = destination }
    public static let capsLock: UInt64 = 0x700000039
    public static let capsLockToF19 = KeyMapping(source: capsLock, destination: 0x70000006E)
    private enum CodingKeys: String, CodingKey {
        case source = "HIDKeyboardModifierMappingSrc"
        case destination = "HIDKeyboardModifierMappingDst"
    }

    public static func parseHidutil(_ data: Data) throws -> [KeyMapping] {
        let text = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        if text == "(null)" || text == "null" { return [] }
        let object: Any
        if let json = try? JSONSerialization.jsonObject(with: data) { object = json }
        else { object = try PropertyListSerialization.propertyList(from: data, options: [], format: nil) }
        guard let array = object as? [[String: Any]] else { throw RemapError.invalidTable }
        let allowed: Set<String> = ["HIDKeyboardModifierMappingSrc", "HIDKeyboardModifierMappingDst"]
        func number(_ value: Any?) throws -> UInt64 {
            let text: String
            if let value = value as? String { text = value }
            else if let value = value as? NSNumber { text = value.stringValue }
            else { throw RemapError.invalidTable }
            let parsed = text.lowercased().hasPrefix("0x") ? UInt64(text.dropFirst(2), radix: 16) : UInt64(text)
            guard let parsed else { throw RemapError.invalidTable }
            return parsed
        }
        return try array.map {
            // Refuse unknown fields instead of losing metadata during a rewrite.
            guard Set($0.keys) == allowed else { throw RemapError.invalidTable }
            return try KeyMapping(source: number($0["HIDKeyboardModifierMappingSrc"]), destination: number($0["HIDKeyboardModifierMappingDst"]))
        }
    }

    public static func hidutilJSON(_ mappings: [KeyMapping]) throws -> String {
        String(decoding: try JSONEncoder().encode(["UserKeyMapping": mappings]), as: UTF8.self)
    }
}

public enum RemapError: Error, LocalizedError, Equatable {
    case invalidTable
    case conflictingCapsLock
    case busy
    case verificationFailed
    case utilityFailed
    case recoveryVersion
    public var errorDescription: String? {
        switch self {
        case .invalidTable: "Cannot safely interpret the mapping table. Further changes have been stopped."
        case .conflictingCapsLock: "Caps Lock is mapped by another tool. Remove that mapping there before enabling F19."
        case .busy: "A keyboard mapping operation is already in progress."
        case .verificationFailed: "The mapping could not be verified. Recovery state was retained."
        case .utilityFailed: "hidutil failed or timed out. No additional keyboard permissions will be requested."
        case .recoveryVersion: "The remapping recovery file is unsupported. Nothing was changed."
        }
    }
}

public protocol KeyMappingBackend: Sendable {
    func read() async throws -> [KeyMapping]
    func write(_ mappings: [KeyMapping]) async throws
}

public struct HidutilBackend: KeyMappingBackend {
    public init() {}
    public func read() async throws -> [KeyMapping] {
        let result = try await LocalProcess.run(executable: "/usr/bin/hidutil", arguments: ["property", "--get", "UserKeyMapping"])
        guard result.succeeded, !result.stdoutTruncated else { throw RemapError.utilityFailed }
        return try KeyMapping.parseHidutil(result.stdout)
    }
    public func write(_ mappings: [KeyMapping]) async throws {
        let result = try await LocalProcess.run(executable: "/usr/bin/hidutil", arguments: ["property", "--set", KeyMapping.hidutilJSON(mappings)])
        guard result.succeeded else { throw RemapError.utilityFailed }
    }
}
