import AppKit
import Foundation
import Testing
import RoadieCore
@testable import RoadieDaemon

@MainActor
struct Spec085PickModifierTests {
    private func key(_ code: UInt16, _ text: String, _ flags: NSEvent.ModifierFlags) throws -> NSEvent {
        try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: 0,
                                      context: nil, characters: text, charactersIgnoringModifiers: text,
                                      isARepeat: false, keyCode: code))
    }

    @Test func theChosenModifierPicksARow() throws {
        // Code 19 : la touche « 2 » de la rangée du haut, quelle que soit la disposition.
        #expect(SearchInputPanel.navigation(try key(19, "2", .command))?.kind == .pick(2))
        #expect(SearchInputPanel.navigation(try key(19, "2", .shift)) == nil)
        let shift = LauncherPickModifier.shift.flags
        #expect(SearchInputPanel.navigation(try key(19, "2", .shift), pick: shift, text: "fi")?.kind == .pick(2))
        // Commande n'ouvre plus de ligne : elle reste aux autres raccourcis.
        #expect(SearchInputPanel.navigation(try key(19, "2", .command), pick: shift) == nil)
    }

    @Test func configKeepsAKnownModifierOrFallsBackToCommand() throws {
        #expect(TargetModeConfig().pickModifier == "command")
        #expect(TargetModeConfig(pickModifier: "shift").pickModifier == "shift")
        #expect(TargetModeConfig(pickModifier: "hyper").pickModifier == "command")
        let path = tempPath("spec085") + ".toml"
        try "[experimental.target_mode]\npick_modifier = \"alt\"\n".write(toFile: path, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: path) }
        let config = try RoadieConfigLoader.load(from: path)
        #expect(config.experimental.targetMode.pickModifier == "alt")
        #expect(LauncherPickModifier(config: "alt").symbol == "⌥")
        #expect(LauncherPickModifier(config: "?") == .command)
    }
}
