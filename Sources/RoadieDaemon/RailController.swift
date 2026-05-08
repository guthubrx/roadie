import AppKit
import Foundation
import RoadieCore

@MainActor
public final class RailController {
    private let store: StageStore
    private let snapshotService: SnapshotService
    private let commandService: StageCommandService
    private let events = EventLog()
    private let thumbnails = WindowThumbnailStore()
    private var panels: [DisplayID: RailPanel] = [:]
    private var screenFrames: [DisplayID: CGRect] = [:]
    private var refreshTimer: Timer?
    private var clickMonitors: [Any] = []
    private var pendingDrag: PendingRailDrag?
    private var dragGhost: RailDragGhostWindow?
    private let dropPreview = DropPreviewController()
    private lazy var windowDragController = WindowDragReorderController(preview: dropPreview)
    private var focusedWindowID: WindowID?
    private var protectedBlurredWindows: [WindowID: Date] = [:]

    public init(
        store: StageStore = StageStore(),
        snapshotService: SnapshotService = SnapshotService(),
        commandService: StageCommandService = StageCommandService()
    ) {
        self.store = store
        self.snapshotService = snapshotService
        self.commandService = commandService
    }

    public func start() {
        NSApplication.shared.setActivationPolicy(.accessory)
        rebuildPanels()
        startClickMonitors()
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.rebuildPanels() }
        }
        RunLoop.main.add(refreshTimer!, forMode: .common)
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.rebuildPanels() }
        }
    }

    private func startClickMonitors() {
        guard clickMonitors.isEmpty else { return }
        if let local = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp], handler: { [weak self] event in
            self?.handleMouse(event.type, at: NSEvent.mouseLocation)
            return event
        }) {
            clickMonitors.append(local)
        }
        if let global = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp], handler: { [weak self] event in
            DispatchQueue.main.async {
                self?.handleMouse(event.type, at: NSEvent.mouseLocation)
            }
        }) {
            clickMonitors.append(global)
        }
    }

    private func handleMouse(_ type: NSEvent.EventType, at screenPoint: CGPoint) {
        switch type {
        case .leftMouseDown:
            handleMouseDown(at: screenPoint)
        case .leftMouseDragged:
            handleMouseDragged(to: screenPoint)
        case .leftMouseUp:
            handleMouseUp(at: screenPoint)
        default:
            break
        }
    }

    private func handleMouseDown(at screenPoint: CGPoint) {
        dragGhost?.hide()
        dropPreview.hide()
        for (displayID, panel) in panels {
            guard panel.frame.contains(screenPoint) else { continue }
            if let payload = panel.dragPayload(at: screenPoint) {
                pendingDrag = PendingRailDrag(
                    displayID: displayID,
                    windowID: payload.windowID,
                    sourceStageID: payload.sourceStageID,
                    grabUnit: payload.grabUnit,
                    startPoint: screenPoint,
                    didDrag: false
                )
                return
            }
            if let action = panel.action(at: screenPoint) {
                perform(action, displayID: displayID)
            } else if let stageID = panel.emptyStageID() {
                print("rail empty switch stage \(stageID.rawValue)")
                fflush(stdout)
                perform(.switchStage(stageID), displayID: displayID)
            } else {
                return
            }
            rebuildPanels()
            return
        }
        windowDragController.handleMouseDown(at: screenPoint)
    }

    private func handleMouseDragged(to screenPoint: CGPoint) {
        guard var drag = pendingDrag else {
            windowDragController.handleMouseDragged(to: screenPoint)
            return
        }
        if hypot(screenPoint.x - drag.startPoint.x, screenPoint.y - drag.startPoint.y) > 6 {
            if !drag.didDrag {
                if dragGhost == nil {
                    dragGhost = RailDragGhostWindow()
                }
                dragGhost?.show(image: thumbnails.cachedImage(for: drag.windowID), at: screenPoint, grabUnit: drag.grabUnit)
            } else {
                dragGhost?.move(to: screenPoint, grabUnit: drag.grabUnit)
            }
            if displayID(at: screenPoint) != nil,
               panels.values.allSatisfy({ !$0.frame.contains(screenPoint) }) {
                _ = dropPreview.update(sourceWindowID: drag.windowID, at: screenPoint)
            } else {
                dropPreview.hide()
            }
            drag.didDrag = true
            pendingDrag = drag
        }
    }

    private func handleMouseUp(at screenPoint: CGPoint) {
        guard let drag = pendingDrag else {
            windowDragController.handleMouseUp(at: screenPoint)
            return
        }
        pendingDrag = nil
        dragGhost?.hide()
        defer { dropPreview.hide() }

        guard drag.didDrag else {
            perform(.switchStage(drag.sourceStageID), displayID: drag.displayID)
            rebuildPanels()
            return
        }

        let targetDisplayID = displayID(at: screenPoint) ?? drag.displayID
        guard let panel = panels[targetDisplayID] ?? panels[drag.displayID] else { return }
        guard let targetStageID = panel.dropStageID(at: screenPoint) else {
            guard displayID(at: screenPoint) != nil else { return }
            print("rail drag summon window \(drag.windowID.rawValue)")
            fflush(stdout)
            if let candidate = dropPreview.update(sourceWindowID: drag.windowID, at: screenPoint) {
                perform(.placeWindow(candidate.sourceWindowID, candidate.orderedWindowIDs, candidate.placements), displayID: candidate.displayID)
            } else {
                perform(.summonWindow(drag.windowID), displayID: targetDisplayID)
            }
            rebuildPanels()
            return
        }
        guard targetStageID != drag.sourceStageID else { return }
        print("rail drag window \(drag.windowID.rawValue) -> stage \(targetStageID.rawValue)")
        fflush(stdout)
        perform(.moveWindow(drag.windowID, targetStageID), displayID: targetDisplayID)
        rebuildPanels()
    }

    private func perform(_ action: RailAction, displayID: DisplayID) {
        switch action {
        case .switchStage(let stageID):
            print("rail switch stage \(stageID.rawValue)")
            fflush(stdout)
            events.append(RoadieEvent(type: "rail_stage_switch", details: ["displayID": displayID.rawValue, "stageID": stageID.rawValue]))
            _ = commandService.switchTo(stageID.rawValue, displayID: displayID)
        case .summonWindow(let windowID):
            print("rail summon window \(windowID.rawValue)")
            fflush(stdout)
            events.append(RoadieEvent(type: "rail_window_summon", details: ["displayID": displayID.rawValue, "windowID": String(windowID.rawValue)]))
            _ = commandService.summon(windowID: windowID, displayID: displayID)
        case .moveWindow(let windowID, let stageID):
            print("rail move window \(windowID.rawValue) -> stage \(stageID.rawValue)")
            fflush(stdout)
            events.append(RoadieEvent(
                type: "rail_window_move",
                details: ["displayID": displayID.rawValue, "windowID": String(windowID.rawValue), "stageID": stageID.rawValue]
            ))
            _ = commandService.assign(windowID: windowID, to: stageID.rawValue, displayID: displayID)
        case .placeWindow(let windowID, let orderedWindowIDs, let placements):
            print("rail place window \(windowID.rawValue)")
            fflush(stdout)
            events.append(RoadieEvent(
                type: "rail_window_place",
                details: ["displayID": displayID.rawValue, "windowID": String(windowID.rawValue)]
            ))
            _ = commandService.place(windowID: windowID, displayID: displayID, orderedWindowIDs: orderedWindowIDs, placements: placements)
        case .moveStage(let stageID, let position):
            print("rail reorder stage \(stageID.rawValue) -> \(position)")
            fflush(stdout)
            events.append(RoadieEvent(
                type: "rail_stage_reorder",
                details: ["displayID": displayID.rawValue, "stageID": stageID.rawValue, "position": String(position)]
            ))
            _ = commandService.reorder(stageID.rawValue, to: position, displayID: displayID)
        }
    }

    private func rebuildPanels() {
        let snapshot = snapshotService.snapshot()
        updateFocusSensitiveCaptureProtection(from: snapshot)
        let state = store.state()
        let config = RailVisualConfig.load()
        thumbnails.prune(keeping: Set(state.scopes.flatMap { scope in
            scope.stages.flatMap { stage in stage.members.map(\.windowID) }
        }))
        let screensByDisplayID = Dictionary(uniqueKeysWithValues: NSScreen.screens.compactMap { screen in
            Self.displayID(for: screen).map { ($0, screen) }
        })

        for (displayID, screen) in screensByDisplayID {
            screenFrames[displayID] = screen.frame
            let desktopID = state.currentDesktopID(for: displayID)
            let scope = state.scopes.first { $0.displayID == displayID && $0.desktopID == desktopID }
                ?? PersistentStageScope(displayID: displayID, desktopID: desktopID)
            let panel = panels[displayID] ?? RailPanel()
            panel.position(on: screen)
            panel.render(
                scope: scope,
                displayName: screen.localizedName,
                config: config,
                thumbnails: thumbnails,
                protectedWindowIDs: Set(protectedBlurredWindows.keys)
            )
            if panels[displayID] == nil {
                panels[displayID] = panel
                panel.makeKey()
                panel.orderFrontRegardless()
            }
        }

        for displayID in panels.keys where screensByDisplayID[displayID] == nil {
            panels[displayID]?.orderOut(nil)
            panels.removeValue(forKey: displayID)
            screenFrames.removeValue(forKey: displayID)
        }
    }

    private func updateFocusSensitiveCaptureProtection(from snapshot: DaemonSnapshot) {
        let now = Date()
        protectedBlurredWindows = protectedBlurredWindows.filter { $0.value > now }
        defer { focusedWindowID = snapshot.focusedWindowID }

        guard let previous = focusedWindowID,
              previous != snapshot.focusedWindowID,
              let entry = snapshot.windows.first(where: { $0.window.id == previous }),
              Self.isDRMSensitiveBundle(entry.window.bundleID)
        else { return }

        protectedBlurredWindows[previous] = now.addingTimeInterval(3)
    }

    private func displayID(at screenPoint: CGPoint) -> DisplayID? {
        screenFrames.first { _, frame in frame.contains(screenPoint) }?.key
    }

    private static func isDRMSensitiveBundle(_ bundleID: String) -> Bool {
        [
            "com.apple.Safari",
            "com.google.Chrome",
            "com.microsoft.edgemac",
            "com.brave.Browser",
            "com.operasoftware.Opera",
            "org.mozilla.firefox",
        ].contains(bundleID)
    }

    private static func displayID(for screen: NSScreen) -> DisplayID? {
        guard let raw = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID,
              let uuid = CGDisplayCreateUUIDFromDisplayID(raw)?.takeRetainedValue(),
              let string = CFUUIDCreateString(nil, uuid) as String?
        else { return nil }
        return DisplayID(rawValue: string)
    }
}

private enum RailAction {
    case switchStage(StageID)
    case summonWindow(WindowID)
    case moveWindow(WindowID, StageID)
    case placeWindow(WindowID, [WindowID], [WindowID: Rect])
    case moveStage(StageID, Int)
}

private struct RailDragPayload {
    var windowID: WindowID
    var sourceStageID: StageID
    var grabUnit: CGPoint
}

private struct PendingRailDrag {
    var displayID: DisplayID
    var windowID: WindowID
    var sourceStageID: StageID
    var grabUnit: CGPoint
    var startPoint: CGPoint
    var didDrag: Bool
}

@MainActor
private final class RailDragGhostWindow: NSPanel {
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

    func show(image: NSImage?, at point: CGPoint, grabUnit: CGPoint) {
        ghostView.image = image
        setContentSize(ghostView.preferredSize(for: image))
        move(to: point, grabUnit: grabUnit)
        orderFrontRegardless()
        ghostView.needsDisplay = true
    }

    func move(to point: CGPoint, grabUnit: CGPoint) {
        let contentInset: CGFloat = 5
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
private final class RailDragGhostView: NSView {
    var image: NSImage?

    func preferredSize(for image: NSImage?) -> CGSize {
        guard let image, image.size.width > 0, image.size.height > 0 else {
            return CGSize(width: 148, height: 92)
        }
        let maxSize = CGSize(width: 170, height: 110)
        let scale = min(maxSize.width / image.size.width, maxSize.height / image.size.height, 1)
        return CGSize(width: image.size.width * scale + 10, height: image.size.height * scale + 10)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let rect = bounds.insetBy(dx: 5, dy: 5)
        let path = NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8)

        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowBlurRadius = 16
        shadow.shadowOffset = .zero
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.45)
        shadow.set()
        NSColor.black.withAlphaComponent(0.30).setFill()
        path.fill()
        NSGraphicsContext.restoreGraphicsState()

        if let image {
            NSGraphicsContext.saveGraphicsState()
            path.addClip()
            image.draw(in: rect, from: aspectFitSourceRect(image.size, for: rect), operation: .sourceOver, fraction: 0.92)
            NSGraphicsContext.restoreGraphicsState()
        } else {
            NSColor.systemGreen.withAlphaComponent(0.45).setFill()
            path.fill()
        }

        NSColor.white.withAlphaComponent(0.42).setStroke()
        path.lineWidth = 1
        path.stroke()
    }

    private func aspectFitSourceRect(_ imageSize: NSSize, for rect: CGRect) -> CGRect {
        CGRect(origin: .zero, size: imageSize)
    }
}

@MainActor
private final class RailPanel: NSPanel {
    private let stack = NSStackView()
    private let width: CGFloat = 260
    private let horizontalInset: CGFloat = 6
    private var visibleStageIDs: [StageID] = []
    private var emptyStageIDs: [StageID] = []

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

    func position(on screen: NSScreen) {
        let frame = screen.frame
        setFrame(
            CGRect(x: frame.minX, y: frame.minY, width: width, height: frame.height),
            display: true
        )
    }

    func render(
        scope: PersistentStageScope,
        displayName: String,
        config: RailVisualConfig,
        thumbnails: WindowThumbnailStore,
        protectedWindowIDs: Set<WindowID>
    ) {
        stack.arrangedSubviews.forEach { view in
            stack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        stack.addArrangedSubview(RailHeaderView(displayName: displayName, desktopID: scope.desktopID))
        let ids = stageIDs(from: scope)
        visibleStageIDs = ids
        emptyStageIDs = scope.stages.filter(\.members.isEmpty).map(\.id)
        centerStages(count: ids.count, config: config)
        for (index, id) in ids.enumerated() {
            let stage = scope.stages.first { $0.id == id } ?? PersistentStage(id: id)
            let card = StageCardView(
                stage: stage,
                isActive: id == scope.activeStageID,
                accent: config.accent(for: id),
                config: config,
                thumbnails: thumbnails.images(for: stage.members, protectedWindowIDs: protectedWindowIDs),
                position: index + 1,
                stageCount: ids.count
            )
            stack.addArrangedSubview(card)
        }
    }

    private func centerStages(count: Int, config: RailVisualConfig) {
        let cardHeight = StageCardView.height(for: config)
        let headerHeight: CGFloat = 42
        let itemCount = count + 1
        let totalHeight = headerHeight
            + CGFloat(count) * cardHeight
            + CGFloat(max(0, itemCount - 1)) * stack.spacing
        let verticalInset = max(20, floor((frame.height - totalHeight) / 2))
        stack.edgeInsets = NSEdgeInsets(top: verticalInset, left: horizontalInset, bottom: verticalInset, right: 18)
    }

    func action(at screenPoint: CGPoint) -> RailAction? {
        guard let contentView else { return nil }
        let windowPoint = convertPoint(fromScreen: screenPoint)
        let contentPoint = contentView.convert(windowPoint, from: nil)
        var view = contentView.hitTest(contentPoint)
        while let current = view {
            if let card = current as? StageCardView {
                let local = card.convert(contentPoint, from: contentView)
                return card.action(at: local)
            }
            view = current.superview
        }
        return nil
    }

    func stageID(at screenPoint: CGPoint) -> StageID? {
        guard let contentView, frame.contains(screenPoint) else { return nil }
        let windowPoint = convertPoint(fromScreen: screenPoint)
        let contentPoint = contentView.convert(windowPoint, from: nil)
        var view = contentView.hitTest(contentPoint)
        while let current = view {
            if let card = current as? StageCardView {
                return card.stageID
            }
            view = current.superview
        }
        return nil
    }

    func dropStageID(at screenPoint: CGPoint) -> StageID? {
        if let id = stageID(at: screenPoint) {
            return id
        }
        guard frame.contains(screenPoint) else { return nil }
        return emptyStageID()
    }

    func emptyStageID() -> StageID? {
        emptyStageIDs.first ?? nextGeneratedStageID()
    }

    func dragPayload(at screenPoint: CGPoint) -> RailDragPayload? {
        guard let contentView, frame.contains(screenPoint) else { return nil }
        let windowPoint = convertPoint(fromScreen: screenPoint)
        let contentPoint = contentView.convert(windowPoint, from: nil)
        var view = contentView.hitTest(contentPoint)
        while let current = view {
            if let card = current as? StageCardView {
                let local = card.convert(contentPoint, from: contentView)
                return card.dragPayload(at: local)
            }
            view = current.superview
        }
        return nil
    }

    private func nextGeneratedStageID() -> StageID {
        let used = Set((visibleStageIDs + emptyStageIDs).map(\.rawValue))
        for index in 1...99 where !used.contains(String(index)) {
            return StageID(rawValue: String(index))
        }
        return StageID(rawValue: UUID().uuidString)
    }

    private func stageIDs(from scope: PersistentStageScope) -> [StageID] {
        var ids = scope.stages.map(\.id)
        ids = ids.filter { id in
            scope.stages.first { $0.id == id }?.members.isEmpty == false
        }
        return ids
    }
}

@MainActor
private final class WindowThumbnailStore {
    private var images: [WindowID: NSImage] = [:]
    private var signatures: [WindowID: String] = [:]
    private var capturedAt: [WindowID: Date] = [:]
    private let drmRefreshInterval: TimeInterval = 2
    private let refreshInterval: TimeInterval = 5

    func images(for members: [PersistentStageMember], protectedWindowIDs: Set<WindowID>) -> [WindowID: NSImage] {
        Dictionary(uniqueKeysWithValues: members.compactMap { member in
            guard let image = image(for: member, captureAllowed: !protectedWindowIDs.contains(member.windowID)) else { return nil }
            return (member.windowID, image)
        })
    }

    func prune(keeping liveIDs: Set<WindowID>) {
        images = images.filter { liveIDs.contains($0.key) }
        signatures = signatures.filter { liveIDs.contains($0.key) }
        capturedAt = capturedAt.filter { liveIDs.contains($0.key) }
    }

    func cachedImage(for windowID: WindowID) -> NSImage? {
        images[windowID]
    }

    private func image(for member: PersistentStageMember, captureAllowed: Bool) -> NSImage? {
        let now = Date()
        let isDRMSensitive = Self.isDRMSensitiveBundle(member.bundleID)
        let signature = "\(member.bundleID)\n\(member.title)"
        if signatures[member.windowID] != signature {
            images.removeValue(forKey: member.windowID)
            capturedAt.removeValue(forKey: member.windowID)
            signatures[member.windowID] = signature
        }
        if let cached = images[member.windowID], !cached.looksBlank {
            let age = now.timeIntervalSince(capturedAt[member.windowID] ?? .distantPast)
            let interval = isDRMSensitive ? drmRefreshInterval : refreshInterval
            guard age >= interval else {
                return cached
            }
        }
        if images[member.windowID]?.looksBlank == true {
            images.removeValue(forKey: member.windowID)
        }
        guard captureAllowed else {
            return images[member.windowID] ?? fallbackImage(for: member, capturedAt: now)
        }

        if let captured = capture(member.windowID) {
            images[member.windowID] = captured
            capturedAt[member.windowID] = now
            return captured
        }

        return images[member.windowID] ?? fallbackImage(for: member, capturedAt: now)
    }

    private func capture(_ windowID: WindowID) -> NSImage? {
        guard let cgImage = CGWindowListCreateImage(
            .null,
            .optionIncludingWindow,
            CGWindowID(windowID.rawValue),
            [.boundsIgnoreFraming, .nominalResolution]
        ),
              !cgImage.looksBlank
        else {
            return nil
        }
        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }

    private func appIcon(for member: PersistentStageMember) -> NSImage? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: member.bundleID) else {
            return nil
        }
        let icon = NSWorkspace.shared.icon(forFile: url.path).copy() as? NSImage ?? NSWorkspace.shared.icon(forFile: url.path)
        icon.size = NSSize(width: 128, height: 128)
        let size = NSSize(width: 160, height: 104)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor(calibratedWhite: 0.08, alpha: 0.96).setFill()
        NSBezierPath(roundedRect: CGRect(origin: .zero, size: size), xRadius: 10, yRadius: 10).fill()
        NSColor.white.withAlphaComponent(0.08).setStroke()
        let border = NSBezierPath(roundedRect: CGRect(x: 0.5, y: 0.5, width: size.width - 1, height: size.height - 1), xRadius: 10, yRadius: 10)
        border.lineWidth = 1
        border.stroke()
        icon.draw(
            in: CGRect(x: (size.width - 52) / 2, y: (size.height - 52) / 2, width: 52, height: 52),
            from: CGRect(origin: .zero, size: icon.size),
            operation: .sourceOver,
            fraction: 1
        )
        image.unlockFocus()
        return image
    }

    private func fallbackImage(for member: PersistentStageMember, capturedAt date: Date) -> NSImage? {
        let image = appIcon(for: member)
        if let image {
            images[member.windowID] = image
            capturedAt[member.windowID] = date
        }
        return image
    }

    private static func isDRMSensitiveBundle(_ bundleID: String) -> Bool {
        [
            "com.apple.Safari",
            "com.google.Chrome",
            "com.microsoft.edgemac",
            "com.brave.Browser",
            "com.operasoftware.Opera",
            "org.mozilla.firefox",
        ].contains(bundleID)
    }
}

@MainActor
private struct RailVisualConfig {
    var mode: RailRenderMode = .stacked
    var stageAccents: [StageID: NSColor] = [:]
    var previewWidth: CGFloat = 160
    var previewHeight: CGFloat = 104
    var leadingPadding: CGFloat = 8
    var trailingPadding: CGFloat = 16
    var verticalPadding: CGFloat = 20
    var stackedOffsetX: CGFloat = 60
    var stackedOffsetY: CGFloat = 80
    var stackedScale: CGFloat = 0.05
    var stackedOpacity: CGFloat = 0.08
    var parallaxRotation: CGFloat = 35
    var parallaxOffsetX: CGFloat = 25
    var parallaxOffsetY: CGFloat = 18
    var parallaxScale: CGFloat = 0.08
    var parallaxOpacity: CGFloat = 0.20
    var parallaxDarken: CGFloat = 0.15

    func accent(for stageID: StageID) -> NSColor {
        stageAccents[stageID] ?? NSColor.systemGreen
    }

    static func load() -> RailVisualConfig {
        let settings = RailSettings.load()
        let mode = RailRenderMode.load(renderer: settings.renderer)
        let accents = settings.stageAccents.reduce(into: [StageID: NSColor]()) { result, item in
            guard let color = NSColor(hex: item.value) else { return }
            result[StageID(rawValue: item.key)] = color
        }
        let preview = settings.preview
        let parallax = settings.parallax
        let useParallaxGeometry = mode == .parallax
        return RailVisualConfig(
            mode: mode,
            stageAccents: accents,
            previewWidth: CGFloat(useParallaxGeometry ? parallax.width : preview.width),
            previewHeight: CGFloat(useParallaxGeometry ? parallax.height : preview.height),
            leadingPadding: CGFloat(useParallaxGeometry ? parallax.leadingPadding : preview.leadingPadding),
            trailingPadding: CGFloat(useParallaxGeometry ? parallax.trailingPadding : preview.trailingPadding),
            verticalPadding: CGFloat(useParallaxGeometry ? parallax.verticalPadding : preview.verticalPadding),
            stackedOffsetX: CGFloat(settings.stacked.offsetX),
            stackedOffsetY: CGFloat(settings.stacked.offsetY),
            stackedScale: CGFloat(settings.stacked.scalePerLayer),
            stackedOpacity: CGFloat(settings.stacked.opacityPerLayer),
            parallaxRotation: CGFloat(parallax.rotation),
            parallaxOffsetX: CGFloat(parallax.offsetX),
            parallaxOffsetY: CGFloat(parallax.offsetY),
            parallaxScale: CGFloat(parallax.scalePerLayer),
            parallaxOpacity: CGFloat(parallax.opacityPerLayer),
            parallaxDarken: CGFloat(parallax.darkenPerLayer)
        )
    }
}

@MainActor
private enum RailRenderMode: String {
    case stacked = "stacked-previews"
    case mosaic
    case parallax = "parallax-45"
    case icons = "icons-only"

    static func load(renderer: String) -> RailRenderMode {
        switch renderer {
        case "mosaic":
            return .mosaic
        case "parallax-45", "parallax":
            return .parallax
        case "icons-only", "icons":
            return .icons
        default:
            return .stacked
        }
    }
}

@MainActor
private final class RailHeaderView: NSView {
    private let displayName: String
    private let desktopID: DesktopID

    init(displayName: String, desktopID: DesktopID) {
        self.displayName = displayName
        self.desktopID = desktopID
        super.init(frame: CGRect(x: 0, y: 0, width: 224, height: 42))
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: 224).isActive = true
        heightAnchor.constraint(equalToConstant: 42).isActive = true
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let title = displayName.isEmpty ? "Roadie" : displayName
        title.draw(in: CGRect(x: 4, y: 19, width: 216, height: 18), withAttributes: [
            .foregroundColor: NSColor.white.withAlphaComponent(0.86),
            .font: NSFont.systemFont(ofSize: 13, weight: .bold),
        ])
        "Desktop \(desktopID)".draw(in: CGRect(x: 4, y: 3, width: 216, height: 14), withAttributes: [
            .foregroundColor: NSColor.white.withAlphaComponent(0.42),
            .font: NSFont.monospacedSystemFont(ofSize: 10, weight: .medium),
        ])
    }
}

@MainActor
private final class StageCardView: NSControl {
    let stageID: StageID
    private let stage: PersistentStage
    private let isActive: Bool
    private let accent: NSColor
    private let config: RailVisualConfig
    private let thumbnails: [WindowID: NSImage]
    private let position: Int
    private let stageCount: Int
    private let contentInset: CGFloat = 4

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    init(
        stage: PersistentStage,
        isActive: Bool,
        accent: NSColor,
        config: RailVisualConfig,
        thumbnails: [WindowID: NSImage],
        position: Int,
        stageCount: Int
    ) {
        self.stage = stage
        self.stageID = stage.id
        self.isActive = isActive
        self.accent = accent
        self.config = config
        self.thumbnails = thumbnails
        self.position = position
        self.stageCount = stageCount
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

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func action(at point: CGPoint) -> RailAction? {
        if dragPayload(at: point) != nil {
            return nil
        }
        if upHitRect.contains(point), position > 1 {
            return .moveStage(stageID, position - 1)
        }
        if downHitRect.contains(point), position < stageCount {
            return .moveStage(stageID, position + 1)
        }
        return .switchStage(stageID)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        drawCard()
    }

    private func drawCard() {
        let rect = bounds.insetBy(dx: contentInset, dy: 12)
        switch config.mode {
        case .stacked:
            drawStacked(in: previewArea(in: rect, visibleCount: visiblePreviewCount))
        case .mosaic:
            drawMosaic(in: previewArea(in: rect, visibleCount: visiblePreviewCount))
        case .parallax:
            drawParallax(in: previewArea(in: rect, visibleCount: visiblePreviewCount))
        case .icons:
            drawIcons(in: rect.insetBy(dx: 8, dy: 18))
        }
        drawControls()
    }

    private var upRect: CGRect {
        let preview = previewArea(in: bounds.insetBy(dx: contentInset, dy: 12), visibleCount: visiblePreviewCount)
        return CGRect(x: preview.midX - 16, y: preview.maxY + 6, width: 32, height: 24)
    }

    private var downRect: CGRect {
        let preview = previewArea(in: bounds.insetBy(dx: contentInset, dy: 12), visibleCount: visiblePreviewCount)
        return CGRect(x: preview.midX - 16, y: preview.minY - 30, width: 32, height: 24)
    }

    private var upHitRect: CGRect {
        upRect.insetBy(dx: -12, dy: -10)
    }

    private var downHitRect: CGRect {
        downRect.insetBy(dx: -12, dy: -10)
    }

    private func drawControls() {
        drawControl("⌃", in: upRect, enabled: position > 1)
        drawControl("⌄", in: downRect, enabled: position < stageCount)
    }

    private func drawControl(_ label: String, in rect: CGRect, enabled: Bool) {
        guard enabled else { return }
        let fontSize = rect.height > 24 ? 14.0 : 12.0
        label.draw(in: rect.insetBy(dx: 0, dy: rect.height > 24 ? 6 : 3), withAttributes: [
            .foregroundColor: NSColor.white.withAlphaComponent(0.70),
            .font: NSFont.systemFont(ofSize: fontSize, weight: .semibold),
        ])
    }

    private func drawStacked(in rect: CGRect) {
        guard !stage.members.isEmpty else {
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
        guard !stage.members.isEmpty else {
            drawEmpty(in: rect)
            return
        }
        let count = min(stage.members.count, 6)
        let cols = count <= 2 ? count : 2
        let rows = Int(ceil(Double(count) / Double(cols)))
        let gap: CGFloat = 6
        let cellW = (rect.width - CGFloat(cols - 1) * gap) / CGFloat(cols)
        let cellH = (rect.height - 34 - CGFloat(rows - 1) * gap) / CGFloat(rows)
        for index in 0..<count {
            let col = index % cols
            let row = index / cols
            let r = CGRect(
                x: rect.minX + CGFloat(col) * (cellW + gap),
                y: rect.minY + CGFloat(row) * (cellH + gap),
                width: cellW,
                height: cellH
            )
            drawPreview(r, index: index)
        }
    }

    private func drawParallax(in rect: CGRect) {
        guard !stage.members.isEmpty else {
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
        guard !stage.members.isEmpty else {
            drawEmpty(in: rect)
            return
        }
        let members = Array(stage.members.prefix(6))
        for (index, member) in members.enumerated() {
            let x = rect.minX + CGFloat(index) * 32
            let r = CGRect(x: x, y: rect.midY - 12, width: 24, height: 24)
            rounded(r, radius: 7, color: color(for: member, index: index))
            iconLetter(for: member).draw(in: r.insetBy(dx: 0, dy: 4), withAttributes: [
                .foregroundColor: NSColor.white,
                .font: NSFont.boldSystemFont(ofSize: 11),
            ])
        }
        if stage.members.count > 6 {
            "+\(stage.members.count - 6)".draw(in: CGRect(x: rect.minX + 196, y: rect.midY - 8, width: 28, height: 18), withAttributes: [
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
        min(stage.members.count, 5)
    }

    private func previewArea(in rect: CGRect, visibleCount: Int) -> CGRect {
        let width = min(config.previewWidth, rect.width - config.leadingPadding - config.trailingPadding)
        let height = min(config.previewHeight, rect.height - 60)
        let leftCompensation: CGFloat
        switch config.mode {
        case .parallax:
            leftCompensation = CGFloat(max(visibleCount - 1, 0)) * config.parallaxOffsetX
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
        let count = min(stage.members.count, maxCount)
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
        if let image = stage.members[safe: index].flatMap({ thumbnails[$0.windowID] }) {
            NSGraphicsContext.saveGraphicsState()
            path.addClip()
            let opacity = opacity(for: index)
            image.draw(in: rect, from: aspectFillSourceRect(image.size, for: rect), operation: .sourceOver, fraction: opacity)
            NSGraphicsContext.restoreGraphicsState()
        } else {
            color(for: stage.members[safe: index], index: index).withAlphaComponent(opacity(for: index)).setFill()
            path.fill()
        }
        NSColor.white.withAlphaComponent(isActive ? 0.34 : 0.18).setStroke()
        path.lineWidth = 1
        path.stroke()
        if darkened {
            NSColor.black.withAlphaComponent(config.parallaxDarken * CGFloat(index)).setFill()
            NSBezierPath(roundedRect: rect.insetBy(dx: 12, dy: 10), xRadius: 4, yRadius: 4).fill()
        }
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
                      accent.withAlphaComponent(0.32).cgColor,
                      accent.withAlphaComponent(0.16).cgColor,
                      accent.withAlphaComponent(0.055).cgColor,
                      accent.withAlphaComponent(0).cgColor,
                  ] as CFArray,
                  locations: [0, 0.28, 0.58, 1]
        )
        else { return }
        let xScale: CGFloat = 1.45
        let yScale: CGFloat = 0.92
        let availableLeft = max(12, center.x - bounds.minX - 4)
        let availableRight = max(12, bounds.maxX - center.x - 4)
        let maxHorizontalRadius = min(availableLeft, availableRight) / xScale
        let desiredRadius = max(union.width, union.height) * 0.95
        let radius = max(24, min(desiredRadius, maxHorizontalRadius))
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
        let angle = min(config.parallaxRotation, 75) * .pi / 180
        let xScale = max(0.45, cos(angle))
        let perspective = sin(angle) * 0.12
        context.translateBy(x: rect.midX, y: rect.midY)
        context.concatenate(CGAffineTransform(a: xScale, b: perspective, c: 0, d: 1, tx: 0, ty: 0))
        context.translateBy(x: -rect.midX, y: -rect.midY)
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
        for item in hitPreviewItemsFrontToBack() {
            guard item.rect.contains(point),
                  let member = stage.members[safe: item.index]
            else { continue }
            return RailDragPayload(
                windowID: member.windowID,
                sourceStageID: stageID,
                grabUnit: CGPoint(
                    x: min(1, max(0, (point.x - item.rect.minX) / max(1, item.rect.width))),
                    y: min(1, max(0, (point.y - item.rect.minY) / max(1, item.rect.height)))
                )
            )
        }
        return nil
    }

    private func hitPreviewItemsFrontToBack() -> [(index: Int, rect: CGRect)] {
        // Stacked/parallax previews are drawn back-to-front, so index 0 is visually on top.
        hitPreviewItems()
    }

    private func hitPreviewItems() -> [(index: Int, rect: CGRect)] {
        let cardRect = bounds.insetBy(dx: contentInset, dy: 12)
        let rect = config.mode == .icons ? cardRect.insetBy(dx: 8, dy: 18) : previewArea(in: cardRect, visibleCount: visiblePreviewCount)
        switch config.mode {
        case .stacked, .parallax:
            return previewItems(in: rect, maxCount: 5)
        case .mosaic:
            let count = min(stage.members.count, 6)
            let cols = count <= 2 ? count : 2
            let rows = Int(ceil(Double(count) / Double(max(cols, 1))))
            let gap: CGFloat = 6
            let cellW = (rect.width - CGFloat(max(cols - 1, 0)) * gap) / CGFloat(max(cols, 1))
            let cellH = (rect.height - 34 - CGFloat(max(rows - 1, 0)) * gap) / CGFloat(max(rows, 1))
            return (0..<count).map { index in
                let col = index % cols
                let row = index / cols
                return (
                    index,
                    CGRect(
                        x: rect.minX + CGFloat(col) * (cellW + gap),
                        y: rect.minY + CGFloat(row) * (cellH + gap),
                        width: cellW,
                        height: cellH
                    )
                )
            }
        case .icons:
            return Array(stage.members.prefix(6)).enumerated().map { index, _ in
                (index, CGRect(x: rect.minX + CGFloat(index) * 32, y: rect.midY - 12, width: 24, height: 24))
            }
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

private extension CGImage {
    var looksBlank: Bool {
        guard width > 0, height > 0 else { return true }

        let sampleWidth = 32
        let sampleHeight = 32
        let bytesPerPixel = 4
        let bytesPerRow = sampleWidth * bytesPerPixel
        var pixels = [UInt8](repeating: 0, count: sampleHeight * bytesPerRow)
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                  data: &pixels,
                  width: sampleWidth,
                  height: sampleHeight,
                  bitsPerComponent: 8,
                  bytesPerRow: bytesPerRow,
                  space: colorSpace,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              )
        else { return true }

        context.interpolationQuality = .low
        context.draw(self, in: CGRect(x: 0, y: 0, width: sampleWidth, height: sampleHeight))

        var darkSamples = 0
        var brightSamples = 0
        var totalSamples = 0
        var previousLuma: Int?
        var lumaChanges = 0
        var index = 0
        while index + 3 < pixels.count {
            let r = Int(pixels[index])
            let g = Int(pixels[index + 1])
            let b = Int(pixels[index + 2])
            let alpha = Int(pixels[index + 3])
            if alpha > 8 {
                let luma = (r * 299 + g * 587 + b * 114) / 1000
                if luma < 10 { darkSamples += 1 }
                if luma > 32 { brightSamples += 1 }
                if let previousLuma, abs(previousLuma - luma) > 8 { lumaChanges += 1 }
                previousLuma = luma
            }
            totalSamples += 1
            index += bytesPerPixel
        }
        guard totalSamples > 0 else { return true }
        return Double(darkSamples) / Double(totalSamples) > 0.96
            && Double(brightSamples) / Double(totalSamples) < 0.01
            && lumaChanges < 8
    }
}

private extension NSImage {
    var looksBlank: Bool {
        guard let cgImage = cgImage(forProposedRect: nil, context: nil, hints: nil) else { return true }
        return cgImage.looksBlank
    }
}

private extension NSColor {
    convenience init?(hex: String) {
        let clean = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard clean.count == 6 || clean.count == 8,
              let value = UInt32(clean, radix: 16)
        else { return nil }
        let red: CGFloat
        let green: CGFloat
        let blue: CGFloat
        let alpha: CGFloat
        if clean.count == 8 {
            red = CGFloat((value >> 24) & 0xff) / 255
            green = CGFloat((value >> 16) & 0xff) / 255
            blue = CGFloat((value >> 8) & 0xff) / 255
            alpha = CGFloat(value & 0xff) / 255
        } else {
            red = CGFloat((value >> 16) & 0xff) / 255
            green = CGFloat((value >> 8) & 0xff) / 255
            blue = CGFloat(value & 0xff) / 255
            alpha = 1
        }
        self.init(calibratedRed: red, green: green, blue: blue, alpha: alpha)
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
