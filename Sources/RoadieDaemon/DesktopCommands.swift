import CoreGraphics
import Foundation
import RoadieAX
import RoadieCore

public struct DesktopCommandService {
    private let service: SnapshotService
    private let store: StageStore
    private let events: EventLog
    private let commandActivity: LayoutCommandActivity

    public init(
        service: SnapshotService = SnapshotService(),
        store: StageStore = StageStore(),
        events: EventLog = EventLog(),
        commandActivity: LayoutCommandActivity = .shared
    ) {
        self.service = service
        self.store = store
        self.events = events
        self.commandActivity = commandActivity
    }

    public func list() -> StageCommandResult {
        let snapshot = service.snapshot()
        guard let display = activeDisplay(in: snapshot) else {
            return StageCommandResult(message: "desktop list: no display", changed: false, outcome: .noOp)
        }
        let state = store.state()
        let current = state.currentDesktopID(for: display.id)
        let ids = desktopIDs(for: display.id, in: state)
        var lines = ["ACTIVE\tID\tLABEL\tSTAGES\tWINDOWS"]
        for id in ids {
            let scopes = state.scopes.filter { $0.displayID == display.id && $0.desktopID == id }
            let stageCount = scopes.flatMap(\.stages).count
            let windowCount = scopes.flatMap(\.stages).flatMap(\.members).count
            let label = state.label(displayID: display.id, desktopID: id) ?? "-"
            lines.append("\(id == current ? "*" : "")\t\(id.rawValue)\t\(label)\t\(stageCount)\t\(windowCount)")
        }
        return StageCommandResult(message: lines.joined(separator: "\n"), changed: false, outcome: .noOp)
    }

    public func current() -> StageCommandResult {
        let snapshot = service.snapshot()
        guard let display = activeDisplay(in: snapshot) else {
            return StageCommandResult(message: "desktop current: no display", changed: false, outcome: .noOp)
        }
        let state = store.state()
        let current = state.currentDesktopID(for: display.id)
        let label = state.label(displayID: display.id, desktopID: current) ?? "-"
        return StageCommandResult(message: "desktop current \(current.rawValue) \(label)", changed: false, outcome: .noOp)
    }

    public func label(_ desktopID: DesktopID, as label: String) -> StageCommandResult {
        let snapshot = service.snapshot()
        guard let display = activeDisplay(in: snapshot) else {
            return StageCommandResult(message: "desktop label: no display", changed: false, outcome: .noOp)
        }
        let state: PersistentStageState
        do {
            state = try store.mutateChecked { state in
                _ = state.scope(displayID: display.id, desktopID: desktopID)
                state.setLabel(label, displayID: display.id, desktopID: desktopID)
                return state
            }
        } catch {
            return .persistenceFailure("desktop label \(desktopID.rawValue)", error)
        }
        let visibleLabel = state.label(displayID: display.id, desktopID: desktopID) ?? "-"
        return StageCommandResult(message: "desktop label \(desktopID.rawValue) \(visibleLabel)", changed: true)
    }

    public func focus(_ desktopID: DesktopID) -> StageCommandResult {
        let snapshot = service.snapshot()
        guard let display = activeDisplay(in: snapshot) else {
            return StageCommandResult(message: "desktop focus: no display", changed: false, outcome: .noOp)
        }
        return switchDisplay(display, to: desktopID, snapshot: snapshot)
    }

    public func cycle(_ direction: StageCycleDirection) -> StageCommandResult {
        let snapshot = service.snapshot()
        guard let display = activeDisplay(in: snapshot) else {
            return StageCommandResult(message: "desktop \(direction.rawValue): no display", changed: false, outcome: .noOp)
        }
        let state: PersistentStageState
        do {
            state = try store.mutateChecked { state in
                for id in (1...6).map({ DesktopID(rawValue: $0) }) {
                    _ = state.scope(displayID: display.id, desktopID: id)
                }
                return state
            }
        } catch {
            return .persistenceFailure("desktop \(direction.rawValue)", error)
        }
        let ids = desktopIDs(for: display.id, in: state)
        let current = state.currentDesktopID(for: display.id)
        let index = ids.firstIndex(of: current) ?? 0
        let nextIndex: Int
        switch direction {
        case .next:
            nextIndex = (index + 1) % ids.count
        case .prev:
            nextIndex = (index - 1 + ids.count) % ids.count
        }
        return switchDisplay(display, to: ids[nextIndex], snapshot: snapshot)
    }

    public func last() -> StageCommandResult {
        let snapshot = service.snapshot(followFocus: false)
        guard let display = activeDisplay(in: snapshot) else {
            return StageCommandResult(message: "desktop last: no display", changed: false, outcome: .noOp)
        }
        let state = store.state()
        guard let last = state.lastDesktopID(for: display.id) else {
            return StageCommandResult(message: "desktop last: none", changed: false, outcome: .noOp)
        }
        return switchDisplay(display, to: last, snapshot: snapshot)
    }

    public func backAndForth() -> StageCommandResult {
        last()
    }

    public func summon(_ desktopID: DesktopID) -> StageCommandResult {
        let snapshot = service.snapshot()
        guard let display = activeDisplay(in: snapshot) else {
            return StageCommandResult(message: "desktop summon: no display", changed: false, outcome: .noOp)
        }
        return switchDisplay(display, to: desktopID, snapshot: snapshot)
    }

    /// Déplace le bureau `source` à la place `target` sur l'écran donné, ou l'écran actif (SPEC-066).
    /// Aucune fenêtre ne bouge : le bureau affiché garde son contenu et change seulement de numéro.
    /// Intentions réécrites après l'état ; si elles échouent, l'état revient (même règle que REL-021).
    public func move(_ source: DesktopID, to target: DesktopID, displayID requested: DisplayID? = nil) -> StageCommandResult {
        let label = "desktop move \(source.rawValue) \(target.rawValue)"
        let displayID: DisplayID
        if let requested {
            displayID = requested
        } else if let display = activeDisplay(in: service.snapshot(followFocus: false)) {
            displayID = display.id
        } else {
            return StageCommandResult(message: "\(label): no display", changed: false, outcome: .noOp)
        }
        let state = store.state()
        let highest = max(ConfigReloadService.shared.currentConfig().desktops.count,
                          state.scopes.filter { $0.displayID == displayID }.map(\.desktopID.rawValue).max() ?? 1)
        guard (1...highest).contains(source.rawValue), (1...highest).contains(target.rawValue) else {
            return StageCommandResult(message: "\(label): desktops are numbered 1 to \(highest)", changed: false, outcome: .failed)
        }
        let mapping = DesktopReorder.mapping(from: source, to: target)
        guard !mapping.isEmpty else {
            return StageCommandResult(message: "\(label): already in place", changed: false, outcome: .noOp)
        }
        var before: PersistentStageState?
        var after: PersistentStageState?
        do {
            try store.mutateChecked { state in
                before = state
                state.renumberDesktops(on: displayID, mapping)
                after = state
            }
            do {
                try service.effectiveIntentStore.mutateChecked { DesktopReorder.remap(intents: &$0, on: displayID, mapping) }
            } catch {
                if let before, let after {
                    try store.mutateChecked { state in
                        guard state == after else { throw StageStateChangedError() }
                        state = before
                    }
                }
                throw error
            }
        } catch {
            return .persistenceFailure(label, error)
        }
        events.append(RoadieEvent(type: "desktop_reordered", details: [
            "displayID": displayID.rawValue, "from": String(source.rawValue), "to": String(target.rawValue)
        ]))
        return StageCommandResult(message: label, changed: true)
    }

    public func assignActiveWindow(to desktopID: DesktopID, follow: Bool = false) -> StageCommandResult {
        beginLayoutCommand("desktop.assign_active_window")
        defer { finishLayoutCommand("desktop.assign_active_window") }
        let generation = PlacementGeneration.shared.next()
        let snapshot = service.snapshot()
        guard let active = activeWindow(in: snapshot),
              let displayID = active.scope?.displayID ?? displayID(containing: active.window.frame.center, in: snapshot.displays),
              let display = snapshot.displays.first(where: { $0.id == displayID })
        else {
            return StageCommandResult(message: "window desktop \(desktopID.rawValue): no active window", changed: false, outcome: .noOp)
        }
        // Bureau cible = bureau actuel de la fenêtre : rien à écrire (REL-016), comme `assign(windowID:...)`.
        guard active.scope?.desktopID != desktopID || active.scope?.displayID != displayID else {
            return StageCommandResult(message: "window desktop \(desktopID.rawValue): already on target desktop", changed: false, outcome: .noOp)
        }
        return moveWindow(active, to: desktopID, on: display, snapshot: snapshot, follow: follow, generation: generation, messageLabel: "")
    }

    public func assign(
        windowID: WindowID,
        to desktopID: DesktopID,
        displayID: DisplayID,
        follow: Bool = false
    ) -> StageCommandResult {
        beginLayoutCommand("desktop.assign_window")
        defer { finishLayoutCommand("desktop.assign_window") }
        let generation = PlacementGeneration.shared.next()
        let snapshot = service.snapshot()
        guard let entry = snapshot.windows.first(where: { $0.window.id == windowID }),
              let display = snapshot.displays.first(where: { $0.id == displayID })
        else {
            return StageCommandResult(message: "window desktop \(desktopID.rawValue): window or display unavailable", changed: false, outcome: .failed)
        }
        guard entry.scope?.desktopID != desktopID || entry.scope?.displayID != displayID else {
            return StageCommandResult(message: "window desktop \(desktopID.rawValue): already on target desktop", changed: false, outcome: .noOp)
        }
        return moveWindow(entry, to: desktopID, on: display, snapshot: snapshot, follow: follow, generation: generation, messageLabel: "window=\(windowID.rawValue) ")
    }

    /// Corps commun des deux entrées publiques (MIN-004) : mutation des scopes, retrait du pin,
    /// intentions de layout, puis masquage (bureau cible non affiché) et disposition en un seul plan.
    /// Les validations propres à chaque entrée restent chez l'appelant.
    private func moveWindow(
        _ entry: ScopedWindowSnapshot,
        to desktopID: DesktopID,
        on display: DisplaySnapshot,
        snapshot: DaemonSnapshot,
        follow: Bool,
        generation: UInt64,
        messageLabel: String
    ) -> StageCommandResult {
        let displayID = display.id
        let sourceScope = entry.scope
        let stageManager = ConfigReloadService.shared.currentConfig().stageManager
        let transaction: (StageScope, PersistentWindowPin?, Bool, CGRect?)
        do {
            // Affectation écrite puis intents retirés ; si ce retrait échoue, l'affectation et le pin
            // reviennent (REL-021) : le refus annoncé ne laisse rien.
            transaction = try service.commitStageTransfer(in: store, { state -> (StageScope, PersistentWindowPin?, Bool, CGRect?) in
                // Cadre mémorisé avant le retrait : sert à replacer une fenêtre garée (REL-016).
                let rememberedFrame = state.scopes.lazy
                    .flatMap { $0.stages.lazy.flatMap { $0.members } }
                    .first { $0.windowID == entry.window.id }?.frame.cgRect
                var targetScope = state.scope(displayID: displayID, desktopID: desktopID)
                targetScope.applyConfiguredStages(stageManager)
                for scopeIndex in state.scopes.indices {
                    state.scopes[scopeIndex].remove(windowID: entry.window.id)
                }
                targetScope.assign(window: entry.window, to: targetScope.activeStageID)
                state.update(targetScope)
                let targetStageScope = StageScope(displayID: displayID, desktopID: desktopID, stageID: targetScope.activeStageID)
                let removedPin = state.removePin(windowID: entry.window.id)
                state.suppressRulePlacement(window: entry.window)
                return (targetStageScope, removedPin, state.currentDesktopID(for: displayID) == desktopID, rememberedFrame)
            }, clearingIntentsOf: { [sourceScope, $0.0].compactMap { $0 } })
        } catch {
            return .persistenceFailure("window desktop \(desktopID.rawValue)", error)
        }
        let (targetStageScope, removedPin, targetIsVisible, rememberedFrame) = transaction

        if follow {
            return switchDisplay(display, to: desktopID, snapshot: snapshot, generation: generation)
        }

        // Plan unique (A15, T212) : fenêtre masquée et scope d'origine disposé en une écriture groupée.
        // Un bureau cible déjà affiché garde la fenêtre visible (REL-016) : une fenêtre garée y reçoit
        // un cadre visible explicite. Les modes à arbre le remplacent par leur disposition ; le mode
        // `float` garde sinon la géométrie courante, donc la fenêtre resterait hors écran.
        var hiding: [WindowID: CGRect] = [:]
        var restoring: [WindowID: CGRect] = [:]
        if targetIsVisible {
            if let frame = Self.visibleRestoreFrame(current: entry.window.frame.cgRect, remembered: rememberedFrame, on: display, among: snapshot.displays) {
                restoring[entry.window.id] = frame
            }
        } else {
            hiding[entry.window.id] = HiddenWindowPlacement.frame(for: entry.window.frame.cgRect, on: display, among: snapshot.displays)
        }
        let (_, result) = service.applyCommandPlacement(
            CommandPlacement(
                hiding: hiding,
                restoring: restoring,
                layoutScopes: Set([sourceScope, targetStageScope].compactMap { $0 })
            ),
            cause: "desktop.assign_window",
            generation: generation,
            events: events
        )
        let hidden = !targetIsVisible && !result.items.contains { $0.windowID == entry.window.id && $0.status == .failed }
        events.append(RoadieEvent(
            type: "window_desktop",
            scope: targetStageScope,
            details: [
                "windowID": String(entry.window.id.rawValue),
                "follow": String(follow),
                "layout": String(result.attempted),
                "unpinned": String(removedPin != nil),
            ]
        ))
        appendManualPinRemovalEvent(removedPin, targetScope: targetStageScope)
        return StageCommandResult.changedOrNoOp(
            "window desktop \(desktopID.rawValue): \(messageLabel)hidden=\(hidden) layout=\(result.attempted)",
            changed: hidden || result.attempted > 0
        )
    }

    /// Cadre visible pour une fenêtre garée (masquée) arrivant sur un bureau affiché : le cadre
    /// mémorisé s'il est visible et sur l'écran, sinon la taille courante centrée dans la zone
    /// visible de l'écran. nil si la fenêtre n'est pas garée. O(d), d = nombre d'écrans.
    static func visibleRestoreFrame(
        current: CGRect,
        remembered: CGRect?,
        on display: DisplaySnapshot,
        among displays: [DisplaySnapshot]
    ) -> CGRect? {
        guard HiddenWindowPlacement.isHiddenOrLegacyOffscreen(current, in: displays) else { return nil }
        let area = display.visibleFrame.cgRect
        if let remembered, !HiddenWindowPlacement.isHiddenOrLegacyOffscreen(remembered, in: displays), area.intersects(remembered) {
            return remembered
        }
        let size = CGSize(width: min(current.width, area.width), height: min(current.height, area.height))
        return CGRect(
            x: area.midX - size.width / 2,
            y: area.midY - size.height / 2,
            width: size.width,
            height: size.height
        ).integral
    }

    private func appendManualPinRemovalEvent(_ pin: PersistentWindowPin?, targetScope: StageScope) {
        guard let pin else { return }
        var details = pin.eventDetails
        details["reason"] = "manual_window_move"
        events.append(RoadieEvent(type: "window.pin_removed", scope: targetScope, details: details))
    }

    private func switchDisplay(
        _ display: DisplaySnapshot,
        to desktopID: DesktopID,
        snapshot: DaemonSnapshot,
        generation: UInt64 = PlacementGeneration.shared.next()
    ) -> StageCommandResult {
        // Préparé hors verrou : config et fenêtres visibles de l'écran (aucune E/S dans `mutate`).
        let stageConfig = ConfigReloadService.shared.currentConfig().stageManager
        // Stage active du bureau cible à arbre : application immédiate, sans l'attente globale de
        // `LayoutCommandActivity` (R12). Mode lu sur une copie de l'état, comme la transaction le verra.
        var preview = store.state()
        var targetPreview = preview.scope(displayID: display.id, desktopID: desktopID)
        targetPreview.applyConfiguredStages(stageConfig)
        let targetUsesTree = targetPreview.stages.first { $0.id == targetPreview.activeStageID }?.mode.usesTreeEngine == true
        if !targetUsesTree { beginLayoutCommand("desktop.switch") }
        defer { if !targetUsesTree { finishLayoutCommand("desktop.switch") } }
        let windowsByID = Dictionary(uniqueKeysWithValues: snapshot.windows.map { ($0.window.id, $0.window) })
        let visibleWindows = windowsByID.values.filter {
            display.frame.cgRect.contains($0.frame.center) && !HiddenWindowPlacement.isHiddenOrLegacyOffscreen($0.frame.cgRect, in: snapshot.displays)
        }

        // Scopes relus et modifiés sous verrou (FR-013) ; le bloc renvoie ce que l'AX fera ensuite.
        let plan: DesktopSwitchPlan?
        do {
            plan = try store.mutateChecked { state -> DesktopSwitchPlan? in
                let previousDesktopID = state.currentDesktopID(for: display.id)
                guard previousDesktopID != desktopID else { return nil }
                var previousScope = state.scope(displayID: display.id, desktopID: previousDesktopID)
                var targetScope = state.scope(displayID: display.id, desktopID: desktopID)
                targetScope.applyConfiguredStages(stageConfig)
                for window in visibleWindows {
                    previousScope.updateFrame(window: window)
                }
                let previousWindowIDs = Set(previousScope.stages.flatMap { $0.members.map(\.windowID) })
                let targetStage = targetScope.stages.first { $0.id == targetScope.activeStageID }
                let targetWindowIDs = Set(targetStage?.members.map(\.windowID) ?? [])
                let hiddenIDs = previousWindowIDs.subtracting(targetWindowIDs)
                state.update(previousScope)
                state.update(targetScope)
                state.switchDesktop(displayID: display.id, to: desktopID)
                state.protectCommandFocus(
                    displayID: display.id,
                    desktopID: desktopID,
                    stageID: targetScope.activeStageID,
                    windowID: targetStage?.focusedWindowID ?? targetStage?.members.last?.windowID,
                    staleFocusedWindowID: snapshot.focusedWindowID.flatMap { hiddenIDs.contains($0) ? $0 : nil }
                )
                return DesktopSwitchPlan(
                    previousDesktopID: previousDesktopID,
                    targetStageID: targetScope.activeStageID,
                    hiddenIDs: hiddenIDs,
                    targetStage: targetStage
                )
            }
        } catch {
            return .persistenceFailure("desktop focus \(desktopID.rawValue)", error)
        }
        guard let plan else {
            return StageCommandResult(message: "desktop focus \(desktopID.rawValue): already active", changed: false, outcome: .noOp)
        }
        let targetStage = plan.targetStage
        let targetWindowIDs = Set(targetStage?.members.map(\.windowID) ?? [])

        // Plan unique (A15, T212) : masquage du bureau quitté et disposition de la stage cible dans
        // une seule écriture groupée, puis le focus.
        let targetScope = StageScope(displayID: display.id, desktopID: desktopID, stageID: plan.targetStageID)
        var placement = CommandPlacement(layoutScopes: [targetScope])
        for id in plan.hiddenIDs {
            guard let window = windowsByID[id] else { continue }
            placement.hiding[id] = HiddenWindowPlacement.frame(for: window.frame.cgRect, on: display, among: snapshot.displays)
        }
        // Mode arbre (A11, T094) : frames finales de l'arbre, sans restaurer les frames mémorisées.
        if targetStage?.mode.usesTreeEngine != true {
            for member in targetStage?.members ?? [] where windowsByID[member.windowID] != nil {
                placement.restoring[member.windowID] = member.frame.cgRect
            }
        }
        let (layoutPlan, result) = service.applyCommandPlacement(placement, cause: "desktop.switch", generation: generation, events: events)
        let layoutAttempted = layoutPlan.commands.count
        let applied = result.applied + result.clamped
        if let focusedID = targetStage?.focusedWindowID ?? targetStage?.members.last?.windowID,
           let focused = windowsByID[focusedID] {
            _ = service.focus(focused)
        }
        events.append(RoadieEvent(
            type: "desktop_focus",
            scope: targetScope,
            details: [
                "previousDesktopID": String(plan.previousDesktopID.rawValue),
                "hidden": String(plan.hiddenIDs.count),
                "shown": String(targetWindowIDs.count),
                "applied": String(applied),
                "layout": String(layoutAttempted)
            ]
        ))

        return StageCommandResult(
            message: "desktop focus \(desktopID.rawValue): hidden=\(plan.hiddenIDs.count) shown=\(targetWindowIDs.count) applied=\(applied) layout=\(layoutAttempted)",
            changed: true
        )
    }

    private func desktopIDs(for displayID: DisplayID, in state: PersistentStageState) -> [DesktopID] {
        let configured = Set(state.scopes.filter { $0.displayID == displayID }.map(\.desktopID))
        let defaults = Set((1...6).map { DesktopID(rawValue: $0) })
        return Array(configured.union(defaults)).sorted()
    }

    private func activeDisplay(in snapshot: DaemonSnapshot) -> DisplaySnapshot? {
        let state = store.state()
        if let activeDisplayID = state.activeDisplayID,
           let display = snapshot.displays.first(where: { $0.id == activeDisplayID }) {
            return display
        }
        if let focusedID = service.focusedWindowID(),
           let entry = snapshot.windows.first(where: { $0.window.id == focusedID }),
           let displayID = entry.scope?.displayID ?? displayID(containing: entry.window.frame.center, in: snapshot.displays) {
            return snapshot.displays.first { $0.id == displayID }
        }
        return snapshot.displays.first
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
        return snapshot.windows.first { entry in
            guard let scope = entry.scope else { return false }
            return entry.window.isTileCandidate && snapshot.state.activeScope(on: scope.displayID) == scope
        }
    }

    private func displayID(containing point: CGPoint, in displays: [DisplaySnapshot]) -> DisplayID? {
        displays.first { $0.frame.cgRect.contains(point) }?.id
    }

    private func beginLayoutCommand(_ reason: String) {
        commandActivity.markActive(reason: reason)
    }

    private func finishLayoutCommand(_ reason: String) {
        commandActivity.finish(reason: reason)
    }
}

/// Résultat de la transaction de changement de bureau, utilisé par les appels AX qui suivent.
private struct DesktopSwitchPlan {
    var previousDesktopID: DesktopID
    var targetStageID: StageID
    var hiddenIDs: Set<WindowID>
    var targetStage: PersistentStage?
}
