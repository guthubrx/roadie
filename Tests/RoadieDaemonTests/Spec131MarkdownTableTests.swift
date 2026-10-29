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

    @MainActor @Test func tableIsRenderedAsATextTable() {
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
    }
}
