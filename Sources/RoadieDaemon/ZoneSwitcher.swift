import AppKit
import Foundation
import RoadieAX
import RoadieCore

/// ⌥Tab (session 135), à la manière de ⌘Tab : ⌥ tenu, chaque Tab avance dans les zones récentes de la recherche à
/// l'écran (⌥⇧Tab recule) ; la liste paraît après 0,15 s ; relâcher ⌥ ramène la fenêtre de la zone, sa stage et son
/// bureau, puis clique la zone.
@MainActor
public final class ZoneSwitcherController {
    private let service: SnapshotService
    private let events: EventLog
    private var records: [ZoneRecord] = []
    private var index = 0
    private var startedAt = Date()
    private var timer: Timer?
    private var panel: ZoneSwitcherPanel?

    public init(service: SnapshotService, events: EventLog = EventLog()) {
        self.service = service
        self.events = events
    }

    /// Un appui sur ⌥Tab (ou ⌥⇧Tab, `reverse`). O(n).
    public func press(reverse: Bool) {
        if timer != nil {
            guard !records.isEmpty else { return }
            index = (index + (reverse ? records.count - 1 : 1)) % records.count
            panel?.select(index)
            return
        }
        // Les zones parcourues sont celles des cartes montrées.
        records = Array(ZoneHistory.shared.records.prefix(ZoneSwitcherPanel.maxCards))
        guard !records.isEmpty else {
            events.append(RoadieEvent(type: "zone.empty"))
            return
        }
        index = ZoneNavigation.firstIndex(count: records.count, mostRecentWindow: records.first?.windowID,
                                          frontWindow: service.focusedWindowID()?.rawValue, reverse: reverse)
        startedAt = Date()
        let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.tick() } }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func tick() {
        guard CGEventSource.flagsState(.combinedSessionState).contains(.maskAlternate) else {
            finish()
            return
        }
        if panel == nil, Date().timeIntervalSince(startedAt) > 0.15 {
            let shown = ZoneSwitcherPanel(records: records)
            shown.select(index)
            shown.present()
            panel = shown
        }
    }

    /// ⌥ relâché : la zone choisie. La fenêtre revient par le sélecteur de fenêtres (stage et bureau compris), puis
    /// l'attente du premier plan et le clic tournent hors du fil principal.
    private func finish() {
        timer?.invalidate()
        timer = nil
        panel?.close()
        panel = nil
        guard records.indices.contains(index) else { return }
        let record = records[index]
        let element = ZoneHistory.shared.element(for: record)
        let switcher = WindowSwitcherService(service: service)
        let events = events
        Task { @MainActor in
            let entries = await switcher.load().entries
            guard let entry = entries.first(where: { $0.id.rawValue == record.windowID }) else {
                ZoneHistory.shared.forget(record)
                ZoneThumbnails.shared.remove(record.key)
                events.append(RoadieEvent(type: "zone.missing", details: ["app": record.appName]))
                return
            }
            _ = switcher.activate(entry)
            let result = await Task.detached(priority: .userInitiated) {
                LiveAppTargetProvider().clickZone(record, element: element)
            }.value
            events.append(RoadieEvent(type: "zone.go", details: [
                "app": record.appName, "changed": String(result.changed), "message": result.message]))
        }
    }
}

/// Zones récentes en cartes, à la manière de ⌘Tab (session 135) : vignette de la fenêtre autour de la zone, zone
/// entourée, icône de l'application et texte de la zone ; la carte choisie est bordée de la couleur d'accent.
@MainActor
final class ZoneSwitcherPanel {
    private let panel: NSPanel
    private var cards: [NSView] = []
    static let cardSize = CGSize(width: 240, height: 176), thumbHeight: CGFloat = 136, gap: CGFloat = 12, maxCards = 7

    init(records: [ZoneRecord]) {
        let shown = Array(records.prefix(Self.maxCards))
        let width = CGFloat(shown.count) * (Self.cardSize.width + Self.gap) + Self.gap
        let height = Self.cardSize.height + 2 * Self.gap
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: width, height: height),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .popUpMenu
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.appearance = NSAppearance(named: .darkAqua)
        let effect = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        effect.material = .hudWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 16
        effect.layer?.masksToBounds = true
        for (offset, record) in shown.enumerated() {
            let origin = NSPoint(x: Self.gap + CGFloat(offset) * (Self.cardSize.width + Self.gap), y: Self.gap)
            let card = Self.card(record, frame: NSRect(origin: origin, size: Self.cardSize))
            effect.addSubview(card)
            cards.append(card)
        }
        panel.contentView = effect
    }

    /// Zone dans la vignette, en points de la vignette affichée (origine en bas à gauche). nil sans recadrage. O(1).
    static func highlight(zone: CGRect, crop: CGRect, in thumb: CGSize) -> CGRect? {
        guard crop.width > 0, crop.height > 0 else { return nil }
        let scale = min(thumb.width / crop.width, thumb.height / crop.height)
        let drawn = CGSize(width: crop.width * scale, height: crop.height * scale)
        let inset = CGPoint(x: (thumb.width - drawn.width) / 2, y: (thumb.height - drawn.height) / 2)
        let local = zone.offsetBy(dx: -crop.minX, dy: -crop.minY)
        // Accessibilité : y vers le bas ; vue AppKit : y vers le haut.
        return CGRect(x: inset.x + local.minX * scale, y: inset.y + (crop.height - local.maxY) * scale,
                      width: local.width * scale, height: local.height * scale).insetBy(dx: -3, dy: -3)
    }

    private static func card(_ record: ZoneRecord, frame: NSRect) -> NSView {
        let card = NSView(frame: frame)
        card.wantsLayer = true
        card.layer?.cornerRadius = 10
        card.layer?.borderWidth = 3
        card.layer?.borderColor = NSColor.clear.cgColor
        let thumbFrame = NSRect(x: 6, y: frame.height - 6 - thumbHeight, width: frame.width - 12, height: thumbHeight)
        let thumb = NSImageView(frame: thumbFrame)
        thumb.imageScaling = .scaleProportionallyUpOrDown
        thumb.wantsLayer = true
        thumb.layer?.cornerRadius = 6
        thumb.layer?.masksToBounds = true
        thumb.layer?.backgroundColor = NSColor(white: 0.12, alpha: 1).cgColor
        let appPath = NSWorkspace.shared.urlForApplication(withBundleIdentifier: record.bundleID)?.path
        let appIcon = appPath.map { NSWorkspace.shared.icon(forFile: $0) }
        if let image = ZoneThumbnails.shared.image(for: record.key), let crop = record.thumbnailCrop?.cgRect {
            thumb.image = image
            if let ring = highlight(zone: record.relative.cgRect, crop: crop, in: thumbFrame.size) {
                let marker = NSView(frame: ring)
                marker.wantsLayer = true
                marker.layer?.borderWidth = 2
                marker.layer?.cornerRadius = 4
                marker.layer?.borderColor = NSColor.systemYellow.cgColor
                thumb.addSubview(marker)
            }
        } else {
            // Pas de vignette (autorisation, fenêtre non capturable) : l'icône de l'application.
            thumb.imageScaling = .scaleProportionallyDown
            thumb.image = appIcon
        }
        let icon = NSImageView(frame: NSRect(x: 8, y: 8, width: 22, height: 22))
        icon.image = appIcon ?? NSImage(systemSymbolName: "app", accessibilityDescription: nil)
        let title = NSTextField(labelWithString: record.title)
        title.font = .systemFont(ofSize: 12, weight: .semibold)
        title.lineBreakMode = .byTruncatingTail
        title.frame = NSRect(x: 36, y: 9, width: frame.width - 44, height: 18)
        title.toolTip = "\(record.appName) · \(record.windowTitle)"
        [thumb, icon, title].forEach(card.addSubview)
        return card
    }

    func select(_ index: Int) {
        for (offset, card) in cards.enumerated() {
            let chosen = offset == index
            card.layer?.borderColor = chosen ? NSColor.controlAccentColor.cgColor : NSColor.clear.cgColor
            card.layer?.backgroundColor = chosen ? NSColor.white.withAlphaComponent(0.08).cgColor : NSColor.clear.cgColor
        }
    }

    /// Au centre de l'écran du pointeur, sans prendre le clavier.
    func present() {
        let mouse = NSEvent.mouseLocation
        if let screen = (NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main)?.visibleFrame {
            panel.setFrameOrigin(NSPoint(x: screen.midX - panel.frame.width / 2, y: screen.midY - panel.frame.height / 2))
        }
        panel.orderFrontRegardless()
    }

    func close() { panel.orderOut(nil) }
}
