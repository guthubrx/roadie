import CoreGraphics
import Foundation
import RoadieAX
import RoadieCore

/// Places retenues des fenêtres flottantes (session 132), dans `~/.roadies/floating-frames.json` :
/// identifiant de règle → cadre (position et taille).
struct FloatingFrameStore: Sendable {
    let path: String

    init(path: String = NSString(string: TestEnvironment.launcherFile("floating-frames.json")).expandingTildeInPath) {
        self.path = path
    }

    func load() -> [String: Rect] {
        JSONPersistence.load([String: Rect].self, from: URL(fileURLWithPath: path), default: [:])
    }

    func merge(_ changes: [String: Rect]) {
        let url = URL(fileURLWithPath: path)
        if case .corrupt = JSONPersistence.loadResult([String: Rect].self, from: url) { return }
        do {
            try JSONPersistence.mutateChecked([String: Rect].self, at: url, default: [:], label: "floating-frames") { saved in
                saved.merge(changes) { _, new in new }
            }
        } catch {
            fputs("roadie: \(error)\n", stderr)
        }
    }
}

/// Fenêtres non tuilées (session 132) : à leur apparition, une place retenue est rendue, sinon une fenêtre
/// ouverte sur le rail est décalée à sa droite ; ensuite, seule la place est retenue après un déplacement.
/// Appelé à chaque passe, bouton de la souris relâché. Au premier appel, les fenêtres déjà ouvertes sont
/// notées sans être déplacées.
final class FloatingPlacement {
    /// Écart laissé entre le rail et la fenêtre décalée.
    static let railMargin: CGFloat = 8
    /// En deçà, un écart de cadre n'est pas un déplacement de l'utilisateur.
    static let tolerance: CGFloat = 2

    struct Move: Equatable {
        let window: WindowSnapshot
        let frame: CGRect
        let reason: String
    }

    private let store: FloatingFrameStore
    /// Fenêtres suivies : dernier cadre connu et règle qui retient leur place.
    private var known: [WindowID: (frame: Rect, key: String?)] = [:]
    private var primed = false

    init(store: FloatingFrameStore = FloatingFrameStore()) {
        self.store = store
    }

    /// Fenêtres concernées : non tuilées et hors des stages, standard ou dialogue, d'une autre application que
    /// Roadie. O(n).
    static func candidates(in snapshot: DaemonSnapshot, ownPID: Int32 = ProcessInfo.processInfo.processIdentifier) -> [WindowSnapshot] {
        snapshot.windows.compactMap { entry in
            let window = entry.window
            guard entry.scope == nil, !window.isTileCandidate, window.pid != ownPID,
                  window.subrole == "AXStandardWindow" || window.subrole == "AXDialog" else { return nil }
            return window
        }
    }

    /// Règle qui retient la place de cette fenêtre : la première règle trouvée, comme pour le tuilage.
    /// O(r log r), seulement pour une fenêtre apparue.
    static func rememberKey(for window: WindowSnapshot, rules: [WindowRule]) -> String? {
        let context = WindowRuleMatchContext(role: window.role, subrole: window.subrole)
        guard let rule = WindowRuleMatcher.firstMatch(rules: rules, window: window, context: context),
              rule.action.rememberFrame == true else { return nil }
        return rule.id
    }

    /// Place d'une fenêtre qui apparaît : sa place retenue si elle est encore sur un écran, sinon à droite du rail
    /// si elle s'ouvre dessus et y tient. nil : rien à changer. O(d).
    static func placement(for frame: CGRect, displays: [CGRect], railWidth: CGFloat, avoidRail: Bool, remembered: CGRect?) -> CGRect? {
        if let remembered, displays.contains(where: { $0.contains(CGPoint(x: remembered.midX, y: remembered.minY + 1)) }) {
            return close(remembered, frame) ? nil : remembered
        }
        guard avoidRail, railWidth > 0,
              let display = displays.first(where: { $0.contains(CGPoint(x: frame.minX, y: frame.minY)) }) ?? displays.first(where: { $0.intersects(frame) }),
              frame.minX < display.minX + railWidth else { return nil }
        let x = display.minX + railWidth + railMargin
        guard x + frame.width <= display.maxX else { return nil }
        return CGRect(x: x, y: frame.minY, width: frame.width, height: frame.height)
    }

    /// Une passe : déplacements à faire pour les fenêtres apparues, places retenues mises à jour pour les autres.
    /// `key` et `railWidth` ne sont lus que pour une fenêtre apparue. O(n).
    func observe(_ windows: [WindowSnapshot], displays: [CGRect], avoidRail: Bool,
                 railWidth: () -> CGFloat, key: (WindowSnapshot) -> String?) -> [Move] {
        let live = Set(windows.map(\.id))
        known = known.filter { live.contains($0.key) }
        guard primed else {
            primed = true
            for window in windows where window.isOnScreen { known[window.id] = (window.frame, key(window)) }
            return []
        }
        var moves: [Move] = []
        var changes: [String: Rect] = [:]
        lazy var width = railWidth()
        lazy var rememberedFrames = store.load()
        for window in windows where window.isOnScreen {
            guard let previous = known[window.id] else {
                let rememberKey = key(window)
                known[window.id] = (window.frame, rememberKey)
                let remembered = rememberKey.flatMap { changes[$0] ?? rememberedFrames[$0] }?.cgRect
                if let target = Self.placement(for: window.frame.cgRect, displays: displays, railWidth: width,
                                               avoidRail: avoidRail, remembered: remembered) {
                    moves.append(Move(window: window, frame: target, reason: remembered.map { Self.close($0, target) } == true ? "remembered" : "rail"))
                }
                continue
            }
            guard !Self.close(previous.frame.cgRect, window.frame.cgRect) else { continue }
            known[window.id] = (window.frame, previous.key)
            if let rememberKey = previous.key {
                changes[rememberKey] = window.frame
            }
        }
        if !changes.isEmpty { store.merge(changes) }
        return moves
    }

    /// Cadre obtenu après un déplacement : la place suivante se compare à lui, pas au cadre d'origine.
    func applied(_ window: WindowID, frame: CGRect) {
        guard let entry = known[window] else { return }
        known[window] = (Rect(frame), entry.key)
    }

    private static func close(_ a: CGRect, _ b: CGRect) -> Bool {
        abs(a.minX - b.minX) <= tolerance && abs(a.minY - b.minY) <= tolerance
            && abs(a.width - b.width) <= tolerance && abs(a.height - b.height) <= tolerance
    }
}
