import Testing
import RoadieAX
import RoadieCore
import RoadieDaemon
import RoadieStages

/// Défaut connu (audit 022, TEST-004, FR-012 de la SPEC-002) : `BorderController.groupIndicator` produit
/// bien le libellé d'un groupe, mais aucun code de production ne l'appelle. `BorderController.refresh`
/// transmet seulement cadre, couleur, épaisseur et rayon au panneau : aucun indicateur de groupe n'est
/// donc affiché à l'écran. Les tests `groupIndicator*` figent le contrat de la fonction isolée ; ils ne
/// prouvent pas un rendu. Le seul traitement de groupe réellement exécuté côté interface est l'élagage
/// des membres absents dans `RailController.railDisplayStage`, couvert plus bas.
/// Correction attendue hors de ce lot : brancher le libellé sur `BorderPanel.render` (puis tester le
/// modèle transmis au panneau), ou corriger le statut de T068 dans la SPEC-002.
@Suite
struct WindowGroupIndicatorTests {
    private let displayID = DisplayID(rawValue: "display-main")
    private let desktopID = DesktopID(rawValue: 1)
    private let stageID = StageID(rawValue: "1")

    private func snapshot(groups: [WindowGroup]) throws -> DaemonSnapshot {
        var state = RoadieState()
        // Crée l'écran avec son bureau 1 et sa stage 1 par défaut.
        state.ensureDisplay(displayID)
        try state.setGroups(
            groups,
            for: StageScope(displayID: displayID, desktopID: desktopID, stageID: stageID)
        )
        return DaemonSnapshot(
            permissions: PermissionSnapshot(accessibilityTrusted: true),
            displays: [powerDisplay()],
            windows: [],
            state: state
        )
    }

    @MainActor
    @Test
    func groupIndicatorReportsGroupActiveMemberAndSize() throws {
        let group = WindowGroup(
            id: "docs",
            windowIDs: [WindowID(rawValue: 1), WindowID(rawValue: 2)],
            activeWindowID: WindowID(rawValue: 2)
        )
        let controller = BorderController()
        let current = try snapshot(groups: [group])

        // Les deux membres voient le même libellé : id du groupe, membre actif, nombre de membres.
        #expect(controller.groupIndicator(for: WindowID(rawValue: 1), snapshot: current) == "docs:2/2")
        #expect(controller.groupIndicator(for: WindowID(rawValue: 2), snapshot: current) == "docs:2/2")
    }

    @MainActor
    @Test
    func groupIndicatorFollowsActiveMemberAndSizeChanges() throws {
        var group = WindowGroup(
            id: "docs",
            windowIDs: [WindowID(rawValue: 1), WindowID(rawValue: 2), WindowID(rawValue: 3)]
        )
        let controller = BorderController()
        #expect(controller.groupIndicator(for: WindowID(rawValue: 3), snapshot: try snapshot(groups: [group])) == "docs:1/3")

        _ = group.focus(WindowID(rawValue: 3))
        #expect(controller.groupIndicator(for: WindowID(rawValue: 1), snapshot: try snapshot(groups: [group])) == "docs:3/3")

        group.remove(WindowID(rawValue: 2))
        #expect(controller.groupIndicator(for: WindowID(rawValue: 1), snapshot: try snapshot(groups: [group])) == "docs:3/2")
    }

    @MainActor
    @Test
    func groupIndicatorIsNilOutsideAnyGroupAndAfterDissolution() throws {
        let group = WindowGroup(id: "docs", windowIDs: [WindowID(rawValue: 1), WindowID(rawValue: 2)])
        let controller = BorderController()

        // Fenêtre qui n'appartient à aucun groupe.
        #expect(controller.groupIndicator(for: WindowID(rawValue: 9), snapshot: try snapshot(groups: [group])) == nil)
        // Groupe dissous : plus aucun libellé, même pour d'anciens membres.
        #expect(controller.groupIndicator(for: WindowID(rawValue: 1), snapshot: try snapshot(groups: [])) == nil)
    }

    @MainActor
    @Test
    func groupIndicatorReadsGroupsCreatedByTheCommandService() {
        let provider = PowerUserProvider(windows: [powerWindow(1, x: 100), powerWindow(2, x: 500)])
        let store = StageStore(path: tempPath("group-indicator-service"))
        let service = SnapshotService(provider: provider, frameWriter: PowerUserWriter(provider: provider), stageStore: store)
        _ = service.snapshot()
        let groups = WindowGroupCommandService(service: service, store: store)
        _ = groups.create(id: "pair", windowIDs: [WindowID(rawValue: 1), WindowID(rawValue: 2)])
        _ = groups.focus(windowID: WindowID(rawValue: 2), in: "pair")

        // Chaîne réelle : commande -> store -> snapshot du daemon -> libellé.
        let indicator = BorderController().groupIndicator(for: WindowID(rawValue: 1), snapshot: service.snapshot())
        #expect(indicator == "pair:2/2")

        _ = groups.dissolve(id: "pair")
        #expect(BorderController().groupIndicator(for: WindowID(rawValue: 1), snapshot: service.snapshot()) == nil)
    }

    /// Seul usage de groupe dans l'interface : le rail retire les membres absents d'un groupe et
    /// supprime le groupe s'il reste moins de deux membres.
    @Test
    func railDisplayStagePrunesAbsentGroupMembers() {
        let ids = (1...3).map { WindowID(rawValue: UInt32($0)) }
        let members = ids.map {
            PersistentStageMember(windowID: $0, bundleID: "app.\($0.rawValue)", title: "Window \($0.rawValue)", frame: Rect(x: 0, y: 0, width: 100, height: 100))
        }
        let stage = PersistentStage(
            id: stageID,
            name: "Stage 1",
            members: members,
            groups: [
                WindowGroup(id: "trio", windowIDs: ids, activeWindowID: ids[2]),
                WindowGroup(id: "pair", windowIDs: [ids[0], ids[1]])
            ]
        )

        // Fenêtre 3 absente : le trio devient une paire dont le membre actif passe au premier restant.
        let withoutThree = RailController.railDisplayStage(stage, liveWindowIDs: [ids[0], ids[1]])
        #expect(withoutThree.groups.map(\.id) == ["trio", "pair"])
        #expect(withoutThree.groups.first { $0.id == "trio" }?.windowIDs == [ids[0], ids[1]])
        #expect(withoutThree.groups.first { $0.id == "trio" }?.activeWindowID == ids[0])

        // Il ne reste qu'un membre vivant : plus aucun groupe affiché.
        let onlyOne = RailController.railDisplayStage(stage, liveWindowIDs: [ids[0]])
        #expect(onlyOne.groups.isEmpty)
    }
}
