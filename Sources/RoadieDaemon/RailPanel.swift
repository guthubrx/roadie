import AppKit
import Foundation
import RoadieAX
import RoadieCore
import RoadieStages

@MainActor
final class RailDragGhostWindow: NSPanel {
    private let ghostView = RailDragGhostView()

    init() {
        super.init(
            contentRect: CGRect(x: 0, y: 0, width: 150, height: 96),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        ignoresMouseEvents = true
        hasShadow = false
        alphaValue = 0.86
        contentView = ghostView
    }

    func show(image: NSImage?, at point: CGPoint, grabUnit: CGPoint, usesBackdrop: Bool = true) {
        ghostView.image = image
        ghostView.usesBackdrop = usesBackdrop
        setContentSize(ghostView.preferredSize(for: image, usesBackdrop: usesBackdrop))
        move(to: point, grabUnit: grabUnit)
        orderFrontRegardless()
        ghostView.needsDisplay = true
    }

    func move(to point: CGPoint, grabUnit: CGPoint) {
        let contentInset = ghostView.contentInset
        let contentWidth = max(1, frame.width - contentInset * 2)
        let contentHeight = max(1, frame.height - contentInset * 2)
        setFrameOrigin(CGPoint(
            x: point.x - (contentInset + grabUnit.x * contentWidth),
            y: point.y - (contentInset + grabUnit.y * contentHeight)
        ))
    }

    func hide() {
        orderOut(nil)
    }
}

@MainActor
final class RailDragGhostView: NSView {
    var image: NSImage?
    var usesBackdrop = true

    var contentInset: CGFloat {
        usesBackdrop ? 5 : 0
    }

    func preferredSize(for image: NSImage?, usesBackdrop: Bool) -> CGSize {
        guard let image, image.size.width > 0, image.size.height > 0 else {
            return CGSize(width: 148, height: 92)
        }
        let maxSize = CGSize(width: 226, height: 170)
        let scale = min(maxSize.width / image.size.width, maxSize.height / image.size.height, 1)
        let inset = usesBackdrop ? 10.0 : 0.0
        return CGSize(width: image.size.width * scale + inset, height: image.size.height * scale + inset)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let rect = bounds.insetBy(dx: contentInset, dy: contentInset)
        let path = NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8)

        if usesBackdrop {
            NSGraphicsContext.saveGraphicsState()
            let shadow = NSShadow()
            shadow.shadowBlurRadius = 16
            shadow.shadowOffset = .zero
            shadow.shadowColor = NSColor.black.withAlphaComponent(0.45)
            shadow.set()
            NSColor.black.withAlphaComponent(0.30).setFill()
            path.fill()
            NSGraphicsContext.restoreGraphicsState()
        }

        if let image {
            NSGraphicsContext.saveGraphicsState()
            if usesBackdrop {
                path.addClip()
            }
            image.draw(in: rect, from: CGRect(origin: .zero, size: image.size), operation: .sourceOver, fraction: 0.92)
            NSGraphicsContext.restoreGraphicsState()
        } else {
            NSColor.systemGreen.withAlphaComponent(0.45).setFill()
            path.fill()
        }

        if usesBackdrop {
            NSColor.white.withAlphaComponent(0.42).setStroke()
            path.lineWidth = 1
            path.stroke()
        }
    }
}

@MainActor
final class RailPanel: NSPanel {
    let stack = RailStackView()
    let stageScrollView = NSScrollView()
    private let horizontalInset: CGFloat = 6
    private var visibleStageIDs: [StageID] = []
    /// Ordre complet du scope, stages vides comprises : base du rang transmis à reorderStage (REL-039).
    private var orderedStageIDs: [StageID] = []
    private var emptyStageIDs: [StageID] = []
    private var emptyClickHideActive = true
    private var emptyClickSafetyMargin: CGFloat = 12
    private var autoHide = false
    private var edgeHitWidth: CGFloat = 8
    private var edgeMagnetismWidth: CGFloat = 24
    private var animationDuration: TimeInterval = 0.16
    private var hideDelay: TimeInterval = 0.35
    private var displayID: DisplayID?
    private var runtimeStore: RailRuntimeStateStore?
    var onVisibleWidthChanged: ((DisplayID) -> Void)?
    /// Dépliage du rail replié (SPEC-051 C-06) : ses vignettes reprennent.
    var onRevealed: ((DisplayID) -> Void)?
    private var screenFrame = CGRect.zero
    private var expandedFrame = CGRect.zero
    private var collapsedFrame = CGRect.zero
    private var interactionFrame = CGRect.zero
    private var isCollapsed = false
    /// Rail replié (masquage automatique) : ses vignettes ne sont pas capturées (SPEC-051 C-06).
    var isRailCollapsed: Bool { isCollapsed }
    private var lastPersistedVisibleWidth: Double?
    private var hideAfter: Date?
    private var recordingIndicatorView: RecordingIndicatorView?
    private var reorderMagnetism: CGFloat = 50
    private var reorderPreview: RailStageReorderPreviewView?
    private var windowDropPreview: RailWindowDropPreviewView?
    private var reorderGeometry: ReorderGeometry?
    private var reorderCopies: [StageID: StageCardView] = [:]
    private var reorderOriginals: [(card: StageCardView, opacity: Float)] = []

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        ignoresMouseEvents = false
        hasShadow = false

        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 13
        stack.edgeInsets = NSEdgeInsets(top: 20, left: horizontalInset, bottom: 20, right: 18)
        // Le panneau reste de la hauteur de l'écran, même quand les cartes débordent.
        let root = NSView()
        contentView = root
        stageScrollView.frame = root.bounds
        stageScrollView.autoresizingMask = [.width, .height]
        stageScrollView.drawsBackground = false
        stageScrollView.hasVerticalScroller = true
        stageScrollView.autohidesScrollers = true
        stageScrollView.scrollerStyle = .overlay
        stageScrollView.documentView = stack
        root.addSubview(stageScrollView)
    }

    func position(on screen: NSScreen, displayID: DisplayID, config: RailVisualConfig, runtimeStore: RailRuntimeStateStore) {
        let frame = screen.frame
        screenFrame = frame
        let wasAutoHide = autoHide
        let runtimeState = runtimeStore.load()
        self.displayID = displayID
        self.runtimeStore = runtimeStore
        autoHide = config.autoHide && !runtimeState.isPinned
        edgeHitWidth = config.edgeHitWidth
        edgeMagnetismWidth = config.edgeMagnetismWidth
        animationDuration = config.animationDuration
        hideDelay = config.hideDelay
        expandedFrame = CGRect(x: frame.minX, y: frame.minY, width: config.railWidth, height: frame.height)
        collapsedFrame = CGRect(x: frame.minX, y: frame.minY, width: edgeHitWidth, height: frame.height)
        interactionFrame = expandedFrame.intersection(screen.visibleFrame)
        if interactionFrame.isNull || interactionFrame.isEmpty {
            interactionFrame = expandedFrame
        }
        if !autoHide {
            isCollapsed = false
        } else if !wasAutoHide {
            isCollapsed = true
        }
        applyAutoHideFrame(animated: false)
        stageScrollView.frame = CGRect(x: 0, y: interactionFrame.minY - frame.minY,
                                       width: self.frame.width, height: interactionFrame.height)
    }

    func updateAutoHide(mouse: CGPoint, canHide: Bool) {
        guard autoHide else { return }
        if isCollapsed {
            if revealFrame.contains(mouse) {
                setCollapsed(false, animated: true)
            }
            return
        }
        if expandedFrame.contains(mouse) {
            hideAfter = nil
            return
        }
        guard canHide else { return }
        if hideDelay <= 0 {
            setCollapsed(true, animated: true)
            return
        }
        let now = Date()
        if hideAfter == nil {
            hideAfter = now.addingTimeInterval(hideDelay)
        }
        if let hideAfter, now >= hideAfter {
            setCollapsed(true, animated: true)
        }
    }

    func revealIfCollapsed() -> Bool {
        guard autoHide, isCollapsed else { return false }
        setCollapsed(false, animated: true)
        return true
    }

    func refreshStageLabels() {
        for view in stack.arrangedSubviews {
            (view as? StageCardView)?.needsDisplay = true
        }
        reorderPreview?.subviews.forEach { $0.needsDisplay = true }
    }

    private func setCollapsed(_ collapsed: Bool, animated: Bool) {
        guard autoHide else { return }
        guard isCollapsed != collapsed else { return }
        isCollapsed = collapsed
        hideAfter = nil
        applyAutoHideFrame(animated: animated)
        if !collapsed, let displayID { onRevealed?(displayID) }
    }

    private func applyAutoHideFrame(animated: Bool) {
        let target = autoHide && isCollapsed ? collapsedFrame : expandedFrame
        if !isCollapsed {
            stack.isHidden = false
        }
        persistVisibleWidth()
        guard animated, animationDuration > 0 else {
            setFrame(target, display: true)
            stack.isHidden = autoHide && isCollapsed
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = animationDuration
            animator().setFrame(target, display: true)
        } completionHandler: { [weak self] in
            Task { @MainActor in
                self?.finishAutoHideFrame()
            }
        }
    }

    private func finishAutoHideFrame() {
        stack.isHidden = autoHide && isCollapsed
    }

    private func persistVisibleWidth() {
        guard let displayID else { return }
        let visibleWidth = autoHide && isCollapsed ? edgeHitWidth : expandedFrame.width
        guard lastPersistedVisibleWidth != Double(visibleWidth) else { return }
        lastPersistedVisibleWidth = Double(visibleWidth)
        runtimeStore?.setVisibleWidth(Double(visibleWidth), for: displayID)
        onVisibleWidthChanged?(displayID)
    }

    // Zone de revelation : bord replie elargi par l'aimantation, sans deborder sur l'ecran voisin (SPEC-016 FR-030).
    private var revealFrame: CGRect {
        collapsedFrame.insetBy(dx: -edgeMagnetismWidth, dy: 0).intersection(screenFrame)
    }

    func render(
        content: RailDisplayContent,
        displayName: String,
        config: RailVisualConfig,
        thumbnails: RailThumbnailStore,
        recordingStatus: TargetRecordingStatus?,
        recordingIndicatorBottomOffset: CGFloat
    ) {
        hideStageReorderPreview()
        hideWindowDropPreview()
        let scope = content.scope
        reorderMagnetism = config.reorderMagnetism
        recordingIndicatorView?.removeFromSuperview()
        recordingIndicatorView = nil
        stack.arrangedSubviews.forEach { view in
            stack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        if config.headerVisible, config.headerPosition == .top {
            stack.addArrangedSubview(RailHeaderView(displayName: displayName, desktopID: scope.desktopID, config: config))
        }
        visibleStageIDs = content.stages.map(\.id)
        orderedStageIDs = scope.stages.map(\.id)
        emptyStageIDs = content.emptyStageIDs
        stack.railBackgroundColor = config.backgroundColor
        stack.railBackgroundOpacity = config.backgroundOpacity
        emptyClickHideActive = config.emptyClickHideActive
        emptyClickSafetyMargin = config.emptyClickSafetyMargin
        positionContent(config: config)
        if let spacer = stageLeadingSpacer(stages: content.stages, config: config) {
            stack.addArrangedSubview(spacer)
        }
        for (index, stage) in content.stages.enumerated() {
            let card = StageCardView(
                stage: stage,
                displayLabel: Self.stageDisplayLabel(stage, position: index + 1),
                isActive: stage.id == scope.activeStageID,
                accent: config.accent(for: stage.id),
                config: config,
                presentationStates: content.presentationStates,
                thumbnails: thumbnails.images(for: stage.members),
                position: index + 1
            )
            card.toolTip = StagePresentationOrder.menuLabel(stage, position: index + 1)
            stack.addArrangedSubview(card)
        }
        if config.headerVisible, config.headerPosition == .bottom {
            stack.addArrangedSubview(RailHeaderView(displayName: displayName, desktopID: scope.desktopID, config: config))
        }
        if let recordingStatus {
            showRecordingIndicator(recordingStatus, bottomOffset: recordingIndicatorBottomOffset, textConfig: config.stageLabel)
        }
        layoutStageDocument()
    }

    private func layoutStageDocument() {
        let clip = stageScrollView.contentView
        let oldTop = max(0, stack.frame.height - clip.bounds.maxY)
        stack.setFrameSize(CGSize(width: frame.width, height: max(clip.bounds.height, stack.fittingSize.height)))
        stack.layoutSubtreeIfNeeded()
        clip.scroll(to: CGPoint(x: 0, y: max(0, stack.frame.height - clip.bounds.height - oldTop)))
        stageScrollView.reflectScrolledClipView(clip)
    }

    /// Nouvelles vignettes sans changement de structure (SPEC-048 C-03) : les cartes existantes
    /// reçoivent leurs images, sans recréation de vues. O(c × m), c cartes, m membres.
    func refreshThumbnails(_ thumbnails: RailThumbnailStore) {
        for case let card as StageCardView in stack.arrangedSubviews {
            card.updateThumbnails(thumbnails.images(for: card.members))
        }
    }

    private func showRecordingIndicator(_ status: TargetRecordingStatus, bottomOffset: CGFloat, textConfig: RailStageLabelConfig) {
        let indicator = RecordingIndicatorView(status: status, textConfig: textConfig)
        recordingIndicatorView = indicator
        stack.addSubview(indicator)
        NSLayoutConstraint.activate([
            indicator.leadingAnchor.constraint(equalTo: stack.leadingAnchor, constant: horizontalInset),
            indicator.bottomAnchor.constraint(equalTo: stack.bottomAnchor, constant: -bottomOffset),
        ])
    }

    private func positionContent(config: RailVisualConfig) {
        stack.spacing = config.layoutSpacing
        let topInset: CGFloat
        let bottomInset: CGFloat
        if config.headerVisible, config.headerPosition == .top {
            topInset = config.layoutTopPadding
            bottomInset = max(20, config.layoutBottomPadding)
        } else if config.headerVisible, config.headerPosition == .bottom {
            topInset = max(20, config.layoutTopPadding)
            bottomInset = config.layoutBottomPadding
        } else {
            topInset = max(20, config.layoutTopPadding)
            bottomInset = max(20, config.layoutBottomPadding)
        }
        let rightInset: CGFloat = config.mode == .icons ? horizontalInset : 18
        stack.edgeInsets = NSEdgeInsets(top: topInset, left: horizontalInset, bottom: bottomInset, right: rightInset)
    }

    private func stageLeadingSpacer(stages: [PersistentStage], config: RailVisualConfig) -> NSView? {
        let count = stages.count
        guard count > 0 else { return nil }
        let stageHeight = stages.reduce(CGFloat.zero) { $0 + StageCardView.height(for: config, memberCount: $1.members.count) }
            + CGFloat(max(0, count - 1)) * config.layoutSpacing
        let centeredTop = max(20, floor((frame.height - stageHeight) / 2))
        let currentTop: CGFloat
        switch config.headerPosition {
        case .top where config.headerVisible:
            currentTop = config.layoutTopPadding + config.headerHeight + config.layoutSpacing * 2
        case .bottom, .hidden:
            currentTop = config.layoutTopPadding + config.layoutSpacing
        case .top:
            currentTop = config.layoutTopPadding + config.layoutSpacing
        }

        let targetTop: CGFloat
        switch config.stagesPosition {
        case .top:
            targetTop = currentTop
        case .center:
            targetTop = centeredTop
        case .bottom:
            targetTop = max(currentTop, frame.height - stageHeight - config.layoutBottomPadding)
        }
        let height = max(0, targetTop - currentTop)
        guard height > 0 else { return nil }
        return FixedHeightSpacer(height: height)
    }

    func action(at screenPoint: CGPoint) -> RailAction? {
        guard let (card, local) = stageCard(at: screenPoint) else { return nil }
        return card.action(at: local)
    }

    func stageID(at screenPoint: CGPoint) -> StageID? {
        stageCard(at: screenPoint)?.0.stageID
    }

    func stageReorderPosition(at screenPoint: CGPoint, sourceStageID: StageID) -> Int? {
        guard acceptsRailInteraction(at: screenPoint) else { return nil }
        if reorderGeometry?.sourceStageID != sourceStageID {
            hideStageReorderPreview()
            guard orderedStageIDs.contains(sourceStageID) else { return nil }
            let cards = stack.arrangedSubviews.compactMap { $0 as? StageCardView }
            guard cards.contains(where: { $0.stageID == sourceStageID }) else { return nil }
            let targets = cards.filter { $0.stageID != sourceStageID }.map { card in
                let preview = card.previewDisplayFrames().first ?? card.bounds
                return (stageID: card.stageID, midY: stack.convert(preview, from: card).midY)
            }
            reorderGeometry = ReorderGeometry(targets: targets, orderedStageIDs: orderedStageIDs,
                                              sourceStageID: sourceStageID, magnetism: reorderMagnetism)
        }
        let point = stack.convert(convertPoint(fromScreen: screenPoint), from: nil)
        return reorderGeometry?.position(at: point.y, previous: reorderPreview?.position)
    }

    func showStageReorderPreview(at screenPoint: CGPoint, sourceStageID: StageID) {
        guard let position = stageReorderPosition(at: screenPoint, sourceStageID: sourceStageID) else {
            hideStageReorderPreview()
            return
        }
        if reorderPreview?.position == position { return }
        let overlay: RailStageReorderPreviewView
        if let existing = reorderPreview {
            overlay = existing
            overlay.position = position
        } else {
            let cards = stack.arrangedSubviews.compactMap { $0 as? StageCardView }
            overlay = RailStageReorderPreviewView(frame: stack.bounds, sourceStageID: sourceStageID, position: position)
            reorderOriginals = cards.map { ($0, $0.layer?.opacity ?? 1) }
            for (index, original) in cards.enumerated() {
                let copy = original.reorderPreview(position: index + 1)
                copy.translatesAutoresizingMaskIntoConstraints = true
                copy.frame = original.frame
                copy.alphaValue = original.stageID == sourceStageID ? 0.5 : 1
                reorderCopies[original.stageID] = copy
                overlay.addSubview(copy)
                // Conserve géométrie et hit-tests des originaux.
                original.layer?.opacity = 0
            }
            stack.addSubview(overlay)
            reorderPreview = overlay
        }
        guard let first = reorderOriginals.first?.card else { return }
        var futureOrder = orderedStageIDs.filter { $0 != sourceStageID }
        futureOrder.insert(sourceStageID, at: min(max(0, position - 1), futureOrder.count))
        let presented = futureOrder.compactMap { reorderCopies[$0] }
        var top = first.frame.maxY
        for (index, copy) in presented.enumerated() {
            copy.setReorderPreviewPosition(index + 1)
            copy.setFrameOrigin(CGPoint(x: copy.frame.minX, y: top - copy.frame.height))
            top = copy.frame.minY - stack.spacing
            // L'ordre des sous-vues suit aussi l'ordre projeté, sans recréer les cartes.
            overlay.addSubview(copy, positioned: .above, relativeTo: nil)
        }
    }

    func hideStageReorderPreview() {
        reorderPreview?.removeFromSuperview()
        reorderPreview = nil
        reorderGeometry = nil
        reorderCopies.removeAll()
        reorderOriginals.forEach { $0.card.layer?.opacity = $0.opacity }
        reorderOriginals.removeAll()
    }

    /// Géométrie fixe du geste : rangs et tolérance préparés une fois, O(n + c).
    /// Chaque mouvement compare les c seuils en mémoire, sans recréer de tableaux.
    private struct ReorderGeometry {
        let sourceStageID: StageID
        let thresholds: [CGFloat]
        let positions: [Int?]
        let indexByPosition: [Int: Int]
        let tolerance: CGFloat

        init(targets: [(stageID: StageID, midY: CGFloat)], orderedStageIDs: [StageID],
             sourceStageID: StageID, magnetism: CGFloat) {
            self.sourceStageID = sourceStageID
            thresholds = targets.map(\.midY)
            let remaining = orderedStageIDs.filter { $0 != sourceStageID }
            let ranks = Dictionary(uniqueKeysWithValues: remaining.enumerated().map { ($0.element, $0.offset + 1) })
            positions = targets.map { ranks[$0.stageID] } + [targets.last.flatMap { ranks[$0.stageID].map { $0 + 1 } }]
            indexByPosition = Dictionary(positions.enumerated().compactMap { index, position in
                position.map { ($0, index) }
            }, uniquingKeysWith: { first, _ in first })
            let gaps = zip(thresholds, thresholds.dropFirst()).map { abs($0 - $1) }.filter { $0 > 0 }
            tolerance = min(48, (gaps.min() ?? 96) / 3) * min(100, max(0, magnetism)) / 100
        }

        func position(at y: CGFloat, previous: Int?) -> Int? {
            guard !thresholds.isEmpty else { return nil }
            let proposedIndex = thresholds.firstIndex { y >= $0 } ?? thresholds.count
            guard let proposed = positions[proposedIndex] else { return nil }
            guard tolerance > 0, let previous, let previousIndex = indexByPosition[previous],
                  previousIndex != proposedIndex else { return proposed }
            if proposedIndex > previousIndex {
                if y > thresholds[previousIndex] - tolerance { return previous }
            } else if y < thresholds[previousIndex - 1] + tolerance { return previous }
            return proposed
        }
    }

    /// Rang persistant, stages vides comprises. API pure également utilisée par les tests.
    static func persistentReorderPosition(
        pointY: CGFloat, targets: [(stageID: StageID, midY: CGFloat)], orderedStageIDs: [StageID],
        sourceStageID: StageID, previousPosition: Int? = nil, magnetism: CGFloat = 0
    ) -> Int? {
        ReorderGeometry(targets: targets, orderedStageIDs: orderedStageIDs, sourceStageID: sourceStageID,
                        magnetism: magnetism).position(at: pointY, previous: previousPosition)
    }

    /// Carte visée, sinon insertion d'une stage à cet interstice. O(s), sans acquisition.
    /// Le depot sur le vide ne depend pas de `empty_click_hide_active`, qui regle seulement le clic (SPEC-016 FR-030).
    func windowDropTarget(at screenPoint: CGPoint) -> RailWindowDropTarget? {
        if let (card, localPoint) = stageCard(at: screenPoint) {
            return RailWindowDropTarget(
                stageID: card.stageID,
                insertionIndex: card.windowInsertionIndex(at: localPoint)
            )
        }
        guard isSafeEmptyClick(at: screenPoint) else { return nil }
        let stageID = emptyStageIDs.first ?? nextGeneratedStageID()
        let point = stack.convert(convertPoint(fromScreen: screenPoint), from: nil)
        let next = stack.arrangedSubviews.compactMap { $0 as? StageCardView }.first { point.y > $0.frame.midY }
        let insertion = next.map { StageInsertion.before($0.stageID) } ?? .end
        return RailWindowDropTarget(stageID: stageID, insertionIndex: 0, stageInsertion: insertion)
    }

    /// Indique la même destination que le dépôt, sans déplacer les cartes ni intercepter la souris. O(s).
    @discardableResult
    func showWindowDropPreview(at screenPoint: CGPoint) -> RailWindowDropTarget? {
        guard let target = windowDropTarget(at: screenPoint) else {
            hideWindowDropPreview()
            return nil
        }
        let rect: CGRect
        if target.stageInsertion == nil, let (card, _) = stageCard(at: screenPoint) {
            rect = stack.convert(card.bounds, from: card).insetBy(dx: 2, dy: 2)
        } else {
            let cards = stack.arrangedSubviews.compactMap { $0 as? StageCardView }
            let point = stack.convert(convertPoint(fromScreen: screenPoint), from: nil)
            let next = cards.first { point.y > $0.frame.midY }
            let center = next.map { $0.frame.maxY + stack.spacing / 2 }
                ?? cards.last.map { $0.frame.minY - stack.spacing / 2 } ?? point.y
            let visible = stack.visibleRect
            let y = min(max(center - 12, visible.minY), max(visible.minY, visible.maxY - 24))
            rect = CGRect(x: horizontalInset, y: y, width: max(1, stack.bounds.width - 24), height: 24)
        }
        let preview = windowDropPreview ?? RailWindowDropPreviewView(frame: rect)
        preview.frame = rect
        preview.isNewStage = target.stageInsertion != nil
        preview.needsDisplay = true
        if preview.superview == nil { stack.addSubview(preview) }
        windowDropPreview = preview
        return target
    }

    func hideWindowDropPreview() {
        windowDropPreview?.removeFromSuperview()
        windowDropPreview = nil
    }

    func emptyStageID(at screenPoint: CGPoint) -> StageID? {
        guard emptyClickHideActive, isSafeEmptyClick(at: screenPoint) else { return nil }
        return emptyStageIDs.first ?? nextGeneratedStageID()
    }

    private func isSafeEmptyClick(at screenPoint: CGPoint) -> Bool {
        guard acceptsRailInteraction(at: screenPoint) else { return false }
        let windowPoint = convertPoint(fromScreen: screenPoint)
        let localX = windowPoint.x
        return localX >= emptyClickSafetyMargin
            && localX <= frame.width - emptyClickSafetyMargin
    }

    func dragPayload(at screenPoint: CGPoint) -> RailDragPayload? {
        guard let (card, local) = stageCard(at: screenPoint) else { return nil }
        return card.dragPayload(at: local)
    }

    private func stageCard(at screenPoint: CGPoint) -> (StageCardView, CGPoint)? {
        guard let contentView, acceptsRailInteraction(at: screenPoint) else { return nil }
        let windowPoint = convertPoint(fromScreen: screenPoint)
        let contentPoint = contentView.convert(windowPoint, from: nil)
        var view = contentView.hitTest(contentPoint)
        while let current = view {
            if let card = current as? StageCardView {
                return (card, card.convert(contentPoint, from: contentView))
            }
            view = current.superview
        }
        return nil
    }

    func stageDragPayload(at screenPoint: CGPoint) -> RailStageDragPayload? {
        guard let (card, local) = stageCard(at: screenPoint) else { return nil }
        return RailStageDragPayload(
            stageID: card.stageID,
            windowID: card.windowID(at: local)
        )
    }

    func hasDirectRailInteraction(at screenPoint: CGPoint) -> Bool {
        stageID(at: screenPoint) != nil
    }

    func shouldCaptureMouse(at screenPoint: CGPoint, allowEmptyRail: Bool) -> Bool {
        guard acceptsRailInteraction(at: screenPoint) else { return false }
        if hasDirectRailInteraction(at: screenPoint) {
            return true
        }
        return allowEmptyRail && emptyStageID(at: screenPoint) != nil
    }

    func updateMousePassthrough(at screenPoint: CGPoint, allowEmptyRail: Bool) {
        let shouldCapture = shouldCaptureMouse(at: screenPoint, allowEmptyRail: allowEmptyRail)
        let shouldIgnore = !shouldCapture
        if ignoresMouseEvents != shouldIgnore {
            ignoresMouseEvents = shouldIgnore
        }
    }

    func isInSafetyMargin(at screenPoint: CGPoint) -> Bool {
        guard acceptsRailInteraction(at: screenPoint) else { return false }
        return !isSafeEmptyClick(at: screenPoint)
    }

    private func acceptsRailInteraction(at screenPoint: CGPoint) -> Bool {
        frame.contains(screenPoint) && interactionFrame.contains(screenPoint)
    }

    private func nextGeneratedStageID() -> StageID {
        Self.nextGeneratedStageID(in: orderedStageIDs)
    }

    /// Un membre hors du relevé garde son ID réservé jusqu'à sa suppression réelle du scope.
    static func nextGeneratedStageID(in orderedStageIDs: [StageID]) -> StageID {
        let used = Set(orderedStageIDs.map(\.rawValue))
        for index in 1...99 where !used.contains(String(index)) {
            return StageID(rawValue: String(index))
        }
        return StageID(rawValue: UUID().uuidString)
    }

    private static func stageDisplayLabel(_ stage: PersistentStage, position: Int) -> String {
        StagePresentationOrder.name(stage, position: position)
    }
}

@MainActor
final class RailWindowDropPreviewView: NSView {
    var isNewStage = false
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 7, yRadius: 7)
        (isNewStage ? NSColor.windowBackgroundColor.withAlphaComponent(0.92) : NSColor.labelColor.withAlphaComponent(0.10)).setFill()
        path.fill()
        NSColor.labelColor.withAlphaComponent(0.45).setStroke()
        path.lineWidth = 0.75
        path.stroke()
        if isNewStage {
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 12, weight: .medium), .foregroundColor: NSColor.labelColor
            ]
            let title = "Nouvelle stage"
            let size = title.size(withAttributes: attributes)
            title.draw(at: CGPoint(x: max(4, (bounds.width - size.width) / 2), y: (bounds.height - size.height) / 2),
                       withAttributes: attributes)
        }
    }
}

@MainActor
final class RailStageReorderPreviewView: NSView {
    let sourceStageID: StageID
    var position: Int

    init(frame: CGRect, sourceStageID: StageID, position: Int) {
        self.sourceStageID = sourceStageID
        self.position = position
        super.init(frame: frame)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

@MainActor
final class RailStackView: NSStackView {
    var railBackgroundColor: NSColor = .clear {
        didSet { needsDisplay = true }
    }
    var railBackgroundOpacity: CGFloat = 0 {
        didSet { needsDisplay = true }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        if railBackgroundOpacity > 0 {
            railBackgroundColor.withAlphaComponent(railBackgroundOpacity).setFill()
            bounds.fill()
        }
    }
}

@MainActor
final class FixedHeightSpacer: NSView {
    init(height: CGFloat) {
        super.init(frame: CGRect(x: 0, y: 0, width: 1, height: height))
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: height).isActive = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

@MainActor
final class RecordingIndicatorView: NSView {
    private let status: TargetRecordingStatus
    private let textConfig: RailStageLabelConfig
    private let indicatorSize: NSSize

    init(status: TargetRecordingStatus, textConfig: RailStageLabelConfig = .default) {
        self.status = status
        self.textConfig = textConfig
        let labelWidth = ("record" as NSString).size(withAttributes: [.font: textConfig.font]).width
        indicatorSize = NSSize(width: max(118, ceil(labelWidth) + 40), height: max(26, textConfig.lineHeight + 12))
        super.init(frame: CGRect(origin: .zero, size: indicatorSize))
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: indicatorSize.width).isActive = true
        heightAnchor.constraint(equalToConstant: indicatorSize.height).isActive = true
        toolTip = "Recording \(status.name)"
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: NSSize {
        indicatorSize
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let rect = bounds.insetBy(dx: 2, dy: 3)
        NSColor(calibratedWhite: 0.02, alpha: 0.42).setFill()
        NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8).fill()

        let dotRect = CGRect(x: rect.minX + 8, y: rect.midY - 4, width: 8, height: 8)
        NSColor.systemRed.setFill()
        NSBezierPath(ovalIn: dotRect).fill()

        let label = "record"
        label.draw(in: CGRect(x: dotRect.maxX + 8, y: rect.minY + 4, width: rect.width - 28, height: rect.height - 6), withAttributes: [
            .font: textConfig.font,
            .foregroundColor: NSColor.systemRed.withAlphaComponent(0.92),
        ])
    }
}
