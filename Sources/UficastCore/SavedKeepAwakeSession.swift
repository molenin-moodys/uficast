import Foundation

/// Local remembered state; assertion ownership itself never survives a process.
public struct SavedKeepAwakeSession: Codable, Equatable, Sendable {
    public var isActive: Bool
    public var expiresAt: Date?
    public init(isActive: Bool = false, expiresAt: Date? = nil) {
        self.isActive = isActive
        self.expiresAt = expiresAt
    }
    public init(state: KeepAwakeState) {
        self.init(isActive: state.isActive, expiresAt: state.expiresAt)
    }
}

extension KeepAwakeService {
    @discardableResult
    public func restore(_ session: SavedKeepAwakeSession, now: Date = Date()) async throws -> KeepAwakeState {
        guard session.isActive else { return try await disable() }
        if let deadline = session.expiresAt {
            let remaining = deadline.timeIntervalSince(now)
            guard remaining > 0 else { return try await disable() }
            return try await enable(for: min(remaining, 7 * 86400))
        }
        return try await enable()
    }
}
