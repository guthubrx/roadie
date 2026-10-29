import AppKit
import RoadieCore

/// Le texte appartient à AppKit : caret, sélection, composition et édition ne sont pas simulés.
/// Le panneau non activant prend le clavier sans activer Roadie ni modifier l'application ciblée.
@MainActor
final class SearchInputPanel: NSPanel, NSTextFieldDelegate, NSWindowDelegate {
    let field = NSTextField()
    var onChange: ((String) -> Void)?
    var onKey: ((SearchKeyInput) -> Void)?
    var onCancel: (() -> Void)?
    /// Touches modificatrices tenues : la ligne choisie annonce la variante de Retour (SPEC-075).
    var onFlags: ((NSEvent.ModifierFlags) -> Void)?
    /// Lettres affichées dans les pastilles (SPEC-084) : Maj + l'une d'elles choisit sa ligne ; toute autre
    /// majuscule reste du texte. Vide en mode commande (`/stage rename Perso`) et barre vide.
    var labelLetters: Set<String> = []
    /// Touche tenue avec un chiffre pour ouvrir une ligne (SPEC-085).
    var pickModifier: NSEvent.ModifierFlags = .command
    /// Quand ⌥ + flèches servent à la sélection multiple (SPEC-091) ; sinon elles déplacent le curseur.
    var selectionKeys = SelectionKeys()
    /// Grille d'un workflow (SPEC-092) : ← → changent de tuile au lieu de déplacer le curseur.
    var gridColumns: Int?
    /// Touche des présentations (session 099) : code physique et modificateurs ; nil : désactivée.
    var viewCycle: (keyCode: UInt16, flags: NSEvent.ModifierFlags)?
    /// Saisie d'un chemin de dossier (session 105) : ⌫ en fin de `…/` remonte d'un dossier.
    var pathNavigation = false
    /// Touches réglables de la barre (session 108) : combinaison physique → action de `LauncherBarKeys`.
    var barKeys: [BarKeyCombo: String] = SearchInputPanel.barKeyTable(LauncherBarKeys.resolved([:]), layout: TargetSearchHotkey.currentLayoutTable())
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
        field.placeholderString = tr("Rechercher ou saisir /commande", "Search or type /command")
        field.cell?.usesSingleLineMode = true
        field.cell?.isScrollable = true
        field.delegate = self
        field.setAccessibilityIdentifier("RoadieCommandInput")
        field.setAccessibilityLabel(tr("Rechercher ou saisir une commande", "Search or type a command"))
        contentView?.addSubview(field)
    }

    /// O(l) seulement si le contenu change ; un rafraîchissement des cibles garde la sélection.
    /// `color` : texte et curseur du thème de la barre (session 101) ; nil garde la couleur actuelle.
    func update(text: String, frame: CGRect, font: NSFont, color: NSColor? = nil) {
        if self.frame != frame { setFrame(frame, display: true) }
        field.font = font
        if let color, field.textColor != color {
            field.textColor = color
            (field.currentEditor() as? NSTextView)?.insertionPointColor = color
        }
        let height = min(frame.height, field.fittingSize.height)
        field.frame = CGRect(x: 0, y: (frame.height - height) / 2, width: frame.width, height: height)
        guard field.stringValue != text else { return }
        // Composition en cours (touche morte : ⌥N pour ~, ^ puis e) : le texte marqué n'est pas encore
        // transmis au modèle, qui garde l'ancienne saisie. Un rendu (⌥ relâchée, rafraîchissement) l'effacerait :
        // AppKit garde la main, le modèle reçoit le texte validé (session 100).
        if (field.currentEditor() as? NSTextView)?.hasMarkedText() == true { return }
        updating = true
        defer { updating = false }
        if let editor = field.currentEditor() as? NSTextView {
            editor.insertText(text, replacementRange: NSRange(location: 0, length: (editor.string as NSString).length))
        } else {
            field.stringValue = text
        }
    }

    /// Saisie reprise (SPEC-090) : tout le texte est sélectionné, la frappe le remplace.
    func selectAllText() {
        (field.currentEditor() as? NSTextView)?.selectAll(nil)
    }

    func beginEditing() {
        makeKeyAndOrderFront(nil)
        makeFirstResponder(field)
        if let editor = field.currentEditor() as? NSTextView {
            editor.allowsUndo = true
            editor.insertionPointColor = field.textColor ?? .white
            editor.setSelectedRange(NSRange(location: (editor.string as NSString).length, length: 0))
        }
    }

    func endEditing() {
        closing = true
        onChange = nil
        onKey = nil
        onCancel = nil
        onFlags = nil
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
        if event.type == .flagsChanged { onFlags?(event.modifierFlags) }
        // → en fin de saisie : les verbes de la ligne choisie, comme Tab (SPEC-075). Ailleurs, le curseur.
        if event.type == .keyDown, event.keyCode == 124, gridColumns == nil, !field.stringValue.isEmpty,
           event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty,
           let editor = field.currentEditor() as? NSTextView, !editor.hasMarkedText(),
           editor.selectedRange() == NSRange(location: (editor.string as NSString).length, length: 0) {
            onKey?(SearchKeyInput(kind: .actions))
            return
        }
        // ⌫ en fin d'un chemin `…/` : le dossier parent, comme la navigation d'Alfred (session 105).
        if event.type == .keyDown, event.keyCode == 51, pathNavigation,
           event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty,
           let editor = field.currentEditor() as? NSTextView, !editor.hasMarkedText(),
           editor.selectedRange() == NSRange(location: (editor.string as NSString).length, length: 0),
           LauncherPathRules.parent(field.stringValue) != nil {
            onKey?(SearchKeyInput(kind: .parentFolder))
            return
        }
        // Effacement dans un champ vide : rien ne change pour AppKit, la barre revient d'une étape (SPEC-074).
        if event.type == .keyDown, event.keyCode == 51, field.stringValue.isEmpty,
           event.modifierFlags.intersection([.command, .control, .option]).isEmpty {
            onKey?(SearchKeyInput(kind: .delete))
            return
        }
        if event.type == .keyDown,
           (field.currentEditor() as? NSTextView)?.hasMarkedText() != true,
           let input = Self.navigation(event, labels: labelLetters, pick: pickModifier, text: field.stringValue,
                                       selection: selectionKeys, grid: gridColumns != nil, viewCycle: viewCycle,
                                       barKeys: barKeys) {
            onKey?(input)
            return
        }
        super.sendEvent(event)
    }

    /// Les menus Édition ne sont pas installés dans le daemon. Cibler exclusivement cet éditeur.
    /// Les touches réglables de la barre passent d'abord (session 108) : ⌘C ne copie la ligne que sans
    /// texte sélectionné, sinon l'éditeur copie le texte.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.type == .keyDown, let editor = field.currentEditor() as? NSTextView, !editor.hasMarkedText(),
           let action = barKeys[BarKeyCombo(event)] {
            if action == "close" { onCancel?(); return true }
            if action == "copy", editor.selectedRange().length > 0 { return NSApp.sendAction(#selector(NSText.copy(_:)), to: editor, from: self) }
            if let input = Self.barInput(action, selection: selectionKeys) { onKey?(input); return true }
        }
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

    /// Codes physiques des chiffres 1 à 9 : rangée du haut puis pavé numérique.
    private static let digitKeys: [UInt16: Int] = [18: 1, 19: 2, 20: 3, 21: 4, 23: 5, 22: 6, 26: 7, 28: 8, 25: 9,
                                                   83: 1, 84: 2, 85: 3, 86: 4, 87: 5, 88: 6, 89: 7, 91: 8, 92: 9]

    /// O(1). Les modificateurs de déplacement/sélection restent à AppKit.
    /// `text` : saisie du champ. Avec Maj pour les raccourcis, Maj + chiffre écrit le chiffre dans une
    /// saisie vide ou de calcul : en AZERTY, les chiffres se tapent avec Maj (SPEC-087 FR-009).
    static func navigation(_ event: NSEvent, labels: Set<String> = [], pick: NSEvent.ModifierFlags = .command,
                           text: String = "", selection: SelectionKeys = SelectionKeys(), grid: Bool = false,
                           viewCycle: (keyCode: UInt16, flags: NSEvent.ModifierFlags)? = nil,
                           barKeys: [BarKeyCombo: String]? = nil) -> SearchKeyInput? {
        let flags = event.modifierFlags.intersection([.command, .control, .option, .shift])
        // Touches réglables (session 108) ; ⌘W se traite dans `performKeyEquivalent`.
        let table = barKeys ?? barKeyTable(LauncherBarKeys.resolved([:]), layout: TargetSearchHotkey.currentLayoutTable())
        if let action = table[BarKeyCombo(event)], action != "close", let input = barInput(action, selection: selection) {
            return input
        }
        // Touche des présentations (session 099), avant les autres rôles de la touche.
        if let viewCycle, event.keyCode == viewCycle.keyCode, flags == viewCycle.flags { return SearchKeyInput(kind: .cycleView) }
        // Grille (SPEC-092 FR-004) : ← → passent à la tuile voisine ; Tab garde les verbes.
        if grid, flags.isEmpty, event.keyCode == 123 || event.keyCode == 124 {
            return SearchKeyInput(kind: .move(event.keyCode == 123 ? -1 : 1))
        }
        // ⌘1 à ⌘9 (ou la touche de `pick_modifier`), rangée du haut ou pavé numérique, quelle que soit
        // la disposition : le code physique compte, pas le caractère.
        let typesDigit = pick == .shift && LauncherCalculator.isTyping(text)
        if flags == pick, !typesDigit, let rank = digitKeys[event.keyCode] {
            return SearchKeyInput(kind: .pick(rank))
        }
        if flags == .shift, let letter = event.charactersIgnoringModifiers?.lowercased(), labels.contains(letter) {
            return SearchKeyInput(kind: .labelCharacter(letter))
        }
        switch event.keyCode {
        case 53: return SearchKeyInput(kind: .escape)
        case 36, 76:
            return SearchKeyInput(kind: .confirm(shift: flags.contains(.shift), command: flags.contains(.command),
                                                 option: flags.contains(.option), control: flags.contains(.control),
                                                 isRepeat: event.isARepeat))
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

extension LauncherPickModifier {
    var flags: NSEvent.ModifierFlags {
        switch self {
        case .command: .command
        case .shift: .shift
        case .alt: .option
        case .control: .control
        }
    }
}

extension SearchInputPanel {
    /// `view_cycle_hotkey` normalisé → code physique et modificateurs selon la disposition ; nil si vide
    /// ou introuvable (session 099). O(128).
    nonisolated static func cycleKey(_ normalized: String, layout: [UInt32: String]) -> (keyCode: UInt16, flags: NSEvent.ModifierFlags)? {
        guard let parts = TargetModeConfig.hotkeyParts(normalized),
              let code = TargetSearchHotkey.namedKeyCode(parts.key) ?? TargetSearchHotkey.keyCode(for: parts.key, in: layout) else { return nil }
        var flags: NSEvent.ModifierFlags = []
        if parts.modifiers.contains("command") { flags.insert(.command) }
        if parts.modifiers.contains("control") { flags.insert(.control) }
        if parts.modifiers.contains("alt") { flags.insert(.option) }
        if parts.modifiers.contains("shift") { flags.insert(.shift) }
        return (UInt16(code), flags)
    }
}

extension SearchInputPanel {
    /// Action d'une touche réglable. Sélection multiple (SPEC-091) : ajouter sur une ligne qui se choisit,
    /// retirer, montrer les actions ou vider avec une sélection ; sinon nil, et AppKit déplace le curseur
    /// ou efface par mot (calcul, chemin, texte). O(1).
    static func barInput(_ action: String, selection: SelectionKeys) -> SearchKeyInput? {
        switch action {
        case "large_type": SearchKeyInput(kind: .largeType)
        case "copy": SearchKeyInput(kind: .copy)
        case "preview": SearchKeyInput(kind: .preview)
        case "save_action": SearchKeyInput(kind: .save)
        case "show_rules": SearchKeyInput(kind: .showRules)
        case "close_all": SearchKeyInput(kind: .closeAll)
        case "settings": SearchKeyInput(kind: .openSettings)
        case "select_toggle" where selection.rowSelectable: SearchKeyInput(kind: .selectToggle)
        case "select_add_next" where selection.rowSelectable: SearchKeyInput(kind: .selectAddNext)
        case "select_remove_last" where selection.hasSelection: SearchKeyInput(kind: .selectRemoveLast)
        case "selection_verbs" where selection.hasSelection: SearchKeyInput(kind: .selectionVerbs)
        case "select_clear" where selection.hasSelection: SearchKeyInput(kind: .selectClear)
        default: nil
        }
    }

    /// Combinaisons physiques des touches de la barre, selon la disposition du clavier. Une combinaison
    /// donnée à deux actions garde la première de `LauncherBarKeys.actions`. O(a).
    nonisolated static func barKeyTable(_ keys: [String: String], layout: [UInt32: String]) -> [BarKeyCombo: String] {
        var table: [BarKeyCombo: String] = [:]
        for action in LauncherBarKeys.actions {
            guard let raw = keys[action.id], let key = cycleKey(raw, layout: layout) else { continue }
            let combo = BarKeyCombo(keyCode: key.keyCode, flags: key.flags)
            if table[combo] == nil { table[combo] = action.id }
        }
        return table
    }
}

/// Touche physique et modificateurs (⌘ ⌃ ⌥ ⇧), sans le côté ni les autres drapeaux.
struct BarKeyCombo: Hashable, Sendable {
    let keyCode: UInt16
    let flags: UInt

    init(keyCode: UInt16, flags: NSEvent.ModifierFlags) {
        self.keyCode = keyCode
        self.flags = flags.intersection([.command, .control, .option, .shift]).rawValue
    }

    init(_ event: NSEvent) { self.init(keyCode: event.keyCode, flags: event.modifierFlags) }
}

/// État de la barre utile aux touches ⌥ (SPEC-091) : une sélection existe, la ligne choisie se choisit.
struct SelectionKeys: Equatable, Sendable {
    var hasSelection = false
    var rowSelectable = false
}
