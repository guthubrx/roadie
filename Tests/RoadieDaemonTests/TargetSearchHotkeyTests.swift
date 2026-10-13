import Carbon
import Testing
import RoadieCore
import RoadieDaemon

@Suite
struct TargetSearchHotkeyTests {
    @Test
    func modifiersMapToCarbonFlags() {
        let flags = TargetSearchHotkey.carbonModifiers(["command", "control", "alt"])
        #expect(flags == UInt32(cmdKey | controlKey | optionKey))
        #expect(TargetSearchHotkey.carbonModifiers(["shift"]) == UInt32(shiftKey))
    }

    @Test
    func namedKeysResolveWithoutTheKeyboardLayout() {
        #expect(TargetSearchHotkey.namedKeyCode("space") == 49)
        #expect(TargetSearchHotkey.namedKeyCode("return") == 36)
        #expect(TargetSearchHotkey.namedKeyCode("f1") == 122)
        #expect(TargetSearchHotkey.namedKeyCode("f12") == 111)
        #expect(TargetSearchHotkey.namedKeyCode("f") == nil)
    }

    @Test
    func characterKeysResolveThroughTheLayoutTable() {
        // Table AZERTY partielle : « f » est le code 3, « a » le code 12.
        let layout: [UInt32: String] = [3: "f", 12: "a", 0: "q"]
        #expect(TargetSearchHotkey.keyCode(for: "F", in: layout) == 3)
        #expect(TargetSearchHotkey.keyCode(for: "a", in: layout) == 12)
        #expect(TargetSearchHotkey.keyCode(for: "z", in: layout) == nil)
    }

    @Test
    func emptyOrInvalidHotkeysAreNotResolved() {
        let layout: [UInt32: String] = [3: "f"]
        #expect(TargetSearchHotkey.resolve("", layout: layout) == nil)
        #expect(TargetSearchHotkey.resolve("f", layout: layout) == nil)
        let resolved = TargetSearchHotkey.resolve("command+control+alt+f", layout: layout)
        #expect(resolved?.keyCode == 3)
        #expect(resolved?.modifiers == UInt32(cmdKey | controlKey | optionKey))
    }
}
