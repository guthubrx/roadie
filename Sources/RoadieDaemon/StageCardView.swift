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
        let lineHeights = labels.map { max($0.0.fontSize + 5, 1) }
        let gap: CGFloat = labels.count > 1 ? 2 : 0
        let blockHeight = lineHeights.reduce(0, +) + gap * CGFloat(max(0, labels.count - 1))
        let top = max(0, (bounds.height - blockHeight) / 2)
        var y = top + blockHeight
        for (index, item) in labels.enumerated() {
            let lineHeight = lineHeights[index]
            y -= lineHeight
            item.1.draw(in: CGRect(x: item.0.offsetX, y: y + item.0.offsetY, width: bounds.width, height: lineHeight), withAttributes: [
                .foregroundColor: item.0.color,
                .font: headerFont(label: item.0),
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

    private func headerFont(label: RailLabelConfig) -> NSFont {
        let family = label.fontFamily.trimmingCharacters(in: .whitespacesAndNewlines)
        if !family.isEmpty, family.lowercased() != "system",
           let font = NSFont(name: family, size: label.fontSize) {
            return font
        }
        return NSFont.systemFont(ofSize: label.fontSize, weight: label.weight)
    }
}

@MainActor
final class StageCardView: NSControl {
    private static var appIconCache: [String: NSImage] = [:]

    let stageID: StageID
    private let stage: PersistentStage
    private let displayLabel: String
    private let isActive: Bool
    private let accent: NSColor
    private let config: RailVisualConfig
    private let presentationStates: [WindowID: WindowPresentationState]
    private let thumbnails: [WindowID: NSImage]
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
        thumbnails: [WindowID: NSImage]
    ) {
        self.stage = stage
        self.stageID = stage.id
        self.displayLabel = displayLabel
        self.isActive = isActive
        self.accent = accent
        self.config = config
        self.presentationStates = presentationStates
        self.thumbnails = thumbnails
        self.visualMembers = Self.focusFirstMembers(stage)
        super.init(frame: CGRect(x: 0, y: 0, width: 224, height: 142))
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: 224).isActive = true
        heightAnchor.constraint(equalToConstant: Self.height(for: config)).isActive = true
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

    static func height(for config: RailVisualConfig) -> CGFloat {
        config.mode == .icons ? 78 : max(150, config.previewHeight + 66)
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
        let rect = bounds.insetBy(dx: contentInset, dy: 12)
        let preview = previewArea(in: rect, visibleCount: visiblePreviewCount)
        let previewBounds = visualPreviewBounds(in: rect, preview: preview)
        if config.stageLabel.enabled, config.stageLabel.zOrder == .below {
            drawStageLabel(in: rect, previewBounds: previewBounds)
        }
        drawStagePreview(in: rect, preview: preview)
        if config.stageLabel.enabled, config.stageLabel.zOrder == .above {
            drawStageLabel(in: rect, previewBounds: previewBounds)
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

    private func drawStageLabel(in rect: CGRect, previewBounds: CGRect) {
        guard !displayLabel.isEmpty else { return }
        let labelConfig = config.stageLabel
        let now = Date()
        guard labelConfig.opacityMultiplier(now: now) > 0 else { return }
        let lineHeight = max(labelConfig.fontSize + 5, 1)
        let baseY: CGFloat
        switch labelConfig.placement {
        case .above:
            baseY = previewBounds.maxY - lineHeight
        case .below:
            baseY = previewBounds.minY - lineHeight * 0.66
        }
        let left = previewBounds.minX + labelConfig.offsetX
        let maxWidth = max(64, rect.maxX - left - 8)
        let labelRect = CGRect(
            x: left,
            y: baseY + labelConfig.offsetY,
            width: maxWidth,
            height: lineHeight
        )
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        paragraph.alignment = labelConfig.alignment.nsTextAlignment
        let label = displayLabel as NSString
        label.draw(in: labelRect, withAttributes: [
            .foregroundColor: labelConfig.resolvedColor(stageAccent: accent, now: now),
            .font: stageLabelFont(),
            .paragraphStyle: paragraph,
        ])
    }

    private func visualPreviewBounds(in rect: CGRect, preview: CGRect) -> CGRect {
        let frames: [CGRect]
        switch config.mode {
        case .stacked, .parallax:
            frames = previewItems(in: preview, maxCount: 5).map(\.rect)
        case .mosaic:
            frames = mosaicPreviewFrames(in: preview)
        case .icons:
            frames = iconPreviewFrames(in: rect.insetBy(dx: 8, dy: 18))
        }
        guard let first = frames.first else { return preview }
        return frames.dropFirst().reduce(first) { $0.union($1) }
    }

    private func stageLabelFont() -> NSFont {
        let label = config.stageLabel
        let family = label.fontFamily.trimmingCharacters(in: .whitespacesAndNewlines)
        if !family.isEmpty, family.lowercased() != "system",
           let font = NSFont(name: family, size: label.fontSize) {
            return font
        }
        return NSFont.systemFont(ofSize: label.fontSize, weight: label.weight)
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
        let members = Array(visualMembers.prefix(6))
        for (index, member) in members.enumerated() {
            let r = iconFrame(in: rect, index: index)
            rounded(r, radius: 7, color: color(for: member, index: index))
            iconLetter(for: member).draw(in: r.insetBy(dx: 0, dy: 4), withAttributes: [
                .foregroundColor: NSColor.white,
                .font: NSFont.boldSystemFont(ofSize: 11),
            ])
            drawPresentationIndicator(in: r, state: presentationState(for: member), radius: 7)
        }
        if visualMembers.count > 6 {
            "+\(visualMembers.count - 6)".draw(in: CGRect(x: rect.minX + 196, y: rect.midY - 8, width: 28, height: 18), withAttributes: [
                .foregroundColor: NSColor.white.withAlphaComponent(0.65),
                .font: NSFont.systemFont(ofSize: 11, weight: .semibold),
            ])
        }
    }

    private func drawEmpty(in rect: CGRect) {
        let line = CGRect(x: rect.minX + 18, y: rect.midY - 3, width: rect.width - 36, height: 6)
        rounded(line, radius: 3, color: NSColor.white.withAlphaComponent(0.10))
    }

    private var visiblePreviewCount: Int {
        min(visualMembers.count, 5)
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
        (0..<min(visualMembers.count, 6)).map { iconFrame(in: rect, index: $0) }
    }

    private func iconFrame(in rect: CGRect, index: Int) -> CGRect {
        CGRect(x: rect.minX + CGFloat(index) * 32, y: rect.midY - 12, width: 24, height: 24)
    }

    private func previewArea(in rect: CGRect, visibleCount: Int) -> CGRect {
        let width = min(config.previewWidth, rect.width - config.leadingPadding - config.trailingPadding)
        let height = min(config.previewHeight, rect.height - 60)
        let leftCompensation: CGFloat
        switch config.mode {
        case .parallax:
            let deepestOffset = CGFloat(max(visibleCount - 1, 0))
            let deepestScale = max(0, 1 - deepestOffset * config.parallaxScale)
            let scaledInset = width * (1 - deepestScale) / 2
            leftCompensation = max(0, deepestOffset * config.parallaxOffsetX - scaledInset)
        case .stacked:
            leftCompensation = CGFloat(max(visibleCount - 1, 0)) * config.stackedOffsetX * 0.18
        case .mosaic, .icons:
            leftCompensation = 0
        }
        return CGRect(
            x: rect.minX + config.leadingPadding + leftCompensation,
            y: rect.midY - height / 2,
            width: width,
            height: height
        )
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
                let dx = -offset * config.stackedOffsetX * 0.18
                let dy = offset * config.stackedOffsetY * 0.10
                return (index, preview.scaled(by: scale).offsetBy(dx: dx, dy: dy))
            case .parallax:
                let offset = CGFloat(index)
                let scale = 1 - offset * config.parallaxScale
                return (index, preview.scaled(by: scale).offsetBy(dx: -offset * config.parallaxOffsetX, dy: offset * config.parallaxOffsetY))
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
        let cardRect = bounds.insetBy(dx: contentInset, dy: 12)
        let preview = config.mode == .icons
            ? cardRect.insetBy(dx: 8, dy: 18)
            : previewArea(in: cardRect, visibleCount: visiblePreviewCount)
        let bounds = visualPreviewBounds(in: cardRect, preview: preview)
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
        let cardRect = bounds.insetBy(dx: contentInset, dy: 12)
        let rect = config.mode == .icons ? cardRect.insetBy(dx: 8, dy: 18) : previewArea(in: cardRect, visibleCount: visiblePreviewCount)
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
