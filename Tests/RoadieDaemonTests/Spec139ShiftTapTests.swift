import Testing
@testable import RoadieDaemon

/// Session 139 : Maj seule recule d'une carte dans ⌘Tab et ⌥Tab, comme dans AltTab, sans doubler Maj + Tab.
struct Spec139ShiftTapTests {
    /// Suite d'états de Maj (et de pas notés) ; rend les relâchements qui reculent.
    private func run(_ tap: inout SwitcherShiftTap, _ events: [String]) -> [Bool] {
        events.map { event in
            if event == "pas" { tap.noteStep(); return false }
            return tap.update(shift: event == "maj")
        }
    }

    @Test func shiftAloneStepsBackOnRelease() {
        var tap = SwitcherShiftTap()
        #expect(run(&tap, ["rien", "maj", "rien", "rien"]) == [false, false, true, false])
    }

    @Test func shiftTabStepsOnlyOnce() {
        var tap = SwitcherShiftTap()
        // Maj + Tab : le pas de Tab suffit ; un pas sans Maj ne compte pas pour le Maj suivant.
        #expect(run(&tap, ["maj", "pas", "rien", "pas", "maj", "rien"]) == [false, false, false, false, false, true])
    }

    @Test func shiftHeldAtOpeningIsTheOpeningStep() {
        var tap = SwitcherShiftTap(initiallyDown: true)
        #expect(run(&tap, ["maj", "rien", "maj", "rien"]) == [false, false, false, true])
    }
}
