import Foundation
import Testing
import RoadieAX
import RoadieCore
@testable import RoadieDaemon

/// Session 022, round 2, lot G : R1-10 (REL-028, code de sortie CLI de `bookmark focus`).
/// R1-09 est couvert dans `Audit022LotGTests`. Aucun test ne touche à `~/.roadies`.
@MainActor
@Suite(.serialized)
struct Audit022R2LotGTests {
    private func makeStore(name: String) -> StageStore {
        let display = DisplayID(rawValue: "display-main")
        let scope = StageScope(displayID: display, desktopID: DesktopID(rawValue: 1), stageID: StageID(rawValue: "1"))
        let store = StageStore(path: tempPath(name))
        store.save(PersistentStageState(
            scopes: [PersistentStageScope(displayID: display, activeStageID: StageID(rawValue: "1"), stages: [
                PersistentStage(id: StageID(rawValue: "1"))
            ])],
            windowBookmarks: [PersistentWindowBookmark(
                name: "work", windowID: WindowID(rawValue: 99), scope: scope, bundleID: "app.gone",
                title: "Gone", frame: Rect(x: 0, y: 0, width: 100, height: 100)
            )]
        ))
        return store
    }

    private func router(store: StageStore) -> CLICommandRouter {
        CLICommandRouter(makeService: { _ in
            let provider = PowerUserProvider(windows: [powerWindow(1, x: 100)])
            return SnapshotService(
                provider: provider,
                frameWriter: PowerUserWriter(provider: provider),
                config: RoadieConfig(),
                intentStore: LayoutIntentStore(path: tempPath("r2g-intents")),
                stageStore: store,
                events: EventLog(path: tempPath("r2g-events")),
                persistStateChanges: false
            )
        })
    }

    /// Fenêtre du signet absente (processus inconnu) : le signet reste, la commande échoue (code 1).
    @Test
    func bookmarkFocusOnAbsentWindowKeepsBookmarkAndExitsNonZero() {
        let store = makeStore(name: "r2g-bookmark-exit")
        defer { try? FileManager.default.removeItem(at: store.fileURL) }

        let response = router(store: store).run(["bookmark", "focus", "work"])

        #expect(response.exitCode == 1)
        #expect(response.stdout.contains("window not visible"))
        #expect(store.state().bookmark(named: "work") != nil)
    }

    @Test
    func absentBookmarkWindowResultIsAFailureAndStaleRemovalIsNot() {
        let absent = WindowCommandResult.failure("bookmark focus work: failed - window not visible (other Space, minimized or unresponsive app), bookmark kept")
        #expect(CLICommandRouter.actionExitCode(outcome: absent.outcome) == 1)
        let removed = WindowCommandResult(message: "bookmark focus work: stale bookmark removed", changed: true)
        #expect(CLICommandRouter.actionExitCode(outcome: removed.outcome) == 0)
    }

    /// R2-06 : « not visible » dans une valeur utilisateur ne fait plus échouer une action sans objet.
    @Test
    func userValueContainingNotVisibleIsNotAFailure() {
        let result = StageCommandResult.noChange("stage create not visible: already exists")
        #expect(CLICommandRouter.actionExitCode(outcome: result.outcome) == 0)
        #expect(CLICommandRouter.actionExitCode(outcome: WindowCommandResult.noChange("window not visible").outcome) == 0)
    }
}
