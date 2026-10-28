import Foundation
import RoadieAX
import RoadieCore

/// Déplacement d'une fenêtre vers une stage, noté à la source (SPEC-081) : sert à l'annuler et à
/// reconnaître une habitude qui mérite une règle.
struct WindowMove: Codable, Equatable, Sendable {
    let windowID: WindowID
    let bundleID: String
    let appName: String
    let from: StageScope?
    let to: StageScope
    let at: Date
    /// Envoi groupé (SPEC-091) : tous ses déplacements s'annulent ensemble.
    var batch: String?
}

/// Règle proposée : une application déplacée souvent vers la même stage.
struct RuleSuggestion: Equatable, Sendable {
    let bundleID: String
    let appName: String
    let stage: StageScope
    let stageTitle: String
    let count: Int

    /// Clé des refus : l'application et l'identité de la stage (nom réel ou place).
    let declineKey: String
}

enum RuleChoice: String, Equatable, Sendable {
    case create, later, never
}

/// Mémoire locale du lanceur, `~/.roadies/launcher-moves.json` : 200 déplacements au plus et les refus
/// de propositions (« Jamais » = `distantFuture`, « Plus tard » = jusqu'à cette date).
struct LauncherMemoryBook: Codable, Equatable, Sendable {
    static let maxMoves = 200
    static let undoWindow: TimeInterval = 10 * 60
    static let habitWindow: TimeInterval = 7 * 24 * 3600

    var moves: [WindowMove] = []
    var declined: [String: Date] = [:]

    mutating func record(_ move: WindowMove) {
        moves.append(move)
        if moves.count > Self.maxMoves { moves.removeFirst(moves.count - Self.maxMoves) }
    }

    /// Dernier déplacement encore annulable : moins de 10 minutes, fenêtre toujours dans sa stage
    /// d'arrivée (`currentScope`), stage d'origine connue. O(1).
    func undoable(at now: Date, currentScope: (WindowID) -> StageScope?) -> WindowMove? {
        guard let last = moves.last, last.from != nil, last.from != last.to,
              now.timeIntervalSince(last.at) <= Self.undoWindow,
              currentScope(last.windowID) == last.to else { return nil }
        return last
    }

    /// Déplacements à annuler ensemble : le dernier, ou tout son lot encore en place (SPEC-091 FR-006). O(m).
    func undoableBatch(at now: Date, currentScope: (WindowID) -> StageScope?) -> [WindowMove] {
        guard let last = undoable(at: now, currentScope: currentScope) else { return [] }
        guard let batch = last.batch else { return [last] }
        return moves.filter { $0.batch == batch && $0.from != nil && $0.from != $0.to && currentScope($0.windowID) == $0.to }
    }

    /// Marque d'un lot les déplacements de ces fenêtres notés depuis `start`. O(m).
    mutating func mark(batch: String, windows: Set<WindowID>, since start: Date) {
        for index in moves.indices where moves[index].at >= start && windows.contains(moves[index].windowID) {
            moves[index].batch = batch
        }
    }

    /// Propositions : 3 déplacements au moins d'une application vers une même stage en 7 jours, 75 % de
    /// ses déplacements, ni règle existante (`hasRule`) ni refus en cours. `identity` donne la clé et le
    /// titre de la stage aujourd'hui (nil si elle n'existe plus). O(m).
    func suggestions(at now: Date, identity: (StageScope) -> (key: String, title: String)?,
                     hasRule: (_ appName: String, StageScope) -> Bool) -> [RuleSuggestion] {
        let recent = moves.filter { now.timeIntervalSince($0.at) <= Self.habitWindow }
        var byApp: [String: [WindowMove]] = [:]
        for move in recent where !move.bundleID.isEmpty { byApp[move.bundleID, default: []].append(move) }
        var result: [RuleSuggestion] = []
        for (bundle, appMoves) in byApp {
            let byStage = Dictionary(grouping: appMoves) { $0.to }
            guard let (stage, toStage) = byStage.max(by: { $0.value.count < $1.value.count }),
                  toStage.count >= 3, Double(toStage.count) >= 0.75 * Double(appMoves.count),
                  let id = identity(stage), !hasRule(toStage.last?.appName ?? bundle, stage) else { continue }
            let key = "\(bundle)|\(id.key)"
            if let until = declined[key], until > now { continue }
            result.append(RuleSuggestion(bundleID: bundle, appName: toStage.last?.appName ?? bundle, stage: stage,
                                         stageTitle: id.title, count: toStage.count, declineKey: key))
        }
        return result.sorted { $0.count > $1.count || ($0.count == $1.count && $0.appName < $1.appName) }
    }

    mutating func decline(_ suggestion: RuleSuggestion, _ choice: RuleChoice, at now: Date) {
        switch choice {
        case .never: declined[suggestion.declineKey] = .distantFuture
        case .later: declined[suggestion.declineKey] = now.addingTimeInterval(24 * 3600)
        case .create: declined[suggestion.declineKey] = nil
        }
    }
}

struct LauncherMemoryStore: Sendable {
    let url: URL

    init(path: String = TestEnvironment.launcherFile("launcher-moves.json")) {
        url = URL(fileURLWithPath: NSString(string: path).expandingTildeInPath)
    }

    func load() -> LauncherMemoryBook { JSONPersistence.load(LauncherMemoryBook.self, from: url, default: LauncherMemoryBook()) }

    func update(_ change: (inout LauncherMemoryBook) -> Void) {
        JSONPersistence.mutate(LauncherMemoryBook.self, at: url, default: LauncherMemoryBook(), label: "launcher memory", change)
    }

    /// Les choix explicites doivent signaler toute modification non enregistrée.
    func updateChecked(_ change: (inout LauncherMemoryBook) -> Void) throws {
        try JSONPersistence.mutateChecked(LauncherMemoryBook.self, at: url, default: LauncherMemoryBook(), label: "launcher memory", change)
    }

    /// Un déplacement réel d'une fenêtre connue ; rien si elle ne change pas de stage. Écrit à chaque
    /// déplacement, rare (un geste de l'utilisateur ou une commande).
    func record(window: WindowSnapshot, from: StageScope?, to: StageScope, at now: Date = Date()) {
        guard from != to else { return }
        update { $0.record(WindowMove(windowID: window.id, bundleID: window.bundleID, appName: window.appName, from: from, to: to, at: now)) }
    }
}

/// Fenêtre fermée récemment, à rouvrir dans sa stage (SPEC-081).
struct ClosedWindow: Equatable, Sendable {
    let bundleID: String
    let title: String
    let stage: StageScope
    let closedAt: Date

    /// Fermetures confirmées de moins de 12 h, les plus récentes d'abord, une par application et
    /// titre, 3 au plus. O(m log m).
    static func recent(in state: PersistentStageState, at now: Date, limit: Int = 3) -> [ClosedWindow] {
        var found: [ClosedWindow] = []
        for scope in state.scopes {
            for stage in scope.stages {
                for member in stage.members {
                    guard let closedAt = member.confirmedClosedAt, now.timeIntervalSince(closedAt) <= 12 * 3600 else { continue }
                    found.append(ClosedWindow(bundleID: member.bundleID, title: member.title,
                                              stage: StageScope(displayID: scope.displayID, desktopID: scope.desktopID, stageID: stage.id),
                                              closedAt: closedAt))
                }
            }
        }
        var seen = Set<String>()
        return found.sorted { $0.closedAt > $1.closedAt }
            .filter { seen.insert("\($0.bundleID)|\($0.title)").inserted }
            .prefix(limit).map { $0 }
    }

    /// « il y a 3 min », « il y a 2 h ».
    static func ago(_ date: Date, now: Date) -> String {
        let minutes = max(1, Int(now.timeIntervalSince(date) / 60))
        return minutes < 60 ? "il y a \(minutes) min" : "il y a \(minutes / 60) h"
    }
}
