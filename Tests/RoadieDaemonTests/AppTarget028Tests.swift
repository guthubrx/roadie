import AppKit
import Testing
import RoadieCore
@testable import RoadieDaemon

/// Arbre synthétique à la frontière AX. Aucune lecture d'Outlook ni permission macOS.
private struct Native028Node {
    var role: String
    var title: String? = nil
    var description: String? = nil
    var value: String? = nil
    var frame: Rect? = nil
    var actions: [String] = []
    var children: [Int] = []
}

private final class Native028Tree {
    let nodes: [Native028Node]
    let elements: [AXUIElement]
    var metadataReads = 0
    var frameReads = 0
    var roleReads = 0
    var childrenReads = 0

    // copyFrame lit AXPosition et AXSize ; les autres lectures font un appel AX chacune.
    var totalAXReads: Int { metadataReads + roleReads + childrenReads + 2 * frameReads }

    init(_ nodes: [Native028Node]) {
        self.nodes = nodes
        elements = nodes.indices.map { AXUIElementCreateApplication(pid_t(10_000 + $0)) }
    }

    private func node(_ element: AXUIElement) -> Native028Node {
        nodes[elements.firstIndex { CFEqual($0, element) }!]
    }

    var reader: AppTargetScanReader {
        AppTargetScanReader(
            string: { element, attribute in
                let node = self.node(element)
                if attribute == kAXRoleAttribute { self.roleReads += 1; return node.role }
                self.metadataReads += 1
                switch attribute {
                case kAXValueAttribute: return node.value
                case kAXTitleAttribute: return node.title
                case kAXDescriptionAttribute: return node.description
                default: return nil
                }
            },
            actions: { element in self.metadataReads += 1; return self.node(element).actions },
            frame: { element in self.frameReads += 1; return self.node(element).frame },
            children: { element, _ in
                self.childrenReads += 1
                return (self.node(element).children.map { self.elements[$0] }, false)
            },
            focusSettable: { _ in false }
        )
    }

    func scan(includeRoles: [String] = ["AXRow", "AXButton"]) -> LiveAppTargetProvider.ScanPass {
        LiveAppTargetProvider().scan(window: elements[0], rootPath: "0", pid: 99,
            config: AppTargetsConfig(enabled: true, maxTargets: 150, includeRoles: includeRoles),
            boost: false, deadline: Date().addingTimeInterval(5), reader: reader)
    }
}

private func native028FolderTree(window: Rect, visibleRow: Rect, hiddenRows: Int) -> Native028Tree {
    let hiddenFrame = Rect(x: 20, y: 900, width: 200, height: 24)
    var nodes = [Native028Node(role: "AXWindow", frame: window,
                              children: Array(stride(from: 1, through: hiddenRows * 3 + 1, by: 3)))]
    for index in 0...hiddenRows {
        let start = nodes.count
        let frame = index == hiddenRows ? visibleRow : hiddenFrame
        let label = index == hiddenRows ? "Drafts" : "Previous folder"
        nodes.append(Native028Node(role: "AXRow", frame: frame, actions: ["AXPress"], children: [start + 1]))
        nodes.append(Native028Node(role: "AXCell", frame: frame, children: [start + 2]))
        nodes.append(Native028Node(role: "AXStaticText", value: label, frame: frame))
    }
    return Native028Tree(nodes)
}

@Suite
struct AppTarget028Tests {
    private let window = Rect(x: 0, y: 0, width: 1000, height: 800)
    private let row = Rect(x: 20, y: 80, width: 200, height: 24)

    @Test
    func draftFindsTheNativeRowLabeledByItsCellWithoutChangingItsClickTarget() {
        let tree = Native028Tree([
            Native028Node(role: "AXWindow", frame: window, children: [1]),
            Native028Node(role: "AXRow", frame: row, actions: ["AXPress"], children: [2]),
            Native028Node(role: "AXCell", frame: row, children: [3]),
            Native028Node(role: "AXStaticText", value: "Drafts", frame: row),
        ])
        let pass = tree.scan()
        let targets = AppTargetQueryService.targets(from: pass.candidates, config: AppTargetsConfig(enabled: true, includeRoles: ["AXRow"]))
        var search = TargetSearchModel(targets: targets)
        search.type("draft")

        #expect(search.matches.map(\.id) == ["app:99/0.0"])
        #expect(search.matches.first?.searchText == "Drafts")
        #expect(search.matches.first?.frame == row)
        #expect(search.matches.first?.clickFrame == nil)
        #expect(pass.elements["app:99/0.0"].map { CFEqual($0.element, tree.elements[1]) } == true)
        #expect(pass.stopReason == "complete")
    }

    @Test
    func nativeLabelsStayWithTheirRowOrNestedButtonAndIgnoreTextOutsideTheControl() {
        let button = Rect(x: 170, y: 80, width: 40, height: 24)
        let secondRow = Rect(x: 20, y: 120, width: 200, height: 24)
        let tree = Native028Tree([
            Native028Node(role: "AXWindow", frame: window, children: [1, 6]),
            Native028Node(role: "AXRow", frame: row, actions: ["AXPress"], children: [2, 3, 5]),
            Native028Node(role: "AXStaticText", value: "Drafts", frame: row),
            Native028Node(role: "AXButton", frame: button, actions: ["AXPress"], children: [4]),
            Native028Node(role: "AXStaticText", value: "More", frame: button),
            Native028Node(role: "AXStaticText", value: "Hidden", frame: Rect(x: 20, y: 500, width: 80, height: 24)),
            Native028Node(role: "AXRow", frame: secondRow, actions: ["AXPress"], children: [7]),
            Native028Node(role: "AXStaticText", value: "Sent", frame: secondRow),
        ])

        #expect(tree.scan().candidates.map(\.searchText) == ["Drafts", "More", "Sent"])
    }

    @Test
    func emptyNativeTitleUsesDescriptionAndEmptyStaticValueUsesTitle() {
        let tree = Native028Tree([
            Native028Node(role: "AXWindow", frame: window, children: [1, 2]),
            Native028Node(role: "AXRow", title: "", description: "Drafts", frame: row, actions: ["AXPress"]),
            Native028Node(role: "AXRow", frame: Rect(x: 20, y: 120, width: 200, height: 24), actions: ["AXPress"], children: [3]),
            Native028Node(role: "AXStaticText", title: "Sent", value: "  ", frame: Rect(x: 20, y: 120, width: 200, height: 24)),
        ])
        let targets = AppTargetQueryService.targets(from: tree.scan().candidates, config: AppTargetsConfig(enabled: true, includeRoles: ["AXRow"]))
        var search = TargetSearchModel(targets: targets)
        search.type("draft")

        #expect(search.matches.first?.title == "Drafts")
        #expect(targets.last?.searchText == "Sent")
    }

    @Test
    func aNativePageContainerDoesNotInheritAllItsText() {
        let tree = Native028Tree([
            Native028Node(role: "AXWindow", frame: window, children: [1]),
            Native028Node(role: "AXGroup", frame: window, actions: ["AXPress"], children: [2]),
            Native028Node(role: "AXStaticText", value: "Drafts", frame: row),
        ])

        #expect(tree.scan().candidates.map(\.searchText) == [""])
    }

    @Test
    func aWebControlStillInheritsItsStaticText() {
        let tree = Native028Tree([
            Native028Node(role: "AXWindow", frame: window, children: [1]),
            Native028Node(role: "AXWebArea", frame: window, children: [2]),
            Native028Node(role: "AXGroup", frame: row, actions: ["AXPress"], children: [3]),
            Native028Node(role: "AXStaticText", value: "Subscriptions", frame: row),
        ])

        #expect(tree.scan().candidates.map(\.searchText) == ["Subscriptions"])
    }

    @Test
    func webEmptyTitleAndValueKeepTheirExistingFallbackBehavior() {
        let tree = Native028Tree([
            Native028Node(role: "AXWindow", frame: window, children: [1]),
            Native028Node(role: "AXWebArea", frame: window, children: [2]),
            Native028Node(role: "AXGroup", title: "", description: "Page description", frame: row,
                          actions: ["AXPress"], children: [3]),
            Native028Node(role: "AXStaticText", title: "Text title", value: "", frame: row),
        ])
        let candidate = tree.scan().candidates.first

        #expect(candidate?.title == "")
        #expect(candidate?.searchText == "")
    }

    @Test
    func offWindowNativeRowsSkipMetadataButStillExposeVisibleChildrenWithStablePaths() {
        let offscreen = Rect(x: 20, y: 900, width: 200, height: 24)
        let tree = Native028Tree([
            Native028Node(role: "AXWindow", frame: window, children: [1]),
            Native028Node(role: "AXRow", frame: offscreen, actions: ["AXPress"], children: [2]),
            Native028Node(role: "AXRow", frame: row, actions: ["AXPress"], children: [3]),
            Native028Node(role: "AXStaticText", value: "Drafts", frame: row),
        ])
        let pass = tree.scan()

        #expect(pass.candidates.map(\.id) == ["99/0.0.0"])
        #expect(pass.candidates.first?.searchText == "Drafts")
        #expect(pass.visited == 4)
        #expect(tree.metadataReads == 12) // Fenêtre, ligne visible, texte : 4 lectures chacun ; ligne hors écran : 0.
        #expect(tree.frameReads == 4) // Cadre de fenêtre et un cadre par ligne/texte, sans double lecture.
    }

    @Test
    func manyOffWindowRowsDoNotSpendTheMetadataBudgetBeforeTheVisibleFolder() {
        // Chaque frère possède la structure native complète AXRow → AXCell → AXStaticText.
        let tree = native028FolderTree(window: window, visibleRow: row, hiddenRows: 120)
        let pass = tree.scan()

        #expect(pass.candidates.map(\.id) == ["99/0.120"])
        #expect(pass.candidates.first?.searchText == "Drafts")
        #expect(pass.visited == 364)
        #expect(tree.metadataReads == 16) // Métadonnées des 4 éléments visibles seulement.
        #expect(tree.totalAXReads == 1472) // Avant correction : 2428 appels, y compris les deux lectures par cadre.
        #expect(pass.stopReason == "complete")
    }
}
