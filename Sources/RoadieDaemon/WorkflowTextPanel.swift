import AppKit
import Foundation

/// Fenêtre de la vue Texte d'un workflow (session 117). Panneau qui n'active pas Roadie, comme les Paramètres,
/// mais reçoit le clavier. Échap ferme ; Retour (avec ou sans touche tenue) envoie le texte à la suite du schéma ;
/// dans le champ de saisie, Retour seul relance le script avec le texte tapé.
@MainActor
final class WorkflowTextPanel: NSObject, NSTextViewDelegate, NSWindowDelegate {
    /// Script de la vue : saisie → réponse, ou message d'échec.
    typealias RunScript = @MainActor (_ input: String, _ variables: [String: String], _ done: @escaping @MainActor (AlfredTextResponse?, String?) -> Void) -> Void
    /// Suite du schéma : texte, bits des touches tenues (Alfred), variables.
    typealias Proceed = @MainActor (_ text: String, _ modifiers: Int, _ variables: [String: String]) -> Void

    private static var current: WorkflowTextPanel?

    private var view: AlfredTextView
    private let runScript: RunScript?
    private let proceed: Proceed
    /// Une flèche sans touche part de la brique : Retour seul l'emprunte, même dans un texte modifiable.
    private let plainContinues: Bool
    private let panel: NSPanel
    private let textView = NSTextView()
    private let scroll = NSScrollView()
    private let input = NSTextField()
    private let footer = NSTextField(labelWithString: "")
    private var monitor: Any?
    private var lastInput = ""
    private var generation = 0

    static func show(_ view: AlfredTextView, plainContinues: Bool, runScript: RunScript?, proceed: @escaping Proceed) {
        current?.close()
        let controller = WorkflowTextPanel(view: view, plainContinues: plainContinues, runScript: runScript, proceed: proceed)
        current = controller
        controller.present()
    }

    private init(view: AlfredTextView, plainContinues: Bool, runScript: RunScript?, proceed: @escaping Proceed) {
        self.view = view
        self.plainContinues = plainContinues
        self.runScript = runScript
        self.proceed = proceed
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 760, height: 540),
                        styleMask: [.titled, .closable, .resizable, .nonactivatingPanel, .utilityWindow], backing: .buffered, defer: false)
        super.init()
    }

    private func present() {
        panel.title = view.title
        panel.level = .floating
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.delegate = self
        panel.minSize = NSSize(width: 360, height: 220)
        layout()
        render()
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        if let area = screen?.visibleFrame {
            panel.setFrameOrigin(NSPoint(x: area.midX - panel.frame.width / 2, y: area.midY - panel.frame.height / 2))
        }
        panel.orderFrontRegardless()
        panel.makeKey()
        panel.makeFirstResponder(view.inputPlacement == .none ? textView : input)
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.window === self.panel else { return event }
            return self.handle(event) ? nil : event
        }
        if view.scriptFile != nil { run(view.initialInput ?? "") }
    }

    private func layout() {
        textView.isRichText = true
        textView.isEditable = view.behaviour == .editable
        textView.isSelectable = true
        textView.allowsUndo = view.behaviour == .editable
        textView.isContinuousSpellCheckingEnabled = false
        textView.textContainerInset = NSSize(width: 14, height: 12)
        textView.drawsBackground = false
        textView.delegate = self
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        scroll.documentView = textView
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        input.placeholderString = "Saisie"
        input.font = .systemFont(ofSize: 14)
        input.target = self
        input.action = #selector(inputReturned)
        footer.font = .systemFont(ofSize: 11)
        footer.textColor = .secondaryLabelColor
        footer.lineBreakMode = .byTruncatingTail
        var rows: [NSView] = []
        if view.inputPlacement == .above { rows.append(input) }
        rows.append(scroll)
        if view.inputPlacement == .below { rows.append(input) }
        rows.append(footer)
        let stack = NSStackView(views: rows)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)
        rows.forEach { $0.translatesAutoresizingMaskIntoConstraints = false }
        stack.translatesAutoresizingMaskIntoConstraints = false
        let content = NSVisualEffectView()
        content.material = .popover
        content.state = .active
        content.addSubview(stack)
        panel.contentView = content
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor), stack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            stack.topAnchor.constraint(equalTo: content.topAnchor), stack.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            scroll.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -20),
            input.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -20),
            footer.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -20),
        ])
        scroll.setContentHuggingPriority(.defaultLow, for: .vertical)
    }

    /// Texte, pied et défilement d'après la vue. O(n).
    private func render() {
        let font: NSFont = view.monospaced ? .monospacedSystemFont(ofSize: 13, weight: .regular) : .systemFont(ofSize: 14)
        let body = view.chunks.isEmpty ? (view.loadingText ?? "") : view.text
        let attributed = view.behaviour == .markdown
            ? WorkflowMarkdownRenderer.render(body, folder: view.folder, font: font, width: max(200, panel.frame.width - 60))
            : NSAttributedString(string: body, attributes: [.font: font, .foregroundColor: NSColor.labelColor])
        textView.textStorage?.setAttributedString(attributed)
        footer.stringValue = view.chunks.isEmpty || view.loadingText == nil ? view.footer : "\(view.loadingText ?? "") · \(view.footer)"
        footer.isHidden = footer.stringValue.isEmpty
        switch view.scroll {
        case .start: textView.scrollToBeginningOfDocument(nil)
        case .end, .auto: textView.scrollToEndOfDocument(nil)
        }
    }

    /// Lance le script avec cette saisie ; une réponse arrivée après une nouvelle saisie est ignorée. O(1).
    private func run(_ text: String) {
        guard let runScript else { return }
        generation += 1
        let mine = generation
        lastInput = text
        if view.chunks.isEmpty { render() }
        runScript(text, view.variables) { [weak self] response, failure in
            guard let self, self.generation == mine, self.panel.isVisible else { return }
            guard let response else {
                self.view.loadingText = nil
                self.view.footer = "Script : \(failure ?? "réponse illisible")"
                self.render()
                return
            }
            self.view.apply(response)
            if response.actionOutput {
                let text = response.response, variables = self.view.variables
                self.close()
                self.proceed(text, 0, variables)
                return
            }
            self.render()
            if let delay = response.rerun {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                    MainActor.assumeIsolated {
                        guard let self, self.generation == mine else { return }
                        self.run(self.lastInput)
                    }
                }
            }
        }
    }

    @objc private func inputReturned() {
        let modifiers = Self.alfredModifiers(NSApp.currentEvent?.modifierFlags ?? [])
        guard modifiers == 0, runScript != nil else { send(modifiers); return }
        let text = input.stringValue
        if view.clearsInput { input.stringValue = "" } else { input.selectText(nil) }
        run(text)
    }

    /// Échap ferme ; Retour hors du champ de saisie envoie le texte (Retour seul dans un texte modifiable sans
    /// flèche sans touche : nouvelle ligne). Vrai si la touche est prise. O(1).
    private func handle(_ event: NSEvent) -> Bool {
        if event.keyCode == 53 { close(); return true }
        guard event.keyCode == 36 || event.keyCode == 76, panel.firstResponder === textView else { return false }
        let modifiers = Self.alfredModifiers(event.modifierFlags)
        if view.behaviour == .editable, modifiers == 0 ? !plainContinues : (modifiers == 131_072 || modifiers == 524_288) {
            return false
        }
        send(modifiers)
        return true
    }

    private func send(_ modifiers: Int) {
        let text = textView.string, variables = view.variables
        close()
        proceed(text, modifiers, variables)
    }

    /// Bits d'Alfred : ⌘ 1048576, ⌥ 524288, ⌃ 262144, ⇧ 131072, fn 8388608. O(1).
    nonisolated static func alfredModifiers(_ flags: NSEvent.ModifierFlags) -> Int {
        (flags.contains(.command) ? 1_048_576 : 0) + (flags.contains(.option) ? 524_288 : 0)
            + (flags.contains(.control) ? 262_144 : 0) + (flags.contains(.shift) ? 131_072 : 0)
            + (flags.contains(.function) ? 8_388_608 : 0)
    }

    func windowWillClose(_ notification: Notification) { teardown() }

    private func close() {
        teardown()
        panel.orderOut(nil)
    }

    private func teardown() {
        generation += 1
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        if Self.current === self { Self.current = nil }
    }
}

/// Markdown en texte mis en forme pour AppKit : blocs d'`AlfredMarkdown`, gras, italique, code et liens dans
/// les lignes par `AttributedString`, images en pièces jointes réduites à la largeur. O(n).
@MainActor
enum WorkflowMarkdownRenderer {
    static func render(_ markdown: String, folder: String, font: NSFont, width: CGFloat) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let body: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.labelColor]
        func paragraph(spacing: CGFloat = 8, indent: CGFloat = 0) -> NSParagraphStyle {
            let style = NSMutableParagraphStyle()
            style.paragraphSpacing = spacing
            style.headIndent = indent
            style.firstLineHeadIndent = indent
            return style
        }
        for block in AlfredMarkdown.blocks(markdown) {
            if result.length > 0 { result.append(NSAttributedString(string: "\n", attributes: body)) }
            switch block {
            case .heading(let level, let text):
                let size = font.pointSize + CGFloat(max(0, 4 - level) * 3) + 2
                result.append(inline(text, font: NSFont.boldSystemFont(ofSize: size), style: paragraph(spacing: 10)))
            case .paragraph(let text):
                result.append(inline(text, font: font, style: paragraph()))
            case .quote(let text):
                let line = inline(text, font: NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask), style: paragraph(indent: 16))
                let quoted = NSMutableAttributedString(attributedString: line)
                quoted.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: NSRange(location: 0, length: quoted.length))
                result.append(quoted)
            case .bullet(let text):
                result.append(inline("•  " + text, font: font, style: paragraph(spacing: 4, indent: 8)))
            case .numbered(let number, let text):
                result.append(inline("\(number).  " + text, font: font, style: paragraph(spacing: 4, indent: 8)))
            case .code(let code):
                result.append(NSAttributedString(string: code, attributes: [
                    .font: NSFont.monospacedSystemFont(ofSize: font.pointSize - 1, weight: .regular),
                    .foregroundColor: NSColor.labelColor, .backgroundColor: NSColor.quaternaryLabelColor, .paragraphStyle: paragraph()]))
            case .image(let alt, let raw):
                let path = AlfredMarkdown.imagePath(raw, folder: folder)
                guard let image = NSImage(contentsOfFile: path), image.size.width > 0 else {
                    result.append(NSAttributedString(string: alt.isEmpty ? raw : alt, attributes: body))
                    continue
                }
                let scale = min(1, (width - 20) / image.size.width)
                let attachment = NSTextAttachment()
                attachment.image = image
                attachment.bounds = CGRect(x: 0, y: 0, width: image.size.width * scale, height: image.size.height * scale)
                result.append(NSAttributedString(attachment: attachment))
            case .rule:
                result.append(NSAttributedString(string: String(repeating: "─", count: 40),
                                                 attributes: [.font: font, .foregroundColor: NSColor.separatorColor]))
            }
        }
        return result
    }

    /// Mise en forme dans une ligne : `**gras**`, `*italique*`, `` `code` ``, liens. O(n).
    static func inline(_ text: String, font: NSFont, style: NSParagraphStyle) -> NSAttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        guard let parsed = try? AttributedString(markdown: text, options: options) else {
            return NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: NSColor.labelColor, .paragraphStyle: style])
        }
        let result = NSMutableAttributedString()
        let fonts = NSFontManager.shared
        for run in parsed.runs {
            var runFont = font
            let intent = run.inlinePresentationIntent ?? []
            if intent.contains(.stronglyEmphasized) { runFont = fonts.convert(runFont, toHaveTrait: .boldFontMask) }
            if intent.contains(.emphasized) { runFont = fonts.convert(runFont, toHaveTrait: .italicFontMask) }
            if intent.contains(.code) { runFont = .monospacedSystemFont(ofSize: font.pointSize - 1, weight: .regular) }
            var attributes: [NSAttributedString.Key: Any] = [.font: runFont, .foregroundColor: NSColor.labelColor, .paragraphStyle: style]
            if intent.contains(.strikethrough) { attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
            if let link = run.link { attributes[.link] = link }
            result.append(NSAttributedString(string: String(parsed[run.range].characters), attributes: attributes))
        }
        return result
    }
}
