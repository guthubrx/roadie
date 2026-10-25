import AppKit
import RoadieCore

/// Panneau global distinct du cycle Cmd+Tab. Le canevas conserve les images, sans recréer les cartes au survol.
/// Aucun contrôle à l’écran : disposition et loupe se règlent dans Paramètres > Vue d’ensemble.
@MainActor
final class OverviewPanel: NSPanel, NSWindowDelegate {
    let canvas = OverviewCanvas(frame: .zero)
    private let events: EventLog
    private let backdrop = NSView()
    private let blur = NSVisualEffectView()
    var onClose: (() -> Void)?
    var onKey: ((UInt16, Bool) -> Void)?
    var config = OverviewConfig()
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    private var escapeMonitor: Any?

    init(events: EventLog = EventLog()) {
        self.events = events
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        title = "Roadie · Vue d’ensemble"
        appearance = NSAppearance(named: .darkAqua)
        isReleasedWhenClosed = false
        acceptsMouseMovedEvents = true
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        minSize = CGSize(width: 780, height: 560)
        delegate = self
        let root = NSView()
        contentView = root
        root.wantsLayer = true
        isOpaque = false; backgroundColor = .clear; hasShadow = true
        // Fond : le fond d’écran flouté de l’utilisateur, qui masque les icônes du bureau comme Mission Control.
        // Sans image lisible, le flou système de ce qui est sous l’overlay prend le relais.
        blur.material = .hudWindow; blur.blendingMode = .behindWindow; blur.state = .active
        backdrop.wantsLayer = true
        backdrop.layer?.contentsGravity = .resizeAspectFill
        backdrop.layer?.masksToBounds = true
        root.addSubview(blur)
        root.addSubview(backdrop)
        // Une seule page : le canevas occupe l’écran, sans vue de défilement.
        root.addSubview(canvas)
    }

    func present(on screen: NSScreen, config: OverviewConfig) {
        self.config = config
        setFrame(screen.frame, display: false)
        appliedBlur = nil
        syncControls()
        layoutContent()
        orderFrontRegardless()
        makeKey()
        makeFirstResponder(canvas)
        if escapeMonitor == nil {
            escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard event.keyCode == 53 else { return event }
                let handled = MainActor.assumeIsolated {
                    guard let self, self.isVisible else { return false }
                    self.onClose?(); return true
                }
                return handled ? nil : event
            }
        }
    }

    private var appliedBlur: Double?

    /// Applique la configuration lue dans Paramètres ; le fond n’est recalculé que si le flou change.
    func syncControls() {
        canvas.config = config
        guard appliedBlur != config.backgroundBlur, let screen = screen ?? NSScreen.main else { return }
        appliedBlur = config.backgroundBlur
        let wallpaper = OverviewWallpaper.blurred(for: screen, percent: config.backgroundBlur, maxPixel: 960)
        backdrop.layer?.contents = wallpaper
        backdrop.isHidden = wallpaper == nil
    }

    func showMessage(_ message: String) {
        canvas.notice = message
        canvas.needsDisplay = true
    }

    func windowDidResize(_ notification: Notification) { layoutContent() }
    func windowShouldClose(_ sender: NSWindow) -> Bool { onClose?(); return false }

    private func layoutContent() {
        guard let root = contentView else { return }
        blur.frame = root.bounds
        backdrop.frame = root.bounds
        canvas.frame = root.bounds
        canvas.viewport = root.bounds.size
        canvas.rebuild()
    }

    /// Retire l’overlay et son écoute clavier avant une activation ou une fermeture.
    func dismiss(completion: () -> Void = {}) {
        orderOut(nil)
        if let escapeMonitor { NSEvent.removeMonitor(escapeMonitor) }; escapeMonitor = nil
        completion()
    }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown {
            let point = contentView?.convert(event.locationInWindow, from: nil) ?? .zero
            let target = contentView?.hitTest(point)
            events.append(RoadieEvent(type: "overview.input", details: ["x": String(Double(point.x)), "y": String(Double(point.y)),
                "target": target.map { String(describing: type(of: $0)) } ?? "none"]))
        }
        if event.type == .keyDown, [UInt16(53), 36, 76, 48, 123, 124, 125, 126].contains(event.keyCode) {
            onKey?(event.keyCode, event.modifierFlags.contains(.shift)); return
        }
        super.sendEvent(event)
    }
}

/// Dessin groupé : les captures gardent leur contenu entier. Identités et clics utilisent les mêmes rectangles.
@MainActor
final class OverviewCanvas: NSView {
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    var model = OverviewModel(entries: [], displays: [], state: PersistentStageState())
    var config = OverviewConfig()
    var viewport = CGSize(width: 1000, height: 700)
    var focusedDesktop: OverviewDesktopID?
    var selectedID: WindowID?
    /// Carte sous la souris : liseré clair seulement, sans effet sur la sélection.
    private(set) var hoveredID: WindowID?
    var magnifiedID: WindowID?
    var magnifiedFrame: CGRect? {
        guard config.loupe, let card = plan.cards.first(where: { $0.entry.id == magnifiedID }) else { return nil }
        return card.frame
    }
    var images: [WindowID: NSImage] = [:]
    var icons: [WindowID: NSImage] = [:]
    var appIcons: [Int32: NSImage] = [:]
    var notice: String?
    var onOpen: ((WindowSwitcherEntry) -> Void)?
    /// Puce de bureau lâchée dans un espace entre bureaux : bureau déplacé, écran visé et numéro de
    /// la place visée (SPEC-066, autre écran SPEC-070).
    var onMoveDesktop: ((OverviewDesktopID, DisplayID, DesktopID) -> Void)?
    /// Puce de stage lâchée dans un espace entre stages : stage, écran et bureau visés, stage devant
    /// laquelle elle s’insère (nil = en dernier) (SPEC-067, autre écran SPEC-070).
    var onMoveStage: ((StageScope, DisplayID, DesktopID, StageID?) -> Void)?
    /// Carte lâchée sur une carte d’une autre stage : la fenêtre rejoint cette stage (SPEC-067).
    var onMoveWindow: ((WindowSwitcherEntry, StageScope) -> Void)?
    private(set) var plan = OverviewLayout()
    /// Ce que l’on déplace : un bureau par sa puce, une stage par la puce de stage d’une carte, une fenêtre par sa carte.
    private enum DragSubject { case desktop(OverviewDesktopID), stage(StageScope, String), window(WindowSwitcherEntry) }
    /// Glisser actif au-delà de 4 points : en dessous, c’est un clic (une carte s’ouvre au relâchement).
    private struct Drag { let subject: DragSubject; let start: CGPoint; var point: CGPoint; var active = false }
    private var drag: Drag?
    private var tracking: NSTrackingArea?
    private var hover = OverviewHoverState()
    private var hoverWork: DispatchWorkItem?
    private var lastPointer: CGPoint?

    func rebuild() {
        plan = OverviewLayout.make(model: model, viewport: viewport, config: config, window: magnifiedID)
        needsDisplay = true
        setAccessibilityRole(.group)
        setAccessibilityLabel("Vue d’ensemble des bureaux et stages")
        setAccessibilityValue("Loupe : " + (focusedDesktop.map { "\($0.displayID.rawValue), bureau \($0.desktopID.rawValue)" } ?? "aucune"))
        let children = plan.cards.map { card in
            let element = NSAccessibilityElement()
            element.setAccessibilityRole(.button)
            element.setAccessibilityLabel(card.entry.window.appName + ", " + card.entry.window.title + ", " + card.entry.subtitleText)
            element.setAccessibilitySelected(card.entry.id == selectedID)
            element.setAccessibilityParent(self)
            if let window {
                element.setAccessibilityFrame(window.convertToScreen(convert(card.frame, to: nil)))
            }
            element.setAccessibilityCustomActions([NSAccessibilityCustomAction(name: "Ouvrir") { [weak self] in
                self?.onOpen?(card.entry); return true
            }])
            return element
        }
        setAccessibilityChildren(children)
    }

    func cancelHover() {
        hoverWork?.cancel(); hoverWork = nil
        hover = OverviewHoverState(); lastPointer = nil
    }

    override func updateTrackingAreas() {
        if let tracking { removeTrackingArea(tracking) }
        let new = NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(new); tracking = new
        super.updateTrackingAreas()
    }

    override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard point != lastPointer else { return }
        lastPointer = point
        let card = plan.cards.first { $0.frame.contains(point) }
        // Liseré clair sur la carte sous la souris : ce qu’un clic ouvrirait.
        if card?.entry.id != hoveredID { hoveredID = card?.entry.id; needsDisplay = true }
        let desktop = plan.desktops.first { $0.frame.contains(point) }?.desktop.id
        let target = desktop.map { OverviewHoverTarget(desktopID: $0, windowID: card?.entry.id) }
        guard config.loupe, hover.moved(to: target, at: ProcessInfo.processInfo.systemUptime) else { return }
        hoverWork?.cancel()
        guard target != nil else { return }
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.window?.isVisible == true,
                      let ready = self.hover.ready(at: ProcessInfo.processInfo.systemUptime) else { return }
                self.hover.consume()
                self.focusedDesktop = ready.desktopID
                // Le survol agrandit (loupe) sans déplacer la sélection : elle reste la fenêtre active ou
                // celle choisie aux flèches, celle qu’Entrée ouvre.
                self.magnifiedID = ready.windowID
                self.rebuild()
            }
        }
        hoverWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.11, execute: work)
    }

    override func mouseExited(with event: NSEvent) {
        hoverWork?.cancel(); hover = OverviewHoverState()
        if hoveredID != nil { hoveredID = nil; needsDisplay = true }
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if let item = plan.desktops.first(where: { chipFrame(for: $0).contains(point) }) {
            drag = Drag(subject: .desktop(item.desktop.id), start: point, point: point)
        } else if let card = plan.cards.first(where: { stageChipFrame(for: $0)?.contains(point) == true }), let scope = card.entry.scope {
            drag = Drag(subject: .stage(scope, card.stageName), start: point, point: point)
        } else if let card = plan.cards.first(where: { $0.frame.contains(point) }) {
            drag = Drag(subject: .window(card.entry), start: point, point: point)
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard var current = drag else { return }
        current.point = convert(event.locationInWindow, from: nil)
        // Une fenêtre absente du relevé (réduite, autre Space) ne se déplace pas : elle reste cliquable.
        if case .window(let entry) = current.subject, !entry.window.isOnScreen { drag = current; return }
        if !current.active, hypot(current.point.x - current.start.x, current.point.y - current.start.y) > 4 {
            current.active = true
            cancelHover()
        }
        drag = current
        if current.active { needsDisplay = true }
    }

    override func mouseUp(with event: NSEvent) {
        guard let current = drag else { return }
        drag = nil
        needsDisplay = true
        guard current.active else {
            if case .window(let entry) = current.subject { selectedID = entry.id; onOpen?(entry) }
            return
        }
        switch current.subject {
        case .desktop(let source):
            if let slot = dropSlot(source: source, point: current.point) { onMoveDesktop?(source, slot.display, slot.target) }
        case .stage(let scope, _):
            if let slot = stageSlot(source: scope, point: current.point) { onMoveStage?(scope, slot.display, slot.desktop, slot.before) }
        case .window(let entry):
            if let target = windowTarget(for: entry, point: current.point) { onMoveWindow?(entry, target) }
        }
    }

    /// Espace d’insertion : écran visé, numéro que prendra le bureau et trait, en coordonnées de la vue.
    struct DropSlot: Equatable { let display: DisplayID; let target: DesktopID; let line: CGRect }

    /// Espace entre deux bureaux de l’écran sous le pointeur le plus proche, y compris avant le premier
    /// et après le dernier. Bureaux empilés en Archipel, côte à côte en Baies. Sur l’écran d’origine,
    /// les espaces qui touchent le bureau déplacé ne changent rien ; sur un autre écran, le bureau prend
    /// le numéro de celui devant lequel il s’insère, ou suit le dernier. nil hors des écrans. O(b).
    func dropSlot(source: OverviewDesktopID, point: CGPoint) -> DropSlot? {
        guard let region = plan.displays.first(where: { $0.frame.insetBy(dx: -24, dy: -24).contains(point) }) else { return nil }
        let displayID = region.display.id
        let desktops = plan.desktops.filter { $0.desktop.id.displayID == displayID }
        guard !desktops.isEmpty else { return nil }
        let vertical = config.presentation != "bays"
        func lead(_ r: CGRect) -> CGFloat { vertical ? r.minY : r.minX }
        func trail(_ r: CGRect) -> CGFloat { vertical ? r.maxY : r.maxX }
        let gaps = (0...desktops.count).map { k -> CGFloat in
            if k == 0 { return lead(desktops[0].frame) }
            if k == desktops.count { return trail(desktops[k - 1].frame) }
            return (trail(desktops[k - 1].frame) + lead(desktops[k].frame)) / 2
        }
        let along = vertical ? point.y : point.x
        guard let k = gaps.indices.min(by: { abs(gaps[$0] - along) < abs(gaps[$1] - along) }) else { return nil }
        let target: DesktopID
        if displayID == source.displayID {
            guard let from = desktops.firstIndex(where: { $0.desktop.id == source }), k != from, k != from + 1 else { return nil }
            // Vers le haut, il prend le numéro du bureau devant lequel il s’insère ; vers le bas, celui d’avant l’espace.
            target = k < from ? desktops[k].desktop.id.desktopID : desktops[k - 1].desktop.id.desktopID
        } else {
            target = k < desktops.count ? desktops[k].desktop.id.desktopID
                : DesktopID(rawValue: desktops[k - 1].desktop.id.desktopID.rawValue + 1)
        }
        let frames = desktops.map(\.frame)
        let line = vertical
            ? CGRect(x: frames.map(\.minX).min() ?? 0, y: gaps[k], width: (frames.map(\.maxX).max() ?? 0) - (frames.map(\.minX).min() ?? 0), height: 0)
            : CGRect(x: gaps[k], y: frames.map(\.minY).min() ?? 0, width: 0, height: (frames.map(\.maxY).max() ?? 0) - (frames.map(\.minY).min() ?? 0))
        return DropSlot(display: displayID, target: target, line: line)
    }

    /// Puce du nom de bureau, en coordonnées de la vue : la même pour le dessin et le clic.
    func chipFrame(for item: OverviewLayout.Desktop) -> CGRect {
        let s = plan.scale
        let r = CGRect(x: item.frame.minX / s, y: item.frame.minY / s, width: item.frame.width / s, height: item.frame.height / s)
        let font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        let dot: CGFloat = item.desktop.isActive ? 12 : 0
        let width = min(r.width - 2 * OverviewLayout.side, ceil((item.desktop.name as NSString).size(withAttributes: [.font: font]).width) + 22 + dot)
        let chip = CGRect(x: r.minX + OverviewLayout.side, y: r.minY + OverviewLayout.top(bays: config.presentation == "bays"), width: width, height: 24)
        return CGRect(x: chip.minX * s, y: chip.minY * s, width: chip.width * s, height: chip.height * s)
    }

    /// Puce de stage d’une carte, en coordonnées de la vue : la même pour le dessin et la prise.
    func stageChipFrame(for card: OverviewLayout.Card) -> CGRect? {
        guard !card.stageName.isEmpty else { return nil }
        let s = plan.scale
        let frame = CGRect(x: card.frame.minX / s, y: card.frame.minY / s, width: card.frame.width / s, height: card.frame.height / s)
        let font = NSFont.systemFont(ofSize: 8.5, weight: .medium)
        let width = min(frame.width * 0.45, ceil((card.stageName as NSString).size(withAttributes: [.font: font]).width) + 16)
        let chip = CGRect(x: frame.maxX - width, y: frame.maxY - OverviewLayout.caption + 5, width: width, height: 14)
        return CGRect(x: chip.minX * s, y: chip.minY * s, width: chip.width * s, height: chip.height * s)
    }

    /// Place d’une stage : écran et bureau visés, stage devant laquelle elle s’insère (nil = en dernier) et trait.
    struct StageSlot: Equatable { let display: DisplayID; let desktop: DesktopID; let before: StageID?; let line: CGRect }

    /// Espace entre deux groupes de cartes d’une stage, dans le bureau sous le pointeur, sur tout écran ;
    /// trait vertical devant la première carte du groupe suivant, ou après la dernière carte. Bureau sans
    /// carte : trait sous sa puce. Les espaces qui touchent la stage déplacée ne changent rien. O(c).
    func stageSlot(source: StageScope, point: CGPoint) -> StageSlot? {
        guard let item = plan.desktops.first(where: { $0.frame.contains(point) }) else { return nil }
        let desktopID = item.desktop.id.desktopID, displayID = item.desktop.id.displayID
        let sameDesktop = displayID == source.displayID && desktopID == source.desktopID
        let s = plan.scale
        var groups: [(stage: StageID, first: CGRect, last: CGRect)] = []
        for card in plan.cards where card.entry.scope?.displayID == displayID && card.entry.scope?.desktopID == desktopID {
            guard let stage = card.entry.scope?.stageID else { continue }
            if groups.last?.stage == stage { groups[groups.count - 1].last = card.frame } else { groups.append((stage, card.frame, card.frame)) }
        }
        guard !groups.isEmpty else {
            guard !sameDesktop else { return nil }
            let chip = chipFrame(for: item)
            let side = OverviewLayout.side * s
            return StageSlot(display: displayID, desktop: desktopID, before: nil,
                             line: CGRect(x: item.frame.minX + side, y: chip.maxY + 10 * s, width: item.frame.width - 2 * side, height: 0))
        }
        let gap = 5 * s, imageHeight = max(1, groups[0].first.height - OverviewLayout.caption * s)
        let lines = (0...groups.count).map { k -> CGRect in
            let card = k < groups.count ? groups[k].first : groups[k - 1].last
            return CGRect(x: k < groups.count ? card.minX - gap : card.maxX + gap, y: card.minY, width: 0, height: imageHeight)
        }
        func distance(_ line: CGRect) -> CGFloat {
            hypot(point.x - line.minX, point.y - min(max(point.y, line.minY), line.maxY))
        }
        guard let k = lines.indices.min(by: { distance(lines[$0]) < distance(lines[$1]) }) else { return nil }
        if sameDesktop, let from = groups.firstIndex(where: { $0.stage == source.stageID }), k == from || k == from + 1 {
            return nil
        }
        return StageSlot(display: displayID, desktop: desktopID, before: k < groups.count ? groups[k].stage : nil, line: lines[k])
    }

    /// Stage de la carte sous le pointeur, sur tout écran, différente de celle de la fenêtre. O(c).
    func windowTarget(for entry: WindowSwitcherEntry, point: CGPoint) -> StageScope? {
        guard let scope = plan.cards.first(where: { $0.frame.contains(point) })?.entry.scope, scope != entry.scope else { return nil }
        return scope
    }

    func select(_ id: WindowID) {
        cancelHover()
        selectedID = id
        magnifiedID = id
        if let desktop = model.displays.flatMap(\.desktops).first(where: { $0.entries.contains { $0.id == id } }), config.loupe {
            focusedDesktop = desktop.id
        }
        rebuild()
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let bays = config.presentation == "bays"
        // Dessin en unités de maquette : les cadres calculés sont ramenés par le facteur du plan.
        let s = plan.scale
        NSGraphicsContext.saveGraphicsState()
        let transform = NSAffineTransform(); transform.scale(by: s); transform.concat()
        defer { NSGraphicsContext.restoreGraphicsState() }
        func u(_ r: CGRect) -> CGRect { CGRect(x: r.minX / s, y: r.minY / s, width: r.width / s, height: r.height / s) }
        let bounds = u(self.bounds), dirtyRect = u(dirtyRect)
        // Voile sombre léger sur le fond d’écran flouté : textes lisibles, fond reconnaissable.
        OverviewWallpaper.veil.setFill(); bounds.fill()
        for (index, region) in plan.displays.enumerated() {
            let r = u(region.frame)
            let label = CGPoint(x: bays ? r.minX + 2 : r.minX + 12, y: r.minY)
            NSImage(systemSymbolName: "display", accessibilityDescription: nil)?.draw(in: CGRect(x: label.x, y: label.y + 3, width: 14, height: 11), from: .zero, operation: .sourceOver, fraction: 0.7, respectFlipped: true, hints: nil)
            text(region.display.name, in: CGRect(x: label.x + 21, y: label.y, width: r.width - 40, height: 16), size: 11, weight: .semibold, color: palette(0.76, 0.85, 0.89))
            guard index + 1 < plan.displays.count else { continue }
            let path = NSBezierPath()
            // Traits obliques de la maquette : décalage fixe, pour ne jamais entrer dans les titres.
            if bays {
                let y = r.maxY + 10.5
                path.move(to: CGPoint(x: 25, y: y + 5)); path.line(to: CGPoint(x: bounds.width - 28, y: y - 5))
                palette(0.73, 0.82, 0.74, 0.33).setStroke()
            } else {
                // Pente de la maquette (26 sur 704), limitée à la marge des bureaux pour ne pas toucher les titres.
                let gap = OverviewLayout.screenGap(forHeight: bounds.height)
                let x = r.maxX + gap / 2, lean = min(26 * (r.maxY - 35) / 704, gap / 2 + 12)
                path.move(to: CGPoint(x: x + lean, y: 42)); path.line(to: CGPoint(x: x - lean, y: r.maxY + 7))
                palette(0.64, 0.78, 0.84, 0.37).setStroke()
            }
            path.lineWidth = 1; path.stroke()
        }
        // Bureaux sans fond : seul leur nom, en puce rectangulaire arrondie. Point vert = bureau actif,
        // puce bleue = bureau agrandi par la loupe.
        let active = drag.flatMap { $0.active ? $0 : nil }
        var draggedDesktop: OverviewDesktopID?, draggedStage: StageScope?, draggedWindow: WindowID?, droppedWindowStage: StageScope?
        switch active?.subject {
        case .desktop(let id): draggedDesktop = id
        case .stage(let scope, _): draggedStage = scope
        case .window(let entry):
            draggedWindow = entry.id
            droppedWindowStage = active.flatMap { windowTarget(for: entry, point: $0.point) }
        case nil: break
        }
        for item in plan.desktops {
            let focused = config.loupe && magnifiedID != nil && item.desktop.entries.contains { $0.id == magnifiedID }
            drawChip(item.desktop, in: u(chipFrame(for: item)), focused: focused, alpha: item.desktop.id == draggedDesktop ? 0.35 : 1)
        }
        // Stage de la fenêtre sélectionnée : ses puces passent en bleu pour montrer ses voisines.
        let chosenStage = plan.cards.first { $0.entry.id == selectedID }?.entry.scope
        for item in plan.cards where u(item.frame).insetBy(dx: -8, dy: -8).intersects(dirtyRect) {
            let target = droppedWindowStage != nil && item.entry.scope == droppedWindowStage
            let faded = (draggedStage != nil && item.entry.scope == draggedStage) || item.entry.id == draggedWindow
            if faded { NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current?.cgContext.setAlpha(0.45) }
            drawCard(item, in: u(item.frame), sameStage: target || (chosenStage != nil && item.entry.scope == chosenStage))
            if faded { NSGraphicsContext.restoreGraphicsState() }
            if target { drawDropRing(u(item.frame)) }
        }
        if let active {
            let offset = CGPoint(x: active.point.x - active.start.x, y: active.point.y - active.start.y)
            switch active.subject {
            case .desktop(let source):
                if let slot = dropSlot(source: source, point: active.point) { drawInsertion(u(slot.line)) }
                if let item = plan.desktops.first(where: { $0.desktop.id == source }) {
                    // La puce suit le pointeur, au-dessus des cartes, décalée comme au moment de la prise.
                    drawChip(item.desktop, in: u(chipFrame(for: item).offsetBy(dx: offset.x, dy: offset.y)), focused: true, alpha: 1)
                }
            case .stage(let scope, let name):
                if let slot = stageSlot(source: scope, point: active.point) { drawInsertion(u(slot.line)) }
                drawStageGhost(name, at: u(CGRect(origin: active.point, size: .zero)).origin)
            case .window(let entry):
                if let card = plan.cards.first(where: { $0.entry.id == entry.id }) {
                    drawWindowGhost(entry, card: u(card.frame), at: u(CGRect(origin: active.point, size: .zero)).origin)
                }
            }
        }
        if let notice {
            let visible = u(visibleRect)
            text(notice, in: CGRect(x: visible.minX + 35, y: visible.midY - 20, width: visible.width - 70, height: 30), size: 14)
        }
    }

    /// Trait d’insertion fin et translucide : dégradé qui s’efface aux deux bouts, léger halo.
    private func drawInsertion(_ line: CGRect) {
        let vertical = line.height == 0
        let length = vertical ? line.width : line.height
        let inset = min(18, length * 0.08)
        let bar = vertical
            ? CGRect(x: line.minX + inset, y: line.minY - 0.5, width: max(0, line.width - 2 * inset), height: 1)
            : CGRect(x: line.minX - 0.5, y: line.minY + inset, width: 1, height: max(0, line.height - 2 * inset))
        let blue = palette(0.48, 0.80, 0.97)
        NSGraphicsContext.saveGraphicsState()
        let glow = NSShadow()
        glow.shadowColor = blue.withAlphaComponent(0.3); glow.shadowBlurRadius = 5; glow.shadowOffset = .zero
        glow.set()
        let gradient = NSGradient(colors: [blue.withAlphaComponent(0), blue.withAlphaComponent(0.5), palette(0.85, 0.95, 1, 0.65),
                                           blue.withAlphaComponent(0.5), blue.withAlphaComponent(0)],
                                  atLocations: [0, 0.22, 0.5, 0.78, 1], colorSpace: .sRGB)
        gradient?.draw(in: NSBezierPath(rect: bar), angle: vertical ? 0 : 90)
        NSGraphicsContext.restoreGraphicsState()
    }

    /// Contour des cartes de la stage visée par une fenêtre glissée.
    private func drawDropRing(_ frame: CGRect) {
        let image = CGRect(x: frame.minX, y: frame.minY, width: frame.width, height: max(1, frame.height - OverviewLayout.caption))
        NSGraphicsContext.saveGraphicsState()
        let glow = NSShadow(); glow.shadowColor = palette(0.48, 0.80, 0.97, 0.6); glow.shadowBlurRadius = 8; glow.shadowOffset = .zero; glow.set()
        palette(0.48, 0.80, 0.97, 0.95).setStroke()
        let ring = NSBezierPath(roundedRect: image.insetBy(dx: -2.5, dy: -2.5), xRadius: 8, yRadius: 8)
        ring.lineWidth = 1.5; ring.stroke()
        NSGraphicsContext.restoreGraphicsState()
    }

    /// Puce de stage portée par le pointeur pendant le glisser.
    private func drawStageGhost(_ name: String, at point: CGPoint) {
        let font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        let width = ceil((name as NSString).size(withAttributes: [.font: font]).width) + 20
        let chip = CGRect(x: point.x + 8, y: point.y + 6, width: width, height: 20)
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow(); shadow.shadowColor = NSColor.black.withAlphaComponent(0.35); shadow.shadowBlurRadius = 10; shadow.shadowOffset = CGSize(width: 0, height: -3); shadow.set()
        box(chip, fill: palette(0.17, 0.36, 0.48, 0.95), stroke: palette(0.45, 0.78, 0.95, 0.9), radius: 5, line: 1)
        NSGraphicsContext.restoreGraphicsState()
        text(name, in: CGRect(x: chip.minX + 10, y: chip.minY + 3, width: width - 14, height: 15), size: 11, weight: .semibold, color: palette(0.85, 0.95, 1))
    }

    /// Aperçu réduit de la fenêtre portée par le pointeur.
    private func drawWindowGhost(_ entry: WindowSwitcherEntry, card: CGRect, at point: CGPoint) {
        let width = min(150, card.width * 0.6)
        let ratio = max(0.4, min(1.2, (card.height - OverviewLayout.caption) / max(1, card.width)))
        let rect = CGRect(x: point.x + 10, y: point.y + 8, width: width, height: width * ratio)
        let path = NSBezierPath(roundedRect: rect, xRadius: 5, yRadius: 5)
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow(); shadow.shadowColor = NSColor.black.withAlphaComponent(0.4); shadow.shadowBlurRadius = 14; shadow.shadowOffset = CGSize(width: 0, height: -4); shadow.set()
        palette(16.0/255, 27.0/255, 36.0/255, 0.92).setFill(); path.fill()
        NSGraphicsContext.restoreGraphicsState()
        NSGraphicsContext.saveGraphicsState(); path.addClip()
        if let image = images[entry.id], image.size.width > 0, image.size.height > 0 {
            image.draw(in: rect, from: WindowSwitcherThumbnailView.sourceRect(image: image.size, target: rect.size), operation: .sourceOver,
                       fraction: 0.9, respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high])
        } else if let icon = icons[entry.id] ?? appIcons[entry.window.pid] {
            let side = min(40, rect.height * 0.6)
            icon.draw(in: CGRect(x: rect.midX - side / 2, y: rect.midY - side / 2, width: side, height: side), from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        }
        NSGraphicsContext.restoreGraphicsState()
        palette(0.48, 0.80, 0.97, 0.8).setStroke(); path.lineWidth = 1; path.stroke()
    }

    private func drawChip(_ desktop: OverviewDesktop, in chip: CGRect, focused: Bool, alpha: CGFloat) {
        let dot: CGFloat = desktop.isActive ? 12 : 0
        box(chip, fill: focused ? palette(0.18, 0.38, 0.52, 0.9 * alpha) : palette(0.08, 0.13, 0.17, 0.55 * alpha),
            stroke: focused ? palette(0.48, 0.80, 0.97, 0.9 * alpha) : palette(0.75, 0.85, 0.90, 0.22 * alpha), radius: 6, line: 1)
        if desktop.isActive {
            box(CGRect(x: chip.minX + 10, y: chip.midY - 3, width: 6, height: 6), fill: palette(0.55, 0.85, 0.66, alpha), stroke: .clear, radius: 3)
        }
        text(desktop.name, in: CGRect(x: chip.minX + 11 + dot, y: chip.minY + 4, width: chip.width - 20 - dot, height: 17), size: 13, weight: .semibold,
             color: palette(0.93, 0.97, 0.99, alpha))
    }

    /// Carte minimaliste : l’aperçu seul, coins arrondis et ombre, puis icône et titre dessous, sans fond ni cadre.
    private func drawCard(_ item: OverviewLayout.Card, in frame: CGRect, sameStage: Bool) {
        let selected = item.entry.id == selectedID
        let radius: CGFloat = 6
        let imageRect = CGRect(x: frame.minX, y: frame.minY, width: frame.width, height: max(1, frame.height - OverviewLayout.caption))
        let path = NSBezierPath(roundedRect: imageRect, xRadius: radius, yRadius: radius)
        let image = images[item.entry.id].flatMap { $0.size.width > 0 && $0.size.height > 0 ? $0 : nil }
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(selected ? 0.35 : 0.22)
        shadow.shadowOffset = CGSize(width: 0, height: -5); shadow.shadowBlurRadius = selected ? 16 : 12
        shadow.set()
        palette(16.0/255, 27.0/255, 36.0/255, image == nil ? 0.55 : 1).setFill(); path.fill()
        NSGraphicsContext.restoreGraphicsState()
        NSGraphicsContext.saveGraphicsState(); path.addClip()
        if let image {
            // Comme le sélecteur : la capture remplit l’aperçu, recadrée par le haut. Une fenêtre au format
            // extrême (plus de trois fois l’écart, ex. fenêtre écrasée au bord de l’écran) reste entière.
            let skew = (image.size.width / image.size.height) / (imageRect.width / imageRect.height)
            if skew > 1.0 / 3, skew < 3 {
                image.draw(in: imageRect, from: WindowSwitcherThumbnailView.sourceRect(image: image.size, target: imageRect.size),
                           operation: .sourceOver, fraction: 1, respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high])
            } else {
                let scale = min(imageRect.width / image.size.width, imageRect.height / image.size.height)
                let fitted = CGSize(width: image.size.width * scale, height: image.size.height * scale)
                image.draw(in: CGRect(x: imageRect.midX - fitted.width / 2, y: imageRect.midY - fitted.height / 2, width: fitted.width, height: fitted.height),
                           from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high])
            }
        } else if let icon = icons[item.entry.id] {
            let side = min(56, imageRect.width * 0.4, imageRect.height * 0.5)
            icon.draw(in: CGRect(x: imageRect.midX - side / 2, y: imageRect.midY - side / 2, width: side, height: side), from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        }
        NSGraphicsContext.restoreGraphicsState()
        if selected {
            // Couleur et épaisseur réglables (Paramètres > Vue d’ensemble).
            let width = CGFloat(config.selectionWidth)
            (NSColor(hex: config.selectionColor) ?? palette(0.40, 0.76, 0.97)).setStroke()
            let ring = NSBezierPath(roundedRect: imageRect.insetBy(dx: -width / 2 - 1, dy: -width / 2 - 1),
                                    xRadius: radius + width / 2 + 1, yRadius: radius + width / 2 + 1)
            ring.lineWidth = width; ring.stroke()
        } else if item.entry.id == hoveredID {
            palette(1, 1, 1, 0.55).setStroke()
            let ring = NSBezierPath(roundedRect: imageRect.insetBy(dx: -1.5, dy: -1.5), xRadius: radius + 1.5, yRadius: radius + 1.5)
            ring.lineWidth = 1; ring.stroke()
        }
        // Légende : icône et titre à gauche, puce de la stage à droite sur la même ligne.
        let caption = CGRect(x: frame.minX, y: imageRect.maxY + 5, width: frame.width, height: 14)
        var chipWidth: CGFloat = 0
        if !item.stageName.isEmpty {
            let font = NSFont.systemFont(ofSize: 8.5, weight: .medium)
            chipWidth = min(frame.width * 0.45, ceil((item.stageName as NSString).size(withAttributes: [.font: font]).width) + 16)
            let chip = CGRect(x: caption.maxX - chipWidth, y: caption.minY, width: chipWidth, height: 14)
            box(chip, fill: sameStage ? palette(0.17, 0.36, 0.48) : palette(0.62, 0.74, 0.80, 0.12),
                stroke: sameStage ? palette(0.45, 0.78, 0.95, 0.8) : palette(0.62, 0.74, 0.80, 0.25), radius: 3.5, line: 0.8)
            text(item.stageName, in: CGRect(x: chip.minX + 7, y: chip.minY + 1.5, width: chip.width - 11, height: 12), size: 8.5, weight: .medium,
                 color: sameStage ? palette(0.78, 0.92, 1) : palette(0.70, 0.80, 0.86))
        }
        appIcons[item.entry.window.pid]?.draw(in: CGRect(x: caption.minX, y: caption.minY, width: 13, height: 13), from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        text(item.entry.window.appName + " · " + (item.entry.window.title.isEmpty ? "Fenêtre" : item.entry.window.title),
             in: CGRect(x: caption.minX + 18, y: caption.minY, width: max(0, caption.width - 18 - chipWidth - 6), height: 13), size: 9,
             color: selected ? palette(0.75, 0.90, 0.99) : palette(0.78, 0.86, 0.90))
    }

    private func palette(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> NSColor {
        NSColor(srgbRed: r, green: g, blue: b, alpha: a)
    }

    private func text(_ string: String, in rect: CGRect, size: CGFloat, weight: NSFont.Weight = .regular, color: NSColor = .labelColor, alignment: NSTextAlignment = .left, kern: CGFloat = 0) {
        let paragraph = NSMutableParagraphStyle(); paragraph.lineBreakMode = .byTruncatingTail; paragraph.alignment = alignment
        (string as NSString).draw(in: CGRect(x: rect.minX, y: rect.minY, width: max(0, rect.width), height: min(22, rect.height)), withAttributes: [.font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color, .paragraphStyle: paragraph, .kern: kern])
    }
    private func box(_ rect: CGRect, fill: NSColor, stroke: NSColor, radius: CGFloat, line: CGFloat = 1) {
        let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
        fill.setFill(); path.fill(); stroke.setStroke(); path.lineWidth = line; path.stroke()
    }
}
