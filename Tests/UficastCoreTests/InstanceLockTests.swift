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
    // A process that another test spawns at this moment briefly holds a kernel copy of the
    // descriptor until exec closes it (O_CLOEXEC), so the lock may free a moment later.
    var nextAttempt = try InstanceLock.acquire(at: url)
    let deadline = Date().addingTimeInterval(1)
    while nextAttempt == nil, Date() < deadline {
        usleep(10_000)
        nextAttempt = try InstanceLock.acquire(at: url)
    }
    let next = try #require(nextAttempt)
    #expect(try InstanceLock.acquire(at: url) == nil)
    next.release()
}
