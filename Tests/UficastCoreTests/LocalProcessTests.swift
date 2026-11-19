import Foundation
import Testing
import UficastCore

@Test func utilityCallsPreserveFixedArgumentBoundaries() async throws {
    let result = try await LocalProcess.run(executable: "/usr/bin/printf", arguments: ["%s|%s", "property", "{\"UserKeyMapping\":[]}"])
    #expect(result.succeeded)
    #expect(String(decoding: result.stdout, as: UTF8.self) == "property|{\"UserKeyMapping\":[]}")
}
