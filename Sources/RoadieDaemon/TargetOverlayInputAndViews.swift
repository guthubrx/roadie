import AppKit
import CoreGraphics
import Foundation
import RoadieCore

/// Fin d'une session suivie d'une action de la boîte de commandes (SPEC-023 R2) : nettoyer la session,
/// prévenir le contrôleur (qui remet son état à zéro), puis lancer l'action un tour de boucle plus tard.
/// Lancée plus tôt, une commande `grid` ou `targets` ouvrirait sa session avant cette remise à zéro,
/// qui effacerait alors la nouvelle session du contrôleur.
@MainActor
enum CommandBoxFollowUp {
    static func finish(cleanup: () -> Void, notify: () -> Void, then action: (@MainActor @Sendable () -> Void)?) {
        cleanup()
        notify()
        guard let action else { return }
        DispatchQueue.main.async { MainActor.assumeIsolated { action() } }
    }
}

/// Effet d'une touche de la boîte de commandes pour la session (SPEC-023 R3).
enum CommandBoxKeyEffect: Equatable {
    /// Saisie, liste ou message à redessiner.
    case update
    /// Retour : commande à exécuter, sans `/`.
    case submit(String)
    /// Échap : fermer sans action.
    case close
    /// `/` effacé : la main revient à la recherche.
    case leave
}

extension SlashCommandModel {
    /// Aiguillage pur d'une touche en mode commande : la recherche n'en voit aucune. Maj + lettre écrit
    /// une majuscule, Tab complète, Maj-Tab et Ctrl-P remontent la liste, Ctrl-N la descend, les
    /// flèches parcourent les suggestions (historique à vide/sans proposition), Retour accepte le
    /// choix explicite puis exécute sans attendre de second Retour.
    /// Complexité : celle de l'opération appelée, O(c + l) au plus.
    mutating func handle(_ input: SearchKeyInput) -> CommandBoxKeyEffect {
        switch input.kind {
        case .text(let value):
            type(value)
        case .labelCharacter(let value):
            type(value.uppercased())
        case .delete:
            deleteBackward()
            if !isActive { return .leave }
        case .next:
            switch input.navigationSource {
            case .arrow:
                if self.input.isEmpty || historyCursor != nil || suggestions.isEmpty { historyDown() }
                else { nextSuggestion() }
            case .control: nextSuggestion()
            case .tab, nil: complete()
            }
        case .previous:
            switch input.navigationSource {
            case .arrow:
                if self.input.isEmpty || historyCursor != nil || suggestions.isEmpty { historyUp() }
                else { previousSuggestion() }
            case .tab, .control, nil: previousSuggestion()
            }
        case .confirm(_, _, _, _, let isRepeat):
            if !isRepeat {
                acceptSelectedSuggestion()
                return .submit(submit())
            }
        case .escape, .closeAll:
            return .close
        case .ignored, .pick, .actions, .copy, .preview, .save, .showRules, .selectToggle, .selectAddNext, .selectRemoveLast,
             .selectionVerbs, .selectClear, .move, .cycleView, .parentFolder, .largeType, .openSettings:
            break
        }
        return .update
    }
}

/// Touches du mode recherche (SPEC-021) et de la boîte de commandes (SPEC-023). Le décodage lit le
/// caractère produit par la touche : sur AZERTY, Maj + `:` arrive comme texte `/`. Les combinaisons
/// Commande (sauf Cmd-Retour) passent à l'app ou au système. En recherche, une touche ignorée est
/// laissée à l'app active ; en mode commande, toute touche sans Commande est retenue (T027).
public struct SearchKeyInput: Sendable, Equatable {
    /// État de la saisie lu par le tap clavier (SPEC-023 T027, T030).
    public enum Mode: Sendable, Equatable {
        /// Recherche, requête vide : le `/` ouvre le mode commande.
        case emptySearch
        /// Recherche en cours : décodage de la SPEC-021 inchangé (FR-010), `/` ignoré.
        case search
        /// Mode commande : tout caractère imprimable est du texte.
        case command
    }

    public enum Kind: Sendable, Equatable {
        case text(String)
        case labelCharacter(String)
        case delete
        case escape
        case next
        case previous
        /// Option et Contrôle choisissent une variante du lanceur (SPEC-075).
        case confirm(shift: Bool, command: Bool, option: Bool = false, control: Bool = false, isRepeat: Bool)
        /// ⌘1 à ⌘9 : action par défaut de la ligne de ce rang parmi celles montrées (SPEC-075).
        case pick(Int)
        /// → en fin de saisie : verbes de la ligne choisie, comme Tab (SPEC-075).
        case actions
        /// ⌘C sans texte sélectionné : copier la ligne choisie ; ⌘Y : son aperçu (SPEC-077).
        case copy
        case preview
        /// ⌘S : garder l'action choisie en abréviation et en commande (SPEC-079).
        case save
        /// ⌘R : vider la saisie et montrer la règle proposée (SPEC-081).
        case showRules
        /// Sélection multiple (SPEC-091) : ⌥↑ ajoute ou retire, ⌥↓ ajoute et descend, ⌥← retire la
        /// dernière, ⌥→ verbes du lot, ⌥⌫ vide.
        case selectToggle, selectAddNext, selectRemoveLast, selectionVerbs, selectClear
        /// Grille d'un workflow (SPEC-092) : ← (-1) et → (+1).
        case move(Int)
        /// Touche des présentations (session 099) : liste → grille → grandes tuiles.
        case cycleView
        /// Session 105 : ⌫ sur un chemin de dossier remonte d'un dossier ; ⌘L montre la ligne en grand ;
        /// ⌘⎋ ferme la barre d'un coup.
        case parentFolder, largeType, closeAll
        /// Session 115 : ⌘, ouvre les Paramètres de Roadie.
        case openSettings
        case ignored
    }

    /// Touche à l'origine de `.next` ou `.previous` : la boîte de commandes leur donne des rôles
    /// différents (compléter, historique, suggestion suivante).
    public enum NavigationSource: Sendable, Equatable {
        case tab
        case arrow
        case control
    }

    public let kind: Kind
    /// Renseignée pour `.next` et `.previous` uniquement.
    public let navigationSource: NavigationSource?
    /// Touche retenue par le tap, donc cachée à l'app active. Faux pour `.ignored`, sauf en mode
    /// commande sans Commande (flèche gauche, touche morte : retenues sans effet).
    public let swallowed: Bool

    init(event: CGEvent, mode: Mode) {
        let flags = event.flags
        var length = 0
        var chars = [UniChar](repeating: 0, count: 8)
        event.keyboardGetUnicodeString(maxStringLength: chars.count, actualStringLength: &length, unicodeString: &chars)
        self.init(
            keyCode: event.getIntegerValueField(.keyboardEventKeycode),
            text: String(utf16CodeUnits: chars, count: length),
            shift: flags.contains(.maskShift),
            command: flags.contains(.maskCommand),
            control: flags.contains(.maskControl),
            isRepeat: event.getIntegerValueField(.keyboardEventAutorepeat) != 0,
            mode: mode
        )
    }

    public init(kind: Kind, navigationSource: NavigationSource? = nil, swallowed: Bool? = nil) {
        self.kind = kind
        self.navigationSource = navigationSource
        self.swallowed = swallowed ?? (kind != .ignored)
    }

    /// Décodage pur, testable, du mode recherche : code de touche, texte produit et modificateurs.
    public static func kind(keyCode: Int64, text: String, shift: Bool, command: Bool, control: Bool, isRepeat: Bool) -> Kind {
        SearchKeyInput(keyCode: keyCode, text: text, shift: shift, command: command, control: control, isRepeat: isRepeat).kind
    }

    /// Décodage pur du mode recherche (SPEC-021), avec la touche de navigation. O(1).
    public init(keyCode: Int64, text: String, shift: Bool, command: Bool, control: Bool, isRepeat: Bool) {
        self.init(keyCode: keyCode, text: text, shift: shift, command: command, control: control, isRepeat: isRepeat, mode: .search)
    }

    /// Décodage pur selon l'état de la saisie. O(t), t ≤ 8 caractères produits.
    public init(keyCode: Int64, text: String, shift: Bool, command: Bool, control: Bool, isRepeat: Bool, mode: Mode) {
        switch keyCode {
        case 53: self.init(kind: .escape); return
        case 51: self.init(kind: .delete); return
        case 36, 76: self.init(kind: .confirm(shift: shift, command: command, control: control, isRepeat: isRepeat)); return
        default: break
        }
        // Cmd-Tab, Cmd-Espace… restent au système.
        if command { self.init(kind: .ignored); return }
        switch keyCode {
        case 48: self.init(kind: shift ? .previous : .next, navigationSource: .tab); return
        case 125: self.init(kind: .next, navigationSource: .arrow); return
        case 126: self.init(kind: .previous, navigationSource: .arrow); return
        default: break
        }
        // Sans Commande : le mode commande retient aussi les touches sans effet.
        let commandMode = mode == .command
        if control {
            switch text.lowercased() {
            case "n", "\u{0E}": self.init(kind: .next, navigationSource: .control)
            case "p", "\u{10}": self.init(kind: .previous, navigationSource: .control)
            default: self.init(kind: .ignored, swallowed: commandMode)
            }
            return
        }
        if commandMode {
            // Caractère produit avec Maj ou Option (`#`, `@`, `{`…) ; touche morte en attente : texte vide.
            let printable = !text.isEmpty && text.allSatisfy(Self.isPrintable)
            self.init(kind: printable ? .text(text) : .ignored, swallowed: true)
            return
        }
        guard text.count == 1, let character = text.first else { self.init(kind: .ignored); return }
        if character.isLetter && shift { self.init(kind: .labelCharacter(String(character).lowercased())); return }
        // Liste de la SPEC-021 (FR-010) ; le `/` d'une requête vide ouvre le mode commande.
        if character.isLetter || character.isNumber || " *;?".contains(character) || (mode == .emptySearch && character == "/") {
            self.init(kind: .text(String(character)))
            return
        }
        self.init(kind: .ignored)
    }

    /// Ni caractère de contrôle, ni touche de fonction (zone privée U+F700…, flèches comprises).
    private static func isPrintable(_ character: Character) -> Bool {
        character.unicodeScalars.allSatisfy { scalar in
            switch scalar.properties.generalCategory {
            case .control, .format, .privateUse, .unassigned: false
            default: true
            }
        }
    }
}

struct KeyInput: Sendable {
    enum Kind: Sendable {
        case characters(String)
        case escape
        case delete
        case confirm
        case arrow(ArrowDirection)
        case other
    }

    enum ArrowDirection: Sendable {
        case left
        case right
        case up
        case down

        var targetGridDirection: TargetGridArrowDirection {
            switch self {
            case .left: return .left
            case .right: return .right
            case .up: return .up
            case .down: return .down
            }
        }
    }

    var kind: Kind
    var normalizedName: String

    init(event: CGEvent) {
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        if keyCode == 53 {
            self.kind = .escape
            self.normalizedName = "escape"
            return
        }
        if keyCode == 51 {
            self.kind = .delete
            self.normalizedName = "backspace"
            return
        }
        if keyCode == 36 {
            self.kind = .confirm
            self.normalizedName = "return"
            return
        }
        if keyCode == 49 {
            self.kind = .confirm
            self.normalizedName = "space"
            return
        }
        if keyCode == 123 {
            self.kind = .arrow(.left)
            self.normalizedName = "arrow_left"
            return
        }
        if keyCode == 124 {
            self.kind = .arrow(.right)
            self.normalizedName = "arrow_right"
            return
        }
        if keyCode == 125 {
            self.kind = .arrow(.down)
            self.normalizedName = "arrow_down"
            return
        }
        if keyCode == 126 {
            self.kind = .arrow(.up)
            self.normalizedName = "arrow_up"
            return
        }
        var length = 0
        var chars = [UniChar](repeating: 0, count: 8)
        event.keyboardGetUnicodeString(maxStringLength: chars.count, actualStringLength: &length, unicodeString: &chars)
        let text = String(utf16CodeUnits: chars, count: length)
            .filter { $0.isLetter || $0.isNumber }
        self.kind = text.isEmpty ? .other : .characters(String(text))
        if let first = text.first {
            let flags = event.flags
            var parts: [String] = []
            if flags.contains(.maskCommand) { parts.append("command") }
            if flags.contains(.maskControl) { parts.append("control") }
            if flags.contains(.maskAlternate) { parts.append("alt") }
            if flags.contains(.maskShift) { parts.append("shift") }
            parts.append(String(first).lowercased())
            self.normalizedName = parts.joined(separator: "+")
        } else {
            self.normalizedName = "other"
        }
    }

    var isRoadieHandled: Bool {
        switch kind {
        case .characters, .escape, .delete, .confirm, .arrow:
            return true
        case .other:
            return false
        }
    }
}

struct TargetOverlayBadge {
    var label: String
    var title: String
    var kind: TargetKind
    var isActive: Bool
    var frame: CGRect
    /// Correspondance mise en avant du mode recherche (vert).
    var isHighlighted = false
    /// Recherche avec des étiquettes d'une lettre : cadre fin autour de chaque résultat.
    var isFramed = false
    /// Résultat du mode recherche : étiquette sur fond vert.
    var isSearchResult = false

    static func badges(from state: TargetOverlayState) -> [TargetOverlayBadge] {
        state.report.targets.compactMap { target in
            guard let frame = target.frame?.cgRect else { return nil }
            return TargetOverlayBadge(
                label: target.label,
                title: target.title,
                kind: target.kind,
                isActive: target.isActive,
                frame: RoadieScreenCoordinate.axRectToNS(frame)
            )
        }
    }
}

@MainActor
final class TargetOverlayWindow: NSPanel {
    private let overlay: TargetOverlayView
    /// Flou derrière la barre et la liste d'un thème translucide (session 101), sous la vue dessinée.
    private var blurViews: [NSVisualEffectView] = []

    init(frame: CGRect, badges: [TargetOverlayBadge], style: TargetOverlayStyle) {
        let content = TargetOverlayView(
            frame: CGRect(origin: .zero, size: frame.size),
            badges: badges,
            screenOrigin: frame.origin,
            style: style
        )
        overlay = content
        super.init(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        colorSpace = .sRGB
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        ignoresMouseEvents = true
        hasShadow = false
        let container = NSView(frame: CGRect(origin: .zero, size: frame.size))
        content.autoresizingMask = [.width, .height]
        container.addSubview(content)
        contentView = container
    }

    func updateStyle(_ style: TargetOverlayStyle) {
        overlay.updateStyle(style)
    }

    /// Une icône réduite en fond est arrivée (session 123).
    func redraw() { overlay.needsDisplay = true }

    /// Mode recherche : nouvelles étiquettes et barre de saisie (nil = pas de barre sur cet écran).
    func update(badges: [TargetOverlayBadge], searchBar: TargetSearchBar?, ghost: LauncherGhost? = nil) {
        let view = overlay
        view.badges = badges
        view.searchBar = searchBar
        view.ghost = ghost
        view.needsDisplay = true
        updateBlur(searchBar)
    }

    /// O(2) : une vue de flou par surface (barre, liste), réutilisées d'un rendu à l'autre.
    private func updateBlur(_ searchBar: TargetSearchBar?) {
        let theme = overlay.currentStyle.theme
        guard let container = contentView, let searchBar, let appearance = theme.blurAppearance else {
            blurViews.forEach { $0.isHidden = true }
            return
        }
        let layout = searchBar.layout(in: overlay.bounds, style: overlay.currentStyle)
        let rects = [layout.bar] + (layout.panel.map { [$0] } ?? [])
        while blurViews.count < rects.count {
            let blur = NSVisualEffectView()
            blur.blendingMode = .behindWindow
            blur.state = .active
            blur.wantsLayer = true
            blur.layer?.masksToBounds = true
            container.addSubview(blur, positioned: .below, relativeTo: overlay)
            blurViews.append(blur)
        }
        for (index, blur) in blurViews.enumerated() {
            guard index < rects.count else { blur.isHidden = true; continue }
            blur.isHidden = false
            blur.frame = rects[index]
            blur.appearance = NSAppearance(named: appearance)
            blur.material = appearance == .aqua ? .popover : .hudWindow
            blur.layer?.cornerRadius = min(CGFloat(theme.roundness), rects[index].height / 2)
        }
    }
}

final class TargetOverlayView: NSView {
    fileprivate var badges: [TargetOverlayBadge]
    fileprivate var searchBar: TargetSearchBar?
    /// Place de la fenêtre à venir pendant l'aperçu actif (SPEC-078), en coordonnées d'écran.
    fileprivate var ghost: LauncherGhost?
    private let screenOrigin: CGPoint
    private var style: TargetOverlayStyle
    var currentStyle: TargetOverlayStyle { style }
    // Réutilisés pour mesurer et dessiner chaque badge : aucune allocation de police dans la boucle.
    private var textAttributes: [NSAttributedString.Key: Any]

    private static func badgeTextAttributes(_ style: TargetOverlayStyle) -> [NSAttributedString.Key: Any] {
        [.font: NSFont.monospacedSystemFont(ofSize: style.labelFontSize, weight: .semibold),
         .foregroundColor: NSColor.white]
    }

    private struct BadgePlacement {
        var badge: CGRect
        var target: CGRect
    }

    init(frame: CGRect, badges: [TargetOverlayBadge], screenOrigin: CGPoint, style: TargetOverlayStyle) {
        self.badges = badges
        self.screenOrigin = screenOrigin
        self.style = style
        self.textAttributes = Self.badgeTextAttributes(style)
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    required init?(coder: NSCoder) {
        nil
    }

    func updateStyle(_ style: TargetOverlayStyle) {
        if self.style.labelFontSize != style.labelFontSize {
            textAttributes = Self.badgeTextAttributes(style)
        }
        self.style = style
        needsDisplay = true
    }

    override var isOpaque: Bool { false }

    /// Fantôme : rectangle translucide en couleur d'accent et icône de l'application, à la place que
    /// prendra la fenêtre ; dessiné sous les étiquettes et la barre.
    private func drawGhost(_ ghost: LauncherGhost) {
        let local = ghost.frame.offsetBy(dx: -screenOrigin.x, dy: -screenOrigin.y)
        guard local.intersects(bounds) else { return }
        let path = NSBezierPath(roundedRect: local.insetBy(dx: 2, dy: 2), xRadius: 12, yRadius: 12)
        NSColor.controlAccentColor.withAlphaComponent(0.16).setFill()
        path.fill()
        NSColor.controlAccentColor.withAlphaComponent(0.85).setStroke()
        path.lineWidth = 2
        path.setLineDash([10, 6], count: 2, phase: 0)
        path.stroke()
        if let icon = ghost.icon {
            let side = min(96, local.width * 0.4, local.height * 0.4)
            icon.draw(in: CGRect(x: local.midX - side / 2, y: local.midY - side / 2, width: side, height: side),
                      from: .zero, operation: .sourceOver, fraction: 0.85)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        guard searchBar != nil, let clock = LauncherOpenClock.current else { return drawNow(dirtyRect) }
        clock.measureDraw { drawNow(dirtyRect) }
    }

    private func drawNow(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        if let ghost { drawGhost(ghost) }
        var occupied: [CGRect] = []
        for badge in badges {
            guard let placement = placement(for: badge, avoiding: occupied) else { continue }
            drawTargetFrame(for: badge, placement: placement)
            drawPointer(for: badge, placement: placement)
            drawBadge(badge, in: placement.badge)
            occupied.append(placement.badge.insetBy(dx: -style.badgeAvoidanceMargin, dy: -style.badgeAvoidanceMargin))
        }
        if let searchBar {
            SearchBarRenderer.draw(searchBar, in: bounds, style: style)
        }
    }

    private func placement(for badge: TargetOverlayBadge, avoiding occupied: [CGRect]) -> BadgePlacement? {
        let localFrame = badge.frame.offsetBy(dx: -screenOrigin.x, dy: -screenOrigin.y)
        guard bounds.intersects(localFrame), localFrame.width > 4, localFrame.height > 4 else { return nil }

        let label = badge.label.isEmpty ? "?" : badge.label
        let textSize = label.size(withAttributes: textAttributes)
        let badgeSize = style.badgeSize(textWidth: textSize.width)
        if badge.kind == .gridCell, style.labelPlacement == .center {
            let rect = clamped(CGRect(
                x: localFrame.midX - badgeSize.width / 2,
                y: localFrame.midY - badgeSize.height / 2,
                width: badgeSize.width,
                height: badgeSize.height
            )).integral
            return BadgePlacement(badge: rect, target: localFrame)
        }
        let candidates = candidateOrigins(for: localFrame, badgeSize: badgeSize)
        for origin in candidates {
            let rect = clamped(CGRect(origin: origin, size: badgeSize)).integral
            if !occupied.contains(where: { $0.intersects(rect) }) {
                return BadgePlacement(badge: rect, target: localFrame)
            }
        }
        let fallback = clamped(CGRect(origin: candidates.first ?? localFrame.origin, size: badgeSize)).integral
        return BadgePlacement(badge: fallback, target: localFrame)
    }

    private func candidateOrigins(for frame: CGRect, badgeSize: CGSize) -> [CGPoint] {
        let gap = style.badgeGap
        let inset = style.badgeInset
        let primary = CGPoint(x: frame.minX + inset, y: frame.maxY + gap)
        let anchors = [
            primary,
            CGPoint(x: frame.maxX - badgeSize.width - inset, y: frame.maxY + gap),
            CGPoint(x: frame.maxX + gap, y: frame.midY - badgeSize.height / 2),
            CGPoint(x: frame.minX - badgeSize.width - gap, y: frame.midY - badgeSize.height / 2),
            CGPoint(x: frame.minX + inset, y: frame.minY - badgeSize.height - gap),
            CGPoint(x: frame.maxX - badgeSize.width - inset, y: frame.minY - badgeSize.height - gap),
            CGPoint(x: frame.midX - badgeSize.width / 2, y: frame.midY - badgeSize.height / 2),
            CGPoint(x: frame.minX + inset, y: frame.maxY - badgeSize.height - inset),
            CGPoint(x: frame.maxX - badgeSize.width - inset, y: frame.maxY - badgeSize.height - inset),
        ]
        let stepX = badgeSize.width + style.badgePlacementSpacing
        let stepY = badgeSize.height + style.badgePlacementSpacing
        var result = anchors
        for ring in 1...8 {
            let distanceX = CGFloat(ring) * stepX
            let distanceY = CGFloat(ring) * stepY
            result.append(contentsOf: [
                CGPoint(x: primary.x + distanceX, y: primary.y),
                CGPoint(x: primary.x - distanceX, y: primary.y),
                CGPoint(x: primary.x, y: primary.y - distanceY),
                CGPoint(x: primary.x, y: primary.y + distanceY),
                CGPoint(x: primary.x + distanceX, y: primary.y - distanceY),
                CGPoint(x: primary.x - distanceX, y: primary.y - distanceY),
            ])
        }
        return result
    }

    private func clamped(_ rect: CGRect) -> CGRect {
        style.clampedBadge(rect, in: bounds)
    }

    private func drawTargetFrame(for badge: TargetOverlayBadge, placement: BadgePlacement) {
        if badge.isHighlighted {
            let path = NSBezierPath(roundedRect: placement.target.insetBy(dx: -2, dy: -2), xRadius: 6, yRadius: 6)
            NSColor.systemGreen.setStroke()
            path.lineWidth = 3
            path.stroke()
            return
        }
        if badge.isFramed {
            let path = NSBezierPath(roundedRect: placement.target.insetBy(dx: -2, dy: -2), xRadius: 6, yRadius: 6)
            NSColor.systemGreen.withAlphaComponent(0.9).setStroke()
            path.lineWidth = 1.5
            path.stroke()
            return
        }
        guard style.drawTargetFrames, badge.kind == .gridCell else { return }
        let rect = placement.target.integral.insetBy(dx: 0.5, dy: 0.5)
        guard rect.width > 2, rect.height > 2 else { return }

        let path = NSBezierPath(rect: rect)
        (NSColor(hex: style.fillColor) ?? .systemBlue)
            .withAlphaComponent(CGFloat(style.fillOpacity))
            .setFill()
        path.fill()

        (NSColor(hex: style.borderColor) ?? .systemBlue)
            .withAlphaComponent(CGFloat(style.borderOpacity))
            .setStroke()
        path.lineWidth = 1
        path.stroke()
    }

    private func drawPointer(for badge: TargetOverlayBadge, placement: BadgePlacement) {
        guard !(badge.kind == .gridCell && style.labelPlacement == .center) else { return }
        let badgeRect = placement.badge
        let targetRect = placement.target
        let targetPoint = nearestPoint(on: targetRect, to: CGPoint(x: badgeRect.midX, y: badgeRect.midY))
        let anchor = nearestPoint(on: badgeRect, to: targetPoint)
        let dx = targetPoint.x - anchor.x
        let dy = targetPoint.y - anchor.y
        let distance = max(1, hypot(dx, dy))
        let ux = dx / distance
        let uy = dy / distance
        let perp = CGPoint(x: -uy * 5, y: ux * 5)
        let tip = CGPoint(x: anchor.x + ux * min(16, distance), y: anchor.y + uy * min(16, distance))

        let path = NSBezierPath()
        path.move(to: CGPoint(x: anchor.x + perp.x, y: anchor.y + perp.y))
        path.line(to: tip)
        path.line(to: CGPoint(x: anchor.x - perp.x, y: anchor.y - perp.y))
        path.close()

        NSColor(calibratedWhite: 0.04, alpha: CGFloat(style.labelBackgroundOpacity)).setFill()
        path.fill()
        (badge.isActive ? NSColor.systemBlue : tint(for: badge.kind)).withAlphaComponent(0.9).setStroke()
        path.lineWidth = 1
        path.stroke()
    }

    private func nearestPoint(on rect: CGRect, to point: CGPoint) -> CGPoint {
        CGPoint(
            x: min(max(point.x, rect.minX), rect.maxX),
            y: min(max(point.y, rect.minY), rect.maxY)
        )
    }

    private func drawBadge(_ badge: TargetOverlayBadge, in rect: CGRect) {
        let label = badge.label.isEmpty ? "?" : badge.label
        let textSize = label.size(withAttributes: textAttributes)
        let path = NSBezierPath(roundedRect: rect, xRadius: style.badgeCornerRadius, yRadius: style.badgeCornerRadius)
        // Recherche : fond vert pour chaque résultat ; seule la bordure distingue la cible choisie
        // (épaisse et blanche).
        (badge.isHighlighted || badge.isSearchResult ? NSColor.systemGreen.withAlphaComponent(0.85)
            : NSColor(calibratedWhite: 0.04, alpha: CGFloat(style.labelBackgroundOpacity))).setFill()
        path.fill()
        (badge.isHighlighted ? NSColor.white : badge.isActive ? NSColor.systemBlue : tint(for: badge.kind)).setStroke()
        path.lineWidth = badge.isHighlighted ? 2.5 : 1.5
        path.stroke()

        var attributes = textAttributes
        if badge.kind == .gridCell {
            attributes[.foregroundColor] = NSColor(hex: style.labelColor) ?? .white
        }
        label.draw(
            in: CGRect(
                x: rect.minX + (rect.width - textSize.width) / 2,
                y: rect.minY + (rect.height - textSize.height) / 2,
                width: textSize.width,
                height: textSize.height
            ),
            withAttributes: attributes
        )
    }

    private func tint(for kind: TargetKind) -> NSColor {
        switch kind {
        case .window:
            return .systemGreen
        case .stage:
            return .systemOrange
        case .display:
            return .systemPurple
        case .desktop:
            return .systemGray
        case .bookmark:
            return .systemPink
        case .appElement:
            return .systemTeal
        case .gridCell:
            return .systemYellow
        }
    }
}
