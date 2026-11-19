import Foundation
import Testing
import UficastCore

@Test func onlyOneInstanceCanHoldTheLockAndClosingAllowsRelaunch() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("instance.lock")
    let firstAttempt = try InstanceLock.acquire(at: url)
    let first = try #require(firstAttempt)
    #expect(try InstanceLock.acquire(at: url) == nil)
    first.release()
    let nextAttempt = try InstanceLock.acquire(at: url)
    let next = try #require(nextAttempt)
    #expect(try InstanceLock.acquire(at: url) == nil)
    next.release()
}
