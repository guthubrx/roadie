import Foundation
import RoadieAX
import RoadieCore

enum WindowSwitcherAction: String, CaseIterable {
    case close
    case minimize
    case hideApp
    case quitApp
    case maximize
    case fullscreen
}

struct WindowSwitcherService {
    private static let axApplicationLimit = 16

    private struct Draft {
        var window: WindowSnapshot
        let scope: StageScope
        let displayName: String
        let desktopName: String
        let stageName: String
    }

    private let service: SnapshotService

    init(service: SnapshotService = SnapshotService()) {
        self.service = service
    }

    @MainActor
    func load() async -> (entries: [WindowSwitcherEntry], context: WindowSwitcherContext) {
        guard let snapshot = await service.readerSnapshot(followFocus: false) else {
            return ([], WindowSwitcherContext())
        }
        let persisted = service.effectiveStageStore.state()
        let drafts = collectDrafts(snapshot: snapshot, persisted: persisted)
        let axStates = await accessibilityStates(for: drafts)
        let entries = drafts.map { draft -> WindowSwitcherEntry in
            let ax = axStates[draft.window.id]
            var window = draft.window
            if let appName = ax?.appName { window.appName = appName }
            if let title = ax?.title, !title.isEmpty { window.title = title }
            return WindowSwitcherEntry(
                window: window,
                scope: draft.scope,
                displayName: draft.displayName,
                desktopName: draft.desktopName,
                stageName: draft.stageName,
                isMinimized: ax?.isMinimized ?? false,
                isHidden: ax?.isHidden ?? false,
                isFullscreen: ax?.isFullscreen ?? window.furniture?.isNativeFullscreen ?? false
            )
        }
        return (entries, context(snapshot: snapshot))
    }

    func activate(_ entry: WindowSwitcherEntry) -> WindowCommandResult {
        let generation = PlacementGeneration.shared.next()
        let snapshot = service.snapshot(followFocus: false)
        guard ProcessLiveness.isAlive(entry.window.pid) else {
            return .failure("switcher activate: application not running")
        }
        guard isStillOpen(entry, in: snapshot) else {
            return .failure("switcher activate: window \(entry.id.rawValue) no longer exists")
        }
        let store = service.effectiveStageStore
        guard let owner = store.state().stageScope(for: entry.id) else {
            return .failure("switcher activate: window \(entry.id.rawValue) has no owner stage")
        }
        if entry.isHidden {
            guard WindowSwitcherWindowAccess.unhideApplication(pid: entry.window.pid, bundleID: entry.window.bundleID) == .performed else {
                return .failure("switcher activate: application refused to unhide")
            }
        }
        let target = snapshot.windows.first { $0.window.id == entry.id }?.window ?? entry.window
        return WindowBookmarkCommandService(service: service, store: store).focusWindow(
            target,
            in: owner,
            snapshot: snapshot,
            generation: generation,
            label: "switcher activate",
            cause: "switcher.activate",
            eventPrefix: "window.switcher",
            details: [
                "windowID": String(entry.id.rawValue),
                "bundleID": entry.window.bundleID,
                "title": entry.window.title,
                "displayID": owner.displayID.rawValue,
                "desktopID": String(owner.desktopID.rawValue),
                "stageID": owner.stageID.rawValue
            ]
        )
    }

    func perform(_ action: WindowSwitcherAction, on entry: WindowSwitcherEntry) -> WindowCommandResult {
        let snapshot = service.snapshot(followFocus: false)
        let label = "switcher \(action.rawValue): window=\(entry.id.rawValue)"
        guard ProcessLiveness.isAlive(entry.window.pid), isStillOpen(entry, in: snapshot) else {
            return .failure("\(label): window no longer exists")
        }
        let pid = entry.window.pid
        switch action {
        case .close:
            return report(WindowSwitcherWindowAccess.close(entry.id, pid: pid), label: label)
        case .minimize:
            return report(WindowSwitcherWindowAccess.minimize(entry.id, pid: pid), label: label)
        case .hideApp:
            return report(WindowSwitcherWindowAccess.hideApplication(pid: pid, bundleID: entry.window.bundleID), label: label)
        case .quitApp:
            return report(WindowSwitcherWindowAccess.quitApplication(pid: pid, bundleID: entry.window.bundleID), label: label)
        case .maximize, .fullscreen:
            let activation = activate(entry)
            guard activation.changed else { return activation }
            let commands = WindowCommandService(service: service)
            return action == .maximize ? commands.toggleMaximize(windowID: entry.id) : commands.toggleFullscreen(windowID: entry.id)
        }
    }

    private func collectDrafts(snapshot: DaemonSnapshot, persisted: PersistentStageState) -> [Draft] {
        var drafts: [Draft] = []
        var seen = Set<WindowID>()
        for scoped in snapshot.windows {
            guard let scope = scoped.scope else { continue }
            seen.insert(scoped.window.id)
            drafts.append(draft(window: scoped.window, scope: scope, snapshot: snapshot, persisted: persisted))
        }
        // Absente de l'écran n'est pas fermée : une fenêtre persistée reste listée si l'inventaire CG
        // confirme encore son pid (autre bureau, réduite, application cachée).
        let inventory = snapshot.existingWindowPIDs ?? [:]
        for scope in persisted.scopes {
            for stage in scope.stages {
                let stageScope = StageScope(displayID: scope.displayID, desktopID: scope.desktopID, stageID: stage.id)
                for member in stage.members where member.confirmedClosedAt == nil && !seen.contains(member.windowID) {
                    guard let pid = member.pid, inventory[member.windowID] == pid else { continue }
                    seen.insert(member.windowID)
                    let window = WindowSnapshot(
                        id: member.windowID,
                        pid: pid,
                        appName: member.bundleID,
                        bundleID: member.bundleID,
                        title: member.title,
                        frame: member.frame,
                        isOnScreen: false,
                        isTileCandidate: false
                    )
                    drafts.append(draft(window: window, scope: stageScope, snapshot: snapshot, persisted: persisted))
                }
            }
        }
        return drafts
    }

    private func draft(window: WindowSnapshot, scope: StageScope, snapshot: DaemonSnapshot, persisted: PersistentStageState) -> Draft {
        Draft(
            window: window,
            scope: scope,
            displayName: snapshot.displays.first { $0.id == scope.displayID }?.name ?? "",
            desktopName: persisted.desktopLabels.first { $0.displayID == scope.displayID && $0.desktopID == scope.desktopID }?.label
                ?? "Bureau \(scope.desktopID.rawValue)",
            stageName: snapshot.state.stage(scope: scope)?.name ?? ""
        )
    }

    /// Lecture AX seulement pour les fenêtres hors écran, un appel par application, hors MainActor.
    private func accessibilityStates(for drafts: [Draft]) async -> [WindowID: WindowSwitcherAXState] {
        let byPID = Dictionary(grouping: drafts.filter { !$0.window.isOnScreen }) { $0.window.pid }
        let selected = byPID.keys.sorted().prefix(Self.axApplicationLimit)
        return await withTaskGroup(of: [WindowID: WindowSwitcherAXState].self) { group in
            for pid in selected {
                let ids = Set(byPID[pid, default: []].map(\.window.id))
                group.addTask {
                    await Task.detached(priority: .utility) {
                        WindowSwitcherWindowAccess.states(pid: pid, windowIDs: ids)
                    }.value
                }
            }
            var merged: [WindowID: WindowSwitcherAXState] = [:]
            for await part in group {
                merged.merge(part) { _, new in new }
            }
            return merged
        }
    }

    private func context(snapshot: DaemonSnapshot) -> WindowSwitcherContext {
        let focused = snapshot.windows.first { $0.window.id == snapshot.focusedWindowID }
        let scope = focused?.scope ?? snapshot.displays.lazy.compactMap { snapshot.state.activeScope(on: $0.id) }.first
        return WindowSwitcherContext(
            focusedWindowID: snapshot.focusedWindowID,
            displayID: scope?.displayID,
            desktopID: scope?.desktopID,
            stageID: scope?.stageID,
            bundleID: focused?.window.bundleID
        )
    }

    private func isStillOpen(_ entry: WindowSwitcherEntry, in snapshot: DaemonSnapshot) -> Bool {
        if snapshot.windows.contains(where: { $0.window.id == entry.id && $0.window.pid == entry.window.pid }) {
            return true
        }
        return snapshot.existingWindowPIDs?[entry.id] == entry.window.pid
    }

    private func report(_ outcome: WindowSwitcherAXOutcome, label: String) -> WindowCommandResult {
        switch outcome {
        case .performed:
            return WindowCommandResult(message: label, changed: true)
        case .targetMissing:
            return .failure("\(label): window not found")
        case .refused(let code):
            return .failure("\(label): refused (AXError \(code))")
        case .applicationRefused:
            return .failure("\(label): application refused")
        }
    }
}
