import Foundation
import Testing
import RoadieCore
import RoadieDaemon

@Suite
struct TargetSearchModelTests {
    private func target(_ label: String, _ title: String, source: TargetSource = .app, kind: TargetKind = .appElement) -> RoadieTarget {
        RoadieTarget(
            id: "app:\(label)",
            label: label,
            kind: kind,
            title: title,
            source: source,
            frame: Rect(x: 0, y: 0, width: 20, height: 20),
            actions: source == .app ? [.click, .doubleClick, .rightClick, .inspect] : [.focus]
        )
    }

    private var sample: [RoadieTarget] {
        [target("A", "Home"), target("S", "Watch Later"), target("D", "Écoute à la carte"), target("F", "Subscriptions")]
    }

    @Test
    func matchingIgnoresCaseAccentsAndSpaces() {
        var model = TargetSearchModel(targets: sample)
        model.type("watchlater")
        #expect(model.matches.map(\.title) == ["Watch Later"])
        model = TargetSearchModel(targets: sample)
        model.type("ECOUTE A")
        #expect(model.matches.map(\.title) == ["Écoute à la carte"])
    }

    @Test
    func titlesStartingWithTheQueryComeFirst() {
        var model = TargetSearchModel(targets: [target("A", "My subscriptions list"), target("S", "Subscriptions")])
        model.type("subscr")
        #expect(model.matches.map(\.title) == ["Subscriptions", "My subscriptions list"])
        #expect(model.highlighted?.title == "Subscriptions")
    }

    @Test
    func emptyStarAndSemicolonShowEverything() {
        for query in ["", "*", ";"] {
            var model = TargetSearchModel(targets: sample)
            model.type(query)
            #expect(model.matches.count == sample.count)
        }
    }

    @Test
    func navigationWrapsAndTypingResetsTheHighlight() {
        var model = TargetSearchModel(targets: sample)
        model.type("e")
        let titles = model.matches.map(\.title)
        #expect(model.highlightedIndex == 0)
        model.previous()
        #expect(model.highlighted?.title == titles.last)
        model.next()
        #expect(model.highlightedIndex == 0)
        model.next()
        model.type("r")
        #expect(model.highlightedIndex == 0)
        model.deleteBackward()
        #expect(model.query == "e")
    }

    @Test
    func noMatchLeavesNothingHighlighted() {
        var model = TargetSearchModel(targets: sample)
        model.type("zzz")
        #expect(model.matches.isEmpty)
        #expect(model.highlighted == nil)
        let verb = model.pressReturn(shift: false, command: false, at: Date())
        #expect(verb == nil)
    }

    @Test
    func shiftLabelJumpsToThatTarget() {
        // Étiquettes données par le modèle : A, S, D… puis AA, AS… ; la 19e est « SA ».
        var model = TargetSearchModel(targets: (0..<20).map { target("T\($0)", "Item \($0)") })
        let beforeTyping = model.typeLabel("s")
        #expect(!beforeTyping)
        model.type("*")
        let first = model.typeLabel("s")
        let firstLabel = model.highlighted?.label
        let second = model.typeLabel("a")
        let secondLabel = model.highlighted?.label
        let unknown = model.typeLabel("q")
        #expect(first && second && !unknown)
        #expect(firstLabel == "S")
        #expect(secondLabel == "SA")
    }

    @Test
    func lateWindowsKeepLabelsAndTheHighlightedTarget() {
        var model = TargetSearchModel(targets: [target("A", "Alpha"), target("B", "Beta")], rank: { _ in 5 })
        model.type("*")
        model.next()
        model.append([target("C", "Gamma")], rank: { _ in 1 })
        model.append([target("D", "Delta")], rank: { _ in 9 })

        #expect(model.targets.map(\.id) == ["app:C", "app:A", "app:B", "app:D"])
        #expect(model.targets.map(\.label) == ["D", "A", "S", "F"])
        #expect(model.highlighted?.id == "app:B")
    }

    @Test
    func fewResultsGetOneLetterLabels() {
        var model = TargetSearchModel(targets: (0..<20).map { target("T\($0)", "Item \($0)") } + [target("X", "Watch Later"), target("Y", "Watch History")])
        model.type("watch")
        let labels = model.matches.map(\.label)
        let picked = model.typeLabel("s")
        #expect(labels == ["A", "S"])
        #expect(model.hasShortLabels)
        #expect(picked && model.highlighted?.id == "app:Y")
        #expect(model.targets.last?.label != "S")
    }

    @Test
    func anEmptyBarSelectsNothing() {
        var model = TargetSearchModel(targets: sample)
        let verb = model.pressReturn(shift: true, command: false, at: Date())
        model.next()
        #expect(model.highlighted == nil)
        #expect(verb == nil)
        model.type("*")
        #expect(model.highlighted != nil)
        model.deleteBackward()
        #expect(model.highlighted == nil)
    }

    @Test
    func returnVariantsChooseTheClick() {
        var model = TargetSearchModel(targets: sample)
        model.type("*")
        let start = Date()
        let verbs: [TargetActionVerb?] = [
            model.pressReturn(shift: true, command: false, at: start),
            model.pressReturn(shift: false, command: true, at: start),
            model.pressReturn(shift: false, command: false, at: start),
            model.pressReturn(shift: false, command: false, at: start.addingTimeInterval(0.2)),
            model.pressReturn(shift: false, command: false, at: start.addingTimeInterval(1)),
            model.pendingReturn(at: start.addingTimeInterval(1.1)),
            model.pendingReturn(at: start.addingTimeInterval(1.4)),
            model.pendingReturn(at: start.addingTimeInterval(2)),
        ]
        #expect(verbs == [.rightClick, .commandClick, nil, .doubleClick, nil, nil, .click, nil])
    }

    @Test
    func roadieTargetsUseTheirDefaultAction() {
        var model = TargetSearchModel(targets: [target("A", "Terminal", source: .roadie, kind: .window)])
        model.type("term")
        let start = Date()
        let shifted = model.pressReturn(shift: true, command: false, at: start)
        _ = model.pressReturn(shift: false, command: false, at: start)
        let pending = model.pendingReturn(at: start.addingTimeInterval(0.5))
        #expect(shifted == .focus)
        #expect(pending == .focus)
    }

    @Test
    func questionMarkShowsPropertiesUntilTheNextKey() {
        var model = TargetSearchModel(targets: sample)
        model.type("home")
        model.type("?")
        #expect(model.query == "home")
        #expect(model.properties?.contains("Home") == true)
        model.type("x")
        #expect(model.properties == nil)
    }

    @Test
    func webTargetsRankByTheirChildText() {
        var leaf = target("A", "AXGroup")
        leaf.searchText = "Subscriptions"
        var model = TargetSearchModel(targets: [target("S", "My subscriptions list"), leaf])
        model.type("subscr")
        #expect(model.highlighted?.id == "app:A")
    }

    @Test
    func searchKeysAreDecodedLikeHomerow() {
        func kind(_ code: Int64, _ text: String = "", shift: Bool = false, command: Bool = false, control: Bool = false, isRepeat: Bool = false) -> SearchKeyInput.Kind {
            SearchKeyInput.kind(keyCode: code, text: text, shift: shift, command: command, control: control, isRepeat: isRepeat)
        }
        #expect(kind(0, "a") == .text("a"))
        #expect(kind(0, "A", shift: true) == .labelCharacter("a"))
        #expect(kind(42, "*") == .text("*"))
        #expect(kind(43, ";") == .text(";"))
        #expect(kind(46, "?", shift: true) == .text("?"))
        #expect(kind(49, " ") == .text(" "))
        #expect(kind(48, "\t") == .next)
        #expect(kind(48, "\t", shift: true) == .previous)
        #expect(kind(45, "\u{0E}", control: true) == .next)
        #expect(kind(35, "\u{10}", control: true) == .previous)
        #expect(kind(36, "\r", shift: true) == .confirm(shift: true, command: false, isRepeat: false))
        #expect(kind(36, "\r", command: true) == .confirm(shift: false, command: true, isRepeat: false))
        #expect(kind(36, "\r", isRepeat: true) == .confirm(shift: false, command: false, isRepeat: true))
        #expect(kind(48, "\t", command: true) == .ignored)
        #expect(kind(1, "s", command: true) == .ignored)
        #expect(kind(33, "") == .ignored)
        #expect(kind(53) == .escape)
        #expect(kind(51) == .delete)
    }
}
