import AppKit
import RoadieAX
import RoadieCore

/// Ce que `BorderController` demande au panneau d'afficher : valeur pure, comparable dans les tests.
/// `groupLabel` est nul pour une fenêtre hors groupe : le rendu reste alors celui d'une simple bordure.
struct BorderRenderModel: Equatable {
    var frame: CGRect
    var color: NSColor
    var thickness: CGFloat
    var cornerRadius: CGFloat
    var groupLabel: String?
}

/// Frontière vers l'écran réel (panneau AppKit), remplaçable par un faux dans les tests.
@MainActor
protocol BorderRendering: AnyObject {
    func render(_ model: BorderRenderModel)
    func hide()
}

@MainActor
public final class BorderController {
    private let snapshotService: SnapshotService
    private let configLoader: () -> RoadieConfig
    private let panel: BorderRendering
    private var refreshTimer: Timer?

    public init(
        snapshotService: SnapshotService = SnapshotService(),
        configLoader: @escaping () -> RoadieConfig = { ConfigReloadService.shared.currentConfig() }
    ) {
        self.snapshotService = snapshotService
        self.configLoader = configLoader
        self.panel = BorderPanel()
    }

    init(
        snapshotService: SnapshotService,
        configLoader: @escaping () -> RoadieConfig,
        panel: BorderRendering
    ) {
        self.snapshotService = snapshotService
        self.configLoader = configLoader
        self.panel = panel
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

    func refresh() {
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
        panel.render(BorderRenderModel(
            frame: Self.axToNS(entry.window.frame.cgRect),
            color: color,
            thickness: CGFloat(max(1, config.thickness)),
            cornerRadius: CGFloat(max(0, config.cornerRadius)),
            groupLabel: Self.groupLabel(for: focusedWindowID, snapshot: snapshot)
        ))
    }

    private func hidePanel() {
        panel.hide()
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

    /// Libellé discret « nom du groupe, position du membre actif/taille » (ex. « docs 2/3 »), ou nil hors groupe.
    /// Complexité : O(écrans x bureaux x stages x groupes + taille du groupe), exécuté à chaque rafraîchissement.
    static func groupLabel(for windowID: WindowID, snapshot: DaemonSnapshot) -> String? {
        for display in snapshot.state.displays.values {
            for desktop in display.desktops.values {
                for stage in desktop.stages.values {
                    guard let group = stage.groups.first(where: { $0.windowIDs.contains(windowID) }) else { continue }
                    let active = group.activeWindowID ?? windowID
                    let position = (group.windowIDs.firstIndex(of: active) ?? 0) + 1
                    return "\(group.id) \(position)/\(group.windowIDs.count)"
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

    static func axToNS(_ rect: CGRect) -> CGRect {
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
private final class BorderPanel: NSPanel, BorderRendering {
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

    func hide() {
        if isVisible { orderOut(nil) }
    }

    func render(_ model: BorderRenderModel) {
        let expanded = model.frame.insetBy(dx: -model.thickness / 2, dy: -model.thickness / 2)
        // FR-023 : aucun travail de fenêtre si rien n'a changé depuis le dernier rendu visible.
        guard !isVisible
            || expanded != self.frame
            || model.color != borderView.color
            || model.thickness != borderView.thickness
            || model.cornerRadius != borderView.cornerRadius
            || model.groupLabel != borderView.groupLabel
        else { return }
        if model.color != borderView.color { borderView.color = model.color }
        if model.thickness != borderView.thickness { borderView.thickness = model.thickness }
        if model.cornerRadius != borderView.cornerRadius { borderView.cornerRadius = model.cornerRadius }
        if model.groupLabel != borderView.groupLabel { borderView.groupLabel = model.groupLabel }
        if expanded != self.frame { setFrame(expanded, display: true) }
        orderFrontRegardless()
    }
}

@MainActor
private final class BorderView: NSView {
    var color: NSColor = .systemBlue { didSet { needsDisplay = true } }
    var thickness: CGFloat = 2 { didSet { needsDisplay = true } }
    var cornerRadius: CGFloat = 10 { didSet { needsDisplay = true } }
    var groupLabel: String? { didSet { needsDisplay = true } }

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
        drawGroupLabel()
    }

    /// Pastille dans le coin haut droit, à l'intérieur de la bordure, couleur de la bordure.
    /// Largeur bornée à la place disponible ; libellé tronqué sur une ligne ; rien si la place manque.
    private func drawGroupLabel() {
        guard let groupLabel else { return }
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .semibold),
            .foregroundColor: NSColor.white,
            .paragraphStyle: paragraph
        ]
        let text = NSAttributedString(string: groupLabel, attributes: attributes)
        guard let geometry = BorderGroupPill.geometry(bounds: bounds, thickness: thickness, textSize: text.size()) else { return }
        color.setFill()
        NSBezierPath(roundedRect: geometry.pill, xRadius: geometry.pill.height / 2, yRadius: geometry.pill.height / 2).fill()
        text.draw(in: geometry.text)
    }
}

/// Géométrie de la pastille de groupe (fonction pure, testable sans AppKit à l'écran).
enum BorderGroupPill {
    static let rightMargin: CGFloat = 8
    static let topMargin: CGFloat = 6
    static let horizontalPadding: CGFloat = 6
    static let verticalPadding: CGFloat = 2
    /// Largeur de texte minimale pour que la pastille reste lisible (au moins « … » et un caractère).
    static let minimumTextWidth: CGFloat = 16

    struct Geometry: Equatable {
        var pill: CGRect
        var text: CGRect
    }

    /// Pastille ancrée en haut à droite. Sa largeur ne dépasse jamais l'espace entre les deux marges
    /// intérieures de la bordure : l'origine ne devient donc jamais négative. `nil` si la place
    /// (largeur ou hauteur) est insuffisante. O(1).
    static func geometry(bounds: CGRect, thickness: CGFloat, textSize: CGSize) -> Geometry? {
        let inset = thickness + rightMargin
        let availableWidth = bounds.width - 2 * inset
        let pillHeight = textSize.height + 2 * verticalPadding
        guard availableWidth >= minimumTextWidth + 2 * horizontalPadding,
              bounds.height >= pillHeight + 2 * (thickness + topMargin)
        else { return nil }
        let pillWidth = min(textSize.width + 2 * horizontalPadding, availableWidth)
        let pill = CGRect(
            x: bounds.maxX - inset - pillWidth,
            y: bounds.maxY - thickness - topMargin - pillHeight,
            width: pillWidth,
            height: pillHeight
        )
        let text = CGRect(
            x: pill.minX + horizontalPadding,
            y: pill.minY + verticalPadding,
            width: pillWidth - 2 * horizontalPadding,
            height: textSize.height
        )
        return Geometry(pill: pill, text: text)
    }
}
