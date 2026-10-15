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
    private let stack = RailStackView()
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
    private var screenFrame = CGRect.zero
    private var expandedFrame = CGRect.zero
    private var collapsedFrame = CGRect.zero
    private var interactionFrame = CGRect.zero
    private var isCollapsed = false
    private var lastPersistedVisibleWidth: Double?
    private var hideAfter: Date?
    private var recordingIndicatorView: RecordingIndicatorView?

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
        contentView = stack
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
    }

    private func setCollapsed(_ collapsed: Bool, animated: Bool) {
        guard autoHide else { return }
        guard isCollapsed != collapsed else { return }
        isCollapsed = collapsed
        hideAfter = nil
        applyAutoHideFrame(animated: animated)
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
        let scope = content.scope
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
            stack.addArrangedSubview(card)
        }
        if config.headerVisible, config.headerPosition == .bottom {
            stack.addArrangedSubview(RailHeaderView(displayName: displayName, desktopID: scope.desktopID, config: config))
        }
        if let recordingStatus {
            showRecordingIndicator(recordingStatus, bottomOffset: recordingIndicatorBottomOffset, textConfig: config.stageLabel)
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
        stageReorderTarget(at: screenPoint, sourceStageID: sourceStageID)?.position
    }

    func showStageReorderPreview(at screenPoint: CGPoint, sourceStageID: StageID) {
        stack.insertionY = stageReorderTarget(at: screenPoint, sourceStageID: sourceStageID)?.lineY
    }

    func hideStageReorderPreview() {
        stack.insertionY = nil
    }

    /// Le repère et le dépôt utilisent le même calcul, y compris les emplacements nommés vides.
    private func stageReorderTarget(at screenPoint: CGPoint, sourceStageID: StageID) -> (position: Int, lineY: CGFloat)? {
        guard let contentView, acceptsRailInteraction(at: screenPoint) else { return nil }
        let windowPoint = convertPoint(fromScreen: screenPoint)
        let point = stack.convert(windowPoint, from: nil)
        let cards = stack.arrangedSubviews.compactMap { $0 as? StageCardView }
            .filter { $0.stageID != sourceStageID }
        guard let last = cards.last else { return nil }
        let targets = cards.map { card in
            let preview = card.previewDisplayFrames().first ?? card.bounds
            return (stageID: card.stageID, midY: stack.convert(preview, from: card).midY)
        }
        guard let position = Self.persistentReorderPosition(
            pointY: point.y, targets: targets, orderedStageIDs: orderedStageIDs, sourceStageID: sourceStageID
        ) else { return nil }
        let before = targets.firstIndex { point.y >= $0.midY }
        let lineY = before.map { cards[$0].frame.maxY + stack.spacing / 2 }
            ?? (last.frame.minY - stack.spacing / 2)
        return (position, min(max(2, lineY), contentView.bounds.height - 2))
    }

    /// Rang (base 1) attendu par `PersistentStageScope.reorderStage`, calculé dans l'ordre complet des stages
    /// après retrait de la source. Les cibles sont les cartes affichées hors source, de haut en bas ; le point
    /// se place avant la première carte dont il dépasse le milieu (y AppKit croissant vers le haut), sinon
    /// après la dernière. Les stages vides, absentes du rail, gardent leur place (REL-039).
    // Complexité : O(n + c) - n = stages du scope, c = cartes affichées.
    static func persistentReorderPosition(
        pointY: CGFloat,
        targets: [(stageID: StageID, midY: CGFloat)],
        orderedStageIDs: [StageID],
        sourceStageID: StageID
    ) -> Int? {
        guard let last = targets.last else { return nil }
        let remaining = orderedStageIDs.filter { $0 != sourceStageID }
        if let before = targets.first(where: { pointY >= $0.midY }) {
            return remaining.firstIndex(of: before.stageID).map { $0 + 1 }
        }
        return remaining.firstIndex(of: last.stageID).map { $0 + 2 }
    }

    /// Cible d'un depot de fenetre : une carte, sinon la zone vide du rail (stage vide ou prochaine stage libre).
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
        return RailWindowDropTarget(stageID: stageID, insertionIndex: 0)
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
        let width = max(1, card.bounds.width)
        let height = max(1, card.bounds.height)
        return RailStageDragPayload(
            stageID: card.stageID,
            image: card.snapshotImage(),
            grabUnit: CGPoint(
                x: min(max(local.x / width, 0), 1),
                y: min(max(local.y / height, 0), 1)
            ),
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
        let used = Set((visibleStageIDs + emptyStageIDs).map(\.rawValue))
        for index in 1...99 where !used.contains(String(index)) {
            return StageID(rawValue: String(index))
        }
        return StageID(rawValue: UUID().uuidString)
    }

    private static func isCustomStageName(_ name: String, id: StageID) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed != "Stage \(id.rawValue)"
    }

    private static func stageDisplayLabel(_ stage: PersistentStage, position: Int) -> String {
        let trimmed = stage.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return isCustomStageName(trimmed, id: stage.id) ? trimmed : "Stage \(position)"
    }
}

@MainActor
final class RailStackView: NSStackView {
    var insertionY: CGFloat? {
        didSet { needsDisplay = true }
    }
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
        if let insertionY {
            NSColor.controlAccentColor.setFill()
            CGRect(x: 6, y: insertionY - 1, width: max(1, bounds.width - 24), height: 2).fill()
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
