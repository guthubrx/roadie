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

public struct WindowCommandResult: Equatable, Sendable {
    public var message: String
    public var changed: Bool

    public init(message: String, changed: Bool) {
        self.message = message
        self.changed = changed
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
        let result = WindowCommandResult(message: ok ? "focused \(pair.neighbor.window.id)" : "focus failed", changed: ok)
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

    public func focusBackAndForth() -> WindowCommandResult {
        let snapshot = service.snapshot()
        guard let active = activeWindow(in: snapshot), let scope = active.scope else {
            return WindowCommandResult(message: "focus back-and-forth: no active window", changed: false)
        }
        var state = stageStore.state()
        let persistentScope = state.scope(displayID: scope.displayID, desktopID: scope.desktopID)
        guard let stage = persistentScope.stages.first(where: { $0.id == scope.stageID }) else {
            return WindowCommandResult(message: "focus back-and-forth: no active stage", changed: false)
        }
        let targetID = stage.previousFocusedWindowID.flatMap { previous in
            snapshot.windows.first { $0.window.id == previous && $0.scope == scope }?.window.id
        } ?? stage.members.reversed().first { $0.windowID != active.window.id }?.windowID
        guard let targetID,
              let target = snapshot.windows.first(where: { $0.window.id == targetID && $0.scope == scope })?.window
        else {
            return WindowCommandResult(message: "focus back-and-forth: no previous window", changed: false)
        }
        let ok = focusWindow(target)
        return WindowCommandResult(message: ok ? "focus back-and-forth \(target.id.rawValue)" : "focus back-and-forth failed", changed: ok)
    }

    public func focus(windowID: WindowID) -> WindowCommandResult {
        let snapshot = service.snapshot()
        guard let target = snapshot.windows.first(where: { $0.window.id == windowID })?.window else {
            return WindowCommandResult(message: "focus: unknown window \(windowID.rawValue)", changed: false)
        }
        let ok = focusWindow(target)
        return WindowCommandResult(message: ok ? "focused \(target.id.rawValue)" : "focus failed", changed: ok)
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
                let result = WindowCommandResult(message: "resize \(direction.rawValue): window not in tree", changed: false)
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
                let pushed = tree.adjustingFence(of: id, edge: edge, to: target, in: geometry.container, innerGap: geometry.innerGap, excluding: geometry.absent)
                guard pushed == tree else { return pushed }
                return tree.adjustingFence(of: id, edge: edge.opposite, to: target, in: geometry.container, innerGap: geometry.innerGap, excluding: geometry.absent)
            }
        case .move, .warp:
            guard let geometry,
                  let neighborID = treeNeighbor(of: id, direction: direction, frames: frames),
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
        let changed = stageStore.mutate { state -> Bool in
            let existing = state.bspTree(for: scope) ?? .empty
            let mutated = mutation(existing)
            guard mutated != existing else { return false }
            state.setBSPTree(mutated, for: scope)
            return true
        }
        var tick: MaintenanceTick?
        if changed {
            service.removeLayoutIntent(scope: scope)
            tick = service.applyTreeScope(
                scope,
                cause: "window.\(verb.rawValue).\(direction.rawValue)",
                generation: generation
            )
        }
        _ = focusWindow(active.window)
        let result = WindowCommandResult(
            message: "\(verb.rawValue) \(direction.rawValue): tree changed=\(changed) applied=\(tick?.applied ?? 0) failed=\(tick?.failed ?? 0)",
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
    /// Égalité départagée par identifiant, pour un résultat déterministe. O(n).
    private func treeNeighbor(of id: WindowID, direction: Direction, frames: [WindowID: CGRect]) -> WindowID? {
        guard let origin = frames[id] else { return nil }
        let best = frames
            .filter { $0.key != id }
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
        service.removeLayoutIntent(scope: scope)
        let ordered = swappedWindowIDs(
            in: snapshot,
            scope: scope,
            activeID: pair.active.window.id,
            neighborID: pair.neighbor.window.id
        )
        let plan = service.applyPlan(
            from: snapshot,
            scope: scope,
            orderedWindowIDs: ordered,
            generation: generation
        )
        let result = service.apply(plan, generation: generation)
        if shouldPersistCommandIntent(after: result) {
            persistIntentAfterCommand(
                from: snapshot,
                scope: scope,
                orderedWindowIDs: ordered,
                plan: plan,
                result: result
            )
        }
        _ = focusWindow(pair.active.window)
        let commandResult = WindowCommandResult(
            message: "move \(direction.rawValue): attempted=\(result.attempted) applied=\(result.applied) clamped=\(result.clamped) failed=\(result.failed)",
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
        service.removeLayoutIntent(scope: scope)
        guard let plan = structuralWarpPlan(
            in: snapshot,
            scope: scope,
            active: pair.active.window,
            neighbor: pair.neighbor.window,
            direction: direction
        ) else {
            let result = WindowCommandResult(message: "warp \(direction.rawValue): no structural change", changed: false)
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
            persistIntentAfterCommand(
                from: snapshot,
                scope: scope,
                orderedWindowIDs: ordered,
                plan: plan,
                result: result
            )
        }
        _ = focusWindow(pair.active.window)
        let commandResult = WindowCommandResult(
            message: "warp \(direction.rawValue): attempted=\(result.attempted) applied=\(result.applied) clamped=\(result.clamped) failed=\(result.failed)",
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
            let result = WindowCommandResult(message: "no active window", changed: false)
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
        service.removeLayoutIntent(scope: scope)
        let resizeResult = service.apply(ApplyPlan(commands: [
            ApplyCommand(window: active.window, frame: Rect(frame)),
        ]), generation: generation)
        guard resizeResult.attempted > 0 && resizeResult.failed < resizeResult.attempted else {
            _ = focusWindow(active.window)
            let result = WindowCommandResult(
                message: "resize \(direction.rawValue): attempted=\(resizeResult.attempted) applied=\(resizeResult.applied) clamped=\(resizeResult.clamped) failed=\(resizeResult.failed)",
                changed: false
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
            persistIntentAfterCommand(
                from: updatedSnapshot,
                scope: scope,
                orderedWindowIDs: ordered,
                plan: plan,
                result: result
            )
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

    public func reset() -> WindowCommandResult {
        let generation = PlacementGeneration.shared.next()
        let snapshot = service.snapshot()
        guard let active = activeWindow(in: snapshot),
              let scope = active.scope,
              let display = snapshot.displays.first(where: { $0.id == scope.displayID })
        else {
            return WindowCommandResult(message: "window reset: no active window", changed: false)
        }
        // La commande reste dans le scope de la fenêtre active : seul lui est soustrait au maintien.
        beginLayoutCommand("window.reset", scopes: [scope])
        defer { finishLayoutCommand("window.reset", scopes: [scope]) }

        service.removeLayoutIntent(scope: scope)
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
        return WindowCommandResult(
            message: "window reset: zoom=\(zoomed) attempted=\(result.attempted) applied=\(result.applied) clamped=\(result.clamped) failed=\(result.failed)",
            changed: result.failed == 0
        )
    }

    public func toggleFullscreen() -> WindowCommandResult {
        toggleZoom(reservingRail: false)
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
            return WindowCommandResult(message: "toggle maximize: failed, refused native-fullscreen or non-resizable window", changed: false)
        }
        guard let active = preferredID == nil ? activeWindow(in: snapshot) : selected,
              let scope = active.scope,
              snapshot.state.activeScope(on: scope.displayID) == scope,
              let display = snapshot.displays.first(where: { $0.id == scope.displayID })
        else {
            return WindowCommandResult(message: "toggle \(name): no active window", changed: false)
        }
        guard !reservingRail || (active.window.isTileCandidate
            && active.window.furniture?.isNativeFullscreen != true
            && active.window.furniture?.isResizable != false) else {
            return WindowCommandResult(message: "toggle maximize: failed, window unavailable for tiling", changed: false)
        }
        let cause = "window.toggle_\(name)"
        beginLayoutCommand(cause, scopes: [scope])
        defer { finishLayoutCommand(cause, scopes: [scope]) }

        let previous = service.commandLayoutIntent(scope: scope)
        let sameMode = previous?.zoomedWindowID == active.window.id
            && (previous?.zoomReservesRail == true) == reservingRail
        let implicitFullscreen = !reservingRail && previous?.zoomedWindowID == nil
            && framesAreClose(active.window.frame.cgRect, display.visibleFrame.cgRect.integral)
        if sameMode || implicitFullscreen {
            let plan = service.restoreZoomLayoutIntent(scope: scope, from: snapshot, generation: generation)
            let result = service.apply(plan, generation: generation)
            _ = focusWindow(active.window)
            return WindowCommandResult(
                message: "toggle \(name) off: commands=\(plan.commands.count) applied=\(result.applied) clamped=\(result.clamped) failed=\(result.failed)",
                changed: result.failed < result.attempted || plan.commands.isEmpty
            )
        }

        let target = reservingRail ? service.maximizedFrame(on: display) : display.visibleFrame.cgRect.integral
        guard let target, !target.isEmpty,
              let appliedFrame = service.setFrame(target, of: active.window, generation: generation) else {
            return WindowCommandResult(message: "toggle \(name) on: failed, refused frame", changed: false)
        }
        if reservingRail && (!display.visibleFrame.cgRect.contains(appliedFrame)
            || appliedFrame.minX < target.minX || appliedFrame.isEmpty) {
            _ = service.setFrame(active.window.frame.cgRect, of: active.window, generation: generation)
            return WindowCommandResult(message: "toggle maximize: failed, refused incompatible application minimum size", changed: false)
        }
        let original = previous?.restorePlacements ?? (previous?.zoomedWindowID == nil ? previous?.placements : nil)
            ?? Dictionary(uniqueKeysWithValues: snapshot.windows.compactMap { entry -> (WindowID, Rect)? in
                guard entry.scope == scope, entry.window.isTileCandidate,
                      !HiddenWindowPlacement.isHidden(entry.window.frame.cgRect, in: snapshot.displays) else { return nil }
                return (entry.window.id, entry.window.frame)
            })
        let zoomedFrame = Rect(appliedFrame)
        persistFrame(zoomedFrame, for: active.window, in: scope)
        let hiddenFrames = hideSiblings(of: active.window.id, in: scope, display: display, snapshot: snapshot, generation: generation)
        var placements = Dictionary(uniqueKeysWithValues: snapshot.windows.compactMap { entry -> (WindowID, Rect)? in
            guard entry.scope == scope, entry.window.isTileCandidate else { return nil }
            return (entry.window.id, entry.window.frame)
        })
        placements.merge(hiddenFrames) { _, hidden in hidden }
        placements[active.window.id] = zoomedFrame
        let ordered = previous.flatMap { $0.zoomedWindowID == nil ? nil : $0.windowIDs }
            ?? service.orderedWindowIDs(in: scope, from: snapshot)
        service.effectiveIntentStore.save(LayoutIntent(
            scope: scope,
            windowIDs: ordered,
            placements: placements,
            source: .command,
            zoomedWindowID: active.window.id,
            zoomReservesRail: reservingRail,
            restorePlacements: original
        ))
        _ = focusWindow(active.window)
        return WindowCommandResult(message: "toggle \(name) on: changed=true", changed: true)
    }

    private func persistFrame(_ frame: Rect, for window: WindowSnapshot, in scopeID: StageScope) {
        var updated = window
        updated.frame = frame
        stageStore.mutate { state in
            var scope = state.scope(displayID: scopeID.displayID, desktopID: scopeID.desktopID)
            scope.updateFrame(window: updated)
            state.update(scope)
        }
    }

    private func hideSiblings(
        of fullscreenWindowID: WindowID,
        in scope: StageScope,
        display: DisplaySnapshot,
        snapshot: DaemonSnapshot,
        generation: UInt64
    ) -> [WindowID: Rect] {
        var hidden: [WindowID: Rect] = [:]
        for entry in snapshot.windows {
            guard entry.scope == scope,
                  entry.window.id != fullscreenWindowID,
                  entry.window.isTileCandidate,
                  entry.window.isOnScreen
            else { continue }
            let frame = HiddenWindowPlacement.frame(
                for: entry.window.frame.cgRect,
                on: display,
                among: snapshot.displays
            )
            if let applied = service.setFrame(frame, of: entry.window, generation: generation) {
                hidden[entry.window.id] = Rect(applied)
            }
        }
        return hidden
    }

    public func toggleNativeFullscreen() -> WindowCommandResult {
        beginLayoutCommand("window.toggle_native_fullscreen")
        defer { finishLayoutCommand("window.toggle_native_fullscreen") }
        let snapshot = service.snapshot()
        guard let active = activeWindow(in: snapshot) else {
            return WindowCommandResult(message: "toggle native-fullscreen: no active window", changed: false)
        }
        let changed = service.toggleNativeFullscreen(active.window)
        _ = focusWindow(active.window)
        return WindowCommandResult(
            message: "toggle native-fullscreen: changed=\(changed)",
            changed: changed
        )
    }

    public func sendToDisplay(_ displayIndex: Int) -> WindowCommandResult {
        let snapshot = service.snapshot()
        guard let active = activeWindow(in: snapshot) else {
            return WindowCommandResult(message: "no active window", changed: false)
        }
        guard let display = snapshot.displays.first(where: { $0.index == displayIndex }) else {
            return WindowCommandResult(message: "unknown display \(displayIndex)", changed: false)
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
            return WindowCommandResult(message: "display \(targetDisplayID.rawValue): window unavailable", changed: false)
        }
        guard let display = snapshot.displays.first(where: { $0.id == targetDisplayID }) else {
            return WindowCommandResult(message: "display \(targetDisplayID.rawValue): display unavailable", changed: false)
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
            return WindowCommandResult(message: "display \(display.index): already on target display", changed: false)
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
        let removedPin = stageStore.mutate { state -> PersistentWindowPin? in
            for scopeIndex in state.scopes.indices {
                state.scopes[scopeIndex].remove(windowID: active.window.id)
            }
            var targetScope = state.scope(displayID: display.id, desktopID: targetDesktopID)
            targetScope.assign(window: transferredWindow, to: targetScope.activeStageID)
            state.update(targetScope)
            let pin = state.removePin(windowID: active.window.id)
            state.suppressRulePlacement(window: transferredWindow)
            return pin
        }

        if let sourceScope {
            service.removeLayoutIntent(scope: sourceScope)
        }
        service.removeLayoutIntent(scope: targetScopeID)

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
            persistIntentsAfterDisplayMove(
                from: updatedSnapshot,
                targetScope: targetScopeID,
                sourceScope: sourceScope,
                plan: plan,
                result: result
            )
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
        return WindowCommandResult(
            message: "display \(display.index): attempted=\(result.attempted) applied=\(result.applied) clamped=\(result.clamped) failed=\(result.failed)",
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
    ) {
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
            service.saveLayoutIntent(scope: scope, windowIDs: ordered, placements: placements, source: .command)
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
        if let context = activeTree(in: snapshot),
           let frames = service.commandTreeGeometry(for: scope, tree: context.tree, in: snapshot)?.frames(of: context.tree),
           frames[active.window.id] != nil {
            guard let neighborID = treeNeighbor(of: active.window.id, direction: direction, frames: frames),
                  let neighbor = snapshot.windows.first(where: { $0.window.id == neighborID })
            else { return nil }
            return (active, neighbor)
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
            return WindowCommandResult(message: "no neighbor \(direction.rawValue)", changed: false)
        }
        guard let target = DisplayTopology.neighbor(from: display, direction: direction, in: snapshot.displays) else {
            return WindowCommandResult(message: "no neighbor \(direction.rawValue)", changed: false)
        }
        let result = sendToDisplay(target.index)
        return WindowCommandResult(
            message: "\(verb) \(direction.rawValue): \(result.message)",
            changed: result.changed
        )
    }

    private func focusAdjacentDisplayWindow(_ direction: Direction, from snapshot: DaemonSnapshot) -> WindowCommandResult {
        guard let active = activeWindow(in: snapshot),
              let display = activeDisplay(for: active, in: snapshot)
        else {
            return WindowCommandResult(message: "no neighbor \(direction.rawValue)", changed: false)
        }
        guard let targetDisplay = DisplayTopology.neighbor(from: display, direction: direction, in: snapshot.displays),
              let targetScope = snapshot.state.activeScope(on: targetDisplay.id)
        else {
            return WindowCommandResult(message: "display focus \(direction.rawValue): no display", changed: false)
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
            return WindowCommandResult(message: result.message, changed: result.changed)
        }

        stageStore.mutate { state in
            state.focusDisplay(targetDisplay.id)
            if var scope = state.scopes.first(where: { $0.displayID == targetScope.displayID && $0.desktopID == targetScope.desktopID }) {
                scope.setFocusedWindow(target.window.id, in: targetScope.stageID)
                state.update(scope)
            }
        }

        let ok = focusWindow(target.window)
        return WindowCommandResult(
            message: ok ? "focused \(target.window.id) on display \(targetDisplay.index)" : "focus failed",
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
        let rects = split(container, horizontally: horizontal, gap: gap, firstCount: firstGroup.count, secondCount: secondGroup.count)

        var placements: [WindowID: CGRect] = [:]
        placements.merge(planGroup(firstGroup, in: rects.first, horizontal: !horizontal, gap: gap)) { lhs, _ in lhs }
        placements.merge(planGroup(secondGroup, in: rects.second, horizontal: !horizontal, gap: gap)) { lhs, _ in lhs }

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
    ) {
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
        service.saveLayoutIntent(
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

    private func split(
        _ rect: CGRect,
        horizontally: Bool,
        gap: CGFloat,
        firstCount: Int,
        secondCount: Int
    ) -> (first: CGRect, second: CGRect) {
        let total = CGFloat(firstCount + secondCount)
        let ratio = total > 0 ? CGFloat(firstCount) / total : 0.5
        if horizontally {
            let usable = max(0, rect.width - gap)
            let firstWidth = floor(usable * ratio)
            return (
                CGRect(x: rect.minX, y: rect.minY, width: firstWidth, height: rect.height),
                CGRect(x: rect.minX + firstWidth + gap, y: rect.minY, width: usable - firstWidth, height: rect.height)
            )
        }

        let usable = max(0, rect.height - gap)
        let firstHeight = floor(usable * ratio)
        return (
            CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: firstHeight),
            CGRect(x: rect.minX, y: rect.minY + firstHeight + gap, width: rect.width, height: usable - firstHeight)
        )
    }

    private func planGroup(_ windowIDs: [WindowID], in rect: CGRect, horizontal: Bool, gap: CGFloat) -> [WindowID: CGRect] {
        guard let first = windowIDs.first else { return [:] }
        guard windowIDs.count > 1 else { return [first: rect.integral] }

        let parts = split(rect, horizontally: horizontal, gap: gap, firstCount: 1, secondCount: windowIDs.count - 1)
        var placements = [first: parts.first.integral]
        placements.merge(planGroup(Array(windowIDs.dropFirst()), in: parts.second, horizontal: !horizontal, gap: gap)) { lhs, _ in lhs }
        return placements
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

/// Géométrie de l'arbre d'un scope pour les commandes (SPEC-017 R12, A9) : conteneur, marge
/// intérieure et feuilles absentes du snapshot (gardées pendant leur grâce, non affichées).
struct CommandTreeGeometry {
    var container: CGRect
    var innerGap: CGFloat
    var absent: Set<WindowID>

    /// Frames de `tree` projeté sans les feuilles absentes. O(n).
    func frames(of tree: BSPTree) -> [WindowID: CGRect] {
        tree.projected(excluding: absent).place(in: container, innerGap: innerGap)
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
            absent: Set(tree.windowIDs).subtracting(live)
        )
    }
}
