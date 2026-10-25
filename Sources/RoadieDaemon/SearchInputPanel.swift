import AppKit

/// Le texte appartient à AppKit : caret, sélection, composition et édition ne sont pas simulés.
/// Le panneau non activant prend le clavier sans activer Roadie ni modifier l'application ciblée.
@MainActor
final class SearchInputPanel: NSPanel, NSTextFieldDelegate, NSWindowDelegate {
    let field = NSTextField()
    var onChange: ((String) -> Void)?
    var onKey: ((SearchKeyInput) -> Void)?
    var onCancel: (() -> Void)?
    /// Étiquettes affichées (recherche non vide) : Maj + lettre choisit une étiquette au lieu d'écrire
    /// une majuscule. Faux en mode commande, où les majuscules sont du texte (`/stage rename Perso`).
    var labelsEnabled = false
    private var updating = false
    private var closing = false

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isReleasedWhenClosed = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
        level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        delegate = self
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.isEditable = true
        field.isSelectable = true
        field.textColor = NSColor(calibratedWhite: 0.94, alpha: 1)
        field.placeholderString = "Rechercher ou saisir /commande"
        field.cell?.usesSingleLineMode = true
        field.cell?.isScrollable = true
        field.delegate = self
        field.setAccessibilityIdentifier("RoadieCommandInput")
        field.setAccessibilityLabel("Rechercher ou saisir une commande")
        contentView?.addSubview(field)
    }

    /// O(l) seulement si le contenu change ; un rafraîchissement des cibles garde la sélection.
    func update(text: String, frame: CGRect, font: NSFont) {
        if self.frame != frame { setFrame(frame, display: true) }
        field.font = font
        let height = min(frame.height, field.fittingSize.height)
        field.frame = CGRect(x: 0, y: (frame.height - height) / 2, width: frame.width, height: height)
        guard field.stringValue != text else { return }
        updating = true
        defer { updating = false }
        if let editor = field.currentEditor() as? NSTextView, !editor.hasMarkedText() {
            editor.insertText(text, replacementRange: NSRange(location: 0, length: (editor.string as NSString).length))
        } else {
            field.stringValue = text
        }
    }

    func beginEditing() {
        makeKeyAndOrderFront(nil)
        makeFirstResponder(field)
        if let editor = field.currentEditor() as? NSTextView {
            editor.allowsUndo = true
            editor.insertionPointColor = .white
            editor.setSelectedRange(NSRange(location: (editor.string as NSString).length, length: 0))
        }
    }

    func endEditing() {
        closing = true
        onChange = nil
        onKey = nil
        onCancel = nil
        orderOut(nil)
        close()
    }

    func controlTextDidChange(_ notification: Notification) {
        guard !updating, !closing else { return }
        onChange?(field.stringValue)
    }

    func windowDidResignKey(_ notification: Notification) {
        guard !closing else { return }
        onCancel?()
    }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown,
           (field.currentEditor() as? NSTextView)?.hasMarkedText() != true,
           let input = Self.navigation(event, labels: labelsEnabled) {
            onKey?(input)
            return
        }
        super.sendEvent(event)
    }

    /// Les menus Édition ne sont pas installés dans le daemon. Cibler exclusivement cet éditeur.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection([.command, .control, .option, .shift])
        guard flags == .command || flags == [.command, .shift],
              let editor = field.currentEditor() as? NSTextView,
              let key = event.charactersIgnoringModifiers?.lowercased() else {
            return super.performKeyEquivalent(with: event)
        }
        if key == "z" {
            if flags.contains(.shift) {
                if editor.undoManager?.canRedo == true { editor.undoManager?.redo() }
            } else if editor.undoManager?.canUndo == true { editor.undoManager?.undo() }
            return true
        }
        guard flags == .command else { return super.performKeyEquivalent(with: event) }
        if key == "w" { onCancel?(); return true }
        let action: Selector? = switch key {
        case "a": #selector(NSText.selectAll(_:))
        case "c": #selector(NSText.copy(_:))
        case "x": #selector(NSText.cut(_:))
        case "v": #selector(NSText.paste(_:))
        default: nil
        }
        if let action { return NSApp.sendAction(action, to: editor, from: self) }
        return super.performKeyEquivalent(with: event)
    }

    /// O(1). Les modificateurs de déplacement/sélection restent à AppKit.
    static func navigation(_ event: NSEvent, labels: Bool = false) -> SearchKeyInput? {
        let flags = event.modifierFlags.intersection([.command, .control, .option, .shift])
        if labels, flags == .shift, let letter = event.charactersIgnoringModifiers?.lowercased(),
           letter.count == 1, letter.first?.isLetter == true {
            return SearchKeyInput(kind: .labelCharacter(letter))
        }
        switch event.keyCode {
        case 53: return SearchKeyInput(kind: .escape)
        case 36, 76:
            return SearchKeyInput(kind: .confirm(shift: flags.contains(.shift), command: flags.contains(.command), isRepeat: event.isARepeat))
        case 48 where flags.isEmpty || flags == .shift:
            return SearchKeyInput(kind: flags.contains(.shift) ? .previous : .next, navigationSource: .tab)
        case 125 where flags.isEmpty: return SearchKeyInput(kind: .next, navigationSource: .arrow)
        case 126 where flags.isEmpty: return SearchKeyInput(kind: .previous, navigationSource: .arrow)
        default: break
        }
        if flags == .control {
            switch event.charactersIgnoringModifiers?.lowercased() {
            case "n": return SearchKeyInput(kind: .next, navigationSource: .control)
            case "p": return SearchKeyInput(kind: .previous, navigationSource: .control)
            default: break
            }
        }
        return nil
    }
}
