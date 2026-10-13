import Foundation
import Testing
import RoadieCore
import RoadieDaemon

private struct FakeAppTargetProvider: AppTargetProviding {
    var items: [AppElementCandidate]
    var clickResult: TargetActionResult = TargetActionResult(changed: true, message: "clicked")

    func candidates(config: AppTargetsConfig) -> AppTargetQueryReport {
        AppTargetQueryReport(targets: AppTargetQueryService.targets(from: items, config: config))
    }

    func click(_ target: RoadieTarget, action: TargetActionVerb) -> TargetActionResult {
        TargetActionResult(changed: clickResult.changed, message: "\(action.rawValue) \(target.id)", target: target, error: clickResult.error)
    }
}

@Suite
struct AppTargetQueryServiceTests {
    @Test
    func appTargetsAreDisabledUnlessConfiguredOrOverridden() {
        let service = AppTargetQueryService(provider: FakeAppTargetProvider(items: []))

        let report = service.query(config: AppTargetsConfig(enabled: false), enabledOverride: false)

        #expect(report.targets.isEmpty)
        #expect(report.error == "app_targets_disabled")
    }

    @Test
    func appTargetsFilterRolesAndPreserveActionableElements() {
        let provider = FakeAppTargetProvider(items: [
            AppElementCandidate(id: "1", role: "AXButton", title: "OK", frame: Rect(x: 0, y: 0, width: 20, height: 20), actions: []),
            AppElementCandidate(id: "2", role: "AXStaticText", title: "Label", frame: Rect(x: 0, y: 30, width: 20, height: 20), actions: []),
            AppElementCandidate(id: "3", role: "AXStaticText", title: "Clickable", frame: Rect(x: 0, y: 60, width: 20, height: 20), actions: ["AXPress"]),
        ])
        let service = AppTargetQueryService(provider: provider)
        let config = AppTargetsConfig(enabled: true, includeRoles: ["AXButton"])

        let report = service.query(config: config)

        #expect(report.targets.map(\.title) == ["OK", "Clickable"])
        #expect(report.targets.allSatisfy { $0.actions.contains(.click) })
        #expect(report.targets.allSatisfy { $0.actions.contains(.doubleClick) })
        #expect(report.targets.allSatisfy { $0.actions.contains(.rightClick) })
    }

    @Test
    func clickVariantsAreRoutedToProvider() {
        let target = RoadieTarget(
            id: "app:1/0",
            kind: .appElement,
            title: "OK",
            source: .app,
            frame: Rect(x: 0, y: 0, width: 100, height: 40),
            actions: [.click, .doubleClick, .rightClick]
        )
        let service = AppTargetQueryService(provider: FakeAppTargetProvider(items: []))

        let result = service.click(target, action: .rightClick)

        #expect(result.changed)
        #expect(result.message == "right-click app:1/0")
    }

    @Test
    func scanIsRetriedOnlyWhileAFullyExploredElectronTreeHasNoWebArea() {
        #expect(AppTargetQueryService.shouldRetryScan(isElectron: true, sawWebArea: false, exploredFully: true, retries: 0))
        #expect(AppTargetQueryService.shouldRetryScan(isElectron: true, sawWebArea: false, exploredFully: true, retries: 1))
        #expect(!AppTargetQueryService.shouldRetryScan(isElectron: true, sawWebArea: false, exploredFully: true, retries: 2))
        #expect(!AppTargetQueryService.shouldRetryScan(isElectron: true, sawWebArea: true, exploredFully: true, retries: 0))
        #expect(!AppTargetQueryService.shouldRetryScan(isElectron: true, sawWebArea: false, exploredFully: false, retries: 0))
        #expect(!AppTargetQueryService.shouldRetryScan(isElectron: false, sawWebArea: false, exploredFully: true, retries: 0))
    }

    @Test
    func electronBundlesAreDetectedByTheirFramework() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let electron = root.appendingPathComponent("Electron.app")
        let native = root.appendingPathComponent("Native.app")
        try FileManager.default.createDirectory(
            at: electron.appendingPathComponent("Contents/Frameworks/Electron Framework.framework"),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(at: native.appendingPathComponent("Contents/Frameworks"), withIntermediateDirectories: true)

        #expect(AppTargetQueryService.isElectronBundle(at: electron))
        #expect(!AppTargetQueryService.isElectronBundle(at: native))
        #expect(!AppTargetQueryService.isElectronBundle(at: nil))
    }

    @Test
    func elementsAreClippedToTheWindowSoTheirClickPointStaysInside() {
        let window = Rect(x: 100, y: 100, width: 400, height: 300)

        #expect(AppTargetQueryService.visibleFrame(Rect(x: 150, y: 150, width: 20, height: 20), in: window)
            == Rect(x: 150, y: 150, width: 20, height: 20))
        let clipped = AppTargetQueryService.visibleFrame(Rect(x: 480, y: 380, width: 60, height: 60), in: window)
        #expect(clipped == Rect(x: 480, y: 380, width: 20, height: 20))
        #expect(clipped.map { window.cgRect.contains(CGPoint(x: $0.cgRect.midX, y: $0.cgRect.midY)) } == true)
        #expect(AppTargetQueryService.visibleFrame(Rect(x: 150, y: 900, width: 20, height: 20), in: window) == nil)
        #expect(AppTargetQueryService.visibleFrame(Rect(x: 500, y: 150, width: 20, height: 20), in: window) == nil)
        #expect(AppTargetQueryService.visibleFrame(Rect(x: 150, y: 900, width: 20, height: 20), in: nil)
            == Rect(x: 150, y: 900, width: 20, height: 20))
    }

    @Test
    func aFocusableElementIsALeafUnlessTheNextFocusableInPreorderIsItsDescendant() {
        #expect(AppTargetQueryService.keepsFocusableLeaf(path: "0.1", nextFocusablePath: nil))
        #expect(!AppTargetQueryService.keepsFocusableLeaf(path: "0.1", nextFocusablePath: "0.1.4.2"))
        #expect(AppTargetQueryService.keepsFocusableLeaf(path: "0.1", nextFocusablePath: "0.10"))
        #expect(AppTargetQueryService.keepsFocusableLeaf(path: "0.1", nextFocusablePath: "0.2.0"))
    }

    @Test
    func rejectedRolesAreSummarizedByFrequencyThenName() {
        let counts = ["AXGroup": 197, "AXStaticText": 106, "AXImage": 96, "AXButton": 4, "AXCell": 4, "AXRow": 1]

        #expect(AppTargetQueryService.rejectedRoleSummary(counts)
            == "AXGroup=197,AXStaticText=106,AXImage=96,AXButton=4,AXCell=4")
        #expect(AppTargetQueryService.rejectedRoleSummary(counts, limit: 2) == "AXGroup=197,AXStaticText=106")
        #expect(AppTargetQueryService.rejectedRoleSummary([:]) == "")
    }

    @Test
    func aFocusableLeafWithoutActionReachesTheFinalTargets() {
        let candidates = [
            AppElementCandidate(id: "1/0.4", role: "AXGroup", title: "Home", frame: Rect(x: 0, y: 0, width: 260, height: 44),
                                actions: [], isFocusableLeaf: true),
            AppElementCandidate(id: "1/0.5", role: "AXGroup", title: "Decor", frame: Rect(x: 0, y: 50, width: 260, height: 44),
                                actions: []),
        ]

        let targets = AppTargetQueryService.targets(from: candidates, config: AppTargetsConfig(enabled: true, includeRoles: ["AXButton"]))

        #expect(targets.map(\.title) == ["Home"])
    }

    @Test
    func onlyFullyExploredFocusableLeavesAreKept() {
        // 0.1 : carte feuille. 0.2 : conteneur d'une feuille (0.2.0). 0.3 : un descendant coupé à max_depth.
        // 0.4 : sous-arbre encore dans la pile d'un parcours coupé. 0.5 : son seul descendant focalisable
        // est hors fenêtre, mais reste un marqueur.
        let markers = ["0.1", "0.2", "0.2.0", "0.3", "0.3.0.?", "0.4", "0.5", "0.5.1"]
        let pending = ["0.1", "0.2", "0.2.0", "0.3", "0.4", "0.5"]

        let leaves = AppTargetQueryService.focusableLeaves(pending: pending, markers: markers, unexplored: ["0.4.2"])

        #expect(leaves == ["0.1", "0.2.0"])
    }

    @Test
    func aFocusableElementWithUnreadableChildrenIsNotProvenALeaf() {
        #expect(AppTargetQueryService.focusableLeaves(pending: ["0.1"], markers: ["0.1", "0.1.?"], unexplored: []).isEmpty)
        // Enfants illisibles par AXChildren mais lus par un attribut boost : le marqueur inconnu suffit.
        #expect(AppTargetQueryService.focusableLeaves(pending: ["0.1"], markers: ["0.1", "0.1.?", "0.1.0"], unexplored: []).isEmpty)
        // Parcours interrompu juste avant le premier enfant : l'enfant reste dans la pile.
        #expect(AppTargetQueryService.focusableLeaves(pending: ["0.1"], markers: ["0.1"], unexplored: ["0.1.0"]).isEmpty)
        // Descendant plus profond resté dans la pile ; `0.10.0` n'est pas sous `0.1`.
        #expect(AppTargetQueryService.focusableLeaves(pending: ["0.1", "0.2"], markers: ["0.1", "0.2"],
                                                      unexplored: ["0.2.3.0", "0.10.0"]) == ["0.1"])
    }

    @Test
    func aLeafIsADuplicateOnlyWhenItCoversItsRetainedTarget() {
        let button = Rect(x: 0, y: 0, width: 100, height: 40)
        let page = Rect(x: 0, y: 0, width: 1800, height: 2000)

        #expect(AppTargetQueryService.duplicatesTarget(Rect(x: 2, y: 2, width: 96, height: 36), of: button))
        #expect(!AppTargetQueryService.duplicatesTarget(Rect(x: 0, y: 0, width: 327, height: 287), of: page))
        #expect(!AppTargetQueryService.duplicatesTarget(Rect(x: 0, y: 0, width: 30, height: 30), of: button))
        #expect(!AppTargetQueryService.duplicatesTarget(button, of: nil))
        // Petite cible dans le coin d'une feuille plus grande : pas la même boîte.
        #expect(!AppTargetQueryService.duplicatesTarget(Rect(x: 20, y: 20, width: 80, height: 80),
                                                        of: Rect(x: 90, y: 90, width: 10, height: 10)))
    }

    @Test
    func slivedOrTinyElementsAreNotHintable() {
        #expect(AppTargetQueryService.isHintable(Rect(x: 0, y: 0, width: 260, height: 44)))
        #expect(!AppTargetQueryService.isHintable(Rect(x: 0, y: 0, width: 145, height: 1)))
        #expect(!AppTargetQueryService.isHintable(Rect(x: 0, y: 0, width: 4, height: 40)))
    }

    @Test
    func identitySetUsesRealEqualityNotOnlyTheHash() {
        // CFString ne hache que le début, le milieu et la fin d'une longue chaîne : même hash, contenus différents.
        let first = (String(repeating: "a", count: 48) + "X" + String(repeating: "b", count: 100)) as CFString
        let second = (String(repeating: "a", count: 48) + "Y" + String(repeating: "b", count: 100)) as CFString
        #expect(CFHash(first) == CFHash(second))
        var set = CFIdentitySet()
        let inserted = [
            set.insert("abc" as CFString),
            set.insert("abc" as CFString),
            set.insert("abd" as CFString),
            set.insert(NSNumber(value: 1)),
            set.insert(first),
            set.insert(second),
        ]

        #expect(inserted == [true, false, true, true, true, true])
    }

    @Test
    func onlyScrolledOutOrOffWindowElementsHideContent() {
        #expect(AppTargetQueryService.hidesContent(nil))
        #expect(AppTargetQueryService.hidesContent(Rect(x: 0, y: 0, width: 191, height: 1)))
        #expect(!AppTargetQueryService.hidesContent(Rect(x: 0, y: 0, width: 283, height: 4)))
    }

    @Test
    func searchTextKeepsChildTextWithoutRepeatingTheTitle() {
        let text = AppTargetQueryService.searchText(
            ["  Subscriptions ", "Subscriptions", "", "Home"],
            excluding: ["home", ""]
        )
        #expect(text == "Subscriptions")
        #expect(AppTargetQueryService.searchText([String(repeating: "a", count: 600)], excluding: []).count == 500)
    }

    @Test
    func childTextMakesAWebTargetSearchable() {
        let candidate = AppElementCandidate(id: "1/0.4", role: "AXGroup", title: "", frame: Rect(x: 0, y: 0, width: 300, height: 270),
                                            actions: [], isFocusableLeaf: true, searchText: "Meta just dropped something")
        let target = AppTargetQueryService.targets(from: [candidate], config: AppTargetsConfig(enabled: true)).first

        #expect(target?.title == "AXGroup")
        #expect(target?.matchText.contains("meta just dropped") == true)
        #expect(target?.searchText == "Meta just dropped something")
    }

    @Test
    func aWebLeafIsClickedOnItsFirstContentNotItsCenter() {
        let row = Rect(x: 0, y: 0, width: 900, height: 90)
        let thumbnail = Rect(x: 10, y: 4, width: 150, height: 82)
        let leaf = AppElementCandidate(id: "1/0.6", role: "AXGroup", title: "", frame: row, actions: [],
                                       isFocusableLeaf: true, clickFrame: thumbnail)
        let button = AppElementCandidate(id: "1/0.7", role: "AXButton", title: "OK", frame: row, actions: ["AXPress"])
        let targets = AppTargetQueryService.targets(from: [leaf, button], config: AppTargetsConfig(enabled: true))

        #expect(targets.first?.frame == row)
        #expect(targets.first?.clickFrame == thumbnail)
        #expect(targets.last?.clickFrame == nil)
    }
}
