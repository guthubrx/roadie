import Foundation
import os
import Testing
import RoadieAX
import RoadieCore
@testable import RoadieDaemon

private final class QuietProvider048: SystemSnapshotProviding, Sendable {
    let scans = OSAllocatedUnfairLock(initialState: 0)
    func permissions(prompt: Bool) -> PermissionSnapshot { .init(accessibilityTrusted: true) }
    func displays() -> [DisplaySnapshot] { [powerDisplay()] }
    func windows() -> [WindowSnapshot] {
        scans.withLock { $0 += 1 }
        return [powerWindow(1, x: 100)]
    }
    func existingWindowPIDs() -> [WindowID: Int32]? { [WindowID(rawValue: 1): 1] }
}

/// SPEC-048 A-01 : sans changement observé, un lecteur réutilise le dernier relevé jusqu'au filet (2 s).
@Suite @MainActor
struct Spec048QuietReaderTests {
    private func fixture(_ name: String, quiet: Bool = true) -> (QuietProvider048, SnapshotService, OSAllocatedUnfairLock<Date>) {
        let provider = QuietProvider048()
        let now = OSAllocatedUnfairLock(initialState: Date(timeIntervalSince1970: 1_000))
        let service = SnapshotService(provider: provider, config: RoadieConfig(),
                                      stageStore: StageStore(path: tempPath("spec048-\(name)")),
                                      persistStateChanges: false, clock: { now.withLock { $0 } })
        if quiet { service.enableQuietReaderReuse(cap: 2) }
        return (provider, service, now)
    }

    @Test func quietReaderReusesPublicationUpToTheSafetyNet() async {
        let (provider, service, now) = fixture("quiet")
        #expect(await service.readerSnapshot() != nil)
        now.withLock { $0.addTimeInterval(1) }
        #expect(await service.readerSnapshot() != nil)
        now.withLock { $0.addTimeInterval(0.99) }
        #expect(await service.readerSnapshot() != nil)
        #expect(provider.scans.withLock { $0 } == 1)
    }

    @Test func observationChangeForcesAnotherAcquisition() async {
        let (provider, service, now) = fixture("change")
        #expect(await service.readerSnapshot() != nil)
        now.withLock { $0.addTimeInterval(0.5) }
        service.noteObservationChange()
        #expect(await service.readerSnapshot() != nil)
        #expect(provider.scans.withLock { $0 } == 2)
    }

    @Test func changeInsideFreshWindowStillUsesTheFreshRule() async {
        let (provider, service, now) = fixture("fresh")
        #expect(await service.readerSnapshot() != nil)
        service.noteObservationChange()
        now.withLock { $0.addTimeInterval(0.1) }
        #expect(await service.readerSnapshot() != nil)
        #expect(provider.scans.withLock { $0 } == 1)
    }

    @Test func quietReuseEndsAtTheSafetyNet() async {
        let (provider, service, now) = fixture("cap")
        #expect(await service.readerSnapshot() != nil)
        now.withLock { $0.addTimeInterval(2.01) }
        #expect(await service.readerSnapshot() != nil)
        #expect(provider.scans.withLock { $0 } == 2)
    }

    @Test func readerWithoutTrackingTilerKeepsTheOldRule() async {
        let (provider, service, now) = fixture("modular", quiet: false)
        #expect(await service.readerSnapshot() != nil)
        now.withLock { $0.addTimeInterval(0.2) }
        #expect(await service.readerSnapshot() != nil)
        #expect(provider.scans.withLock { $0 } == 2)
    }

    @Test func commandsKeepTheirOneHundredFiftyMillisecondRule() {
        let (provider, service, now) = fixture("commands")
        _ = service.sharedSnapshot()
        now.withLock { $0.addTimeInterval(0.2) }
        _ = service.sharedSnapshot()
        #expect(provider.scans.withLock { $0 } == 2)
    }

    @Test func schedulerRequestsOutsideSafetyNetNoteAChange() {
        var changes = 0
        let scheduler = TickScheduler(
            tick: { _ in MaintenanceTick(commands: 0, applied: 0, clamped: 0, failed: 0) },
            nextDeadline: { _ in nil },
            isBlocked: { true },
            schedule: { _, _ in {} },
            events: nil,
            onObservationChange: { changes += 1 }
        )
        scheduler.request(cause: "ax:AXFocusedWindowChanged")
        scheduler.request(cause: "ax:AXWindowMoved", delay: .externalChange)
        scheduler.request(cause: "safety", delay: .safetyNet)
        #expect(changes == 2)
    }
}
