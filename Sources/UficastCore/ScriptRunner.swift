import Foundation
import UficastProcess

public enum ScriptRunError: Error, LocalizedError, Equatable {
    case alreadyRunning
    case argumentRequired
    case unexpectedArgument
    case nullCharacter
    case system(Int32)
    case invalidURL
    case truncatedURL

    public var errorDescription: String? {
        switch self {
        case .alreadyRunning: "This command is already running."
        case .argumentRequired: "Enter an argument before running this command."
        case .unexpectedArgument: "This command does not accept an argument."
        case .nullCharacter: "Arguments cannot contain a null character."
        case .system(let code): "Could not run the process: \(String(cString: strerror(code))) (\(code))."
        case .invalidURL: "Expected exactly one absolute HTTP(S) URL on stdout."
        case .truncatedURL: "The URL output exceeded the output limit."
        }
    }
}

public struct ScriptResult: Sendable {
    public enum Termination: Equatable, Sendable { case exited, timedOut, cancelled }
    public var exitCode: Int32
    public var termination: Termination
    public var stdout: Data
    public var stderr: Data
    public var stdoutTruncated: Bool
    public var stderrTruncated: Bool
    public var succeeded: Bool { termination == .exited && exitCode == 0 }

    public func outputURL() throws -> URL {
        guard succeeded else { throw ScriptRunError.invalidURL }
        guard !stdoutTruncated else { throw ScriptRunError.truncatedURL }
        guard let text = String(data: stdout, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty, !text.contains(where: \.isWhitespace),
              let url = URL(string: text, encodingInvalidCharacters: false),
              let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme),
              let host = url.host, !host.isEmpty else { throw ScriptRunError.invalidURL }
        return url
    }
}

public actor ScriptRunner {
    private var running: [String: NativeRun] = [:]
    public var activeCommandIDs: Set<String> { Set(running.keys) }
    public init() {}

    public func run(_ command: ScriptCommand, argument: String? = nil) async throws -> ScriptResult {
        try Task.checkCancellation()
        guard running[command.id] == nil else { throw ScriptRunError.alreadyRunning }
        var config = Configuration()
        config.scripts = [command]
        _ = try config.validated()
        if command.requiresArgument {
            guard let argument, !argument.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw ScriptRunError.argumentRequired
            }
        } else if argument != nil { throw ScriptRunError.unexpectedArgument }
        guard argument?.contains("\0") != true else { throw ScriptRunError.nullCharacter }
        let session = try NativeRun()
        running[command.id] = session
        defer { running[command.id] = nil }
        return try await withTaskCancellationHandler {
            try await session.execute(command, argument: argument)
        } onCancel: { session.cancel() }
    }

    public func cancel(_ id: String) { running[id]?.cancel() }
    public func cancelAll() { running.values.forEach { $0.cancel() } }
    public func waitUntilIdle() async {
        while !running.isEmpty { try? await Task.sleep(for: .milliseconds(25)) }
    }
}

/// The pointer is worker-confined, except for C's atomic cancellation flag.
private final class NativeRun: @unchecked Sendable {
    private let process: OpaquePointer
    init() throws {
        guard let process = uf_process_create() else { throw ScriptRunError.system(ENOMEM) }
        self.process = process
    }
    deinit { uf_process_destroy(process) }
    func cancel() { uf_process_cancel(process) }

    func execute(_ command: ScriptCommand, argument: String?) async throws -> ScriptResult {
        let script = Configuration.fileURL(command.path)
        let interpreter = command.interpreter.map { Configuration.fileURL($0).path }
        var arguments = interpreter != nil ? [script.path] : []
        if let argument { arguments.append(argument) }
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        environment.merge(command.environment) { _, override in override }
        let directory = command.workingDirectory.map { Configuration.fileURL($0).path } ?? script.deletingLastPathComponent().path
        return try await execute(executable: interpreter ?? script.path, arguments: arguments,
                                 environment: environment, directory: directory, timeout: command.timeoutSeconds)
    }

    func execute(executable: String, arguments: [String], environment: [String: String],
                 directory: String, timeout: Double) async throws -> ScriptResult {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .utility).async { [self] in
                let arguments = [executable] + arguments
                let code = Self.withCStringArray(arguments) { argv in
                    Self.withCStringArray(environment.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }) { env in
                        uf_process_run(process, executable, argv, env, directory, timeout, 1024 * 1024)
                    }
                }
                guard code == 0 else { continuation.resume(throwing: ScriptRunError.system(code)); return }
                let termination: ScriptResult.Termination = switch uf_process_reason(process) {
                case Int32(UF_PROCESS_TIMED_OUT): .timedOut
                case Int32(UF_PROCESS_CANCELLED): .cancelled
                default: .exited
                }
                continuation.resume(returning: ScriptResult(
                    exitCode: uf_process_exit_code(process), termination: termination,
                    stdout: Self.data(uf_process_stdout(process), count: uf_process_stdout_size(process)),
                    stderr: Self.data(uf_process_stderr(process), count: uf_process_stderr_size(process)),
                    stdoutTruncated: uf_process_stdout_truncated(process), stderrTruncated: uf_process_stderr_truncated(process)
                ))
            }
        }
    }

    private static func data(_ pointer: UnsafePointer<UInt8>?, count: Int) -> Data {
        guard let pointer, count > 0 else { return Data() }
        return Data(bytes: pointer, count: count)
    }

    private static func withCStringArray(_ strings: [String], body: (UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>) -> Int32) -> Int32 {
        var pointers = strings.map { strdup($0) } + [nil]
        defer { pointers.forEach { free($0) } }
        guard !pointers.dropLast().contains(where: { $0 == nil }) else { return ENOMEM }
        return pointers.withUnsafeMutableBufferPointer { body($0.baseAddress!) }
    }
}


/// Fixed executable/argv utility calls reuse the same bounded native worker.
public enum LocalProcess {
    public static func run(executable: String, arguments: [String], timeout: Double = 5) async throws -> ScriptResult {
        try Task.checkCancellation()
        guard executable.hasPrefix("/"), !executable.contains("\0"),
              !arguments.contains(where: { $0.contains("\0") }), timeout.isFinite, timeout > 0 else {
            throw ConfigError.invalid("Invalid utility process parameters.")
        }
        let session = try NativeRun()
        return try await withTaskCancellationHandler {
            try await session.execute(executable: executable, arguments: arguments,
                                      environment: ProcessInfo.processInfo.environment, directory: "/", timeout: timeout)
        } onCancel: { session.cancel() }
    }
}
