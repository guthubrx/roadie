import AppKit
import Foundation
import Testing
import RoadieAX
import RoadieCore
import RoadieStages
@testable import RoadieDaemon

/// Session 022, round 2, lot H : R1-15 (TEST-004, indicateur de groupe de la bordure, FR-012 de la SPEC-002).
/// `BorderController.refresh()` est exécuté pour de vrai ; seul le panneau AppKit est remplacé par un faux
/// qui enregistre ce qu'on lui demande d'afficher.
@MainActor
final class FakeBorderPanel: BorderRendering {
    private(set) var rendered: [BorderRenderModel] = []
    private(set) var hideCount = 0

    func render(_ model: BorderRenderModel) { rendered.append(model) }
    func hide() { hideCount += 1 }
}

@MainActor
@Suite(.serialized)
struct Audit022R2LotHTests {
    private struct Rig {
        let provider: PowerUserProvider
        let service: SnapshotService
        let groups: WindowGroupCommandService
        let panel: FakeBorderPanel
        let controller: BorderController
    }

    private func makeRig(bordersEnabled: Bool = true) -> Rig {
        let provider = PowerUserProvider(windows: [
            powerWindow(1, x: 100), powerWindow(2, x: 500), powerWindow(3, x: 820, width: 150)
        ])
        let store = StageStore(path: tempPath("border-group-label"))
        // Ce test porte sur le rendu, pas sur le temps passé dans la file MainActor.
        let service = SnapshotService(provider: provider, frameWriter: PowerUserWriter(provider: provider),
                                      stageStore: store, clock: { Date(timeIntervalSince1970: 1_000) })
        _ = service.snapshot()
        var config = RoadieConfig()
        config.fx.borders.enabled = bordersEnabled
        let panel = FakeBorderPanel()
        let controller = BorderController(snapshotService: service, configLoader: { config }, panel: panel)
        return Rig(
            provider: provider,
            service: service,
            groups: WindowGroupCommandService(service: service, store: store),
            panel: panel,
            controller: controller
        )
    }

    private func focus(_ id: UInt32, in rig: Rig) {
        rig.provider.focusedID = WindowID(rawValue: id)
        rig.service.invalidateSharedSnapshot()
    }

    @Test
    func refreshSendsGroupLabelOfActiveMemberToThePanel() async {
        let rig = makeRig()
        _ = rig.groups.create(id: "docs", windowIDs: [WindowID(rawValue: 1), WindowID(rawValue: 2), WindowID(rawValue: 3)])
        _ = rig.groups.focus(windowID: WindowID(rawValue: 2), in: "docs")
        focus(2, in: rig)

        await rig.controller.refresh()

        let model = rig.panel.rendered.last
        #expect(rig.panel.rendered.count == 1)
        #expect(model?.groupLabel == "docs 2/3")
        // La bordure garde ses réglages habituels : l'indicateur s'y ajoute sans les remplacer.
        #expect(model?.thickness == 2)
        #expect(model?.cornerRadius == 10)
        #expect(model?.color == NSColor(hex: "#7AA2F7"))
    }

    @Test
    func refreshSendsNoLabelOutsideGroupAndDropsItAfterDissolution() async {
        let rig = makeRig()
        _ = rig.groups.create(id: "pair", windowIDs: [WindowID(rawValue: 1), WindowID(rawValue: 2)])

        // Fenêtre 3 : hors groupe.
        focus(3, in: rig)
        await rig.controller.refresh()
        let outside = rig.panel.rendered.last
        #expect(outside != nil)
        #expect(outside?.groupLabel == nil)
        #expect(outside?.frame == BorderController.axToNS(CGRect(x: 820, y: 100, width: 150, height: 300)))

        // Fenêtre 1 : membre du groupe, puis groupe dissous.
        focus(1, in: rig)
        await rig.controller.refresh()
        #expect(rig.panel.rendered.count == 2)
        #expect(rig.panel.rendered.last?.groupLabel == "pair 1/2")

        _ = rig.groups.dissolve(id: "pair")
        rig.service.invalidateSharedSnapshot()
        await rig.controller.refresh()
        #expect(rig.panel.rendered.count == 3)
        #expect(rig.panel.rendered.last?.groupLabel == nil)
    }

    @Test
    func refreshHidesPanelWhenBordersAreDisabled() async {
        let rig = makeRig(bordersEnabled: false)
        await rig.controller.refresh()
        #expect(rig.panel.rendered.isEmpty)
        #expect(rig.panel.hideCount == 1)
    }

    @Test
    func groupLabelFollowsActiveMemberPositionAndGroupSize() throws {
        var group = WindowGroup(id: "docs", windowIDs: (1...3).map { WindowID(rawValue: $0) })
        let ids = group.windowIDs
        func label(_ window: WindowID, _ groups: [WindowGroup]) throws -> String? {
            let display = DisplayID(rawValue: "display-main")
            var state = RoadieState()
            state.ensureDisplay(display)
            try state.setGroups(groups, for: StageScope(displayID: display, desktopID: DesktopID(rawValue: 1), stageID: StageID(rawValue: "1")))
            let snapshot = DaemonSnapshot(
                permissions: PermissionSnapshot(accessibilityTrusted: true),
                displays: [powerDisplay()],
                windows: [],
                state: state
            )
            return BorderController.groupLabel(for: window, snapshot: snapshot)
        }

        #expect(try label(ids[2], [group]) == "docs 1/3")
        _ = group.focus(ids[2])
        #expect(try label(ids[0], [group]) == "docs 3/3")
        group.remove(ids[1])
        #expect(try label(ids[0], [group]) == "docs 2/2")
        #expect(try label(WindowID(rawValue: 9), [group]) == nil)
    }
}
