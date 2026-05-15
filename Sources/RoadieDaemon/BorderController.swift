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
        configLoader: @escaping () -> RoadieConfig = { (try? RoadieConfigLoader.load()) ?? RoadieConfig() }
    ) {
        self.snapshotService = snapshotService
        self.configLoader = configLoader
    }

    public func start() {
        NSApplication.shared.setActivationPolicy(.accessory)
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
            panel.orderOut(nil)
            return
        }

        let snapshot = snapshotService.snapshot()
        guard let focusedWindowID = snapshot.focusedWindowID,
              let entry = snapshot.windows.first(where: { $0.window.id == focusedWindowID }),
              entry.window.isTileCandidate,
              entry.scope != nil,
              !isHidden(entry.window.frame.cgRect, in: snapshot.displays),
              !Self.isWindowVisiblyOccluded(entry, in: snapshot)
        else {
            panel.orderOut(nil)
            return
        }

        let color = entry.pin == nil ? activeColor(for: entry.scope?.stageID, config: config) : .systemRed
        _ = groupIndicator(for: focusedWindowID, snapshot: snapshot)
        panel.render(
            frame: Self.axToNS(entry.window.frame.cgRect),
            color: color,
            thickness: CGFloat(max(1, config.thickness)),
            cornerRadius: CGFloat(max(0, config.cornerRadius))
        )
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
            guard !isObviouslyHidden(frame, in: snapshot.displays) else { continue }
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

    private func isHidden(_ frame: CGRect, in displays: [DisplaySnapshot]) -> Bool {
        Self.isObviouslyHidden(frame, in: displays)
    }

    nonisolated private static func isObviouslyHidden(_ frame: CGRect, in displays: [DisplaySnapshot]) -> Bool {
        if frame.maxX < -1000 || frame.minX < -10000 {
            return true
        }
        return displays.contains { display in
            let visible = display.visibleFrame.cgRect
            let nearBottomEdge = abs(frame.minY - (visible.maxY - 1)) <= 64
            let nearLeftEdge = abs(frame.maxX - (visible.minX + 1)) <= 4
            let nearRightEdge = abs(frame.minX - (visible.maxX - 1)) <= 4
            return nearBottomEdge && (nearLeftEdge || nearRightEdge)
        }
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
        borderView.color = color
        borderView.thickness = thickness
        borderView.cornerRadius = cornerRadius
        setFrame(expanded, display: true)
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

private extension NSColor {
    convenience init?(hex: String) {
        var raw = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if raw.hasPrefix("#") {
            raw.removeFirst()
        }
        guard raw.count == 6 || raw.count == 8,
              let value = UInt64(raw, radix: 16)
        else { return nil }

        let red: CGFloat
        let green: CGFloat
        let blue: CGFloat
        let alpha: CGFloat
        if raw.count == 8 {
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
        self.init(srgbRed: red, green: green, blue: blue, alpha: alpha)
    }
}
