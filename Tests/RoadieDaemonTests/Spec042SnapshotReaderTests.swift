import Foundation
import os
import Testing
import RoadieAX
import RoadieCore
@testable import RoadieDaemon

private final class ReaderProvider042: SystemSnapshotProviding, Sendable {
    struct State {
        var scans = 0
        var inventories = 0
        var mainThreadScans = 0
        var focusPreparedOnMain = false
        var focusReadOnMain = false
    }
    let state = OSAllocatedUnfairLock(initialState: State())
    let duringScan = OSAllocatedUnfairLock<(@Sendable () -> Void)?>(initialState: nil)
    func permissions(prompt: Bool) -> PermissionSnapshot { .init(accessibilityTrusted: true) }
    func displays() -> [DisplaySnapshot] { [powerDisplay()] }
    func windows() -> [WindowSnapshot] {
        state.withLock { $0.scans += 1; if Thread.isMainThread { $0.mainThreadScans += 1 } }
        duringScan.withLock { $0 }?()
        return [powerWindow(1, x: 100)]
    }
    @MainActor func focusedWindowReader() -> @Sendable () -> WindowID? {
        state.withLock { $0.focusPreparedOnMain = Thread.isMainThread }
        return {
            self.state.withLock { $0.focusReadOnMain = Thread.isMainThread }
            return nil
        }
    }
    func existingWindowPIDs() -> [WindowID: Int32]? {
        state.withLock { $0.inventories += 1 }
        return [WindowID(rawValue: 1): 1]
    }
}

@Suite @MainActor
struct Spec042SnapshotReaderTests {
    private func service(_ provider: ReaderProvider042,
                         clock: @escaping @Sendable () -> Date = { Date(timeIntervalSince1970: 1_000) }) -> SnapshotService {
        SnapshotService(provider: provider, config: RoadieConfig(),
                        stageStore: StageStore(path: tempPath("reader042")),
                        persistStateChanges: false, clock: clock)
    }

    @Test func readersReuseOneAcquisitionOutsideMainAndItsInventory() async throws {
        let provider = ReaderProvider042()
        let service = service(provider)
        let first = Task { await service.readerSnapshot() }
        let second = Task { await service.readerSnapshot() }
        let a = try #require(await first.value)
        let b = try #require(await second.value)
        #expect(a == b)
        _ = service.railWindowIDs(in: a)
        _ = service.railWindowIDs(in: b)
        #expect(provider.state.withLock { $0.scans } == 1)
        #expect(provider.state.withLock { $0.mainThreadScans } == 0)
        #expect(provider.state.withLock { $0.inventories } == 1)
        #expect(provider.state.withLock { $0.focusPreparedOnMain })
        #expect(!provider.state.withLock { $0.focusReadOnMain })
        service.invalidateSharedSnapshot()
        #expect(await service.readerSnapshot() != nil)
        #expect(provider.state.withLock { $0.scans } == 2)
    }

    @Test func invalidationDuringAcquisitionDiscardsTheObservation() async {
        let provider = ReaderProvider042()
        let service = service(provider)
        provider.duringScan.withLock { $0 = { service.invalidateSharedSnapshot() } }
        #expect(await service.readerSnapshot() == nil)
        provider.duringScan.withLock { $0 = nil }
        #expect(await service.readerSnapshot() != nil)
        #expect(provider.state.withLock { $0.scans } == 2)
    }

    @Test func stateChangeDuringAcquisitionDoesNotPublishAnOldObservation() async {
        let provider = ReaderProvider042()
        let service = service(provider)
        let store = service.effectiveStageStore
        provider.duringScan.withLock { $0 = {
            store.mutate { $0.activeDisplayID = DisplayID(rawValue: "changed") }
        } }
        #expect(await service.readerSnapshot() == nil)
        #expect(store.state().activeDisplayID == DisplayID(rawValue: "changed"))
    }

    @Test func producerRemainsFreshForReadersWithoutAnotherScan() async {
        let provider = ReaderProvider042()
        let service = service(provider)
        let produced = service.producerSnapshot(cycle: 0.5)
        #expect(await service.readerSnapshot() == produced)
        #expect(provider.state.withLock { $0.scans } == 1)
    }

    @Test func expiredPublicationRequiresAnotherAcquisition() async {
        let provider = ReaderProvider042()
        let now = OSAllocatedUnfairLock(initialState: Date(timeIntervalSince1970: 1_000))
        let service = service(provider, clock: { now.withLock { $0 } })
        #expect(await service.readerSnapshot() != nil)
        now.withLock { $0.addTimeInterval(0.149) }
        #expect(await service.readerSnapshot() != nil)
        #expect(provider.state.withLock { $0.scans } == 1)
        now.withLock { $0.addTimeInterval(0.002) }
        #expect(await service.readerSnapshot() != nil)
        #expect(provider.state.withLock { $0.scans } == 2)
    }
}
