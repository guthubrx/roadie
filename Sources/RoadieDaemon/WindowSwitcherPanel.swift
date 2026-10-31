import AppKit
import RoadieCore

enum WindowSwitcherStyle: String, Sendable {
    case thumbnails, icons, list

    static func from(_ raw: String) -> WindowSwitcherStyle {
        WindowSwitcherStyle(rawValue: raw) ?? .thumbnails
    }
}

struct WindowSwitcherAppearance: Equatable {
    var style: WindowSwitcherStyle
    var thumbnailWidth: CGFloat
    var autoSize: Bool
    var fontSize: CGFloat
    var fontFamily: String
    var preview: Bool
    var presentation: WindowSwitcherPresentation
    var thumbnailHeightLimit: CGFloat = 140
    var appIcon = true
    /// 0 : automatique.
    var appIconSize: CGFloat = 0

    init(config: WindowSwitcherConfig, profile: WindowSwitcherShortcutConfig? = nil) {
        style = WindowSwitcherStyle.from(profile?.styleOverride ?? config.style)
        thumbnailWidth = CGFloat(profile?.thumbnailWidthOverride ?? config.thumbnailWidth)
        autoSize = profile?.autoSizeOverride ?? config.autoSize
        fontSize = CGFloat(profile?.fontSizeOverride ?? config.fontSize)
        fontFamily = profile?.fontFamilyOverride ?? config.fontFamily
        preview = profile?.previewOverride ?? config.preview
        presentation = WindowSwitcherPresentation(rawValue: profile?.presentationOverride ?? config.presentation) ?? .classic
        appIcon = config.appIcon
        appIconSize = CGFloat(config.appIconSize)
    }

    var compactCaptions: Bool { presentation != .classic && style == .thumbnails }
    /// Hauteur du texte sous la vignette : une ligne en présentation compacte, deux sinon.
    var textHeight: CGFloat {
        compactCaptions ? ceil(fontSize * 1.4) + 4 : WindowSwitcherGrid.labelsHeight(fontSize: fontSize)
    }
    /// Une taille choisie plus grande que le texte agrandit la ligne du titre ; la taille automatique y tient toujours.
    var captionHeight: CGFloat {
        style == .thumbnails && appIconSize > 0 ? max(textHeight, iconSide + 4) : textHeight
    }

    /// Côté de l'icône de l'application (session 121), 0 sans icône. Automatique : la hauteur du texte à côté
    /// (titre et application), 22 points au plus en une ligne ; 28 en liste ; 56 pour le style Icônes, où l'icône
    /// est l'image de la carte et reste donc affichée. La carte limite encore la taille automatique à sa largeur.
    var iconSide: CGFloat {
        switch style {
        case .icons: appIconSize > 0 ? appIconSize : 56
        case .list: appIcon ? (appIconSize > 0 ? appIconSize : 28) : 0
        case .thumbnails:
            !appIcon ? 0 : appIconSize > 0 ? appIconSize : compactCaptions ? min(22, textHeight - 2) : (textHeight - 4).rounded()
        }
    }

    /// Icône du titre d'une carte de cette largeur : un cinquième au plus en automatique, la moitié sinon. O(1).
    func captionIconSide(cardWidth: CGFloat) -> CGFloat {
        min(iconSide, (cardWidth * (appIconSize > 0 ? 0.5 : 0.2)).rounded())
    }

    func imageHeight(cardWidth: CGFloat) -> CGFloat {
        let natural = WindowSwitcherGrid.imageHeight(cardWidth: cardWidth)
        return compactCaptions ? min(natural, thumbnailHeightLimit) : natural
    }

    @MainActor func font(size: CGFloat, weight: NSFont.Weight) -> NSFont {
        if fontFamily != "system", let named = NSFontManager.shared.font(withFamily: fontFamily,
            traits: [], weight: weight == .regular ? 5 : 7, size: size) { return named }
        return NSFont.systemFont(ofSize: size, weight: weight)
    }
}

struct WindowSwitcherGridLayout: Equatable {
    var columns: Int
    var cardSize: CGSize
    var frames: [CGRect]
    var contentSize: CGSize
}

/// Mise en page pure des cartes : ordre ligne par ligne depuis le haut, sans AppKit.
enum WindowSwitcherGrid {
    static let spacing: CGFloat = 12
    static let minCardWidth: CGFloat = 120

    static func labelsHeight(fontSize: CGFloat) -> CGFloat {
        fontSize * 1.3 + max(fontSize - 3, 10) * 1.3 + 4
    }

    static func imageHeight(cardWidth: CGFloat) -> CGFloat {
        max(0, cardWidth - 16) * 9 / 16
    }

    static func layout(count: Int, appearance: WindowSwitcherAppearance, available: CGFloat) -> WindowSwitcherGridLayout {
        guard count > 0 else {
            return WindowSwitcherGridLayout(columns: 1, cardSize: .zero, frames: [], contentSize: .zero)
        }
        let width = max(available, 0)
        let labels = appearance.captionHeight
        let card: CGSize
        let columns: Int
        switch appearance.style {
        case .list:
            columns = 1
            card = CGSize(width: width, height: max(44, max(labels, appearance.iconSide) + 16))
        case .icons:
            let cardWidth = min(max(minCardWidth, appearance.fontSize * 7, appearance.iconSide + 16), max(1, width))
            columns = fit(count: count, width: width, cardWidth: cardWidth)
            card = CGSize(width: cardWidth, height: 8 + appearance.iconSide + 8 + labels + 8)
        case .thumbnails:
            let base = min(max(appearance.thumbnailWidth, minCardWidth), 400)
            let cardWidth: CGFloat
            if appearance.autoSize && appearance.presentation != .classic {
                columns = fit(count: count, width: width, cardWidth: max(180, base))
                cardWidth = max(1, min(400, (width - spacing * CGFloat(columns - 1)) / CGFloat(columns)))
            } else if appearance.autoSize {
                let maxColumns = max(1, Int((width + spacing) / (minCardWidth + spacing)))
                columns = min(count, maxColumns)
                cardWidth = max(1, min(base, (width - spacing * CGFloat(columns - 1)) / CGFloat(columns)))
            } else {
                columns = fit(count: count, width: width, cardWidth: base)
                cardWidth = min(base, max(1, width))
            }
            card = CGSize(width: cardWidth, height: 8 + appearance.imageHeight(cardWidth: cardWidth) + 6 + labels + 8)
        }
        let rows = (count + columns - 1) / columns
        let frames = (0..<count).map { index in
            CGRect(
                x: CGFloat(index % columns) * (card.width + spacing),
                y: CGFloat(index / columns) * (card.height + spacing),
                width: card.width,
                height: card.height
            )
        }
        let content = CGSize(
            width: CGFloat(columns) * card.width + CGFloat(columns - 1) * spacing,
            height: CGFloat(rows) * card.height + CGFloat(rows - 1) * spacing
        )
        return WindowSwitcherGridLayout(columns: columns, cardSize: card, frames: frames, contentSize: content)
    }

    private static func fit(count: Int, width: CGFloat, cardWidth: CGFloat) -> Int {
        min(count, max(1, Int((width + spacing) / (cardWidth + spacing))))
    }
}

extension WindowSwitcherEntry {
    var subtitleText: String {
        [stageName, desktopName, displayName].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    var stateBadges: [String] {
        var badges: [String] = []
        if !isAvailable { badges.append(tr("indisponible", "unavailable")) }
        if !visibilityKnown { badges.append(tr("état non vérifié", "state unknown")) }
        if isMinimized { badges.append(tr("réduite", "minimized")) }
        if isHidden { badges.append(tr("masquée", "hidden")) }
        if isFullscreen { badges.append(tr("plein écran", "full screen")) }
        return badges
    }
}

extension WindowSwitcherAction {
    var menuTitle: String {
        switch self {
        case .close: tr("Fermer la fenêtre", "Close window")
        case .minimize: tr("Réduire ou restaurer", "Minimize or restore")
        case .hideApp: tr("Masquer l'application", "Hide app")
        case .quitApp: tr("Quitter l'application", "Quit app")
        case .maximize: tr("Maximiser", "Maximize")
        case .fullscreen: tr("Plein écran Roadie", "Roadie full screen")
        }
    }
}

/// Carte d'une fenêtre : vignette, icône ou ligne compacte. Dessinée sans focus ni activation.
@MainActor
final class WindowSwitcherCardView: NSView {
    let entryID: WindowID
    var onClick: (() -> Void)?
    /// Icônes du coin (session 137), montrées au survol : × ferme la fenêtre ou retire la zone, sens interdit exclut
    /// l'application du sélecteur ou de ses zones de clics.
    var onDismiss: (() -> Void)?
    var onBan: (() -> Void)?
    private var cornerButtons: [CardCornerButton] = []
    var isSelected = false {
        didSet {
            guard isSelected != oldValue else { return }
            needsDisplay = true
            setAccessibilitySelected(isSelected)
        }
    }

    override var isFlipped: Bool { true }

    init(entry: WindowSwitcherEntry, image: NSImage?, appearance: WindowSwitcherAppearance, frame: NSRect,
         appIcon: NSImage? = nil, iconOnly: Bool = false) {
        entryID = entry.id
        super.init(frame: frame)
        wantsLayer = false
        let title = entry.window.title.isEmpty ? entry.window.appName : entry.window.title
        let badges = entry.stateBadges
        let context = appearance.presentation == .classic ? entry.subtitleText : ""
        let subtitle = ([context, entry.window.appName] + badges).filter { !$0.isEmpty }.joined(separator: " · ")
        let titleField = NSTextField(labelWithString: title)
        titleField.font = appearance.font(size: appearance.fontSize, weight: .medium)
        titleField.textColor = .labelColor
        titleField.lineBreakMode = .byTruncatingTail
        titleField.maximumNumberOfLines = 1
        let subtitleField = NSTextField(labelWithString: subtitle)
        subtitleField.font = appearance.font(size: max(appearance.fontSize - 3, 10), weight: .regular)
        subtitleField.textColor = .secondaryLabelColor
        subtitleField.lineBreakMode = .byTruncatingTail
        subtitleField.maximumNumberOfLines = 1
        let imageView = WindowSwitcherThumbnailView()
        imageView.image = image ?? appIcon
        imageView.fillsThumbnail = appearance.compactCaptions && !iconOnly && image != nil
        imageView.isIcon = appearance.style == .thumbnails && (iconOnly || image == nil)
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.imageAlignment = .alignCenter
        imageView.wantsLayer = true
        imageView.layer?.cornerRadius = 7
        imageView.layer?.masksToBounds = true
        imageView.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.14).cgColor
        imageView.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.7).cgColor
        imageView.layer?.borderWidth = 0.5
        addSubview(imageView)
        addSubview(titleField)
        addSubview(subtitleField)
        place(imageView, titleField, subtitleField, appearance: appearance, imageHeight: appearance.presentation == .overview ? max(0, bounds.height - appearance.captionHeight - 22) : appearance.imageHeight(cardWidth: bounds.width))
        imageView.isHidden = appearance.style == .list && appearance.iconSide == 0
        if appearance.compactCaptions { subtitleField.isHidden = true }
        let side = appearance.style == .thumbnails ? appearance.captionIconSide(cardWidth: bounds.width) : 0
        if side > 0 {
            // Icône à gauche du texte, centrée sur la ligne du titre ; le texte se décale d'autant.
            let captionTop = imageView.frame.maxY + 6
            let icon = NSImageView(frame: CGRect(x: 8, y: captionTop + (appearance.captionHeight - side) / 2, width: side, height: side))
            icon.image = appIcon ?? NSImage(systemSymbolName: "app", accessibilityDescription: entry.window.appName)
            icon.imageScaling = .scaleProportionallyUpOrDown
            addSubview(icon)
            let textX = icon.frame.maxX + 6
            for field in [titleField, subtitleField] {
                field.frame = CGRect(x: textX, y: field.frame.minY, width: max(0, bounds.width - textX - 8), height: field.frame.height)
            }
        }
        titleField.toolTip = title
        subtitleField.toolTip = subtitle
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(([title, entry.window.appName, entry.subtitleText] + badges).filter { !$0.isEmpty }.joined(separator: ", "))
        let app = entry.window.appName
        let isZone = entry.id.rawValue >= WindowSwitcherZones.firstID
        let ban = CardCornerButton(symbol: "nosign", tip: isZone
            ? tr("Plus de zones de clics pour \(app)", "No more click zones for \(app)")
            : tr("Ne plus montrer \(app) dans le sélecteur", "Stop showing \(app) in the switcher"),
            frame: CGRect(x: bounds.width - 54, y: 6, width: 22, height: 22)) { [weak self] in self?.onBan?() }
        let close = CardCornerButton(symbol: "xmark", tip: isZone ? tr("Retirer cette zone", "Remove this zone") : tr("Fermer la fenêtre", "Close the window"),
                                     frame: CGRect(x: bounds.width - 28, y: 6, width: 22, height: 22)) { [weak self] in self?.onDismiss?() }
        cornerButtons = [ban, close]
        cornerButtons.forEach { $0.isHidden = true; addSubview($0) }
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }

    override func mouseEntered(with event: NSEvent) { cornerButtons.forEach { $0.isHidden = false } }
    override func mouseExited(with event: NSEvent) { cornerButtons.forEach { $0.isHidden = true } }

    private func place(_ imageView: NSImageView, _ title: NSTextField, _ subtitle: NSTextField, appearance: WindowSwitcherAppearance, imageHeight: CGFloat) {
        let width = bounds.width
        let labels = appearance.captionHeight, text = appearance.textHeight, side = appearance.iconSide
        switch appearance.style {
        case .thumbnails:
            let imageHeight = min(imageHeight, max(0, bounds.height - labels - 22))
            imageView.frame = CGRect(x: 8, y: 8, width: width - 16, height: imageHeight)
            // Texte centré dans sa ligne, plus haute que lui si l'icône choisie est grande.
            let top = 8 + imageHeight + 6 + (labels - text) / 2
            title.frame = CGRect(x: 8, y: top, width: width - 16, height: appearance.compactCaptions ? text : text * 0.55)
            subtitle.frame = CGRect(x: 8, y: top + text * 0.5, width: width - 16, height: text * 0.5)
        case .icons:
            imageView.frame = CGRect(x: (width - side) / 2, y: 8, width: side, height: side)
            title.alignment = .center
            subtitle.alignment = .center
            title.frame = CGRect(x: 4, y: side + 16, width: width - 8, height: labels * 0.55)
            subtitle.frame = CGRect(x: 4, y: side + 16 + labels * 0.5, width: width - 8, height: labels * 0.5)
        case .list:
            imageView.frame = CGRect(x: 12, y: (bounds.height - side) / 2, width: side, height: side)
            let textX: CGFloat = side > 0 ? 12 + side + 12 : 12
            let top = (bounds.height - labels) / 2
            title.frame = CGRect(x: textX, y: top, width: width - textX - 12, height: labels * 0.55)
            subtitle.frame = CGRect(x: textX, y: top + labels * 0.5, width: width - textX - 12, height: labels * 0.5)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 10, yRadius: 10)
        (isSelected ? NSColor.controlAccentColor.withAlphaComponent(0.18) : NSColor.labelColor.withAlphaComponent(0.025)).setFill()
        path.fill()
        (isSelected ? NSColor.controlAccentColor : NSColor.separatorColor.withAlphaComponent(0.3)).setStroke()
        path.lineWidth = isSelected ? 2 : 0.5
        path.stroke()
    }

    override func mouseDown(with event: NSEvent) { onClick?() }
    override func accessibilityPerformPress() -> Bool { onClick?(); return true }
}

final class WindowSwitcherFlippedView: NSView {
    override var isFlipped: Bool { true }
}

/// Panneau non activant : prend le clavier sans activer Roadie ni la cible. Le champ natif garde l'édition, IME compris.
@MainActor
final class WindowSwitcherPanel: NSPanel, NSSearchFieldDelegate {
    enum Key: Equatable {
        case cancel, confirm, next, previous, left, right, up, down
    }

    var switcherAppearance: WindowSwitcherAppearance
    var onQueryChange: ((String) -> Void)?
    var onNavigate: ((_ backwards: Bool) -> Void)?
    var onConfirm: (() -> Void)?
    var onCancel: (() -> Void)?
    var onSelect: ((WindowID) -> Void)?
    /// Icônes du coin d'une carte (session 137).
    var onDismiss: ((WindowID) -> Void)?
    var onBan: ((WindowID) -> Void)?
    var onAction: ((WindowSwitcherAction) -> Void)?
    var onHighlight: ((WindowID) -> Void)?
    var onSearchMode: ((Bool) -> Void)?
    private(set) var isSearchEditing = false
    private var searchStartedOpen = false
    private var profile = WindowSwitcherShortcutConfig()
    private var navigationModifiers: Set<WindowSwitcherModifier> = []
    private var hoverMonitor: Any?
    private var previousMouse: CGPoint?


    private let effect = NSVisualEffectView()
    private let field = NSSearchField()
    private let previewPane = WindowSwitcherDetailView()
    private let footerLine = NSBox()
    private let detailLine = NSBox()
    private let scrollView = NSScrollView()
    private let gridContainer = WindowSwitcherFlippedView()
    private let groupScroll = NSScrollView()
    private let groupContainer = WindowSwitcherFlippedView()
    private let statusLabel = NSTextField(labelWithString: "")
    private let selectionLabel = NSTextField(labelWithString: "")
    private let actionsButton = NSPopUpButton(frame: .zero, pullsDown: true)
    private var groupedLayout = WindowSwitcherGroupedLayout()
    private var renderedEntries: [WindowSwitcherEntry] = []
    private var renderedImages: [WindowID: NSImage] = [:]
    private var iconOnlyIDs: Set<WindowID> = []
    /// Icônes par processus, lues à l'affichage ; réglables pour les rendus hors écran de la documentation.
    var appIcons: [Int32: NSImage] = [:]
    private var groups = WindowSwitcherGroups(entries: [])
    private var browsing = SwitcherBrowsingState()
    private var selectedWindowID: WindowID?
    private var needsSelectionReveal = false
    private var layoutWidth: CGFloat = 0
    private var layoutHeight: CGFloat = 0
    private var cards: [WindowSwitcherCardView] = []
    private var visibleArea = CGRect(x: 0, y: 0, width: 1280, height: 800)
    private var previewShown = false
    private let pad: CGFloat = 16
    private var searchHeight: CGFloat { max(28, switcherAppearance.fontSize * 1.4 + 8) }
    /// Session 122 : ni titre ni résumé en haut, ni aide en bas ; seulement les fenêtres. La recherche, le menu
    /// Actions et un refus d'action ont encore leur place quand ils sont montrés.
    private var headerHeight: CGFloat { field.isHidden ? pad : searchHeight + 2 * pad }
    private var showsFooter: Bool { !actionsButton.isHidden || !selectionLabel.stringValue.isEmpty }
    private var footerHeight: CGFloat { showsFooter ? max(44, switcherAppearance.fontSize * 1.4 + 18) : pad }

    var renderedWindowIDs: [WindowID] { cards.map(\.entryID) }
    /// La résolution suit la taille réellement affichée, sans augmenter le nombre de captures.
    var thumbnailDisplayWidth: CGFloat { min(400, cards.lazy.map(\.frame.width).max() ?? switcherAppearance.thumbnailWidth) }

    override var canBecomeKey: Bool { true }

    func configure(profile: WindowSwitcherShortcutConfig, forceSearch: Bool = false, navigationModifiers: Set<WindowSwitcherModifier>? = nil) {
        self.profile = profile
        if let navigationModifiers { self.navigationModifiers = navigationModifiers }
        let search = SwitcherNavigation.visible(profile.searchVisibility, automatic: forceSearch)
        field.isHidden = !search && !isSearchEditing
        actionsButton.isHidden = !SwitcherNavigation.visible(profile.actionsVisibility, automatic: profile.releaseAction != "focus" || forceSearch)
        if forceSearch && profile.searchVisibility != "never" { beginSearch(initial: true) }
        relayout()
    }

    func beginSearch(initial: Bool = false) {
        guard profile.searchVisibility != "never" else { return }
        isSearchEditing = true
        searchStartedOpen = initial
        field.isHidden = false
        onSearchMode?(true)
        relayout()
        makeFirstResponder(field)
    }

    func escape() {
        if isSearchEditing && !searchStartedOpen {
            isSearchEditing = false
            field.stringValue = ""
            field.isHidden = profile.searchVisibility != "always"
            onQueryChange?("")
            onSearchMode?(false)
            relayout()
            makeFirstResponder(gridContainer)
        } else { onCancel?() }
    }

    func hover(at location: CGPoint) {
        guard profile.mouseHover, previousMouse != location else { return }
        previousMouse = location
        let point = gridContainer.convert(location, from: nil)
        guard scrollView.frame.contains(effect.convert(location, from: nil)),
              let card = cards.first(where: { $0.frame.contains(point) }), !card.isSelected else { return }
        onHighlight?(card.entryID)
    }

    private func move(_ direction: SwitcherDirection) {
        guard profile.arrowNavigation, let index = cards.firstIndex(where: \.isSelected) else { return }
        if let target = SwitcherNavigation.destination(from: index, direction: direction, frames: cards.map(\.frame)) {
            onHighlight?(cards[target].entryID)
        } else if direction == .left || direction == .right {
            moveGroup(backwards: direction == .left)
        }
    }

    override var canBecomeMain: Bool { false }

    init(appearance: WindowSwitcherAppearance) {
        self.switcherAppearance = appearance
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isReleasedWhenClosed = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        title = tr("Sélecteur de fenêtres Roadie", "Roadie window switcher")
        setAccessibilityLabel(title)

        effect.material = .popover
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 14
        effect.layer?.borderWidth = 0.5
        effect.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.7).cgColor
        effect.layer?.masksToBounds = true
        contentView = effect

        field.placeholderString = tr("Rechercher une fenêtre", "Search windows")
        field.sendsSearchStringImmediately = true
        field.delegate = self
        field.setAccessibilityLabel(tr("Rechercher une fenêtre", "Search windows"))

        scrollView.hasVerticalScroller = true
        scrollView.scrollerStyle = .overlay
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.documentView = gridContainer

        groupScroll.drawsBackground = false
        groupScroll.borderType = .noBorder
        groupScroll.scrollerStyle = .overlay
        groupScroll.autohidesScrollers = true
        groupScroll.documentView = groupContainer

        previewPane.onOpen = { [weak self] in self?.onConfirm?() }
        for line in [footerLine, detailLine] { line.boxType = .separator; effect.addSubview(line) }

        statusLabel.alignment = .center
        statusLabel.textColor = .secondaryLabelColor

        actionsButton.addItem(withTitle: "Actions")
        for action in WindowSwitcherAction.allCases {
            actionsButton.addItem(withTitle: action.menuTitle)
            actionsButton.lastItem?.representedObject = action.rawValue
            actionsButton.lastItem?.target = self
            actionsButton.lastItem?.action = #selector(actionChosen(_:))
        }
        actionsButton.setAccessibilityLabel(tr("Actions sur la fenêtre sélectionnée", "Actions on the selected window"))
        actionsButton.isEnabled = false

        effect.addSubview(field)
        effect.addSubview(previewPane)
        effect.addSubview(scrollView)
        effect.addSubview(groupScroll)
        effect.addSubview(statusLabel)
        effect.addSubview(actionsButton)
        selectionLabel.lineBreakMode = .byTruncatingMiddle
        selectionLabel.maximumNumberOfLines = 1
        effect.addSubview(selectionLabel)
    }

    func showLoading() {
        previewShown = false
        renderedEntries = []
        renderedImages = [:]
        groups = WindowSwitcherGroups(entries: [])
        clearCards()
        previewPane.update(entry: nil, image: nil, icon: nil, appearance: switcherAppearance)
        setStatus(tr("Chargement des fenêtres…", "Loading windows…"))
        relayout()
    }

    func render(
        entries: [WindowSwitcherEntry],
        selectedID: WindowID?,
        query: String,
        images: [WindowID: NSImage],
        previewImage: NSImage?,
        emptyMessage: String,
        iconOnlyIDs: Set<WindowID> = []
    ) {
        needsSelectionReveal = needsSelectionReveal || selectedID != selectedWindowID || field.stringValue != query
        renderedEntries = entries
        renderedImages = images
        self.iconOnlyIDs = iconOnlyIDs
        let pids = Set(entries.map { $0.window.pid })
        appIcons = appIcons.filter { pids.contains($0.key) }
        for pid in pids where appIcons[pid] == nil { appIcons[pid] = NSRunningApplication(processIdentifier: pid)?.icon }
        groups = WindowSwitcherGroups(entries: entries)
        selectedWindowID = selectedID
        browsing.reconcile(groups: groups, selectedID: selectedID)
        if field.stringValue != query { field.stringValue = query }
        previewShown = switcherAppearance.preview && !entries.isEmpty
        rebuildContent()
        setStatus(entries.isEmpty ? emptyMessage : "")
        select(selectedID, previewImage: previewImage)
    }

    func select(_ id: WindowID?, previewImage: NSImage?) {
        needsSelectionReveal = needsSelectionReveal || selectedWindowID != id
        selectedWindowID = id
        let oldDesktop = browsing.desktop, oldStage = browsing.stage
        browsing.reconcile(groups: groups, selectedID: id)
        if (usesDesktopTabs && oldDesktop != browsing.desktop) || (switcherAppearance.presentation == .hierarchy && oldStage != browsing.stage) {
            rebuildContent()
        }
        selectionLabel.stringValue = ""
        for card in cards { card.isSelected = card.entryID == id }
        let entry = renderedEntries.first { $0.id == id }
        previewPane.update(entry: entry, image: previewImage, icon: entry.flatMap { appIcons[$0.window.pid] }, appearance: switcherAppearance)
        previewPane.isHidden = !previewShown
        actionsButton.isEnabled = id != nil
        relayout()
    }

    func showActionError() {
        selectionLabel.stringValue = tr("Action refusée par l’application. Réessayez ou choisissez une autre fenêtre.",
                                        "The app refused the action. Try again or choose another window.")
        selectionLabel.textColor = .systemOrange
        relayout()
    }

    func present(on screen: NSScreen) {
        layout(in: screen.visibleFrame)
        EffectAnimator.shared.visibility(self, visible: true, action: .switcher)
        makeKey()
        makeFirstResponder(field.isHidden ? gridContainer : field)
        acceptsMouseMovedEvents = true
        if hoverMonitor == nil {
            hoverMonitor = NSEvent.addLocalMonitorForEvents(matching: .mouseMoved) { [weak self] event in
                MainActor.assumeIsolated {
                    if let self, event.window === self { self.hover(at: event.locationInWindow) }
                }
                return event
            }
        }
    }

    /// Même circuit de géométrie pour l'écran réel et les rendus natifs de validation.
    func layout(in visibleFrame: CGRect) {
        visibleArea = visibleFrame
        relayout()
    }

    override func orderOut(_ sender: Any?) {
        if let hoverMonitor { NSEvent.removeMonitor(hoverMonitor) }
        hoverMonitor = nil
        previousMouse = nil
        EffectAnimator.shared.visibility(self, visible: false, action: .switcher) { [weak self] in self?.finishHiding(sender) }
    }

    private func finishHiding(_ sender: Any?) { super.orderOut(sender) }

    func controlTextDidChange(_ notification: Notification) {
        isSearchEditing = true
        onSearchMode?(true)
        onQueryChange?(field.stringValue)
    }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, event.modifierFlags.intersection([.command, .control, .option, .shift]) == .command,
           event.charactersIgnoringModifiers?.lowercased() == "f" {
            beginSearch()
            return
        }
        if event.type == .keyDown,
           (field.currentEditor() as? NSTextView)?.hasMarkedText() != true,
           let key = Self.key(for: event, allowing: navigationModifiers) {
            switch key {
            case .cancel: escape()
            case .confirm: onConfirm?()
            case .next: onNavigate?(false)
            case .previous: onNavigate?(true)
            case .left, .right:
                if isSearchEditing && !field.stringValue.isEmpty { super.sendEvent(event); return }
                move(key == .left ? .left : .right)
            case .up: move(.up)
            case .down: move(.down)
            }
            return
        }
        super.sendEvent(event)
    }

    /// Cmd+A/C/X/V vont à l'éditeur du champ : il n'y a pas de menu Édition dans le démon.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.modifierFlags.intersection([.command, .control, .option, .shift]) == .command,
              let editor = firstResponder as? NSTextView, editor.isFieldEditor,
              let action = Self.editAction(for: event.charactersIgnoringModifiers?.lowercased())
        else { return super.performKeyEquivalent(with: event) }
        return NSApp.sendAction(action, to: editor, from: self)
    }

    /// Les flèches restent utilisables pendant le maintien du raccourci d'ouverture.
    static func key(for event: NSEvent, allowing modifiers: Set<WindowSwitcherModifier> = []) -> Key? {
        let flags = event.modifierFlags.intersection([.command, .control, .option, .shift])
        let arrowAllowed = WindowSwitcherHotkey.held(in: CGEventFlags(rawValue: UInt64(flags.rawValue))).isSubset(of: modifiers)
        switch event.keyCode {
        case 53: return .cancel
        case 36, 76: return .confirm
        case 48:
            guard flags.isEmpty || flags == .shift else { return nil }
            return flags.contains(.shift) ? .previous : .next
        case 123: return arrowAllowed ? .left : nil
        case 124: return arrowAllowed ? .right : nil
        case 125: return arrowAllowed ? .down : nil
        case 126: return arrowAllowed ? .up : nil
        default: return nil
        }
    }

    static func editAction(for key: String?) -> Selector? {
        switch key {
        case "a": return #selector(NSText.selectAll(_:))
        case "c": return #selector(NSText.copy(_:))
        case "x": return #selector(NSText.cut(_:))
        case "v": return #selector(NSText.paste(_:))
        default: return nil
        }
    }

    @objc private func actionChosen(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let action = WindowSwitcherAction(rawValue: raw) else { return }
        onAction?(action)
    }

    private var maxWidth: CGFloat { max(280, min(visibleArea.width - 48, 1440)) }
    private var usesDesktopTabs: Bool { [.stageColumns, .desktopTabs].contains(switcherAppearance.presentation) }
    private var sideHierarchy: Bool { switcherAppearance.presentation == .hierarchy && maxWidth >= 700 && !renderedEntries.isEmpty }
    private var sidebarWidth: CGFloat { sideHierarchy ? min(260, max(180, switcherAppearance.fontSize * 10)) : 0 }
    private var navigationHeight: CGFloat {
        (usesDesktopTabs || (switcherAppearance.presentation == .hierarchy && !sideHierarchy)) && !renderedEntries.isEmpty
            ? max(40, switcherAppearance.fontSize * 1.5 + 14) : 0
    }
    private var bottomPreview: Bool { [.stageColumns, .overview].contains(switcherAppearance.presentation) }
    private var sidePreview: Bool { previewShown && maxWidth >= 700 && !bottomPreview }
    private var rightPreview: Bool { switcherAppearance.presentation != .classic }
    private var mainWidth: CGFloat { maxWidth - 2 * pad - (sideHierarchy ? sidebarWidth + pad : 0) }
    private var gridWidth: CGFloat { sidePreview ? floor((mainWidth - pad) * 0.62) : mainWidth }

    private var bodyBudget: (available: CGFloat, preferred: CGFloat) {
        let previewWidth = sidePreview ? mainWidth - gridWidth - pad : mainWidth
        let stackedHeight: CGFloat = previewShown && !sidePreview ? min(180, previewWidth * 0.5) : 0
        let previewBlock = stackedHeight > 0 ? stackedHeight + pad : 0
        let available = max(56, visibleArea.height - 32 - headerHeight - footerHeight - previewBlock - navigationHeight)
        return (available, min(available, max(400, maxWidth * 0.65 - previewBlock - navigationHeight)))
    }

    /// Change uniquement la sélection du modèle, jamais l'appartenance des fenêtres.
    func chooseGroup(_ id: SwitcherGroupID) {
        let entries: [WindowSwitcherEntry]
        if switcherAppearance.presentation == .hierarchy {
            entries = groups.stages.first { $0.id == id }?.entries ?? []
        } else { entries = groups.desktops.first { $0.id == id }?.entries ?? [] }
        guard let first = entries.first else { return }
        onHighlight?(first.id)
    }

    private func moveGroup(backwards: Bool) {
        let ids: [SwitcherGroupID]
        let current: SwitcherGroupID?
        if usesDesktopTabs { ids = groups.desktops.map(\.id); current = browsing.desktop }
        else if switcherAppearance.presentation == .hierarchy { ids = groups.stages.map(\.id); current = browsing.stage }
        else { return }
        guard let index = ids.firstIndex(where: { $0 == current }), ids.count > 1 else { return }
        chooseGroup(ids[(index + (backwards ? ids.count - 1 : 1)) % ids.count])
    }

    private func rebuildContent() {
        clearCards()
        layoutWidth = gridWidth
        layoutHeight = bodyBudget.preferred
        groupedLayout = WindowSwitcherGroupedGeometry.fittedLayout(entries: renderedEntries, appearance: switcherAppearance,
            width: gridWidth, height: layoutHeight, browsing: browsing)
        for frame in groupedLayout.surfaces {
            let surface = NSView(frame: frame)
            surface.wantsLayer = true
            surface.layer?.cornerRadius = 9
            surface.layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.035).cgColor
            surface.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.3).cgColor
            surface.layer?.borderWidth = 0.5
            gridContainer.addSubview(surface)
        }
        for heading in groupedLayout.headings {
            let label = NSTextField(labelWithString: heading.text)
            label.frame = heading.frame.insetBy(dx: 27, dy: 3)
            label.frame.size.width = max(0, heading.frame.width - 30)
            let icon = NSImageView(frame: CGRect(x: heading.frame.minX + 2, y: heading.frame.minY + 5,
                                                width: 19, height: 19))
            icon.image = NSImage(systemSymbolName: heading.isDesktop ? "display" : "folder.fill", accessibilityDescription: nil)
            icon.contentTintColor = heading.isDesktop ? .controlAccentColor : .secondaryLabelColor
            gridContainer.addSubview(icon)
            label.font = switcherAppearance.font(size: switcherAppearance.fontSize, weight: heading.isDesktop ? .bold : .semibold)
            label.textColor = .labelColor
            label.lineBreakMode = .byTruncatingTail
            label.maximumNumberOfLines = 1
            label.toolTip = heading.text
            gridContainer.addSubview(label)
        }
        for item in groupedLayout.cards {
            let card = WindowSwitcherCardView(entry: item.entry, image: renderedImages[item.entry.id],
                                              appearance: switcherAppearance, frame: item.frame,
                                              appIcon: appIcons[item.entry.window.pid], iconOnly: iconOnlyIDs.contains(item.entry.id))
            card.onClick = { [weak self] in self?.onSelect?(item.entry.id) }
            card.onDismiss = { [weak self] in self?.onDismiss?(item.entry.id) }
            card.onBan = { [weak self] in self?.onBan?(item.entry.id) }
            card.isSelected = item.entry.id == selectedWindowID
            gridContainer.addSubview(card)
            cards.append(card)
        }
        rebuildGroupNavigation()
    }

    private func rebuildGroupNavigation() {
        groupContainer.subviews.forEach { $0.removeFromSuperview() }
        groupScroll.isHidden = !sideHierarchy && navigationHeight == 0
        groupScroll.hasVerticalScroller = sideHierarchy
        groupScroll.hasHorizontalScroller = !sideHierarchy
        let font = switcherAppearance.font(size: max(12, switcherAppearance.fontSize - 1), weight: .medium)
        let rowHeight = max(36, font.pointSize * 1.5 + 12)
        func button(_ title: String, id: SwitcherGroupID, selected: Bool, frame: CGRect) {
            let button = SwitcherGroupButton(title: title, selected: selected, frame: frame) { [weak self] in self?.chooseGroup(id) }
            button.font = font
            groupContainer.addSubview(button)
        }
        if sideHierarchy {
            var y: CGFloat = 0
            for desktop in groups.desktops {
                let label = NSTextField(labelWithString: desktop.title)
                label.font = switcherAppearance.font(size: font.pointSize, weight: .semibold)
                label.lineBreakMode = .byTruncatingTail
                label.toolTip = desktop.title
                label.frame = CGRect(x: 4, y: y, width: sidebarWidth - 8, height: rowHeight)
                groupContainer.addSubview(label)
                y += rowHeight
                for stage in desktop.stages {
                    button("\(stage.title) · \(stage.entries.count)", id: stage.id, selected: stage.id == browsing.stage,
                           frame: CGRect(x: 6, y: y, width: sidebarWidth - 12, height: rowHeight))
                    y += rowHeight + 4
                }
                y += 12
            }
            groupContainer.frame = CGRect(x: 0, y: 0, width: sidebarWidth, height: y)
        } else if navigationHeight > 0 {
            let choices: [(SwitcherGroupID, String, Bool)] = usesDesktopTabs
                ? groups.desktops.map { ($0.id, "\($0.title) · \($0.entries.count)", $0.id == browsing.desktop) }
                : groups.stages.map { ($0.id, "\($0.desktopTitle) / \($0.title)", $0.id == browsing.stage) }
            let available = maxWidth - 2 * pad
            let widest = choices.map { ($0.1 as NSString).size(withAttributes: [.font: font]).width + 28 }.max() ?? 120
            let cell = max(available / CGFloat(max(1, choices.count)), min(320, max(120, widest)))
            for (i, choice) in choices.enumerated() {
                button(choice.1, id: choice.0, selected: choice.2,
                       frame: CGRect(x: CGFloat(i) * cell, y: 0, width: cell - 4, height: navigationHeight - 6))
            }
            groupContainer.frame = CGRect(x: 0, y: 0, width: max(available, cell * CGFloat(choices.count)), height: navigationHeight - 2)
        }
        if needsSelectionReveal, let selected = groupContainer.subviews.compactMap({ $0 as? NSButton }).first(where: { $0.state == .on }) {
            selected.scrollToVisible(selected.bounds)
        }
    }

    private func clearCards() {
        gridContainer.subviews.forEach { $0.removeFromSuperview() }
        cards = []
        groupedLayout = WindowSwitcherGroupedLayout()
    }

    private func setStatus(_ text: String) {
        statusLabel.stringValue = text
        statusLabel.isHidden = text.isEmpty
        scrollView.isHidden = !text.isEmpty
    }

    private func relayout() {
        if abs(layoutWidth - gridWidth) > 0.5 || abs(layoutHeight - bodyBudget.preferred) > 0.5 {
            needsSelectionReveal = true
            rebuildContent()
        }
        let width = maxWidth
        let innerWidth = width - 2 * pad
        let scrollWidth = gridWidth
        let previewWidth = sidePreview ? mainWidth - scrollWidth - pad : mainWidth
        let stackedPreviewHeight: CGFloat = previewShown && !sidePreview ? min(180, previewWidth * 0.5) : 0
        let previewBlock = stackedPreviewHeight > 0 ? stackedPreviewHeight + pad : 0
        let availableBody = bodyBudget.available
        let minimumBody: CGFloat = sidePreview ? max(400, switcherAppearance.fontSize * 15) : (switcherAppearance.presentation == .classic ? 56 : 220)
        // Le contenu utilise la hauteur de l'écran avant d'imposer un défilement.
        let bodyHeight = min(max(groupedLayout.size.height, minimumBody), availableBody)
        let height = headerHeight + navigationHeight + previewBlock + bodyHeight + footerHeight
        let origin = CGPoint(x: visibleArea.midX - width / 2, y: visibleArea.midY - height / 2)
        setFrame(CGRect(origin: origin, size: CGSize(width: width, height: height)), display: true)

        field.font = switcherAppearance.font(size: switcherAppearance.fontSize, weight: .regular)
        statusLabel.font = switcherAppearance.font(size: switcherAppearance.fontSize, weight: .regular)
        actionsButton.font = switcherAppearance.font(size: max(12, switcherAppearance.fontSize - 2), weight: .regular)
        field.frame = CGRect(x: pad, y: height - pad - searchHeight, width: innerWidth, height: searchHeight)
        footerLine.isHidden = !showsFooter
        footerLine.frame = CGRect(x: 0, y: footerHeight - 2, width: width, height: 1)
        let mainX = pad + (sideHierarchy ? sidebarWidth + pad : 0)
        let contentY = footerHeight + (bottomPreview ? previewBlock : 0)
        previewPane.frame = sidePreview
            ? CGRect(x: rightPreview ? mainX + scrollWidth + pad : mainX, y: contentY, width: previewWidth, height: bodyHeight)
            : CGRect(x: mainX, y: bottomPreview ? footerHeight : footerHeight + bodyHeight + pad,
                     width: previewWidth, height: stackedPreviewHeight)
        scrollView.frame = CGRect(x: sidePreview && !rightPreview ? mainX + previewWidth + pad : mainX,
                                  y: contentY, width: scrollWidth, height: bodyHeight)
        groupScroll.frame = sideHierarchy
            ? CGRect(x: pad, y: contentY, width: sidebarWidth, height: bodyHeight)
            : CGRect(x: pad, y: height - headerHeight - navigationHeight, width: innerWidth, height: navigationHeight)
        detailLine.isHidden = !sidePreview
        detailLine.frame = CGRect(x: rightPreview ? mainX + scrollWidth + pad / 2 : mainX + previewWidth + pad / 2,
                                  y: contentY, width: 1, height: bodyHeight)
        previewPane.layoutContent()
        statusLabel.frame = scrollView.frame
        let actionWidth = min(150, innerWidth * 0.35)
        actionsButton.frame = CGRect(x: pad, y: 8, width: actionWidth, height: footerHeight - 16)
        selectionLabel.font = switcherAppearance.font(size: max(12, switcherAppearance.fontSize - 2), weight: .regular)
        let hintsX = pad + (actionsButton.isHidden ? 0 : actionWidth + 12)
        selectionLabel.frame = CGRect(x: hintsX, y: 12, width: max(0, width - pad - hintsX), height: max(0, footerHeight - 20))
        selectionLabel.toolTip = selectionLabel.stringValue

        gridContainer.frame = CGRect(
            x: 0, y: 0, width: scrollWidth, height: max(groupedLayout.size.height, bodyHeight)
        )
        if needsSelectionReveal, let selected = cards.first(where: { $0.entryID == selectedWindowID }) {
            selected.scrollToVisible(selected.bounds)
        }
        needsSelectionReveal = false
    }
}

@MainActor
private final class SwitcherGroupButton: NSButton {
    private let pressed: () -> Void
    private let selected: Bool

    init(title: String, selected: Bool, frame: CGRect, pressed: @escaping () -> Void) {
        self.pressed = pressed
        self.selected = selected
        super.init(frame: frame)
        self.title = title
        self.toolTip = title
        bezelStyle = .roundRect
        isBordered = false
        setButtonType(.pushOnPushOff)
        state = selected ? .on : .off
        contentTintColor = selected ? .controlAccentColor : .labelColor
        (cell as? NSButtonCell)?.lineBreakMode = .byTruncatingTail
        target = self
        action = #selector(chosen)
        setAccessibilityValue(selected ? tr("Sélectionné", "Selected") : tr("Non sélectionné", "Not selected"))
    }

    required init?(coder: NSCoder) { nil }
    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 7, yRadius: 7)
        (selected ? NSColor.controlAccentColor.withAlphaComponent(0.20) : NSColor.labelColor.withAlphaComponent(0.035)).setFill()
        path.fill()
        (selected ? NSColor.controlAccentColor : NSColor.separatorColor.withAlphaComponent(0.5)).setStroke()
        path.lineWidth = selected ? 2 : 0.5
        path.stroke()
        super.draw(dirtyRect)
    }
    @objc private func chosen() { state = .on; pressed() }
}

/// Petite icône ronde du coin d'une carte (session 137), sur fond sombre, avec son aide.
final class CardCornerButton: NSButton {
    private let handler: () -> Void

    init(symbol: String, tip: String, frame: CGRect, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(frame: frame)
        image = NSImage(systemSymbolName: symbol, accessibilityDescription: tip)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 11, weight: .bold))
        isBordered = false
        imagePosition = .imageOnly
        contentTintColor = .white
        toolTip = tip
        setAccessibilityLabel(tip)
        wantsLayer = true
        layer?.cornerRadius = frame.width / 2
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.6).cgColor
        target = self
        action = #selector(fire)
    }

    required init?(coder: NSCoder) { nil }

    @objc private func fire() { handler() }
}
