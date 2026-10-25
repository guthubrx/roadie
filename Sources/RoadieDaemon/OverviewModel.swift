import Foundation
import RoadieCore
import RoadieAX

struct OverviewDesktopID: Hashable {
    let displayID: DisplayID
    let desktopID: DesktopID
}

struct OverviewStage {
    let scope: StageScope
    let name: String
    var entries: [WindowSwitcherEntry]
    let isActive: Bool
}

struct OverviewDesktop {
    let id: OverviewDesktopID
    let name: String
    let isActive: Bool
    var stages: [OverviewStage]
    var entries: [WindowSwitcherEntry] { stages.flatMap(\.entries) }
}

struct OverviewDisplay {
    let id: DisplayID
    let name: String
    var desktops: [OverviewDesktop]
}

/// Projection sans AX ni mutation. O(w+s+b log b+t log t), identités indexées avant parcours.
struct OverviewModel {
    var displays: [OverviewDisplay]
    var entries: [WindowSwitcherEntry] { displays.flatMap { $0.desktops.flatMap(\.entries) } }

    init(entries: [WindowSwitcherEntry], displays: [DisplaySnapshot], state: PersistentStageState) {
        let fallback = displays.first?.id ?? DisplayID(rawValue: "unknown")
        let activeByDisplay = Dictionary(state.desktopSelections.map { ($0.displayID, $0.currentDesktopID) }, uniquingKeysWith: { first, _ in first })
        let labels = Dictionary(state.desktopLabels.map {
            (OverviewDesktopID(displayID: $0.displayID, desktopID: $0.desktopID), $0.label)
        }, uniquingKeysWith: { first, _ in first })
        var persistent: [OverviewDesktopID: PersistentStageScope] = [:]
        var storedStages: [StageScope: PersistentStage] = [:]
        var bureauIDsByDisplay: [DisplayID: Set<DesktopID>] = [:]
        for (id, _) in labels { bureauIDsByDisplay[id.displayID, default: []].insert(id.desktopID) }
        for scope in state.scopes {
            let id = OverviewDesktopID(displayID: scope.displayID, desktopID: scope.desktopID)
            guard persistent[id] == nil else { continue }
            persistent[id] = scope
            if scope.desktopID == (activeByDisplay[scope.displayID] ?? DesktopID(rawValue: 1)) || labels[id] != nil {
                bureauIDsByDisplay[scope.displayID, default: []].insert(scope.desktopID)
            }
            for stage in scope.stages {
                let key = StageScope(displayID: scope.displayID, desktopID: scope.desktopID, stageID: stage.id)
                if storedStages[key] == nil { storedStages[key] = stage }
            }
        }
        var grouped: [StageScope: [WindowSwitcherEntry]] = [:]
        var scopesByDesktop: [OverviewDesktopID: [StageScope]] = [:]
        var displayIDs = displays.map(\.id)
        var seenDisplays = Set(displayIDs)
        var names = Dictionary(displays.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        for entry in entries {
            let scope = entry.scope ?? StageScope(displayID: fallback, desktopID: DesktopID(rawValue: 1), stageID: StageID(rawValue: "unassigned"))
            let id = OverviewDesktopID(displayID: scope.displayID, desktopID: scope.desktopID)
            if grouped[scope] == nil { scopesByDesktop[id, default: []].append(scope) }
            grouped[scope, default: []].append(entry)
            bureauIDsByDisplay[scope.displayID, default: []].insert(scope.desktopID)
            if seenDisplays.insert(scope.displayID).inserted { displayIDs.append(scope.displayID) }
            if names[scope.displayID] == nil { names[scope.displayID] = entry.displayName }
        }
        var result: [OverviewDisplay] = []
        for displayID in displayIDs {
            let activeID = activeByDisplay[displayID] ?? DesktopID(rawValue: 1)
            var bureauIDs = bureauIDsByDisplay[displayID] ?? []
            bureauIDs.insert(activeID)
            var bureaux: [OverviewDesktop] = []
            for desktopID in bureauIDs.sorted() {
                let id = OverviewDesktopID(displayID: displayID, desktopID: desktopID)
                let stored = persistent[id]
                let active = activeID == desktopID
                var stageIDs = stored?.stages.filter {
                    StagePresentationOrder.isNamed($0) || grouped[StageScope(displayID: displayID, desktopID: desktopID, stageID: $0.id)] != nil
                }.map(\.id) ?? []
                var seenStages = Set(stageIDs)
                for scope in (scopesByDesktop[id] ?? []).sorted(by: { $0.stageID.rawValue < $1.stageID.rawValue }) {
                    if seenStages.insert(scope.stageID).inserted { stageIDs.append(scope.stageID) }
                }
                let stages = stageIDs.enumerated().map { index, stageID in
                    let scope = StageScope(displayID: displayID, desktopID: desktopID, stageID: stageID)
                    return OverviewStage(scope: scope,
                        name: storedStages[scope].map { StagePresentationOrder.name($0, position: index + 1) } ?? grouped[scope]?.first?.stageName ?? "Stage \(index + 1)",
                        entries: grouped[scope] ?? [], isActive: active && stored?.activeStageID == stageID)
                }
                bureaux.append(OverviewDesktop(id: id,
                    name: "Bureau \(desktopID.rawValue)" + (labels[id].map { " · \($0)" } ?? ""), isActive: active, stages: stages))
            }
            result.append(OverviewDisplay(id: displayID, name: names[displayID] ?? displayID.rawValue, desktops: bureaux))
        }
        self.displays = result
    }
}

struct OverviewLayout {
    struct Display { let display: OverviewDisplay; let frame: CGRect }
    struct Desktop { let desktop: OverviewDesktop; let frame: CGRect }
    /// `stageName` alimente la puce de la légende : les stages n’ont plus de zone propre.
    struct Card { let entry: WindowSwitcherEntry; let stageName: String; let frame: CGRect }
    var displays: [Display] = []
    var desktops: [Desktop] = []
    var cards: [Card] = []
    var size: CGSize = .zero
    /// Facteur appliqué à la maquette 1440 : voir `scale(forWidth:)`.
    var scale: CGFloat = 1
    /// Puissance 0,7 du rapport de largeur, entre 1 et 2 : un 4K de 3840 points reçoit 2.
    static func scale(forWidth width: CGFloat) -> CGFloat { min(2, max(1, pow(width / 1440, 0.7))) }
    /// Écart entre écrans en Archipel, élargi avec la hauteur pour conserver la pente des traits.
    static func screenGap(forHeight height: CGFloat) -> CGFloat { 29 * max(1, height / 773) }

    // Mesures de la maquette approuvée, en unités de maquette.
    static let caption: CGFloat = 22, cardGap: CGFloat = 10
    /// Format unique des aperçus, comme dans le sélecteur : la capture y est recadrée par le haut.
    static let cardRatio: CGFloat = 1.6
    /// Marges d’un bureau : côtés, haut (Archipel / Baies), titre, bas.
    static let side: CGFloat = 15, head: CGFloat = 36, bottom: CGFloat = 14
    static func top(bays: Bool) -> CGFloat { bays ? 6 : 15 }

    /// Hauteur d’une carte de largeur `width`, légende comprise.
    static func cardHeight(_ width: CGFloat) -> CGFloat { width / cardRatio + caption }

    /// Colonnes de cartes de largeur `card` dans `width`. O(1).
    static func columns(card: CGFloat, in width: CGFloat) -> Int { max(1, Int((width + cardGap) / (card + cardGap))) }

    /// Hauteur d’un bureau de `count` fenêtres sur `columns` colonnes. O(1).
    static func desktopHeight(count: Int, columns: Int, card: CGFloat, bays: Bool) -> CGFloat {
        let rows = CGFloat((count + columns - 1) / max(1, columns))
        return top(bays: bays) + head + bottom + max(0, rows * (cardHeight(card) + cardGap) - cardGap)
    }

    /// Plan d’un écran pour une largeur de carte donnée : rectangles des bureaux (relatifs à l’origine
    /// de l’écran), colonnes et largeur de carte de chacun, hauteur totale. O(b²) en Baies, b bureaux.
    private struct ScreenPlan { var frames: [CGRect] = []; var columns: [Int] = []; var cards: [CGFloat] = []; var height: CGFloat = 0 }

    /// Archipel : bureaux empilés dans la colonne de l’écran.
    private static func stacked(_ display: OverviewDisplay, width: CGFloat, card: CGFloat, focus: OverviewDesktopID?, factor: CGFloat) -> ScreenPlan {
        var plan = ScreenPlan(), y: CGFloat = 0
        for desktop in display.desktops {
            let w = desktop.id == focus ? card * factor : card
            let columns = columns(card: min(w, width - 2 * side), in: width - 2 * side)
            let height = desktopHeight(count: desktop.entries.count, columns: columns, card: min(w, width - 2 * side), bays: false)
            plan.frames.append(CGRect(x: 0, y: y, width: width, height: height))
            plan.columns.append(columns); plan.cards.append(min(w, width - 2 * side))
            y += height + 15
        }
        plan.height = max(0, y - 15)
        return plan
    }

    /// Baies : bureaux côte à côte. Les colonnes vont au bureau le plus haut tant que la largeur le permet.
    private static func sideBySide(_ display: OverviewDisplay, width: CGFloat, card: CGFloat, focus: OverviewDesktopID?, factor: CGFloat) -> ScreenPlan? {
        let gap: CGFloat = 17
        let cards = display.desktops.map { $0.id == focus ? card * factor : card }
        var columns = Array(repeating: 1, count: cards.count)
        func used() -> CGFloat { zip(columns, cards).reduce(0) { $0 + CGFloat($1.0) * ($1.1 + cardGap) - cardGap + 2 * side } + gap * CGFloat(max(0, cards.count - 1)) }
        guard used() <= width else { return nil }
        while true {
            let heights = display.desktops.indices.map { desktopHeight(count: display.desktops[$0].entries.count, columns: columns[$0], card: cards[$0], bays: true) }
            guard let tallest = heights.indices.max(by: { heights[$0] < heights[$1] }),
                  columns[tallest] < display.desktops[tallest].entries.count else { break }
            columns[tallest] += 1
            if used() > width { columns[tallest] -= 1; break }
        }
        // Largeur restante partagée entre les bureaux : les îles couvrent toute la bande.
        let extra = (width - used()) / CGFloat(max(1, cards.count))
        var plan = ScreenPlan(), x: CGFloat = 0
        for index in cards.indices {
            let w = CGFloat(columns[index]) * (cards[index] + cardGap) - cardGap + 2 * side + extra
            let height = desktopHeight(count: display.desktops[index].entries.count, columns: columns[index], card: cards[index], bays: true)
            plan.frames.append(CGRect(x: x, y: 0, width: w, height: height))
            plan.columns.append(columns[index]); plan.cards.append(cards[index])
            plan.height = max(plan.height, height)
            x += w + gap
        }
        plan.frames = plan.frames.map { CGRect(x: $0.minX, y: 0, width: $0.width, height: plan.height) }
        return plan
    }

    /// Une grille par bureau, même taille de carte partout, fenêtres dans l’ordre des stages.
    /// Dichotomie sur la largeur de carte : la plus grande qui fait tenir tous les écrans. O((w+b²) log W).
    /// Loupe : le bureau de la fenêtre survolée affiche des cartes agrandies du pourcentage choisi.
    private static func compose(_ model: OverviewModel, size: CGSize, config: OverviewConfig, window: WindowID?) -> OverviewLayout {
        var result = OverviewLayout()
        let count = model.displays.count
        let bays = config.presentation == "bays"
        let factor = config.loupe && window != nil ? CGFloat(config.magnification / 100) : 1
        let focus = factor > 1 ? model.displays.flatMap(\.desktops).first { $0.entries.contains { $0.id == window } }?.id : nil
        let screenGap = screenGap(forHeight: size.height)
        let usable = size.width - 56 - screenGap * CGFloat(max(0, count - 1))
        // `widths` garde les largeurs du dernier essai réussi, donc de la taille retenue.
        var widths: [CGFloat] = []
        /// Archipel : largeur minimale d’un écran pour que ses bureaux tiennent en hauteur. O(n) essais.
        func narrowest(_ display: OverviewDisplay, card: CGFloat) -> CGFloat? {
            let widest = display.desktops.map { $0.id == focus ? card * factor : card }.max() ?? card
            let most = max(1, display.desktops.map(\.entries.count).max() ?? 1)
            for columns in 1...most {
                let width = CGFloat(columns) * (widest + cardGap) - cardGap + 2 * side
                if width > usable { return nil }
                if stacked(display, width: width, card: card, focus: focus, factor: factor).height <= size.height - 72 { return width }
            }
            return nil
        }
        func plans(_ card: CGFloat) -> [ScreenPlan]? {
            if bays {
                var plans: [ScreenPlan] = []
                for display in model.displays {
                    guard let plan = sideBySide(display, width: size.width - 56, card: card, focus: focus, factor: factor) else { return nil }
                    plans.append(plan)
                }
                let total = plans.reduce(0) { $0 + 28 + $1.height } + 21 * CGFloat(max(0, count - 1))
                return total <= size.height - 34 ? plans : nil
            }
            // Largeur selon le besoin de chaque écran, surplus partagé au prorata : un écran peu rempli
            // ne réserve plus une colonne vide.
            var needs: [CGFloat] = []
            for display in model.displays {
                guard let need = narrowest(display, card: card) else { return nil }
                needs.append(need)
            }
            let total = needs.reduce(0, +)
            guard total <= usable else { return nil }
            widths = needs.map { $0 * usable / max(1, total) }
            return zip(model.displays, widths).map { stacked($0, width: $1, card: card, focus: focus, factor: factor) }
        }
        // Borne basse très petite : tout doit tenir sur une seule page, sans défilement.
        var low: CGFloat = 8, high: CGFloat = 640
        var chosen = plans(low)
        if let top = plans(high) { chosen = top; low = high }
        else if chosen != nil {
            for _ in 0..<18 {
                let middle = (low + high) / 2
                if let candidate = plans(middle) { chosen = candidate; low = middle } else { high = middle }
            }
        }
        // Cas extrême (bureaux trop nombreux pour leurs seuls titres) : la composition est coupée, jamais défilée.
        var screens = chosen ?? []
        if chosen == nil {
            widths = Array(repeating: usable / CGFloat(max(1, count)), count: count)
            screens = bays ? model.displays.map { sideBySide($0, width: size.width - 56, card: low, focus: nil, factor: 1) ?? ScreenPlan() }
                           : zip(model.displays, widths).map { stacked($0, width: $1, card: low, focus: focus, factor: factor) }
        }
        var cursor = CGPoint(x: 28, y: 14)
        for (index, display) in model.displays.enumerated() {
            let plan = screens[index]
            let origin: CGPoint
            if bays {
                result.displays.append(Display(display: display, frame: CGRect(x: 28, y: cursor.y, width: size.width - 56, height: 28 + plan.height)))
                origin = CGPoint(x: 28, y: cursor.y + 28)
                cursor.y += 28 + plan.height + 21
            } else {
                result.displays.append(Display(display: display, frame: CGRect(x: cursor.x, y: 15, width: widths[index], height: max(size.height - 39, 33 + plan.height))))
                origin = CGPoint(x: cursor.x, y: 48)
                cursor.x += widths[index] + screenGap
            }
            for (slot, desktop) in display.desktops.enumerated() where slot < plan.frames.count {
                let rect = plan.frames[slot].offsetBy(dx: origin.x, dy: origin.y)
                result.desktops.append(Desktop(desktop: desktop, frame: rect))
                let card = plan.cards[slot], columns = plan.columns[slot], height = cardHeight(card)
                let left = rect.minX + side, top = rect.minY + top(bays: bays) + head
                let names = Dictionary(desktop.stages.map { ($0.scope, $0.name) }, uniquingKeysWith: { first, _ in first })
                for (index, entry) in desktop.entries.enumerated() {
                    let frame = CGRect(x: left + CGFloat(index % columns) * (card + cardGap), y: top + CGFloat(index / columns) * (height + cardGap), width: card, height: height)
                    result.cards.append(Card(entry: entry, stageName: entry.scope.flatMap { names[$0] } ?? "", frame: frame))
                }
            }
        }
        // Centrage vertical (SPEC-071) : le vide sous le contenu se partage entre le haut et le bas.
        // En Archipel, la colonne d’un écran garde son bas pour ne pas déplacer les traits de séparation.
        let contentTop = result.displays.map(\.frame.minY).min() ?? 0
        let contentBottom = max(result.desktops.map(\.frame.maxY).max() ?? 0, result.cards.map(\.frame.maxY).max() ?? 0)
        let dy = max(0, (size.height - contentBottom - contentTop) / 2)
        if dy > 0 {
            result.displays = result.displays.map { item in
                let frame = item.frame
                return Display(display: item.display, frame: bays ? frame.offsetBy(dx: 0, dy: dy)
                               : CGRect(x: frame.minX, y: frame.minY + dy, width: frame.width, height: max(0, frame.height - dy)))
            }
            result.desktops = result.desktops.map { Desktop(desktop: $0.desktop, frame: $0.frame.offsetBy(dx: 0, dy: dy)) }
            result.cards = result.cards.map { Card(entry: $0.entry, stageName: $0.stageName, frame: $0.frame.offsetBy(dx: 0, dy: dy)) }
        }
        result.size = size
        return result
    }

    /// Composition sur une seule page, à la taille de l’écran : jamais de défilement. O((w+b²) log W).
    static func make(model: OverviewModel, viewport: CGSize, config: OverviewConfig, window: WindowID? = nil) -> OverviewLayout {
        guard !model.displays.isEmpty else { var empty = OverviewLayout(); empty.size = viewport; return empty }
        let scale = scale(forWidth: viewport.width)
        let size = CGSize(width: viewport.width / scale, height: viewport.height / scale)
        var result = compose(model, size: size, config: config, window: window)
        func scaled(_ r: CGRect) -> CGRect { CGRect(x: r.minX * scale, y: r.minY * scale, width: r.width * scale, height: r.height * scale) }
        result.displays = result.displays.map { Display(display: $0.display, frame: scaled($0.frame)) }
        result.desktops = result.desktops.map { Desktop(desktop: $0.desktop, frame: scaled($0.frame)) }
        result.cards = result.cards.map { Card(entry: $0.entry, stageName: $0.stageName, frame: scaled($0.frame)) }
        result.size = CGSize(width: result.size.width * scale, height: result.size.height * scale)
        result.scale = scale
        return result
    }
}

struct OverviewHoverTarget: Equatable {
    let desktopID: OverviewDesktopID
    let windowID: WindowID?
}

/// Le délai est armé uniquement par un mouvement réel. Un relayout seul ne crée pas une cible.
struct OverviewHoverState {
    private var candidate: OverviewHoverTarget?
    private var consumed: OverviewHoverTarget?
    private var since: TimeInterval = 0
    mutating func moved(to id: OverviewHoverTarget?, at time: TimeInterval) -> Bool {
        guard id != candidate else { return false }
        candidate = id; since = time
        return true
    }
    func ready(at time: TimeInterval) -> OverviewHoverTarget? {
        guard time - since >= 0.1, candidate != consumed else { return nil }
        return candidate
    }
    mutating func consume() { consumed = candidate }
}
