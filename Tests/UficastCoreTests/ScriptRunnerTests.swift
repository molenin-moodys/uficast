import Foundation
import Testing
import UficastCore

private struct ScriptFixture {
    let directory: URL
    let path: URL
    init(_ source: String, extension suffix: String = "sh") throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        path = directory.appendingPathComponent("fixture.\(suffix)")
        try Data(source.utf8).write(to: path)
    }
    func remove() { try? FileManager.default.removeItem(at: directory) }
    var command: ScriptCommand { ScriptCommand(name: "Fixture", path: path.path, interpreter: "/bin/sh") }
}

@Test func scriptReceivesExactlyOneUnchangedArgumentWithoutEvaluation() async throws {
    let fixture = try ScriptFixture("printf '%s\\000' \"$#\"; printf '%s' \"$1\"")
    defer { fixture.remove() }
    var command = fixture.command
    command.requiresArgument = true
    let input = "  Unicode: Привет 'quoted' \"double\"; $(touch leaked) `touch leaked`\nsecond line  "
    let result = try await ScriptRunner().run(command, argument: input)
    #expect(result.succeeded)
    #expect(result.stdout == Data("1\0\(input)".utf8))
    #expect(!FileManager.default.fileExists(atPath: fixture.directory.appendingPathComponent("leaked").path))
}

@Test func noArgumentWorkingDirectoryAndExplicitEnvironment() async throws {
    let fixture = try ScriptFixture("printf '%s|%s|%s|%s' \"$#\" \"$PWD\" \"$UFICAST_FIXTURE\" \"$PATH\"")
    defer { fixture.remove() }
    var command = fixture.command
    command.environment = ["UFICAST_FIXTURE": "literal $HOME value", "PATH": "/fixture/path"]
    let result = try await ScriptRunner().run(command)
    #expect(result.succeeded)
    let fields = String(decoding: result.stdout, as: UTF8.self).components(separatedBy: "|")
    #expect(fields.count == 4)
    #expect(fields[0] == "0")
    #expect(URL(fileURLWithPath: fields[1]).resolvingSymlinksInPath() == fixture.directory.resolvingSymlinksInPath())
    #expect(fields[2] == "literal $HOME value")
    #expect(fields[3] == "/fixture/path")
}

@Test func drainsBothPipesBeyondCaptureLimitWithoutDeadlock() async throws {
    let fixture = try ScriptFixture("(/bin/dd if=/dev/zero bs=65536 count=20 2>/dev/null) >&2 & /bin/dd if=/dev/zero bs=65536 count=20 2>/dev/null; wait")
    defer { fixture.remove() }
    let result = try await ScriptRunner().run(fixture.command)
    #expect(result.succeeded)
    #expect(result.stdout.count == 1024 * 1024)
    #expect(result.stderr.count == 1024 * 1024)
    #expect(result.stdoutTruncated && result.stderrTruncated)
}

@Test func timeoutStopsAnUncooperativeShellAndItsChild() async throws {
    let fixture = try ScriptFixture("trap '' TERM; /bin/sh -c '/bin/sleep 0.9; echo leaked > leaked' & wait")
    defer { fixture.remove() }
    var command = fixture.command
    command.timeoutSeconds = 0.1
    let start = ContinuousClock.now
    let result = try await ScriptRunner().run(command)
    #expect(result.termination == .timedOut)
    #expect(start.duration(to: .now) < .seconds(2))
    try await Task.sleep(for: .seconds(1))
    #expect(!FileManager.default.fileExists(atPath: fixture.directory.appendingPathComponent("leaked").path))
}

@Test func timeoutHandlesLeaderExitingWhileChildHoldsPipes() async throws {
    let fixture = try ScriptFixture("/bin/sleep 20 & exit 0")
    defer { fixture.remove() }
    var command = fixture.command
    command.timeoutSeconds = 0.1
    let result = try await ScriptRunner().run(command)
    #expect(result.termination == .timedOut)
    #expect(!result.succeeded)
}

@Test func cancellationAndDuplicateRunProtection() async throws {
    let fixture = try ScriptFixture("/bin/sleep 20")
    defer { fixture.remove() }
    let command = fixture.command
    let runner = ScriptRunner()
    let first = Task { try await runner.run(command) }
    for _ in 0..<100 {
        if await runner.activeCommandIDs.contains(command.id) { break }
        try await Task.sleep(for: .milliseconds(5))
    }
    do { _ = try await runner.run(command); Issue.record("Duplicate command was accepted") }
    catch { #expect(error as? ScriptRunError == .alreadyRunning) }
    first.cancel()
    let result = try await first.value
    #expect(result.termination == .cancelled)
    #expect(await runner.activeCommandIDs.isEmpty)
}

@Test func missingExecutableAndNonExecutableScriptAreReported() async throws {
    let fixture = try ScriptFixture("exit 0")
    defer { fixture.remove() }
    var command = fixture.command
    command.interpreter = "/does-not-exist/interpreter"
    do { _ = try await ScriptRunner().run(command); Issue.record("Missing interpreter ran") }
    catch { #expect(error as? ScriptRunError == .system(ENOENT)) }
    command.interpreter = nil
    do { _ = try await ScriptRunner().run(command); Issue.record("Non-executable script ran") }
    catch { #expect(error as? ScriptRunError == .system(EACCES)) }
}

@Test func nonzeroExitKeepsStderrSeparateAndNeverYieldsURL() async throws {
    let fixture = try ScriptFixture("printf 'https://example.com'; printf 'failed' >&2; exit 7")
    defer { fixture.remove() }
    let result = try await ScriptRunner().run(fixture.command)
    #expect(result.exitCode == 7)
    #expect(String(decoding: result.stderr, as: UTF8.self) == "failed")
    #expect(result.failureDescription == "Exit code 7 — failed")
    #expect(throws: ScriptRunError.self) { try result.outputURL() }
}

@Test func failedScriptShowsStdoutWhenStderrIsEmpty() async throws {
    let fixture = try ScriptFixture("printf 'Unknown input prefix. Expected demo-*.'; exit 2")
    defer { fixture.remove() }
    let result = try await ScriptRunner().run(fixture.command)
    #expect(result.failureDescription == "Exit code 2 — Unknown input prefix. Expected demo-*.")
}

@Test func appleScriptReceivesArgumentWithoutAutomationOrAccessibility() async throws {
    let fixture = try ScriptFixture("on run argv\nreturn item 1 of argv\nend run", extension: "applescript")
    defer { fixture.remove() }
    var command = fixture.command
    command.interpreter = "/usr/bin/osascript"
    command.requiresArgument = true
    let result = try await ScriptRunner().run(command, argument: "quoted \"Привет\"")
    #expect(result.succeeded)
    #expect(String(decoding: result.stdout, as: UTF8.self) == "quoted \"Привет\"\n")
}
