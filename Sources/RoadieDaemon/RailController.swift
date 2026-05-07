import AppKit
import Foundation
import RoadieCore

@MainActor
public final class RailController {
    private let store: StageStore
    private let snapshotService: SnapshotService
    private let commandService: StageCommandService
    private var panels: [DisplayID: RailPanel] = [:]
    private var refreshTimer: Timer?
    private var clickMonitors: [Any] = []

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
        if let local = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown, handler: { [weak self] event in
            self?.handleClick(at: NSEvent.mouseLocation)
            return event
        }) {
            clickMonitors.append(local)
        }
        if let global = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown, handler: { [weak self] _ in
            DispatchQueue.main.async {
                self?.handleClick(at: NSEvent.mouseLocation)
            }
        }) {
            clickMonitors.append(global)
        }
    }

    private func handleClick(at screenPoint: CGPoint) {
        for (displayID, panel) in panels {
            guard panel.frame.contains(screenPoint),
                  let stageID = panel.stageID(at: screenPoint)
            else { continue }
            print("rail click stage \(stageID.rawValue)")
            fflush(stdout)
            _ = commandService.switchTo(stageID.rawValue, displayID: displayID)
            rebuildPanels()
            return
        }
    }

    private func rebuildPanels() {
        _ = snapshotService.snapshot()
        let state = store.state()
        let renderMode = RailRenderMode.load()
        let screensByDisplayID = Dictionary(uniqueKeysWithValues: NSScreen.screens.compactMap { screen in
            Self.displayID(for: screen).map { ($0, screen) }
        })

        for (displayID, screen) in screensByDisplayID {
            let desktopID = state.currentDesktopID(for: displayID)
            let scope = state.scopes.first { $0.displayID == displayID && $0.desktopID == desktopID }
                ?? PersistentStageScope(displayID: displayID, desktopID: desktopID)
            let panel = panels[displayID] ?? RailPanel()
            panel.position(on: screen)
            panel.render(scope: scope, mode: renderMode) { [weak self] stageID in
                _ = self?.commandService.switchTo(stageID.rawValue, displayID: displayID)
                self?.rebuildPanels()
            }
            if panels[displayID] == nil {
                panels[displayID] = panel
                panel.makeKey()
                panel.orderFrontRegardless()
            }
        }

        for displayID in panels.keys where screensByDisplayID[displayID] == nil {
            panels[displayID]?.orderOut(nil)
            panels.removeValue(forKey: displayID)
        }
    }

    private static func displayID(for screen: NSScreen) -> DisplayID? {
        guard let raw = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID,
              let uuid = CGDisplayCreateUUIDFromDisplayID(raw)?.takeRetainedValue(),
              let string = CFUUIDCreateString(nil, uuid) as String?
        else { return nil }
        return DisplayID(rawValue: string)
    }
}

@MainActor
private final class RailPanel: NSPanel {
    private let stack = NSStackView()
    private let width: CGFloat = 260

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
        backgroundColor = NSColor.black.withAlphaComponent(0.36)
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        ignoresMouseEvents = false
        hasShadow = true

        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.edgeInsets = NSEdgeInsets(top: 24, left: 18, bottom: 24, right: 18)
        contentView = stack
    }

    func position(on screen: NSScreen) {
        let frame = screen.frame
        setFrame(
            CGRect(x: frame.minX, y: frame.minY, width: width, height: frame.height),
            display: true
        )
    }

    func render(scope: PersistentStageScope, mode: RailRenderMode, onSelect: @escaping (StageID) -> Void) {
        stack.arrangedSubviews.forEach { view in
            stack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        let ids = stageIDs(from: scope)
        for id in ids {
            let stage = scope.stages.first { $0.id == id } ?? PersistentStage(id: id)
            let card = StageCardView(stage: stage, isActive: id == scope.activeStageID, mode: mode)
            card.onClick = { onSelect(id) }
            stack.addArrangedSubview(card)
        }
    }

    func stageID(at screenPoint: CGPoint) -> StageID? {
        guard let contentView else { return nil }
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

    private func stageIDs(from scope: PersistentStageScope) -> [StageID] {
        var ids = scope.stages.map(\.id)
        for id in (1...6).map({ StageID(rawValue: String($0)) }) where !ids.contains(id) {
            ids.append(id)
        }
        return ids
    }
}

@MainActor
private enum RailRenderMode: String {
    case stacked = "stacked-previews"
    case mosaic
    case parallax = "parallax-45"
    case icons = "icons-only"

    static func load() -> RailRenderMode {
        let path = NSString(string: "~/.config/roadies/roadies.toml").expandingTildeInPath
        guard let raw = try? String(contentsOfFile: path, encoding: .utf8) else { return .stacked }
        if raw.contains("renderer = \"mosaic\"") { return .mosaic }
        if raw.contains("renderer = \"parallax-45\"") || raw.contains("renderer = \"parallax\"") { return .parallax }
        if raw.contains("renderer = \"icons-only\"") || raw.contains("renderer = \"icons\"") { return .icons }
        return .stacked
    }
}

@MainActor
private final class StageCardView: NSControl {
    let stageID: StageID
    private let stage: PersistentStage
    private let isActive: Bool
    private let mode: RailRenderMode
    var onClick: (() -> Void)?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    init(stage: PersistentStage, isActive: Bool, mode: RailRenderMode) {
        self.stage = stage
        self.stageID = stage.id
        self.isActive = isActive
        self.mode = mode
        super.init(frame: CGRect(x: 0, y: 0, width: 224, height: 142))
        wantsLayer = true
        target = self
        action = #selector(clicked)
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: 224).isActive = true
        heightAnchor.constraint(equalToConstant: mode == .icons ? 78 : 142).isActive = true
        layer?.cornerRadius = 18
        layer?.masksToBounds = false
        layer?.backgroundColor = NSColor(white: 0.08, alpha: isActive ? 0.92 : 0.58).cgColor
        layer?.borderWidth = isActive ? 1.8 : 0.8
        layer?.borderColor = (isActive ? NSColor.systemGreen : NSColor.white.withAlphaComponent(0.16)).cgColor
        layer?.shadowColor = (isActive ? NSColor.systemGreen : NSColor.black).cgColor
        layer?.shadowOpacity = isActive ? 0.62 : 0.28
        layer?.shadowRadius = isActive ? 18 : 8
        layer?.shadowOffset = .zero
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func clicked() {
        print("rail click stage \(stageID.rawValue)")
        fflush(stdout)
        onClick?()
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        drawCard()
    }

    private func drawCard() {
        let rect = bounds.insetBy(dx: 12, dy: 12)
        drawTitle(in: rect)
        switch mode {
        case .stacked:
            drawStacked(in: rect.insetBy(dx: 10, dy: 18))
        case .mosaic:
            drawMosaic(in: rect.insetBy(dx: 10, dy: 18))
        case .parallax:
            drawParallax(in: rect.insetBy(dx: 10, dy: 18))
        case .icons:
            drawIcons(in: rect.insetBy(dx: 8, dy: 18))
        }
    }

    private func drawTitle(in rect: CGRect) {
        let badgeRect = CGRect(x: rect.minX, y: rect.maxY - 26, width: 28, height: 22)
        rounded(badgeRect, radius: 9, color: isActive ? .systemGreen : NSColor.white.withAlphaComponent(0.20))
        let attrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: NSColor.white,
            .font: NSFont.boldSystemFont(ofSize: 13),
        ]
        stageID.rawValue.draw(in: badgeRect.insetBy(dx: 0, dy: 3), withAttributes: attrs)

        let count = stage.members.count
        let titleAttrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: NSColor.white.withAlphaComponent(isActive ? 0.92 : 0.68),
            .font: NSFont.systemFont(ofSize: 12, weight: .semibold),
        ]
        stage.name.draw(in: CGRect(x: badgeRect.maxX + 8, y: badgeRect.minY + 8, width: rect.width - 42, height: 16), withAttributes: titleAttrs)

        let label = "\(stage.mode.rawValue) · \(count) \(count > 1 ? "fenêtres" : "fenêtre")"
        let labelAttrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: NSColor.white.withAlphaComponent(isActive ? 0.84 : 0.50),
            .font: NSFont.systemFont(ofSize: 10, weight: .medium),
        ]
        label.draw(in: CGRect(x: badgeRect.maxX + 8, y: badgeRect.minY - 5, width: rect.width - 42, height: 14), withAttributes: labelAttrs)
    }

    private func drawStacked(in rect: CGRect) {
        guard !stage.members.isEmpty else {
            drawEmpty(in: rect)
            return
        }
        let previews = previewRects(in: rect, maxCount: 5)
        for (index, preview) in previews.enumerated().reversed() {
            let offset = CGFloat(index) * 9
            let shifted = preview.offsetBy(dx: -offset * 0.85, dy: offset * 0.45)
            drawPreview(shifted, index: index)
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
        let previews = previewRects(in: rect, maxCount: 5)
        for (index, preview) in previews.enumerated().reversed() {
            let shifted = preview.offsetBy(dx: CGFloat(index) * -18, dy: CGFloat(index) * 7)
            drawPreview(shifted, index: index, skewed: true)
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

    private func previewRects(in rect: CGRect, maxCount: Int) -> [CGRect] {
        let count = min(stage.members.count, maxCount)
        let base = CGRect(x: rect.minX + 18, y: rect.minY + 6, width: rect.width - 36, height: rect.height - 44)
        return (0..<count).map { _ in base }
    }

    private func drawPreview(_ rect: CGRect, index: Int, skewed: Bool = false) {
        guard !rect.isEmpty else { return }
        let path = NSBezierPath(roundedRect: rect, xRadius: 12, yRadius: 12)
        color(for: stage.members[safe: index], index: index).setFill()
        path.fill()
        NSColor.white.withAlphaComponent(isActive ? 0.34 : 0.18).setStroke()
        path.lineWidth = 1
        path.stroke()
        if skewed {
            NSColor.black.withAlphaComponent(0.18).setFill()
            NSBezierPath(roundedRect: rect.insetBy(dx: 12, dy: 10), xRadius: 8, yRadius: 8).fill()
        }
        let title = stage.members[safe: index]?.title ?? ""
        let short = title.isEmpty ? "Window" : String(title.prefix(22))
        short.draw(in: rect.insetBy(dx: 10, dy: 8), withAttributes: [
            .foregroundColor: NSColor.white.withAlphaComponent(0.82),
            .font: NSFont.systemFont(ofSize: 10, weight: .medium),
        ])
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

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
