import AppKit
import Foundation
import RoadieCore

/// Navigateur SF Symbols (session 131), sur le modèle de l'exemple d'Alfred 6 regardé sur alfredapp.com/v6 : champ
/// de recherche, grille de 6 colonnes, sélection turquoise, nom et catégories sous la grille, à droite l'aperçu en
/// quatre tailles et la version minimale de chaque système. Données de macOS (`CoreGlyphs.bundle`).
enum LauncherSymbols {
    struct Symbol: Equatable, Sendable {
        let name: String
        let categories: [String]
        let keywords: [String]
        /// Année d'apparition dans SF Symbols (« 2019 », « 2023.2 »).
        let release: String
    }

    struct Catalog: Sendable {
        /// Dans l'ordre de l'app SF Symbols.
        let symbols: [Symbol]
        /// Année → versions minimales (`macOS`, `iOS`, `watchOS`, `tvOS`, `visionOS`).
        let releases: [String: [String: String]]

        static let empty = Catalog(symbols: [], releases: [:])
    }

    static let resources = URL(fileURLWithPath: "/System/Library/CoreServices/CoreGlyphs.bundle/Contents/Resources")

    /// Préfixes qui ouvrent le navigateur, en français et en anglais.
    static let keywords = ["symbols", "symboles", "sf"]

    /// Recherche tapée après `symbols ` ; nil sinon. O(t).
    static func query(_ text: String) -> String? {
        let lower = text.lowercased()
        for keyword in keywords where lower == keyword || lower.hasPrefix(keyword + " ") {
            return String(text.dropFirst(keyword.count)).trimmingCharacters(in: .whitespaces)
        }
        return nil
    }

    /// Catalogue lu dans les fichiers de macOS ; vide si absents. O(s).
    static func load(from folder: URL = resources) -> Catalog {
        func plist(_ name: String) -> Any? {
            guard let data = try? Data(contentsOf: folder.appendingPathComponent(name)) else { return nil }
            return try? PropertyListSerialization.propertyList(from: data, format: nil)
        }
        let availability = plist("name_availability.plist") as? [String: Any] ?? [:]
        let years = availability["symbols"] as? [String: String] ?? [:]
        let releases = availability["year_to_release"] as? [String: [String: String]] ?? [:]
        let categories = plist("symbol_categories.plist") as? [String: [String]] ?? [:]
        let search = plist("symbol_search.plist") as? [String: [String]] ?? [:]
        let order = plist("symbol_order.plist") as? [String] ?? []
        var seen = Set<String>()
        let names = (order + years.keys.sorted()).filter { years[$0] != nil && seen.insert($0).inserted }
        let symbols = names.map { Symbol(name: $0, categories: categories[$0] ?? [], keywords: search[$0] ?? [], release: years[$0] ?? "") }
        return Catalog(symbols: symbols, releases: releases)
    }

    /// Symboles qui correspondent : nom commençant par la saisie, puis nom la contenant, puis mot-clé ou catégorie ;
    /// ordre de l'app à égalité ; tous sans saisie. O(s × k).
    static func search(_ query: String, in symbols: [Symbol], limit: Int = 600) -> [Symbol] {
        let needle = query.lowercased().trimmingCharacters(in: .whitespaces)
        guard !needle.isEmpty else { return Array(symbols.prefix(limit)) }
        var ranked: [(symbol: Symbol, score: Int, index: Int)] = []
        for (index, symbol) in symbols.enumerated() {
            let score: Int
            if symbol.name.hasPrefix(needle) { score = 3 }
            else if symbol.name.contains(needle) { score = 2 }
            else if symbol.keywords.contains(where: { $0.contains(needle) }) || symbol.categories.contains(where: { categoryName($0).lowercased().contains(needle) }) { score = 1 }
            else { continue }
            ranked.append((symbol, score, index))
        }
        return ranked.sorted { $0.score != $1.score ? $0.score > $1.score : $0.index < $1.index }.prefix(limit).map(\.symbol)
    }

    /// Versions minimales d'un symbole, dans l'ordre de l'aperçu d'Alfred 6. O(1).
    static func versions(of symbol: Symbol, releases: [String: [String: String]]) -> [(system: String, version: String)] {
        let table = releases[symbol.release] ?? [:]
        return ["macOS", "iOS", "watchOS", "tvOS", "visionOS"].compactMap { system in table[system].map { (system, $0) } }
    }

    /// Nom d'une catégorie de l'app SF Symbols. O(1).
    static func categoryName(_ key: String) -> String {
        let names: [String: (String, String)] = [
            "whatsnew": ("Nouveautés", "What's New"), "draw": ("Dessin", "Draw"), "variable": ("Variables", "Variable"),
            "multicolor": ("Multicolores", "Multicolor"), "communication": ("Communication", "Communication"), "weather": ("Météo", "Weather"),
            "maps": ("Plans", "Maps"), "objectsandtools": ("Objets et outils", "Objects & Tools"), "devices": ("Appareils", "Devices"),
            "cameraandphotos": ("Appareil photo et photos", "Camera & Photos"), "gaming": ("Jeux", "Gaming"), "connectivity": ("Connectivité", "Connectivity"),
            "transportation": ("Transports", "Transportation"), "automotive": ("Automobile", "Automotive"), "accessibility": ("Accessibilité", "Accessibility"),
            "privacyandsecurity": ("Confidentialité et sécurité", "Privacy & Security"), "human": ("Personnes", "Human"), "home": ("Maison", "Home"),
            "fitness": ("Forme", "Fitness"), "nature": ("Nature", "Nature"), "editing": ("Édition", "Editing"),
            "textformatting": ("Mise en forme du texte", "Text Formatting"), "media": ("Médias", "Media"), "keyboard": ("Clavier", "Keyboard"),
            "commerce": ("Commerce", "Commerce"), "time": ("Temps", "Time"), "health": ("Santé", "Health"), "shapes": ("Formes", "Shapes"),
            "arrows": ("Flèches", "Arrows"), "indices": ("Indices", "Indices"), "math": ("Maths", "Math"),
        ]
        guard let pair = names[key] else { return key.prefix(1).uppercased() + key.dropFirst() }
        return tr(pair.0, pair.1)
    }
}

/// Fenêtre du navigateur SF Symbols. Flèches : sélection ; Retour : nom copié, fenêtre fermée ; ⌘C : nom copié ;
/// Échap : fermer. Catalogue lu une fois, hors du fil principal.
@MainActor
final class LauncherSymbolsPanel: NSObject, NSWindowDelegate, NSSearchFieldDelegate {
    private static var current: LauncherSymbolsPanel?
    nonisolated(unsafe) private static var cached: LauncherSymbols.Catalog?

    private let panel: NSPanel
    private let field = NSSearchField()
    private let grid = SymbolGridView()
    private let scroll = NSScrollView()
    private let nameLabel = NSTextField(labelWithString: "")
    private let categoriesLabel = NSTextField(labelWithString: "")
    private let previews = (0..<4).map { _ in NSImageView() }
    private let versionsLabel = NSTextField(labelWithString: "")
    private var catalog = LauncherSymbols.Catalog.empty
    private var monitor: Any?

    static func show(query: String) {
        current?.close()
        let browser = LauncherSymbolsPanel()
        current = browser
        browser.present(query: query)
    }

    private override init() {
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 740, height: 760),
                        styleMask: [.titled, .closable, .resizable, .nonactivatingPanel, .utilityWindow], backing: .buffered, defer: false)
        super.init()
    }

    private func present(query: String) {
        panel.title = "SF Symbols"
        panel.level = .floating
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.delegate = self
        panel.minSize = NSSize(width: 560, height: 420)
        layout()
        field.stringValue = query
        grid.onSelect = { [weak self] in self?.renderSelection() }
        grid.onConfirm = { [weak self] in self?.confirm() }
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        if let area = screen?.visibleFrame {
            panel.setFrameOrigin(NSPoint(x: area.midX - panel.frame.width / 2, y: area.midY - panel.frame.height / 2))
        }
        panel.orderFrontRegardless()
        panel.makeKey()
        panel.makeFirstResponder(field)
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.window === self.panel else { return event }
            switch event.keyCode {
            case 53: self.close(); return nil
            case 36, 76: self.confirm(); return nil
            case 123: self.grid.move(-1); return nil
            case 124: self.grid.move(1); return nil
            case 125: self.grid.move(SymbolGridView.columns); return nil
            case 126: self.grid.move(-SymbolGridView.columns); return nil
            default:
                if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers == "c", self.panel.firstResponder !== self.field.currentEditor() {
                    self.copySelection()
                    return nil
                }
                return event
            }
        }
        if let cached = Self.cached {
            catalog = cached
            refresh()
        } else {
            nameLabel.stringValue = tr("Chargement…", "Loading…")
            Task {
                let loaded = await Task.detached(priority: .userInitiated) { LauncherSymbols.load() }.value
                Self.cached = loaded
                self.catalog = loaded
                self.refresh()
            }
        }
    }

    private func layout() {
        let style = WorkflowViewStyle.current
        let content = NSVisualEffectView()
        style.prepare(panel, effect: content)
        style.decorate(field)
        field.placeholderString = tr("Rechercher", "Search")
        field.font = .systemFont(ofSize: 18)
        field.delegate = self
        grid.style = style
        scroll.documentView = grid
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        nameLabel.font = .monospacedSystemFont(ofSize: 17, weight: .regular)
        nameLabel.alignment = .center
        // Noms longs (« rectangle.portrait.and.arrow.forward.fill ») : deux lignes plutôt qu'un nom coupé (essai du 29 octobre).
        nameLabel.maximumNumberOfLines = 2
        nameLabel.lineBreakMode = .byCharWrapping
        nameLabel.cell?.wraps = true
        categoriesLabel.font = .systemFont(ofSize: 12)
        categoriesLabel.textColor = .secondaryLabelColor
        categoriesLabel.alignment = .center
        versionsLabel.font = .monospacedDigitSystemFont(ofSize: 13, weight: .regular)
        // Quatre tailles dans des cases fixes : sans elles, le grand aperçu débordait sur les petits (essai du 29 octobre).
        let sizes: [CGFloat] = [72, 40, 22, 13]
        for (view, size) in zip(previews, sizes) {
            view.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: size, weight: .regular)
            view.contentTintColor = .labelColor
            view.imageScaling = .scaleProportionallyDown
            view.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([view.widthAnchor.constraint(equalToConstant: size * 2.2),
                                         view.heightAnchor.constraint(equalToConstant: size * 1.6)])
        }
        let side = NSStackView(views: previews + [versionsLabel])
        side.orientation = .vertical
        side.alignment = .centerX
        side.spacing = 14
        let left = NSStackView(views: [field, scroll, nameLabel, categoriesLabel])
        left.orientation = .vertical
        left.spacing = 10
        let root = NSStackView(views: [left, side])
        root.orientation = .horizontal
        root.alignment = .top
        root.spacing = 16
        root.edgeInsets = NSEdgeInsets(top: style == .system ? 12 : 36, left: 14, bottom: 14, right: 14)
        root.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(root)
        panel.contentView = content
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: content.leadingAnchor), root.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            root.topAnchor.constraint(equalTo: content.topAnchor), root.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            scroll.widthAnchor.constraint(equalToConstant: SymbolGridView.cell * CGFloat(SymbolGridView.columns) + 18),
            scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 300),
            field.widthAnchor.constraint(equalTo: scroll.widthAnchor), nameLabel.widthAnchor.constraint(equalTo: scroll.widthAnchor),
            categoriesLabel.widthAnchor.constraint(equalTo: scroll.widthAnchor), side.widthAnchor.constraint(equalToConstant: 200),
        ])
    }

    func controlTextDidChange(_ notification: Notification) { refresh() }

    private func refresh() {
        grid.symbols = LauncherSymbols.search(field.stringValue, in: catalog.symbols)
        grid.selection = 0
        grid.frame = NSRect(x: 0, y: 0, width: SymbolGridView.cell * CGFloat(SymbolGridView.columns),
                            height: max(scroll.contentSize.height, grid.contentHeight))
        grid.needsDisplay = true
        grid.scrollToSelection()
        renderSelection()
    }

    private func renderSelection() {
        guard let symbol = grid.selected else {
            nameLabel.stringValue = catalog.symbols.isEmpty ? tr("Symboles indisponibles", "Symbols unavailable") : tr("Aucun symbole", "No symbol")
            categoriesLabel.stringValue = ""
            versionsLabel.stringValue = ""
            previews.forEach { $0.image = nil }
            return
        }
        nameLabel.stringValue = symbol.name
        categoriesLabel.stringValue = symbol.categories.map(LauncherSymbols.categoryName).joined(separator: ", ")
        let image = NSImage(systemSymbolName: symbol.name, accessibilityDescription: symbol.name)
        previews.forEach { $0.image = image }
        versionsLabel.stringValue = LauncherSymbols.versions(of: symbol, releases: catalog.releases)
            .map { $0.system.padding(toLength: 10, withPad: " ", startingAt: 0) + $0.version }.joined(separator: "\n")
    }

    private func copySelection() {
        guard let name = grid.selected?.name else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(name, forType: .string)
    }

    private func confirm() {
        copySelection()
        close()
    }

    private func close() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        panel.orderOut(nil)
        if Self.current === self { Self.current = nil }
    }

    func windowWillClose(_ notification: Notification) { close() }
}

/// Grille dessinée des symboles : 6 colonnes, sélection en turquoise (#358188), clic pour choisir, double clic pour
/// copier. Seules les cases visibles sont dessinées. O(v) par dessin.
@MainActor
final class SymbolGridView: NSView {
    static let columns = 6
    static let cell: CGFloat = 76

    var symbols: [LauncherSymbols.Symbol] = []
    var selection = 0
    var style = WorkflowViewStyle.system
    var onSelect: (() -> Void)?
    var onConfirm: (() -> Void)?

    var selected: LauncherSymbols.Symbol? { symbols.indices.contains(selection) ? symbols[selection] : nil }
    var contentHeight: CGFloat { CGFloat((symbols.count + Self.columns - 1) / Self.columns) * Self.cell }
    override var isFlipped: Bool { true }

    func move(_ step: Int) {
        guard !symbols.isEmpty else { return }
        selection = min(max(0, selection + step), symbols.count - 1)
        needsDisplay = true
        scrollToSelection()
        onSelect?()
    }

    func scrollToSelection() {
        scrollToVisible(rect(for: selection).insetBy(dx: 0, dy: -8))
    }

    private func rect(for index: Int) -> NSRect {
        NSRect(x: CGFloat(index % Self.columns) * Self.cell, y: CGFloat(index / Self.columns) * Self.cell, width: Self.cell, height: Self.cell)
    }

    override func draw(_ dirtyRect: NSRect) {
        // Le rectangle reçu peut être infini (dessin par couche) : borné à la vue avant toute conversion en entier.
        let area = dirtyRect.intersection(bounds)
        guard !area.isNull, area.minY.isFinite, area.maxY.isFinite else { return }
        let first = max(0, Int(area.minY / Self.cell) * Self.columns)
        let last = min(symbols.count, Int(ceil(area.maxY / Self.cell)) * Self.columns)
        guard first < last else { return }
        let configuration = NSImage.SymbolConfiguration(pointSize: 30, weight: .regular)
        for index in first..<last {
            let box = rect(for: index).insetBy(dx: 4, dy: 4)
            let chosen = index == selection
            if chosen {
                NSColor(red: 0x35 / 255, green: 0x81 / 255, blue: 0x88 / 255, alpha: 1).setFill()
                NSBezierPath(roundedRect: box, xRadius: 10, yRadius: 10).fill()
            }
            guard let image = NSImage(systemSymbolName: symbols[index].name, accessibilityDescription: nil)?
                .withSymbolConfiguration(configuration) else { continue }
            let tint = chosen ? NSColor.white : NSColor.secondaryLabelColor
            let tinted = NSImage(size: image.size, flipped: false) { frame in
                image.draw(in: frame)
                tint.set()
                frame.fill(using: .sourceAtop)
                return true
            }
            let origin = NSPoint(x: box.midX - image.size.width / 2, y: box.midY - image.size.height / 2)
            tinted.draw(in: NSRect(origin: origin, size: image.size))
        }
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let index = Int(point.y / Self.cell) * Self.columns + Int(point.x / Self.cell)
        guard symbols.indices.contains(index) else { return }
        selection = index
        needsDisplay = true
        onSelect?()
        if event.clickCount == 2 { onConfirm?() }
    }
}
