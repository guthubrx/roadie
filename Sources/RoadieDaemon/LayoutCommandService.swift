import Foundation
import RoadieAX
import RoadieCore
import RoadieStages
import RoadieTiler

public struct LayoutCommandResult: Equatable, Sendable {
    public var message: String
    public var changed: Bool

    public init(message: String, changed: Bool) {
        self.message = message
        self.changed = changed
    }
}

public struct LayoutCommandService {
    private let service: SnapshotService
    private let events: EventLog

    public init(service: SnapshotService = SnapshotService(), events: EventLog = EventLog()) {
        self.service = service
        self.events = events
    }

    /// `roadie balance` (SPEC-017 R12, T091) : dans la stage active de chaque écran en mode arbre,
    /// ratios remis à 0,5 et appliqués tout de suite ; les autres modes gardent la passe de
    /// disposition globale, sans les scopes à arbre.
    // O(w log w) - w = fenêtres du snapshot.
    public func balance() -> LayoutCommandResult {
        let generation = PlacementGeneration.shared.next()
        let snapshot = service.snapshot()
        service.removeLayoutIntents(in: snapshot)
        let treeScopes = snapshot.displays.compactMap { display -> StageScope? in
            guard let scope = snapshot.state.activeScope(on: display.id),
                  snapshot.state.stage(scope: scope)?.mode.usesTreeEngine == true
            else { return nil }
            return scope
        }
        let treeResults = treeScopes.map { scope in
            treeCommand("balance", label: "balance", scope: scope, snapshot: snapshot, generation: generation) { tree, _ in tree.balanced() }
        }
        let scopesByWindowID = Dictionary(
            snapshot.windows.compactMap { entry in entry.scope.map { (entry.window.id, $0) } },
            uniquingKeysWith: { first, _ in first }
        )
        let plan = ApplyPlan(commands: service.applyPlan(from: service.snapshot(), generation: generation).commands.filter { command in
            scopesByWindowID[command.window.id].map { !treeScopes.contains($0) } ?? true
        })
        let result = service.apply(plan, generation: generation)
        return LayoutCommandResult(
            message: "balance: trees=\(treeScopes.count) commands=\(plan.commands.count) applied=\(result.applied) clamped=\(result.clamped) failed=\(result.failed)",
            changed: treeResults.contains { $0.changed } || result.failed < result.attempted || plan.commands.isEmpty
        )
    }

    public func flatten() -> LayoutCommandResult {
        let generation = PlacementGeneration.shared.next()
        guard let context = activeContext() else {
            return LayoutCommandResult(message: "layout flatten: no active scope", changed: false)
        }
        // Mode arbre : `layout flatten` équivaut à `balance` (R12).
        if context.stage.mode.usesTreeEngine {
            return treeCommand("layout.flatten", label: "layout flatten", scope: context.scope, snapshot: context.snapshot, generation: generation) { tree, _ in
                tree.balanced()
            }
        }
        service.removeLayoutIntent(scope: context.scope)
        let ordered = service.orderedWindowIDs(in: context.scope, from: context.snapshot)
        let plan = service.applyPlan(from: context.snapshot, scope: context.scope, orderedWindowIDs: ordered, generation: generation)
        let result = service.apply(plan, generation: generation)
        emit(command: "layout.flatten", changed: result.failed < result.attempted || plan.commands.isEmpty)
        return LayoutCommandResult(
            message: "layout flatten: commands=\(plan.commands.count) applied=\(result.applied) clamped=\(result.clamped) failed=\(result.failed)",
            changed: result.failed < result.attempted || plan.commands.isEmpty
        )
    }

    public func split(_ axis: String) -> LayoutCommandResult {
        let generation = PlacementGeneration.shared.next()
        guard axis == "horizontal" || axis == "vertical" else {
            return LayoutCommandResult(message: "layout split: requires horizontal|vertical", changed: false)
        }
        guard let context = activeContext() else {
            return LayoutCommandResult(message: "layout split: no active scope", changed: false)
        }
        // Mode arbre : impose le sens du split parent de la fenêtre active. Vocabulaire Roadie :
        // `horizontal` = côte à côte (frontière verticale), `vertical` = empilées.
        if context.stage.mode.usesTreeEngine {
            guard let activeID = activeWindowID(in: context) else {
                return LayoutCommandResult(message: "layout split: no active window", changed: false)
            }
            let orientation: BSPOrientation = axis == "horizontal" ? .vertical : .horizontal
            return treeCommand("layout.split", label: "layout split \(axis)", scope: context.scope, snapshot: context.snapshot, generation: generation) { tree, absent in
                tree.settingSplit(of: activeID, to: orientation, excluding: absent)
            }
        }
        guard let display = context.snapshot.displays.first(where: { $0.id == context.scope.displayID }) else {
            return LayoutCommandResult(message: "layout split: no active display", changed: false)
        }
        service.removeLayoutIntent(scope: context.scope)
        let ordered = service.orderedWindowIDs(in: context.scope, from: context.snapshot)
        let placements = linearPlacements(
            ordered,
            in: display.visibleFrame.cgRect,
            horizontal: axis == "horizontal",
            gap: CGFloat(service.innerGap())
        )
        let windowsByID = Dictionary(uniqueKeysWithValues: context.snapshot.windows.compactMap { entry -> (WindowID, WindowSnapshot)? in
            guard entry.scope == context.scope, entry.window.isTileCandidate else { return nil }
            return (entry.window.id, entry.window)
        })
        let commands = ordered.compactMap { id -> ApplyCommand? in
            guard let window = windowsByID[id], let frame = placements[id], !framesAreClose(window.frame.cgRect, frame) else { return nil }
            return ApplyCommand(window: window, frame: Rect(frame.integral))
        }
        let plan = ApplyPlan(commands: commands)
        let result = service.apply(plan, generation: generation)
        persist(scope: context.scope, ordered: ordered, snapshot: context.snapshot, result: result)
        emit(command: "layout.split", changed: result.failed < result.attempted || plan.commands.isEmpty)
        return LayoutCommandResult(
            message: "layout split \(axis): commands=\(plan.commands.count) applied=\(result.applied) clamped=\(result.clamped) failed=\(result.failed)",
            changed: result.failed < result.attempted || plan.commands.isEmpty
        )
    }

    /// Inverse le sens du split parent de la fenêtre active (yabai --toggle split). Mode arbre
    /// uniquement ; `direction` est accepté pour la compatibilité de la CLI et ignoré.
    public func toggleSplit(_ direction: Direction? = nil) -> LayoutCommandResult {
        let generation = PlacementGeneration.shared.next()
        guard let context = activeContext() else {
            return LayoutCommandResult(message: "layout toggle-split: no active scope", changed: false)
        }
        guard context.stage.mode.usesTreeEngine else {
            return LayoutCommandResult(message: "layout toggle-split: requires spatialBsp", changed: false)
        }
        guard let activeID = activeWindowID(in: context) else {
            return LayoutCommandResult(message: "layout toggle-split: no active window", changed: false)
        }
        return treeCommand("layout.toggle_split", label: "layout toggle-split", scope: context.scope, snapshot: context.snapshot, generation: generation) { tree, absent in
            tree.togglingSplit(of: activeID, excluding: absent)
        }
    }

    public func insert(_ direction: Direction) -> LayoutCommandResult {
        insert(direction, verb: "insert")
    }

    private func insert(_ direction: Direction, verb: String) -> LayoutCommandResult {
        let generation = PlacementGeneration.shared.next()
        guard let context = activeContext(),
              let activeID = context.snapshot.focusedWindowID ?? context.stage.focusedWindowID ?? context.stage.windowIDs.last
        else {
            return LayoutCommandResult(message: "layout \(verb): no active window", changed: false)
        }
        // Mode arbre : refus explicite (R12) ; « unavailable » donne un code de sortie non nul.
        if context.stage.mode.usesTreeEngine {
            return LayoutCommandResult(message: "layout \(verb): unavailable in tree mode (spatialBsp), use warp", changed: false)
        }
        var ordered = service.orderedWindowIDs(in: context.scope, from: context.snapshot)
        ordered.removeAll { $0 == activeID }
        switch direction {
        case .left, .up:
            ordered.insert(activeID, at: 0)
        case .right, .down:
            ordered.append(activeID)
        }
        let plan = service.applyPlan(from: context.snapshot, scope: context.scope, orderedWindowIDs: ordered, generation: generation)
        let result = service.apply(plan, generation: generation)
        persist(scope: context.scope, ordered: ordered, snapshot: context.snapshot, result: result)
        emit(command: "layout.insert", changed: result.failed < result.attempted || plan.commands.isEmpty)
        return LayoutCommandResult(
            message: "layout insert \(direction.rawValue): commands=\(plan.commands.count) applied=\(result.applied) clamped=\(result.clamped) failed=\(result.failed)",
            changed: result.failed < result.attempted || plan.commands.isEmpty
        )
    }

    public func zoomParent() -> LayoutCommandResult {
        let generation = PlacementGeneration.shared.next()
        guard let context = activeContext(),
              let activeID = context.snapshot.focusedWindowID ?? context.stage.focusedWindowID ?? context.stage.windowIDs.last,
              let entry = context.snapshot.windows.first(where: { $0.window.id == activeID }),
              let display = context.snapshot.displays.first(where: { $0.id == context.scope.displayID })
        else {
            return LayoutCommandResult(message: "layout zoom-parent: no active window", changed: false)
        }
        let plan = ApplyPlan(commands: [ApplyCommand(window: entry.window, frame: display.visibleFrame)])
        let result = service.apply(plan, generation: generation)
        service.saveLayoutIntent(
            scope: context.scope,
            windowIDs: [activeID],
            placements: [activeID: result.items.first?.actual ?? display.visibleFrame],
            source: .command,
            zoomedWindowID: activeID
        )
        emit(command: "layout.zoom-parent", changed: result.failed < result.attempted)
        return LayoutCommandResult(
            message: "layout zoom-parent: applied=\(result.applied) clamped=\(result.clamped) failed=\(result.failed)",
            changed: result.failed < result.attempted
        )
    }

    public func join(with direction: Direction) -> LayoutCommandResult {
        insert(direction, verb: "join-with")
    }

    private func activeWindowID(in context: (snapshot: DaemonSnapshot, scope: StageScope, stage: RoadieStages.StageState)) -> WindowID? {
        context.snapshot.focusedWindowID ?? context.stage.focusedWindowID ?? context.stage.windowIDs.last
    }

    /// Commande sur l'arbre d'une stage (SPEC-017 R12, T091) : mutation de l'arbre persisté, puis
    /// une seule application immédiate par `applyTreeScope`, dans une nouvelle génération.
    /// `mutation` reçoit les feuilles absentes du snapshot (A9), à exclure de la géométrie.
    // O(n²) au pire - n = feuilles de l'arbre, borné (voir BSPTree).
    private func treeCommand(
        _ command: String,
        label: String,
        scope: StageScope,
        snapshot: DaemonSnapshot,
        generation: UInt64,
        mutation: (BSPTree, Set<WindowID>) -> BSPTree
    ) -> LayoutCommandResult {
        let live = Set(snapshot.windows.compactMap { entry in
            entry.scope == scope && entry.window.isTileCandidate ? entry.window.id : nil
        })
        let treeChanged = service.effectiveStageStore.mutate { state -> Bool in
            let existing = state.bspTree(for: scope) ?? .empty
            let mutated = mutation(existing, Set(existing.windowIDs).subtracting(live))
            guard mutated != existing else { return false }
            state.setBSPTree(mutated, for: scope)
            return true
        }
        let tick = service.applyTreeScope(scope, cause: command, generation: generation)
        let changed = treeChanged || tick.applied + tick.clamped > 0
        emit(command: command, changed: changed || tick.failed == 0)
        return LayoutCommandResult(
            message: "\(label): tree changed=\(treeChanged) commands=\(tick.commands) applied=\(tick.applied) clamped=\(tick.clamped) failed=\(tick.failed)",
            changed: changed
        )
    }

    private func activeContext() -> (snapshot: DaemonSnapshot, scope: StageScope, stage: RoadieStages.StageState)? {
        let snapshot = service.snapshot()
        if let focusedID = snapshot.focusedWindowID,
           let focused = snapshot.windows.first(where: { entry in
               guard let scope = entry.scope else { return false }
               return entry.window.id == focusedID
                   && entry.window.isTileCandidate
                   && snapshot.state.activeScope(on: scope.displayID) == scope
           })?.scope,
           let stage = snapshot.state.stage(scope: focused) {
            return (snapshot, focused, stage)
        }

        for display in snapshot.displays {
            guard let scope = snapshot.state.activeScope(on: display.id),
                  let stage = snapshot.state.stage(scope: scope)
            else { continue }
            return (snapshot, scope, stage)
        }
        return nil
    }

    private func persist(scope: StageScope, ordered: [WindowID], snapshot: DaemonSnapshot, result: ApplyResult) {
        var placements = Dictionary(uniqueKeysWithValues: snapshot.windows.compactMap { entry -> (WindowID, Rect)? in
            guard entry.scope == scope else { return nil }
            return (entry.window.id, entry.window.frame)
        })
        for item in result.items where item.status != .failed {
            placements[item.windowID] = item.actual ?? item.requested
        }
        service.saveLayoutIntent(scope: scope, windowIDs: ordered, placements: placements, source: .command)
    }

    private func linearPlacements(_ ordered: [WindowID], in rect: CGRect, horizontal: Bool, gap: CGFloat) -> [WindowID: CGRect] {
        guard !ordered.isEmpty else { return [:] }
        guard ordered.count > 1 else { return [ordered[0]: rect.integral] }

        var result: [WindowID: CGRect] = [:]
        let totalGap = gap * CGFloat(ordered.count - 1)
        if horizontal {
            let usable = max(0, rect.width - totalGap)
            let baseWidth = floor(usable / CGFloat(ordered.count))
            var x = rect.minX
            for (index, id) in ordered.enumerated() {
                let width = index == ordered.count - 1 ? max(0, rect.maxX - x) : baseWidth
                result[id] = CGRect(x: x, y: rect.minY, width: width, height: rect.height).integral
                x += width + gap
            }
            return result
        }

        let usable = max(0, rect.height - totalGap)
        let baseHeight = floor(usable / CGFloat(ordered.count))
        var y = rect.minY
        for (index, id) in ordered.enumerated() {
            let height = index == ordered.count - 1 ? max(0, rect.maxY - y) : baseHeight
            result[id] = CGRect(x: rect.minX, y: y, width: rect.width, height: height).integral
            y += height + gap
        }
        return result
    }

    private func framesAreClose(_ lhs: CGRect, _ rhs: CGRect) -> Bool {
        abs(lhs.minX - rhs.minX) <= 1
            && abs(lhs.minY - rhs.minY) <= 1
            && abs(lhs.width - rhs.width) <= 1
            && abs(lhs.height - rhs.height) <= 1
    }

    private func emit(command: String, changed: Bool) {
        events.append(RoadieEventEnvelope(
            id: "cmd_\(UUID().uuidString)",
            type: changed ? "command.applied" : "command.failed",
            scope: .command,
            subject: AutomationSubject(kind: "command", id: command),
            cause: .command,
            payload: ["command": .string(command)]
        ))
    }
}

/// Frames d'une commande qui change la visibilité (bascule de stage, de bureau ou de signet,
/// `window display N`, dépôt entre scopes, SPEC-017 A15, T212). Les changements logiques sont
/// déjà persistés ; ces frames entrent dans un seul plan arbitré par fenêtre.
struct CommandPlacement {
    /// Fenêtres à masquer : priorité sur toute autre frame (A1).
    var hiding: [WindowID: CGRect] = [:]
    /// Frames à reposer (frames mémorisées des modes sans arbre, fenêtre transférée). Elles servent
    /// de géométrie au calcul de la disposition et cèdent la place à sa frame si elle en donne une.
    var restoring: [WindowID: CGRect] = [:]
    /// Scopes à disposer ; seuls ceux actifs dans le snapshot du plan sont posés. nil : tous.
    var layoutScopes: Set<StageScope>? = []
}

extension SnapshotService {
    /// Plan unique d'une commande (A15, T212) : copie de travail du snapshot avec les frames
    /// masquées et restaurées, disposition des scopes demandés calculée sur cette copie, arbitrage
    /// par fenêtre (masquage, puis disposition, puis restauration), puis une seule écriture groupée
    /// dans `generation`. Le focus reste à l'appelant, après l'application.
    /// `snapshot` : relevé fait après les changements logiques ; nil = snapshot partagé (relevé si
    /// l'état a changé). Contournement local (lot C3) : le suivi des scopes à arbre reprend celui de
    /// `applyTreeScope` (fin d'attente, épisode, `layout_apply`, publication), faute d'API commune.
    // O(w log w) - w = fenêtres du snapshot.
    @discardableResult
    func applyCommandPlacement(
        _ placement: CommandPlacement,
        snapshot: DaemonSnapshot? = nil,
        cause: String,
        generation: UInt64,
        events: EventLog
    ) -> (plan: ApplyPlan, result: ApplyResult) {
        let startedAt = Date()
        let observed = snapshot ?? sharedSnapshot(followFocus: false)
        var working = observed
        for index in working.windows.indices {
            let id = working.windows[index].window.id
            if let frame = placement.hiding[id] ?? placement.restoring[id] {
                working.windows[index].window.frame = Rect(frame)
            }
        }
        let scopeByWindow = Dictionary(
            working.windows.compactMap { entry in entry.scope.map { (entry.window.id, $0) } },
            uniquingKeysWith: { first, _ in first }
        )
        let laidOut = { (id: WindowID) in
            placement.layoutScopes.map { scopes in scopeByWindow[id].map(scopes.contains) ?? false } ?? true
        }
        var targets = placement.restoring
        let layout = placement.layoutScopes?.isEmpty == true ? [] : applyPlan(from: working, generation: generation).commands
        for command in layout where laidOut(command.window.id) {
            targets[command.window.id] = command.frame.cgRect
        }
        targets.merge(placement.hiding) { _, hidden in hidden }
        let windowsByID = Dictionary(observed.windows.map { ($0.window.id, $0.window) }, uniquingKeysWith: { first, _ in first })
        let plan = ApplyPlan(commands: targets.keys.sorted().compactMap { id -> ApplyCommand? in
            guard let window = windowsByID[id], let target = targets[id], !LayoutMaintainer.matches(window.frame.cgRect, target) else { return nil }
            return ApplyCommand(window: window, frame: Rect(target))
        })
        let treeScopes = observed.displays.compactMap { display -> StageScope? in
            guard let scope = working.state.activeScope(on: display.id),
                  working.state.stage(scope: scope)?.mode.usesTreeEngine == true,
                  placement.layoutScopes?.contains(scope) ?? true
            else { return nil }
            return scope
        }
        let processState = SnapshotProcessState.forStatePath(effectiveStageStore.fileURL.path)
        let commandCause = cause.hasPrefix("command:") ? cause : "command:\(cause)"
        let episode = treeScopes.isEmpty ? nil : EpisodeContext.shared.begin(cause: commandCause)
        for scope in treeScopes { processState.noteTreeScopeApplied(scope, at: startedAt) }
        let result = apply(plan, generation: generation)
        if let episode, let scope = treeScopes.first {
            events.append(RoadieEvent(type: "layout_apply", scope: scope, details: [
                "cause": commandCause,
                "durationMs": String(format: "%.1f", Date().timeIntervalSince(startedAt) * 1000),
                "pass": String(processState.nextCommandPass(episode: episode)),
                // Relevé fait après les changements logiques : l'état a changé, le partagé est périmé.
                "scans": "1",
                "axWrites": String(result.items.count * 3),
                "layoutVersion": String(generation),
                "commands": String(plan.commands.count),
                "applied": String(result.applied),
                "clamped": String(result.clamped),
                "failed": String(result.failed),
                "windowWrites": result.items.map { "\($0.windowID.rawValue):1" }.joined(separator: ",")
            ], episodeId: episode))
            for scope in treeScopes {
                TreeScopeApplicationCenter.shared.publish(TreeScopeApplication(
                    scope: scope,
                    generation: generation,
                    windowIDs: result.items.compactMap { scopeByWindow[$0.windowID] == scope ? $0.windowID : nil },
                    appliedAt: Date()
                ))
            }
        }
        return (plan, result)
    }
}
