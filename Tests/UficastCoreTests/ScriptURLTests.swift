import Foundation
import Testing
@testable import UficastCore

private func result(_ text: String, truncated: Bool = false) -> ScriptResult {
    ScriptResult(exitCode: 0, termination: .exited, stdout: Data(text.utf8), stderr: Data(),
                 stdoutTruncated: truncated, stderrTruncated: false)
}

@Test func opensOnlyOneStrictAbsoluteWebURL() throws {
    #expect(try result("\n https://example.com/?q=a%20b \n").outputURL().absoluteString == "https://example.com/?q=a%20b")
    for invalid in ["", "https://example.com\nhttps://example.org", "file:///tmp/file", "javascript:alert(1)",
                    "example.com", "/relative", "https://", "https://example.com/a b", "https://example.com/%xx"] {
        #expect(throws: ScriptRunError.self) { try result(invalid).outputURL() }
    }
    #expect(throws: ScriptRunError.self) { try result("https://example.com", truncated: true).outputURL() }
}
