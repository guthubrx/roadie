import CoreGraphics
import Foundation
import RoadieAX
import RoadieCore
import RoadieTiler

public enum Direction: String, Sendable {
    case left
    case right
    case up
    case down
}

public struct WindowCommandResult: CommandResult, Equatable, Sendable {
    public var message: String
    public var changed: Bool
    /// Statut explicite (REL-042). Sans valeur donnée : `.changed` si `changed`, sinon nil
    /// (statut non posé, code de sortie lu dans le message).
    public var outcome: CommandOutcome?

    public init(message: String, changed: Bool, outcome: CommandOutcome? = nil) {
        self.message = message
        self.changed = changed
        self.outcome = outcome ?? (changed ? .changed : nil)
    }
}

public struct WindowCommandService {
    private let service: SnapshotService
    private let stageStore: StageStore
    private let resizeStep: CGFloat
    private let mouseFollower: MouseFollower
    private let events: EventLog
    private let commandActivity: LayoutCommandActivity

    public init(
        service: SnapshotService = SnapshotService(),
        stageStore: StageStore? = nil,
        resizeStep: CGFloat = 80,
        mouseFollower: MouseFollower = MouseFollower(),
        events: EventLog = EventLog(),
        commandActivity: LayoutCommandActivity = .shared
    ) {
        self.service = service
        self.stageStore = stageStore ?? service.effectiveStageStore
        self.resizeStep = resizeStep
        self.mouseFollower = mouseFollower
        self.events = events
        self.commandActivity = commandActivity
    }

    public func focus(_ direction: Direction) -> WindowCommandResult {
        let snapshot = service.snapshot()
        guard let pair = activeAndNeighbor(in: snapshot, direction: direction) else {
            let result = focusAdjacentDisplayWindow(direction, from: snapshot)
            appendWindowCommandEvent(
                verb: "focus",
                direction: direction,
                snapshot: snapshot,
                active: activeWindow(in: snapshot),
                result: result
            )
            return result
        }
        let ok = focusWindow(pair.neighbor.window)
        if ok, let scope = pair.active.scope {
            recenterScrollingRibbonIfNeeded(scope: scope, snapshot: snapshot, direction: direction)
        }
        let result = WindowCommandResult.changedOrFailed(ok ? "focused \(pair.neighbor.window.id)" : "focus failed", changed: ok)
        appendWindowCommandEvent(
            verb: "focus",
            direction: direction,
            snapshot: snapshot,
            active: pair.active,
            neighbor: pair.neighbor,
            result: result
        )
        return result
    }

    private func recenterScrollingRibbonIfNeeded(scope: StageScope, snapshot: DaemonSnapshot, direction: Direction? = nil) {
        guard snapshot.state.stage(scope: scope)?.mode == .scrolling else { return }
        let gen = PlacementGeneration.shared.next()
        let refreshed = service.snapshot(followFocus: false)
        let ordered = refreshed.state.stage(scope: scope)?.windowIDs ?? []
        guard !ordered.isEmpty else { return }
        let smoothPolicy: MotionPolicy? = service.effectiveConfig.tiling.scrollingSmoothScroll
            ? FrameTransitionRuntime.scrollingRibbonPolicy
            : nil
        _ = service.apply(
            service.applyPlan(from: refreshed, scope: scope, orderedWindowIDs: ordered, generation: gen),
            generation: gen,
            animation: .move,
            transitionDirection: direction,
            policyOverride: smoothPolicy
        )
    }

    public func focusBackAndForth() -> WindowCommandResult {
        let snapshot = service.snapshot()
        guard let active = activeWindow(in: snapshot), let scope = active.scope else {
            return WindowCommandResult(message: "focus back-and-forth: no active window", changed: false, outcome: .noOp)
        }
        var state = stageStore.state()
        let persistentScope = state.scope(displayID: scope.displayID, desktopID: scope.desktopID)
        guard let stage = persistentScope.stages.first(where: { $0.id == scope.stageID }) else {
            return WindowCommandResult(message: "focus back-and-forth: no active stage", changed: false, outcome: .noOp)
        }
        let targetID = stage.previousFocusedWindowID.flatMap { previous in
            snapshot.windows.first { $0.window.id == previous && $0.scope == scope }?.window.id
        } ?? stage.members.reversed().first { $0.windowID != active.window.id }?.windowID
        guard let targetID,
              let target = snapshot.windows.first(where: { $0.window.id == targetID && $0.scope == scope })?.window
        else {
            return WindowCommandResult(message: "focus back-and-forth: no previous window", changed: false, outcome: .noOp)
        }
        let ok = focusWindow(target)
        if ok {
            recenterScrollingRibbonIfNeeded(scope: scope, snapshot: snapshot)
        }
        return WindowCommandResult.changedOrFailed(ok ? "focus back-and-forth \(target.id.rawValue)" : "focus back-and-forth failed", changed: ok)
    }

    public func focus(windowID: WindowID) -> WindowCommandResult {
        let snapshot = service.snapshot()
        guard let entry = snapshot.windows.first(where: { $0.window.id == windowID }) else {
            return WindowCommandResult(message: "focus: unknown window \(windowID.rawValue)", changed: false, outcome: .failed)
        }
        let ok = focusWindow(entry.window)
        if ok, let scope = entry.scope {
            if snapshot.state.stage(scope: scope)?.mode.usesTreeEngine == true {
                _ = try? stageStore.mutateChecked { state in
                    if let tree = state.bspTree(for: scope), tree.tabGroup(containing: windowID) != nil {
                        let updated = tree.selectingTab(windowID)
                        if updated != tree {
                            state.setBSPTree(updated, for: scope)
                        }
                        var persistent = state.scope(displayID: scope.displayID, desktopID: scope.desktopID)
                        persistent.setFocusedWindow(windowID, in: scope.stageID)
                        state.update(persistent)
                    }
                }
                _ = service.snapshot(followFocus: false)
            }
            recenterScrollingRibbonIfNeeded(scope: scope, snapshot: snapshot)
        }
        return WindowCommandResult.changedOrFailed(ok ? "focused \(entry.window.id.rawValue)" : "focus failed", changed: ok)
    }

    /// Fenêtre active et arbre de son scope, si ce scope utilise le moteur à arbre
    /// (`usesTreeEngine` : `spatialBsp` et son alias `mutableBsp`). Arbre vide s'il n'est pas
    /// encore construit. nil pour les autres modes.
    private func activeTree(in snapshot: DaemonSnapshot) -> (active: ScopedWindowSnapshot, scope: StageScope, tree: BSPTree)? {
        guard let active = activeWindow(in: snapshot),
              let scope = active.scope,
              snapshot.state.stage(scope: scope)?.mode.usesTreeEngine == true
        else { return nil }
        return (active, scope, stageStore.state().bspTree(for: scope) ?? .empty)
    }

    private enum TreeVerb: String {
        case move
        case warp
        case resize
    }

    /// `move`, `warp` et `resize` en mode arbre (SPEC-017 R12, T090) : mutation de l'arbre persisté,
    /// puis une seule application immédiate par `applyTreeScope`, dans une nouvelle génération, sans
    /// l'attente globale de 2 s de `LayoutCommandActivity`. Voisines et frontières sont mesurées sur
    /// l'arbre projeté (A9). `move` échange les feuilles (yabai --swap) ; `warp` retire la fenêtre et
    /// la réinsère en coupant la voisine selon la forme de sa feuille (R3) ; `resize` pousse le bord
    /// désigné vers l'extérieur, ou à défaut tire la frontière opposée vers l'intérieur.
    // O(n²) au pire - n = feuilles de l'arbre, borné (voir BSPTree).
    private func treeCommand(
        _ verb: TreeVerb,
        _ direction: Direction,
        snapshot: DaemonSnapshot,
        context: (active: ScopedWindowSnapshot, scope: StageScope, tree: BSPTree),
        generation: UInt64
    ) -> WindowCommandResult {
        let (active, scope, tree) = context
        let id = active.window.id
        let geometry = service.commandTreeGeometry(for: scope, tree: tree, in: snapshot)
        let frames = geometry?.frames(of: tree) ?? [:]
        let mutation: (BSPTree) -> BSPTree
        var neighbor: ScopedWindowSnapshot?
        switch verb {
        case .resize:
            guard let geometry, let frame = frames[id], let edge = BSPEdge(rawValue: direction.rawValue) else {
                let result = WindowCommandResult(message: "resize \(direction.rawValue): window not in tree", changed: false, outcome: .noOp)
                appendWindowCommandEvent(verb: "resize", direction: direction, snapshot: snapshot, active: active, scope: scope, result: result, extra: ["strategy": "tree"])
                return result
            }
            // Le même décalage déplace le bord désigné vers l'extérieur et le bord opposé vers
            // l'intérieur : `adjustingFence` ne lit que le bord de la frontière visée.
            let target: CGRect = switch direction {
            case .left: frame.offsetBy(dx: -resizeStep, dy: 0)
            case .right: frame.offsetBy(dx: resizeStep, dy: 0)
            case .up: frame.offsetBy(dx: 0, dy: -resizeStep)
            case .down: frame.offsetBy(dx: 0, dy: resizeStep)
            }
            mutation = { tree in
                let pushed = tree.adjustingFence(of: id, edge: edge, to: target, in: geometry.container, innerGap: geometry.innerGap, tabBarHeight: geometry.tabBarHeight, excluding: geometry.absent)
                guard pushed == tree else { return pushed }
                return tree.adjustingFence(of: id, edge: edge.opposite, to: target, in: geometry.container, innerGap: geometry.innerGap, tabBarHeight: geometry.tabBarHeight, excluding: geometry.absent)
            }
        case .move, .warp:
            guard let geometry,
                  let neighborID = treeNeighbor(of: id, direction: direction, frames: frames, tree: tree, absent: geometry.absent),
                  let found = snapshot.windows.first(where: { $0.window.id == neighborID })
            else {
                let result = sendActiveToAdjacentDisplay(direction, from: snapshot, verb: verb.rawValue)
                appendWindowCommandEvent(verb: verb.rawValue, direction: direction, snapshot: snapshot, active: active, result: result)
                return result
            }
            neighbor = found
            if verb == .move {
                mutation = { $0.swapping(id, neighborID) }
            } else {
                let side: BSPInsertionSide = (direction == .right || direction == .down) ? .right : .left
                mutation = {
                    $0.removing(id).inserting(id, at: neighborID, side: side, in: geometry.container, innerGap: geometry.innerGap, excluding: geometry.absent)
                }
            }
        }
        let changed: Bool
        do {
            changed = try stageStore.mutateChecked { state -> Bool in
                let existing = state.bspTree(for: scope) ?? .empty
                let mutated = mutation(existing)
                guard mutated != existing else { return false }
                state.setBSPTree(mutated, for: scope)
                return true
            }
            if changed {
                try service.removeLayoutIntentChecked(scope: scope)
            }
        } catch {
            return .persistenceFailure("\(verb.rawValue) \(direction.rawValue)", error)
        }
        var tick: MaintenanceTick?
        if changed {
            // SPEC-051 D-03 : les fenêtres n'ont pas bougé depuis le relevé d'entrée et l'arbre
            // muté est relu depuis stages.json : aucun second relevé AX.
            tick = service.applyTreeScope(
                scope,
                cause: "window.\(verb.rawValue).\(direction.rawValue)",
                generation: generation,
                using: snapshot
            )
        }
        _ = focusWindow(active.window)
        let result = WindowCommandResult.changedOrFailed(
            "\(verb.rawValue) \(direction.rawValue): tree changed=\(changed) applied=\(tick?.applied ?? 0) failed=\(tick?.failed ?? 0)",
            changed: changed
        )
        appendWindowCommandEvent(
            verb: verb.rawValue,
            direction: direction,
            snapshot: snapshot,
            active: active,
            neighbor: neighbor,
            scope: scope,
            result: result,
            extra: [
                "strategy": "tree",
                "treeApplied": String(tick?.applied ?? 0),
                "treeCommands": String(tick?.commands ?? 0)
            ]
        )
        return result
    }

    /// Voisine de `id` dans `direction`, mesurée sur les frames de l'arbre projeté (A9).
    /// Exclut les co-onglets de `id` et privilégie l'onglet actif de chaque tuile voisine (Spec 165).
    /// Égalité départagée par identifiant, pour un résultat déterministe. O(n).
    private func treeNeighbor(
        of id: WindowID,
        direction: Direction,
        frames: [WindowID: CGRect],
        tree: BSPTree? = nil,
        absent: Set<WindowID> = []
    ) -> WindowID? {
        guard let origin = frames[id] else { return nil }
        let projected = tree?.projected(excluding: absent)
        let ownGroup = Set(projected?.tabGroup(containing: id)?.windowIDs ?? [id])
        let activeIDs = projected?.activeWindowIDs
        let best = frames
            .filter { !ownGroup.contains($0.key) && (activeIDs == nil || activeIDs!.contains($0.key)) }
            .map { (id: $0.key, score: neighborScore(from: origin, to: $0.value, direction: direction)) }
            .min { $0.score != $1.score ? $0.score < $1.score : $0.id.rawValue < $1.id.rawValue }
        guard let best, best.score.isFinite else { return nil }
        return best.id
    }

    public func move(_ direction: Direction) -> WindowCommandResult {
        let generation = PlacementGeneration.shared.next()
        let snapshot = service.snapshot()
        if let context = activeTree(in: snapshot) {
            return treeCommand(.move, direction, snapshot: snapshot, context: context, generation: generation)
        }
        beginLayoutCommand("window.move.\(direction.rawValue)")
        defer { finishLayoutCommand("window.move.\(direction.rawValue)") }
        guard let pair = activeAndNeighbor(in: snapshot, direction: direction),
              let scope = pair.active.scope
        else {
            let result = sendActiveToAdjacentDisplay(direction, from: snapshot, verb: "move")
            appendWindowCommandEvent(
                verb: "move",
                direction: direction,
                snapshot: snapshot,
                active: activeWindow(in: snapshot),
                result: result
            )
            return result
        }
        do {
            try service.removeLayoutIntentChecked(scope: scope)
        } catch {
            return .persistenceFailure("move \(direction.rawValue)", error)
        }
        let ordered = swappedWindowIDs(
            in: snapshot,
            scope: scope,
            activeID: pair.active.window.id,
            neighborID: pair.neighbor.window.id
        )
        // Modes `tabbed` et `scrolling` : persister directement le nouvel ordre dans `stages.json`
        // pour que la barre d'onglets et le ruban reflètent immédiatement l'échange (Spec 164).
        if snapshot.state.stage(scope: scope)?.mode.allowsWindowOverlapOrOverflow == true {
            do {
                try stageStore.mutateChecked { state in
                    var persistent = state.scope(displayID: scope.displayID, desktopID: scope.desktopID)
                    if let idx = persistent.stages.firstIndex(where: { $0.id == scope.stageID }) {
                        let byID = Dictionary(uniqueKeysWithValues: persistent.stages[idx].members.map { ($0.windowID, $0) })
                        let reordered = ordered.compactMap { byID[$0] }
                        let orderedSet = Set(ordered)
                        let remaining = persistent.stages[idx].members.filter { !orderedSet.contains($0.windowID) }
                        persistent.stages[idx].members = reordered + remaining
                        persistent.stages[idx].focusedWindowID = pair.active.window.id
                        state.update(persistent)
                    }
                }
            } catch {
                return .persistenceFailure("move \(direction.rawValue)", error)
            }
            let plan = service.applyPlan(from: snapshot, scope: scope, orderedWindowIDs: ordered, generation: generation)
            let result = service.apply(plan, generation: generation)
            _ = focusWindow(pair.active.window)
            let commandResult = WindowCommandResult(
                message: "move \(direction.rawValue): reordered attempted=\(result.attempted) applied=\(result.applied)",
                changed: true,
                outcome: .changed
            )
            appendWindowCommandEvent(
                verb: "move",
                direction: direction,
                snapshot: snapshot,
                active: pair.active,
                neighbor: pair.neighbor,
                scope: scope,
                result: commandResult,
                applyResult: result
            )
            return commandResult
        }
        let plan = service.applyPlan(
            from: snapshot,
            scope: scope,
            orderedWindowIDs: ordered,
            generation: generation
        )
        let result = service.apply(plan, generation: generation)
        if shouldPersistCommandIntent(after: result) {
            do {
                try persistIntentAfterCommand(
                    from: snapshot,
                    scope: scope,
                    orderedWindowIDs: ordered,
                    plan: plan,
                    result: result
                )
            } catch {
                return .persistenceFailure("move \(direction.rawValue)", error)
            }
        }
        _ = focusWindow(pair.active.window)
        let commandResult = WindowCommandResult.changedOrFailed(
            "move \(direction.rawValue): attempted=\(result.attempted) applied=\(result.applied) clamped=\(result.clamped) failed=\(result.failed)",
            changed: result.attempted > 0 && result.failed < result.attempted
        )
        appendWindowCommandEvent(
            verb: "move",
            direction: direction,
            snapshot: snapshot,
            active: pair.active,
            neighbor: pair.neighbor,
            scope: scope,
            result: commandResult,
            applyResult: result
        )
        return commandResult
    }

    public func warp(_ direction: Direction) -> WindowCommandResult {
        let generation = PlacementGeneration.shared.next()
        let snapshot = service.snapshot()
        if let context = activeTree(in: snapshot) {
            return treeCommand(.warp, direction, snapshot: snapshot, context: context, generation: generation)
        }
        beginLayoutCommand("window.warp.\(direction.rawValue)")
        defer { finishLayoutCommand("window.warp.\(direction.rawValue)") }
        guard let pair = activeAndNeighbor(in: snapshot, direction: direction),
              let scope = pair.active.scope
        else {
            let result = sendActiveToAdjacentDisplay(direction, from: snapshot, verb: "warp")
            appendWindowCommandEvent(
                verb: "warp",
                direction: direction,
                snapshot: snapshot,
                active: activeWindow(in: snapshot),
                result: result
            )
            return result
        }
        do {
            try service.removeLayoutIntentChecked(scope: scope)
        } catch {
            return .persistenceFailure("warp \(direction.rawValue)", error)
        }
        guard let plan = structuralWarpPlan(
            in: snapshot,
            scope: scope,
            active: pair.active.window,
            neighbor: pair.neighbor.window,
            direction: direction
        ) else {
            let result = WindowCommandResult(message: "warp \(direction.rawValue): no structural change", changed: false, outcome: .noOp)
            appendWindowCommandEvent(
                verb: "warp",
                direction: direction,
                snapshot: snapshot,
                active: pair.active,
                neighbor: pair.neighbor,
                scope: scope,
                result: result
            )
            return result
        }
        let result = service.apply(plan, generation: generation)
        if shouldPersistCommandIntent(after: result) {
            let ordered = service.orderedWindowIDs(in: scope, from: snapshot)
            do {
                try persistIntentAfterCommand(
                    from: snapshot,
                    scope: scope,
                    orderedWindowIDs: ordered,
                    plan: plan,
                    result: result
                )
            } catch {
                return .persistenceFailure("warp \(direction.rawValue)", error)
            }
        }
        _ = focusWindow(pair.active.window)
        let commandResult = WindowCommandResult.changedOrFailed(
            "warp \(direction.rawValue): attempted=\(result.attempted) applied=\(result.applied) clamped=\(result.clamped) failed=\(result.failed)",
            changed: result.attempted > 0 && result.failed < result.attempted
        )
        appendWindowCommandEvent(
            verb: "warp",
            direction: direction,
            snapshot: snapshot,
            active: pair.active,
            neighbor: pair.neighbor,
            scope: scope,
            result: commandResult,
            applyResult: result
        )
        return commandResult
    }

    public func resize(_ direction: Direction) -> WindowCommandResult {
        let generation = PlacementGeneration.shared.next()
        let snapshot = service.snapshot()
        if let context = activeTree(in: snapshot) {
            return treeCommand(.resize, direction, snapshot: snapshot, context: context, generation: generation)
        }
        beginLayoutCommand("window.resize.\(direction.rawValue)")
        defer { finishLayoutCommand("window.resize.\(direction.rawValue)") }
        guard let active = activeWindow(in: snapshot),
              let scope = active.scope
        else {
            let result = WindowCommandResult(message: "no active window", changed: false, outcome: .noOp)
            appendWindowCommandEvent(
                verb: "resize",
                direction: direction,
                snapshot: snapshot,
                active: nil,
                result: result
            )
            return result
        }
        let frame = resizedFrame(active.window.frame.cgRect, direction: direction)
        do {
            try service.removeLayoutIntentChecked(scope: scope)
        } catch {
            return .persistenceFailure("resize \(direction.rawValue)", error)
        }
        let resizeResult = service.apply(ApplyPlan(commands: [
            ApplyCommand(window: active.window, frame: Rect(frame)),
        ]), generation: generation)
        guard resizeResult.attempted > 0 && resizeResult.failed < resizeResult.attempted else {
            _ = focusWindow(active.window)
            let result = WindowCommandResult(
                message: "resize \(direction.rawValue): attempted=\(resizeResult.attempted) applied=\(resizeResult.applied) clamped=\(resizeResult.clamped) failed=\(resizeResult.failed)",
                changed: false,
                outcome: .failed
            )
            appendWindowCommandEvent(
                verb: "resize",
                direction: direction,
                snapshot: snapshot,
                active: active,
                scope: scope,
                result: result,
                applyResult: resizeResult,
                extra: ["phase": "direct"]
            )
            return result
        }

        let actualFrame = resizeResult.items.first(where: { $0.windowID == active.window.id })?.actual ?? Rect(frame)
        let updatedSnapshot = snapshotByUpdating(windowID: active.window.id, to: actualFrame, in: snapshot)
        let plan = service.applyPlan(from: updatedSnapshot, priorityWindowIDs: [active.window.id], generation: generation)
        let result = service.apply(plan, generation: generation)
        if shouldPersistCommandIntent(after: resizeResult), shouldPersistCommandIntent(after: result) {
            let ordered = service.orderedWindowIDs(in: scope, from: updatedSnapshot)
            do {
                try persistIntentAfterCommand(
                    from: updatedSnapshot,
                    scope: scope,
                    orderedWindowIDs: ordered,
                    plan: plan,
                    result: result
                )
            } catch {
                return .persistenceFailure("resize \(direction.rawValue)", error)
            }
        }
        _ = focusWindow(active.window)
        let commandResult = WindowCommandResult(
            message: "resize \(direction.rawValue): direct=\(resizeResult.applied + resizeResult.clamped) layout=\(result.attempted) applied=\(result.applied) clamped=\(result.clamped) failed=\(result.failed)",
            changed: true
        )
        appendWindowCommandEvent(
            verb: "resize",
            direction: direction,
            snapshot: snapshot,
            active: active,
            scope: scope,
            result: commandResult,
            applyResult: result,
            extra: [
                "directAttempted": String(resizeResult.attempted),
                "directApplied": String(resizeResult.applied),
                "directClamped": String(resizeResult.clamped),
                "directFailed": String(resizeResult.failed)
            ]
        )
        return commandResult
    }

    /// Ferme gracieusement la fenêtre ciblée (ou focalisée) via son bouton AX de fermeture (Spec 160).
    public func close(windowID: WindowID? = nil) -> WindowCommandResult {
        let snapshot = service.snapshot()
        let entry: ScopedWindowSnapshot?
        if let windowID {
            entry = snapshot.windows.first { $0.window.id == windowID }
        } else if let focusedID = service.focusedWindowID() ?? snapshot.focusedWindowID,
                  let focusedEntry = snapshot.windows.first(where: { $0.window.id == focusedID }) {
            entry = focusedEntry
        } else {
            entry = activeWindow(in: snapshot)
        }
        guard let target = entry else {
            let suffix = windowID.map { " \($0.rawValue): unknown window" } ?? ": no active window"
            return WindowCommandResult(
                message: "window close\(suffix)",
                changed: false,
                outcome: windowID == nil ? .noOp : .failed
            )
        }
        let ok = service.close(target.window)
        let result = WindowCommandResult.changedOrFailed(
            ok ? "window close \(target.window.id.rawValue): closed" : "window close \(target.window.id.rawValue): failed",
            changed: ok
        )
        events.append(RoadieEvent(
            type: "window_close",
            scope: target.scope,
            details: [
                "windowID": String(target.window.id.rawValue),
                "bundleID": target.window.bundleID,
                "closed": String(ok),
            ]
        ))
        return result
    }

    /// Rassemble dans la stage active toutes les autres fenêtres gérées (hors plein écran natif et hors épingles)
    /// de la même application (`bundleID`) que la fenêtre ciblée ou active (Spec 160).
    public func gatherApp(windowID: WindowID? = nil) -> WindowCommandResult {
        let generation = PlacementGeneration.shared.next()
        let snapshot = service.snapshot()
        let anchor: ScopedWindowSnapshot?
        if let windowID {
            anchor = snapshot.windows.first { $0.window.id == windowID }
        } else {
            anchor = activeWindow(in: snapshot)
        }
        guard let anchor,
              let displayID = anchor.scope?.displayID
                ?? snapshot.displays.first(where: { $0.frame.cgRect.contains(anchor.window.frame.center) })?.id
                ?? snapshot.displays.first?.id,
              let display = snapshot.displays.first(where: { $0.id == displayID })
        else {
            return WindowCommandResult(message: "window gather-app: no active window", changed: false, outcome: .noOp)
        }
        let bundleID = anchor.window.bundleID
        guard !bundleID.isEmpty else {
            return WindowCommandResult(message: "window gather-app: unknown bundle", changed: false, outcome: .noOp)
        }

        var currentState = stageStore.state()
        let desktopID = currentState.currentDesktopID(for: displayID)
        let currentScope = currentState.scope(displayID: displayID, desktopID: desktopID)
        let targetScope = StageScope(displayID: displayID, desktopID: desktopID, stageID: currentScope.activeStageID)

        let candidates = snapshot.windows.filter { entry in
            entry.window.bundleID == bundleID
                && entry.window.id != anchor.window.id
                && entry.scope != targetScope
                && entry.window.isTileCandidate
                && entry.window.furniture?.isNativeFullscreen != true
                && currentState.pin(for: entry.window.id) == nil
        }
        guard !candidates.isEmpty else {
            return WindowCommandResult(
                message: "window gather-app \(bundleID): no other windows to gather",
                changed: false,
                outcome: .noOp
            )
        }

        let affectedScopes = Set([targetScope] + candidates.compactMap(\.scope))
        beginLayoutCommand("window.gather_app", scopes: affectedScopes)
        defer { finishLayoutCommand("window.gather_app", scopes: affectedScopes) }

        let defaultMode = service.effectiveConfig.tiling.defaultStrategy
        do {
            try stageStore.mutateChecked { state in
                let activeStageID = state.scope(displayID: displayID, desktopID: desktopID).activeStageID
                let activeStageScope = StageScope(displayID: displayID, desktopID: desktopID, stageID: activeStageID)
                // 1) Retirer toutes les fenêtres rassemblées de leurs stages et arbres d'origine.
                for entry in candidates {
                    let window = entry.window
                    for scopeIndex in state.scopes.indices {
                        state.scopes[scopeIndex].remove(windowID: window.id)
                    }
                    if let sourceScope = entry.scope,
                       sourceScope != activeStageScope,
                       let sourceTree = state.bspTree(for: sourceScope) {
                        state.setBSPTree(sourceTree.removing(window.id), for: sourceScope)
                    }
                    state.suppressRulePlacement(window: window)
                }
                // 2) Lire le scope cible après nettoyage, y affecter les fenêtres, puis persister le scope.
                var activeScope = state.scope(displayID: displayID, desktopID: desktopID)
                let usesTree = activeScope.stages.first(where: { $0.id == activeStageID })?.mode.usesTreeEngine ?? defaultMode.usesTreeEngine
                for entry in candidates {
                    activeScope.assign(
                        window: entry.window,
                        to: activeStageID,
                        insertionIndex: nil,
                        focusWindow: false,
                        defaultMode: defaultMode
                    )
                }
                state.update(activeScope)
                // 3) Mettre à jour l'arbre BSP cible après `state.update(activeScope)` (qui remplace le scope).
                if usesTree {
                    var tree = state.bspTree(for: activeStageScope) ?? .empty
                    let container = display.visibleFrame.cgRect
                    if !tree.contains(anchor.window.id) {
                        tree = tree.inserting(anchor.window.id, at: nil, side: .right, in: container)
                    }
                    for entry in candidates where !tree.contains(entry.window.id) {
                        tree = tree.inserting(entry.window.id, at: anchor.window.id, side: .right, in: container)
                    }
                    state.setBSPTree(tree, for: activeStageScope)
                }
            }
        } catch {
            return .persistenceFailure("window gather-app \(bundleID)", error)
        }

        var placement = CommandPlacement(layoutScopes: affectedScopes)
        for entry in candidates {
            if HiddenWindowPlacement.isHiddenOrLegacyOffscreen(entry.window.frame.cgRect, in: snapshot.displays)
                || !display.frame.cgRect.intersects(entry.window.frame.cgRect) {
                let rect = display.visibleFrame.cgRect
                placement.restoring[entry.window.id] = CGRect(
                    x: rect.minX + 40,
                    y: rect.minY + 40,
                    width: min(entry.window.frame.cgRect.width, rect.width),
                    height: min(entry.window.frame.cgRect.height, rect.height)
                ).integral
            }
        }
        let (_, applyResult) = service.applyCommandPlacement(
            placement,
            cause: "window.gather_app",
            generation: generation,
            events: events
        )
        _ = focusWindow(anchor.window)
        events.append(RoadieEvent(
            type: "window_gather_app",
            scope: targetScope,
            details: [
                "bundleID": bundleID,
                "anchorWindowID": String(anchor.window.id.rawValue),
                "gathered": String(candidates.count),
                "applied": String(applyResult.applied + applyResult.clamped),
            ]
        ))
        return WindowCommandResult(
            message: "window gather-app \(bundleID): gathered=\(candidates.count) applied=\(applyResult.applied + applyResult.clamped)",
            changed: true
        )
    }

    public func reset() -> WindowCommandResult {
        let generation = PlacementGeneration.shared.next()
        let snapshot = service.snapshot()
        guard let active = activeWindow(in: snapshot),
              let scope = active.scope,
              let display = snapshot.displays.first(where: { $0.id == scope.displayID })
        else {
            return WindowCommandResult(message: "window reset: no active window", changed: false, outcome: .noOp)
        }
        // La commande reste dans le scope de la fenêtre active : seul lui est soustrait au maintien.
        beginLayoutCommand("window.reset", scopes: [scope])
        defer { finishLayoutCommand("window.reset", scopes: [scope]) }

        do {
            try service.removeLayoutIntentChecked(scope: scope)
        } catch {
            return .persistenceFailure("window reset", error)
        }
        let zoomed = service.reset(active.window)
        Thread.sleep(forTimeInterval: 0.08)

        let visible = display.visibleFrame.cgRect
        let intermediate = centeredFrame(
            CGRect(
                x: active.window.frame.x,
                y: active.window.frame.y,
                width: min(active.window.frame.width, visible.width * 0.6),
                height: min(active.window.frame.height, visible.height * 0.6)
            ),
            in: visible
        )
        _ = service.setFrame(intermediate, of: active.window, generation: generation)
        Thread.sleep(forTimeInterval: 0.08)

        let updatedSnapshot = service.snapshot()
        let result = service.apply(service.applyPlan(from: updatedSnapshot, generation: generation), generation: generation)
        _ = focusWindow(active.window)
        return WindowCommandResult.changedOrFailed(
            "window reset: zoom=\(zoomed) attempted=\(result.attempted) applied=\(result.applied) clamped=\(result.clamped) failed=\(result.failed)",
            changed: result.failed == 0
        )
    }

    public func toggleFullscreen(windowID: WindowID? = nil) -> WindowCommandResult {
        toggleZoom(reservingRail: false, windowID: windowID)
    }

    /// O(w log w) avec restauration d'arbre ; validation sans arbre bornée à O(w²).
    public func toggleMaximize(windowID: WindowID? = nil) -> WindowCommandResult {
        toggleZoom(reservingRail: true, windowID: windowID)
    }

    /// O(w) à l'entrée ; la sortie réutilise le coût du plan du scope (O(w log w), validation O(w²)).
    private func toggleZoom(reservingRail: Bool, windowID: WindowID? = nil) -> WindowCommandResult {
        let generation = PlacementGeneration.shared.next()
        let snapshot = service.snapshot()
        let name = reservingRail ? "maximize" : "fullscreen"
        // La maximisation vise le focus réel, même si le plein écran natif le rend non tilable.
        // Le repli de sélection du plein écran historique reste inchangé.
        let preferredID = windowID ?? (reservingRail ? service.focusedWindowID() : nil)
        let selected = preferredID.flatMap { id in snapshot.windows.first { $0.window.id == id } }
        if reservingRail, let selected,
           selected.window.furniture?.isNativeFullscreen == true || selected.window.furniture?.isResizable == false {
            return WindowCommandResult(message: "toggle maximize: failed, refused native-fullscreen or non-resizable window", changed: false, outcome: .failed)
        }
        guard let active = preferredID == nil ? activeWindow(in: snapshot) : selected,
              let scope = active.scope,
              snapshot.state.activeScope(on: scope.displayID) == scope,
              let display = snapshot.displays.first(where: { $0.id == scope.displayID })
        else {
            return WindowCommandResult(message: "toggle \(name): no active window", changed: false, outcome: .noOp)
        }
        guard !reservingRail || (active.window.isTileCandidate
            && active.window.furniture?.isNativeFullscreen != true
            && active.window.furniture?.isResizable != false) else {
            return WindowCommandResult(message: "toggle maximize: failed, window unavailable for tiling", changed: false, outcome: .failed)
        }
        let cause = "window.toggle_\(name)"
        beginLayoutCommand(cause, scopes: [scope])
        defer { finishLayoutCommand(cause, scopes: [scope]) }

        let previous = service.commandLayoutIntent(scope: scope)
        let sameMode = previous?.zoomedWindowID == active.window.id
            && (previous?.zoomReservesRail == true) == reservingRail
        // Une fenêtre déjà grande entre aussi dans le mode explicite sans rail (SPEC-055).
        if sameMode {
            let plan: ApplyPlan
            do {
                plan = try service.restoreZoomLayoutIntentChecked(scope: scope, from: snapshot, generation: generation)
            } catch {
                return .persistenceFailure("toggle \(name) off", error)
            }
            let result = service.apply(plan, generation: generation)
            _ = focusWindow(active.window)
            return WindowCommandResult.changedOrFailed(
                "toggle \(name) off: commands=\(plan.commands.count) applied=\(result.applied) clamped=\(result.clamped) failed=\(result.failed)",
                changed: result.failed < result.attempted || plan.commands.isEmpty
            )
        }

        let target = reservingRail ? service.maximizedFrame(on: display) : display.visibleFrame.cgRect.integral
        guard let target, !target.isEmpty else {
            return WindowCommandResult(message: "toggle \(name) on: failed, refused frame", changed: false, outcome: .failed)
        }
        let original = previous?.restorePlacements ?? (previous?.zoomedWindowID == nil ? previous?.placements : nil)
            ?? Dictionary(uniqueKeysWithValues: snapshot.windows.compactMap { entry -> (WindowID, Rect)? in
                guard entry.scope == scope, entry.window.isTileCandidate,
                      !HiddenWindowPlacement.isHidden(entry.window.frame.cgRect, in: snapshot.displays) else { return nil }
                return (entry.window.id, entry.window.frame)
            })
        let hiding = siblingsToHide(of: active.window.id, in: scope, display: display, snapshot: snapshot)
        var placements = Dictionary(uniqueKeysWithValues: snapshot.windows.compactMap { entry -> (WindowID, Rect)? in
            guard entry.scope == scope, entry.window.isTileCandidate else { return nil }
            return (entry.window.id, entry.window.frame)
        })
        for (window, frame) in hiding { placements[window.id] = Rect(frame) }
        placements[active.window.id] = Rect(target)
        let ordered = previous.flatMap { $0.zoomedWindowID == nil ? nil : $0.windowIDs }
            ?? service.orderedWindowIDs(in: scope, from: snapshot)
        let zoomIntent = { (placements: [WindowID: Rect]) in
            LayoutIntent(scope: scope, windowIDs: ordered, placements: placements, source: .command,
                         zoomedWindowID: active.window.id, zoomReservesRail: reservingRail, restorePlacements: original)
        }
        // Décisions écrites avant tout effet AX (REL-021, R2-01) : cadre mémorisé d'abord, intent
        // ensuite. L'intent est la seule écriture que la maintenance applique : sans lui, rien ne
        // bouge ; s'il échoue, le cadre mémorisé reprend sa valeur.
        let storedIntent = service.effectiveIntentStore.intent(for: scope)
        do {
            try persistFrame(Rect(target), for: active.window, in: scope)
            do {
                try service.effectiveIntentStore.saveChecked(zoomIntent(placements))
            } catch {
                do {
                    try persistFrame(active.window.frame, for: active.window, in: scope)
                } catch let rollback {
                    throw PartialCommitError(cause: "\(error)", rollback: rollback)
                }
                throw error
            }
        } catch {
            return .persistenceFailure("toggle \(name) on", error)
        }
        let appliedFrame = service.setFrame(target, of: active.window, generation: generation)
        let incompatible = appliedFrame.map { frame in
            reservingRail && (!display.visibleFrame.cgRect.contains(frame) || frame.minX < target.minX || frame.isEmpty)
        } ?? false
        guard let appliedFrame, !incompatible else {
            // Refus de l'application : fenêtre, intent et cadre mémorisé reviennent à l'état
            // d'avant, sinon la maintenance réappliquerait le zoom refusé.
            // Retour arrière impossible : résultat partiel explicite (REL-021).
            if appliedFrame != nil { _ = service.setFrame(active.window.frame.cgRect, of: active.window, generation: generation) }
            var rollbackError: Error?
            do {
                if let storedIntent {
                    try service.effectiveIntentStore.saveChecked(storedIntent)
                } else {
                    try service.effectiveIntentStore.removeChecked(scope: scope)
                }
            } catch {
                rollbackError = error
            }
            do {
                try persistFrame(active.window.frame, for: active.window, in: scope)
            } catch {
                rollbackError = rollbackError ?? error
            }
            let refusal = appliedFrame == nil ? "toggle \(name) on: failed, refused frame"
                : "toggle maximize: failed, refused incompatible application minimum size"
            if let rollbackError {
                return .partial("\(refusal); partial, rollback failed: \(rollbackError)")
            }
            return .failure(refusal)
        }
        var applied = placements
        applied[active.window.id] = Rect(appliedFrame)
        for (window, frame) in hiding {
            // Masquage refusé : la voisine garde son cadre observé, comme avant l'écriture anticipée.
            applied[window.id] = service.setFrame(frame, of: window, generation: generation).map { Rect($0) } ?? window.frame
        }
        // Cadres ajustés par les applications : l'intent retient les cadres appliqués (T040).
        // Un échec ici reste sans conséquence : l'intent écrit est cohérent, l'observation le recale.
        if applied != placements {
            try? service.effectiveIntentStore.saveChecked(zoomIntent(applied))
        }
        if Rect(appliedFrame) != Rect(target) {
            try? persistFrame(Rect(appliedFrame), for: active.window, in: scope)
        }
        _ = focusWindow(active.window)
        return WindowCommandResult(message: "toggle \(name) on: changed=true", changed: true)
    }

    private func persistFrame(_ frame: Rect, for window: WindowSnapshot, in scopeID: StageScope) throws {
        var updated = window
        updated.frame = frame
        try stageStore.mutateChecked { state in
            var scope = state.scope(displayID: scopeID.displayID, desktopID: scopeID.desktopID)
            scope.updateFrame(window: updated)
            state.update(scope)
        }
    }

    /// Voisines visibles à cacher et leur cadre de masquage, sans effet AX. O(w·d).
    private func siblingsToHide(
        of fullscreenWindowID: WindowID,
        in scope: StageScope,
        display: DisplaySnapshot,
        snapshot: DaemonSnapshot
    ) -> [(WindowSnapshot, CGRect)] {
        snapshot.windows.compactMap { entry in
            guard entry.scope == scope,
                  entry.window.id != fullscreenWindowID,
                  entry.window.isTileCandidate,
                  entry.window.isOnScreen
            else { return nil }
            return (entry.window, HiddenWindowPlacement.frame(
                for: entry.window.frame.cgRect,
                on: display,
                among: snapshot.displays
            ))
        }
    }

    public func toggleNativeFullscreen() -> WindowCommandResult {
        beginLayoutCommand("window.toggle_native_fullscreen")
        defer { finishLayoutCommand("window.toggle_native_fullscreen") }
        let snapshot = service.snapshot()
        guard let active = activeWindow(in: snapshot) else {
            return WindowCommandResult(message: "toggle native-fullscreen: no active window", changed: false, outcome: .noOp)
        }
        let changed = service.toggleNativeFullscreen(active.window)
        _ = focusWindow(active.window)
        return WindowCommandResult.changedOrNoOp(
            "toggle native-fullscreen: changed=\(changed)",
            changed: changed
        )
    }

    public func sendToDisplay(_ displayIndex: Int) -> WindowCommandResult {
        let snapshot = service.snapshot()
        guard let active = activeWindow(in: snapshot) else {
            return WindowCommandResult(message: "no active window", changed: false, outcome: .noOp)
        }
        guard let display = snapshot.displays.first(where: { $0.index == displayIndex }) else {
            return WindowCommandResult(message: "unknown display \(displayIndex)", changed: false, outcome: .failed)
        }
        return send(active, to: display, focusMovedWindow: true)
    }

    public func send(
        windowID: WindowID,
        toDisplayID targetDisplayID: DisplayID,
        focusMovedWindow: Bool = true
    ) -> WindowCommandResult {
        let snapshot = service.snapshot()
        guard let entry = snapshot.windows.first(where: { $0.window.id == windowID }) else {
            return WindowCommandResult(message: "display \(targetDisplayID.rawValue): window unavailable", changed: false, outcome: .failed)
        }
        guard let display = snapshot.displays.first(where: { $0.id == targetDisplayID }) else {
            return WindowCommandResult(message: "display \(targetDisplayID.rawValue): display unavailable", changed: false, outcome: .failed)
        }
        return send(entry, to: display, focusMovedWindow: focusMovedWindow)
    }

    private func send(
        _ active: ScopedWindowSnapshot,
        to display: DisplaySnapshot,
        focusMovedWindow: Bool
    ) -> WindowCommandResult {
        beginLayoutCommand("window.display")
        defer { finishLayoutCommand("window.display") }
        let generation = PlacementGeneration.shared.next()
        let sourceScope = active.scope
        var initialStageState = stageStore.state()
        let targetDesktopID = initialStageState.currentDesktopID(for: display.id)
        let targetActiveStageID = initialStageState.scope(displayID: display.id, desktopID: targetDesktopID).activeStageID
        let targetScopeID = StageScope(
            displayID: display.id,
            desktopID: targetDesktopID,
            stageID: targetActiveStageID
        )
        if sourceScope == targetScopeID {
            return WindowCommandResult(message: "display \(display.index): already on target display", changed: false, outcome: .noOp)
        }

        // Frame de transfert : centrée sur l'écran cible. Elle n'est pas écrite seule (T212) : elle
        // entre dans le plan unique, comme géométrie de départ de la disposition cible.
        let transferFrame = centeredFrame(active.window.frame.cgRect, in: display.visibleFrame.cgRect)
        let transferredWindow = WindowSnapshot(
            id: active.window.id,
            pid: active.window.pid,
            appName: active.window.appName,
            bundleID: active.window.bundleID,
            title: active.window.title,
            frame: Rect(transferFrame),
            isOnScreen: active.window.isOnScreen,
            isTileCandidate: active.window.isTileCandidate,
            subrole: active.window.subrole,
            role: active.window.role,
            furniture: active.window.furniture
        )
        let removedPin: PersistentWindowPin?
        do {
            // Affectation écrite puis intents retirés ; si ce retrait échoue, l'affectation et le pin
            // reviennent (REL-021) : le refus annoncé ne laisse rien.
            removedPin = try service.commitStageTransfer(in: stageStore, { state -> PersistentWindowPin? in
                for scopeIndex in state.scopes.indices {
                    state.scopes[scopeIndex].remove(windowID: active.window.id)
                }
                var targetScope = state.scope(displayID: display.id, desktopID: targetDesktopID)
                targetScope.assign(window: transferredWindow, to: targetScope.activeStageID)
                state.update(targetScope)
                let pin = state.removePin(windowID: active.window.id)
                state.suppressRulePlacement(window: transferredWindow)
                return pin
            }, clearingIntentsOf: { _ in [sourceScope, targetScopeID].compactMap { $0 } })
        } catch {
            return .persistenceFailure("display \(display.index)", error)
        }

        // Plan unique (A15, T212) : fenêtre transférée, scope d'origine et scope cible dans une seule
        // écriture groupée, puis le focus.
        let observed = service.snapshot()
        let (plan, result) = service.applyCommandPlacement(
            CommandPlacement(restoring: [active.window.id: transferFrame], layoutScopes: Set([sourceScope, targetScopeID].compactMap { $0 })),
            snapshot: observed,
            cause: "window.display",
            generation: generation,
            events: events
        )
        let updatedSnapshot = snapshotByUpdating(windowID: active.window.id, to: Rect(transferFrame), in: observed)
        if shouldPersistCommandIntent(after: result) {
            do {
                try persistIntentsAfterDisplayMove(
                    from: updatedSnapshot,
                    targetScope: targetScopeID,
                    sourceScope: sourceScope,
                    plan: plan,
                    result: result
                )
            } catch {
                // Fenêtre déjà transférée : la commande a réussi. Sans intent, la maintenance
                // recalcule la disposition que le plan vient d'appliquer (REL-021).
                fputs("roadie: display \(display.index): layout intent not persisted: \(error)\n", stderr)
            }
        }
        if focusMovedWindow {
            _ = focusWindow(active.window)
        }
        events.append(RoadieEvent(
            type: "window_display",
            scope: targetScopeID,
            details: [
                "windowID": String(active.window.id.rawValue),
                "displayIndex": String(display.index),
                "focus": String(focusMovedWindow),
                "attempted": String(result.attempted),
                "applied": String(result.applied),
                "clamped": String(result.clamped),
                "failed": String(result.failed),
                "unpinned": String(removedPin != nil),
            ]
        ))
        appendManualPinRemovalEvent(removedPin, targetScope: targetScopeID)
        return WindowCommandResult.changedOrFailed(
            "display \(display.index): attempted=\(result.attempted) applied=\(result.applied) clamped=\(result.clamped) failed=\(result.failed)",
            changed: result.attempted > 0 && result.failed < result.attempted
        )
    }

    private func appendManualPinRemovalEvent(_ pin: PersistentWindowPin?, targetScope: StageScope) {
        guard let pin else { return }
        var details = pin.eventDetails
        details["reason"] = "manual_window_move"
        events.append(RoadieEvent(type: "window.pin_removed", scope: targetScope, details: details))
    }

    /// Sans `scopes`, la commande suspend tout le maintien ; avec, seulement ces scopes (FR-040).
    private func beginLayoutCommand(_ reason: String, scopes: Set<StageScope> = []) {
        commandActivity.markActive(reason: reason, scopes: scopes)
    }

    private func finishLayoutCommand(_ reason: String, scopes: Set<StageScope> = []) {
        commandActivity.finish(reason: reason, scopes: scopes)
    }

    private func shouldPersistCommandIntent(after result: ApplyResult) -> Bool {
        result.attempted > 0 && result.applied == result.attempted && result.clamped == 0 && result.failed == 0
    }

    private func appendWindowCommandEvent(
        verb: String,
        direction: Direction? = nil,
        snapshot: DaemonSnapshot,
        active: ScopedWindowSnapshot?,
        neighbor: ScopedWindowSnapshot? = nil,
        scope explicitScope: StageScope? = nil,
        result: WindowCommandResult,
        applyResult: ApplyResult? = nil,
        extra: [String: String] = [:]
    ) {
        let scope = explicitScope ?? active?.scope
        var details = extra
        details["verb"] = verb
        if let direction {
            details["direction"] = direction.rawValue
        }
        details["changed"] = String(result.changed)
        details["message"] = result.message
        if let active {
            details["activeWindowID"] = String(active.window.id.rawValue)
            details["activeApp"] = active.window.appName
        }
        if let neighbor {
            details["neighborWindowID"] = String(neighbor.window.id.rawValue)
            details["neighborApp"] = neighbor.window.appName
        }
        if let focusedID = snapshot.focusedWindowID {
            details["focusedWindowID"] = String(focusedID.rawValue)
        }
        if let applyResult {
            details["attempted"] = String(applyResult.attempted)
            details["applied"] = String(applyResult.applied)
            details["clamped"] = String(applyResult.clamped)
            details["failed"] = String(applyResult.failed)
        }
        events.append(RoadieEvent(type: "window.command", scope: scope, details: details))
    }

    private func persistIntentsAfterDisplayMove(
        from snapshot: DaemonSnapshot,
        targetScope: StageScope,
        sourceScope: StageScope?,
        plan: ApplyPlan,
        result: ApplyResult
    ) throws {
        let scopes = Set([targetScope, sourceScope].compactMap { $0 })
        guard !scopes.isEmpty else { return }
        let resultFrames = Dictionary(uniqueKeysWithValues: result.items.compactMap { item -> (WindowID, Rect)? in
            guard item.status != .failed else { return nil }
            return (item.windowID, item.actual ?? item.requested)
        })
        let plannedFrames = Dictionary(uniqueKeysWithValues: plan.commands.map { ($0.window.id, $0.frame) })

        for scope in scopes {
            guard let stage = snapshot.state.stage(scope: scope) else { continue }
            var placements = Dictionary(uniqueKeysWithValues: snapshot.windows.compactMap { entry -> (WindowID, Rect)? in
                guard entry.scope == scope, entry.window.isTileCandidate else { return nil }
                return (entry.window.id, entry.window.frame)
            })
            for (id, frame) in plannedFrames where placements[id] != nil {
                placements[id] = frame
            }
            for (id, frame) in resultFrames where placements[id] != nil {
                placements[id] = frame
            }
            let ordered = service.orderedWindowIDs(in: scope, from: snapshot, mode: stage.mode)
            guard Set(placements.keys) == Set(ordered) else { continue }
            try service.saveLayoutIntentChecked(scope: scope, windowIDs: ordered, placements: placements, source: .command)
        }
    }

    /// Fenêtre active et sa voisine dans `direction`. Mode arbre (T220) : voisine mesurée sur les
    /// frames de l'arbre projeté (A9), pas sur les frames physiques (une fenêtre qui déborde de sa
    /// feuille ne fausse pas le choix) ; frames physiques pour les autres modes, ou si la fenêtre
    /// active n'a pas encore de feuille. O(w).
    private func activeAndNeighbor(
        in snapshot: DaemonSnapshot,
        direction: Direction
    ) -> (active: ScopedWindowSnapshot, neighbor: ScopedWindowSnapshot)? {
        guard let active = activeWindow(in: snapshot), let scope = active.scope else { return nil }
        if let stage = snapshot.state.stage(scope: scope), stage.mode.allowsWindowOverlapOrOverflow {
            let liveByID = Dictionary(uniqueKeysWithValues: snapshot.windows.compactMap { entry -> (WindowID, ScopedWindowSnapshot)? in
                guard entry.scope == scope, entry.window.isTileCandidate else { return nil }
                return (entry.window.id, entry)
            })
            let ordered = stage.windowIDs.compactMap { liveByID[$0] }
            guard ordered.count > 1,
                  let idx = ordered.firstIndex(where: { $0.window.id == active.window.id })
            else { return nil }
            switch stage.mode {
            case .tabbed:
                let step = (direction == .left || direction == .up) ? -1 : 1
                let nextIdx = (idx + step + ordered.count) % ordered.count
                return (active, ordered[nextIdx])
            case .scrolling:
                if direction == .left, idx > 0 { return (active, ordered[idx - 1]) }
                if direction == .right, idx + 1 < ordered.count { return (active, ordered[idx + 1]) }
                return nil
            default:
                break
            }
        }
        if let context = activeTree(in: snapshot),
           let geometry = service.commandTreeGeometry(for: scope, tree: context.tree, in: snapshot) {
            let frames = geometry.frames(of: context.tree)
            if frames[active.window.id] != nil {
                guard let neighborID = treeNeighbor(of: active.window.id, direction: direction, frames: frames, tree: context.tree, absent: geometry.absent),
                      let neighbor = snapshot.windows.first(where: { $0.window.id == neighborID })
                else { return nil }
                return (active, neighbor)
            }
        }
        let activeFrame = active.window.frame.cgRect
        // Pre-compute score once per candidate to avoid O(2n) score calls in min(by:).
        let scored = snapshot.windows.compactMap { candidate -> (ScopedWindowSnapshot, CGFloat)? in
            guard candidate.scope == scope,
                  candidate.window.id != active.window.id,
                  candidate.window.isTileCandidate else { return nil }
            return (candidate, neighborScore(from: activeFrame, to: candidate.window.frame.cgRect, direction: direction))
        }
        guard let best = scored.min(by: { $0.1 < $1.1 }), best.1.isFinite else { return nil }
        return (active, best.0)
    }

    private func sendActiveToAdjacentDisplay(
        _ direction: Direction,
        from snapshot: DaemonSnapshot,
        verb: String
    ) -> WindowCommandResult {
        guard let active = activeWindow(in: snapshot),
              let display = activeDisplay(for: active, in: snapshot)
        else {
            return WindowCommandResult(message: "no neighbor \(direction.rawValue)", changed: false, outcome: .noOp)
        }
        guard let target = DisplayTopology.neighbor(from: display, direction: direction, in: snapshot.displays) else {
            return WindowCommandResult(message: "no neighbor \(direction.rawValue)", changed: false, outcome: .noOp)
        }
        let result = sendToDisplay(target.index)
        return WindowCommandResult(message: "\(verb) \(direction.rawValue): \(result.message)", changed: result.changed, outcome: result.outcome)
    }

    private func focusAdjacentDisplayWindow(_ direction: Direction, from snapshot: DaemonSnapshot) -> WindowCommandResult {
        guard let active = activeWindow(in: snapshot),
              let display = activeDisplay(for: active, in: snapshot)
        else {
            return WindowCommandResult(message: "no neighbor \(direction.rawValue)", changed: false, outcome: .noOp)
        }
        guard let targetDisplay = DisplayTopology.neighbor(from: display, direction: direction, in: snapshot.displays),
              let targetScope = snapshot.state.activeScope(on: targetDisplay.id)
        else {
            return WindowCommandResult(message: "display focus \(direction.rawValue): no display", changed: false, outcome: .noOp)
        }
        let candidates = snapshot.windows.filter {
            $0.scope == targetScope && $0.window.isTileCandidate
        }
        let rankedCandidates = candidates.compactMap { candidate -> (window: ScopedWindowSnapshot, score: CGFloat)? in
            let score = crossDisplayFocusScore(
                from: active.window.frame.cgRect,
                to: candidate.window.frame.cgRect,
                direction: direction
            )
            return score.isFinite ? (candidate, score) : nil
        }
        guard let target = rankedCandidates.min(by: { $0.score < $1.score })?.window else {
            let result = DisplayCommandService(service: service, store: stageStore, events: events).focus(direction)
            return WindowCommandResult(message: result.message, changed: result.changed, outcome: result.outcome)
        }

        do {
            try stageStore.mutateChecked { state in
                state.focusDisplay(targetDisplay.id)
                if var scope = state.scopes.first(where: { $0.displayID == targetScope.displayID && $0.desktopID == targetScope.desktopID }) {
                    scope.setFocusedWindow(target.window.id, in: targetScope.stageID)
                    state.update(scope)
                }
            }
        } catch {
            return .persistenceFailure("display focus \(direction.rawValue)", error)
        }

        let ok = focusWindow(target.window)
        return WindowCommandResult.changedOrFailed(
            ok ? "focused \(target.window.id) on display \(targetDisplay.index)" : "focus failed",
            changed: ok
        )
    }

    private func activeDisplay(for active: ScopedWindowSnapshot, in snapshot: DaemonSnapshot) -> DisplaySnapshot? {
        if let displayID = active.scope?.displayID,
           let display = snapshot.displays.first(where: { $0.id == displayID }) {
            return display
        }
        return snapshot.displays.first { $0.frame.cgRect.contains(active.window.frame.center) }
    }

    /// Écriture gardée en `mutate` (REL-021) : elle suit le focus déjà donné et ne fait que noter
    /// la fenêtre focalisée, que le snapshot suivant réécrit depuis le focus réel (followFocus).
    private func focusWindow(_ window: WindowSnapshot) -> Bool {
        let ok = service.focus(window)
        if ok {
            stageStore.mutate { state in
                guard let scope = state.stageScope(for: window.id) else { return }
                var persistentScope = state.scope(displayID: scope.displayID, desktopID: scope.desktopID)
                persistentScope.setFocusedWindow(window.id, in: scope.stageID)
                state.update(persistentScope)
                state.focusDisplay(scope.displayID)
            }
            mouseFollower.follow(window)
        }
        return ok
    }

    private func activeWindow(in snapshot: DaemonSnapshot) -> ScopedWindowSnapshot? {
        if let focusedID = service.focusedWindowID(),
           let focused = snapshot.windows.first(where: { entry in
               guard let scope = entry.scope else { return false }
               return entry.window.id == focusedID
                   && entry.window.isTileCandidate
                   && snapshot.state.activeScope(on: scope.displayID) == scope
           }) {
            return focused
        }

        for display in snapshot.displays {
            guard let scope = snapshot.state.activeScope(on: display.id),
                  let stage = snapshot.state.stage(scope: scope)
            else { continue }
            if let focusedID = stage.focusedWindowID,
               let focused = snapshot.windows.first(where: { $0.window.id == focusedID && $0.scope == scope && $0.window.isTileCandidate }) {
                return focused
            }
            if let lastID = stage.windowIDs.last,
               let last = snapshot.windows.first(where: { $0.window.id == lastID && $0.scope == scope && $0.window.isTileCandidate }) {
                return last
            }
        }

        return snapshot.windows.first { entry in
            guard let scope = entry.scope else { return false }
            return entry.window.isTileCandidate && snapshot.state.activeScope(on: scope.displayID) == scope
        }
    }

    private func structuralWarpPlan(
        in snapshot: DaemonSnapshot,
        scope: StageScope,
        active: WindowSnapshot,
        neighbor: WindowSnapshot,
        direction: Direction
    ) -> ApplyPlan? {
        guard let display = snapshot.displays.first(where: { $0.id == scope.displayID }) else { return nil }
        let scopedWindows = snapshot.windows
            .filter { $0.scope == scope && $0.window.isTileCandidate }
            .map(\.window)
        guard scopedWindows.count > 2 else {
            return service.applyPlan(
                from: snapshot,
                scope: scope,
                orderedWindowIDs: swappedWindowIDs(
                    in: snapshot,
                    scope: scope,
                    activeID: active.id,
                    neighborID: neighbor.id
                )
            )
        }
        let horizontal = direction == .left || direction == .right
        var targetGroup = scopedWindows
            .filter { isOnTargetSide($0.frame.cgRect, from: active.frame.cgRect, direction: direction) }
            .map(\.id)
        var sourceGroup = scopedWindows
            .filter { !isOnTargetSide($0.frame.cgRect, from: active.frame.cgRect, direction: direction) }
            .map(\.id)

        guard targetGroup.contains(neighbor.id), sourceGroup.contains(active.id) else { return nil }
        sourceGroup.removeAll { $0 == active.id }
        targetGroup.removeAll { $0 == active.id }

        if horizontal {
            insert(active.id, into: &targetGroup, sortedByYUsing: scopedWindows)
        } else {
            insert(active.id, into: &targetGroup, sortedByXUsing: scopedWindows)
        }
        guard !targetGroup.isEmpty, !sourceGroup.isEmpty else { return nil }

        let container = display.visibleFrame.cgRect
        let gap = CGFloat(service.innerGap())
        let targetFirst: Bool
        switch direction {
        case .left, .up: targetFirst = true
        case .right, .down: targetFirst = false
        }
        let firstGroup = targetFirst ? targetGroup : sourceGroup
        let secondGroup = targetFirst ? sourceGroup : targetGroup
        // Même découpe que l'aperçu de dépôt (PERF-003, O(n)).
        let rects = DropGroupGeometry.split(container, horizontally: horizontal, gap: gap, firstCount: firstGroup.count, secondCount: secondGroup.count)

        var placements: [WindowID: CGRect] = [:]
        placements.merge(DropGroupGeometry.planGroup(firstGroup, in: rects.first, horizontal: !horizontal, gap: gap)) { lhs, _ in lhs }
        placements.merge(DropGroupGeometry.planGroup(secondGroup, in: rects.second, horizontal: !horizontal, gap: gap)) { lhs, _ in lhs }

        let windowsByID = Dictionary(uniqueKeysWithValues: scopedWindows.map { ($0.id, $0) })
        let commands = placements.keys.sorted().compactMap { id -> ApplyCommand? in
            guard let window = windowsByID[id], let frame = placements[id], !framesAreClose(window.frame.cgRect, frame) else { return nil }
            return ApplyCommand(window: window, frame: Rect(frame.integral))
        }
        return commands.isEmpty ? nil : ApplyPlan(commands: commands)
    }

    private func persistIntentAfterCommand(
        from snapshot: DaemonSnapshot,
        scope: StageScope,
        orderedWindowIDs: [WindowID],
        plan: ApplyPlan,
        result: ApplyResult
    ) throws {
        var placements = Dictionary(uniqueKeysWithValues: snapshot.windows.compactMap { entry -> (WindowID, Rect)? in
            guard entry.scope == scope, entry.window.isTileCandidate else { return nil }
            return (entry.window.id, entry.window.frame)
        })
        for item in result.items {
            if item.status != .failed {
                placements[item.windowID] = item.actual ?? item.requested
            }
        }
        for command in plan.commands {
            if placements[command.window.id] == nil {
                placements[command.window.id] = command.frame
            }
        }
        guard Set(placements.keys) == Set(orderedWindowIDs) else { return }
        try service.saveLayoutIntentChecked(
            scope: scope,
            windowIDs: orderedWindowIDs.sorted(),
            placements: placements,
            source: .command
        )
    }

    private func snapshotByUpdating(windowID: WindowID, to frame: Rect, in snapshot: DaemonSnapshot) -> DaemonSnapshot {
        DaemonSnapshot(
            permissions: snapshot.permissions,
            displays: snapshot.displays,
            windows: snapshot.windows.map { entry in
                guard entry.window.id == windowID else { return entry }
                var window = entry.window
                window.frame = frame
                return ScopedWindowSnapshot(window: window, scope: entry.scope)
            },
            state: snapshot.state,
            focusedWindowID: snapshot.focusedWindowID
        )
    }

    private func swappedWindowIDs(
        in snapshot: DaemonSnapshot,
        scope: StageScope,
        activeID: WindowID,
        neighborID: WindowID
    ) -> [WindowID] {
        service.orderedWindowIDs(in: scope, from: snapshot).map { id in
            if id == activeID { return neighborID }
            if id == neighborID { return activeID }
            return id
        }
    }

    private func isOnTargetSide(_ candidate: CGRect, from active: CGRect, direction: Direction) -> Bool {
        switch direction {
        case .left: candidate.midX < active.midX
        case .right: candidate.midX > active.midX
        case .up: candidate.midY < active.midY
        case .down: candidate.midY > active.midY
        }
    }

    private func insert(_ id: WindowID, into group: inout [WindowID], sortedByYUsing windows: [WindowSnapshot]) {
        group.append(id)
        let frames = Dictionary(uniqueKeysWithValues: windows.map { ($0.id, $0.frame.cgRect) })
        group.sort { lhs, rhs in (frames[lhs]?.midY ?? 0) < (frames[rhs]?.midY ?? 0) }
    }

    private func insert(_ id: WindowID, into group: inout [WindowID], sortedByXUsing windows: [WindowSnapshot]) {
        group.append(id)
        let frames = Dictionary(uniqueKeysWithValues: windows.map { ($0.id, $0.frame.cgRect) })
        group.sort { lhs, rhs in (frames[lhs]?.midX ?? 0) < (frames[rhs]?.midX ?? 0) }
    }

    private func framesAreClose(_ lhs: CGRect, _ rhs: CGRect) -> Bool {
        abs(lhs.minX - rhs.minX) <= 1
            && abs(lhs.minY - rhs.minY) <= 1
            && abs(lhs.width - rhs.width) <= 1
            && abs(lhs.height - rhs.height) <= 1
    }

    private func neighborScore(from active: CGRect, to candidate: CGRect, direction: Direction) -> CGFloat {
        let dx = candidate.midX - active.midX
        let dy = candidate.midY - active.midY
        switch direction {
        case .left where dx < -1:
            return directionalScore(
                primaryDistance: max(0, active.minX - candidate.maxX),
                orthogonalDistance: abs(dy),
                orthogonalGap: rangeGap(active.minY...active.maxY, candidate.minY...candidate.maxY),
                overlapsOrthogonalAxis: rangesOverlap(active.minY...active.maxY, candidate.minY...candidate.maxY)
            )
        case .right where dx > 1:
            return directionalScore(
                primaryDistance: max(0, candidate.minX - active.maxX),
                orthogonalDistance: abs(dy),
                orthogonalGap: rangeGap(active.minY...active.maxY, candidate.minY...candidate.maxY),
                overlapsOrthogonalAxis: rangesOverlap(active.minY...active.maxY, candidate.minY...candidate.maxY)
            )
        case .up where dy < -1:
            return directionalScore(
                primaryDistance: max(0, active.minY - candidate.maxY),
                orthogonalDistance: abs(dx),
                orthogonalGap: rangeGap(active.minX...active.maxX, candidate.minX...candidate.maxX),
                overlapsOrthogonalAxis: rangesOverlap(active.minX...active.maxX, candidate.minX...candidate.maxX)
            )
        case .down where dy > 1:
            return directionalScore(
                primaryDistance: max(0, candidate.minY - active.maxY),
                orthogonalDistance: abs(dx),
                orthogonalGap: rangeGap(active.minX...active.maxX, candidate.minX...candidate.maxX),
                overlapsOrthogonalAxis: rangesOverlap(active.minX...active.maxX, candidate.minX...candidate.maxX)
            )
        default:
            return .infinity
        }
    }

    private func directionalScore(
        primaryDistance: CGFloat,
        orthogonalDistance: CGFloat,
        orthogonalGap: CGFloat,
        overlapsOrthogonalAxis: Bool
    ) -> CGFloat {
        if overlapsOrthogonalAxis {
            return primaryDistance + orthogonalDistance * 0.05
        }
        return 100_000 + orthogonalGap * 4 + primaryDistance + orthogonalDistance * 0.1
    }

    private func rangesOverlap(_ lhs: ClosedRange<CGFloat>, _ rhs: ClosedRange<CGFloat>) -> Bool {
        min(lhs.upperBound, rhs.upperBound) > max(lhs.lowerBound, rhs.lowerBound)
    }

    private func rangeGap(_ lhs: ClosedRange<CGFloat>, _ rhs: ClosedRange<CGFloat>) -> CGFloat {
        if rangesOverlap(lhs, rhs) { return 0 }
        if lhs.upperBound <= rhs.lowerBound { return rhs.lowerBound - lhs.upperBound }
        return lhs.lowerBound - rhs.upperBound
    }

    private func crossDisplayFocusScore(from active: CGRect, to candidate: CGRect, direction: Direction) -> CGFloat {
        guard isOnTargetSide(candidate, from: active, direction: direction) else { return .infinity }

        let primaryDistance: CGFloat
        let orthogonalDistance: CGFloat
        let orthogonalGap: CGFloat
        let orthogonalOverlap: CGFloat

        switch direction {
        case .left:
            primaryDistance = max(0, active.minX - candidate.maxX)
            orthogonalDistance = abs(active.midY - candidate.midY)
            orthogonalGap = rangeGap(active.minY...active.maxY, candidate.minY...candidate.maxY)
            orthogonalOverlap = rangeOverlap(active.minY...active.maxY, candidate.minY...candidate.maxY)
        case .right:
            primaryDistance = max(0, candidate.minX - active.maxX)
            orthogonalDistance = abs(active.midY - candidate.midY)
            orthogonalGap = rangeGap(active.minY...active.maxY, candidate.minY...candidate.maxY)
            orthogonalOverlap = rangeOverlap(active.minY...active.maxY, candidate.minY...candidate.maxY)
        case .up:
            primaryDistance = max(0, active.minY - candidate.maxY)
            orthogonalDistance = abs(active.midX - candidate.midX)
            orthogonalGap = rangeGap(active.minX...active.maxX, candidate.minX...candidate.maxX)
            orthogonalOverlap = rangeOverlap(active.minX...active.maxX, candidate.minX...candidate.maxX)
        case .down:
            primaryDistance = max(0, candidate.minY - active.maxY)
            orthogonalDistance = abs(active.midX - candidate.midX)
            orthogonalGap = rangeGap(active.minX...active.maxX, candidate.minX...candidate.maxX)
            orthogonalOverlap = rangeOverlap(active.minX...active.maxX, candidate.minX...candidate.maxX)
        }

        if orthogonalOverlap > 0 {
            return primaryDistance * 0.25 + orthogonalDistance * 0.05 - orthogonalOverlap * 0.1
        }
        return 100_000 + orthogonalGap * 4 + primaryDistance * 0.25 + orthogonalDistance * 0.1
    }

    private func rangeOverlap(_ lhs: ClosedRange<CGFloat>, _ rhs: ClosedRange<CGFloat>) -> CGFloat {
        max(0, min(lhs.upperBound, rhs.upperBound) - max(lhs.lowerBound, rhs.lowerBound))
    }

    private func resizedFrame(_ frame: CGRect, direction: Direction) -> CGRect {
        switch direction {
        case .left:
            return CGRect(x: frame.minX - resizeStep, y: frame.minY, width: frame.width + resizeStep, height: frame.height)
        case .right:
            return CGRect(x: frame.minX, y: frame.minY, width: frame.width + resizeStep, height: frame.height)
        case .up:
            return CGRect(x: frame.minX, y: frame.minY - resizeStep, width: frame.width, height: frame.height + resizeStep)
        case .down:
            return CGRect(x: frame.minX, y: frame.minY, width: frame.width, height: frame.height + resizeStep)
        }
    }

    private func centeredFrame(_ frame: CGRect, in container: CGRect) -> CGRect {
        let width = min(frame.width, container.width)
        let height = min(frame.height, container.height)
        return CGRect(
            x: container.midX - width / 2,
            y: container.midY - height / 2,
            width: width,
            height: height
        ).integral
    }

    // MARK: - Commandes d'onglets BSP (Spec 165)

    /// Fait défiler l'onglet actif (`delta = +1` suivant, `-1` précédent) dans le `.tabGroup`
    /// de la fenêtre active (en `spatialBsp`) ou dans la stage entière (en mode `.tabbed`).
    public func tabCycle(delta: Int) -> WindowCommandResult {
        guard delta != 0 else {
            return .noChange("tab cycle: zero delta")
        }
        let snapshot = service.snapshot()
        guard let active = activeWindow(in: snapshot), let scope = active.scope else {
            return .noChange("tab cycle: no active window")
        }
        if snapshot.state.stage(scope: scope)?.mode == .tabbed {
            return focus(delta > 0 ? .right : .left)
        }
        guard let context = activeTree(in: snapshot),
              let geometry = service.commandTreeGeometry(for: scope, tree: context.tree, in: snapshot)
        else {
            return .noChange("tab cycle: stage does not use tree engine")
        }
        let projected = context.tree.projected(excluding: geometry.absent)
        guard let cycled = projected.cyclingTab(from: active.window.id, delta: delta),
              let targetEntry = snapshot.windows.first(where: { $0.window.id == cycled.nextActive && $0.scope == scope })
        else {
            return .noChange("tab cycle: window is not in a tab group")
        }
        do {
            try stageStore.mutateChecked { state in
                let existing = state.bspTree(for: scope) ?? .empty
                state.setBSPTree(existing.selectingTab(cycled.nextActive), for: scope)
                var persistent = state.scope(displayID: scope.displayID, desktopID: scope.desktopID)
                persistent.setFocusedWindow(cycled.nextActive, in: scope.stageID)
                state.update(persistent)
            }
        } catch {
            return .persistenceFailure("tab cycle", error)
        }
        let ok = focusWindow(targetEntry.window)
        _ = service.snapshot(followFocus: false)
        let result = WindowCommandResult.changedOrFailed(
            ok ? "tab \(delta > 0 ? "next" : "prev"): focused \(cycled.nextActive.rawValue)" : "tab cycle: focus failed",
            changed: ok
        )
        appendWindowCommandEvent(
            verb: delta > 0 ? "tab_next" : "tab_prev",
            direction: delta > 0 ? .right : .left,
            snapshot: snapshot,
            active: active,
            neighbor: targetEntry,
            scope: scope,
            result: result
        )
        return result
    }

    /// Empile la fenêtre active (ou `windowID`) en onglet dans la tuile voisine dans `direction`.
    public func tabStack(_ direction: Direction, windowID: WindowID? = nil) -> WindowCommandResult {
        let generation = PlacementGeneration.shared.next()
        let snapshot = service.snapshot()
        let targetEntry: ScopedWindowSnapshot?
        if let windowID {
            targetEntry = snapshot.windows.first(where: { $0.window.id == windowID })
        } else {
            targetEntry = activeWindow(in: snapshot)
        }
        guard let active = targetEntry,
              let scope = active.scope,
              snapshot.state.stage(scope: scope)?.mode.usesTreeEngine == true
        else {
            return .noChange("tab stack \(direction.rawValue): no active BSP window")
        }
        let tree = stageStore.state().bspTree(for: scope) ?? .empty
        guard let geometry = service.commandTreeGeometry(for: scope, tree: tree, in: snapshot) else {
            return .noChange("tab stack \(direction.rawValue): no tree geometry")
        }
        let frames = geometry.frames(of: tree)
        guard let neighborID = treeNeighbor(of: active.window.id, direction: direction, frames: frames, tree: tree, absent: geometry.absent),
              let neighbor = snapshot.windows.first(where: { $0.window.id == neighborID })
        else {
            return .noChange("tab stack \(direction.rawValue): no neighbor")
        }
        let changed: Bool
        do {
            changed = try stageStore.mutateChecked { state -> Bool in
                let existing = state.bspTree(for: scope) ?? .empty
                let mutated = existing.stacking(active.window.id, onto: neighborID)
                guard mutated != existing else { return false }
                state.setBSPTree(mutated, for: scope)
                var persistent = state.scope(displayID: scope.displayID, desktopID: scope.desktopID)
                persistent.setFocusedWindow(active.window.id, in: scope.stageID)
                state.update(persistent)
                return true
            }
            if changed {
                try service.removeLayoutIntentChecked(scope: scope)
            }
        } catch {
            return .persistenceFailure("tab stack \(direction.rawValue)", error)
        }
        guard changed else {
            return .noChange("tab stack \(direction.rawValue): unchanged")
        }
        let tick = service.applyTreeScope(
            scope,
            cause: "window.tab.stack.\(direction.rawValue)",
            generation: generation,
            using: snapshot
        )
        _ = focusWindow(active.window)
        _ = service.snapshot(followFocus: false)
        let result = WindowCommandResult(
            message: "tab stack \(direction.rawValue): stacked \(active.window.id.rawValue) onto \(neighborID.rawValue) applied=\(tick.applied)",
            changed: true,
            outcome: .changed
        )
        appendWindowCommandEvent(
            verb: "tab_stack",
            direction: direction,
            snapshot: snapshot,
            active: active,
            neighbor: neighbor,
            scope: scope,
            result: result
        )
        return result
    }

    /// Détache la fenêtre active (ou `windowID`) de son `.tabGroup` dans sa propre tuile BSP.
    public func tabUnstack(_ direction: Direction? = nil, windowID: WindowID? = nil) -> WindowCommandResult {
        let generation = PlacementGeneration.shared.next()
        let snapshot = service.snapshot()
        let targetEntry: ScopedWindowSnapshot?
        if let windowID {
            targetEntry = snapshot.windows.first(where: { $0.window.id == windowID })
        } else {
            targetEntry = activeWindow(in: snapshot)
        }
        guard let active = targetEntry,
              let scope = active.scope,
              snapshot.state.stage(scope: scope)?.mode.usesTreeEngine == true
        else {
            return .noChange("tab unstack: no active BSP window")
        }
        let tree = stageStore.state().bspTree(for: scope) ?? .empty
        guard let geometry = service.commandTreeGeometry(for: scope, tree: tree, in: snapshot),
              tree.tabGroup(containing: active.window.id) != nil
        else {
            return .noChange("tab unstack: window is not in a tab group")
        }
        let changed: Bool
        do {
            changed = try stageStore.mutateChecked { state -> Bool in
                let existing = state.bspTree(for: scope) ?? .empty
                let mutated: BSPTree
                if let direction {
                    let side: BSPInsertionSide = (direction == .left || direction == .up) ? .left : .right
                    let wide = (direction == .left || direction == .right)
                    mutated = existing.unstacking(active.window.id, side: side, containerIsWide: wide)
                } else {
                    mutated = existing.unstacking(
                        active.window.id,
                        side: .right,
                        in: geometry.container,
                        innerGap: geometry.innerGap,
                        excluding: geometry.absent
                    )
                }
                guard mutated != existing else { return false }
                state.setBSPTree(mutated, for: scope)
                return true
            }
            if changed {
                try service.removeLayoutIntentChecked(scope: scope)
            }
        } catch {
            return .persistenceFailure("tab unstack", error)
        }
        guard changed else {
            return .noChange("tab unstack: unchanged")
        }
        let tick = service.applyTreeScope(
            scope,
            cause: "window.tab.unstack",
            generation: generation,
            using: snapshot
        )
        _ = focusWindow(active.window)
        _ = service.snapshot(followFocus: false)
        let result = WindowCommandResult(
            message: "tab unstack: detached \(active.window.id.rawValue) applied=\(tick.applied)",
            changed: true,
            outcome: .changed
        )
        appendWindowCommandEvent(
            verb: "tab_unstack",
            direction: direction ?? .right,
            snapshot: snapshot,
            active: active,
            scope: scope,
            result: result
        )
        return result
    }

    /// Déplace l'onglet actif d'un cran à gauche (`-1`) ou à droite (`+1`) dans sa barre d'onglets.
    public func tabMove(delta: Int) -> WindowCommandResult {
        guard delta != 0 else { return .noChange("tab move: zero delta") }
        let snapshot = service.snapshot()
        guard let active = activeWindow(in: snapshot), let scope = active.scope else {
            return .noChange("tab move: no active window")
        }
        if snapshot.state.stage(scope: scope)?.mode == .tabbed {
            return move(delta < 0 ? .left : .right)
        }
        guard snapshot.state.stage(scope: scope)?.mode.usesTreeEngine == true else {
            return .noChange("tab move: stage does not use tree engine")
        }
        let changed: Bool
        do {
            changed = try stageStore.mutateChecked { state -> Bool in
                let existing = state.bspTree(for: scope) ?? .empty
                let mutated = existing.reorderingTab(active.window.id, delta: delta)
                guard mutated != existing else { return false }
                state.setBSPTree(mutated, for: scope)
                return true
            }
        } catch {
            return .persistenceFailure("tab move", error)
        }
        if changed {
            _ = service.snapshot(followFocus: false)
        }
        return .changedOrNoOp(
            changed ? "tab move: reordered \(active.window.id.rawValue)" : "tab move: unchanged",
            changed: changed
        )
    }

    /// Place l'onglet `windowID` à l'index `toIndex` (réordonnancement par glisser horizontal dans la barre).
    public func tabReorder(windowID: WindowID, toIndex: Int) -> WindowCommandResult {
        let snapshot = service.snapshot()
        guard let entry = snapshot.windows.first(where: { $0.window.id == windowID }),
              let scope = entry.scope,
              let stage = snapshot.state.stage(scope: scope)
        else {
            return .noChange("tab reorder: unknown window")
        }
        let changed: Bool
        do {
            if stage.mode == .tabbed {
                changed = try stageStore.mutateChecked { state -> Bool in
                    var persistent = state.scope(displayID: scope.displayID, desktopID: scope.desktopID)
                    guard let idx = persistent.stages.firstIndex(where: { $0.id == scope.stageID }) else { return false }
                    let liveSet = Set(stage.windowIDs)
                    var liveMembers = persistent.stages[idx].members.filter { liveSet.contains($0.windowID) }
                    let hiddenMembers = persistent.stages[idx].members.filter { !liveSet.contains($0.windowID) }
                    guard let oldIdx = liveMembers.firstIndex(where: { $0.windowID == windowID }) else { return false }
                    let clamped = min(max(0, toIndex), liveMembers.count - 1)
                    guard clamped != oldIdx else { return false }
                    let moved = liveMembers.remove(at: oldIdx)
                    liveMembers.insert(moved, at: clamped)
                    persistent.stages[idx].members = liveMembers + hiddenMembers
                    state.update(persistent)
                    return true
                }
            } else if stage.mode.usesTreeEngine {
                changed = try stageStore.mutateChecked { state -> Bool in
                    let existing = state.bspTree(for: scope) ?? .empty
                    let mutated = existing.reorderingTab(windowID, toIndex: toIndex)
                    guard mutated != existing else { return false }
                    state.setBSPTree(mutated, for: scope)
                    return true
                }
            } else {
                changed = false
            }
        } catch {
            return .persistenceFailure("tab reorder", error)
        }
        if changed {
            _ = service.snapshot(followFocus: false)
        }
        return .changedOrNoOp(
            changed ? "tab reorder: moved \(windowID.rawValue) to \(toIndex)" : "tab reorder: unchanged",
            changed: changed
        )
    }

    /// Directions voisines disponibles pour empiler `windowID` dans son arbre BSP (utilisé par le menu contextuel).
    func availableTabStackDirections(for windowID: WindowID, in snapshot: DaemonSnapshot) -> [Direction] {
        guard let entry = snapshot.windows.first(where: { $0.window.id == windowID }),
              let scope = entry.scope,
              snapshot.state.stage(scope: scope)?.mode.usesTreeEngine == true
        else { return [] }
        let tree = stageStore.state().bspTree(for: scope) ?? .empty
        guard let geometry = service.commandTreeGeometry(for: scope, tree: tree, in: snapshot) else { return [] }
        let frames = geometry.frames(of: tree)
        return [.left, .right, .up, .down].filter { direction in
            treeNeighbor(of: windowID, direction: direction, frames: frames, tree: tree, absent: geometry.absent) != nil
        }
    }

}

private extension BSPEdge {
    var opposite: BSPEdge {
        switch self {
        case .left: .right
        case .right: .left
        case .up: .down
        case .down: .up
        }
    }
}

/// Géométrie de l'arbre d'un scope pour les commandes (SPEC-017 R12, A9, Spec 165) : conteneur,
/// marge intérieure, hauteur de barre d'onglets, minimums confirmés et feuilles absentes du snapshot.
struct CommandTreeGeometry {
    var container: CGRect
    var innerGap: CGFloat
    var absent: Set<WindowID>
    var tabBarHeight: CGFloat = 0
    var minimumSizes: [WindowID: CGSize] = [:]

    /// Frames de `tree` projeté sans les feuilles absentes. O(n).
    func frames(of tree: BSPTree) -> [WindowID: CGRect] {
        tree.projected(excluding: absent).place(
            in: container,
            innerGap: innerGap,
            tabBarHeight: tabBarHeight,
            minimumSizes: minimumSizes
        )
    }

    /// Emplacements des barres d'onglets des tuiles `.tabGroup` projetées. O(n).
    func tabBarFrames(of tree: BSPTree) -> [BSPTabBarPlacement] {
        tree.projected(excluding: absent).tabBarFrames(
            in: container,
            innerGap: innerGap,
            tabBarHeight: tabBarHeight,
            minimumSizes: minimumSizes
        )
    }
}

extension SnapshotService {
    /// Géométrie de l'arbre de `scope`, en lecture seule (ni l'arbre ni l'état ne sont écrits).
    /// Le conteneur est celui de la disposition de l'arbre (`treeContainer`). nil sans fenêtre
    /// placée dans le scope : les appelants retombent alors sur leur conteneur de repli.
    // O(w) - w = fenêtres du snapshot.
    func commandTreeGeometry(for scope: StageScope, tree: BSPTree, in snapshot: DaemonSnapshot) -> CommandTreeGeometry? {
        let live = snapshot.windows.compactMap { entry in
            entry.scope == scope && entry.window.isTileCandidate ? entry.window.id : nil
        }
        guard !live.isEmpty, let container = treeContainer(for: scope, in: snapshot) else { return nil }
        return CommandTreeGeometry(
            container: container,
            innerGap: CGFloat(innerGap()),
            absent: Set(tree.windowIDs).subtracting(live),
            tabBarHeight: CGFloat(effectiveConfig.tiling.tabbedBarHeight),
            minimumSizes: confirmedMinimumSizes(for: scope, in: snapshot)
        )
    }
}
