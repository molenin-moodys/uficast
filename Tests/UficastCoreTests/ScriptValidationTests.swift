import Foundation
import Testing
import UficastCore

@Test func invalidArgumentDoesNotLaunchAProcess() async throws {
    let runner = ScriptRunner()
    var command = ScriptCommand(name: "Never launched", path: "/missing/file", requiresArgument: true)
    for value: String? in [nil, " \n ", "valid\0invalid"] {
        do { _ = try await runner.run(command, argument: value); Issue.record("Invalid argument accepted") }
        catch {
            #expect(error as? ScriptRunError == (value?.contains("\0") == true ? .nullCharacter : .argumentRequired))
        }
    }
    command.requiresArgument = false
    do { _ = try await runner.run(command, argument: "unexpected"); Issue.record("Unexpected argument accepted") }
    catch { #expect(error as? ScriptRunError == .unexpectedArgument) }
    #expect(await runner.activeCommandIDs.isEmpty)
}
