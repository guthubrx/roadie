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

    init(config: WindowSwitcherConfig, profile: WindowSwitcherShortcutConfig? = nil) {
        style = WindowSwitcherStyle.from(profile?.styleOverride ?? config.style)
        thumbnailWidth = CGFloat(profile?.thumbnailWidthOverride ?? config.thumbnailWidth)
        autoSize = profile?.autoSizeOverride ?? config.autoSize
        fontSize = CGFloat(profile?.fontSizeOverride ?? config.fontSize)
        fontFamily = profile?.fontFamilyOverride ?? config.fontFamily
        preview = profile?.previewOverride ?? config.preview
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
            let imageHeight = WindowSwitcherGrid.imageHeight(cardWidth: width)
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
    private var hoverMonitor: Any?
    private var previousMouse: CGPoint?


    private let effect = NSVisualEffectView()
    private let field = NSSearchField()
    private let previewView = NSImageView()
    private let scrollView = NSScrollView()
    private let gridContainer = WindowSwitcherFlippedView()
    private let statusLabel = NSTextField(labelWithString: "")
    private let selectionLabel = NSTextField(labelWithString: "")
    private var detailsByID: [WindowID: String] = [:]
    private let actionsButton = NSPopUpButton(frame: .zero, pullsDown: true)
    private var grid = WindowSwitcherGridLayout(columns: 1, cardSize: .zero, frames: [], contentSize: .zero)
    private var cards: [WindowSwitcherCardView] = []
    private var visibleArea = CGRect(x: 0, y: 0, width: 1280, height: 800)
    private var previewShown = false
    private let pad: CGFloat = 16
    private var headerHeight: CGFloat { field.isHidden ? 16 : 52 }
    private let footerHeight: CGFloat = 44

    override var canBecomeKey: Bool { true }

    func configure(profile: WindowSwitcherShortcutConfig, forceSearch: Bool = false) {
        self.profile = profile
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
        guard profile.arrowNavigation, let index = cards.firstIndex(where: \.isSelected),
              let target = SwitcherNavigation.destination(from: index, direction: direction, frames: grid.frames),
              cards.indices.contains(target) else { return }
        onHighlight?(cards[target].entryID)
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
        effect.addSubview(statusLabel)
        effect.addSubview(actionsButton)
        selectionLabel.lineBreakMode = .byTruncatingMiddle
        selectionLabel.maximumNumberOfLines = 1
        effect.addSubview(selectionLabel)
    }

    func showLoading() {
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
        clearCards()
        detailsByID = Dictionary(entries.map { ($0.id, [$0.window.title, $0.subtitleText].filter { !$0.isEmpty }.joined(separator: " · ")) }, uniquingKeysWith: { _, last in last })
        if field.stringValue != query { field.stringValue = query }
        previewShown = switcherAppearance.preview && !entries.isEmpty
        grid = WindowSwitcherGrid.layout(count: entries.count, appearance: switcherAppearance, available: gridWidth)
        for (entry, frame) in zip(entries, grid.frames) {
            let card = WindowSwitcherCardView(entry: entry, image: images[entry.id], appearance: switcherAppearance, frame: frame)
            card.onClick = { [weak self] in self?.onSelect?(entry.id) }
            gridContainer.addSubview(card)
            cards.append(card)
        }
        setStatus(entries.isEmpty ? emptyMessage : "")
        select(selectedID, previewImage: previewImage)
    }

    func select(_ id: WindowID?, previewImage: NSImage?) {
        selectionLabel.stringValue = id.flatMap { detailsByID[$0] } ?? ""
        selectionLabel.textColor = .secondaryLabelColor
        for card in cards { card.isSelected = card.entryID == id }
        if let selected = cards.first(where: { $0.entryID == id }) {
            selected.scrollToVisible(selected.bounds)
        }
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
        visibleArea = screen.visibleFrame
        relayout()
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
           let key = Self.key(for: event) {
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

    /// Gauche/droite restent au champ (curseur) ; Tab, Maj+Tab et flèches haut/bas parcourent les cartes.
    static func key(for event: NSEvent) -> Key? {
        let flags = event.modifierFlags.intersection([.command, .control, .option, .shift])
        switch event.keyCode {
        case 53: return .cancel
        case 36, 76: return .confirm
        case 48:
            guard flags.isEmpty || flags == .shift else { return nil }
            return flags.contains(.shift) ? .previous : .next
        case 123: return flags.isEmpty ? .left : nil
        case 124: return flags.isEmpty ? .right : nil
        case 125: return flags.isEmpty ? .down : nil
        case 126: return flags.isEmpty ? .up : nil
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
    private var sidePreview: Bool { previewShown && maxWidth >= 700 }
    private var gridWidth: CGFloat { sidePreview ? floor((maxWidth - 3 * pad) * 0.60) : maxWidth - 2 * pad }

    private func clearCards() {
        cards.forEach { $0.removeFromSuperview() }
        cards = []
        grid = WindowSwitcherGrid.layout(count: 0, appearance: switcherAppearance, available: 0)
    }

    private func setStatus(_ text: String) {
        statusLabel.stringValue = text
        statusLabel.isHidden = text.isEmpty
        scrollView.isHidden = !text.isEmpty
    }

    private func relayout() {
        let width = maxWidth
        let innerWidth = width - 2 * pad
        let scrollWidth = gridWidth
        let previewWidth = sidePreview ? innerWidth - scrollWidth - pad : innerWidth
        let stackedPreviewHeight: CGFloat = previewShown && !sidePreview ? min(200, innerWidth * 9 / 16) : 0
        let previewBlock = stackedPreviewHeight > 0 ? stackedPreviewHeight + pad : 0
        let availableBody = max(56, visibleArea.height - 32 - headerHeight - footerHeight - previewBlock)
        let minimumBody: CGFloat = sidePreview ? 260 : 56
        let bodyHeight = min(max(min(grid.contentSize.height, visibleArea.height * 0.60), minimumBody), availableBody)
        let height = headerHeight + previewBlock + bodyHeight + footerHeight
        let origin = CGPoint(x: visibleArea.midX - width / 2, y: visibleArea.midY - height / 2)
        setFrame(CGRect(origin: origin, size: CGSize(width: width, height: height)), display: true)

        field.font = switcherAppearance.font(size: switcherAppearance.fontSize, weight: .regular)
        statusLabel.font = switcherAppearance.font(size: switcherAppearance.fontSize, weight: .regular)
        actionsButton.font = switcherAppearance.font(size: max(12, switcherAppearance.fontSize - 2), weight: .regular)
        field.frame = CGRect(x: pad, y: height - headerHeight + 12, width: innerWidth, height: 28)
        previewView.frame = sidePreview
            ? CGRect(x: pad, y: footerHeight, width: previewWidth, height: bodyHeight)
            : CGRect(x: pad, y: footerHeight + bodyHeight + pad, width: previewWidth, height: stackedPreviewHeight)
        scrollView.frame = CGRect(x: sidePreview ? pad + previewWidth + pad : pad,
                                  y: footerHeight, width: scrollWidth, height: bodyHeight)
        statusLabel.frame = scrollView.frame
        actionsButton.frame = CGRect(x: pad, y: 8, width: 190, height: 28)
        selectionLabel.font = switcherAppearance.font(size: max(12, switcherAppearance.fontSize - 2), weight: .regular)
        selectionLabel.frame = CGRect(x: pad + (actionsButton.isHidden ? 0 : 202), y: 12, width: max(0, innerWidth - (actionsButton.isHidden ? 0 : 202)), height: 24)

        let inset = max(0, (scrollWidth - grid.contentSize.width) / 2)
        gridContainer.frame = CGRect(
            x: 0, y: 0, width: scrollWidth, height: max(grid.contentSize.height, bodyHeight)
        )
        for (card, frame) in zip(cards, grid.frames) {
            card.frame = frame.offsetBy(dx: inset, dy: 0)
        }
    }
}
