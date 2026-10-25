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
    private struct Draft {
        var window: WindowSnapshot
        let scope: StageScope
        let displayName: String
        let desktopName: String
        let stageName: String
    }

    private let service: SnapshotService

    init(service: SnapshotService = SnapshotService()) {
        self.service = service.withoutObservationPersistence()
    }

    @MainActor
    func load() async -> (entries: [WindowSwitcherEntry], context: WindowSwitcherContext, snapshot: DaemonSnapshot?, persisted: PersistentStageState) {
        guard let snapshot = await service.readerSnapshot(followFocus: false) else {
            return ([], WindowSwitcherContext(), nil, PersistentStageState())
        }
        let persisted = service.effectiveStageStore.state()
        let drafts = collectDrafts(snapshot: snapshot, persisted: persisted)
        let axStates = await accessibilityStates(for: drafts)
        let retired = Self.retiredWindows(axStates, withoutSpace: SpaceProbe.windowsWithoutSpace)
        let entries = drafts.filter { !retired.contains($0.window.id) }.map { draft -> WindowSwitcherEntry in
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
                isFullscreen: ax?.isFullscreen ?? window.furniture?.isNativeFullscreen ?? false,
                visibilityKnown: window.isOnScreen || ax?.visibilityKnown == true
            )
        }
        // Fenêtre réellement au premier plan selon macOS : le relevé sans suivi du focus retient celle de
        // la stage active du premier écran, pas forcément celle où l’utilisateur travaille.
        return (entries, context(snapshot: snapshot, systemFocusedID: service.focusedWindowID()), snapshot, persisted)
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
        let target = snapshot.windows.first { $0.window.id == entry.id }?.window ?? entry.window
        return WindowBookmarkCommandService(service: service, store: store).focusWindow(
            target,
            in: owner,
            snapshot: snapshot,
            generation: generation,
            label: "switcher activate",
            cause: "switcher.activate",
            eventPrefix: "window.switcher",
            requireOwnership: true,
            prepareTarget: {
                !entry.isHidden || WindowSwitcherWindowAccess.unhideApplication(pid: entry.window.pid, bundleID: entry.window.bundleID) == .performed
            },
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
            guard activation.changed, activation.outcome != .failed else { return activation }
            let commands = WindowCommandService(service: service)
            return action == .maximize ? commands.toggleMaximize(windowID: entry.id) : commands.toggleFullscreen(windowID: entry.id)
        }
    }

    private func collectDrafts(snapshot: DaemonSnapshot, persisted: PersistentStageState) -> [Draft] {
        var drafts: [Draft] = []
        var seen = Set<WindowID>()
        let stageLabels = Self.stageLabels(in: persisted, liveWindowIDs: Set(snapshot.windows.map(\.window.id)))
        for scoped in snapshot.windows {
            guard let scope = scoped.scope else { continue }
            seen.insert(scoped.window.id)
            drafts.append(draft(window: scoped.window, scope: scope, snapshot: snapshot, persisted: persisted, stageLabels: stageLabels))
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
                    drafts.append(draft(window: window, scope: stageScope, snapshot: snapshot, persisted: persisted, stageLabels: stageLabels))
                }
            }
        }
        return drafts
    }

    /// Même numérotation que le rail ; un nom généré ne révèle jamais un UUID interne.
    static func stageLabels(in state: PersistentStageState, liveWindowIDs: Set<WindowID>) -> [StageScope: String] {
        var labels: [StageScope: String] = [:]
        for scope in state.scopes {
            let order = StagePresentationOrder(scope: scope, liveWindowIDs: liveWindowIDs)
            for (index, stage) in order.visibleStages.enumerated() {
                let id = StageScope(displayID: scope.displayID, desktopID: scope.desktopID, stageID: stage.id)
                labels[id] = StagePresentationOrder.name(stage, position: index + 1)
            }
        }
        return labels
    }

    private func draft(window: WindowSnapshot, scope: StageScope, snapshot: DaemonSnapshot,
                       persisted: PersistentStageState, stageLabels: [StageScope: String]) -> Draft {
        Draft(
            window: window,
            scope: scope,
            displayName: snapshot.displays.first { $0.id == scope.displayID }?.name ?? "",
            desktopName: persisted.desktopLabels.first { $0.displayID == scope.displayID && $0.desktopID == scope.desktopID }?.label
                ?? "Bureau \(scope.desktopID.rawValue)",
            stageName: stageLabels[scope] ?? ""
        )
    }

    /// Lecture AX seulement pour les fenêtres hors écran, un appel par application, hors MainActor.
    private func accessibilityStates(for drafts: [Draft]) async -> [WindowID: WindowSwitcherAXState] {
        let byPID = Dictionary(grouping: drafts.filter { !$0.window.isOnScreen }) { $0.window.pid }
        return await Self.loadAccessibilityStates(byPID: byPID.mapValues { Set($0.map(\.window.id)) }) { pid, ids in
            WindowSwitcherWindowAccess.states(pid: pid, windowIDs: ids)
        }
    }

    /// Fenêtre fermée que son application garde en mémoire (AlDente, réglages d'applications de barre
    /// des menus) : l'application répond sans la lister, elle n'est ni cachée ni réduite, et aucun
    /// bureau ne la porte. Une fenêtre d'un autre bureau garde son bureau ; sans réponse SkyLight,
    /// rien n'est écarté. O(k), k = fenêtres absentes de la liste AX.
    static func retiredWindows(
        _ states: [WindowID: WindowSwitcherAXState],
        withoutSpace: (Set<WindowID>) -> Set<WindowID>?
    ) -> Set<WindowID> {
        let unlisted = Set(states.lazy.filter { !$0.value.isListed && !$0.value.isHidden }.map(\.key))
        guard !unlisted.isEmpty else { return [] }
        return withoutSpace(unlisted)?.intersection(unlisted) ?? []
    }

    /// Fenêtres retirées parmi des fenêtres vivantes absentes du relevé (SPEC-083), mêmes critères
    /// que le sélecteur. Une lecture AX par application, puis une requête SkyLight. O(k).
    static func retiredWindows(pids: [WindowID: Int32]) -> Set<WindowID> {
        var states: [WindowID: WindowSwitcherAXState] = [:]
        for (pid, ids) in Dictionary(grouping: pids.keys, by: { pids[$0] ?? 0 }) where pid > 0 {
            states.merge(WindowSwitcherWindowAccess.states(pid: pid, windowIDs: Set(ids))) { _, new in new }
        }
        return retiredWindows(states, withoutSpace: SpaceProbe.windowsWithoutSpace)
    }

    /// Toutes les applications sont consultées, avec au plus quatre lectures AX simultanées.
    /// Chaque pid n'est visité qu'une fois ; l'annulation empêche de lancer les suivants.
    static func loadAccessibilityStates(
        byPID: [Int32: Set<WindowID>],
        read: @escaping @Sendable (Int32, Set<WindowID>) -> [WindowID: WindowSwitcherAXState]
    ) async -> [WindowID: WindowSwitcherAXState] {
        await withTaskGroup(of: [WindowID: WindowSwitcherAXState].self) { group in
            var pending = byPID.keys.sorted().makeIterator()
            func enqueue(_ pid: Int32) {
                let ids = byPID[pid, default: []]
                group.addTask { read(pid, ids) }
            }
            for _ in 0..<min(4, byPID.count) {
                if let pid = pending.next() { enqueue(pid) }
            }
            var merged: [WindowID: WindowSwitcherAXState] = [:]
            while let part = await group.next() {
                merged.merge(part) { _, new in new }
                if !Task.isCancelled, let pid = pending.next() { enqueue(pid) }
            }
            return merged
        }
    }

    /// `systemFocusedID` prime s’il désigne une fenêtre du relevé ; sinon repli sur le relevé. O(n).
    func context(snapshot: DaemonSnapshot, systemFocusedID: WindowID? = nil) -> WindowSwitcherContext {
        let focusedID = systemFocusedID.flatMap { id in snapshot.windows.contains { $0.window.id == id } ? id : nil }
            ?? snapshot.focusedWindowID
        let focused = snapshot.windows.first { $0.window.id == focusedID }
        let scope = focused?.scope ?? snapshot.displays.lazy.compactMap { snapshot.state.activeScope(on: $0.id) }.first
        return WindowSwitcherContext(
            focusedWindowID: focusedID,
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
