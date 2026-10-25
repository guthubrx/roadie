import CoreGraphics
import Foundation
import Testing
import RoadieAX
import RoadieCore
import RoadieTiler
@testable import RoadieDaemon

struct Spec078PlacementTests {
    private let display = powerDisplay()
    private var scope: StageScope { StageScope(displayID: display.id, desktopID: DesktopID(rawValue: 1), stageID: StageID(rawValue: "1")) }

    private func service(mode: WindowManagementMode, focused: WindowID, name: String) -> (SnapshotService, WindowSnapshot, WindowSnapshot) {
        let left = powerWindow(1, x: 0, y: 0, width: 500, height: 800)
        let right = powerWindow(2, x: 500, y: 0, width: 500, height: 800)
        let provider = PowerUserProvider(displays: [display], windows: [left, right])
        provider.focusedID = focused
        let store = StageStore(path: tempPath(name))
        store.save(PersistentStageState(scopes: [
            PersistentStageScope(displayID: display.id, stages: [
                PersistentStage(id: StageID(rawValue: "1"), mode: mode, focusedWindowID: focused, members: [left, right].map(treeMember),
                                bspTree: mode.usesTreeEngine ? .split(orientation: .vertical, ratio: 0.5, first: .leaf(left.id), second: .leaf(right.id)) : nil),
            ]),
        ], activeDisplayID: display.id))
        let service = SnapshotService(provider: provider, frameWriter: PowerUserWriter(provider: provider),
                                      config: RoadieConfig(tiling: TilingConfig(gapsOuter: 0, gapsInner: 0)),
                                      intentStore: LayoutIntentStore(path: tempPath(name + "-intents")), stageStore: store)
        return (service, left, right)
    }

    @Test func aPhantomCutsTheFocusedLeafLikeANewWindow() throws {
        let (service, left, right) = service(mode: .spatialBsp, focused: WindowID(rawValue: 2), name: "spec078-tree")
        let snapshot = service.snapshot(followFocus: false)
        let phantom = SnapshotService.previewPhantomID
        let placements = service.previewPlacements(scope: scope, incoming: phantom, in: snapshot)
        let ghost = try #require(placements[phantom])
        let leftFrame = try #require(placements[left.id])
        let rightFrame = try #require(placements[right.id])
        // La fenêtre active (à droite) est coupée en deux ; la gauche ne bouge pas.
        #expect(leftFrame == CGRect(x: 0, y: 0, width: 500, height: 800))
        #expect(rightFrame.minX >= 500 && ghost.minX >= 500)
        #expect(!rightFrame.intersects(ghost.insetBy(dx: 1, dy: 1)))
        // Les deux moitiés couvrent la feuille coupée, à une ligne d'un point près (arrondi de la coupe).
        #expect(abs(rightFrame.height * rightFrame.width + ghost.height * ghost.width - 500 * 800) <= 500)
    }

    @Test func otherEnginesMakeRoomToo() throws {
        let (service, left, right) = service(mode: .masterStack, focused: WindowID(rawValue: 1), name: "spec078-stack")
        let snapshot = service.snapshot(followFocus: false)
        let incoming = WindowID(rawValue: 9)
        let placements = service.previewPlacements(scope: scope, incoming: incoming, in: snapshot)
        #expect(Set(placements.keys) == [left.id, right.id, incoming])
        let frames = Array(placements.values)
        for (index, frame) in frames.enumerated() {
            #expect(CGRect(x: 0, y: 0, width: 1000, height: 800).contains(frame))
            for other in frames[(index + 1)...] { #expect(!frame.intersects(other.insetBy(dx: 1, dy: 1))) }
        }
    }
}

struct Spec078HoldTests {
    @Test func theHoldExpiresWithoutRenewal() {
        let hold = LayoutPreviewHold()
        let now = Date(timeIntervalSince1970: 1_000)
        #expect(!hold.isHeld(at: now))
        hold.hold(now: now)
        #expect(hold.isHeld(at: now.addingTimeInterval(1)))
        #expect(!hold.isHeld(at: now.addingTimeInterval(LayoutPreviewHold.lease + 0.1)))
        hold.hold(now: now)
        hold.release()
        #expect(!hold.isHeld(at: now))
    }
}

struct Spec078RequestTests {
    private let stage = StageScope(displayID: DisplayID(rawValue: "A"), desktopID: DesktopID(rawValue: 1), stageID: StageID(rawValue: "2"))
    private let firefox = LauncherApp(bundleID: "org.mozilla.firefox", path: "/Applications/Firefox.app", name: "Firefox", alternateNames: [])

    private func destination(_ kind: LauncherDestination.Kind) -> LauncherDestination { LauncherDestination(kind: kind, title: "x", detail: "") }

    @Test func onlyStageDestinationsOfPlacingVerbsArePreviewed() {
        let open = LauncherAction(subject: .app(firefox), verb: .openIn, destination: destination(.stage(stage)))
        #expect(LauncherPreviewRequest.of(open) == LauncherPreviewRequest(stage: stage, incoming: nil, appPath: firefox.path))
        let window = RoadieTarget(id: "window:7", kind: .window, title: "Firefox", source: .roadie,
                                  scope: TargetScopeSnapshot(displayId: "A", desktopId: 1, stageId: "1", windowId: 7), actions: [.focus])
        let send = LauncherAction(subject: .target(window), verb: .sendTo, destination: destination(.stage(stage)))
        #expect(LauncherPreviewRequest.of(send)?.incoming == WindowID(rawValue: 7))
        // Pas d'aperçu : nouvelle stage, bureau, verbe sans placement, stage d'origine de la fenêtre.
        #expect(LauncherPreviewRequest.of(LauncherAction(subject: .app(firefox), verb: .openIn,
                                                         destination: destination(.newStage(name: nil, stage.displayID, stage.desktopID)))) == nil)
        #expect(LauncherPreviewRequest.of(LauncherAction(subject: .target(window), verb: .sendTo,
                                                         destination: destination(.desktop(stage.displayID, DesktopID(rawValue: 2))))) == nil)
        #expect(LauncherPreviewRequest.of(LauncherAction(subject: .app(firefox), verb: .gatherIn, destination: destination(.stage(stage)))) == nil)
        let own = StageScope(displayID: DisplayID(rawValue: "A"), desktopID: DesktopID(rawValue: 1), stageID: StageID(rawValue: "1"))
        #expect(LauncherPreviewRequest.of(LauncherAction(subject: .target(window), verb: .sendTo, destination: destination(.stage(own)))) == nil)
    }
}
