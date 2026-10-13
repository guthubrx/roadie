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
            return WindowCommandResult(message: "bookmark set \(name): no active tiled window", changed: false)
        }

        let bookmark = store.mutate { state in
            state.setBookmark(name: name, window: active.window, scope: scope)
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
            return WindowCommandResult(message: "bookmark focus \(name): not found", changed: false)
        }
        guard let targetEntry = snapshot.windows.first(where: { $0.window.id == bookmark.windowID }) else {
            // Absente du snapshot n'est pas fermée : autre Space, fenêtre réduite, application qui
            // ne répond pas. Seul un processus mort le prouve ; sinon le signet reste et la purge
            // différée (délai de grâce) tranche (REL-028).
            guard processIsDead(owningWindow: bookmark.windowID, in: state) else {
                return WindowCommandResult(
                    message: "bookmark focus \(name): window not visible (other Space, minimized or unresponsive app), bookmark kept",
                    changed: false
                )
            }
            let removed = store.mutate { $0.removeBookmark(named: name) }
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
        guard let display = snapshot.displays.first(where: { $0.id == targetScope.displayID }) else {
            return WindowCommandResult(message: "bookmark focus \(name): display unavailable", changed: false)
        }

        let windowsByID = Dictionary(uniqueKeysWithValues: snapshot.windows.map { ($0.window.id, $0.window) })
        // Préparé hors verrou : fenêtres visibles de l'écran (aucune E/S ni AX dans `mutate`).
        let visibleWindows = windowsByID.values.filter {
            display.frame.cgRect.contains($0.frame.center) && !HiddenWindowPlacement.isHiddenOrLegacyOffscreen($0.frame.cgRect, in: snapshot.displays)
        }

        // Scopes relus et modifiés sous verrou (FR-013) : les autres scopes ne sont pas écrasés.
        // Le bloc renvoie les membres utiles aux appels AX faits après la transaction.
        let plan = store.mutate { state -> BookmarkFocusPlan in
            var targetPersistentScope = state.scope(displayID: targetScope.displayID, desktopID: targetScope.desktopID)
            targetPersistentScope.ensureStage(targetScope.stageID)
            let previousDesktopID = state.currentDesktopID(for: display.id)
            var previousPersistentScope = state.scope(displayID: display.id, desktopID: previousDesktopID)
            let previousStageID = previousPersistentScope.activeStageID
            let result = BookmarkFocusPlan(
                previousScope: StageScope(displayID: display.id, desktopID: previousDesktopID, stageID: previousStageID),
                previousMembers: Set(previousPersistentScope.memberIDs(in: previousStageID)),
                targetMembers: Set(targetPersistentScope.memberIDs(in: targetScope.stageID)),
                // Capturé avant la mise à jour des frames : les membres reprennent leur frame mémorisée.
                targetStage: targetPersistentScope.stages.first { $0.id == targetScope.stageID }
            )
            for window in visibleWindows {
                if previousDesktopID == targetScope.desktopID {
                    targetPersistentScope.updateFrame(window: window)
                } else {
                    previousPersistentScope.updateFrame(window: window)
                }
            }
            targetPersistentScope.activeStageID = targetScope.stageID
            targetPersistentScope.setFocusedWindow(bookmark.windowID, in: targetScope.stageID)
            if previousDesktopID != targetScope.desktopID {
                state.update(previousPersistentScope)
            }
            state.switchDesktop(displayID: display.id, to: targetScope.desktopID)
            state.focusDisplay(display.id)
            state.update(targetPersistentScope)
            return result
        }

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
            for member in plan.targetStage?.members ?? [] where windowsByID[member.windowID] != nil {
                placement.restoring[member.windowID] = member.frame.cgRect
            }
        }
        let (layoutPlan, result) = service.applyCommandPlacement(placement, cause: "bookmark.focus", generation: generation, events: events)
        let layoutAttempted = layoutPlan.commands.count
        let applied = result.applied + result.clamped
        let ok = service.focus(targetEntry.window)
        if ok {
            mouseFollower.follow(targetEntry.window)
            store.mutate { $0.updateBookmarkObservation(window: targetEntry.window, scope: targetScope) }
        }
        events.append(RoadieEvent(
            type: ok ? "window.bookmark_focused" : "window.bookmark_focus_failed",
            scope: targetScope,
            details: eventDetails(bookmark).merging([
                "restored": String(applied),
                "layout": String(layoutAttempted)
            ], uniquingKeysWith: { lhs, _ in lhs })
        ))
        return WindowCommandResult(
            message: ok
                ? "bookmark focus \(name): window=\(bookmark.windowID.rawValue) restored=\(applied) layout=\(layoutAttempted)"
                : "bookmark focus \(name): focus failed",
            changed: ok
        )
    }

    public func clear(_ rawName: String) -> WindowCommandResult {
        let name = PersistentWindowBookmark.normalizedName(rawName)
        guard let removed = store.mutate({ $0.removeBookmark(named: name) }) else {
            return WindowCommandResult(message: "bookmark clear \(name): not found", changed: false)
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
            return WindowCommandResult(message: "NAME\tWINDOW\tAPP\tTITLE\tSCOPE\tSTATUS", changed: false)
        }
        let liveWindowIDs = Set(service.snapshot(followFocus: false).windows.map(\.window.id))
        var lines = ["NAME\tWINDOW\tAPP\tTITLE\tSCOPE\tSTATUS"]
        for bookmark in bookmarks {
            let status = liveWindowIDs.contains(bookmark.windowID) ? "live" : "missing"
            lines.append("\(bookmark.name)\t\(bookmark.windowID.rawValue)\t\(bookmark.bundleID)\t\(bookmark.title)\t\(bookmark.scope)\t\(status)")
        }
        return WindowCommandResult(message: lines.joined(separator: "\n"), changed: false)
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
}
