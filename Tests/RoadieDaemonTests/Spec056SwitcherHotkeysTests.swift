import Carbon
import CoreGraphics
import Testing
@testable import RoadieDaemon

struct Spec056SwitcherHotkeysTests {
    @Test func parseReadsModifiersAndNamedKey() {
        let hotkey = WindowSwitcherHotkey.parse("ctrl+alt+tab", layout: [:])
        #expect(hotkey?.keyCode == 48)
        #expect(hotkey?.modifiers == [.control, .option])
    }

    @Test func parseAcceptsModifierAliases() {
        #expect(WindowSwitcherHotkey.parse("control+opt+tab", layout: [:])?.modifiers == [.control, .option])
        #expect(WindowSwitcherHotkey.parse("cmd+shift+tab", layout: [:])?.modifiers == [.command, .shift])
    }

    @Test(arguments: ["tab", "", "hyper+tab", "ctrl+zzzz", "ctrl+"])
    func parseRefusesBareKeysUnknownModifiersAndUnknownKeys(text: String) {
        #expect(WindowSwitcherHotkey.parse(text, layout: [:]) == nil)
    }

    @Test func releaseTriggersWhenAnyRequiredModifierIsUp() {
        let required: Set<WindowSwitcherModifier> = [.control, .option]
        #expect(!WindowSwitcherHotkey.isReleased(required: required, held: [.control, .option]))
        #expect(!WindowSwitcherHotkey.isReleased(required: required, held: [.control, .option, .shift]))
        #expect(WindowSwitcherHotkey.isReleased(required: required, held: [.control]))
        #expect(WindowSwitcherHotkey.isReleased(required: required, held: []))
    }

    @Test func heldReadsCoreGraphicsFlags() {
        let flags: CGEventFlags = [.maskControl, .maskAlternate]
        #expect(WindowSwitcherHotkey.held(in: flags) == [.control, .option])
    }

    @Test func carbonMaskCombinesModifiers() {
        #expect(WindowSwitcherHotkey.carbonModifiers([.control, .option]) == UInt32(controlKey | optionKey))
    }

    @Test func planAddsShiftVariantForBackwardCycling() {
        let plan = WindowSwitcherHotkeyPlan(
            requests: [WindowSwitcherHotkeyRequest(profileID: "all", hotkey: "ctrl+alt+tab")],
            layout: [:]
        )
        #expect(plan.entries.map(\.backwards) == [false, true])
        #expect(plan.entries[1].hotkey.modifiers == [.control, .option, .shift])
        #expect(plan.issues.isEmpty)
    }

    @Test func planDoesNotAddShiftVariantWhenShiftIsAlreadyRequired() {
        let plan = WindowSwitcherHotkeyPlan(
            requests: [WindowSwitcherHotkeyRequest(profileID: "fenetres", hotkey: "ctrl+alt+shift+tab")],
            layout: [:]
        )
        #expect(plan.entries.map(\.backwards) == [false])
    }

    @Test func planReportsInvalidProfileWithoutRegisteringIt() {
        let plan = WindowSwitcherHotkeyPlan(
            requests: [WindowSwitcherHotkeyRequest(profileID: "casse", hotkey: "tab")],
            layout: [:]
        )
        #expect(plan.entries.isEmpty)
        #expect(plan.issues == ["invalide:casse"])
    }

    @Test func planKeepsFirstOwnerOnCollisionAndReportsIt() {
        let plan = WindowSwitcherHotkeyPlan(
            requests: [
                WindowSwitcherHotkeyRequest(profileID: "all", hotkey: "ctrl+alt+tab"),
                WindowSwitcherHotkeyRequest(profileID: "stage", hotkey: "ctrl+alt+tab"),
            ],
            layout: [:]
        )
        #expect(plan.entries.map(\.profileID) == ["all", "all"])
        #expect(plan.issues == ["collision:stage:all", "collision:stage:all"])
    }
}
