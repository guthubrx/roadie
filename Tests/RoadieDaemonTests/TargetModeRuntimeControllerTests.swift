import CoreGraphics
import Foundation
import Testing
import RoadieAX
import RoadieCore
import RoadieStages
@testable import RoadieDaemon

@Suite
struct TargetModeRuntimeControllerTests {
    @Test
    func commandRoundTripsThroughDistributedNotificationPayload() throws {
        let command = TargetModeRuntimeCommand(name: "targets.interactive", arguments: [
            "source": "all",
            "includeAppTargets": "true",
            "duration": "10"
        ])

        let parsed = try #require(TargetModeRuntimeCommand(userInfo: command.userInfo))

        #expect(parsed.name == "targets.interactive")
        #expect(parsed.string("source") == "all")
        #expect(parsed.bool("includeAppTargets"))
        #expect(parsed.double("duration") == 10)
    }

    @Test
    func commandRejectsMissingCommandName() {
        #expect(TargetModeRuntimeCommand(userInfo: ["source": "all"]) == nil)
    }

    @Test
    func gridFocusPickerPrefersTopmostWindowContainingCellCenter() {
        let large = ScopedWindowSnapshot(window: WindowSnapshot(
            id: WindowID(rawValue: 10),
            pid: 100,
            appName: "Large",
            bundleID: "large",
            title: "Large",
            frame: Rect(x: 100, y: 100, width: 500, height: 500),
            isOnScreen: true,
            isTileCandidate: true
        ), scope: nil)
        let small = ScopedWindowSnapshot(window: WindowSnapshot(
            id: WindowID(rawValue: 20),
            pid: 200,
            appName: "Small",
            bundleID: "small",
            title: "Small",
            frame: Rect(x: 140, y: 140, width: 80, height: 80),
            isOnScreen: true,
            isTileCandidate: true
        ), scope: nil)
        let snapshot = DaemonSnapshot(
            permissions: PermissionSnapshot(accessibilityTrusted: true),
            displays: [],
            windows: [large, small],
            state: RoadieState()
        )

        let target = GridFocusPicker.targetWindow(intersectingAXFrame: CGRect(x: 120, y: 120, width: 140, height: 140), in: snapshot)

        #expect(target?.window.id == large.window.id)
    }

    @Test
    func gridFocusPickerFallsBackToTopmostIntersectingWindowWhenCenterIsEmpty() {
        let top = ScopedWindowSnapshot(window: WindowSnapshot(
            id: WindowID(rawValue: 30),
            pid: 300,
            appName: "Top",
            bundleID: "top",
            title: "Top",
            frame: Rect(x: 100, y: 100, width: 100, height: 100),
            isOnScreen: true,
            isTileCandidate: true
        ), scope: nil)
        let bottom = ScopedWindowSnapshot(window: WindowSnapshot(
            id: WindowID(rawValue: 40),
            pid: 400,
            appName: "Bottom",
            bundleID: "bottom",
            title: "Bottom",
            frame: Rect(x: 110, y: 110, width: 500, height: 500),
            isOnScreen: true,
            isTileCandidate: true
        ), scope: nil)
        let snapshot = DaemonSnapshot(
            permissions: PermissionSnapshot(accessibilityTrusted: true),
            displays: [],
            windows: [top, bottom],
            state: RoadieState()
        )

        let target = GridFocusPicker.targetWindow(intersectingAXFrame: CGRect(x: 90, y: 90, width: 130, height: 60), in: snapshot)

        #expect(target?.window.id == top.window.id)
    }

    @Test
    func labelStylesFollowTheConfiguredFontSize() {
        let letters = TargetOverlayStyle.labels(TargetModeConfig(labelFontSize: 20))
        let grid = TargetOverlayStyle.grid(TargetGridConfig(labelFontSize: 20))

        #expect(abs(letters.scale - 20.0 / 13.0) < 0.001)
        #expect(abs(grid.scale - 20.0 / 13.0) < 0.001)
        #expect(TargetOverlayStyle.labels(TargetModeConfig()).scale == 1)
    }

    /// SPEC-023 R2 : l'action différée de la boîte part après le nettoyage de la session et la remise à
    /// zéro du contrôleur, un tour de boucle plus tard ; la commande `grid` arrive alors au contrôleur.
    /// La session de recherche exige un tap clavier et des écrans : la séquence est testée par la
    /// fonction qu'elle appelle, avec le vrai contrôleur.
    @Test @MainActor
    func deferredBoxActionRunsAfterTheSessionEndsAndReachesTheController() async throws {
        let eventPath = tempPath("command-box-events")
        defer { try? FileManager.default.removeItem(atPath: eventPath) }
        let provider = PowerUserProvider(windows: [])
        let controller = TargetModeRuntimeController(
            service: SnapshotService(provider: provider, frameWriter: PowerUserWriter(provider: provider), config: RoadieConfig()),
            events: EventLog(path: eventPath)
        )
        let steps = StepLog()

        CommandBoxFollowUp.finish(
            cleanup: { steps.entries.append("cleanup") },
            notify: { steps.entries.append("finish") },
            then: {
                steps.entries.append("action")
                controller.handle(TargetModeRuntimeCommand(name: "grid.interactive", arguments: ["scope": "display"]))
            }
        )
        #expect(steps.entries == ["cleanup", "finish"])

        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
        #expect(steps.entries == ["cleanup", "finish", "action"])
        // Grille désactivée par défaut : la commande est traitée (et refusée), pas ignorée.
        let events = try String(contentsOfFile: eventPath, encoding: .utf8)
        #expect(events.contains("grid.interactive"))
        #expect(events.contains("target_grid_disabled"))
    }
}

@MainActor
private final class StepLog {
    var entries: [String] = []
}
