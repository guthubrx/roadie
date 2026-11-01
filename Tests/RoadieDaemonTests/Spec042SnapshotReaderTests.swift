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

@Suite @MainActor struct Spec149ProducerTests {
    @Test func slowProducerLeavesMainActorFreeAndDiscardsInvalidatedObservation() async throws {
        let provider = ReaderProvider042()
        let gate = DispatchSemaphore(value: 0)
        provider.duringScan.withLock { $0 = { gate.wait() } }
        let service = SnapshotService(provider: provider, config: RoadieConfig(),
            stageStore: StageStore(path: tempPath("producer149")), persistStateChanges: false)
        let task = Task { await service.readerSnapshot(producerCycle: 0.5) }
        for _ in 0..<100 {
            if provider.state.withLock({ $0.scans }) > 0 { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(provider.state.withLock { $0.scans } == 1)
        #expect(provider.state.withLock { $0.mainThreadScans } == 0)
        service.invalidateSharedSnapshot()
        gate.signal()
        #expect(await task.value == nil)
        provider.duringScan.withLock { $0 = nil }
        #expect(await service.readerSnapshot(producerCycle: 0.5) != nil)
        #expect(provider.state.withLock { $0.mainThreadScans } == 0)
    }

    @Test func preparedMaintainerDoesNotRepeatTheScanOnMain() async throws {
        let provider = ReaderProvider042()
        let service = SnapshotService(provider: provider, config: RoadieConfig(),
            stageStore: StageStore(path: tempPath("maintainer149")), persistStateChanges: false)
        let maintainer = LayoutMaintainer(service: service)
        #expect(await maintainer.prepareTick())
        _ = maintainer.tick()
        #expect(provider.state.withLock { $0.scans } == 1)
        #expect(provider.state.withLock { $0.mainThreadScans } == 0)
    }
}

extension Spec149ProducerTests {
    @Test func replayProviderPreparesFocusOnMainAndReadsItOutsideMain() async throws {
        let base = ReaderProvider042()
        let provider = ReplayableSnapshotProvider(base: base)
        let service = SnapshotService(provider: provider, config: RoadieConfig(),
            stageStore: StageStore(path: tempPath("focus-replay149")), persistStateChanges: false)
        #expect(await service.readerSnapshot(producerCycle: 0.5) != nil)
        #expect(base.state.withLock { $0.focusPreparedOnMain })
        #expect(!base.state.withLock { $0.focusReadOnMain })
        provider.replayLastScan()
        _ = service.snapshot()
        #expect(base.state.withLock { $0.scans } == 1)
    }
}

extension Spec149ProducerTests {
    @Test func cancelledRestoreReadKeepsTheExistingSnapshot() async throws {
        let provider = ReaderProvider042(), gate = DispatchSemaphore(value: 0)
        provider.duringScan.withLock { $0 = { gate.wait() } }
        let service = SnapshotService(provider: provider, config: RoadieConfig(),
            stageStore: StageStore(path: tempPath("restore-reader149")), persistStateChanges: false)
        let path = tempPath("restore149")
        let original = Data("retour arrière conservé".utf8)
        try original.write(to: URL(fileURLWithPath: path))
        defer { try? FileManager.default.removeItem(atPath: path) }
        let restore = RestoreSafetyService(path: path, service: service)
        let task = Task { try await restore.writeSnapshotAsync() }
        for _ in 0..<100 {
            if provider.state.withLock({ $0.scans }) > 0 { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(provider.state.withLock { $0.mainThreadScans } == 0)
        task.cancel()
        gate.signal()
        #expect(try await task.value == nil)
        #expect(try Data(contentsOf: URL(fileURLWithPath: path)) == original)
    }

    @Test func asyncRestorePersistsTheAcquiredFramesWithoutAnotherScan() async throws {
        let provider = ReaderProvider042()
        let service = SnapshotService(provider: provider, config: RoadieConfig(),
            stageStore: StageStore(path: tempPath("restore-save-reader149")), persistStateChanges: false)
        let path = tempPath("restore-save149")
        defer { try? FileManager.default.removeItem(atPath: path) }
        let restore = RestoreSafetyService(path: path, service: service)
        let saved = try #require(try await restore.writeSnapshotAsync())
        #expect(saved.windows.count == 1)
        #expect(provider.state.withLock { $0.scans } == 1)
        #expect(provider.state.withLock { $0.mainThreadScans } == 0)
        #expect(FileManager.default.fileExists(atPath: path))
    }
}
