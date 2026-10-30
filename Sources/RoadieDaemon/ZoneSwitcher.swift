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
        records = ZoneHistory.shared.records
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

/// Liste des zones récentes : application, texte de la zone, fenêtre ; la zone choisie est surlignée.
@MainActor
final class ZoneSwitcherPanel {
    private let panel: NSPanel
    private var rows: [NSView] = []
    private static let width: CGFloat = 520, rowHeight: CGFloat = 46

    init(records: [ZoneRecord]) {
        let shown = Array(records.prefix(10))
        let height = CGFloat(shown.count) * Self.rowHeight + 16
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: Self.width, height: height),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .popUpMenu
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.appearance = NSAppearance(named: .darkAqua)
        let effect = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: Self.width, height: height))
        effect.material = .hudWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 12
        effect.layer?.masksToBounds = true
        for (offset, record) in shown.enumerated() {
            let row = Self.row(record, frame: NSRect(x: 8, y: height - 8 - CGFloat(offset + 1) * Self.rowHeight, width: Self.width - 16, height: Self.rowHeight))
            effect.addSubview(row)
            rows.append(row)
        }
        panel.contentView = effect
    }

    private static func row(_ record: ZoneRecord, frame: NSRect) -> NSView {
        let row = NSView(frame: frame)
        row.wantsLayer = true
        row.layer?.cornerRadius = 8
        let path = NSWorkspace.shared.urlForApplication(withBundleIdentifier: record.bundleID)?.path
        let icon = NSImageView(frame: NSRect(x: 8, y: 7, width: 32, height: 32))
        icon.image = path.map { NSWorkspace.shared.icon(forFile: $0) } ?? NSImage(systemSymbolName: "app", accessibilityDescription: nil)
        let title = NSTextField(labelWithString: "« \(record.title) »")
        title.font = .systemFont(ofSize: 14, weight: .semibold)
        title.lineBreakMode = .byTruncatingTail
        title.frame = NSRect(x: 50, y: 22, width: frame.width - 58, height: 18)
        let detail = NSTextField(labelWithString: "\(record.appName) · \(record.windowTitle)")
        detail.font = .systemFont(ofSize: 11)
        detail.textColor = .secondaryLabelColor
        detail.lineBreakMode = .byTruncatingTail
        detail.frame = NSRect(x: 50, y: 5, width: frame.width - 58, height: 15)
        [icon, title, detail].forEach(row.addSubview)
        return row
    }

    func select(_ index: Int) {
        for (offset, row) in rows.enumerated() {
            row.layer?.backgroundColor = offset == index ? NSColor.controlAccentColor.withAlphaComponent(0.55).cgColor : NSColor.clear.cgColor
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
