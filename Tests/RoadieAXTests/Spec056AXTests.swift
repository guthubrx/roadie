import Foundation
import Testing
@testable import RoadieAX
import RoadieCore

@Suite
struct Spec056AXTests {
    @Test
    func statesWithoutRequestedWindowsAreEmpty() {
        #expect(WindowSwitcherWindowAccess.states(pid: getpid(), windowIDs: []).isEmpty)
    }

    @Test
    func unknownWindowIsNeverPerformed() {
        let missing = WindowID(rawValue: 4_000_000_000)

        #expect(WindowSwitcherWindowAccess.close(missing, pid: getpid()) != .performed)
        #expect(WindowSwitcherWindowAccess.minimize(missing, pid: getpid()) != .performed)
    }

    @Test
    func applicationActionsRefuseAMismatchedBundleIdentity() {
        let bundleID = "spec056.invalid.bundle"

        #expect(WindowSwitcherWindowAccess.hideApplication(pid: getpid(), bundleID: bundleID) == .targetMissing)
        #expect(WindowSwitcherWindowAccess.unhideApplication(pid: getpid(), bundleID: bundleID) == .targetMissing)
        #expect(WindowSwitcherWindowAccess.quitApplication(pid: getpid(), bundleID: bundleID) == .targetMissing)
    }

    @Test
    func axStateDefaultsToNoSpecialState() {
        let state = WindowSwitcherAXState()

        #expect(!state.isMinimized)
        #expect(!state.isFullscreen)
        #expect(!state.isHidden)
        #expect(state.title == nil)
    }
}
