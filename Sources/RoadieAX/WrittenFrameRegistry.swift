import CoreGraphics
import Foundation
import RoadieCore

/// Dernière écriture AX de Roadie sur une fenêtre (SPEC-017 R6, A2, A4, A13, A14).
public struct WrittenFrame: Sendable, Equatable {
    public var requested: CGRect
    public var readBack: CGRect?
    /// Frame acceptée pour la génération courante (refus confirmé, réponse de l'application).
    public var accepted: CGRect?
    public var writtenAt: Date
    /// Génération de placement globale et monotone de la dernière écriture (A13).
    public var generation: UInt64
    /// Écritures faites dans `generation` (budget A13).
    public var writesInGeneration: Int
    /// Seconde observation réelle d'un refus de taille (A14) ; nil tant qu'il est en attente.
    public var refusalConfirmedAt: Date?
    /// Codes AX bruts des phases atteintes par cette tentative, sans lecture supplémentaire.
    public var axResultCodes: [String: Int32]?
    /// Booléen AXFullScreen frais avant l'écriture ; nil si cet attribut était illisible ou absent.
    public var nativeFullscreenReading: Bool?

    /// Refus en attente : la frame relue s'écarte de la frame demandée.
    public var hasRefusal: Bool {
        readBack.map { !WrittenFrameRegistry.matches($0, requested) } ?? false
    }
}

/// Mémoire des frames écrites, partagée par le processus et placée au point unique d'écriture
/// AX. Elle distingue l'écho de nos placements, la réponse de l'application et le changement
/// externe. Verrou interne : lue depuis le callback AX et depuis la passe de disposition.
public final class WrittenFrameRegistry: @unchecked Sendable {
    public static let shared = WrittenFrameRegistry()

    private static let echoWindow: TimeInterval = LayoutTolerance.echoWindow
    private static let historyWindow: TimeInterval = 1.5
    private static let historyLimit = 32

    public enum Classification: Equatable { case echo, appResponse, external }

    private let lock = NSLock()
    private var entries: [UInt32: WrittenFrame] = [:]
    private struct RecentFrame {
        var frame: CGRect
        var recordedAt: Date
        var generation: UInt64
    }
    private var history: [UInt32: [RecentFrame]] = [:]

    public init() {}

    /// Enregistre une écriture. Une nouvelle génération repart à une écriture et efface la frame
    /// acceptée ; la même génération incrémente le compteur. Chaque écriture attend sa propre
    /// confirmation de refus. L'historique reste séparé du budget. O(1), borne de 32 cadres.
    public func record(
        windowID: UInt32, requested: CGRect, readBack: CGRect?, generation: UInt64, at date: Date,
        axResultCodes: [String: Int32]? = nil, nativeFullscreenReading: Bool? = nil
    ) {
        lock.withLock {
            var entry = WrittenFrame(
                requested: requested, readBack: readBack, accepted: nil, writtenAt: date,
                generation: generation, writesInGeneration: 1, refusalConfirmedAt: nil,
                axResultCodes: axResultCodes, nativeFullscreenReading: nativeFullscreenReading
            )
            if let previous = entries[windowID], previous.generation == generation {
                entry.accepted = previous.accepted
                entry.writesInGeneration = previous.writesInGeneration + 1
            }
            entries[windowID] = entry
            remember(windowID: windowID, frames: [requested, readBack].compactMap { $0 }, generation: generation, at: date)
        }
    }

    /// Accepte une frame pour la génération courante de la fenêtre. Sans écriture connue : sans effet. O(1).
    public func accept(windowID: UInt32, frame: CGRect, at date: Date = Date()) {
        lock.withLock {
            guard let entry = entries[windowID] else { return }
            entries[windowID]?.accepted = frame
            remember(windowID: windowID, frames: [frame], generation: entry.generation, at: date)
        }
    }

    public func entry(for windowID: UInt32) -> WrittenFrame? {
        lock.withLock { entries[windowID] }
    }

    /// Budget A13 épuisé : `writeBudgetPerGeneration` tentatives déjà inscrites pour cette fenêtre
    /// dans `generation`. Contrôlé au point commun d'écriture (T213). O(1).
    public func isOverBudget(windowID: UInt32, generation: UInt64) -> Bool {
        guard generation != PlacementGeneration.outsideBudget,
              let entry = entry(for: windowID), entry.generation == generation
        else { return false }
        return entry.writesInGeneration >= LayoutTolerance.writeBudgetPerGeneration
    }

    public func forget(windowID: UInt32) {
        lock.withLock {
            entries[windowID] = nil
            history[windowID] = nil
        }
    }

    /// Seconde observation réelle (notification AX ou relecture AX fraîche, jamais le snapshot
    /// republié) d'une fenêtre dont le refus est en attente (A14). Si elle reproduit la frame
    /// relue, le refus est confirmé ; si elle rejoint la frame demandée, le refus disparaît.
    /// Fournir `generation` si la lecture a démarré avant un possible changement d'écriture.
    /// Les notifications AX passent par `consumeEcho`, qui écarte les anciens échos ambigus.
    /// Retourne vrai si le refus vient d'être confirmé. O(1).
    @discardableResult
    public func confirmRefusal(windowID: UInt32, observed: CGRect, at date: Date, generation: UInt64? = nil) -> Bool {
        lock.withLock {
            guard generation == nil || entries[windowID]?.generation == generation else { return false }
            return confirmRefusalLocked(windowID: windowID, observed: observed, at: date)
        }
    }

    private func confirmRefusalLocked(windowID: UInt32, observed: CGRect, at date: Date) -> Bool {
        guard let entry = entries[windowID], entry.hasRefusal, entry.refusalConfirmedAt == nil,
              let readBack = entry.readBack, date >= entry.writtenAt
        else { return false }
        if Self.matches(observed, entry.requested) {
            entries[windowID]?.readBack = observed
            return false
        }
        guard Self.matches(observed, readBack) else { return false }
        entries[windowID]?.refusalConfirmedAt = date
        return true
    }

    /// Fenêtres dont le refus écrit attend sa seconde observation, triées. O(n log n).
    public func pendingRefusals() -> [UInt32] {
        lock.withLock {
            entries.filter { $0.value.hasRefusal && $0.value.refusalConfirmedAt == nil }.keys.sorted()
        }
    }

    /// Classe une frame observée (A4, étapes 2 à 4 ; la session de geste est tenue ailleurs) :
    /// - écho : dernière écriture (compatibilité), ou cadre historique de moins de 1,5 s ;
    /// - réponse de l'application : différente, moins de `echoWindow` après l'écriture ;
    /// - changement externe : sinon, ou sans écriture connue. O(1).
    public func classify(windowID: UInt32, observed: CGRect, now: Date) -> Classification {
        lock.withLock {
            pruneHistory(windowID: windowID, now: now)
            return classifyLocked(windowID: windowID, observed: observed, now: now)
        }
    }

    /// Absorbe un écho AX et confirme seulement une relecture attribuable à l'écriture courante.
    /// Le même verrou protège classement et confirmation contre une écriture concurrente.
    /// Un cadre ambigu entre générations attend une vraie relecture AX via `confirmRefusal`.
    /// O(1), au plus 32 cadres parcourus. Ne pas appeler pendant un appui souris.
    @discardableResult
    public func consumeEcho(windowID: UInt32, observed: CGRect, now: Date) -> Bool {
        lock.withLock {
            pruneHistory(windowID: windowID, now: now)
            guard classifyLocked(windowID: windowID, observed: observed, now: now) == .echo else { return false }
            if let entry = entries[windowID],
               !(history[windowID] ?? []).contains(where: {
                   $0.generation != entry.generation && Self.matches($0.frame, observed)
               }) {
                _ = confirmRefusalLocked(windowID: windowID, observed: observed, at: now)
            }
            return true
        }
    }

    private func classifyLocked(windowID: UInt32, observed: CGRect, now: Date) -> Classification {
        guard let entry = entries[windowID] else { return .external }
        let known = [entry.requested, entry.readBack, entry.accepted].compactMap { $0 }
        if known.contains(where: { Self.matches($0, observed) })
            || (history[windowID] ?? []).contains(where: { Self.matches($0.frame, observed) }) { return .echo }
        // SPEC-062 : écriture sans relecture (délai AX dépassé −25204, fenêtre illisible) : l’application
        // n’a pas répondu, la frame observée n’est pas sa réponse. Écart à reprendre, pas à accepter.
        guard entry.readBack != nil else { return .external }
        return now.timeIntervalSince(entry.writtenAt) < Self.echoWindow ? .appResponse : .external
    }

    /// Appelées sous verrou. Les observations d'échos ne renouvellent jamais leur échéance.
    private func pruneHistory(windowID: UInt32, now: Date) {
        guard var recent = history[windowID] else { return }
        recent.removeAll {
            let age = now.timeIntervalSince($0.recordedAt)
            return age < 0 || age >= Self.historyWindow
        }
        history[windowID] = recent.isEmpty ? nil : recent
    }

    private func remember(windowID: UInt32, frames: [CGRect], generation: UInt64, at date: Date) {
        pruneHistory(windowID: windowID, now: date)
        var recent = history[windowID] ?? []
        for frame in frames {
            recent.append(RecentFrame(frame: frame, recordedAt: date, generation: generation))
        }
        if recent.count > Self.historyLimit { recent.removeFirst(recent.count - Self.historyLimit) }
        history[windowID] = recent
    }

    /// Égalité de deux frames à `LayoutTolerance.frameMatch` près sur chaque composante.
    static func matches(_ lhs: CGRect, _ rhs: CGRect) -> Bool {
        let tolerance = LayoutTolerance.frameMatch
        return abs(lhs.minX - rhs.minX) <= tolerance
            && abs(lhs.minY - rhs.minY) <= tolerance
            && abs(lhs.width - rhs.width) <= tolerance
            && abs(lhs.height - rhs.height) <= tolerance
    }
}

/// Génération de placement globale et monotone (A13). Une génération s'ouvre à chaque intention
/// externe (événement, commande, bascule, geste) ; une correction interne garde la génération en cours.
public final class PlacementGeneration: @unchecked Sendable {
    public static let shared = PlacementGeneration()
    /// Génération des écritures hors budget (T222, A3) : réparation des modes sans arbre
    /// (`bsp`, `masterStack` : recalage, voisines, tailles minimales, isolement), qui n'ont pas la
    /// garantie d'une passe. Jamais rendue par `next()` ; inscrite au registre comme une autre.
    public static let outsideBudget = UInt64.max
    private let lock = NSLock()
    private var value: UInt64 = 0

    public init() {}

    /// Ouvre une nouvelle génération et la renvoie. O(1).
    @discardableResult
    public func next() -> UInt64 { lock.withLock { value &+= 1; return value } }

    /// Génération en cours (0 si aucune n'a été ouverte). O(1).
    public var current: UInt64 { lock.withLock { value } }
}
