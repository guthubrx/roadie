import Testing
import RoadieAX
import RoadieCore
import RoadieDaemon
import RoadieStages

/// L'indicateur de groupe affiché sur la bordure est testé dans `Audit022R2LotHTests`.
/// Ici : le seul traitement de groupe côté rail.
@Suite
struct WindowGroupIndicatorTests {
    private let stageID = StageID(rawValue: "1")

    /// Le rail retire les membres absents d'un groupe et
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
