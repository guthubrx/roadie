import CoreGraphics
import Foundation
@testable import RoadieAX
import RoadieCore
import Testing
@testable import RoadieDaemon

/// Spec 159 — Couverture de `StageFocusRecallService` et sûreté concurrente des types migrés en `Sendable` strict.
@Suite(.serialized)
struct Spec159MaintenabiliteTests {
    private final class SpyFrameWriter: WindowFrameWriting, @unchecked Sendable {
        private let lock = NSLock()
        var focusedWindowIDs: [WindowID] = []
        var focusedAppWindowCalls: [(bundleID: String, windowID: WindowID)] = []
        var activatedBundles: [String] = []
        var focusResults: [WindowID: Bool] = [:]
        var focusAppWindowResults: [WindowID: Bool] = [:]
        var activateResult = true

        func setFrame(_ frame: CGRect, of window: WindowSnapshot) -> CGRect? { frame }

        func focus(_ window: WindowSnapshot) -> Bool {
            lock.withLock {
                focusedWindowIDs.append(window.id)
                return focusResults[window.id] ?? true
            }
        }

        func focusApplicationWindow(bundleID: String, windowID: WindowID, title: String, frame: Rect) -> Bool {
            lock.withLock {
                focusedAppWindowCalls.append((bundleID, windowID))
                return focusAppWindowResults[windowID] ?? false
            }
        }

        func activateApplication(bundleID: String) -> Bool {
            lock.withLock {
                activatedBundles.append(bundleID)
                return activateResult
            }
        }
    }

    private struct StaticProvider: SystemSnapshotProviding {
        var displaysList: [DisplaySnapshot] = [
            DisplaySnapshot(
                id: DisplayID(rawValue: "spec159-display"),
                index: 1,
                name: "Display",
                frame: Rect(x: 0, y: 0, width: 1600, height: 900),
                visibleFrame: Rect(x: 0, y: 30, width: 1600, height: 870),
                isMain: true
            )
        ]
        var windowsList: [WindowSnapshot] = []

        func permissions(prompt: Bool) -> PermissionSnapshot {
            PermissionSnapshot(accessibilityTrusted: true, screenRecordingGranted: true)
        }
        func displays() -> [DisplaySnapshot] { displaysList }
        func windows() -> [WindowSnapshot] { windowsList }
        func focusedWindowID() -> WindowID? { windowsList.first?.id }
    }

    private func makeService(writer: SpyFrameWriter, windows: [WindowSnapshot] = []) -> SnapshotService {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("spec159-\(UUID())")
        let stagePath = dir.appendingPathComponent("stages.json").path
        let intentPath = dir.appendingPathComponent("intents.json").path
        return SnapshotService(
            provider: StaticProvider(windowsList: windows),
            frameWriter: writer,
            intentStore: LayoutIntentStore(path: intentPath),
            stageStore: StageStore(path: stagePath)
        )
    }

    private func member(
        _ id: UInt32,
        bundleID: String = "com.example.app",
        lastSeenAt: Date? = nil,
        presentationState: WindowPresentationState = .normal,
        closed: Bool = false
    ) -> PersistentStageMember {
        PersistentStageMember(
            windowID: WindowID(rawValue: id),
            bundleID: bundleID,
            title: "Win \(id)",
            frame: Rect(x: 10, y: 40, width: 600, height: 400),
            presentationState: presentationState,
            lastSeenAt: lastSeenAt,
            confirmedClosedAt: closed ? Date(timeIntervalSince1970: 1_500) : nil
        )
    }

    private func window(_ id: UInt32, bundleID: String = "com.example.app") -> WindowSnapshot {
        WindowSnapshot(
            id: WindowID(rawValue: id),
            pid: 500,
            appName: "App",
            bundleID: bundleID,
            title: "Win \(id)",
            frame: Rect(x: 10, y: 40, width: 600, height: 400),
            isOnScreen: true,
            isTileCandidate: true
        )
    }

    @Test func missingFocusCandidatesPrioritizePreferredThenMostRecentAndFilterClosedAndMaximized() {
        let older = Date(timeIntervalSince1970: 1_000)
        let newer = Date(timeIntervalSince1970: 2_000)
        let stage = PersistentStage(
            id: StageID(rawValue: "s1"),
            focusedWindowID: WindowID(rawValue: 1),
            members: [
                member(1, lastSeenAt: older),
                member(2, lastSeenAt: newer),
                member(3, lastSeenAt: newer, presentationState: .maximized),
                member(4, lastSeenAt: newer, closed: true),
                member(5, bundleID: "", lastSeenAt: newer),
            ]
        )

        let defaultOrder = StageFocusRecallService.missingFocusCandidates(in: stage)
        #expect(defaultOrder.map(\.windowID) == [WindowID(rawValue: 1), WindowID(rawValue: 2)])

        let withMaximized = StageFocusRecallService.missingFocusCandidates(
            in: stage,
            preferredWindowID: WindowID(rawValue: 3),
            includeMaximized: true
        )
        #expect(withMaximized.map(\.windowID) == [WindowID(rawValue: 3), WindowID(rawValue: 2), WindowID(rawValue: 1)])
    }

    @Test func focusOrRecallPreferredCoversLiveRecallAndBundleFallback() {
        let writer = SpyFrameWriter()
        let service = makeService(writer: writer)
        let recall = StageFocusRecallService(service: service)

        let w1 = window(10, bundleID: "com.example.live")
        let stage = PersistentStage(
            id: StageID(rawValue: "s1"),
            members: [
                member(10, bundleID: "com.example.live"),
                member(20, bundleID: "com.example.missing"),
                member(30, bundleID: "com.example.other"),
            ]
        )

        // 1) Fenêtre vivante : focus direct sans rappel ni activation bundle.
        #expect(recall.focusOrRecallPreferred(
            windowID: w1.id,
            bundleID: w1.bundleID,
            in: stage,
            windowsByID: [w1.id: w1]
        ))
        #expect(writer.focusedWindowIDs == [w1.id])
        #expect(writer.focusedAppWindowCalls.isEmpty)

        // 2) Fenêtre absente présente dans la stage : sollicite uniquement cette fenêtre (`onlyPreferred: true`), jamais w30.
        writer.focusAppWindowResults[WindowID(rawValue: 20)] = true
        #expect(recall.focusOrRecallPreferred(
            windowID: WindowID(rawValue: 20),
            bundleID: "com.example.missing",
            in: stage,
            windowsByID: [:]
        ))
        #expect(writer.focusedAppWindowCalls.map(\.windowID) == [WindowID(rawValue: 20)])
        #expect(writer.activatedBundles.isEmpty)

        // 3) Fenêtre absente même de la stage : repli sur `activateApplication(bundleID:)`.
        #expect(recall.focusOrRecallPreferred(
            windowID: WindowID(rawValue: 99),
            bundleID: "com.example.fallback",
            in: stage,
            windowsByID: [:]
        ))
        #expect(writer.activatedBundles == ["com.example.fallback"])
    }

    @Test func focusOrRecallTargetSkipsRecallWhenLiveWindowFocuses() {
        let writer = SpyFrameWriter()
        let service = makeService(writer: writer)
        let recall = StageFocusRecallService(service: service)
        let w1 = window(11, bundleID: "com.example.one")
        let stage = PersistentStage(id: StageID(rawValue: "s1"), members: [member(11, bundleID: "com.example.one")])

        let ok = recall.focusOrRecallTarget(windowID: w1.id, in: stage, windowsByID: [w1.id: w1])
        #expect(ok.focusedWindow)
        #expect(ok.recall.attempted.isEmpty)

        // Si le focus direct échoue, le rappel est tenté.
        writer.focusResults[w1.id] = false
        writer.focusAppWindowResults[w1.id] = true
        let fallback = recall.focusOrRecallTarget(windowID: w1.id, in: stage, windowsByID: [w1.id: w1])
        #expect(!fallback.focusedWindow)
        #expect(fallback.recall.focusedWindowID == w1.id)
    }

    @Test func strictSendablePrimitivesAreSafeUnderConcurrentAccess() throws {
        let generation = PlacementGeneration()
        let permit = InteractiveWritePermit(generations: generation)
        let hold = LayoutPreviewHold()
        let now = Date(timeIntervalSince1970: 5_000)
        let unresponsive = AXUnresponsiveApps(now: { now })
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("spec159-railcache-\(UUID())")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let railConfigPath = tempDir.appendingPathComponent("roadies.toml").path
        try "[fx.rail]\nwidth = 160\n".write(toFile: railConfigPath, atomically: true, encoding: .utf8)

        DispatchQueue.concurrentPerform(iterations: 64) { index in
            _ = permit.advance()
            _ = permit.isCurrent
            hold.hold(for: 1.0, now: now)
            _ = hold.isHeld(at: now)
            let pid = pid_t(1000 + (index % 8))
            unresponsive.markUnresponsive(pid)
            _ = unresponsive.isQuarantined(pid)
            if index % 2 == 0 { unresponsive.markResponsive(pid) }
            let loaded = RailSettings.load(path: railConfigPath)
            #expect(loaded.width == 160)
        }

        #expect(generation.current == 64)
        #expect(hold.isHeld(at: now))
        hold.release()
        #expect(!hold.isHeld(at: now))
        unresponsive.markUnresponsive(4242)
        #expect(unresponsive.isQuarantined(4242))
        unresponsive.markResponsive(4242)
        #expect(!unresponsive.isQuarantined(4242))
        permit.invalidate()
        #expect(!permit.isCurrent)
    }

    @Test @MainActor func launcherTerminalValidatesBundlesAndResolvesFallbackTerminal() throws {
        // Terminal.app système (et tout réglage inconnu qui retombe sur Terminal) résolus via LaunchServices.
        #expect(LauncherTerminal.isInstalled("terminal"))
        #expect(LauncherTerminal.isInstalled("unknown_fallback"))
        #expect(LauncherTerminal.bundleIdentifiers(forAppName: "Terminal") == ["com.apple.Terminal"])

        // Un dossier vide ou un simple fichier nommé `.app` n'est pas considéré comme un paquet valide.
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("spec159-bundle-\(UUID())")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fakeApp = tempDir.appendingPathComponent("Fake.app")
        try FileManager.default.createDirectory(at: fakeApp, withIntermediateDirectories: true)
        #expect(!LauncherTerminal.isValidAppBundle(at: fakeApp.path))

        let validApp = tempDir.appendingPathComponent("Valid.app")
        let contents = validApp.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0"><dict>
            <key>CFBundleIdentifier</key><string>com.example.valid-terminal</string>
        </dict></plist>
        """
        try plist.write(to: contents.appendingPathComponent("Info.plist"), atomically: true, encoding: .utf8)
        #expect(LauncherTerminal.isValidAppBundle(at: validApp.path))
    }
}
