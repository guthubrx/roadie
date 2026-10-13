import CoreGraphics
import Darwin
import Foundation
import Testing
import RoadieAX
import RoadieCore
@testable import RoadieDaemon

/// Session 022, round 2, lot B : R1-02 (REL-021, commandes de stage sans persistance) et
/// R1-14 (REL-023, seconde transaction de `moveStage` sur le scope exact).
/// Aucun test ne touche à `~/.roadies`.
@Suite(.serialized)
struct Audit022R2LotBTests {
    // MARK: - R1-02 : échec de persistance propagé, aucun effet système

    @Test
    func createReportsFailureWhenStageStateIsUnreadable() throws {
        let fixture = try LotBFixture("r2b-create-corrupt")
        defer { fixture.cleanUp() }
        let garbage = Data("{ pas du json".utf8)
        try garbage.write(to: fixture.store.fileURL)

        let result = fixture.commands.create("3")

        #expect(!result.changed)
        #expect(result.message.contains("failed"))
        #expect(CLICommandRouter.actionExitCode(outcome: result.outcome) == 1)
        #expect(try Data(contentsOf: fixture.store.fileURL) == garbage)
    }

    @Test
    func assignWithoutFollowNeitherHidesNorAnnouncesWhenStateCannotBeWritten() throws {
        let fixture = try LotBFixture("r2b-assign")
        defer { fixture.cleanUp() }
        let before = try fixture.lockStateDirectory()
        guard fixture.directoryIsReadOnly else { return } // administrateur : cas non reproductible

        let result = fixture.commands.assign(
            windowID: fixture.window.id,
            to: "2",
            displayID: fixture.main.id,
            focusAssignedWindow: false
        )

        #expect(!result.changed)
        #expect(result.message.contains("failed"))
        #expect(fixture.writer.frames.isEmpty)
        #expect(fixture.writer.focused.isEmpty)
        #expect(try Data(contentsOf: fixture.store.fileURL) == before)
    }

    @Test
    func switchNeitherMovesNorFocusesWhenStateCannotBeWritten() throws {
        let fixture = try LotBFixture("r2b-switch")
        defer { fixture.cleanUp() }
        let before = try fixture.lockStateDirectory()
        guard fixture.directoryIsReadOnly else { return }

        let result = fixture.commands.switchTo("2", displayID: fixture.main.id)

        #expect(!result.changed)
        #expect(result.message.contains("failed"))
        #expect(fixture.writer.frames.isEmpty)
        #expect(fixture.writer.focused.isEmpty)
        #expect(try Data(contentsOf: fixture.store.fileURL) == before)
    }

    @Test
    func moveToDisplayDoesNotMoveWindowsWhenStateCannotBeWritten() throws {
        let fixture = try LotBFixture("r2b-move")
        defer { fixture.cleanUp() }
        let before = try fixture.lockStateDirectory()
        guard fixture.directoryIsReadOnly else { return }

        let result = fixture.commands.moveActiveStageToDisplay(index: 2, followFocus: true)

        #expect(!result.changed)
        #expect(result.message.contains("failed"))
        #expect(fixture.writer.frames.isEmpty)
        #expect(try Data(contentsOf: fixture.store.fileURL) == before)
    }

    @Test
    func setModeDoesNotLayOutWhenLayoutIntentCannotBeRemoved() throws {
        let fixture = try LotBFixture("r2b-mode-intent")
        defer { fixture.cleanUp() }
        // Intent illisible : sa suppression est refusée, la disposition ne doit pas suivre.
        let garbage = Data("{ pas du json".utf8)
        try garbage.write(to: fixture.intentURL)

        let result = fixture.commands.setMode(.masterStack)

        #expect(!result.changed)
        #expect(result.message.contains("failed"))
        #expect(fixture.writer.frames.isEmpty)
        #expect(try Data(contentsOf: fixture.intentURL) == garbage)
    }

    @Test
    func stageCommandsStillSucceedWhenStateIsWritable() throws {
        let fixture = try LotBFixture("r2b-ok")
        defer { fixture.cleanUp() }

        #expect(fixture.commands.create("3").changed)
        let assign = fixture.commands.assign(
            windowID: fixture.window.id,
            to: "2",
            displayID: fixture.main.id,
            focusAssignedWindow: false
        )
        #expect(assign.changed)
        var state = fixture.store.state()
        let owner = state.scope(displayID: fixture.main.id).stages.first { $0.members.contains { $0.windowID == fixture.window.id } }
        #expect(owner?.id.rawValue == "2")
    }

    // MARK: - R1-14 : seconde transaction de moveStage

    /// Pendant l'écriture AX, le bureau actif de l'écran cible passe au bureau 2, où une autre
    /// fenêtre occupe une stage « 1 ». Seul le scope calculé par la première transaction est recentré.
    @Test
    func noFollowMoveRecentersInExactTargetScopeAfterConcurrentDesktopSwitch() {
        let run = concurrentNoFollowMove("r2b-move-desktop", switchDesktop: true)
        #expect(run.result.changed)
        #expect(run.frame(desktop: 1, window: 1) == Rect(x: 1350, y: 250, width: 300, height: 300))
        #expect(run.frame(desktop: 2, window: 3) == otherDesktopFrame)
    }

    /// Pendant l'écriture AX, une fenêtre non transférée rejoint la stage déplacée : elle garde
    /// sa frame, seul le membre transféré est recentré.
    @Test
    func noFollowMoveRecentersOnlyTransferredMembers() {
        let run = concurrentNoFollowMove("r2b-move-member", switchDesktop: false)
        #expect(run.result.changed)
        #expect(run.frame(desktop: 1, window: 1) == Rect(x: 1350, y: 250, width: 300, height: 300))
        #expect(run.frame(desktop: 1, window: 4) == lateFrame)
    }
}

private let otherDesktopFrame = Rect(x: 1020, y: 20, width: 200, height: 200)
private let lateFrame = Rect(x: 1040, y: 40, width: 200, height: 200)

private struct ConcurrentMoveRun {
    let result: StageCommandResult
    let state: PersistentStageState
    let sideID: DisplayID

    func frame(desktop: Int, window: UInt32) -> Rect? {
        state.scopes
            .first { $0.displayID == sideID && $0.desktopID == DesktopID(rawValue: desktop) }?
            .stages.first { $0.id == StageID(rawValue: "1") }?
            .members.first { $0.windowID == WindowID(rawValue: window) }?
            .frame
    }
}

/// Stage « 1 » (fenêtre 1) déplacée de l'écran principal vers l'écran secondaire sans suivre le
/// focus. Pendant la première écriture AX, la fenêtre 4 rejoint la stage déplacée sur le bureau 1,
/// et, si demandé, l'écran secondaire passe au bureau 2 (stage « 1 » de la fenêtre 3).
private func concurrentNoFollowMove(_ name: String, switchDesktop: Bool) -> ConcurrentMoveRun {
    let main = powerDisplay("display-main", index: 1, x: 0)
    let side = powerDisplay("display-side", index: 2, x: 1000)
    let moved = powerWindow(1, x: 100)
    let resident = powerWindow(2, x: 1100)
    let provider = PowerUserProvider(displays: [main, side], windows: [moved, resident])
    let writer = HookedWriter(base: PowerUserWriter(provider: provider))
    let store = StageStore(path: tempPath(name))
    store.save(PersistentStageState(scopes: [
        PersistentStageScope(displayID: main.id, activeStageID: StageID(rawValue: "1"), stages: [lotBStage("1", moved)]),
        PersistentStageScope(displayID: side.id, activeStageID: StageID(rawValue: "9"), stages: [lotBStage("9", resident), lotBStage("1")]),
        PersistentStageScope(
            displayID: side.id,
            desktopID: DesktopID(rawValue: 2),
            activeStageID: StageID(rawValue: "1"),
            stages: [PersistentStage(id: StageID(rawValue: "1"), members: [lotBMember(3, frame: otherDesktopFrame)])]
        ),
    ], activeDisplayID: main.id))
    writer.onFirstWrite = {
        store.mutate { state in
            if let index = state.scopes.firstIndex(where: { $0.displayID == side.id && $0.desktopID == DesktopID(rawValue: 1) }),
               let stage = state.scopes[index].stages.firstIndex(where: { $0.id == StageID(rawValue: "1") }) {
                state.scopes[index].stages[stage].members.append(lotBMember(4, frame: lateFrame))
            }
            if switchDesktop {
                state.switchDesktop(displayID: side.id, to: DesktopID(rawValue: 2))
            }
        }
    }
    let service = SnapshotService(provider: provider, frameWriter: writer, config: RoadieConfig(), stageStore: store)

    let result = StageCommandService(service: service, store: store, config: RoadieConfig())
        .moveActiveStageToDisplay(index: 2, followFocus: false)

    #expect(writer.wrote)
    return ConcurrentMoveRun(result: result, state: store.state(), sideID: side.id)
}

// MARK: - Outils

/// Écran principal (stages 1 et 2, fenêtre dans la 1) et écran secondaire, état dans un dossier
/// dédié que `lockStateDirectory` passe en lecture seule : le verrou existe déjà, seule l'écriture
/// atomique échoue (le corps de la transaction a été exécuté).
private struct LotBFixture {
    let directory: URL
    let main = powerDisplay("display-main", index: 1, x: 0)
    let side = powerDisplay("display-side", index: 2, x: 1000)
    let window = powerWindow(1, x: 100)
    let provider: PowerUserProvider
    let writer: PowerUserWriter
    let store: StageStore
    let intentURL: URL
    let commands: StageCommandService

    init(_ name: String) throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("\(name)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        provider = PowerUserProvider(displays: [main, side], windows: [window])
        writer = PowerUserWriter(provider: provider)
        store = StageStore(path: directory.appendingPathComponent("stages.json").path)
        store.save(PersistentStageState(scopes: [
            PersistentStageScope(displayID: main.id, activeStageID: StageID(rawValue: "1"), stages: [lotBStage("1", window), lotBStage("2")]),
            PersistentStageScope(displayID: side.id, activeStageID: StageID(rawValue: "1"), stages: [lotBStage("1")]),
        ], activeDisplayID: main.id))
        intentURL = directory.appendingPathComponent("intents.json")
        let service = SnapshotService(
            provider: provider,
            frameWriter: writer,
            config: RoadieConfig(),
            intentStore: LayoutIntentStore(path: intentURL.path),
            stageStore: store
        )
        commands = StageCommandService(service: service, store: store, config: RoadieConfig())
    }

    /// Octets de l'état avant la commande, puis dossier en lecture seule.
    func lockStateDirectory() throws -> Data {
        let data = try Data(contentsOf: store.fileURL)
        chmod(directory.path, 0o500)
        return data
    }

    var directoryIsReadOnly: Bool { access(directory.path, W_OK) != 0 }

    func cleanUp() {
        chmod(directory.path, 0o700)
        try? FileManager.default.removeItem(at: directory)
    }
}

/// Écrivain qui exécute `onFirstWrite` pendant la première écriture AX (changement concurrent).
private final class HookedWriter: WindowFrameWriting, @unchecked Sendable {
    let base: PowerUserWriter
    var onFirstWrite: (() -> Void)?
    private(set) var wrote = false

    init(base: PowerUserWriter) {
        self.base = base
    }

    func setFrame(_ frame: CGRect, of window: WindowSnapshot) -> CGRect? {
        if !wrote {
            wrote = true
            onFirstWrite?()
        }
        return base.setFrame(frame, of: window)
    }

    func focus(_ window: WindowSnapshot) -> Bool { base.focus(window) }
}

private func lotBStage(_ rawID: String, _ windows: WindowSnapshot...) -> PersistentStage {
    PersistentStage(
        id: StageID(rawValue: rawID),
        members: windows.map {
            PersistentStageMember(windowID: $0.id, bundleID: $0.bundleID, title: $0.title, frame: $0.frame)
        }
    )
}

private func lotBMember(_ id: UInt32, frame: Rect) -> PersistentStageMember {
    PersistentStageMember(windowID: WindowID(rawValue: id), bundleID: "app.\(id)", title: "Window \(id)", frame: frame)
}
