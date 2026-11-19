import Foundation
import Testing
import UficastCore

private let mebibyte = 1024 * 1024

@Test func stdinRoundTripsLargeInput() async throws {
    let input = Data(String(repeating: "abc\n", count: 2 * mebibyte / 4).utf8)
    let result = try await LocalProcess.run(executable: "/bin/cat", arguments: [], input: input)
    #expect(result.succeeded)
    #expect(result.stdoutTruncated)
    #expect(result.stdout.count == mebibyte)
    #expect(result.stdout == input.prefix(mebibyte))
}

@Test func stdinSmallInputExact() async throws {
    let input = Data("héllo <b> & ünïcode\n".utf8)
    let result = try await LocalProcess.run(executable: "/bin/cat", arguments: [], input: input)
    #expect(result.succeeded)
    #expect(result.stdout == input)
}

@Test func childThatExitsEarlyDoesNotHangOrCrash() async throws {
    // The child never reads; writing must stop on EPIPE instead of raising SIGPIPE.
    let input = Data(repeating: 0x61, count: 4 * mebibyte)
    let start = ContinuousClock.now
    let result = try await LocalProcess.run(executable: "/usr/bin/true", arguments: [], input: input)
    #expect(start.duration(to: .now) < .seconds(5))
    #expect(result.termination == .exited)
    #expect(result.exitCode == 0)
}

@Test func timeoutStillAppliesWithPendingInput() async throws {
    let input = Data(repeating: 0x61, count: mebibyte)
    let result = try await LocalProcess.run(executable: "/bin/sleep", arguments: ["5"], input: input, timeout: 0.5)
    #expect(result.termination == .timedOut)
}
