import AppKit
import Foundation
import Testing
@testable import RoadieDaemon

/// Vue Texte des workflows (session 117).
struct Spec117TextViewTests {
    @Test func scriptJSONUpdatesTheTextAsAlfredDocuments() {
        var view = AlfredTextView(workflowID: "w", objectUID: "t", title: "Essai", folder: "/tmp")
        view.apply(.parse(#"{"response": "Question", "footer": "↩ Envoyer", "variables": {"chat": "1"}}"#))
        view.apply(.parse(#"{"response": "…", "behaviour": {"response": "append"}, "rerun": 0.01}"#))
        #expect(view.text == "Question\n\n…" && view.rerun == 0.1)
        view.apply(.parse(#"{"response": "Réponse", "behaviour": {"response": "replacelast", "scroll": "end", "inputfield": "select"}}"#))
        #expect(view.chunks == ["Question", "Réponse"] && view.footer == "↩ Envoyer" && view.variables == ["chat": "1"])
        #expect(view.scroll == .end && !view.clearsInput && view.rerun == nil)
        view.apply(.parse(#"{"response": "Titre", "behaviour": {"response": "prepend"}}"#))
        #expect(view.chunks.first == "Titre")
        // Une sortie qui n'est pas ce JSON devient le texte.
        view.apply(.parse("texte brut"))
        #expect(view.text == "texte brut")
        #expect(AlfredTextResponse.parse(#"{"response": "x", "actionoutput": true}"#).actionOutput)
    }

    @Test func markdownBlocksCoverHeadingsListsCodeAndImages() {
        let blocks = AlfredMarkdown.blocks("""
        # Titre
        Un **paragraphe**
        sur deux lignes

        - point
        2. second
        > cité
        ```
        let x = 1
        ```
        ![Capture](images/a.png)
        ---
        """)
        #expect(blocks == [.heading(level: 1, text: "Titre"), .paragraph("Un **paragraphe**\nsur deux lignes"), .bullet("point"),
                           .numbered("2", "second"), .quote("cité"), .code("let x = 1"), .image(alt: "Capture", path: "images/a.png"), .rule])
        #expect(AlfredMarkdown.imagePath("images/a.png", folder: "/wf") == "/wf/images/a.png")
        #expect(AlfredMarkdown.imagePath("/tmp/b.png", folder: "/wf") == "/tmp/b.png")
    }

    @MainActor @Test func inlineMarkdownBecomesBoldAndCode() {
        let font = NSFont.systemFont(ofSize: 14)
        let text = WorkflowMarkdownRenderer.inline("Un **mot** et `code`", font: font, style: NSParagraphStyle())
        #expect(text.string == "Un mot et code")
        let bold = text.attribute(.font, at: 3, effectiveRange: nil) as? NSFont
        #expect(bold.map { NSFontManager.shared.traits(of: $0).contains(.boldFontMask) } == true)
        let code = text.attribute(.font, at: 10, effectiveRange: nil) as? NSFont
        #expect(code?.isFixedPitch == true)
    }

    @Test func engineOpensTheViewFromAnArgumentAFileOrAScript() async throws {
        var fixture = WorkflowFixture()
        fixture.add("k", "input.keyword", ["keyword": "t", "argumenttype": 1])
        fixture.add("arg", "userinterface.text", ["inputtype": 0, "behaviour": 2, "footertext": "↩ Fermer", "fontmode": 2])
        fixture.add("file", "userinterface.text", ["inputtype": 2, "inputfile": "notes.md"])
        fixture.add("script", "userinterface.text", ["inputtype": 1, "inputfile": "reply", "scriptinput": 2, "loadingtext": "Patience"])
        let workflow = try fixture.write(files: ["notes.md": "# Notes", "reply": "#!/bin/sh\necho '{\"response\": \"ok\"}'"])
        let effects = RecordedEffects()
        let engine = AlfredWorkflowEngine(effects: effects)
        _ = await engine.start(workflow, at: "arg", arg: ["bonjour"])
        let shown = try #require(effects.lastText)
        #expect(shown.text == "bonjour" && shown.behaviour == .markdown && shown.footer == "↩ Fermer" && shown.monospaced)
        _ = await engine.start(workflow, at: "file", arg: [])
        #expect(effects.lastText?.text == "# Notes" && effects.lastText?.folder == workflow.folder.path)
        _ = await engine.start(workflow, at: "script", arg: ["question"])
        let script = try #require(effects.lastText)
        #expect(script.scriptFile == "reply" && script.initialInput == "question" && script.inputPlacement == .below)
        #expect(script.chunks.isEmpty && script.loadingText == "Patience")
        #expect(AlfredWorkflowEngine.supportedTypes.contains("userinterface.text"))
    }

    @Test func modifierBitsMatchAlfred() {
        #expect(WorkflowTextPanel.alfredModifiers([.command, .shift]) == 1_048_576 + 131_072)
        #expect(WorkflowTextPanel.alfredModifiers([]) == 0)
    }
}
