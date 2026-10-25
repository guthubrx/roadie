import AppKit

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
            let scale = min(48, max(8, style.commandTextFontSize)) / 13
            let heights = suggestions.map { $0.kind == .header ? 24 * scale : 46 * scale }
            return SearchBarLayout.makeRich(bounds: bounds, heights: heights, selected: selectedSuggestion,
                                            searchTextFontSize: style.searchTextFontSize)
        }
        return SearchBarLayout.make(bounds: bounds, suggestions: suggestions.count,
                                    messageLines: messageTextLines.count, searchTextFontSize: style.searchTextFontSize,
                                    commandTextFontSize: style.commandTextFontSize)
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
            for (row, index) in zip(layout.suggestionRows, shown) {
                drawRich(state.suggestions[index], in: row, selected: index == state.selectedSuggestion, font: commandFont)
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

    /// Ligne du lanceur à la manière d'Alfred : icône de 32 points, nom puis détail plus petit dessous,
    /// sélection pleine largeur en couleur d'accent avec le rappel des touches à droite.
    private static func drawRich(_ suggestion: SlashSuggestion, in row: CGRect, selected: Bool, font: NSFont) {
        if suggestion.kind == .header {
            let small = NSFontManager.shared.convert(NSFontManager.shared.convert(font, toSize: max(8, font.pointSize - 2.5)), toHaveTrait: .boldFontMask)
            let text = line(suggestion.text.uppercased(), font: small, color: NSColor(calibratedWhite: 0.5, alpha: 1))
            draw(text, in: CGRect(x: row.minX + 6, y: row.minY, width: row.width - 12, height: row.height * 0.8))
            return
        }
        if selected {
            NSColor.controlAccentColor.withAlphaComponent(0.88).setFill()
            NSBezierPath(roundedRect: row.insetBy(dx: -4, dy: 1.5), xRadius: 8, yRadius: 8).fill()
        }
        let side = min(32, row.height - 10)
        var textX = row.minX + 8
        if let image = icon(suggestion.icon) {
            let isSymbol = if case .symbol = suggestion.icon { true } else { false }
            let drawn = isSymbol ? side * 0.7 : side
            image.draw(in: CGRect(x: textX + (side - drawn) / 2, y: row.midY - drawn / 2, width: drawn, height: drawn))
            textX += side + 12
        }
        let hint = selected ? line("⇥ actions   ↩", font: NSFontManager.shared.convert(font, toSize: max(8, font.pointSize - 2)),
                                   color: NSColor.white.withAlphaComponent(0.7)) : nil
        let hintWidth = hint.map { $0.size().width + 8 } ?? 0
        let width = max(0, row.maxX - 8 - hintWidth - textX)
        let titleFont = NSFontManager.shared.convert(NSFontManager.shared.convert(font, toSize: font.pointSize + 2.5), toHaveTrait: .boldFontMask)
        let detailFont = NSFontManager.shared.convert(font, toSize: max(8, font.pointSize - 1.5))
        let title = line(suggestion.text.trimmingCharacters(in: .whitespaces), font: titleFont, color: .white)
        if suggestion.detail.isEmpty {
            draw(title, in: CGRect(x: textX, y: row.minY, width: width, height: row.height))
        } else {
            let detail = line(suggestion.detail, font: detailFont,
                              color: selected ? NSColor.white.withAlphaComponent(0.8) : NSColor(calibratedWhite: 0.6, alpha: 1),
                              truncation: .byTruncatingMiddle)
            draw(title, in: CGRect(x: textX, y: row.midY, width: width, height: row.height / 2 - 2))
            draw(detail, in: CGRect(x: textX, y: row.minY + 3, width: width, height: row.height / 2 - 3))
        }
        if let hint { draw(hint, in: CGRect(x: row.maxX - hintWidth, y: row.minY, width: hintWidth, height: row.height)) }
    }

    /// Icônes des lignes du lanceur, gardées pendant la vie du processus. O(1) après la première lecture.
    private static var icons: [SlashSuggestion.Icon: NSImage] = [:]

    private static func icon(_ icon: SlashSuggestion.Icon?) -> NSImage? {
        guard let icon else { return nil }
        if let cached = icons[icon] { return cached }
        let image: NSImage? = switch icon {
        case .file(let path): NSWorkspace.shared.icon(forFile: path)
        case .symbol(let name): NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(paletteColors: [NSColor(calibratedWhite: 0.8, alpha: 1)]))
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

