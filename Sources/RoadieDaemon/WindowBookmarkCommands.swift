import CoreGraphics
import Foundation
import RoadieAX
import RoadieCore

public struct WindowBookmarkCommandService {
    private let service: SnapshotService
    private let store: StageStore
    private let mouseFollower: MouseFollower
    private let events: EventLog
    private let isProcessAlive: (Int32) -> Bool

    public init(
        service: SnapshotService = SnapshotService(),
        store: StageStore = StageStore(),
        mouseFollower: MouseFollower = MouseFollower(),
        events: EventLog = EventLog(),
        isProcessAlive: @escaping (Int32) -> Bool = ProcessLiveness.isAlive
    ) {
        self.service = service
        self.store = store
        self.mouseFollower = mouseFollower
        self.events = events
        self.isProcessAlive = isProcessAlive
    }

    public func set(_ rawName: String) -> WindowCommandResult {
        let name = PersistentWindowBookmark.normalizedName(rawName)
        let snapshot = service.snapshot()
        guard let active = activeWindow(in: snapshot),
              let scope = active.scope
        else {
            return .noChange("bookmark set \(name): no active tiled window")
        }

        let bookmark: PersistentWindowBookmark
        do {
            bookmark = try store.mutateChecked { state in
                state.setBookmark(name: name, window: active.window, scope: scope)
            }
        } catch {
            return .persistenceFailure("bookmark set \(name)", error)
        }
        events.append(RoadieEvent(
            type: "window.bookmark_set",
            scope: scope,
            details: eventDetails(bookmark)
        ))
        return WindowCommandResult(message: "bookmark set \(name): window=\(active.window.id.rawValue)", changed: true)
    }

    public func focus(_ rawName: String) -> WindowCommandResult {
        let name = PersistentWindowBookmark.normalizedName(rawName)
        let generation = PlacementGeneration.shared.next()
        let snapshot = service.snapshot(followFocus: false)
        let state = store.state()
        guard let bookmark = state.bookmark(named: name) else {
            return .failure("bookmark focus \(name): not found")
        }
        guard let targetEntry = snapshot.windows.first(where: { $0.window.id == bookmark.windowID }) else {
            // Absente du snapshot n'est pas fermée : autre Space, fenêtre réduite, application qui
            // ne répond pas. Seul un processus mort le prouve ; sinon le signet reste et la purge
            // différée (délai de grâce) tranche (REL-028).
            guard processIsDead(owningWindow: bookmark.windowID, in: state) else {
                return .failure("bookmark focus \(name): failed - window not visible (other Space, minimized or unresponsive app), bookmark kept")
            }
            let removed: PersistentWindowBookmark?
            do {
                removed = try store.mutateChecked { $0.removeBookmark(named: name) }
            } catch {
                return .persistenceFailure("bookmark focus \(name)", error)
            }
            if let removed {
                events.append(RoadieEvent(
                    type: "window.bookmark_pruned",
                    scope: removed.scope,
                    details: eventDetails(removed).merging(["reason": "focus_stale"], uniquingKeysWith: { lhs, _ in lhs })
                ))
            }
            return WindowCommandResult(message: "bookmark focus \(name): stale bookmark removed", changed: true)
        }

        let targetScope = targetEntry.scope ?? state.stageScope(for: bookmark.windowID) ?? bookmark.scope
        return focusWindow(
            targetEntry.window,
            in: targetScope,
            snapshot: snapshot,
            generation: generation,
            label: "bookmark focus \(name)",
            cause: "bookmark.focus",
            eventPrefix: "window.bookmark",
            details: eventDetails(bookmark)
        )
    }

    /// Rejoint écran, bureau et stage de la fenêtre sans changer son appartenance.
    func focusWindow(
        _ target: WindowSnapshot,
        in targetScope: StageScope,
        snapshot: DaemonSnapshot,
        generation: UInt64,
        label: String,
        cause: String,
        eventPrefix: String,
        requireOwnership: Bool = false,
        prepareTarget: (() -> Bool)? = nil,
        details: [String: String]
    ) -> WindowCommandResult {
        guard let display = snapshot.displays.first(where: { $0.id == targetScope.displayID }) else {
            return .failure("\(label): display unavailable")
        }

        let windowsByID = Dictionary(uniqueKeysWithValues: snapshot.windows.map { ($0.window.id, $0.window) })
        // Préparé hors verrou : fenêtres visibles de l'écran (aucune E/S ni AX dans `mutate`).
        let visibleWindows = windowsByID.values.filter {
            display.frame.cgRect.contains($0.frame.center) && !HiddenWindowPlacement.isHiddenOrLegacyOffscreen($0.frame.cgRect, in: snapshot.displays)
        }

        // Scopes relus et modifiés sous verrou (FR-013) : les autres scopes ne sont pas écrasés.
        // Le bloc renvoie les membres utiles aux appels AX faits après la transaction.
        let plan: BookmarkFocusPlan
        do {
            plan = try store.mutateChecked { state -> BookmarkFocusPlan in
                if requireOwnership, state.stageScope(for: target.id) != targetScope { throw WindowFocusContextError.changed }
                var targetPersistentScope = state.scope(displayID: targetScope.displayID, desktopID: targetScope.desktopID)
                targetPersistentScope.ensureStage(targetScope.stageID)
                let previousDesktopID = state.currentDesktopID(for: display.id)
                var previousPersistentScope = state.scope(displayID: display.id, desktopID: previousDesktopID)
                let previousStageID = previousPersistentScope.activeStageID
                var result = BookmarkFocusPlan(
                    previousScope: StageScope(displayID: display.id, desktopID: previousDesktopID, stageID: previousStageID),
                    previousMembers: Set(previousPersistentScope.memberIDs(in: previousStageID)),
                    targetMembers: Set(targetPersistentScope.memberIDs(in: targetScope.stageID)),
                    // Capturé avant la mise à jour des frames : les membres reprennent leur frame mémorisée.
                    targetStage: targetPersistentScope.stages.first { $0.id == targetScope.stageID },
                    previousState: state
                )
                for window in visibleWindows {
                    if previousDesktopID == targetScope.desktopID {
                        targetPersistentScope.updateFrame(window: window)
                    } else {
                        previousPersistentScope.updateFrame(window: window)
                    }
                }
                targetPersistentScope.activeStageID = targetScope.stageID
                targetPersistentScope.setFocusedWindow(target.id, in: targetScope.stageID)
                if previousDesktopID != targetScope.desktopID {
                    state.update(previousPersistentScope)
                }
                state.switchDesktop(displayID: display.id, to: targetScope.desktopID)
                state.focusDisplay(display.id)
                state.update(targetPersistentScope)
                result.committedState = state
                return result
            }
        } catch WindowFocusContextError.changed {
            return .failure("\(label): context changed, retry selection")
        } catch {
            return .persistenceFailure(label, error)
        }

        func restoreFailure(_ reason: String) -> WindowCommandResult {
            // Ne revenir en arrière que si aucun autre écrivain n'a modifié l'état.
            // Les données d'une commande concurrente ne doivent jamais être écrasées.
            var rolledBack = false
            do {
                try store.mutateChecked { state in
                    guard let expected = plan.committedState, state == expected else { return }
                    state = plan.previousState
                    rolledBack = true
                }
            } catch { return .persistenceFailure(label, error) }
            service.invalidateSharedSnapshot()
            events.append(RoadieEvent(type: "\(eventPrefix)_focus_failed", scope: targetScope,
                details: details.merging(["reason": reason, "rolledBack": String(rolledBack)], uniquingKeysWith: { _, new in new })))
            return .failure("\(label): \(reason)")
        }
        if let prepareTarget, !prepareTarget() { return restoreFailure("application refused to unhide") }

        // Une fenêtre réduite peut manquer au relevé AX. La restaurer avant de calculer
        // son tuilage ; le relevé suivant fournit sa géométrie réelle, jamais celle de la carte.
        let restoreBeforeLayout = requireOwnership && windowsByID[target.id] == nil
        if restoreBeforeLayout, !service.focus(target) {
            // Invisible pour AX : souvent sur un autre espace, quand un plein écran natif est actif.
            let outcome = service.focusOnOtherSpace(target)
            events.append(RoadieEvent(type: "\(eventPrefix)_space_focus", scope: targetScope, details: details.merging([
                "opened": String(outcome.opened), "remote": String(outcome.remote), "focused": String(outcome.focused), "waitedMs": String(outcome.waitedMs)
            ], uniquingKeysWith: { _, new in new })))
            if !outcome.focused { return restoreFailure("restore failed") }
        }
        let refreshed = restoreBeforeLayout ? service.snapshot(followFocus: false) : nil
        let observedWindows = refreshed.map { Dictionary($0.windows.map { ($0.window.id, $0.window) }, uniquingKeysWith: { _, last in last }) } ?? windowsByID

        // Plan unique (A15, T212) : masquage de la stage quittée et disposition de la stage du signet
        // dans une seule écriture groupée, puis le focus.
        var placement = CommandPlacement(layoutScopes: [targetScope])
        if plan.previousScope != targetScope {
            for id in plan.previousMembers.subtracting(plan.targetMembers) {
                guard let window = windowsByID[id] else { continue }
                placement.hiding[id] = HiddenWindowPlacement.frame(for: window.frame.cgRect, on: display, among: snapshot.displays)
            }
        }
        // Mode arbre (A11, T094) : frames finales de l'arbre, sans restaurer les frames mémorisées.
        if plan.targetStage?.mode.usesTreeEngine != true {
            for member in plan.targetStage?.members ?? [] where observedWindows[member.windowID] != nil {
                placement.restoring[member.windowID] = member.frame.cgRect
            }
        }
        let (layoutPlan, result) = service.applyCommandPlacement(placement, snapshot: refreshed, cause: cause, generation: generation, events: events)
        let layoutAttempted = layoutPlan.commands.count
        let applied = result.applied + result.clamped
        // Si AX n'expose pas encore la fenêtre restaurée, remettre son cadre mémorisé.
        // Le producteur recalculera le tuilage dès qu'elle redevient lisible.
        var restoredMissing = true
        if restoreBeforeLayout, observedWindows[target.id] == nil,
           let member = plan.targetStage?.members.first(where: { $0.windowID == target.id }) {
            restoredMissing = service.setFrame(member.frame.cgRect, of: target, generation: generation) != nil
        }
        // Le placement peut avoir changé la fenêtre active ; confirmer le focus après celui-ci.
        let ok = service.focus(target)
        if ok {
            mouseFollower.follow(target)
            // Gardé en `mutate` (REL-021) : simple observation après le focus déjà donné, que le
            // snapshot suivant réécrit (`updateBookmarkObservation` à chaque passe).
            if !requireOwnership {
                store.mutate { $0.updateBookmarkObservation(window: target, scope: targetScope) }
            }
        }
        events.append(RoadieEvent(
            type: ok ? "\(eventPrefix)_focused" : "\(eventPrefix)_focus_failed",
            scope: targetScope,
            details: details.merging([
                "restored": String(applied),
                "layout": String(layoutAttempted)
            ], uniquingKeysWith: { lhs, _ in lhs })
        ))
        if requireOwnership, result.failed > 0 || !restoredMissing {
            return WindowCommandResult(message: "\(label): placement incomplete, failed=\(result.failed + (restoredMissing ? 0 : 1))",
                                       changed: ok, outcome: .failed)
        }
        return .changedOrFailed(
            ok
                ? "\(label): window=\(target.id.rawValue) restored=\(applied) layout=\(layoutAttempted)"
                : "\(label): focus failed",
            changed: ok
        )
    }

    public func clear(_ rawName: String) -> WindowCommandResult {
        let name = PersistentWindowBookmark.normalizedName(rawName)
        let removal: PersistentWindowBookmark?
        do {
            removal = try store.mutateChecked { $0.removeBookmark(named: name) }
        } catch {
            return .persistenceFailure("bookmark clear \(name)", error)
        }
        guard let removed = removal else {
            return .failure("bookmark clear \(name): not found")
        }
        events.append(RoadieEvent(
            type: "window.bookmark_removed",
            scope: removed.scope,
            details: eventDetails(removed)
        ))
        return WindowCommandResult(message: "bookmark clear \(name): window=\(removed.windowID.rawValue)", changed: true)
    }

    public func list() -> WindowCommandResult {
        let bookmarks = store.state().windowBookmarks
        guard !bookmarks.isEmpty else {
            return .noChange("NAME\tWINDOW\tAPP\tTITLE\tSCOPE\tSTATUS")
        }
        let liveWindowIDs = Set(service.snapshot(followFocus: false).windows.map(\.window.id))
        var lines = ["NAME\tWINDOW\tAPP\tTITLE\tSCOPE\tSTATUS"]
        for bookmark in bookmarks {
            let status = liveWindowIDs.contains(bookmark.windowID) ? "live" : "missing"
            lines.append("\(bookmark.name)\t\(bookmark.windowID.rawValue)\t\(bookmark.bundleID)\t\(bookmark.title)\t\(bookmark.scope)\t\(status)")
        }
        return .noChange(lines.joined(separator: "\n"))
    }

    /// Vrai si le pid mémorisé du membre de stage portant cette fenêtre n'existe plus.
    /// Sans membre ou sans pid connu (anciens fichiers) : pas de preuve, donc faux.
    /// O(scopes * stages * membres).
    private func processIsDead(owningWindow windowID: WindowID, in state: PersistentStageState) -> Bool {
        for scope in state.scopes {
            for stage in scope.stages {
                guard let member = stage.members.first(where: { $0.windowID == windowID }) else { continue }
                if let pid = member.pid { return !isProcessAlive(pid) }
            }
        }
        return false
    }

    private func activeWindow(in snapshot: DaemonSnapshot) -> ScopedWindowSnapshot? {
        if let focusedID = snapshot.focusedWindowID,
           let focused = snapshot.windows.first(where: { $0.window.id == focusedID && $0.window.isTileCandidate && $0.scope != nil }) {
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
        return snapshot.windows.first { $0.window.isTileCandidate && $0.scope != nil }
    }

    private func eventDetails(_ bookmark: PersistentWindowBookmark) -> [String: String] {
        [
            "name": bookmark.name,
            "windowID": String(bookmark.windowID.rawValue),
            "bundleID": bookmark.bundleID,
            "title": bookmark.title,
            "displayID": bookmark.scope.displayID.rawValue,
            "desktopID": String(bookmark.scope.desktopID.rawValue),
            "stageID": bookmark.scope.stageID.rawValue
        ]
    }
}

/// Résultat de la transaction de focus d'un signet, utilisé par les appels AX qui suivent.
private struct BookmarkFocusPlan {
    var previousScope: StageScope
    var previousMembers: Set<WindowID>
    var targetMembers: Set<WindowID>
    var targetStage: PersistentStage?
    var previousState: PersistentStageState
    var committedState: PersistentStageState?
}

private enum WindowFocusContextError: Error { case changed }
