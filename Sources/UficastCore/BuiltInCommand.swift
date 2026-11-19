import Foundation

public enum BuiltInCommand: String, CaseIterable, Sendable {
    case caffeine, decaffeine

    public init?(entryID: String) {
        guard entryID.hasPrefix("builtin:") else { return nil }
        self.init(rawValue: String(entryID.dropFirst("builtin:".count)))
    }

    public var keepsAwake: Bool { self == .caffeine }
    public var symbolName: String { keepsAwake ? "cup.and.saucer.fill" : "cup.and.saucer" }
    public var entry: LauncherEntry {
        LauncherEntry(id: "builtin:\(rawValue)", name: rawValue, kind: .builtIn,
                      fileURL: URL(string: "uficast://command/\(rawValue)")!,
                      alias: keepsAwake ? "cafe" : "decafe")
    }
    public static var entries: [LauncherEntry] { allCases.map(\.entry) }
}
