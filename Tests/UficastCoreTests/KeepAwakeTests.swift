import Foundation
import Testing
import UficastCore

private actor FixtureAssertions: SleepAssertionBackend {
    var acquisitions = 0
    var releases: [UInt32] = []
    var acquisitionFails = false
    var releaseFails = false
    func acquire() throws -> UInt32 {
        if acquisitionFails { throw KeepAwakeError.system(-1) }
        acquisitions += 1
        return UInt32(acquisitions + 100)
    }
    func release(_ id: UInt32) throws {
        if releaseFails { throw KeepAwakeError.system(-2) }
        releases.append(id)
    }
    func failAcquisition() { acquisitionFails = true }
    func failRelease(_ fail: Bool) { releaseFails = fail }
}

@Test func keepAwakeStartsOffAndRenewalReusesExactlyOneOwnedAssertion() async throws {
    let backend = FixtureAssertions()
    let service = KeepAwakeService(backend: backend)
    #expect(await service.state.isActive == false)
    try await service.enable(for: 30)
    try await service.enable()
    #expect(await backend.acquisitions == 1)
    #expect(await service.state.isActive)
    #expect(await service.state.expiresAt == nil)
    try await service.disable()
    try await service.disable()
    #expect(await backend.releases == [101])
    #expect(await service.state.isActive == false)
}

@Test func timedKeepAwakeExpiresAndReleasesItsAssertion() async throws {
    let backend = FixtureAssertions()
    let service = KeepAwakeService(backend: backend)
    try await service.enable(for: 0.03)
    for _ in 0..<100 {
        if await !service.state.isActive { break }
        try await Task.sleep(for: .milliseconds(10))
    }
    #expect(await service.state.isActive == false)
    #expect(await backend.releases == [101])
}

@Test func anOldTimerCannotDisableAnIndefiniteRenewal() async throws {
    let backend = FixtureAssertions()
    let service = KeepAwakeService(backend: backend)
    try await service.enable(for: 0.03)
    try await service.enable()
    try await Task.sleep(for: .milliseconds(80))
    #expect(await service.state.isActive)
    #expect(await backend.releases.isEmpty)
    try await service.disable()
}

@Test func failedAssertionChangesNeverPretendTheMacIsInAnotherState() async throws {
    let failing = FixtureAssertions()
    await failing.failAcquisition()
    let unavailable = KeepAwakeService(backend: failing)
    do { try await unavailable.enable(); Issue.record("Failed assertion was accepted") }
    catch { #expect(error as? KeepAwakeError == .system(-1)) }
    #expect(await unavailable.state.isActive == false)
    let backend = FixtureAssertions()
    let service = KeepAwakeService(backend: backend)
    try await service.enable()
    await backend.failRelease(true)
    do { try await service.disable(); Issue.record("Failed release was hidden") }
    catch { #expect(error as? KeepAwakeError == .system(-2)) }
    #expect(await service.state.isActive)
    await backend.failRelease(false)
    try await service.disable()
    #expect(await backend.releases == [101])
}
