import Foundation
import RoadieAX
import RoadieCore

/// Aperçu réversible des voisines, sans mutation de l'arbre ou de l'affectation.
/// Les places et la visée viennent du même contexte figé que le fantôme.
@MainActor
final class LiveDropPreview {
    private final class Session {
        let permit: InteractiveWritePermit
        let originals: [WindowID: ScopedWindowSnapshot]
        var windows: [WindowID: WindowSnapshot]
        var touched: Set<WindowID> = []
        var scopes: Set<StageScope> = []
        var source: WindowID?
        var dispatcher: InteractiveFrameDispatcher!
        var ending = false
        var action: (@MainActor () -> Void)?
        let config: TilingConfig
        let stages: [StageScope: PersistentStage]
        var lastPlacements: [WindowID: Rect] = [:]
        var lastCandidate: DropPreviewCandidate?
        init(context: DropPreviewContext, state: PersistentStageState, generations: PlacementGeneration, config: TilingConfig) {
            self.config = config
            stages = LiveDropPreview.stageIndex(state)
            permit = InteractiveWritePermit(generations: generations)
            originals = Dictionary(context.snapshot.windows.filter {
                $0.pin == nil && $0.window.isTileCandidate && $0.window.isOnScreen
                    && $0.window.furniture?.isNativeFullscreen != true
            }.map { ($0.window.id, $0) }, uniquingKeysWith: { a, _ in a })
            windows = originals.mapValues(\.window)
        }
    }
    private let service: SnapshotService
    private let generations: PlacementGeneration
    private let activity: WindowDragActivity
    private var session: Session?
    private var timer: Timer?
    private var superseded = false
    var isActive: Bool { session != nil }

    init(service: SnapshotService, generations: PlacementGeneration = .shared,
         activity: WindowDragActivity = .shared) {
        self.service = service; self.generations = generations; self.activity = activity
    }

    func begin(_ context: DropPreviewContext) {
        invalidate()
        superseded = false
        // L'acquisition du contexte peut réconcilier une destruction ancienne.
        // La visée garde l'arbre d'avant, la garde compare l'état APRES acquisition.
        let current = Session(context: context, state: service.effectiveStageStore.state(),
                              generations: generations, config: service.effectiveConfig.tiling)
        session = current
        current.dispatcher = InteractiveFrameDispatcher(service: service, permit: current.permit) { [weak current] result in
            guard let current else { return }
            for item in result.items {
                if let actual = item.actual { current.windows[item.windowID]?.frame = actual }
            }
        }
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let current = self.session, !current.ending else { return }
                self.update(current.lastCandidate)
            }
        }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    /// O(w + s) par cible : commandes indexées, un seul dernier lot par PID.
    func update(_ candidate: DropPreviewCandidate?) {
        guard let current = session, !current.ending else { return }
        if !service.effectiveConfig.tiling.liveDragPreview && current.touched.isEmpty {
            current.lastCandidate = candidate
            return
        }
        if let candidate {
            if current.source == nil { current.source = candidate.sourceWindowID }
            guard current.source == candidate.sourceWindowID,
                  let source = current.originals[candidate.sourceWindowID], let sourceScope = source.scope
            else { invalidate(); return }
            current.scopes.formUnion([sourceScope, candidate.scope])
        }
        guard valid(current) else { invalidate(); return }
        current.lastCandidate = candidate
        let placements = service.effectiveConfig.tiling.liveDragPreview ? candidate?.placements ?? [:] : [:]
        guard placements != current.lastPlacements else { return }
        current.lastPlacements = placements
        submit(placements, current: current)
    }

    /// Solde les écritures avant de rendre la main au dépôt normal. Une application lente ne
    /// bloque pas le fil principal ; le permis est révoqué après 500 ms au plus.
    func finish(then action: (@MainActor () -> Void)? = nil) {
        guard let current = session else { if !superseded { action?() }; return }
        if current.ending {
            if action == nil { current.action = nil; submit([:], current: current) }
            return
        }
        guard valid(current) else { invalidate(); return }
        current.ending = true
        current.action = action
        if current.touched.isEmpty {
            invalidate(); action?(); return
        }
        // Au dépôt, les voisines gardent leur aperçu : pas d'aller-retour visible.
        // Sans action définitive, la même file restaure les cadres initiaux.
        if action == nil { submit([:], current: current) }
        if let source = current.source { activity.markActive(windowID: source) }
        Task { [self, current] in
            let deadline = Date().addingTimeInterval(0.5)
            while !current.dispatcher.isIdle && Date() < deadline && current.permit.isCurrent {
                try? await Task.sleep(for: .milliseconds(10))
            }
            guard session === current else { return }
            let canCommit = valid(current)
            let completion = current.action
            invalidate()
            activity.release()
            if canCommit { completion?() }
        }
    }

    /// Une nouvelle commande gagne. Aucune restauration d'une ancienne disposition.
    func invalidate() {
        superseded = true
        timer?.invalidate(); timer = nil
        if session?.ending == true { activity.release() }
        session?.dispatcher?.invalidate()
        session = nil
    }

    private func submit(_ placements: [WindowID: Rect], current: Session) {
        let eligible = placements.filter { id, _ in
            id != current.source && current.originals[id] != nil
        }
        current.touched.formUnion(eligible.keys)
        let commands = current.touched.compactMap { id -> ApplyCommand? in
            guard let original = current.originals[id], let window = current.windows[id] else { return nil }
            let target = eligible[id] ?? original.window.frame
            guard !window.frame.cgRect.matchesFrame(target.cgRect)
                    || current.dispatcher.mayChange(window) else { return nil }
            return ApplyCommand(window: window, frame: target)
        }
        if !commands.isEmpty || !current.dispatcher.isIdle {
            current.dispatcher.submit(commands, generation: current.permit.advance())
        }
    }

    /// Cache JSON existant : contrôle des portées et des feuilles, sans observation AX.
    /// O(w + s) : index des stages/pins construits une fois par validation.
    private func valid(_ current: Session) -> Bool {
        guard current.permit.isCurrent else { return false }
        var config = service.effectiveConfig.tiling
        config.liveDragPreview = current.config.liveDragPreview
        guard config == current.config else { return false }
        let state = service.effectiveStageStore.state()
        let stages = Self.stageIndex(state)
        let active = Set(state.scopes.map {
            StageScope(displayID: $0.displayID, desktopID: $0.desktopID, stageID: $0.activeStageID)
        })
        let pins = Set(state.windowPins.map(\.windowID))
        guard pins.isDisjoint(with: current.touched), current.source.map({ !pins.contains($0) }) ?? true else { return false }
        for scope in current.scopes {
            guard state.currentDesktopID(for: scope.displayID) == scope.desktopID,
                  active.contains(scope),
                  let fresh = stages[scope], let before = current.stages[scope],
                  fresh.mode == before.mode, fresh.bspTree == before.bspTree,
                  fresh.members.map(\.windowID) == before.members.map(\.windowID),
                  fresh.members.map(\.confirmedClosedAt) == before.members.map(\.confirmedClosedAt),
                  service.effectiveIntentStore.intent(for: scope)?.zoomedWindowID == nil
            else { return false }
        }
        return true
    }

    private nonisolated static func stageIndex(_ state: PersistentStageState) -> [StageScope: PersistentStage] {
        var result: [StageScope: PersistentStage] = [:]
        for scope in state.scopes {
            for stage in scope.stages {
                result[StageScope(displayID: scope.displayID, desktopID: scope.desktopID, stageID: stage.id)] = stage
            }
        }
        return result
    }
}
