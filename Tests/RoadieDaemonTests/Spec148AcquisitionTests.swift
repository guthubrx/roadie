import AppKit
import Foundation
import os
import Testing
import RoadieAX
import RoadieCore
@testable import RoadieDaemon

private final class Acquisition148Provider: SystemSnapshotProviding, Sendable {
    struct State { var scans = 0; var mainScans = 0; var invalidations: Int; var onScan: (@Sendable () -> Void)? }
    let state: OSAllocatedUnfairLock<State>
    let windowsToRead: [WindowSnapshot]
    init(invalidations: Int = 0, windows: [WindowSnapshot] = [powerWindow(1, x: 100), powerWindow(2, x: 500)]) {
        state = .init(initialState: State(invalidations: invalidations)); windowsToRead = windows
    }
    func permissions(prompt: Bool) -> PermissionSnapshot { .init(accessibilityTrusted: true) }
    func displays() -> [DisplaySnapshot] { [powerDisplay()] }
    func windows() -> [WindowSnapshot] {
        let callback = state.withLock { s -> (@Sendable () -> Void)? in
            s.scans += 1; if Thread.isMainThread { s.mainScans += 1 }
            guard s.invalidations > 0 else { return nil }; s.invalidations -= 1; return s.onScan
        }
        callback?(); return windowsToRead
    }
    func existingWindowPIDs() -> [WindowID: Int32]? { Dictionary(uniqueKeysWithValues: windowsToRead.map { ($0.id, $0.pid) }) }
}

@Suite @MainActor struct Spec148AcquisitionTests {
    private func fixture(_ provider: Acquisition148Provider) -> SnapshotService {
        let service = SnapshotService(provider: provider, config: RoadieConfig(),
            intentStore: LayoutIntentStore(path: tempPath("148-intents")),
            stageStore: StageStore(path: tempPath("148-stages")),
            events: EventLog(path: tempPath("148-events")), persistStateChanges: false)
        provider.state.withLock { $0.onScan = { service.invalidateSharedSnapshot() } }
        return service
    }
    @Test func transientInvalidationAtOpeningIsNotAnEmptyList() async throws {
        let provider = Acquisition148Provider(invalidations: 1), service = fixture(provider)
        let loaded = await WindowSwitcherService(service: service).load()
        #expect(loaded.snapshot != nil)
        #expect(Set(loaded.entries.map(\.id)) == [WindowID(rawValue: 1), WindowID(rawValue: 2)])
        #expect(provider.state.withLock { $0.scans } == 2)
        #expect(provider.state.withLock { $0.mainScans } == 0)
    }
    @Test func exhaustedAcquisitionRemainsUnavailableAndBounded() async {
        let provider = Acquisition148Provider(invalidations: 100), service = fixture(provider)
        let loaded = await WindowSwitcherService(service: service).load()
        #expect(loaded.snapshot == nil)
        #expect(provider.state.withLock { $0.scans } == 4)
    }
    @Test func genuinelyEmptySnapshotNeedsNoRetry() async {
        let provider = Acquisition148Provider(windows: []), service = fixture(provider)
        let loaded = await WindowSwitcherService(service: service).load()
        #expect(loaded.snapshot != nil)
        #expect(loaded.entries.isEmpty)
        #expect(provider.state.withLock { $0.scans } == 1)
    }
    @Test func cancellationDoesNotStartAnotherScan() async throws {
        let provider = Acquisition148Provider(invalidations: 100), service = fixture(provider)
        let gate = DispatchSemaphore(value: 0)
        provider.state.withLock { $0.onScan = { service.invalidateSharedSnapshot(); gate.wait() } }
        let task = Task { await WindowSwitcherService(service: service).load() }
        while provider.state.withLock({ $0.scans }) == 0 { try await Task.sleep(for: .milliseconds(1)) }
        task.cancel(); gate.signal()
        #expect(await task.value.snapshot == nil)
        #expect(provider.state.withLock { $0.scans } == 1)
    }

    private func waitUntil(_ predicate: () -> Bool) async throws {
        let limit = Date().addingTimeInterval(3)
        while !predicate(), Date() < limit { try await Task.sleep(for: .milliseconds(10)) }
        #expect(predicate())
    }

    private func visiblePanel() -> WindowSwitcherPanel? {
        NSApplication.shared.windows.compactMap { $0 as? WindowSwitcherPanel }.first { $0.isVisible }
    }

    private func labels(_ view: NSView) -> [String] {
        ((view as? NSTextField).map { [$0.stringValue] } ?? [])
            + view.subviews.flatMap { labels($0) }
    }

    private func capture(_ panel: WindowSwitcherPanel, name: String) throws {
        guard let path = ProcessInfo.processInfo.environment["ROADIE_SPEC148_PROOF_DIR"] else { return }
        let view = try #require(panel.contentView)
        view.layoutSubtreeIfNeeded()
        let bitmap = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        let png = try #require(bitmap.representation(using: .png, properties: [:]))
        let folder = URL(fileURLWithPath: path, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try png.write(to: folder.appendingPathComponent(name + ".png"))
    }

    @Test func unavailableOpeningShowsItsReasonAndTabCanRecover() async throws {
        let provider = Acquisition148Provider(invalidations: 100), service = fixture(provider)
        let controller = WindowSwitcherController(service: service, thumbnails: RailThumbnailStore(),
                                                   events: service.effectiveEvents)
        defer { controller.cancel() }
        controller.show()
        try await waitUntil {
            self.visiblePanel()?.contentView.map { self.labels($0).contains { $0.contains("Lecture des fenêtres indisponible") } } == true
        }
        let panel = try #require(visiblePanel())
        #expect(panel.renderedWindowIDs.isEmpty)
        #expect(!labels(try #require(panel.contentView)).contains("Aucune fenêtre dans ce contexte"))
        #expect(provider.state.withLock { $0.scans } == 4)
        try capture(panel, name: "indisponible")
        provider.state.withLock { $0.invalidations = 0 }
        controller.next()
        try await waitUntil { Set(panel.renderedWindowIDs) == [WindowID(rawValue: 1), WindowID(rawValue: 2)] }
        #expect(!labels(try #require(panel.contentView)).contains { $0.contains("Lecture des fenêtres indisponible") })
        try capture(panel, name: "reprise")
        controller.cancel()
        // Le fondu de fermeture est asynchrone : attendre sa fin, pas seulement orderOut.
        try await waitUntil { !panel.isVisible }
    }

    @Test func cancelledOpeningCannotReopenOnLateAcquisition() async throws {
        let provider = Acquisition148Provider(invalidations: 1), service = fixture(provider)
        let gate = DispatchSemaphore(value: 0)
        provider.state.withLock { $0.onScan = { service.invalidateSharedSnapshot(); gate.wait() } }
        let controller = WindowSwitcherController(service: service, thumbnails: RailThumbnailStore(),
                                                   events: service.effectiveEvents)
        defer { controller.cancel() }
        controller.show()
        try await waitUntil { provider.state.withLock { $0.scans } > 0 }
        controller.cancel(); gate.signal()
        try await Task.sleep(for: .milliseconds(200))
        #expect(visiblePanel() == nil)
        #expect(provider.state.withLock { $0.scans } == 1)
    }

    @Test func failedReloadDoesNotEraseAlreadyRenderedCards() {
        let panel = WindowSwitcherPanel(appearance: .init(config: WindowSwitcherConfig()))
        defer { panel.close() }
        let entry = WindowSwitcherEntry(window: powerWindow(1, x: 100), scope: nil)
        panel.render(entries: [entry], selectedID: entry.id, query: "", images: [:], previewImage: nil, emptyMessage: "Vide")
        panel.showAcquisitionError()
        #expect(panel.renderedWindowIDs == [entry.id])
    }

    @Test func lotGReadOnlyReaderPublicationDoesNotInvalidateConcurrentProducerAcquisition() async throws {
        let provider = Acquisition148Provider(invalidations: 1)
        let service = fixture(provider)
        let entered = OSAllocatedUnfairLock(initialState: false)
        let releaseProducer = DispatchSemaphore(value: 0)
        provider.state.withLock {
            $0.onScan = {
                entered.withLock { $0 = true }
                releaseProducer.wait()
            }
        }
        // 1. Le producteur démarre son relevé AX (en pause sur le sémaphore).
        let producerTask = Task { await service.readerSnapshot(followFocus: true, producerCycle: 60) }
        try await waitUntil { entered.withLock { $0 } }
        // 2. Un lecteur (bordure/rail) publie en lecture seule pendant ce temps :
        //    publicationRevision avance, mais stateMutationRevision reste inchangée.
        let revisionBefore = service.publicationRevision
        let readerResult = await service.readerSnapshot(followFocus: true, producerCycle: nil)
        #expect(readerResult != nil)
        #expect(service.publicationRevision > revisionBefore)
        // 3. Le producteur reprend et réussit du premier coup sans rejet parasite.
        releaseProducer.signal()
        let producerResult = await producerTask.value
        #expect(producerResult != nil)

        // 4. Une vraie invalidation (commande/écriture) continue d'invalider le producteur.
        let invalidatedProvider = Acquisition148Provider(invalidations: 1)
        let invalidatedService = fixture(invalidatedProvider)
        let failedProducer = await invalidatedService.readerSnapshot(followFocus: true, producerCycle: 60)
        #expect(failedProducer == nil)
    }

    @Test func lotJSwitcherLoadReusesFreshFollowFocusSnapshotAndProvisionalLoadAvoidsAX() async throws {
        let provider = Acquisition148Provider(invalidations: 0)
        let service = fixture(provider)
        service.enableQuietReaderReuse(cap: 5.0)
        // Le producteur publie un snapshot `followFocus: true`.
        _ = service.producerSnapshot(cycle: 1.0)
        #expect(provider.state.withLock { $0.scans } == 1)

        // `WindowSwitcherService.load()` réutilise ce snapshot sans relancer de scan AX.
        let switcher = WindowSwitcherService(service: service)
        let loaded = await switcher.load()
        #expect(loaded.snapshot != nil)
        #expect(Set(loaded.entries.map(\.id)) == [WindowID(rawValue: 1), WindowID(rawValue: 2)])
        #expect(provider.state.withLock { $0.scans } == 1)

        // Le repli mémoire (`provisionalLoad`) produit immédiatement la liste sans aucun appel AX.
        let provisional = try #require(switcher.provisionalLoad())
        #expect(Set(provisional.entries.map(\.id)) == [WindowID(rawValue: 1), WindowID(rawValue: 2)])
        #expect(provider.state.withLock { $0.scans } == 1)
    }
}
