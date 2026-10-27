import AppKit
import Testing
@testable import RoadieDaemon

/// Session 100 : une touche morte (⌥N pour ~ en AZERTY, ^ puis e) survit aux rendus de la barre.
@Suite(.serialized)
@MainActor
struct Spec100DeadKeyTests {
    private func panel() throws -> (SearchInputPanel, NSTextView) {
        _ = NSApplication.shared
        let panel = SearchInputPanel()
        panel.update(text: "", frame: CGRect(x: 300, y: 100, width: 560, height: 28), font: .systemFont(ofSize: 15))
        panel.beginEditing()
        return (panel, try #require(panel.field.currentEditor() as? NSTextView))
    }

    @Test
    func renderDuringCompositionKeepsTheMarkedTildeAndTheModelGetsTheCommittedOne() throws {
        let (panel, editor) = try panel()
        defer { panel.endEditing() }
        var seen: [String] = []
        panel.onChange = { seen.append($0) }
        editor.setMarkedText("˜", selectedRange: NSRange(location: 1, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        // ⌥ relâchée : la barre se redessine avec l'ancienne saisie du modèle.
        panel.update(text: "", frame: panel.frame, font: .systemFont(ofSize: 15))
        #expect(editor.hasMarkedText())
        #expect(editor.string == "˜")
        editor.insertText("~", replacementRange: NSRange(location: NSNotFound, length: 0))
        #expect(editor.string == "~")
        #expect(seen.last == "~")
        // Après validation, le modèle reprend la main sur le texte (complétion ~/).
        panel.update(text: "~/", frame: panel.frame, font: .systemFont(ofSize: 15))
        #expect(editor.string == "~/")
    }

    @Test
    func circumflexCompositionAfterExistingTextIsKept() throws {
        let (panel, editor) = try panel()
        defer { panel.endEditing() }
        panel.update(text: "f", frame: panel.frame, font: .systemFont(ofSize: 15))
        editor.setMarkedText("^", selectedRange: NSRange(location: 1, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        panel.update(text: "f", frame: panel.frame, font: .systemFont(ofSize: 15))
        editor.insertText("ê", replacementRange: NSRange(location: NSNotFound, length: 0))
        #expect(editor.string == "fê")
    }
}
