import CoreGraphics
import Foundation
import RoadieAX
import RoadieCore

public struct WindowBookmarkCommandService {
    private let service: SnapshotService
    private let store: StageStore
    private let mouseFollower: MouseFollower
    private let events: EventLog

    public init(
        service: SnapshotService = SnapshotService(),
        store: StageStore = StageStore(),
        mouseFollower: MouseFollower = MouseFollower(),
        events: EventLog = EventLog()
    ) {
        self.service = service
        self.store = store
        self.mouseFollower = mouseFollower
        self.events = events
    }

    public func set(_ rawName: String) -> WindowCommandResult {
        let name = PersistentWindowBookmark.normalizedName(rawName)
        let snapshot = service.snapshot()
        guard let active = activeWindow(in: snapshot),
              let scope = active.scope
        else {
            return WindowCommandResult(message: "bookmark set \(name): no active tiled window", changed: false)
        }

        var state = store.state()
        let bookmark = state.setBookmark(name: name, window: active.window, scope: scope)
        store.save(state)
        events.append(RoadieEvent(
            type: "window.bookmark_set",
            scope: scope,
            details: eventDetails(bookmark)
        ))
        return WindowCommandResult(message: "bookmark set \(name): window=\(active.window.id.rawValue)", changed: true)
    }

    public func focus(_ rawName: String) -> WindowCommandResult {
        let name = PersistentWindowBookmark.normalizedName(rawName)
        let snapshot = service.snapshot(followFocus: false)
        var state = store.state()
        guard let bookmark = state.bookmark(named: name) else {
            return WindowCommandResult(message: "bookmark focus \(name): not found", changed: false)
        }
        guard let targetEntry = snapshot.windows.first(where: { $0.window.id == bookmark.windowID }) else {
            let removed = state.removeBookmark(named: name)
            store.save(state)
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

        var targetPersistentScope = state.scope(displayID: targetScope.displayID, desktopID: targetScope.desktopID)
        targetPersistentScope.ensureStage(targetScope.stageID)
        let previousDesktopID = state.currentDesktopID(for: display.id)
        let previousPersistentScope = state.scope(displayID: display.id, desktopID: previousDesktopID)
        let previousStageID = previousPersistentScope.activeStageID
        let previousScope = StageScope(displayID: display.id, desktopID: previousDesktopID, stageID: previousStageID)
        let previousMembers = Set(previousPersistentScope.memberIDs(in: previousStageID))
        let targetMembers = Set(targetPersistentScope.memberIDs(in: targetScope.stageID))
        let targetStage = targetPersistentScope.stages.first { $0.id == targetScope.stageID }
        let windowsByID = Dictionary(uniqueKeysWithValues: snapshot.windows.map { ($0.window.id, $0.window) })

        for window in windowsByID.values where display.frame.cgRect.contains(window.frame.center) && !isHidden(window.frame.cgRect) {
            if previousDesktopID == targetScope.desktopID {
                targetPersistentScope.updateFrame(window: window)
            } else {
                var previous = previousPersistentScope
                previous.updateFrame(window: window)
                state.update(previous)
            }
        }

        targetPersistentScope.activeStageID = targetScope.stageID
        targetPersistentScope.setFocusedWindow(bookmark.windowID, in: targetScope.stageID)
        state.switchDesktop(displayID: display.id, to: targetScope.desktopID)
        state.focusDisplay(display.id)
        state.update(targetPersistentScope)
        store.save(state)

        var applied = 0
        if previousScope != targetScope {
            for id in previousMembers.subtracting(targetMembers) {
                guard let window = windowsByID[id] else { continue }
                if service.setFrame(hiddenFrame(for: window.frame.cgRect, on: display, among: snapshot.displays), of: window) != nil {
                    applied += 1
                }
            }
        }

        for member in targetStage?.members ?? [] {
            guard let window = windowsByID[member.windowID] else { continue }
            if service.setFrame(member.frame.cgRect, of: window) != nil {
                applied += 1
            }
        }

        let layoutResult = service.apply(service.applyPlan(from: service.snapshot(followFocus: false)))
        let ok = service.focus(targetEntry.window)
        if ok {
            mouseFollower.follow(targetEntry.window)
            var updatedState = store.state()
            updatedState.updateBookmarkObservation(window: targetEntry.window, scope: targetScope)
            store.save(updatedState)
        }
        events.append(RoadieEvent(
            type: ok ? "window.bookmark_focused" : "window.bookmark_focus_failed",
            scope: targetScope,
            details: eventDetails(bookmark).merging([
                "restored": String(applied),
                "layout": String(layoutResult.attempted)
            ], uniquingKeysWith: { lhs, _ in lhs })
        ))
        return WindowCommandResult(
            message: ok
                ? "bookmark focus \(name): window=\(bookmark.windowID.rawValue) restored=\(applied) layout=\(layoutResult.attempted)"
                : "bookmark focus \(name): focus failed",
            changed: ok
        )
    }

    public func clear(_ rawName: String) -> WindowCommandResult {
        let name = PersistentWindowBookmark.normalizedName(rawName)
        var state = store.state()
        guard let removed = state.removeBookmark(named: name) else {
            return WindowCommandResult(message: "bookmark clear \(name): not found", changed: false)
        }
        store.save(state)
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

    private func hiddenFrame(for frame: CGRect, on display: DisplaySnapshot, among displays: [DisplaySnapshot]) -> CGRect {
        let displayOffset = displays.firstIndex(where: { $0.id == display.id }) ?? 0
        let offset = CGFloat(200 + displayOffset * 40)
        let x = display.frame.x + display.frame.width + offset
        let y = display.frame.y + display.frame.height + offset
        return CGRect(x: x, y: y, width: max(frame.width, 80), height: max(frame.height, 60)).integral
    }

    private func isHidden(_ frame: CGRect) -> Bool {
        frame.origin.x > 9_000 || frame.origin.y > 9_000
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
