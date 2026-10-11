import Foundation
import Testing
import RoadieCore
import RoadieDaemon
import RoadieTiler

/// SPEC-017 A8 : migration explicite des stages `mutableBsp` vers `spatialBsp`.
@Suite
struct StateMigrationTests {
    private let display = DisplayID(rawValue: "display-main")
    private let container = CGRect(x: 0, y: 0, width: 1600, height: 900)

    private func migrationPath() -> String {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("state-migration-\(UUID().uuidString).json").path
    }

    private func cleanUp(_ path: String) {
        try? FileManager.default.removeItem(atPath: path)
        try? FileManager.default.removeItem(atPath: "\(path).pre-017")
        try? FileManager.default.removeItem(atPath: "\(path).lock")
    }

    private func member(_ raw: UInt32, x: Double, width: Double = 400) -> PersistentStageMember {
        PersistentStageMember(
            windowID: WindowID(rawValue: raw),
            bundleID: "com.test.app",
            title: "W\(raw)",
            frame: Rect(x: x, y: 0, width: width, height: 900)
        )
    }

    private func ids(_ raws: [UInt32]) -> [WindowID] { raws.map { WindowID(rawValue: $0) } }

    /// Inférence factice : chaîne de splits qui garde l'ordre des feuilles (indépendante du lot L4).
    private func chain(_ windowIDs: [WindowID]) -> BSPTree {
        guard let first = windowIDs.first else { return .empty }
        return windowIDs.dropFirst().reduce(BSPTree.leaf(first)) {
            .split(orientation: .vertical, ratio: 0.5, first: $0, second: .leaf($1))
        }
    }

    /// Stage 1 : mutableBsp à 3 membres dans un ordre non trié ; stage 2 : mutableBsp vide ;
    /// stage 3 : masterStack ; stage 4 : spatialBsp avec arbre (non concernées).
    private func legacyState() -> PersistentStageState {
        PersistentStageState(scopes: [
            PersistentStageScope(displayID: display, stages: [
                PersistentStage(id: StageID(rawValue: "1"), mode: .mutableBsp, members: [
                    member(30, x: 0), member(10, x: 400), member(20, x: 800, width: 0),
                ]),
                PersistentStage(id: StageID(rawValue: "2"), mode: .mutableBsp),
                PersistentStage(id: StageID(rawValue: "3"), mode: .masterStack, members: [member(40, x: 0)]),
                PersistentStage(id: StageID(rawValue: "4"), mode: .spatialBsp, members: [member(50, x: 0)], bspTree: .leaf(WindowID(rawValue: 50))),
            ]),
        ])
    }

    private func stage(_ state: PersistentStageState, _ id: String) -> PersistentStage? {
        state.scopes.first?.stages.first { $0.id == StageID(rawValue: id) }
    }

    @Test
    func migrationBacksUpOnceKeepsMembersAndOrderAndIsIdempotent() throws {
        let path = migrationPath()
        defer { cleanUp(path) }
        let store = StageStore(path: path)
        let legacy = legacyState()
        store.save(legacy)
        let original = try Data(contentsOf: URL(fileURLWithPath: path))
        var inferred: [([(WindowID, CGRect?)], CGRect)] = []

        let migrated = try store.migrateLegacyTreeModes(
            infer: { ordered, rect in
                inferred.append((ordered, rect))
                return chain(ordered.map(\.0))
            },
            container: { _ in container }
        )

        #expect(migrated == 2)
        #expect(try Data(contentsOf: URL(fileURLWithPath: "\(path).pre-017")) == original)
        let state = store.state()
        #expect(stage(state, "1")?.mode == .spatialBsp)
        #expect(stage(state, "1")?.members.map(\.windowID) == ids([30, 10, 20]))
        #expect(stage(state, "1")?.bspTree?.windowIDs == ids([30, 10, 20]))
        #expect(stage(state, "2")?.mode == .spatialBsp)
        #expect(stage(state, "2")?.bspTree == nil)
        #expect(stage(state, "3") == stage(legacy, "3"))
        #expect(stage(state, "4") == stage(legacy, "4"))
        // Un seul appel (stage 1), membres dans l'ordre ; frame de largeur nulle transmise à nil.
        #expect(inferred.count == 1)
        #expect(inferred.first?.0.map(\.0) == ids([30, 10, 20]))
        #expect(inferred.first?.0.map { $0.1 == nil } == [false, false, true])
        #expect(inferred.first?.1 == container)

        // Deuxième appel : rien à migrer, aucune écriture (inode inchangé), sauvegarde intacte.
        let inode = try FileManager.default.attributesOfItem(atPath: path)[.systemFileNumber] as? Int
        let again = try store.migrateLegacyTreeModes(
            infer: { _, _ in Issue.record("infer ne doit pas être appelé"); return .empty },
            container: { _ in container }
        )
        #expect(again == 0)
        #expect(try FileManager.default.attributesOfItem(atPath: path)[.systemFileNumber] as? Int == inode)
        #expect(try Data(contentsOf: URL(fileURLWithPath: "\(path).pre-017")) == original)
    }

    /// Une sauvegarde existante n'est jamais écrasée ; un arbre qui couvre déjà les membres est gardé ;
    /// sans conteneur d'écran, l'inférence reçoit l'union des frames connues.
    @Test
    func migrationKeepsExistingBackupAndValidTreeAndFallsBackToKnownFrames() throws {
        let path = migrationPath()
        defer { cleanUp(path) }
        let store = StageStore(path: path)
        let tree = BSPTree.split(orientation: .vertical, ratio: 0.3, first: .leaf(WindowID(rawValue: 1)), second: .leaf(WindowID(rawValue: 2)))
        store.save(PersistentStageState(scopes: [
            PersistentStageScope(displayID: display, stages: [
                PersistentStage(id: StageID(rawValue: "1"), mode: .mutableBsp, members: [member(1, x: 0), member(2, x: 400)], bspTree: tree),
                PersistentStage(id: StageID(rawValue: "2"), mode: .mutableBsp, members: [member(3, x: 100), member(4, x: 500)], bspTree: .leaf(WindowID(rawValue: 9))),
            ]),
        ]))
        try "older backup".write(toFile: "\(path).pre-017", atomically: true, encoding: .utf8)
        var containers: [CGRect] = []

        let migrated = try store.migrateLegacyTreeModes(
            infer: { ordered, rect in
                containers.append(rect)
                return chain(ordered.map(\.0))
            },
            container: { _ in nil }
        )

        #expect(migrated == 2)
        #expect(try String(contentsOfFile: "\(path).pre-017", encoding: .utf8) == "older backup")
        let state = store.state()
        #expect(stage(state, "1")?.bspTree == tree)
        #expect(stage(state, "2")?.bspTree?.windowIDs == ids([3, 4]))
        #expect(containers == [CGRect(x: 100, y: 0, width: 800, height: 900)])
    }

    /// Fichier illisible (FR-015) : aucune migration, aucune sauvegarde, fichier intact.
    @Test
    func migrationLeavesUnreadableFileUntouched() throws {
        let path = migrationPath()
        defer {
            cleanUp(path)
            let directory = (path as NSString).deletingLastPathComponent
            let name = (path as NSString).lastPathComponent
            for file in (try? FileManager.default.contentsOfDirectory(atPath: directory)) ?? [] where file.hasPrefix("\(name).corrupt-") {
                try? FileManager.default.removeItem(atPath: "\(directory)/\(file)")
            }
        }
        let garbage = "{\"scopes\": [ {\"mode\": \"mutableBsp\""
        try garbage.write(toFile: path, atomically: true, encoding: .utf8)

        let migrated = try StageStore(path: path).migrateLegacyTreeModes(
            infer: { _, _ in .empty },
            container: { _ in container }
        )

        #expect(migrated == 0)
        #expect(!FileManager.default.fileExists(atPath: "\(path).pre-017"))
        #expect(try String(contentsOfFile: path, encoding: .utf8) == garbage)
    }
}
