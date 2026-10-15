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

    /// Seules les surfaces visibles gardent la recherche ouverte ; l'espace entre elles reste extérieur.
    func contains(_ point: CGPoint) -> Bool {
        bar.contains(point) || panel?.contains(point) == true
    }

    /// Le clic et le dessin utilisent la même tranche de propositions. O(s), s ≤ 8.
    func suggestionIndex(at point: CGPoint, count: Int, selected: Int?) -> Int? {
        let visible = Self.visibleSuggestions(count: count, selected: selected, rows: suggestionRows.count)
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
        let shown = SearchBarLayout.visibleSuggestions(count: state.suggestions.count,
                                                       selected: state.selectedSuggestion, rows: layout.suggestionRows.count)
        for (row, index) in zip(layout.suggestionRows, shown) {
            if index == state.selectedSuggestion {
                NSColor.white.withAlphaComponent(0.08).setFill()
                NSBezierPath(roundedRect: row.insetBy(dx: -6, dy: 1), xRadius: 6, yRadius: 6).fill()
            }
            draw(suggestionLine(state.suggestions[index], font: commandFont), in: row)
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

    private static func suggestionLine(_ suggestion: SlashSuggestion, font: NSFont) -> NSAttributedString {
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

