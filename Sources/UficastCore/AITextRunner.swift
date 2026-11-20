import Foundation

public protocol AITextRunning: Sendable {
    func run(command: String, prompt: String, timeout: Double) async throws -> String
    func cancel() async
}

public enum AITextError: Error, LocalizedError, Equatable {
    case emptyOutput, outputTooLong, failed(String), cancelled

    public var errorDescription: String? {
        switch self {
        case .emptyOutput: "The command printed no answer."
        case .outputTooLong: "The answer was longer than 1 MB."
        case .failed(let message): message
        case .cancelled: "Cancelled."
        }
    }
}

/// Runs the owner's command line through a login shell, so the owner's PATH applies.
/// The prompt goes only to stdin; it never becomes part of argv or shell text.
public actor AITextRunner: AITextRunning {
    private let workingDirectory: URL
    private var current: NativeRun?

    public init(workingDirectory: URL) { self.workingDirectory = workingDirectory }

    public func run(command: String, prompt: String, timeout: Double) async throws -> String {
        // An empty private folder, so a CLI picks up no project instructions.
        try FileManager.default.createDirectory(at: workingDirectory, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        current?.cancel()
        let session = try NativeRun()
        current = session
        defer { if current === session { current = nil } }
        let result = try await withTaskCancellationHandler {
            try await session.execute(executable: "/bin/zsh", arguments: ["-lc", command],
                                      environment: ProcessInfo.processInfo.environment,
                                      directory: workingDirectory.path, timeout: timeout, input: Data(prompt.utf8))
        } onCancel: { session.cancel() }
        switch result.termination {
        case .cancelled: throw AITextError.cancelled
        case .timedOut: throw AITextError.failed("Timed out after \(String(format: "%g", timeout)) s.")
        case .exited: break
        }
        guard result.exitCode == 0 else { throw AITextError.failed(result.failureDescription ?? "Exit code \(result.exitCode)") }
        guard !result.stdoutTruncated else { throw AITextError.outputTooLong }
        let text = String(decoding: result.stdout, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw AITextError.emptyOutput }
        return text
    }

    public func cancel() { current?.cancel() }
}
