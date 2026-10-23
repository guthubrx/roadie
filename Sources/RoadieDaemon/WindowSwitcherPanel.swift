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

    init(config: WindowSwitcherConfig, profile: WindowSwitcherShortcutConfig? = nil) {
        style = WindowSwitcherStyle.from(profile?.styleOverride ?? config.style)
        thumbnailWidth = CGFloat(profile?.thumbnailWidthOverride ?? config.thumbnailWidth)
        autoSize = profile?.autoSizeOverride ?? config.autoSize
        fontSize = CGFloat(profile?.fontSizeOverride ?? config.fontSize)
        fontFamily = profile?.fontFamilyOverride ?? config.fontFamily
        preview = profile?.previewOverride ?? config.preview
        presentation = WindowSwitcherPresentation(rawValue: profile?.presentationOverride ?? config.presentation) ?? .classic
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
        let labels = labelsHeight(fontSize: appearance.fontSize)
        let card: CGSize
        let columns: Int
        switch appearance.style {
        case .list:
            columns = 1
            card = CGSize(width: width, height: max(44, labels + 16))
        case .icons:
            let cardWidth = min(max(minCardWidth, appearance.fontSize * 7), max(1, width))
            columns = fit(count: count, width: width, cardWidth: cardWidth)
            card = CGSize(width: cardWidth, height: 8 + 56 + 8 + labels + 8)
        case .thumbnails:
            let base = min(max(appearance.thumbnailWidth, minCardWidth), 400)
            let cardWidth: CGFloat
            if appearance.autoSize {
                let maxColumns = max(1, Int((width + spacing) / (minCardWidth + spacing)))
                columns = min(count, maxColumns)
                cardWidth = max(1, min(base, (width - spacing * CGFloat(columns - 1)) / CGFloat(columns)))
            } else {
                columns = fit(count: count, width: width, cardWidth: base)
                cardWidth = min(base, max(1, width))
            }
            card = CGSize(width: cardWidth, height: 8 + imageHeight(cardWidth: cardWidth) + 6 + labels + 8)
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
        if !isAvailable { badges.append("indisponible") }
        if !visibilityKnown { badges.append("état non vérifié") }
        if isMinimized { badges.append("réduite") }
        if isHidden { badges.append("masquée") }
        if isFullscreen { badges.append("plein écran") }
        return badges
    }
}

extension WindowSwitcherAction {
    var menuTitle: String {
        switch self {
        case .close: "Fermer la fenêtre"
        case .minimize: "Réduire ou restaurer"
        case .hideApp: "Masquer l'application"
        case .quitApp: "Quitter l'application"
        case .maximize: "Maximiser"
        case .fullscreen: "Plein écran Roadie"
        }
    }
}

/// Carte d'une fenêtre : vignette, icône ou ligne compacte. Dessinée sans focus ni activation.
@MainActor
final class WindowSwitcherCardView: NSView {
    let entryID: WindowID
    var onClick: (() -> Void)?
    var isSelected = false {
        didSet {
            guard isSelected != oldValue else { return }
            needsDisplay = true
            setAccessibilitySelected(isSelected)
        }
    }

    override var isFlipped: Bool { true }

    init(entry: WindowSwitcherEntry, image: NSImage?, appearance: WindowSwitcherAppearance, frame: NSRect) {
        entryID = entry.id
        super.init(frame: frame)
        wantsLayer = false
        let title = entry.window.title.isEmpty ? entry.window.appName : entry.window.title
        let badges = entry.stateBadges
        let subtitle = ([entry.subtitleText, entry.window.appName] + badges).filter { !$0.isEmpty }.joined(separator: " · ")
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
        let imageView = NSImageView()
        imageView.image = image
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.imageAlignment = .alignCenter
        addSubview(imageView)
        addSubview(titleField)
        addSubview(subtitleField)
        place(imageView, titleField, subtitleField, style: appearance.style, labels: WindowSwitcherGrid.labelsHeight(fontSize: appearance.fontSize))
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(([title, entry.window.appName, entry.subtitleText] + badges).filter { !$0.isEmpty }.joined(separator: ", "))
    }

    required init?(coder: NSCoder) {
        nil
    }

    private func place(_ imageView: NSImageView, _ title: NSTextField, _ subtitle: NSTextField, style: WindowSwitcherStyle, labels: CGFloat) {
        let width = bounds.width
        switch style {
        case .thumbnails:
            let imageHeight = min(WindowSwitcherGrid.imageHeight(cardWidth: width), max(0, bounds.height - labels - 22))
            imageView.frame = CGRect(x: 8, y: 8, width: width - 16, height: imageHeight)
            title.frame = CGRect(x: 8, y: 8 + imageHeight + 6, width: width - 16, height: labels * 0.55)
            subtitle.frame = CGRect(x: 8, y: 8 + imageHeight + 6 + labels * 0.5, width: width - 16, height: labels * 0.5)
        case .icons:
            imageView.frame = CGRect(x: (width - 56) / 2, y: 8, width: 56, height: 56)
            title.alignment = .center
            subtitle.alignment = .center
            title.frame = CGRect(x: 4, y: 72, width: width - 8, height: labels * 0.55)
            subtitle.frame = CGRect(x: 4, y: 72 + labels * 0.5, width: width - 8, height: labels * 0.5)
        case .list:
            imageView.frame = CGRect(x: 12, y: (bounds.height - 28) / 2, width: 28, height: 28)
            title.frame = CGRect(x: 52, y: 6, width: width - 64, height: labels * 0.55)
            subtitle.frame = CGRect(x: 52, y: 6 + labels * 0.5, width: width - 64, height: labels * 0.5)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        guard isSelected else { return }
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 10, yRadius: 10)
        NSColor.controlAccentColor.withAlphaComponent(0.22).setFill()
        path.fill()
        NSColor.controlAccentColor.setStroke()
        path.lineWidth = 2
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
    private let previewView = NSImageView()
    private let scrollView = NSScrollView()
    private let gridContainer = WindowSwitcherFlippedView()
    private let groupScroll = NSScrollView()
    private let groupContainer = WindowSwitcherFlippedView()
    private let statusLabel = NSTextField(labelWithString: "")
    private let selectionLabel = NSTextField(labelWithString: "")
    private var detailsByID: [WindowID: String] = [:]
    private let actionsButton = NSPopUpButton(frame: .zero, pullsDown: true)
    private var groupedLayout = WindowSwitcherGroupedLayout()
    private var renderedEntries: [WindowSwitcherEntry] = []
    private var renderedImages: [WindowID: NSImage] = [:]
    private var groups = WindowSwitcherGroups(entries: [])
    private var browsing = SwitcherBrowsingState()
    private var selectedWindowID: WindowID?
    private var needsSelectionReveal = false
    private var layoutWidth: CGFloat = 0
    private var cards: [WindowSwitcherCardView] = []
    private var visibleArea = CGRect(x: 0, y: 0, width: 1280, height: 800)
    private var previewShown = false
    private let pad: CGFloat = 16
    private var searchHeight: CGFloat { max(28, switcherAppearance.fontSize * 1.4 + 8) }
    private var headerHeight: CGFloat { field.isHidden ? 16 : searchHeight + 2 * pad }
    private var footerHeight: CGFloat { max(44, switcherAppearance.fontSize * 1.4 + 18) }

    var renderedWindowIDs: [WindowID] { cards.map(\.entryID) }

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
        title = "Sélecteur de fenêtres Roadie"
        setAccessibilityLabel(title)

        effect.material = .popover
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 14
        effect.layer?.masksToBounds = true
        contentView = effect

        field.placeholderString = "Rechercher une fenêtre"
        field.sendsSearchStringImmediately = true
        field.delegate = self
        field.setAccessibilityLabel("Rechercher une fenêtre")

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

        previewView.imageScaling = .scaleProportionallyUpOrDown
        previewView.wantsLayer = true
        previewView.layer?.cornerRadius = 8
        previewView.layer?.masksToBounds = true
        previewView.setAccessibilityLabel("Aperçu de la fenêtre sélectionnée")

        statusLabel.alignment = .center
        statusLabel.textColor = .secondaryLabelColor

        actionsButton.addItem(withTitle: "Actions")
        for action in WindowSwitcherAction.allCases {
            actionsButton.addItem(withTitle: action.menuTitle)
            actionsButton.lastItem?.representedObject = action.rawValue
            actionsButton.lastItem?.target = self
            actionsButton.lastItem?.action = #selector(actionChosen(_:))
        }
        actionsButton.setAccessibilityLabel("Actions sur la fenêtre sélectionnée")
        actionsButton.isEnabled = false

        effect.addSubview(field)
        effect.addSubview(previewView)
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
        previewView.image = nil
        setStatus("Chargement des fenêtres…")
        relayout()
    }

    func render(
        entries: [WindowSwitcherEntry],
        selectedID: WindowID?,
        query: String,
        images: [WindowID: NSImage],
        previewImage: NSImage?,
        emptyMessage: String
    ) {
        needsSelectionReveal = needsSelectionReveal || selectedID != selectedWindowID || field.stringValue != query
        renderedEntries = entries
        renderedImages = images
        groups = WindowSwitcherGroups(entries: entries)
        selectedWindowID = selectedID
        browsing.reconcile(groups: groups, selectedID: selectedID)
        detailsByID = Dictionary(entries.map { ($0.id, [$0.window.title, $0.subtitleText].filter { !$0.isEmpty }.joined(separator: " · ")) }, uniquingKeysWith: { _, last in last })
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
        selectionLabel.stringValue = id.flatMap { detailsByID[$0] } ?? ""
        selectionLabel.textColor = .secondaryLabelColor
        for card in cards { card.isSelected = card.entryID == id }
        previewView.image = previewImage
        previewView.isHidden = !previewShown
        actionsButton.isEnabled = id != nil
        relayout()
    }

    func showActionError() {
        selectionLabel.stringValue = "Action refusée par l’application. Réessayez ou choisissez une autre fenêtre."
        selectionLabel.textColor = .systemOrange
    }

    func present(on screen: NSScreen) {
        layout(in: screen.visibleFrame)
        orderFrontRegardless()
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
        super.orderOut(sender)
    }

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

    private var maxWidth: CGFloat { max(280, min(visibleArea.width - 40, 1100)) }
    private var usesDesktopTabs: Bool { [.stageColumns, .desktopTabs].contains(switcherAppearance.presentation) }
    private var sideHierarchy: Bool { switcherAppearance.presentation == .hierarchy && maxWidth >= 700 && !renderedEntries.isEmpty }
    private var sidebarWidth: CGFloat { sideHierarchy ? min(260, max(180, switcherAppearance.fontSize * 10)) : 0 }
    private var navigationHeight: CGFloat {
        (usesDesktopTabs || (switcherAppearance.presentation == .hierarchy && !sideHierarchy)) && !renderedEntries.isEmpty
            ? max(40, switcherAppearance.fontSize * 1.5 + 14) : 0
    }
    private var bottomPreview: Bool { [.stageColumns, .overview].contains(switcherAppearance.presentation) }
    private var sidePreview: Bool { previewShown && maxWidth >= 700 && !bottomPreview }
    private var rightPreview: Bool { [.sections, .hierarchy].contains(switcherAppearance.presentation) }
    private var mainWidth: CGFloat { maxWidth - 2 * pad - (sideHierarchy ? sidebarWidth + pad : 0) }
    private var gridWidth: CGFloat { sidePreview ? floor((mainWidth - pad) * 0.60) : mainWidth }

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
        groupedLayout = WindowSwitcherGroupedGeometry.layout(entries: renderedEntries, appearance: switcherAppearance,
                                                              width: gridWidth, browsing: browsing)
        for frame in groupedLayout.surfaces {
            let surface = NSView(frame: frame)
            surface.wantsLayer = true
            surface.layer?.cornerRadius = 9
            surface.layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.025).cgColor
            surface.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.45).cgColor
            surface.layer?.borderWidth = 0.5
            gridContainer.addSubview(surface)
        }
        for heading in groupedLayout.headings {
            let label = NSTextField(labelWithString: heading.text)
            label.frame = heading.frame
            label.font = switcherAppearance.font(size: switcherAppearance.fontSize, weight: heading.isDesktop ? .bold : .semibold)
            label.textColor = .labelColor
            label.lineBreakMode = .byTruncatingTail
            label.maximumNumberOfLines = 1
            label.toolTip = heading.text
            gridContainer.addSubview(label)
        }
        for item in groupedLayout.cards {
            let card = WindowSwitcherCardView(entry: item.entry, image: renderedImages[item.entry.id],
                                              appearance: switcherAppearance, frame: item.frame)
            card.onClick = { [weak self] in self?.onSelect?(item.entry.id) }
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
        if abs(layoutWidth - gridWidth) > 0.5 { needsSelectionReveal = true; rebuildContent() }
        let width = maxWidth
        let innerWidth = width - 2 * pad
        let scrollWidth = gridWidth
        let previewWidth = sidePreview ? mainWidth - scrollWidth - pad : mainWidth
        let stackedPreviewHeight: CGFloat = previewShown && !sidePreview ? min(bottomPreview ? 160 : 200, previewWidth * 9 / 16) : 0
        let previewBlock = stackedPreviewHeight > 0 ? stackedPreviewHeight + pad : 0
        let availableBody = max(56, visibleArea.height - 32 - headerHeight - footerHeight - previewBlock - navigationHeight)
        let minimumBody: CGFloat = sidePreview ? 260 : (switcherAppearance.presentation == .classic ? 56 : 220)
        let bodyHeight = min(max(min(groupedLayout.size.height, visibleArea.height * 0.60), minimumBody), availableBody)
        let height = headerHeight + navigationHeight + previewBlock + bodyHeight + footerHeight
        let origin = CGPoint(x: visibleArea.midX - width / 2, y: visibleArea.midY - height / 2)
        setFrame(CGRect(origin: origin, size: CGSize(width: width, height: height)), display: true)

        field.font = switcherAppearance.font(size: switcherAppearance.fontSize, weight: .regular)
        statusLabel.font = switcherAppearance.font(size: switcherAppearance.fontSize, weight: .regular)
        actionsButton.font = switcherAppearance.font(size: max(12, switcherAppearance.fontSize - 2), weight: .regular)
        field.frame = CGRect(x: pad, y: height - pad - searchHeight, width: innerWidth, height: searchHeight)
        let mainX = pad + (sideHierarchy ? sidebarWidth + pad : 0)
        let contentY = footerHeight + (bottomPreview ? previewBlock : 0)
        previewView.frame = sidePreview
            ? CGRect(x: rightPreview ? mainX + scrollWidth + pad : mainX, y: contentY, width: previewWidth, height: bodyHeight)
            : CGRect(x: mainX, y: bottomPreview ? footerHeight : footerHeight + bodyHeight + pad,
                     width: previewWidth, height: stackedPreviewHeight)
        scrollView.frame = CGRect(x: sidePreview && !rightPreview ? mainX + previewWidth + pad : mainX,
                                  y: contentY, width: scrollWidth, height: bodyHeight)
        groupScroll.frame = sideHierarchy
            ? CGRect(x: pad, y: contentY, width: sidebarWidth, height: bodyHeight)
            : CGRect(x: pad, y: height - headerHeight - navigationHeight, width: innerWidth, height: navigationHeight)
        statusLabel.frame = scrollView.frame
        actionsButton.frame = CGRect(x: pad, y: 8, width: 190, height: footerHeight - 16)
        selectionLabel.font = switcherAppearance.font(size: max(12, switcherAppearance.fontSize - 2), weight: .regular)
        selectionLabel.frame = CGRect(x: pad + (actionsButton.isHidden ? 0 : 202), y: 12, width: max(0, innerWidth - (actionsButton.isHidden ? 0 : 202)), height: footerHeight - 20)

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
        setAccessibilityValue(selected ? "Sélectionné" : "Non sélectionné")
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
