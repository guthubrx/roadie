import AppKit
import Testing
@testable import RoadieDaemon

/// Session 131 : tableaux Markdown dans la vue Texte, comme l'annonce Alfred 6.
struct Spec131MarkdownTableTests {
    @Test func tablesAreParsedWithAlignments() {
        let text = "Titre\n\n| Ville | Heure | Écart |\n|:------|:-----:|------:|\n| Tokyo | 03:00 | +8 |\n| Lima \\| Pérou | 13:00 |\n\nFin"
        let blocks = AlfredMarkdown.blocks(text)
        #expect(blocks.count == 3)
        #expect(blocks[1] == .table(header: ["Ville", "Heure", "Écart"], alignments: [.left, .center, .right],
                                    rows: [["Tokyo", "03:00", "+8"], ["Lima | Pérou", "13:00", ""]]))
        #expect(blocks[2] == .paragraph("Fin"))
    }

    @Test func barsWithoutSeparatorStayParagraphsAndRulesStayRules() {
        #expect(AlfredMarkdown.blocks("a | b\nc | d") == [.paragraph("a | b\nc | d")])
        #expect(AlfredMarkdown.blocks("---") == [.rule])
        #expect(AlfredMarkdown.separator("|---|:-:|") == [.left, .center])
        #expect(AlfredMarkdown.separator("| a | b |") == nil)
        // Code : les barres n'y font pas de tableau.
        #expect(AlfredMarkdown.blocks("```\n| a |\n|---|\n```") == [.code("| a |\n|---|")])
    }

    @MainActor @Test func tableIsRenderedAsATextTable() throws {
        let rendered = WorkflowMarkdownRenderer.render("| A | B |\n|---|--:|\n| 1 | 2 |", folder: "/", font: .systemFont(ofSize: 13), width: 400)
        var blocks = 0
        var rightAligned = false
        rendered.enumerateAttribute(.paragraphStyle, in: NSRange(location: 0, length: rendered.length)) { value, _, _ in
            guard let style = value as? NSParagraphStyle, !style.textBlocks.isEmpty else { return }
            blocks += 1
            if style.alignment == .right { rightAligned = true }
        }
        #expect(blocks >= 4 && rightAligned)
        #expect(rendered.string.contains("A") && rendered.string.contains("2"))
        // Mise en page réelle (TextKit 1, comme la vue Texte) : les cellules d'une ligne sont côte à côte.
        let view = NSTextView(usingTextLayoutManager: false)
        view.frame = NSRect(x: 0, y: 0, width: 400, height: 200)
        view.textStorage?.setAttributedString(rendered)
        let layout = try #require(view.layoutManager), container = try #require(view.textContainer)
        layout.ensureLayout(for: container)
        func frame(_ text: String) -> NSRect {
            let range = (rendered.string as NSString).range(of: text)
            return layout.boundingRect(forGlyphRange: layout.glyphRange(forCharacterRange: range, actualCharacterRange: nil), in: container)
        }
        #expect(abs(frame("A").midY - frame("B").midY) < 2 && frame("B").minX > frame("A").maxX)
        #expect(frame("1").minY > frame("A").maxY - 1)
    }

    /// Vue Texte sans champ de saisie (comme la première fiche « Informations ») : la mise en page levait une
    /// exception AppKit qui faisait planter Roadie. Chaque placement du champ doit s'ouvrir.
    @MainActor @Test func textPanelOpensWithEveryInputPlacement() throws {
        for placement in [AlfredTextView.InputPlacement.none, .above, .below] {
            var view = AlfredTextView(workflowID: "spec131.panel", objectUID: "view", title: "spec131-\(placement.rawValue)", folder: "/")
            view.behaviour = .markdown
            view.inputPlacement = placement
            view.chunks = ["# Fiche\n\n| | |\n|---|---|\n| Taille | `1 o` |"]
            WorkflowTextPanel.show(view, plainContinues: false, runScript: nil) { _, _, _ in }
            let panel = try #require(NSApp.windows.first { $0.title == view.title })
            #expect(panel.isVisible)
            panel.close()
        }
    }
}
