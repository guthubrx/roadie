import CoreGraphics
import Foundation
import Testing
import RoadieAX
import RoadieCore
@testable import RoadieDaemon
import RoadieStages
import RoadieTiler

private struct R2LotAProvider: SystemSnapshotProviding {
    var displaySnapshots: [DisplaySnapshot]
    var windowSnapshots: [WindowSnapshot] = []

    func permissions(prompt: Bool) -> PermissionSnapshot { PermissionSnapshot(accessibilityTrusted: true) }
    func displays() -> [DisplaySnapshot] { displaySnapshots }
    func windows() -> [WindowSnapshot] { windowSnapshots }
    func focusedWindowID() -> WindowID? { nil }
    func mouseLocation() -> CGPoint? { nil }
}

/// Session 022, round 2, lot A : constats de contre-revue R1-01 (réconciliation des arbres) et
/// R1-12 (fusion des métadonnées persistées, REL-005).
@Suite
struct Audit022R2LotATests {
    // MARK: R1-12

    /// Stage 1 vide en mode `float`, stage 2 active : l'état runtime garde le mode de la stage 1.
    @Test
    func emptyInactiveStageKeepsPersistedMode() {
        let display = powerDisplay("display-a")
        let desktop = DesktopID(rawValue: 1)
        let stageStore = StageStore(path: tempPath("r2-lot-a-stage-mode"))
        stageStore.mutate { state in
            state.update(PersistentStageScope(
                displayID: display.id,
                desktopID: desktop,
                activeStageID: StageID(rawValue: "2"),
                stages: [
                    PersistentStage(id: StageID(rawValue: "1"), name: "Libre", mode: .float),
                    PersistentStage(id: StageID(rawValue: "2"), mode: .bsp),
                ]
            ))
        }
        let service = SnapshotService(provider: R2LotAProvider(displaySnapshots: [display]), stageStore: stageStore)

        let state = service.snapshot().state
        let stageOne = StageScope(displayID: display.id, desktopID: desktop, stageID: StageID(rawValue: "1"))

        #expect(state.stage(scope: stageOne)?.mode == .float)
        #expect(state.stage(scope: stageOne)?.name == "Libre")
        #expect(state.activeScope(on: display.id)?.stageID == StageID(rawValue: "2"))
        try? FileManager.default.removeItem(at: stageStore.fileURL)
    }

    /// Desktop 2 inactif, occupé en stage 1, avec la stage 3 active persistée : le desktop runtime
    /// reprend la stage 3 active et son mode, la fenêtre reste en stage 1 et le desktop 1 reste courant.
    @Test
    func inactiveDesktopKeepsPersistedActiveStage() {
        let display = powerDisplay("display-a")
        let window = powerWindow(7, x: 100)
        let desktopTwo = DesktopID(rawValue: 2)
        let stageStore = StageStore(path: tempPath("r2-lot-a-inactive-desktop"))
        stageStore.mutate { state in
            state.update(PersistentStageScope(displayID: display.id, desktopID: DesktopID(rawValue: 1)))
            state.update(PersistentStageScope(
                displayID: display.id,
                desktopID: desktopTwo,
                activeStageID: StageID(rawValue: "3"),
                stages: [
                    PersistentStage(id: StageID(rawValue: "1"), members: [
                        PersistentStageMember(windowID: window.id, bundleID: window.bundleID, title: window.title, frame: window.frame),
                    ]),
                    PersistentStage(id: StageID(rawValue: "3"), name: "Mail", mode: .float),
                ]
            ))
        }
        let service = SnapshotService(
            provider: R2LotAProvider(displaySnapshots: [display], windowSnapshots: [window]),
            stageStore: stageStore
        )

        let state = service.snapshot().state
        let desktop = state.desktop(displayID: display.id, desktopID: desktopTwo)
        let stageOne = StageScope(displayID: display.id, desktopID: desktopTwo, stageID: StageID(rawValue: "1"))
        let stageThree = StageScope(displayID: display.id, desktopID: desktopTwo, stageID: StageID(rawValue: "3"))

        #expect(desktop?.activeStageID == StageID(rawValue: "3"))
        #expect(state.stage(scope: stageThree)?.mode == .float)
        #expect(state.stage(scope: stageThree)?.name == "Mail")
        #expect(state.stage(scope: stageOne)?.windowIDs == [window.id])
        #expect(state.display(display.id)?.currentDesktopID == DesktopID(rawValue: 1))
        try? FileManager.default.removeItem(at: stageStore.fileURL)
    }

    // MARK: R1-01

    /// La réconciliation par ensemble de feuilles donne le même arbre que l'ancien parcours
    /// (`windowIDs` relu, `removing` par feuille, `contains` par membre) sur des cas aléatoires.
    @Test
    func reconciledTreeMatchesReference() {
        var generator = R2LotARandom(seed: 0x022_A2_01)
        let container = CGRect(x: 0, y: 0, width: 1200, height: 800)
        for round in 0..<400 {
            let count = Int(generator.next() % 12)
            var tree = BSPTree.empty
            for id in 0..<count {
                let anchor = id == 0 ? nil : WindowID(rawValue: UInt32(generator.next() % UInt64(id)) + 1)
                tree = tree.inserting(
                    WindowID(rawValue: UInt32(id) + 1),
                    at: anchor,
                    side: generator.next().isMultiple(of: 2) ? .right : .left,
                    in: container
                )
            }
            // Membres : une partie des feuilles plus des fenêtres nouvelles, dans un ordre mêlé.
            let candidates = (1...UInt32(count + 6)).map(WindowID.init(rawValue:)).shuffled(using: &generator)
            let members = candidates.filter { _ in generator.next() % 4 != 0 }
            let live = Set(candidates.filter { _ in generator.next() % 3 != 0 })
            let kept = Set(members.filter { _ in generator.next() % 5 != 0 })
            let stage = PersistentStage(
                id: StageID(rawValue: "1"),
                mode: .bsp,
                focusedWindowID: members.randomElement(using: &generator),
                previousFocusedWindowID: members.randomElement(using: &generator),
                members: members.map { PersistentStageMember(windowID: $0, bundleID: "b", title: "t", frame: Rect(x: 0, y: 0, width: 1, height: 1)) }
            )
            let focus = candidates.randomElement(using: &generator)
            let side: BSPInsertionSide = round.isMultiple(of: 2) ? .right : .left

            let expected = referenceReconciledTree(tree, stage: stage, kept: kept, live: live, globalFocus: focus, side: side, container: container)
            let actual = SnapshotService.reconciledTree(
                tree, stage: stage, kept: kept, live: live, globalFocus: focus,
                side: side, container: container, innerGap: 8
            )
            #expect(actual == expected, "round \(round)")
        }
    }

    /// Arbre en chaîne déjà complet : aucune insertion, arbre inchangé.
    @Test
    func reconciledChainTreeWithoutChangeIsUntouched() {
        let container = CGRect(x: 0, y: 0, width: 1200, height: 800)
        let ids = (1...50).map { WindowID(rawValue: UInt32($0)) }
        let tree = chainTree(ids)
        let stage = PersistentStage(
            id: StageID(rawValue: "1"),
            members: ids.map { PersistentStageMember(windowID: $0, bundleID: "b", title: "t", frame: Rect(x: 0, y: 0, width: 1, height: 1)) }
        )
        let result = SnapshotService.reconciledTree(
            tree, stage: stage, kept: Set(ids), live: Set(ids), globalFocus: ids.last,
            side: .right, container: container, innerGap: 8
        )
        #expect(result == tree)
    }
}

/// Ancien algorithme de `reconcileTrees`, conservé comme référence de comparaison.
private func referenceReconciledTree(
    _ initial: BSPTree,
    stage: PersistentStage,
    kept: Set<WindowID>,
    live: Set<WindowID>,
    globalFocus: WindowID?,
    side: BSPInsertionSide,
    container: CGRect
) -> BSPTree {
    var tree = initial
    for id in tree.windowIDs where !kept.contains(id) {
        tree = tree.removing(id)
    }
    let absent = Set(tree.windowIDs).subtracting(live)
    let anchors = Set(tree.windowIDs).intersection(live)
    var anchor = [globalFocus, stage.focusedWindowID, stage.previousFocusedWindowID]
        .lazy
        .compactMap { $0 }
        .first { anchors.contains($0) }
    for member in stage.members where kept.contains(member.windowID)
        && live.contains(member.windowID)
        && !tree.contains(member.windowID) {
        tree = tree.inserting(member.windowID, at: anchor, side: side, in: container, innerGap: 8, excluding: absent)
        anchor = member.windowID
    }
    return tree
}

/// Arbre en chaîne : chaque split a une feuille à gauche et le reste de la chaîne à droite.
private func chainTree(_ ids: [WindowID]) -> BSPTree {
    var tree = BSPTree.empty
    for id in ids.reversed() {
        tree = tree.isEmpty ? .leaf(id) : .split(orientation: .vertical, ratio: 0.5, first: .leaf(id), second: tree)
    }
    return tree
}

private struct R2LotARandom: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return state
    }
}
