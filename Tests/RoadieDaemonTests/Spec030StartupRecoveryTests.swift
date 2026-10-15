import CoreGraphics
import Foundation
import Testing
import RoadieAX
import RoadieCore
@testable import RoadieDaemon

private final class StartupRecoveryProvider: SystemSnapshotProviding, @unchecked Sendable {
    var trusted = true
    var liveWindows: [WindowSnapshot] = []
    var liveDisplays = [powerDisplay("host")]
    var windowReadCount = 0
    func permissions(prompt: Bool) -> PermissionSnapshot { PermissionSnapshot(accessibilityTrusted: trusted) }
    func displays() -> [DisplaySnapshot] { liveDisplays }
    func windows() -> [WindowSnapshot] {
        windowReadCount += 1
        return liveWindows
    }
}

private final class StartupRecoveryWriter: WindowFrameWriting, @unchecked Sendable {
    func setFrame(_ frame: CGRect, of window: WindowSnapshot) -> CGRect? { frame }
}

@Suite
struct Spec030StartupRecoveryTests {
    private func fixture(_ provider: any SystemSnapshotProviding) -> (StageStore, SnapshotService, URL) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("roadie-030-\(UUID())")
        let store = StageStore(path: directory.appendingPathComponent("stages.json").path)
        let externalWindow = powerWindow(30030, x: 100)
        store.save(PersistentStageState(scopes: [
            PersistentStageScope(displayID: DisplayID(rawValue: "host"), stages: [
                PersistentStage(id: StageID(rawValue: "1"), name: "Host")
            ]),
            PersistentStageScope(displayID: DisplayID(rawValue: "external"), stages: [
                PersistentStage(id: StageID(rawValue: "4"), name: "Code", mode: .spatialBsp, members: [
                    PersistentStageMember(windowID: externalWindow.id, bundleID: externalWindow.bundleID,
                                          title: externalWindow.title, frame: externalWindow.frame)
                ])
            ])
        ], activeDisplayID: DisplayID(rawValue: "host")))
        let service = SnapshotService(
            provider: provider, frameWriter: StartupRecoveryWriter(), config: RoadieConfig(),
            intentStore: LayoutIntentStore(path: directory.appendingPathComponent("intents.json").path),
            stageStore: store, events: EventLog(path: directory.appendingPathComponent("events.jsonl").path)
        )
        return (store, service, directory)
    }

    @Test
    func recoveryUsesOnlyOneSystemScanPerPass() {
        let provider = StartupRecoveryProvider()
        provider.liveWindows = [powerWindow(30030, x: 100)]
        let replay = ReplayableSnapshotProvider(base: provider)
        let (store, service, directory) = fixture(replay)
        defer { try? FileManager.default.removeItem(at: directory) }
        var time = Date()
        let maintainer = LayoutMaintainer(service: service, scanReplay: replay, now: { time })
        _ = maintainer.tick(cause: "command:startup")
        let previousReads = provider.windowReadCount
        time.addTimeInterval(LayoutTolerance.displayTopologySettle + 0.1)
        _ = maintainer.tick(cause: "deadline")
        #expect(provider.windowReadCount == previousReads + 1)
        #expect(store.state().stageScope(for: WindowID(rawValue: 30030))?.displayID.rawValue == "host")
    }

    @Test
    func startupRecoversDisconnectedMembersAfterSettlingWithoutDisplayNotification() {
        let provider = StartupRecoveryProvider()
        provider.liveWindows = [powerWindow(30030, x: 100)]
        let (store, service, directory) = fixture(provider)
        defer { try? FileManager.default.removeItem(at: directory) }
        var time = Date()
        let maintainer = LayoutMaintainer(service: service, now: { time })

        _ = maintainer.tick(cause: "command:startup")
        #expect(service.snapshot(followFocus: false).windows.first?.scope == nil)
        #expect(maintainer.nextDeadline(now: time) == time.addingTimeInterval(LayoutTolerance.displayTopologySettle))
        time.addTimeInterval(LayoutTolerance.displayTopologySettle + 0.1)
        _ = maintainer.tick(cause: "deadline")

        let recovered = service.snapshot(followFocus: false).windows.first?.scope
        #expect(recovered?.displayID == DisplayID(rawValue: "host"))
        let stages = store.state().scopes.filter { $0.displayID == DisplayID(rawValue: "host") }.flatMap(\.stages)
        #expect(stages.filter { $0.name == "Code" && !$0.members.isEmpty }.count == 1)
        #expect(stages.first { $0.name == "Code" }?.origin?.displayID == DisplayID(rawValue: "external"))
        _ = maintainer.tick(cause: "safety")
        #expect(store.state().scopes.flatMap(\.stages).flatMap(\.members).filter { $0.windowID.rawValue == 30030 }.count == 1)
    }

    @Test
    func delayedWindowsRecoverWithoutAnotherDisplayNotification() {
        let provider = StartupRecoveryProvider()
        let (store, service, directory) = fixture(provider)
        defer { try? FileManager.default.removeItem(at: directory) }
        var time = Date()
        let maintainer = LayoutMaintainer(service: service, now: { time })
        _ = maintainer.tick(cause: "command:startup")
        #expect(store.state().scopes.first { $0.displayID.rawValue == "external" }?.stages.first?.members.count == 1)
        time.addTimeInterval(5)
        provider.liveWindows = [powerWindow(30030, x: 100)]
        _ = maintainer.tick(cause: "safety")
        #expect(service.snapshot(followFocus: false).windows.first?.scope?.displayID.rawValue == "host")
    }

    @Test
    func deniedAccessibilityPreservesDisconnectedMembers() {
        let provider = StartupRecoveryProvider()
        provider.trusted = false
        provider.liveWindows = [powerWindow(30030, x: 100)]
        let (store, service, directory) = fixture(provider)
        defer { try? FileManager.default.removeItem(at: directory) }
        let maintainer = LayoutMaintainer(service: service)
        #expect(maintainer.tick(cause: "command:startup").accessibilityDenied)
        #expect(store.state().scopes.first { $0.displayID.rawValue == "external" }?.stages.first?.members.count == 1)
        #expect(store.state().scopes.first { $0.displayID.rawValue == "host" }?.stages.contains { $0.parkingState == .parked } == false)
    }

    @Test
    func connectedDisplayIsNotParkedAtStartup() {
        let provider = StartupRecoveryProvider()
        provider.liveWindows = [powerWindow(30030, x: 2000)]
        provider.liveDisplays.append(powerDisplay("external", index: 2, x: 1920))
        let (store, service, directory) = fixture(provider)
        defer { try? FileManager.default.removeItem(at: directory) }
        let maintainer = LayoutMaintainer(service: service)
        _ = maintainer.tick(cause: "command:startup")
        #expect(service.snapshot(followFocus: false).windows.first?.scope?.displayID.rawValue == "external")
        #expect(store.state().scopes.flatMap(\.stages).contains { $0.parkingState == .parked } == false)
    }
}
