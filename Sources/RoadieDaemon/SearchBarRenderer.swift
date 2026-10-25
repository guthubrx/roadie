import AppKit
import RoadieCore

/// Mise en page de la barre de saisie et de la boîte de commandes (SPEC-023 R4), pure. La barre reste
/// collée en bas de l'écran (y = minY + 48) ; la liste et le message s'empilent au-dessus d'elle,
/// sans sortir de l'écran. Le message, réponse à Retour, est le plus près de la barre.
struct SearchBarLayout: Equatable {
    static let maxSuggestions = 8
    static let maxMessageLines = 12
    static let lineHeight: CGFloat = 22
    static let padding: CGFloat = 8
    static let gap: CGFloat = 6

    var bar: CGRect
    /// Fond des lignes ; nil sans ligne.
    var panel: CGRect?
    /// De haut en bas.
    var suggestionRows: [CGRect]
    var messageRows: [CGRect]
    /// Lignes de hauteurs variables (lanceur) : index de la première ligne montrée. nil : lignes égales.
    var firstVisible: Int? = nil

    /// Seules les surfaces visibles gardent la recherche ouverte ; l'espace entre elles reste extérieur.
    func contains(_ point: CGPoint) -> Bool {
        bar.contains(point) || panel?.contains(point) == true
    }

    /// Le clic et le dessin utilisent la même tranche de propositions. O(s), s ≤ 8.
    func suggestionIndex(at point: CGPoint, count: Int, selected: Int?) -> Int? {
        let visible = visibleRange(count: count, selected: selected)
        guard let row = suggestionRows.firstIndex(where: { $0.insetBy(dx: -6, dy: 0).contains(point) }) else { return nil }
        let index = visible.lowerBound + row
        return visible.contains(index) ? index : nil
    }

    /// La largeur du contenu ne déplace plus la barre. Faute de place, les suggestions cèdent la
    /// place au message. Complexité : O(s + m), s ≤ 8 et m ≤ 12.
    static func make(
        bounds: CGRect, suggestions: Int, messageLines: Int,
        searchTextFontSize: CGFloat = 15, commandTextFontSize: CGFloat = 13
    ) -> SearchBarLayout {
        let lineHeight = Self.lineHeight * min(48, max(8, commandTextFontSize)) / 13
        let barHeight = 40 * min(48, max(8, searchTextFontSize)) / 15
        let margin = min(20, bounds.width * 0.05)
        let width = max(0, min(640, bounds.width - 2 * margin))
        let bar = CGRect(x: bounds.midX - width / 2, y: bounds.minY + min(48, max(0, bounds.height - barHeight)), width: width, height: min(bounds.height, barHeight))
        let room = max(0, Int((bounds.maxY - 8 - bar.maxY - gap - 2 * padding) / lineHeight))
        let messageCount = min(messageLines, maxMessageLines, room)
        let suggestionCount = min(suggestions, maxSuggestions, room - messageCount)
        let total = messageCount + suggestionCount
        guard total > 0 else { return SearchBarLayout(bar: bar, panel: nil, suggestionRows: [], messageRows: []) }
        let panel = CGRect(x: bar.minX, y: bar.maxY + gap, width: bar.width, height: CGFloat(total) * lineHeight + 2 * padding)
        let rows = (0..<total).map { index in
            CGRect(x: panel.minX + 12, y: panel.maxY - padding - CGFloat(index + 1) * lineHeight, width: panel.width - 24, height: lineHeight)
        }
        return SearchBarLayout(
            bar: bar,
            panel: panel,
            suggestionRows: Array(rows.prefix(suggestionCount)),
            messageRows: Array(rows.suffix(messageCount))
        )
    }

    /// Tranche montrée, commune au dessin et au clic. O(1).
    func visibleRange(count: Int, selected: Int?) -> Range<Int> {
        if let firstVisible { return firstVisible..<min(count, firstVisible + suggestionRows.count) }
        return Self.visibleSuggestions(count: count, selected: selected, rows: suggestionRows.count)
    }

    /// Liste du lanceur (SPEC-073) : lignes de hauteurs différentes (titres de section fins, résultats
    /// sur deux niveaux). La tranche montrée commence au début et glisse juste assez pour garder la
    /// sélection visible. O(n), n lignes.
    static func makeRich(bounds: CGRect, heights: [CGFloat], selected: Int?, searchTextFontSize: CGFloat = 15) -> SearchBarLayout {
        let base = make(bounds: bounds, suggestions: 0, messageLines: 0, searchTextFontSize: searchTextFontSize)
        let room = max(0, bounds.maxY - 8 - base.bar.maxY - gap - 2 * padding)
        guard !heights.isEmpty else { return base }
        var start = 0, end = 0, used: CGFloat = 0
        while end < heights.count, used + heights[end] <= room { used += heights[end]; end += 1 }
        if let selected, selected >= end, selected < heights.count {
            end = selected + 1
            used = heights[start..<end].reduce(0, +)
            while used > room, start < selected { used -= heights[start]; start += 1 }
            while end < heights.count, used + heights[end] <= room { used += heights[end]; end += 1 }
        }
        guard end > start else { return base }
        let panel = CGRect(x: base.bar.minX, y: base.bar.maxY + gap, width: base.bar.width, height: used + 2 * padding)
        var top = panel.maxY - padding
        let rows = heights[start..<end].map { height -> CGRect in
            top -= height
            return CGRect(x: panel.minX + 10, y: top, width: panel.width - 20, height: height)
        }
        return SearchBarLayout(bar: base.bar, panel: panel, suggestionRows: rows, messageRows: [], firstVisible: start)
    }

    /// Suggestions montrées dans `rows` lignes, sélection comprise. O(1).
    static func visibleSuggestions(count: Int, selected: Int?, rows: Int) -> Range<Int> {
        let shown = max(0, min(count, rows))
        let start = min(max(0, (selected ?? 0) - shown + 1), count - shown)
        return start..<(start + shown)
    }
}

/// Contenu de la barre de saisie du mode recherche.
struct TargetSearchBar {
    var query: String
    var matchCount: Int
    var properties: String?
    var isLoading: Bool
    /// Mode commande (SPEC-023) : saisie après le `/` ; nil en mode recherche.
    var commandInput: String? = nil
    var suggestions: [SlashSuggestion] = []
    var selectedSuggestion: Int? = nil
    var message: SlashMessage? = nil
    /// Lanceur : icône grande, nom et détail sur deux niveaux, sélection en couleur d'accent.
    var richRows = false
    /// Le champ AppKit affiche le texte à l'exécution ; les rendus hors écran le dessinent encore.
    var usesNativeInput = false

    var inputText: String {
        if let commandInput { return "/\(commandInput)▏" }
        if let properties { return properties }
        return query.isEmpty ? "Rechercher ou saisir /commande" : "\(query)▏"
    }

    var counterText: String? { commandInput == nil ? String(max(0, matchCount)) : nil }

    /// Contenu commun au dessin et à la géométrie du panneau.
    var messageTextLines: [String] {
        switch message {
        case .info(let lines): return Array(lines.prefix(SearchBarLayout.maxMessageLines))
        case .error(let text, let usage): return [text] + (usage.map { ["Usage : \($0)"] } ?? [])
        case nil: return []
        }
    }

    /// Même géométrie pour le dessin et les clics, y compris après un réglage de police.
    func layout(in bounds: CGRect, style: TargetOverlayStyle) -> SearchBarLayout {
        if richRows {
            let metrics = LauncherRowMetrics(fontSize: style.commandTextFontSize)
            let heights = suggestions.map { $0.kind == .header ? metrics.header : metrics.row }
            return SearchBarLayout.makeRich(bounds: bounds, heights: heights, selected: selectedSuggestion,
                                            searchTextFontSize: style.searchTextFontSize)
        }
        return SearchBarLayout.make(bounds: bounds, suggestions: suggestions.count,
                                    messageLines: messageTextLines.count, searchTextFontSize: style.searchTextFontSize,
                                    commandTextFontSize: style.commandTextFontSize)
    }
}

/// Proportions d'une ligne du lanceur, communes à la géométrie et au dessin : comme chez Alfred,
/// l'icône fait environ deux fois la hauteur du nom et le chemin reste nettement plus petit.
struct LauncherRowMetrics: Equatable {
    let title: CGFloat
    let detail: CGFloat
    let row: CGFloat
    let header: CGFloat
    let icon: CGFloat

    init(fontSize: CGFloat) {
        title = min(48, max(8, fontSize))
        detail = max(10, (title * 0.62).rounded())
        row = max(40, (title * 2.5).rounded())
        header = max(20, (title * 1.25).rounded())
        icon = row - 8
    }
}

/// Réserve le compteur à droite ; le texte long ne peut ni le recouvrir ni déplacer son cadre.
struct SearchBarContentLayout: Equatable {
    var input: CGRect
    var counter: CGRect?

    static func make(bar: CGRect, counterSize: CGSize?) -> Self {
        let inner = bar.insetBy(dx: min(16, bar.width / 8), dy: min(6, bar.height / 4))
        guard let counterSize else { return Self(input: inner, counter: nil) }
        let width = min(inner.width / 2, counterSize.width + 20)
        let height = min(inner.height, counterSize.height + 6)
        let counter = CGRect(x: inner.maxX - width, y: inner.midY - height / 2, width: width, height: height)
        let gap = min(12, max(0, counter.minX - inner.minX))
        let input = CGRect(x: inner.minX, y: inner.minY, width: max(0, counter.minX - gap - inner.minX), height: inner.height)
        return Self(input: input, counter: counter)
    }
}

/// Dessin AppKit de la barre Caps+F, réutilisé pour les rendus hors écran. O(s + m), au plus 20 lignes.
@MainActor
enum SearchBarRenderer {
    static func inputFrame(_ state: TargetSearchBar, bar: CGRect, style: TargetOverlayStyle) -> CGRect {
        let font = font(family: style.searchFontFamily, size: style.searchTextFontSize)
        return contentLayout(counter: counter(state, font: font), isLoading: state.isLoading, bar: bar).input
    }

    private static func counter(_ state: TargetSearchBar, font: NSFont) -> NSAttributedString? {
        state.counterText.map {
            line($0, font: NSFontManager.shared.convert(font, toSize: max(8, font.pointSize - 2)),
                 color: NSColor(calibratedWhite: 0.72, alpha: 1))
        }
    }

    private static func contentLayout(counter: NSAttributedString?, isLoading: Bool, bar: CGRect) -> SearchBarContentLayout {
        let size = counter.map { text in
            let size = text.size()
            return CGSize(width: size.width + (isLoading ? 10 : 0), height: size.height)
        }
        return SearchBarContentLayout.make(bar: bar, counterSize: size)
    }

    static func draw(_ state: TargetSearchBar, in bounds: CGRect, style: TargetOverlayStyle) {
        // Résoudre les deux familles une fois par dessin, hors des boucles de suggestions.
        let inputFont = font(family: style.searchFontFamily, size: style.searchTextFontSize)
        let commandFont = font(family: style.commandFontFamily, size: style.commandTextFontSize)
        let messageColor: NSColor = if case .error = state.message { .systemRed } else { .white }
        let messages = state.messageTextLines.map { line($0, font: commandFont, color: messageColor) }
        let layout = state.layout(in: bounds, style: style)
        guard layout.bar.width > 0, layout.bar.height > 0 else { return }
        drawSurface(layout.bar)
        let counter = counter(state, font: inputFont)
        let content = contentLayout(counter: counter, isLoading: state.isLoading, bar: layout.bar)
        let placeholder = state.commandInput == nil && state.properties == nil && state.query.isEmpty
        let text = line(state.inputText, font: inputFont,
                        color: NSColor(calibratedWhite: placeholder ? 0.52 : 0.94, alpha: 1), truncation: .byTruncatingHead)
        if !state.usesNativeInput { draw(text, in: content.input) }
        if let counter, let rect = content.counter {
            NSColor.white.withAlphaComponent(0.08).setFill()
            NSBezierPath(roundedRect: rect, xRadius: rect.height / 2, yRadius: rect.height / 2).fill()
            var textRect = rect.insetBy(dx: min(6, rect.width / 4), dy: 0)
            if state.isLoading {
                let diameter = min(4, rect.width / 8, rect.height / 2)
                let dot = CGRect(x: rect.minX + min(8, rect.width / 4), y: rect.midY - diameter / 2,
                                 width: diameter, height: diameter)
                NSColor.white.withAlphaComponent(0.55).setFill()
                NSBezierPath(ovalIn: dot).fill()
                let inset = min(10, textRect.width / 2)
                textRect.origin.x += inset
                textRect.size.width -= inset
            }
            draw(counter, in: textRect, centered: true)
        }
        guard let panel = layout.panel else { return }
        drawSurface(panel)
        let shown = layout.visibleRange(count: state.suggestions.count, selected: state.selectedSuggestion)
        if state.richRows {
            let metrics = LauncherRowMetrics(fontSize: style.commandTextFontSize)
            for (row, index) in zip(layout.suggestionRows, shown) {
                drawRich(state.suggestions[index], in: row, selected: index == state.selectedSuggestion, font: commandFont, metrics: metrics)
            }
            return
        }
        for (row, index) in zip(layout.suggestionRows, shown) {
            if index == state.selectedSuggestion {
                NSColor.white.withAlphaComponent(0.08).setFill()
                NSBezierPath(roundedRect: row.insetBy(dx: -6, dy: 1), xRadius: 6, yRadius: 6).fill()
            }
            let suggestion = state.suggestions[index]
            var textRow = row
            if let image = icon(suggestion.icon) {
                let side = min(row.height - 4, 18)
                image.draw(in: CGRect(x: row.minX, y: row.midY - side / 2, width: side, height: side))
                textRow = CGRect(x: row.minX + side + 8, y: row.minY, width: max(0, row.width - side - 8), height: row.height)
            }
            draw(suggestionLine(suggestion, font: commandFont), in: textRow)
        }
        for (row, message) in zip(layout.messageRows, messages) { draw(message, in: row) }
    }

    private static func drawSurface(_ rect: CGRect) {
        let path = NSBezierPath(roundedRect: rect, xRadius: 12, yRadius: 12)
        NSColor(calibratedWhite: 0.10, alpha: 0.96).setFill()
        path.fill()
        NSColor.white.withAlphaComponent(0.18).setStroke()
        path.lineWidth = 0.5
        path.stroke()
    }

    /// O(1) : AppKit résout la famille ; une famille absente garde la taille et utilise le système.
    static func font(family: String, size: CGFloat) -> NSFont {
        guard family != "system",
              let font = NSFontManager.shared.font(withFamily: family, traits: [], weight: 5, size: size) else {
            return NSFont.systemFont(ofSize: size, weight: .regular)
        }
        return font
    }

    private static func line(_ text: String, font: NSFont, color: NSColor,
                             truncation: NSLineBreakMode = .byTruncatingTail) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = truncation
        return NSAttributedString(string: text.components(separatedBy: .newlines).joined(separator: " "), attributes: [
            .font: font,
            .foregroundColor: color, .paragraphStyle: paragraph,
        ])
    }

    /// Ligne du lanceur à la manière d'Alfred : grande icône, nom en graisse normale et chemin plus
    /// petit serrés l'un sous l'autre, sélection pleine largeur en couleur d'accent, rappel des touches.
    private static func drawRich(_ suggestion: SlashSuggestion, in row: CGRect, selected: Bool, font: NSFont, metrics: LauncherRowMetrics) {
        let fonts = NSFontManager.shared
        let iconX = row.minX + 4
        let textX = iconX + metrics.icon + 10
        if suggestion.kind == .header {
            let small = fonts.convert(fonts.convert(font, toSize: max(9, metrics.detail - 1)), toHaveTrait: .boldFontMask)
            let text = NSMutableAttributedString(attributedString: line(suggestion.text.uppercased(), font: small,
                                                                        color: NSColor(calibratedWhite: 0.52, alpha: 1)))
            text.addAttribute(.kern, value: 0.8, range: NSRange(location: 0, length: text.length))
            let height = text.size().height
            draw(text, in: CGRect(x: iconX + 2, y: row.minY + 2, width: row.width - 8, height: height + 2))
            return
        }
        if selected {
            NSColor.controlAccentColor.withAlphaComponent(0.9).setFill()
            NSBezierPath(roundedRect: row.insetBy(dx: -4, dy: 1), xRadius: 9, yRadius: 9).fill()
        }
        let side = metrics.icon
        let iconRect = CGRect(x: iconX, y: row.midY - side / 2, width: side, height: side)
        switch suggestion.icon {
        case .file?:
            icon(suggestion.icon)?.draw(in: iconRect, from: .zero, operation: .sourceOver, fraction: 1,
                                        respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high.rawValue])
        case .symbol?:
            // Tuile de la taille d'une icône d'application : même poids visuel dans la liste.
            let tile = iconRect.insetBy(dx: side * 0.06, dy: side * 0.06)
            NSColor.white.withAlphaComponent(selected ? 0.2 : 0.1).setFill()
            NSBezierPath(roundedRect: tile, xRadius: tile.width * 0.24, yRadius: tile.width * 0.24).fill()
            if let image = icon(suggestion.icon) {
                let box = side * 0.5
                let scale = min(box / max(1, image.size.width), box / max(1, image.size.height))
                let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
                image.draw(in: CGRect(x: tile.midX - size.width / 2, y: tile.midY - size.height / 2, width: size.width, height: size.height))
            }
        case .window(let id, let app)?:
            drawWindow(WindowID(rawValue: id), app: app, in: iconRect)
        case nil:
            break
        }
        // Ligne choisie : Tab et Retour ; les autres, leur ⌘ + chiffre (SPEC-075).
        let hint = selected ? line("⇥ actions   ↩", font: fonts.convert(font, toSize: metrics.detail),
                                   color: NSColor.white.withAlphaComponent(0.75))
            : suggestion.shortcut.isEmpty ? nil : line(suggestion.shortcut, font: fonts.convert(font, toSize: metrics.detail),
                                                       color: NSColor(calibratedWhite: 0.5, alpha: 1))
        let hintWidth = hint.map { $0.size().width + 12 } ?? 0
        let width = max(0, row.maxX - 8 - hintWidth - textX)
        let title = line(suggestion.text.trimmingCharacters(in: .whitespaces), font: fonts.convert(font, toSize: metrics.title),
                         color: NSColor(calibratedWhite: 0.97, alpha: 1))
        if suggestion.detail.isEmpty {
            draw(title, in: CGRect(x: textX, y: row.minY, width: width, height: row.height))
        } else {
            let detail = line(suggestion.detail, font: fonts.convert(font, toSize: metrics.detail),
                              color: selected ? NSColor.white.withAlphaComponent(0.78) : NSColor(calibratedWhite: 0.58, alpha: 1),
                              truncation: .byTruncatingMiddle)
            // Les deux lignes forment un bloc centré, sans espace entre elles.
            let titleHeight = title.size().height, detailHeight = detail.size().height
            let bottom = row.midY - (titleHeight + detailHeight) / 2
            draw(detail, in: CGRect(x: textX, y: bottom, width: width, height: detailHeight))
            draw(title, in: CGRect(x: textX, y: bottom + detailHeight, width: width, height: titleHeight))
        }
        if let hint { draw(hint, in: CGRect(x: row.maxX - hintWidth, y: row.minY, width: hintWidth, height: row.height)) }
    }

    /// Dernière vignette nette, sinon celle du rail ou du sélecteur ; jamais l'icône de repli du cache.
    /// Remplaçable par les tests de rendu, qui n'ont pas de capture. O(1).
    static var thumbnail: @MainActor (WindowID) -> NSImage? = { id in
        let store = RailThumbnailStore.shared
        return store.detailedImage(for: id)?.image ?? (store.hasCapturedImage(for: id) ? store.cachedImage(for: id) : nil)
    }

    /// Vignette déjà capturée (vue d'ensemble, puis rail et sélecteur) aux proportions de la fenêtre,
    /// avec la pastille de son application ; sans vignette, l'icône de l'application. Ne capture jamais.
    private static func drawWindow(_ id: WindowID, app: String?, in rect: CGRect) {
        let appIcon = icon(app.map(SlashSuggestion.Icon.file))
        guard let thumbnail = thumbnail(id), thumbnail.size.width > 0, thumbnail.size.height > 0 else {
            appIcon?.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true,
                          hints: [.interpolation: NSImageInterpolation.high.rawValue])
            return
        }
        let scale = min(rect.width / thumbnail.size.width, rect.height / thumbnail.size.height)
        let size = CGSize(width: thumbnail.size.width * scale, height: thumbnail.size.height * scale)
        let frame = CGRect(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2, width: size.width, height: size.height)
        let path = NSBezierPath(roundedRect: frame, xRadius: 4, yRadius: 4)
        NSGraphicsContext.saveGraphicsState()
        path.addClip()
        thumbnail.draw(in: frame, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true,
                       hints: [.interpolation: NSImageInterpolation.high.rawValue])
        NSGraphicsContext.restoreGraphicsState()
        NSColor.white.withAlphaComponent(0.25).setStroke()
        path.lineWidth = 0.5
        path.stroke()
        if let appIcon {
            let badge = rect.width * 0.46
            appIcon.draw(in: CGRect(x: rect.maxX - badge * 0.8, y: rect.minY - badge * 0.15, width: badge, height: badge),
                         from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true,
                         hints: [.interpolation: NSImageInterpolation.high.rawValue])
        }
    }

    /// Icônes des lignes du lanceur, gardées pendant la vie du processus. O(1) après la première lecture.
    private static var icons: [SlashSuggestion.Icon: NSImage] = [:]

    private static func icon(_ icon: SlashSuggestion.Icon?) -> NSImage? {
        guard let icon else { return nil }
        if let cached = icons[icon] { return cached }
        let image: NSImage? = switch icon {
        // Lien résolu : sans la flèche d'alias (Safari est un lien vers le système).
        case .file(let path): NSWorkspace.shared.icon(forFile: URL(fileURLWithPath: path).resolvingSymlinksInPath().path)
        case .window(_, let app): app.map { NSWorkspace.shared.icon(forFile: URL(fileURLWithPath: $0).resolvingSymlinksInPath().path) }
        case .symbol(let name): NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 64, weight: .regular)
                .applying(.init(paletteColors: [NSColor(calibratedWhite: 0.9, alpha: 1)])))
        }
        icons[icon] = image
        return image
    }

    private static func suggestionLine(_ suggestion: SlashSuggestion, font: NSFont) -> NSAttributedString {
        if suggestion.kind == .header {
            let small = NSFontManager.shared.convert(font, toSize: max(8, font.pointSize - 2))
            return line(suggestion.text.uppercased(), font: NSFontManager.shared.convert(small, toHaveTrait: .boldFontMask),
                        color: NSColor(calibratedWhite: 0.5, alpha: 1))
        }
        let name = (suggestion.kind == .command ? "/" : "") + suggestion.text.trimmingCharacters(in: .whitespaces)
        let result = NSMutableAttributedString(attributedString: line(name, font: font, color: NSColor(calibratedWhite: 0.94, alpha: 1)))
        if !suggestion.detail.isEmpty {
            result.append(line("   " + suggestion.detail, font: font, color: NSColor(calibratedWhite: 0.55, alpha: 1)))
        }
        return result
    }

    private static func draw(_ line: NSAttributedString, in rect: CGRect, centered: Bool = false) {
        guard rect.width > 0, rect.height > 0 else { return }
        let size = line.size()
        let width = min(size.width, rect.width)
        let x = centered ? rect.midX - width / 2 : rect.minX
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: rect).addClip()
        line.draw(in: CGRect(x: x, y: rect.midY - size.height / 2, width: width, height: size.height))
        NSGraphicsContext.restoreGraphicsState()
    }
}

