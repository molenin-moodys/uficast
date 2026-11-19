import Foundation

public struct LauncherEntry: Identifiable, Hashable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case application, script, builtIn
        public var title: String {
            switch self {
            case .application: "Application"
            case .script: "Script"
            case .builtIn: "Command"
            }
        }
    }
    public var id: String
    public var name: String
    public var kind: Kind
    public var fileURL: URL
    public var alias: String?
    public var isEnabled: Bool

    public init(id: String, name: String, kind: Kind = .application, fileURL: URL,
                alias: String? = nil, isEnabled: Bool = true) {
        self.id = id
        self.name = name
        self.kind = kind
        self.fileURL = fileURL
        self.alias = alias
        self.isEnabled = isEnabled
    }
}

public struct UsageRecord: Sendable {
    public var count: Int
    public var lastUsed: Date
    public init(count: Int = 0, lastUsed: Date = .distantPast) {
        self.count = count
        self.lastUsed = lastUsed
    }
}

public enum SearchText {
    public static func normalize(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .lowercased()
    }
}
