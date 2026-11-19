import Foundation
import IOKit.pwr_mgt

public protocol SleepAssertionBackend: Sendable {
    func acquire() async throws -> UInt32
    func release(_ id: UInt32) async throws
}

public struct SystemSleepAssertions: SleepAssertionBackend {
    public init() {}
    public func acquire() async throws -> UInt32 {
        var id: IOPMAssertionID = 0
        // Keeping the display awake also prevents idle system sleep. A system-
        // only assertion allows the screen to turn off while caffeine is active.
        let result = IOPMAssertionCreateWithName(kIOPMAssertPreventUserIdleDisplaySleep as CFString,
                                                IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                                "Uficast Keep Awake" as CFString, &id)
        guard result == kIOReturnSuccess else { throw KeepAwakeError.system(result) }
        return id
    }
    public func release(_ id: UInt32) async throws {
        let result = IOPMAssertionRelease(id)
        guard result == kIOReturnSuccess else { throw KeepAwakeError.system(result) }
    }
}

public struct KeepAwakeState: Sendable {
    public var isActive: Bool
    public var expiresAt: Date?
    public var revision: UInt64
    public static let inactive = KeepAwakeState(isActive: false, expiresAt: nil, revision: 0)
}

public enum KeepAwakeError: Error, LocalizedError, Equatable {
    case invalidDuration
    case busy
    case system(Int32)
    public var errorDescription: String? {
        switch self {
        case .invalidDuration: "Choose a duration greater than zero and no longer than seven days, or use indefinite mode."
        case .busy: "A Keep Awake change is already in progress."
        case .system(let code): "macOS could not change the Keep Awake assertion (error \(code))."
        }
    }
}

public actor KeepAwakeService {
    private let backend: any SleepAssertionBackend
    private var assertion: UInt32?
    private var expiry: Date?
    private var timer: Task<Void, Never>?
    private var generation: UInt64 = 0
    private var revision: UInt64 = 0
    private var busy = false
    private var observer: (@Sendable (KeepAwakeState, String?) -> Void)?

    public init(backend: any SleepAssertionBackend = SystemSleepAssertions()) { self.backend = backend }
    public var state: KeepAwakeState { KeepAwakeState(isActive: assertion != nil, expiresAt: expiry, revision: revision) }

    public func setObserver(_ observer: @escaping @Sendable (KeepAwakeState, String?) -> Void) {
        self.observer = observer
        observer(state, nil)
    }

    @discardableResult
    public func enable(for seconds: TimeInterval? = nil) async throws -> KeepAwakeState {
        guard !busy else { throw KeepAwakeError.busy }
        if let seconds, !seconds.isFinite || seconds <= 0 || seconds > 7 * 86400 { throw KeepAwakeError.invalidDuration }
        busy = true
        defer { busy = false }
        do {
            if assertion == nil { assertion = try await backend.acquire() }
            timer?.cancel()
            generation += 1
            let currentGeneration = generation
            expiry = seconds.map { Date().addingTimeInterval($0) }
            if let seconds {
                timer = Task { [weak self] in
                    do { try await Task.sleep(for: .seconds(seconds)) } catch { return }
                    await self?.expire(generation: currentGeneration)
                }
            } else { timer = nil }
            publish()
            return state
        } catch { publish(error: error.localizedDescription); throw error }
    }

    @discardableResult
    public func disable() async throws -> KeepAwakeState {
        guard !busy else { throw KeepAwakeError.busy }
        busy = true
        defer { busy = false }
        timer?.cancel()
        timer = nil
        generation += 1
        expiry = nil
        do {
            if let assertion { try await backend.release(assertion); self.assertion = nil }
            publish()
            return state
        } catch { publish(error: error.localizedDescription); throw error }
    }

    public func waitUntilIdle() async {
        while busy { try? await Task.sleep(for: .milliseconds(10)) }
    }

    private func expire(generation expected: UInt64) async {
        guard expected == generation, assertion != nil, !busy else { return }
        _ = try? await disable() // Failure is published and ownership remains active for retry.
    }

    private func publish(error: String? = nil) {
        revision += 1
        observer?(state, error)
    }
}
