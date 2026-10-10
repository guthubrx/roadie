import AppKit
import RoadieAX
import RoadieCore

@MainActor
public final class BorderController {
    private let snapshotService: SnapshotService
    private let configLoader: () -> RoadieConfig
    private let panel = BorderPanel()
    private var refreshTimer: Timer?

    public init(
        snapshotService: SnapshotService = SnapshotService(),
        configLoader: @escaping () -> RoadieConfig = { ConfigReloadService.shared.currentConfig() }
    ) {
        self.snapshotService = snapshotService
        self.configLoader = configLoader
    }

    public func start() {
        NSApplication.shared.setActivationPolicy(.accessory)
        UserInputActivity.shared.startMonitoring()
        refresh()
        refreshTimer?.invalidate()
        let newTimer = Timer.scheduledTimer(withTimeInterval: 0.12, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        refreshTimer = newTimer
        RunLoop.main.add(newTimer, forMode: .common)
    }

    private func refresh() {
        let config = configLoader().fx.borders
        guard config.enabled else {
            hidePanel()
            return
        }

        let snapshot = snapshotService.sharedSnapshot()
        guard let focusedWindowID = snapshot.focusedWindowID,
              let entry = snapshot.windows.first(where: { $0.window.id == focusedWindowID }),
              entry.window.isTileCandidate,
              entry.scope != nil,
              !HiddenWindowPlacement.isHiddenOrLegacyOffscreen(entry.window.frame.cgRect, in: snapshot.displays),
              !Self.isWindowVisiblyOccluded(entry, in: snapshot)
        else {
            hidePanel()
            return
        }

        let color = entry.pin == nil ? activeColor(for: entry.scope?.stageID, config: config) : .systemRed
        panel.render(
            frame: Self.axToNS(entry.window.frame.cgRect),
            color: color,
            thickness: CGFloat(max(1, config.thickness)),
            cornerRadius: CGFloat(max(0, config.cornerRadius))
        )
    }

    private func hidePanel() {
        if panel.isVisible { panel.orderOut(nil) }
    }

    private func activeColor(for stageID: StageID?, config: BorderConfig) -> NSColor {
        let rawColor: String
        if let stageID,
           let override = config.stageOverrides.first(where: { $0.stageID == stageID.rawValue }) {
            rawColor = override.activeColor ?? config.activeColor
        } else {
            rawColor = config.activeColor
        }
        return NSColor(hex: rawColor) ?? NSColor.systemBlue
    }

    public func groupIndicator(for windowID: WindowID, snapshot: DaemonSnapshot) -> String? {
        for display in snapshot.state.displays.values {
            for desktop in display.desktops.values {
                for stage in desktop.stages.values {
                    if let group = stage.groups.first(where: { $0.windowIDs.contains(windowID) }) {
                        return "\(group.id):\(group.activeWindowID?.rawValue ?? windowID.rawValue)/\(group.windowIDs.count)"
                    }
                }
            }
        }
        return nil
    }

    nonisolated public static func isWindowVisiblyOccluded(
        _ target: ScopedWindowSnapshot,
        in snapshot: DaemonSnapshot
    ) -> Bool {
        let targetFrame = target.window.frame.cgRect
        for entry in snapshot.windows {
            if entry.window.id == target.window.id {
                return false
            }
            guard entry.window.isOnScreen else { continue }
            let frame = entry.window.frame.cgRect
            guard !HiddenWindowPlacement.isHiddenOrLegacyOffscreen(frame, in: snapshot.displays) else { continue }
            let intersection = frame.intersection(targetFrame)
            guard !intersection.isNull,
                  intersection.width >= 24,
                  intersection.height >= 24,
                  intersection.width * intersection.height >= 2_500
            else { continue }
            return true
        }
        return false
    }

    private static func axToNS(_ rect: CGRect) -> CGRect {
        let primary = NSScreen.screens.first(where: { $0.frame.origin == .zero })
            ?? NSScreen.main
            ?? NSScreen.screens.first
        guard let primary else { return rect }
        return CGRect(
            x: rect.minX,
            y: primary.frame.height - rect.minY - rect.height,
            width: rect.width,
            height: rect.height
        )
    }

}

@MainActor
private final class BorderPanel: NSPanel {
    private let borderView = BorderView()

    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue - 1)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        ignoresMouseEvents = true
        hasShadow = false
        contentView = borderView
    }

    func render(frame: CGRect, color: NSColor, thickness: CGFloat, cornerRadius: CGFloat) {
        let expanded = frame.insetBy(dx: -thickness / 2, dy: -thickness / 2)
        // FR-023 : aucun travail de fenêtre si rien n'a changé depuis le dernier rendu visible.
        guard !isVisible
            || expanded != self.frame
            || color != borderView.color
            || thickness != borderView.thickness
            || cornerRadius != borderView.cornerRadius
        else { return }
        if color != borderView.color { borderView.color = color }
        if thickness != borderView.thickness { borderView.thickness = thickness }
        if cornerRadius != borderView.cornerRadius { borderView.cornerRadius = cornerRadius }
        if expanded != self.frame { setFrame(expanded, display: true) }
        orderFrontRegardless()
    }
}

@MainActor
private final class BorderView: NSView {
    var color: NSColor = .systemBlue { didSet { needsDisplay = true } }
    var thickness: CGFloat = 2 { didSet { needsDisplay = true } }
    var cornerRadius: CGFloat = 10 { didSet { needsDisplay = true } }

    override var isOpaque: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let path = NSBezierPath(
            roundedRect: bounds.insetBy(dx: thickness / 2, dy: thickness / 2),
            xRadius: cornerRadius,
            yRadius: cornerRadius
        )
        path.lineWidth = thickness
        color.setStroke()
        path.stroke()
    }
}
