import AppKit
import RoadieAX
import RoadieCore

/// Copie initiale sous le pointeur : une capture par geste, aucun écrivain AX.
/// La destination et la remise en page de la vraie fenêtre restent indépendantes.
@MainActor
final class DragPointerPreview {
    typealias Capture = @MainActor (WindowSnapshot) async -> CGImage?
    private let capture: Capture
    private let presents: Bool
    private var task: Task<Void, Never>?
    private var sequence = UUID()
    private var image: CGImage?
    private var panel: DragPointerPanel?
    private var initialFrame = CGRect.zero
    private var anchor = CGPoint.zero
    private var point = CGPoint.zero
    private var config = EffectsConfig()
    private var visible = false
    private(set) var isReady = false
    private(set) var failed = false
    var onPrepared: (() -> Void)?
    var enabled: Bool { config.dragPreview != "none" }
    var visibleFrame: CGRect? { visible && isReady && enabled ? Self.frame(initial: initialFrame, anchor: anchor, point: point, scale: config.dragPreviewScalePercent / 100) : nil }

    init(presents: Bool = true, capture: @escaping Capture = { await RailThumbnailStore.shared.captureDragSource($0) }) {
        self.presents = presents; self.capture = capture
    }

    func prepare(window: WindowSnapshot, anchor: CGPoint, config: EffectsConfig) {
        end()
        self.config = config; self.anchor = anchor; point = anchor; initialFrame = window.frame.cgRect
        let sequence = self.sequence
        let began = ProcessInfo.processInfo.systemUptime
        guard config.dragPreview == "content" else { isReady = true; onPrepared?(); return }
        task = Task { [weak self, capture] in
            let result = await capture(window)
            guard let self, self.sequence == sequence, !Task.isCancelled else { return }
            image = result; isReady = result != nil; failed = result == nil
            EventLog().append(RoadieEvent(type: "drag.pointer_prepared", details: [
                "windowID": String(window.id.rawValue), "ready": String(isReady),
                "captureMs": String((ProcessInfo.processInfo.systemUptime - began) * 1000)]))
            onPrepared?()
        }
    }

    func show(at point: CGPoint) { visible = true; update(at: point) }
    func update(at point: CGPoint) {
        self.point = point
        guard presents, visible, isReady, enabled, let frame = visibleFrame else { return }
        if panel == nil { panel = DragPointerPanel() }
        panel?.show(image: image, frame: frame, opacity: config.dragPreviewOpacityPercent / 100)
    }
    func end() {
        sequence = UUID(); task?.cancel(); task = nil
        panel?.releaseImage(); panel?.orderOut(nil); panel = nil
        image = nil; visible = false; isReady = false; failed = false
    }

    nonisolated static func frame(initial: CGRect, anchor: CGPoint, point: CGPoint, scale: Double) -> CGRect {
        let scale = min(1, max(0.25, scale))
        return CGRect(x: point.x - (anchor.x - initial.minX) * scale,
                      y: point.y - (anchor.y - initial.minY) * scale,
                      width: initial.width * scale, height: initial.height * scale)
    }
}

@MainActor
private final class DragPointerPanel: NSPanel {
    private let imageLayer = CALayer()
    private let outlineLayer = CAShapeLayer()
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isReleasedWhenClosed = false; isOpaque = false; backgroundColor = .clear
        level = .floating; isFloatingPanel = true; hidesOnDeactivate = false
        ignoresMouseEvents = true; hasShadow = true
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        let view = NSView(); view.wantsLayer = true; view.layer = CALayer()
        contentView = view
        imageLayer.contentsGravity = .resizeAspect
        view.layer?.addSublayer(imageLayer); view.layer?.addSublayer(outlineLayer)
    }
    func show(image: CGImage?, frame: CGRect, opacity: Double) {
        CATransaction.begin(); CATransaction.setDisableActions(true)
        let bounds = CGRect(origin: .zero, size: frame.size)
        imageLayer.frame = bounds; imageLayer.contents = image
        outlineLayer.isHidden = image != nil; outlineLayer.path = CGPath(roundedRect: bounds.insetBy(dx: 2, dy: 2), cornerWidth: 8, cornerHeight: 8, transform: nil)
        outlineLayer.fillColor = NSColor.systemGreen.withAlphaComponent(0.15).cgColor
        outlineLayer.strokeColor = NSColor.systemGreen.cgColor; outlineLayer.lineWidth = 3
        CATransaction.commit()
        alphaValue = min(1, max(0.1, opacity))
        setFrame(RoadieScreenCoordinate.axRectToNS(frame), display: false)
        contentView?.frame = bounds
        orderFrontRegardless()
    }
    func releaseImage() { imageLayer.contents = nil }
}

/// Preuve d'un déplacement natif, pas d'une sélection/onglet déplacé dans le contenu.
enum NativeWindowDragEvidence {
    static func followsPointer(initial: CGRect, observed: CGRect, from: CGPoint, to: CGPoint, constrainedTo bounds: CGRect? = nil, minimumDistance: Double = 8) -> Bool {
        let dx = to.x - from.x, dy = to.y - from.y
        let movedX = observed.minX - initial.minX, movedY = observed.minY - initial.minY
        guard [dx, dy, movedX, movedY, observed.width, observed.height].allSatisfy(\.isFinite),
              hypot(dx, dy) > minimumDistance, hypot(movedX, movedY) > minimumDistance,
              abs(initial.width - observed.width) <= 1, abs(initial.height - observed.height) <= 1 else { return false }
        if abs(dx - movedX) <= 8 && abs(dy - movedY) <= 8 { return true }
        guard let bounds else { return false }
        // Une grande fenêtre peut atteindre le bord alors que le pointeur continue.
        func bounded(_ actual: Double, _ requested: Double) -> Bool {
            actual * requested >= 0 && abs(actual) <= abs(requested) + 8
        }
        let atVerticalEdge = abs(observed.minY - bounds.minY) <= 2 || abs(observed.maxY - bounds.maxY) <= 2
        let atHorizontalEdge = abs(observed.minX - bounds.minX) <= 2 || abs(observed.maxX - bounds.maxX) <= 2
        return (abs(dx) > minimumDistance && abs(movedX) > minimumDistance && abs(dx - movedX) <= 8
                    && atVerticalEdge && bounded(movedY, dy))
            || (abs(dy) > minimumDistance && abs(movedY) > minimumDistance && abs(dy - movedY) <= 8
                    && atHorizontalEdge && bounded(movedX, dx))
    }
}
