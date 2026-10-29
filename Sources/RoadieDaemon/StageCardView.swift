import AppKit
import Foundation
import RoadieAX
import RoadieCore
import RoadieStages

@MainActor
final class RailHeaderView: NSView {
    private let displayName: String
    private let desktopID: DesktopID
    private let config: RailVisualConfig

    init(displayName: String, desktopID: DesktopID, config: RailVisualConfig) {
        self.displayName = displayName
        self.desktopID = desktopID
        self.config = config
        let width = config.headerWidth > 0 ? config.headerWidth : max(1, config.railWidth - 12)
        super.init(frame: CGRect(x: 0, y: 0, width: width, height: config.headerHeight))
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: width).isActive = true
        heightAnchor.constraint(equalToConstant: config.headerHeight).isActive = true
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let labels = [
            (config.displayLabel, render(template: config.displayLabel.template)),
            (config.desktopLabel, render(template: config.desktopLabel.template)),
        ].filter { $0.0.enabled && !$0.1.isEmpty }
        guard !labels.isEmpty else { return }
        let lineHeights = labels.map { $0.0.lineHeight }
        let gap: CGFloat = labels.count > 1 ? 2 : 0
        let blockHeight = lineHeights.reduce(0, +) + gap * CGFloat(max(0, labels.count - 1))
        let top = max(0, (bounds.height - blockHeight) / 2)
        var y = top + blockHeight
        for (index, item) in labels.enumerated() {
            let lineHeight = lineHeights[index]
            y -= lineHeight
            item.1.draw(in: CGRect(x: item.0.offsetX, y: y + item.0.offsetY, width: bounds.width, height: lineHeight), withAttributes: [
                .foregroundColor: item.0.color,
                .font: item.0.font,
                .paragraphStyle: paragraphStyle(for: item.0),
            ])
            y -= gap
        }
    }

    private func render(template: String) -> String {
        template
            .replacingOccurrences(of: "{display}", with: displayName.isEmpty ? "Roadie" : displayName)
            .replacingOccurrences(of: "{desktop}", with: String(desktopID.rawValue))
    }

    private func paragraphStyle(for label: RailLabelConfig) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        switch label.alignment {
        case .left:
            style.alignment = .left
        case .center:
            style.alignment = .center
        case .right:
            style.alignment = .right
        }
        style.lineBreakMode = .byTruncatingTail
        return style
    }

}

@MainActor
final class StageCardView: NSControl {
    private static var appIconCache: [String: NSImage] = [:]

    let stageID: StageID
    private let stage: PersistentStage
    private var displayLabel: String
    private let isActive: Bool
    private let accent: NSColor
    private let config: RailVisualConfig
    private let captionLineHeight: CGFloat
    private let presentationStates: [WindowID: WindowPresentationState]
    private var thumbnails: [WindowID: NSImage]
    private let visualMembers: [PersistentStageMember]
    private let contentInset: CGFloat = 4

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    init(
        stage: PersistentStage,
        displayLabel: String,
        isActive: Bool,
        accent: NSColor,
        config: RailVisualConfig,
        presentationStates: [WindowID: WindowPresentationState],
        thumbnails: [WindowID: NSImage],
        position: Int? = nil
    ) {
        self.stage = stage
        self.stageID = stage.id
        self.displayLabel = position.map { "\($0) — \(displayLabel)" } ?? displayLabel
        self.isActive = isActive
        self.accent = accent
        self.config = config
        self.captionLineHeight = config.stageLabel.captionLineHeight
        self.presentationStates = presentationStates
        self.thumbnails = thumbnails
        self.visualMembers = Self.focusFirstMembers(stage)
        let width = Self.width(for: config)
        let height = Self.height(for: config, memberCount: stage.members.count)
        super.init(frame: CGRect(x: 0, y: 0, width: width, height: height))
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: width).isActive = true
        heightAnchor.constraint(equalToConstant: height).isActive = true
        layer?.cornerRadius = 18
        layer?.masksToBounds = false
        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.borderWidth = 0
        layer?.borderColor = NSColor.clear.cgColor
        layer?.shadowColor = accent.cgColor
        layer?.shadowOpacity = 0
        layer?.shadowRadius = 0
        layer?.shadowOffset = .zero
    }

    /// Même rendu et mêmes miniatures, avec la légende de la position future.
    func reorderPreview(position: Int) -> StageCardView {
        StageCardView(stage: stage, displayLabel: StagePresentationOrder.name(stage, position: position),
                      isActive: isActive, accent: accent, config: config,
                      presentationStates: presentationStates, thumbnails: thumbnails, position: position)
    }

    var members: [PersistentStageMember] { stage.members }

    /// Nouvelles vignettes (SPEC-048 C-03) : redessin seulement si une image a changé. O(m).
    @discardableResult
    func updateThumbnails(_ images: [WindowID: NSImage]) -> Bool {
        guard images.count != thumbnails.count
            || images.contains(where: { thumbnails[$0.key] !== $0.value }) else { return false }
        thumbnails = images
        needsDisplay = true
        return true
    }

    /// Seule la légende varie pendant le geste ; miniatures, styles et contraintes sont réutilisés.
    func setReorderPreviewPosition(_ position: Int) {
        displayLabel = "\(position) — \(StagePresentationOrder.name(stage, position: position))"
        needsDisplay = true
    }

    static func width(for config: RailVisualConfig) -> CGFloat {
        config.mode == .icons ? max(1, config.railWidth - 12) : 224
    }

    static func height(for config: RailVisualConfig, memberCount: Int = 6) -> CGFloat {
        // Les deux marges augmentent avec le texte ; le dessin et les zones de clic restent communs.
        let extra = max(0, config.stageLabel.lineHeight - 16)
        if config.mode == .icons {
            let size = iconSize(for: config)
            let columns = iconColumns(availableWidth: width(for: config) - 24, config: config)
            let rows = max(1, ceil(CGFloat(min(7, memberCount)) / CGFloat(columns)))
            return max(config.slotHeight, 78 + extra * 2 + (rows - 1) * (size + 8))
        }
        if config.slotHeight > 0 { return max(80, config.slotHeight) }
        return max(150, config.previewHeight + 66) + max(0, config.stageLabel.captionLineHeight - 16) * 2
    }

    private static func iconSize(for config: RailVisualConfig) -> CGFloat {
        max(24, config.stageLabel.lineHeight + 8)
    }

    private static func iconColumns(availableWidth: CGFloat, config: RailVisualConfig) -> Int {
        max(1, Int((availableWidth + 8) / (iconSize(for: config) + 8)))
    }

    private static func focusFirstMembers(_ stage: PersistentStage) -> [PersistentStageMember] {
        guard let focusedWindowID = stage.focusedWindowID,
              let index = stage.members.firstIndex(where: { $0.windowID == focusedWindowID })
        else {
            return stage.members
        }
        var members = stage.members
        let focused = members.remove(at: index)
        members.insert(focused, at: 0)
        return members
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // Clic sur le fond de la carte : activer la stage. Un clic sur l'aperçu d'une fenêtre passe par `dragPayload`
    // (qui porte l'action de focus d'un plein écran natif) ; le fond ne doit jamais viser une fenêtre précise.
    func action(at point: CGPoint) -> RailAction? {
        dragPayload(at: point) == nil ? .switchStage(stageID) : nil
    }

    func snapshotImage() -> NSImage? {
        guard bounds.width > 0, bounds.height > 0,
              let representation = bitmapImageRepForCachingDisplay(in: bounds)
        else { return nil }
        cacheDisplay(in: bounds, to: representation)
        let image = NSImage(size: bounds.size)
        image.addRepresentation(representation)
        return image
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        drawCard()
    }

    private func drawCard() {
        let rect = cardContentRect
        let preview = previewArea(in: rect)
        if config.stageLabel.enabled, config.stageLabel.zOrder == .below {
            drawStageLabel()
        }
        drawStagePreview(in: rect, preview: preview)
        if config.stageLabel.enabled, config.stageLabel.zOrder == .above {
            drawStageLabel()
        }
    }

    private func drawStagePreview(in rect: CGRect, preview: CGRect) {
        switch config.mode {
        case .stacked:
            drawStacked(in: preview)
        case .mosaic:
            drawMosaic(in: preview)
        case .parallax:
            drawParallax(in: preview)
        case .icons:
            drawIcons(in: rect.insetBy(dx: 8, dy: 18))
        }
    }

    private var compactCaption: Bool {
        config.mode != .icons && config.stageLabel.enabled && config.stageLabel.placement == .below
    }

    private var cardContentRect: CGRect {
        bounds.insetBy(dx: contentInset, dy: compactCaption && config.slotHeight > 0 ? 6 : 12)
    }

    private var captionUsesPerspective: Bool {
        config.mode == .parallax && config.stageLabel.followsPerspective
    }

    private func captionHeight(previewWidth: CGFloat) -> CGFloat {
        captionLineHeight + (captionUsesPerspective ? previewWidth * abs(parallaxProjection.b) : 0)
    }

    /// Réserve verticale bornée : les couches restent visibles sans toucher la légende voisine.
    private func verticalFanReserve(previewWidth: CGFloat) -> CGFloat {
        guard compactCaption, config.slotHeight > 0, config.mode == .parallax || config.mode == .stacked else { return 0 }
        let available = cardContentRect.height - captionHeight(previewWidth: previewWidth) - config.stageLabel.gap
        return min(8, max(0, available * 0.15))
    }

    /// Rectangle du texte avant projection et transformation effectivement utilisée pour son dessin.
    func stageLabelLayout() -> (rect: CGRect, transform: CGAffineTransform) {
        let label = config.stageLabel
        let preview = previewArea(in: cardContentRect)
        let previews = hitPreviewItems().map(\.rect)
        let rawFront: CGRect
        if config.mode == .icons || config.mode == .mosaic {
            rawFront = previews.dropFirst().reduce(previews.first ?? preview) { $0.union($1) }
        } else {
            rawFront = previews.first ?? preview
        }
        let projectedFront = config.mode == .parallax ? rawFront.applying(parallaxProjection(for: rawFront)) : rawFront
        let anchor = visualMembers.isEmpty && compactCaption ? emptyMarkerFrame(in: preview) : projectedFront
        let width = captionUsesPerspective ? rawFront.width : projectedFront.width
        let lineHeight = captionLineHeight
        let visualHeight = lineHeight + (captionUsesPerspective ? width * abs(parallaxProjection.b) : 0)
        let centerY = label.placement == .above
            ? anchor.maxY + label.gap + visualHeight / 2
            : anchor.minY - label.gap - visualHeight / 2
        var rect = CGRect(x: projectedFront.midX - width / 2 + label.offsetX,
                          y: centerY - lineHeight / 2 + label.offsetY, width: width, height: lineHeight)
        let projected = captionUsesPerspective ? rect.applying(parallaxProjection(for: rect)) : rect
        let dy = max(0, -projected.minY) - max(0, projected.maxY - bounds.height)
        rect.origin.y += dy
        return (rect, captionUsesPerspective ? parallaxProjection(for: rect) : .identity)
    }

    private func drawStageLabel() {
        guard !visualMembers.isEmpty, !displayLabel.isEmpty else { return }
        let labelConfig = config.stageLabel
        let now = Date()
        guard labelConfig.opacityMultiplier(now: now) > 0,
              let context = NSGraphicsContext.current?.cgContext else { return }
        let layout = stageLabelLayout()
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        paragraph.alignment = labelConfig.alignment.nsTextAlignment
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.8)
        shadow.shadowBlurRadius = 2
        shadow.shadowOffset = .zero
        context.saveGState()
        context.concatenate(layout.transform)
        (displayLabel as NSString).draw(in: layout.rect, withAttributes: [
            .foregroundColor: labelConfig.resolvedColor(stageAccent: accent, now: now),
            .font: labelConfig.captionFont,
            .paragraphStyle: paragraph,
            .shadow: shadow,
        ])
        context.restoreGState()
    }

    private func drawStacked(in rect: CGRect) {
        guard !visualMembers.isEmpty else {
            drawEmpty(in: rect)
            return
        }
        let items = previewItems(in: rect, maxCount: 5)
        drawActiveStageShadowBehind(items)
        for item in items.reversed() {
            drawPreview(item.rect, index: item.index)
        }
    }

    private func drawMosaic(in rect: CGRect) {
        guard !visualMembers.isEmpty else {
            drawEmpty(in: rect)
            return
        }
        for (index, frame) in mosaicPreviewFrames(in: rect).enumerated() {
            drawPreview(frame, index: index)
        }
    }

    private func drawParallax(in rect: CGRect) {
        guard !visualMembers.isEmpty else {
            drawEmpty(in: rect)
            return
        }
        let items = previewItems(in: rect, maxCount: 5)
        drawActiveStageShadowBehind(items)
        for item in items.reversed() {
            drawPreview(item.rect, index: item.index, skewed: true)
        }
    }

    private func drawIcons(in rect: CGRect) {
        guard !visualMembers.isEmpty else {
            drawEmpty(in: rect)
            return
        }
        let members = Array(visualMembers.prefix(iconMemberCount))
        for (index, member) in members.enumerated() {
            let r = iconFrame(in: rect, index: index)
            rounded(r, radius: 7, color: color(for: member, index: index))
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .center
            iconLetter(for: member).draw(in: r.insetBy(dx: 0, dy: 4), withAttributes: [
                .foregroundColor: NSColor.white,
                .font: config.stageLabel.font,
                .paragraphStyle: paragraph,
            ])
            drawPresentationIndicator(in: r, state: presentationState(for: member), radius: 7)
        }
        if visualMembers.count > 6 {
            "+\(visualMembers.count - iconMemberCount)".draw(in: iconFrame(in: rect, index: iconMemberCount), withAttributes: [
                .foregroundColor: NSColor.white.withAlphaComponent(0.65),
                .font: config.stageLabel.font,
            ])
        }
    }

    private func drawEmpty(in rect: CGRect) {
        // Une destination nommée reste identifiable après le fondu des libellés (SPEC-053).
        let projected = config.mode == .parallax ? rect.applying(parallaxProjection(for: rect)) : rect
        let frame = projected.intersection(bounds).insetBy(dx: 2, dy: 2)
        guard frame.width > 0, frame.height > 0 else { return }
        let path = NSBezierPath(roundedRect: frame, xRadius: 6, yRadius: 6)
        NSColor.labelColor.withAlphaComponent(0.04).setFill()
        path.fill()
        NSColor.labelColor.withAlphaComponent(0.30).setStroke()
        path.lineWidth = 1
        path.setLineDash([3, 3], count: 2, phase: 0)
        path.stroke()
        let font = config.stageLabel.captionFont
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineBreakMode = .byTruncatingTail
        let name = (displayLabel.isEmpty ? stage.name : displayLabel).trimmingCharacters(in: .whitespacesAndNewlines)
        let empty = tr("Vide", "Empty")
        let text = name.isEmpty ? empty : "\(name)\n\(empty)"
        let height = min(frame.height, ceil(font.ascender - font.descender + font.leading) * (name.isEmpty ? 1 : 2))
        (text as NSString).draw(in: CGRect(x: frame.minX + 6, y: frame.midY - height / 2,
                                         width: max(0, frame.width - 12), height: height), withAttributes: [
            .font: font, .foregroundColor: NSColor.secondaryLabelColor, .paragraphStyle: paragraph,
        ])
    }

    private func emptyMarkerFrame(in rect: CGRect) -> CGRect {
        guard compactCaption else {
            return CGRect(x: rect.minX + 18, y: rect.midY - 3, width: max(1, rect.width - 36), height: 6)
        }
        let frame = config.mode == .parallax ? rect.applying(parallaxProjection(for: rect)) : rect
        return CGRect(x: frame.minX + frame.width * 0.15, y: frame.minY, width: frame.width * 0.7, height: 6)
    }

    private func mosaicPreviewFrames(in rect: CGRect) -> [CGRect] {
        let count = min(visualMembers.count, 6)
        guard count > 0 else { return [] }
        let cols = count <= 2 ? count : 2
        let rows = Int(ceil(Double(count) / Double(cols)))
        let gap: CGFloat = 6
        let cellW = (rect.width - CGFloat(cols - 1) * gap) / CGFloat(cols)
        let cellH = (rect.height - 34 - CGFloat(rows - 1) * gap) / CGFloat(rows)
        return (0..<count).map { index in
            let col = index % cols
            let row = index / cols
            return CGRect(
                x: rect.minX + CGFloat(col) * (cellW + gap),
                y: rect.minY + CGFloat(row) * (cellH + gap),
                width: cellW,
                height: cellH
            )
        }
    }

    private func iconPreviewFrames(in rect: CGRect) -> [CGRect] {
        (0..<iconMemberCount).map { iconFrame(in: rect, index: $0) }
    }

    private var iconMemberCount: Int { min(visualMembers.count, 6) }

    /// Tous les cadres dessinés, compteur compris ; les cibles de clic ne comprennent que les membres.
    func iconDisplayFrames() -> [CGRect] {
        let rect = cardContentRect.insetBy(dx: 8, dy: 18)
        return (0..<min(7, visualMembers.count)).map { iconFrame(in: rect, index: $0) }
    }

    private func iconFrame(in rect: CGRect, index: Int) -> CGRect {
        let size = Self.iconSize(for: config)
        let columns = Self.iconColumns(availableWidth: rect.width, config: config)
        let slots = min(7, visualMembers.count)
        let rows = ceil(CGFloat(slots) / CGFloat(columns))
        let blockHeight = rows * size + max(0, rows - 1) * 8
        return CGRect(
            x: rect.minX + CGFloat(index % columns) * (size + 8),
            y: rect.midY + blockHeight / 2 - size - CGFloat(index / columns) * (size + 8),
            width: size, height: size
        )
    }

    /// Même réserve pour cinq fenêtres : la première vignette reste sur la même colonne.
    /// La réserve se réduit si nécessaire pour garder l'éventail dans la largeur du rail.
    private var previewAvailableWidth: CGFloat {
        max(1, min(bounds.width - 8, config.railWidth - 20) - config.leadingPadding - config.trailingPadding)
    }

    private var parallaxProjection: CGAffineTransform {
        Self.parallaxTransform(for: .zero, rotation: config.parallaxRotation)
    }

    private var parallaxXScale: CGFloat { parallaxProjection.a }

    private func parallaxProjection(for rect: CGRect) -> CGAffineTransform {
        Self.parallaxTransform(for: rect, rotation: config.parallaxRotation)
    }

    private func horizontalStep(width: CGFloat) -> CGFloat {
        let scale = config.mode == .parallax ? parallaxXScale : 1
        let shrink = config.mode == .parallax ? config.parallaxScale : config.stackedScale
        let requested = config.mode == .parallax ? config.parallaxOffsetX : config.stackedOffsetX * 0.18
        return min(requested, max(0, (previewAvailableWidth - width * scale) / 4 + width * shrink * scale / 2))
    }

    private func previewArea(in rect: CGRect) -> CGRect {
        let scale = config.mode == .parallax ? parallaxXScale : 1
        let width = min(config.previewWidth, previewAvailableWidth / scale)
        let verticalReserve = config.slotHeight > 0 ? 2 * config.verticalPadding : 60
        let perspectiveHeight = config.mode == .parallax ? width * abs(parallaxProjection.b) : 0
        let hasCompactLayout = compactCaption && config.slotHeight > 0
        let height = hasCompactLayout
            ? max(1, min(config.previewHeight, rect.height - captionHeight(previewWidth: width) - config.stageLabel.gap - perspectiveHeight - verticalFanReserve(previewWidth: width)))
            : max(1, min(config.previewHeight, rect.height - verticalReserve))
        let leftCompensation: CGFloat
        switch config.mode {
        case .parallax, .stacked:
            let shrink = config.mode == .parallax ? config.parallaxScale : config.stackedScale
            leftCompensation = 4 * max(0, horizontalStep(width: width) - width * shrink * scale / 2)
                - width * (1 - scale) / 2
        case .mosaic, .icons:
            leftCompensation = 0
        }
        return CGRect(
            x: rect.minX + config.leadingPadding + leftCompensation,
            y: hasCompactLayout
                ? rect.minY + captionHeight(previewWidth: width) + config.stageLabel.gap + perspectiveHeight / 2
                : rect.midY - height / 2,
            width: width,
            height: height
        )
    }

    /// Cadres réellement dessinés, aussi utilisés par le repère de dépôt et les vérifications de géométrie.
    func previewDisplayFrames() -> [CGRect] {
        hitPreviewItems().map { item in
            config.mode == .parallax
                ? item.rect.applying(Self.parallaxTransform(for: item.rect, rotation: config.parallaxRotation))
                : item.rect
        }
    }

    private func previewRects(in rect: CGRect, maxCount: Int) -> [CGRect] {
        let count = min(visualMembers.count, maxCount)
        let base = CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height)
        return (0..<count).map { _ in base }
    }

    private func previewItems(in rect: CGRect, maxCount: Int) -> [(index: Int, rect: CGRect)] {
        previewRects(in: rect, maxCount: maxCount).enumerated().map { item in
            let index = item.offset
            let preview = item.element
            switch config.mode {
            case .stacked:
                let offset = CGFloat(index)
                let scale = 1 - offset * config.stackedScale
                let dx = -offset * horizontalStep(width: preview.width)
                let step = compactCaption && config.slotHeight > 0
                    ? min(config.stackedOffsetY * 0.10, preview.height * config.stackedScale / 2 + verticalFanReserve(previewWidth: preview.width) / 4)
                    : config.stackedOffsetY * 0.10
                let dy = offset * step
                return (index, preview.scaled(by: scale).offsetBy(dx: dx, dy: dy))
            case .parallax:
                let offset = CGFloat(index)
                let scale = 1 - offset * config.parallaxScale
                let projectedHeight = preview.height + preview.width * abs(parallaxProjection.b)
                let step = compactCaption && config.slotHeight > 0
                    ? min(config.parallaxOffsetY, projectedHeight * config.parallaxScale / 2 + verticalFanReserve(previewWidth: preview.width) / 4)
                    : config.parallaxOffsetY
                return (index, preview.scaled(by: scale).offsetBy(dx: -offset * horizontalStep(width: preview.width), dy: offset * step))
            case .mosaic, .icons:
                return (index, preview)
            }
        }
    }

    private func drawPreview(_ rect: CGRect, index: Int, skewed: Bool = false) {
        guard !rect.isEmpty else { return }
        if skewed {
            guard let context = NSGraphicsContext.current?.cgContext else { return }
            context.saveGState()
            applyParallaxTransform(for: rect, in: context)
            drawPreviewBody(rect, index: index, darkened: true)
            context.restoreGState()
            return
        }
        drawPreviewBody(rect, index: index, darkened: false)
    }

    private func drawPreviewBody(_ rect: CGRect, index: Int, darkened: Bool) {
        let path = NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6)
        let member = visualMembers[safe: index]
        if let image = member.flatMap({ thumbnails[$0.windowID] }) {
            NSGraphicsContext.saveGraphicsState()
            path.addClip()
            let opacity = opacity(for: index)
            image.draw(in: rect, from: aspectFillSourceRect(image.size, for: rect), operation: .sourceOver, fraction: opacity)
            NSGraphicsContext.restoreGraphicsState()
        } else {
            color(for: member, index: index).withAlphaComponent(opacity(for: index)).setFill()
            path.fill()
        }
        if let member {
            drawAppIcon(for: member, in: rect, opacity: opacity(for: index))
        }
        NSColor.white.withAlphaComponent(isActive ? 0.34 : 0.18).setStroke()
        path.lineWidth = 1
        path.stroke()
        drawPresentationIndicator(in: rect, state: presentationState(for: member), radius: 6)
        if darkened {
            NSColor.black.withAlphaComponent(config.parallaxDarken * CGFloat(index)).setFill()
            NSBezierPath(roundedRect: rect.insetBy(dx: 12, dy: 10), xRadius: 4, yRadius: 4).fill()
        }
    }

    private func presentationState(for member: PersistentStageMember?) -> WindowPresentationState {
        guard let member else { return .normal }
        return presentationStates[member.windowID] ?? .normal
    }

    private func drawPresentationIndicator(in rect: CGRect, state: WindowPresentationState, radius: CGFloat) {
        switch state {
        case .normal:
            return
        case .maximized:
            drawCornerIndicator(in: rect.insetBy(dx: 1.5, dy: 1.5))
        case .nativeFullscreen:
            drawFullIndicator(in: rect.insetBy(dx: 1.5, dy: 1.5), radius: radius)
        }
    }

    private func drawFullIndicator(in rect: CGRect, radius: CGFloat) {
        let shadow = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
        NSColor.black.withAlphaComponent(0.70).setStroke()
        shadow.lineWidth = 4
        shadow.stroke()

        let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
        presentationIndicatorColor.setStroke()
        path.lineWidth = 2.2
        path.stroke()
    }

    private func drawCornerIndicator(in rect: CGRect) {
        let length = min(18, max(8, min(rect.width, rect.height) * 0.28))
        let shadow = cornerPath(in: rect, length: length)
        NSColor.black.withAlphaComponent(0.70).setStroke()
        shadow.lineWidth = 4
        shadow.stroke()

        let path = cornerPath(in: rect, length: length)
        presentationIndicatorColor.setStroke()
        path.lineWidth = 2.2
        path.stroke()
    }

    private func cornerPath(in rect: CGRect, length: CGFloat) -> NSBezierPath {
        let path = NSBezierPath()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY + length))
        path.line(to: CGPoint(x: rect.minX, y: rect.minY))
        path.line(to: CGPoint(x: rect.minX + length, y: rect.minY))

        path.move(to: CGPoint(x: rect.maxX - length, y: rect.minY))
        path.line(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.line(to: CGPoint(x: rect.maxX, y: rect.minY + length))

        path.move(to: CGPoint(x: rect.maxX, y: rect.maxY - length))
        path.line(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.line(to: CGPoint(x: rect.maxX - length, y: rect.maxY))

        path.move(to: CGPoint(x: rect.minX + length, y: rect.maxY))
        path.line(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.line(to: CGPoint(x: rect.minX, y: rect.maxY - length))
        return path
    }

    private var presentationIndicatorColor: NSColor {
        NSColor.white.withAlphaComponent(0.94)
    }

    private func drawAppIcon(for member: PersistentStageMember, in rect: CGRect, opacity: CGFloat) {
        guard let icon = Self.appIcon(for: member.bundleID) else { return }
        let iconSize = min(max(rect.height * 0.30, 18), 30)
        let padding: CGFloat = 6
        let iconRect = CGRect(
            x: rect.minX + padding,
            y: rect.minY + padding,
            width: iconSize,
            height: iconSize
        )
        icon.draw(
            in: iconRect,
            from: CGRect(origin: .zero, size: icon.size),
            operation: .sourceOver,
            fraction: min(1, 0.92 * opacity)
        )
    }

    private static func appIcon(for bundleID: String) -> NSImage? {
        if let cached = appIconCache[bundleID] {
            return cached
        }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return nil
        }
        let icon = NSWorkspace.shared.icon(forFile: url.path).copy() as? NSImage ?? NSWorkspace.shared.icon(forFile: url.path)
        icon.size = NSSize(width: 64, height: 64)
        let cleanedIcon = icon.removingEdgeWhiteBackground()
        appIconCache[bundleID] = cleanedIcon
        return cleanedIcon
    }

    private func drawActiveStageShadowBehind(_ items: [(index: Int, rect: CGRect)]) {
        guard isActive, let first = items.first?.rect else { return }
        let union = items.dropFirst().reduce(first) { $0.union($1.rect) }
        let center = CGPoint(x: union.midX, y: union.midY)
        guard let context = NSGraphicsContext.current?.cgContext,
              let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let gradient = CGGradient(
                  colorsSpace: colorSpace,
                  colors: [
                      accent.withAlphaComponent(0.56).cgColor,
                      accent.withAlphaComponent(0.38).cgColor,
                      accent.withAlphaComponent(0.20).cgColor,
                      accent.withAlphaComponent(0.075).cgColor,
                      accent.withAlphaComponent(0).cgColor,
                  ] as CFArray,
                  locations: [0, 0.18, 0.44, 0.74, 1]
        )
        else { return }
        let xScale: CGFloat = 1.12
        let yScale: CGFloat = 0.86
        let availableLeft = max(12, center.x - bounds.minX - 10)
        let availableRight = max(12, bounds.maxX - center.x - 10)
        let availableTop = max(12, bounds.maxY - center.y - 10)
        let availableBottom = max(12, center.y - bounds.minY - 10)
        let maxHorizontalRadius = min(availableLeft, availableRight) / xScale
        let maxVerticalRadius = min(availableTop, availableBottom) / yScale
        let desiredRadius = max(union.width, union.height) * 1.70
        let radius = max(72, min(desiredRadius, maxHorizontalRadius, maxVerticalRadius))
        context.saveGState()
        context.translateBy(x: center.x, y: center.y)
        context.scaleBy(x: xScale, y: yScale)
        context.drawRadialGradient(
            gradient,
            startCenter: .zero,
            startRadius: 0,
            endCenter: .zero,
            endRadius: radius,
            options: [.drawsAfterEndLocation]
        )
        context.restoreGState()
    }

    private func applyParallaxTransform(for rect: CGRect, in context: CGContext) {
        context.concatenate(Self.parallaxTransform(for: rect, rotation: config.parallaxRotation))
    }

    /// Compression horizontale et cisaillement d'un aperçu parallax autour de son centre, communs au dessin
    /// et au test du clic (REL-040). Déterminant = xScale >= 0,45 : toujours inversible.
    static func parallaxTransform(for rect: CGRect, rotation: CGFloat) -> CGAffineTransform {
        let angle = min(rotation, 75) * .pi / 180
        let xScale = max(0.45, cos(angle))
        let perspective = sin(angle) * 0.12
        return CGAffineTransform(translationX: -rect.midX, y: -rect.midY)
            .concatenating(CGAffineTransform(a: xScale, b: perspective, c: 0, d: 1, tx: 0, ty: 0))
            .concatenating(CGAffineTransform(translationX: rect.midX, y: rect.midY))
    }

    private func opacity(for index: Int) -> CGFloat {
        let perLayer = config.mode == .stacked ? config.stackedOpacity : config.parallaxOpacity
        return max(0.25, (isActive ? 0.95 : 0.82) - CGFloat(index) * perLayer)
    }

    private func aspectFillSourceRect(_ imageSize: NSSize, for rect: CGRect) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0, rect.width > 0, rect.height > 0 else { return .zero }
        let sourceAspect = imageSize.width / imageSize.height
        let targetAspect = rect.width / rect.height
        if sourceAspect > targetAspect {
            let width = imageSize.height * targetAspect
            return CGRect(x: (imageSize.width - width) / 2, y: 0, width: width, height: imageSize.height)
        }
        let height = imageSize.width / targetAspect
        return CGRect(
            x: 0,
            y: (imageSize.height - height) / 2,
            width: imageSize.width,
            height: height
        )
    }

    func dragPayload(at point: CGPoint) -> RailDragPayload? {
        guard let hit = hitPreview(at: point) else { return nil }
        return RailDragPayload(
            windowID: hit.member.windowID,
            sourceStageID: stageID,
            clickAction: presentationState(for: hit.member) == .nativeFullscreen
                ? nativeFullscreenFocusAction(for: hit.member)
                : nil,
            grabUnit: CGPoint(
                x: min(1, max(0, (hit.localPoint.x - hit.rect.minX) / max(1, hit.rect.width))),
                y: min(1, max(0, (hit.localPoint.y - hit.rect.minY) / max(1, hit.rect.height)))
            )
        )
    }

    func windowID(at point: CGPoint) -> WindowID? {
        hitPreview(at: point)?.member.windowID
    }

    func windowInsertionIndex(at point: CGPoint) -> Int {
        let count = stage.members.count
        guard count > 0 else { return 0 }
        let cardRect = cardContentRect
        let preview = config.mode == .icons
            ? cardRect.insetBy(dx: 8, dy: 18)
            : previewArea(in: cardRect)
        let frames = previewDisplayFrames()
        let bounds = frames.dropFirst().reduce(frames.first ?? preview) { $0.union($1) }
        let clampedY = min(max(point.y, bounds.minY), bounds.maxY)
        let unitFromTop = 1 - ((clampedY - bounds.minY) / max(1, bounds.height))
        return min(max(Int((unitFromTop * CGFloat(count)).rounded()), 0), count)
    }

    /// `localPoint` est le point dans le repère de l'aperçu avant transformation : en parallax, le clic est
    /// ramené par l'inverse de la transformée du dessin, pour viser la forme réellement visible (REL-040).
    private func hitPreview(at point: CGPoint) -> (member: PersistentStageMember, rect: CGRect, localPoint: CGPoint)? {
        for item in hitPreviewItems() {
            let localPoint = config.mode == .parallax
                ? point.applying(Self.parallaxTransform(for: item.rect, rotation: config.parallaxRotation).inverted())
                : point
            guard item.rect.contains(localPoint),
                  let member = visualMembers[safe: item.index]
            else { continue }
            return (member, item.rect, localPoint)
        }
        return nil
    }

    private func nativeFullscreenFocusAction(for member: PersistentStageMember) -> RailAction {
        .focusNativeFullscreen(member.windowID, member.bundleID, stageID)
    }

    /// Aperçus dans l'ordre de test du clic, du dessus vers le dessous : en stacked/parallax, dessinés
    /// de l'arrière vers l'avant, l'index 0 est visuellement au-dessus. Mêmes cadres que le dessin (MIN-001).
    private func hitPreviewItems() -> [(index: Int, rect: CGRect)] {
        let cardRect = cardContentRect
        let rect = config.mode == .icons ? cardRect.insetBy(dx: 8, dy: 18) : previewArea(in: cardRect)
        switch config.mode {
        case .stacked, .parallax:
            return previewItems(in: rect, maxCount: 5)
        case .mosaic:
            return Array(mosaicPreviewFrames(in: rect).enumerated()).map { ($0.offset, $0.element) }
        case .icons:
            return Array(iconPreviewFrames(in: rect).enumerated()).map { ($0.offset, $0.element) }
        }
    }

    private func rounded(_ rect: CGRect, radius: CGFloat, color: NSColor) {
        color.setFill()
        NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
    }

    private func color(for member: PersistentStageMember?, index: Int) -> NSColor {
        let seed = Int(member?.windowID.rawValue ?? UInt32(index + 1))
        let palette: [NSColor] = [
            NSColor(calibratedRed: 0.15, green: 0.35, blue: 0.72, alpha: 0.96),
            NSColor(calibratedRed: 0.43, green: 0.28, blue: 0.72, alpha: 0.96),
            NSColor(calibratedRed: 0.12, green: 0.50, blue: 0.42, alpha: 0.96),
            NSColor(calibratedRed: 0.64, green: 0.32, blue: 0.16, alpha: 0.96),
        ]
        return palette[abs(seed) % palette.count]
    }

    private func iconLetter(for member: PersistentStageMember) -> String {
        let source = member.bundleID.split(separator: ".").last.map(String.init) ?? member.title
        return String(source.prefix(1)).uppercased()
    }
}

private extension NSImage {
    func removingEdgeWhiteBackground() -> NSImage {
        let pixelWidth = 64
        let pixelHeight = 64
        let bytesPerPixel = 4
        let bytesPerRow = pixelWidth * bytesPerPixel
        var pixels = [UInt8](repeating: 0, count: pixelHeight * bytesPerRow)
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                  data: &pixels,
                  width: pixelWidth,
                  height: pixelHeight,
                  bitsPerComponent: 8,
                  bytesPerRow: bytesPerRow,
                  space: colorSpace,
                  bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
              ),
              let cgImage = cgImage(forProposedRect: nil, context: nil, hints: nil)
        else {
            return self
        }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight))

        func offset(_ x: Int, _ y: Int) -> Int {
            y * bytesPerRow + x * bytesPerPixel
        }

        func isEdgeWhite(_ x: Int, _ y: Int) -> Bool {
            let i = offset(x, y)
            let red = pixels[i]
            let green = pixels[i + 1]
            let blue = pixels[i + 2]
            let alpha = pixels[i + 3]
            return alpha > 0 && red >= 238 && green >= 238 && blue >= 238
        }

        var visited = [Bool](repeating: false, count: pixelWidth * pixelHeight)
        var queue: [(x: Int, y: Int)] = []

        func enqueue(_ x: Int, _ y: Int) {
            guard x >= 0, x < pixelWidth, y >= 0, y < pixelHeight else { return }
            let index = y * pixelWidth + x
            guard !visited[index], isEdgeWhite(x, y) else { return }
            visited[index] = true
            queue.append((x, y))
        }

        for x in 0..<pixelWidth {
            enqueue(x, 0)
            enqueue(x, pixelHeight - 1)
        }
        for y in 0..<pixelHeight {
            enqueue(0, y)
            enqueue(pixelWidth - 1, y)
        }

        var cursor = 0
        while cursor < queue.count {
            let point = queue[cursor]
            cursor += 1
            let i = offset(point.x, point.y)
            pixels[i] = 0
            pixels[i + 1] = 0
            pixels[i + 2] = 0
            pixels[i + 3] = 0
            enqueue(point.x + 1, point.y)
            enqueue(point.x - 1, point.y)
            enqueue(point.x, point.y + 1)
            enqueue(point.x, point.y - 1)
        }

        guard let cleaned = context.makeImage() else {
            return self
        }
        return NSImage(cgImage: cleaned, size: NSSize(width: pixelWidth, height: pixelHeight))
    }
}

private extension CGRect {
    func scaled(by rawScale: CGFloat) -> CGRect {
        let scale = max(0.35, rawScale)
        let newWidth = width * scale
        let newHeight = height * scale
        return CGRect(
            x: midX - newWidth / 2,
            y: midY - newHeight / 2,
            width: newWidth,
            height: newHeight
        )
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
