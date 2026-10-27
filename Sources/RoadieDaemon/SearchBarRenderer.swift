import AppKit
import RoadieCore

/// Place de la barre (session 102) : en bas (historique, liste au-dessus), au centre ou en haut comme
/// Alfred (liste dessous), ou place retenue après un glisser : centre de la barre en fractions de l'écran,
/// y depuis le bas. La liste s'ouvre du côté où il y a le plus de place.
enum SearchBarPlacement: Equatable, Sendable {
    case bottom, center, top
    case custom(x: CGFloat, y: CGFloat)

    init(setting: String) {
        switch setting {
        case "top": self = .top
        case "center": self = .center
        default: self = .bottom
        }
    }

    /// La liste s'ouvre sous la barre quand celle-ci est dans la moitié haute de l'écran.
    var listBelow: Bool {
        switch self {
        case .bottom: false
        case .center, .top: true
        case .custom(_, let y): y > 0.5
        }
    }

    /// Cadre de la barre, toujours entièrement dans `bounds`. O(1).
    func bar(in bounds: CGRect, width: CGFloat, height: CGFloat) -> CGRect {
        let height = min(bounds.height, height)
        let x: CGFloat, y: CGFloat
        switch self {
        case .bottom:
            x = bounds.midX - width / 2
            y = bounds.minY + min(48, max(0, bounds.height - height))
        case .center:
            x = bounds.midX - width / 2
            y = bounds.midY + bounds.height * 0.1 - height / 2
        case .top:
            x = bounds.midX - width / 2
            y = bounds.maxY - bounds.height * 0.2 - height
        case .custom(let fx, let fy):
            x = bounds.minX + fx * bounds.width - width / 2
            y = bounds.minY + fy * bounds.height - height / 2
        }
        return CGRect(x: min(max(x, bounds.minX), bounds.maxX - width), y: min(max(y, bounds.minY), bounds.maxY - height),
                      width: width, height: height)
    }

    /// Place retenue d'une barre dont le centre est `center`. O(1).
    static func custom(center: CGPoint, in bounds: CGRect) -> SearchBarPlacement {
        guard bounds.width > 0, bounds.height > 0 else { return .bottom }
        return .custom(x: min(1, max(0, (center.x - bounds.minX) / bounds.width)),
                       y: min(1, max(0, (center.y - bounds.minY) / bounds.height)))
    }
}

/// Mise en page de la barre de saisie et de la boîte de commandes (SPEC-023 R4), pure. La barre suit sa
/// place (session 102) ; la liste et le message s'empilent au-dessus d'elle ou dessous, sans sortir de
/// l'écran. Le message, réponse à Retour, est le plus près de la barre quand la liste est au-dessus.
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
    /// `width`, `barHeight` : ceux du thème (session 101) ; `maxRows` : nombre de résultats montrés, 0 sans limite.
    static func make(
        bounds: CGRect, suggestions: Int, messageLines: Int,
        searchTextFontSize: CGFloat = 15, commandTextFontSize: CGFloat = 13,
        width preferredWidth: CGFloat = 640, barHeight preferredHeight: CGFloat? = nil, maxRows: Int = 0,
        placement: SearchBarPlacement = .bottom
    ) -> SearchBarLayout {
        let lineHeight = Self.lineHeight * min(48, max(8, commandTextFontSize)) / 13
        let barHeight = preferredHeight ?? 40 * min(48, max(8, searchTextFontSize)) / 15
        let margin = min(20, bounds.width * 0.05)
        let width = max(0, min(preferredWidth, bounds.width - 2 * margin))
        let bar = placement.bar(in: bounds, width: width, height: barHeight)
        let below = placement.listBelow
        let room = max(0, Int(listRoom(bar: bar, bounds: bounds, below: below) / lineHeight))
        let messageCount = min(messageLines, maxMessageLines, room)
        let suggestionCount = min(suggestions, maxRows > 0 ? maxRows : maxSuggestions, room - messageCount)
        let total = messageCount + suggestionCount
        guard total > 0 else { return SearchBarLayout(bar: bar, panel: nil, suggestionRows: [], messageRows: []) }
        let panel = panelFrame(bar: bar, height: CGFloat(total) * lineHeight + 2 * padding, below: below)
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

    /// Hauteur disponible pour la liste, au-dessus ou au-dessous de la barre. O(1).
    static func listRoom(bar: CGRect, bounds: CGRect, below: Bool) -> CGFloat {
        max(0, (below ? bar.minY - (bounds.minY + 8) : bounds.maxY - 8 - bar.maxY) - gap - 2 * padding)
    }

    /// Fond de la liste collé à la barre, du côté choisi. O(1).
    static func panelFrame(bar: CGRect, height: CGFloat, below: Bool) -> CGRect {
        CGRect(x: bar.minX, y: below ? bar.minY - gap - height : bar.maxY + gap, width: bar.width, height: height)
    }

    /// Tranche montrée, commune au dessin et au clic. O(1).
    func visibleRange(count: Int, selected: Int?) -> Range<Int> {
        if let firstVisible { return firstVisible..<min(count, firstVisible + suggestionRows.count) }
        return Self.visibleSuggestions(count: count, selected: selected, rows: suggestionRows.count)
    }

    /// Liste du lanceur (SPEC-073) : lignes de hauteurs différentes (titres de section fins, résultats
    /// sur deux niveaux). La tranche montrée commence au début et glisse juste assez pour garder la
    /// sélection visible. O(n), n lignes.
    /// `maxRows` borne la hauteur de la liste à autant de lignes de résultat (session 101).
    static func makeRich(bounds: CGRect, heights: [CGFloat], selected: Int?, searchTextFontSize: CGFloat = 15,
                         width: CGFloat = 640, barHeight: CGFloat? = nil, maxRows: Int = 0,
                         placement: SearchBarPlacement = .bottom) -> SearchBarLayout {
        let base = make(bounds: bounds, suggestions: 0, messageLines: 0, searchTextFontSize: searchTextFontSize,
                        width: width, barHeight: barHeight, placement: placement)
        var room = listRoom(bar: base.bar, bounds: bounds, below: placement.listBelow)
        if maxRows > 0, let row = heights.max() { room = min(room, CGFloat(maxRows) * row) }
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
        let panel = panelFrame(bar: base.bar, height: used + 2 * padding, below: placement.listBelow)
        var top = panel.maxY - padding
        let rows = heights[start..<end].map { height -> CGRect in
            top -= height
            return CGRect(x: panel.minX + 10, y: top, width: panel.width - 20, height: height)
        }
        return SearchBarLayout(bar: base.bar, panel: panel, suggestionRows: rows, messageRows: [], firstVisible: start)
    }

    /// Grille d'un workflow (SPEC-092) : un rectangle par tuile montrée, rangée par rangée depuis le
    /// haut ; la grille défile par rangées entières pour garder la tuile choisie visible. `label` :
    /// hauteur des textes sous l'image ; `footer` : une ligne en pied pour la tuile choisie. O(t), t
    /// tuiles montrées.
    static func makeGrid(bounds: CGRect, count: Int, columns: Int, selected: Int?, label: CGFloat = 20, footer: Bool,
                         searchTextFontSize: CGFloat = 15, width: CGFloat = 640, barHeight: CGFloat? = nil,
                         placement: SearchBarPlacement = .bottom) -> SearchBarLayout {
        let base = make(bounds: bounds, suggestions: 0, messageLines: 0, searchTextFontSize: searchTextFontSize,
                        width: width, barHeight: barHeight, placement: placement)
        let columns = max(1, columns)
        guard count > 0, base.bar.width > 2 * padding else { return base }
        let side = min(140, (base.bar.width - 2 * padding - 8) / CGFloat(columns))
        let tile = CGSize(width: side, height: side + label)
        let footerHeight = footer ? lineHeight : 0
        let room = max(0, listRoom(bar: base.bar, bounds: bounds, below: placement.listBelow) - footerHeight)
        let totalRows = (count + columns - 1) / columns
        let shownRows = min(totalRows, max(1, Int(room / tile.height)))
        let selectedRow = min(totalRows - 1, max(0, selected ?? 0) / columns)
        let startRow = min(max(0, selectedRow - shownRows + 1), totalRows - shownRows)
        let panel = panelFrame(bar: base.bar, height: CGFloat(shownRows) * tile.height + 2 * padding + footerHeight,
                               below: placement.listBelow)
        let left = panel.minX + (panel.width - CGFloat(columns) * tile.width) / 2
        var tiles: [CGRect] = []
        for row in 0..<shownRows {
            for column in 0..<columns where (startRow + row) * columns + column < count {
                tiles.append(CGRect(x: left + CGFloat(column) * tile.width, y: panel.maxY - padding - CGFloat(row + 1) * tile.height,
                                    width: tile.width, height: tile.height))
            }
        }
        let footerRows = footer ? [CGRect(x: panel.minX + 12, y: panel.minY + padding, width: panel.width - 24, height: lineHeight)] : []
        return SearchBarLayout(bar: base.bar, panel: panel, suggestionRows: tiles, messageRows: footerRows, firstVisible: startRow * columns)
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
    /// Signal d'une règle à proposer, devant le compteur (« 💡 1 », SPEC-081).
    var chip: String?
    /// Le champ AppKit affiche le texte à l'exécution ; les rendus hors écran le dessinent encore.
    var usesNativeInput = false
    /// Grille d'un workflow (SPEC-092) : tuiles au lieu de lignes.
    var grid: SearchGrid?
    /// Chip de la présentation (session 099), en tête de la pastille du compteur ; un clic la change.
    var viewChip: String?
    /// Place de la barre à l'écran (session 102), commune au dessin et aux clics.
    var placement: SearchBarPlacement = .bottom

    var inputText: String {
        if let commandInput { return "/\(commandInput)▏" }
        if let properties { return properties }
        return query.isEmpty ? "Rechercher ou saisir /commande" : "\(query)▏"
    }

    var counterText: String? {
        guard commandInput == nil else { return nil }
        return ([viewChip, chip].compactMap { $0 } + [String(max(0, matchCount))]).joined(separator: "   ")
    }

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
        let width = CGFloat(style.theme.width)
        let barHeight = style.theme.barHeight(fontSize: style.searchTextFontSize)
        if let grid {
            return SearchBarLayout.makeGrid(bounds: bounds, count: suggestions.count, columns: grid.columns, selected: selectedSuggestion,
                                            label: grid.labelHeight(fontSize: style.commandTextFontSize), footer: grid.footer != nil,
                                            searchTextFontSize: style.searchTextFontSize, width: width, barHeight: barHeight,
                                            placement: placement)
        }
        if richRows {
            let metrics = LauncherRowMetrics(fontSize: style.commandTextFontSize)
            let heights = suggestions.map { $0.kind == .header ? metrics.header : metrics.row }
            return SearchBarLayout.makeRich(bounds: bounds, heights: heights, selected: selectedSuggestion,
                                            searchTextFontSize: style.searchTextFontSize, width: width, barHeight: barHeight,
                                            maxRows: style.maxRows, placement: placement)
        }
        return SearchBarLayout.make(bounds: bounds, suggestions: suggestions.count,
                                    messageLines: messageTextLines.count, searchTextFontSize: style.searchTextFontSize,
                                    commandTextFontSize: style.commandTextFontSize, width: width, barHeight: barHeight,
                                    maxRows: style.maxRows, placement: placement)
    }
}

/// Réglages d'affichage d'une grille (SPEC-092 FR-003) ; `footer` : texte en pied de la tuile choisie.
struct SearchGrid: Equatable {
    var columns: Int
    var showTitles = true
    var showSubtitles = false
    var footer: String?

    /// Titre (et sous-titre) sous l'image, à la taille des détails du lanceur.
    func labelHeight(fontSize: CGFloat) -> CGFloat {
        let line = (LauncherRowMetrics(fontSize: fontSize).detail * 1.35).rounded()
        return (showTitles ? line : 0) + (showSubtitles ? line : 0) + 4
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
        return contentLayout(counter: counter(state, font: font, theme: style.theme), isLoading: state.isLoading, bar: bar).input
    }

    /// Rectangle de la pastille du compteur (et du chip), comme au dessin ; nil sans pastille.
    static func counterFrame(_ state: TargetSearchBar, bar: CGRect, style: TargetOverlayStyle) -> CGRect? {
        let font = font(family: style.searchFontFamily, size: style.searchTextFontSize)
        return contentLayout(counter: counter(state, font: font, theme: style.theme), isLoading: state.isLoading, bar: bar).counter
    }

    /// Le compteur garde la taille du texte de la recherche moins 2 points, plafonnée à 15 : les grands
    /// textes des thèmes d'Alfred ne l'agrandissent pas.
    private static func counter(_ state: TargetSearchBar, font: NSFont, theme: LauncherTheme) -> NSAttributedString? {
        state.counterText.map {
            line($0, font: NSFontManager.shared.convert(font, toSize: max(8, min(15, font.pointSize - 2))),
                 color: theme.ownsSizes ? LauncherTheme.color(theme.headerColor) : NSColor(calibratedWhite: 0.72, alpha: 1))
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
        let theme = style.theme
        let messageColor: NSColor = if case .error = state.message { .systemRed } else { LauncherTheme.color(theme.title.color) }
        let messages = state.messageTextLines.map { line($0, font: commandFont, color: messageColor) }
        let layout = state.layout(in: bounds, style: style)
        guard layout.bar.width > 0, layout.bar.height > 0 else { return }
        drawSurface(layout.bar, theme: theme)
        drawSearchBackground(layout.bar, theme: theme)
        let counter = counter(state, font: inputFont, theme: theme)
        let content = contentLayout(counter: counter, isLoading: state.isLoading, bar: layout.bar)
        let placeholder = state.commandInput == nil && state.properties == nil && state.query.isEmpty
        let inputColor = LauncherTheme.color(theme.searchText.color)
        let text = line(state.inputText, font: inputFont,
                        color: placeholder ? inputColor.withAlphaComponent(inputColor.alphaComponent * 0.55) : inputColor,
                        truncation: .byTruncatingHead)
        if !state.usesNativeInput { draw(text, in: content.input) }
        if let counter, let rect = content.counter {
            inputColor.withAlphaComponent(0.08).setFill()
            NSBezierPath(roundedRect: rect, xRadius: rect.height / 2, yRadius: rect.height / 2).fill()
            var textRect = rect.insetBy(dx: min(6, rect.width / 4), dy: 0)
            if state.isLoading {
                let diameter = min(4, rect.width / 8, rect.height / 2)
                let dot = CGRect(x: rect.minX + min(8, rect.width / 4), y: rect.midY - diameter / 2,
                                 width: diameter, height: diameter)
                inputColor.withAlphaComponent(0.55).setFill()
                NSBezierPath(ovalIn: dot).fill()
                let inset = min(10, textRect.width / 2)
                textRect.origin.x += inset
                textRect.size.width -= inset
            }
            draw(counter, in: textRect, centered: true)
        }
        guard let panel = layout.panel else { return }
        drawSurface(panel, theme: theme)
        let shown = layout.visibleRange(count: state.suggestions.count, selected: state.selectedSuggestion)
        if let grid = state.grid {
            let metrics = LauncherRowMetrics(fontSize: style.commandTextFontSize)
            for (rect, index) in zip(layout.suggestionRows, shown) {
                drawTile(state.suggestions[index], in: rect, selected: index == state.selectedSuggestion, grid: grid, font: commandFont,
                         metrics: metrics, theme: theme)
            }
            if let footer = grid.footer, let row = layout.messageRows.first {
                draw(line(footer, font: NSFontManager.shared.convert(commandFont, toSize: metrics.detail),
                          color: LauncherTheme.color(theme.subtitle.color), truncation: .byTruncatingMiddle), in: row, centered: true)
            }
            return
        }
        if state.richRows {
            let metrics = LauncherRowMetrics(fontSize: style.commandTextFontSize)
            for (row, index) in zip(layout.suggestionRows, shown) {
                drawRich(state.suggestions[index], in: row, selected: index == state.selectedSuggestion, font: commandFont,
                         metrics: metrics, theme: theme)
            }
            return
        }
        for (row, index) in zip(layout.suggestionRows, shown) {
            if index == state.selectedSuggestion {
                (theme.ownsSizes ? LauncherTheme.color(theme.selectedBackground) : NSColor.white.withAlphaComponent(0.08)).setFill()
                NSBezierPath(roundedRect: row.insetBy(dx: -6, dy: 1), xRadius: 6, yRadius: 6).fill()
            }
            let suggestion = state.suggestions[index]
            var textRow = row
            if let image = icon(suggestion.icon, tint: symbolTint(theme)) {
                let side = min(row.height - 4, 18)
                image.draw(in: CGRect(x: row.minX, y: row.midY - side / 2, width: side, height: side))
                textRow = CGRect(x: row.minX + side + 8, y: row.minY, width: max(0, row.width - side - 8), height: row.height)
            }
            draw(suggestionLine(suggestion, font: commandFont, theme: theme, selected: index == state.selectedSuggestion), in: textRow)
        }
        for (row, message) in zip(layout.messageRows, messages) { draw(message, in: row) }
    }

    /// Fond et contour du thème ; le flou éventuel est posé dessous par la fenêtre (`SearchBarBlur`).
    private static func drawSurface(_ rect: CGRect, theme: LauncherTheme) {
        let radius = min(CGFloat(theme.roundness), rect.height / 2)
        let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
        LauncherTheme.color(theme.windowColor).setFill()
        path.fill()
        LauncherTheme.color(theme.borderColor).setStroke()
        path.lineWidth = theme.borderWidth > 0 ? min(CGFloat(theme.borderWidth), rect.height / 4) : 0.5
        path.stroke()
    }

    /// Fond du champ de saisie d'un thème d'Alfred, en retrait du bord de la barre. Rien s'il est transparent.
    private static func drawSearchBackground(_ bar: CGRect, theme: LauncherTheme) {
        let color = LauncherTheme.color(theme.searchBackground)
        guard color.alphaComponent > 0 else { return }
        let rect = bar.insetBy(dx: min(8, bar.width / 8), dy: min(6, bar.height / 4))
        let radius = min(CGFloat(theme.searchRoundness), rect.height / 2)
        color.setFill()
        NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
    }

    /// O(1) : AppKit résout la famille ; une famille absente garde la taille et utilise le système.
    /// `System` et `System Light` : noms des polices système dans les thèmes d'Alfred.
    static func font(family: String, size: CGFloat) -> NSFont {
        if family.lowercased() == "system light" { return NSFont.systemFont(ofSize: size, weight: .light) }
        guard family.lowercased() != "system",
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
    private static func drawRich(_ suggestion: SlashSuggestion, in row: CGRect, selected: Bool, font: NSFont, metrics: LauncherRowMetrics,
                                 theme: LauncherTheme = .roadie) {
        let titleColor = LauncherTheme.color(selected ? theme.title.colorSelected : theme.title.color)
        let fonts = NSFontManager.shared
        let iconX = row.minX + 4
        let textX = iconX + metrics.icon + 10
        if suggestion.kind == .header {
            let small = fonts.convert(fonts.convert(font, toSize: max(9, metrics.detail - 1)), toHaveTrait: .boldFontMask)
            let text = NSMutableAttributedString(attributedString: line(suggestion.text.uppercased(), font: small,
                                                                        color: theme.ownsSizes ? LauncherTheme.color(theme.headerColor) : NSColor(calibratedWhite: 0.52, alpha: 1)))
            text.addAttribute(.kern, value: 0.8, range: NSRange(location: 0, length: text.length))
            let height = text.size().height
            draw(text, in: CGRect(x: iconX + 2, y: row.minY + 2, width: row.width - 8, height: height + 2))
            return
        }
        if selected {
            LauncherTheme.color(theme.selectedBackground).setFill()
            let radius = CGFloat(theme.rowRoundness)
            NSBezierPath(roundedRect: row.insetBy(dx: -4, dy: 1), xRadius: radius, yRadius: radius).fill()
        }
        let side = metrics.icon
        let iconRect = CGRect(x: iconX, y: row.midY - side / 2, width: side, height: side)
        switch suggestion.icon {
        case .file?, .image?:
            icon(suggestion.icon)?.draw(in: iconRect, from: .zero, operation: .sourceOver, fraction: 1,
                                        respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high.rawValue])
        case .symbol?:
            // Tuile de la taille d'une icône d'application : même poids visuel dans la liste.
            let tile = iconRect.insetBy(dx: side * 0.06, dy: side * 0.06)
            titleColor.withAlphaComponent(selected ? 0.2 : 0.1).setFill()
            NSBezierPath(roundedRect: tile, xRadius: tile.width * 0.24, yRadius: tile.width * 0.24).fill()
            if let image = icon(suggestion.icon, tint: symbolTint(theme)) {
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
                                   color: LauncherTheme.color(theme.shortcut.colorSelected))
            : suggestion.shortcut.isEmpty ? nil : line(suggestion.shortcut, font: fonts.convert(font, toSize: metrics.detail),
                                                       color: LauncherTheme.color(theme.shortcut.color))
        // Pastille de la lettre Maj (SPEC-084), au-dessus du rappel de touche.
        let letter = suggestion.letter.isEmpty ? nil
            : line(suggestion.letter, font: fonts.convert(fonts.convert(font, toSize: metrics.detail), toHaveTrait: .boldFontMask),
                   color: titleColor)
        let chip = letter.map { CGSize(width: $0.size().width + 10, height: $0.size().height + 2) }
        let hintWidth = max(hint.map { $0.size().width + 12 } ?? 0, chip.map { $0.width + 12 } ?? 0)
        let width = max(0, row.maxX - 8 - hintWidth - textX)
        let title = line(suggestion.text.trimmingCharacters(in: .whitespaces), font: fonts.convert(font, toSize: metrics.title),
                         color: titleColor)
        if suggestion.detail.isEmpty {
            draw(title, in: CGRect(x: textX, y: row.minY, width: width, height: row.height))
        } else {
            let detail = line(suggestion.detail, font: fonts.convert(font, toSize: metrics.detail),
                              color: LauncherTheme.color(selected ? theme.subtitle.colorSelected : theme.subtitle.color),
                              truncation: .byTruncatingMiddle)
            // Les deux lignes forment un bloc centré, sans espace entre elles.
            let titleHeight = title.size().height, detailHeight = detail.size().height
            let bottom = row.midY - (titleHeight + detailHeight) / 2
            draw(detail, in: CGRect(x: textX, y: bottom, width: width, height: detailHeight))
            draw(title, in: CGRect(x: textX, y: bottom + detailHeight, width: width, height: titleHeight))
        }
        guard let letter, let chip else {
            if let hint { draw(hint, in: CGRect(x: row.maxX - hintWidth, y: row.minY, width: hintWidth, height: row.height)) }
            return
        }
        // Pastille en haut, rappel en bas, calés à droite comme les autres rappels ; sans rappel, la
        // pastille est centrée en hauteur. Repère non retourné : y monte.
        let right = row.maxX - 12
        let hintSize = hint?.size() ?? .zero
        let top = row.midY + (chip.height + hintSize.height) / 2
        let capsule = CGRect(x: right - chip.width, y: top - chip.height, width: chip.width, height: chip.height)
        titleColor.withAlphaComponent(selected ? 0.28 : 0.16).setFill()
        NSBezierPath(roundedRect: capsule, xRadius: chip.height / 2, yRadius: chip.height / 2).fill()
        draw(letter, in: capsule, centered: true)
        if let hint { draw(hint, in: CGRect(x: right - hintSize.width, y: capsule.minY - hintSize.height, width: hintSize.width, height: hintSize.height)) }
    }

    /// Tuile d'une grille (SPEC-092) : image ajustée sans déformation (research R5), titre et sous-titre
    /// centrés dessous ; une tuile sans titre ni icône (espaceur) reste vide.
    private static func drawTile(_ suggestion: SlashSuggestion, in rect: CGRect, selected: Bool, grid: SearchGrid, font: NSFont,
                                 metrics: LauncherRowMetrics, theme: LauncherTheme = .roadie) {
        let label = grid.labelHeight(fontSize: metrics.title)
        let cell = rect.insetBy(dx: 3, dy: 3)
        if selected {
            LauncherTheme.color(theme.selectedBackground).setFill()
            let radius = max(CGFloat(theme.rowRoundness), 4)
            NSBezierPath(roundedRect: cell, xRadius: radius, yRadius: radius).fill()
        }
        let box = CGRect(x: cell.minX + 6, y: cell.minY + label, width: cell.width - 12, height: max(0, cell.height - label - 6))
        if let image = icon(suggestion.icon, tint: symbolTint(theme)), image.size.width > 0, image.size.height > 0 {
            let scale = min(box.width / image.size.width, box.height / image.size.height)
            let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            image.draw(in: CGRect(x: box.midX - size.width / 2, y: box.midY - size.height / 2, width: size.width, height: size.height),
                       from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true,
                       hints: [.interpolation: NSImageInterpolation.high.rawValue])
        }
        let fonts = NSFontManager.shared
        let small = fonts.convert(font, toSize: metrics.detail)
        var top = box.minY
        for (text, shown, color) in [(suggestion.text, grid.showTitles, LauncherTheme.color(selected ? theme.title.colorSelected : theme.title.color)),
                                     (suggestion.detail, grid.showSubtitles, LauncherTheme.color(selected ? theme.subtitle.colorSelected : theme.subtitle.color))]
        where shown {
            let height = (metrics.detail * 1.35).rounded()
            top -= height
            if !text.isEmpty { draw(line(text, font: small, color: color), in: CGRect(x: cell.minX + 2, y: top, width: cell.width - 4, height: height), centered: true) }
        }
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
    /// Un symbole se teinte à la couleur du thème (session 101) : la teinte fait partie de la clé.
    private struct IconKey: Hashable {
        let icon: SlashSuggestion.Icon
        let tint: String
    }

    private static var icons: [IconKey: NSImage] = [:]

    private static func symbolTint(_ theme: LauncherTheme) -> String {
        theme.ownsSizes ? theme.title.color : "#E6E6E6FF"
    }

    private static func icon(_ icon: SlashSuggestion.Icon?, tint: String = "#E6E6E6FF") -> NSImage? {
        guard let icon else { return nil }
        let key = IconKey(icon: icon, tint: tint)
        if let cached = icons[key] { return cached }
        let image: NSImage? = switch icon {
        // Lien résolu : sans la flèche d'alias (Safari est un lien vers le système).
        case .file(let path): NSWorkspace.shared.icon(forFile: URL(fileURLWithPath: path).resolvingSymlinksInPath().path)
        case .window(_, let app): app.map { NSWorkspace.shared.icon(forFile: URL(fileURLWithPath: $0).resolvingSymlinksInPath().path) }
        case .image(let path): thumbnailImage(path)
        case .symbol(let name): NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 64, weight: .regular)
                .applying(.init(paletteColors: [LauncherTheme.color(tint)])))
        }
        icons[key] = image
        return image
    }

    /// Vignette d'une image (512 points au plus) : une photo lourde n'est pas chargée en entier pour une
    /// tuile ; repli sur l'image si macOS ne sait pas la réduire (session 099). O(taille de la vignette).
    nonisolated static func thumbnailImage(_ path: String, maxPixels: Int = 512) -> NSImage? {
        let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageIfAbsent: true, kCGImageSourceCreateThumbnailWithTransform: true,
                                        kCGImageSourceThumbnailMaxPixelSize: maxPixels]
        guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return NSImage(contentsOfFile: path) }
        return NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
    }

    private static func suggestionLine(_ suggestion: SlashSuggestion, font: NSFont, theme: LauncherTheme = .roadie,
                                       selected: Bool = false) -> NSAttributedString {
        // `roadie` garde ses gris d'origine ; un thème d'Alfred donne ses couleurs, sélection comprise.
        let alfred = theme.ownsSizes
        if suggestion.kind == .header {
            let small = NSFontManager.shared.convert(font, toSize: max(8, font.pointSize - 2))
            return line(suggestion.text.uppercased(), font: NSFontManager.shared.convert(small, toHaveTrait: .boldFontMask),
                        color: alfred ? LauncherTheme.color(theme.headerColor) : NSColor(calibratedWhite: 0.5, alpha: 1))
        }
        let name = (suggestion.kind == .command ? "/" : "") + suggestion.text.trimmingCharacters(in: .whitespaces)
        let nameColor = alfred ? LauncherTheme.color(selected ? theme.title.colorSelected : theme.title.color) : NSColor(calibratedWhite: 0.94, alpha: 1)
        let result = NSMutableAttributedString(attributedString: line(name, font: font, color: nameColor))
        if !suggestion.detail.isEmpty {
            let detailColor = alfred ? LauncherTheme.color(selected ? theme.subtitle.colorSelected : theme.subtitle.color)
                : NSColor(calibratedWhite: 0.55, alpha: 1)
            result.append(line("   " + suggestion.detail, font: font, color: detailColor))
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

