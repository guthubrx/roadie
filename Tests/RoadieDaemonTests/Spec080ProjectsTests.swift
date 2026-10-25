import Foundation
import Testing
import RoadieCore
import RoadieTiler
@testable import RoadieDaemon

struct Spec080ProjectTests {
    private let now = Date(timeIntervalSince1970: 2_000_000_000)
    private func window(_ app: String, document: String? = nil, url: String? = nil) -> ProjectWindow {
        ProjectWindow(bundleID: "a.\(app)", appPath: "/Applications/\(app).app", document: document, url: url, title: app)
    }

    @Test func captureKeepsLiveWindowsInOrderAndTheTreeByRank() throws {
        let a = WindowID(rawValue: 11), b = WindowID(rawValue: 22), gone = WindowID(rawValue: 33)
        let tree = BSPTree.split(orientation: .vertical, ratio: 0.6, first: .leaf(a),
                                 second: .split(orientation: .horizontal, ratio: 0.5, first: .leaf(gone), second: .leaf(b)))
        let project = StageProject.capture(name: "Essai", members: [a, gone, b],
                                           windows: [a: window("Preview", document: "/Users/x/a.pdf"), b: window("Chrome", url: "https://x.org")],
                                           tree: tree, at: now)
        #expect(project.windows.map(\.title) == ["Preview", "Chrome"])
        // La feuille fermée disparaît, son frère remonte ; les feuilles deviennent des rangs.
        #expect(project.tree == .split(orientation: .vertical, ratio: 0.6, first: .leaf(WindowID(rawValue: 1)), second: .leaf(WindowID(rawValue: 2))))
        let reopened = [WindowID(rawValue: 501), WindowID(rawValue: 502)]
        #expect(project.tree(for: reopened) == .split(orientation: .vertical, ratio: 0.6, first: .leaf(reopened[0]), second: .leaf(reopened[1])))
        #expect(project.tree(for: [reopened[0]]) == nil)
    }

    @Test func aProjectWithoutTreeOrWindowsStaysUsable() {
        let project = StageProject.capture(name: "Vide", members: [WindowID(rawValue: 1)], windows: [:], tree: nil, at: now)
        #expect(project.windows.isEmpty && project.tree == nil)
        #expect(project.tree(for: []) == nil)
    }

    @Test func storeReplacesByNameAndDeletes() {
        let store = StageProjectStore(path: tempPath("spec080-projects") + ".json")
        store.save(StageProject.capture(name: "Essai", members: [], windows: [:], tree: nil, at: now))
        store.save(StageProject(name: "essai", savedAt: now, windows: [window("Notes")], tree: nil))
        #expect(store.load().projects.count == 1)
        #expect(store.load().project(named: "ESSAI")?.windows.count == 1)
        #expect(store.delete("Essai") && !store.delete("Essai"))
    }
}

struct Spec080LauncherTests {
    private let now = Date(timeIntervalSince1970: 2_000_000_000)

    @Test func projectsHaveTheirSectionAndVerbs() {
        let project = StageProject(name: "Rapport", savedAt: now, windows: [], tree: nil)
        let list = LauncherList(query: "rap", apps: [], details: [:], targets: [], ranking: LauncherRanking(), now: now, projects: [project])
        #expect(list.rows.first == .header("Projets") && list.best == "project:rapport")
        #expect(LauncherVerb.verbs(for: .project("Rapport")) == [.reopenProject, .deleteProject])
        let stage = RoadieTarget(id: "stage:1", kind: .stage, title: "Rapport", source: .roadie, actions: [.switch])
        #expect(LauncherVerb.verbs(for: .target(stage)).contains(.saveProject))
        #expect(LauncherAlias.from(LauncherAction(subject: .project("Rapport"), verb: .reopenProject, destination: nil)) { _ in nil }
                == .failure(.unsupportedVerb))
    }
}
