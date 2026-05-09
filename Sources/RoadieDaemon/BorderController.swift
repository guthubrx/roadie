import AppKit
import RoadieAX
import RoadieCore

@MainActor
public final class BorderController {
    private let snapshotService: SnapshotService
    private let snapshotProvider: any SystemSnapshotProviding
    private let stageStore: StageStore
    private let configLoader: () -> RoadieConfig
    private let panel = BorderPanel()
    private var refreshTimer: Timer?
    private var activationObserver: NSObjectProtocol?
    private var focusObserver: AXObserver?
    private var activePID: pid_t?
    private var pendingRefresh = false

    public init(
        snapshotService: SnapshotService = SnapshotService(),
        snapshotProvider: any SystemSnapshotProviding = LiveSystemSnapshotProvider(),
        stageStore: StageStore = StageStore(),
        configLoader: @escaping () -> RoadieConfig = { (try? RoadieConfigLoader.load()) ?? RoadieConfig() }
    ) {
        self.snapshotService = snapshotService
        self.snapshotProvider = snapshotProvider
        self.stageStore = stageStore
        self.configLoader = configLoader
    }

    public func start() {
        NSApplication.shared.setActivationPolicy(.accessory)
        refresh()
        startFocusObserver()
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshIfChanged() }
        }
        RunLoop.main.add(refreshTimer!, forMode: .common)
    }

    public func stop() {
        refreshTimer?.invalidate()
        refreshTimer = nil
        if let activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(activationObserver)
        }
        activationObserver = nil
        removeFocusObserver()
        panel.orderOut(nil)
    }

    private func startFocusObserver() {
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
                return
            }
            Task { @MainActor in
                self?.watchFocusedWindowChanges(for: app.processIdentifier)
                self?.scheduleImmediateRefresh()
            }
        }
        if let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier {
            watchFocusedWindowChanges(for: pid)
        }
    }

    private func watchFocusedWindowChanges(for pid: pid_t) {
        guard pid != activePID else { return }
        removeFocusObserver()

        var createdObserver: AXObserver?
        let error = AXObserverCreate(pid, borderFocusObserverCallback, &createdObserver)
        guard error == .success, let createdObserver else { return }

        let appElement = AXUIElementCreateApplication(pid)
        let refcon = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        let added = AXObserverAddNotification(
            createdObserver,
            appElement,
            kAXFocusedWindowChangedNotification as CFString,
            refcon
        )
        guard added == .success || added == .notificationAlreadyRegistered else { return }

        focusObserver = createdObserver
        activePID = pid
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(createdObserver), .commonModes)
    }

    private func removeFocusObserver() {
        if let focusObserver {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(focusObserver), .commonModes)
        }
        focusObserver = nil
        activePID = nil
    }

    fileprivate func scheduleImmediateRefresh() {
        guard !pendingRefresh else { return }
        pendingRefresh = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.pendingRefresh = false
            if !self.refreshFocusedWindowFast() {
                self.refresh()
            }
        }
    }

    private func refreshFocusedWindowFast() -> Bool {
        let config = configLoader().fx.borders
        guard config.enabled else {
            panel.orderOut(nil)
            return true
        }
        let displays = snapshotProvider.displays()
        guard let focusedWindowID = snapshotProvider.focusedWindowID(),
              let window = snapshotProvider.windows(includeAccessibilityAttributes: false).first(where: { $0.id == focusedWindowID }),
              !isHidden(window.frame.cgRect, in: displays)
        else {
            panel.orderOut(nil)
            return false
        }
        panel.render(
            frame: Self.axToNS(window.frame.cgRect),
            color: activeColor(for: stageStore.state().stageScope(for: focusedWindowID)?.stageID, config: config),
            thickness: CGFloat(max(1, config.thickness)),
            cornerRadius: CGFloat(max(0, config.cornerRadius)),
            windowID: focusedWindowID
        )
        return true
    }

    private func refresh() {
        let config = configLoader().fx.borders
        guard config.enabled else {
            panel.orderOut(nil)
            return
        }

        let snapshot = snapshotService.snapshot(
            includeAccessibilityAttributes: false,
            followExternalFocus: true,
            persistState: false
        )
        guard let focusedWindowID = snapshot.focusedWindowID,
              let entry = snapshot.windows.first(where: { $0.window.id == focusedWindowID }),
              !isHidden(entry.window.frame.cgRect, in: snapshot.displays)
        else {
            panel.orderOut(nil)
            return
        }

        let color = activeColor(for: entry.scope?.stageID, config: config)
        _ = groupIndicator(for: focusedWindowID, snapshot: snapshot)
        panel.render(
            frame: Self.axToNS(entry.window.frame.cgRect),
            color: color,
            thickness: CGFloat(max(1, config.thickness)),
            cornerRadius: CGFloat(max(0, config.cornerRadius)),
            windowID: focusedWindowID
        )
    }

    private func refreshIfChanged() {
        let focusedID = snapshotService.focusedWindowID()
        guard focusedID != panel.renderedWindowID else { return }
        refresh()
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

    private func isHidden(_ frame: CGRect, in displays: [DisplaySnapshot]) -> Bool {
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

private let borderFocusObserverCallback: AXObserverCallback = { _, _, _, refcon in
    guard let refcon else { return }
    let controller = Unmanaged<BorderController>
        .fromOpaque(refcon)
        .takeUnretainedValue()
    Task { @MainActor in
        controller.scheduleImmediateRefresh()
    }
}

@MainActor
private final class BorderPanel: NSPanel {
    private let borderView = BorderView()
    private(set) var renderedWindowID: WindowID?
    private var lastRender: (frame: CGRect, color: NSColor, thickness: CGFloat, cornerRadius: CGFloat)?

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

    override func orderOut(_ sender: Any?) {
        renderedWindowID = nil
        lastRender = nil
        super.orderOut(sender)
    }

    func render(frame: CGRect, color: NSColor, thickness: CGFloat, cornerRadius: CGFloat, windowID: WindowID? = nil) {
        let expanded = frame.insetBy(dx: -thickness / 2, dy: -thickness / 2)
        renderedWindowID = windowID
        if let lastRender,
           lastRender.frame.isEquivalent(to: expanded, tolerancePoints: 0.5),
           lastRender.color == color,
           lastRender.thickness == thickness,
           lastRender.cornerRadius == cornerRadius {
            orderFrontRegardless()
            return
        }
        lastRender = (expanded, color, thickness, cornerRadius)
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
