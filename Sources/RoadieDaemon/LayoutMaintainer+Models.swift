import CoreGraphics
import Foundation
import RoadieAX
import RoadieCore
import RoadieStages
import RoadieTiler

/// Déplacement d'une fenêtre vers la stage de son écran physique, avec sa place d'origine.
struct ReconciledDisplayMove {
    struct Origin {
        var member: PersistentStageMember
        var index: Int
        var wasFocused: Bool
        var previousFocusedWindowID: WindowID?
        var mode: WindowManagementMode
        var bspTree: BSPTree?

        /// Place du membre dans la stage `scope` de `state`, nil s'il n'y est pas.
        init?(in state: PersistentStageState, windowID: WindowID, scope: StageScope) {
            guard let stage = state.scopes
                .first(where: { $0.displayID == scope.displayID && $0.desktopID == scope.desktopID })?
                .stages.first(where: { $0.id == scope.stageID }),
                  let index = stage.members.firstIndex(where: { $0.windowID == windowID })
            else { return nil }
            self.member = stage.members[index]
            self.index = index
            self.wasFocused = stage.focusedWindowID == windowID
            self.previousFocusedWindowID = stage.previousFocusedWindowID
            self.mode = stage.mode
            self.bspTree = stage.bspTree
        }
    }

    var window: WindowSnapshot
    var source: StageScope
    var target: StageScope
    var origin: Origin?
}

struct RulePlacementDestination {
    var scope: StageScope
    var follow: Bool
}

/// Refus de taille mémorisé : l'application a gardé `actual` quand Roadie demandait `requested`.
/// Expire après `LayoutTolerance.refusalMemorySeconds` (FR-004), sauf s'il s'est répété à
/// l'identique après expiration : il dure alors jusqu'à une autre demande acceptée (SPEC-083).
struct ClampedFrame {
    var requested: Rect
    var actual: Rect
    var recordedAt: Date
    var lasting = false

    func matches(command: ApplyCommand) -> Bool {
        if command.window.frame.isClose(to: actual, tolerance: LayoutTolerance.frameNear),
           requested.isClose(to: command.frame, tolerance: LayoutTolerance.sameRequest) {
            return true
        }
        if impossibleKnownMinimumIsStillRequested(by: command) {
            return true
        }
        guard currentStillMatchesClamp(command.window.frame),
              requested.isClose(
                  to: command.frame,
                  positionTolerance: LayoutTolerance.clampedPositionDrift,
                  sizeTolerance: LayoutTolerance.clampShrink
              )
        else {
            return sameImpossibleAxisIsStillRequested(by: command)
        }
        return command.frame.width <= command.window.frame.width + LayoutTolerance.frameNear
            && command.frame.height <= command.window.frame.height + LayoutTolerance.frameNear
    }

    /// Commande à envoyer malgré ce refus : inchangée si le refus ne la concerne pas ; nil si elle
    /// reprend la position d'une demande déjà refusée ; sinon la nouvelle position est appliquée
    /// avec la taille actuelle, seule la taille refusée est abandonnée (FR-004).
    func adjusted(_ command: ApplyCommand) -> ApplyCommand? {
        guard matches(command: command) else { return command }
        let drift = LayoutTolerance.clampedPositionDrift
        guard abs(command.frame.x - requested.x) > drift || abs(command.frame.y - requested.y) > drift else {
            return nil
        }
        let current = command.window.frame
        let moved = Rect(x: command.frame.x, y: command.frame.y, width: current.width, height: current.height)
        guard !current.isClose(to: moved, tolerance: LayoutTolerance.frameMatch) else { return nil }
        return ApplyCommand(window: command.window, frame: moved)
    }

    func shouldExcludeFromLayout(window: WindowSnapshot) -> Bool {
        guard currentStillMatchesClamp(window.frame) else { return false }

        return requestedGrowthWasRejected(requested: requested.width, actual: actual.width)
            || requestedGrowthWasRejected(requested: requested.height, actual: actual.height)
    }

    private func currentStillMatchesClamp(_ frame: Rect) -> Bool {
        abs(frame.width - actual.width) <= LayoutTolerance.clampShrink
            && abs(frame.height - actual.height) <= LayoutTolerance.clampShrink
    }

    private func sameImpossibleAxisIsStillRequested(by command: ApplyCommand) -> Bool {
        guard currentStillMatchesClamp(command.window.frame) else { return false }

        return axisStillImpossible(
            requested: requested.width,
            actual: actual.width,
            nextRequested: command.frame.width
        ) || axisStillImpossible(
            requested: requested.height,
            actual: actual.height,
            nextRequested: command.frame.height
        )
    }

    private func axisStillImpossible(requested: Double, actual: Double, nextRequested: Double) -> Bool {
        requestedGrowthWasRejected(requested: requested, actual: actual)
            && requestedGrowthWasRejected(requested: nextRequested, actual: actual)
            || requestedShrinkWasRejected(requested: requested, actual: actual)
            && requestedShrinkWasRejected(requested: nextRequested, actual: actual)
    }

    private func impossibleKnownMinimumIsStillRequested(by command: ApplyCommand) -> Bool {
        let widthMinimumStillRelevant = command.window.frame.width >= actual.width - LayoutTolerance.clampShrink
            && requestedShrinkWasRejected(requested: command.frame.width, actual: actual.width)
        let heightMinimumStillRelevant = command.window.frame.height >= actual.height - LayoutTolerance.clampShrink
            && requestedShrinkWasRejected(requested: command.frame.height, actual: actual.height)
        return widthMinimumStillRelevant || heightMinimumStillRelevant
    }

    private func requestedGrowthWasRejected(requested: Double, actual: Double) -> Bool {
        let tolerance = max(LayoutTolerance.growthMinimum, actual * LayoutTolerance.growthRatio)
        return requested > actual + tolerance
    }

    private func requestedShrinkWasRejected(requested: Double, actual: Double) -> Bool {
        requested < actual - LayoutTolerance.clampShrink
    }
}

/// Refus d'une restauration directe. Les mêmes échos AX ne créent pas de nouvelle demande.
struct FailedRestoration {
    var pid: Int32
    var bundleID: String
    var scope: StageScope?
    var requested: Rect
    var observed: Rect
    var observedReliably: Bool
    var attempts: Int

    init(_ command: ApplyCommand, scope: StageScope?, observed: Rect?, attempts: Int) {
        pid = command.window.pid
        bundleID = command.window.bundleID
        self.scope = scope
        requested = command.frame
        self.observed = observed ?? command.window.frame
        observedReliably = observed != nil
        self.attempts = attempts
    }

    /// Une réponse partielle peut arriver après la relecture : sa progression vers la cible
    /// conserve le budget. Un geste confirmé libère cette mémoire avant l'arbitrage.
    func continues(_ command: ApplyCommand, scope: StageScope?) -> Bool {
        pid == command.window.pid && bundleID == command.window.bundleID && self.scope == scope
            && (!observedReliably
                || observed.isClose(to: command.window.frame, tolerance: LayoutTolerance.unchangedSinceRefusal)
                || isDelayedPartialResponse(command.window.frame))
    }

    /// Chaque composante doit rester entre la dernière observation et la cible refusée.
    /// Un axe qui s'en éloigne ou dépasse la cible constitue une nouvelle géométrie.
    private func isDelayedPartialResponse(_ current: Rect) -> Bool {
        let tolerance = LayoutTolerance.unchangedSinceRefusal
        let components = [
            (observed.x, requested.x, current.x), (observed.y, requested.y, current.y),
            (observed.width, requested.width, current.width), (observed.height, requested.height, current.height)
        ]
        var progressed = false
        for (before, target, actual) in components {
            guard actual >= min(before, target) - tolerance,
                  actual <= max(before, target) + tolerance else { return false }
            if abs(actual - before) > tolerance { progressed = true }
        }
        return progressed
    }

    func permits(_ command: ApplyCommand, scope: StageScope?) -> Bool {
        !continues(command, scope: scope) || attempts < LayoutTolerance.writeBudgetPerGeneration
    }

    func matches(_ command: ApplyCommand, scope: StageScope?) -> Bool {
        continues(command, scope: scope)
            && requested.isClose(to: command.frame, tolerance: LayoutTolerance.sameRequest)
            && observed.isClose(to: command.window.frame, tolerance: LayoutTolerance.unchangedSinceRefusal)
    }
}

/// Échec d'application mémorisé. Expire après `LayoutTolerance.refusalMemorySeconds` (FR-004),
/// sauf s'il s'est répété à l'identique après expiration : il dure alors tant que la fenêtre
/// reste à ce cadre et que la demande ne change pas (SPEC-086).
struct FailedFrame {
    var requested: Rect
    var observedAtFailure: Rect
    var recordedAt: Date
    var lasting = false

    func matches(command: ApplyCommand) -> Bool {
        requested.isClose(to: command.frame, tolerance: LayoutTolerance.sameRequest)
            && command.window.frame.isClose(to: observedAtFailure, tolerance: LayoutTolerance.unchangedSinceRefusal)
    }
}

/// Écriture réussie puis annulée par l'application : la même demande n'est pas répétée tant que
/// la fenêtre reste à son cadre d'avant l'écriture (modes sans arbre, A3).
struct RevertedAppliedFrame {
    var requested: Rect
    var observedBeforeApply: Rect
    var appliedAt: Date
    /// Retours de l'application à `observedBeforeApply` après cette même écriture.
    var reverts = 0

    /// Annulée deux fois de suite : la demande n'est plus refaite, quel que soit le délai, tant
    /// que la cible et le cadre observé restent les mêmes (SPEC-083).
    var isLasting: Bool { reverts >= 2 }

    func matches(command: ApplyCommand) -> Bool {
        requested.isClose(to: command.frame, tolerance: LayoutTolerance.sameRequest)
            && command.window.frame.isClose(to: observedBeforeApply, tolerance: LayoutTolerance.unchangedSinceRefusal)
    }
}


private extension Rect {
    /// Tolérances explicites (SPEC-016 FR-041) : plus de valeur par défaut implicite.
    func isClose(to other: Rect, positionTolerance: Double, sizeTolerance: Double) -> Bool {
        abs(x - other.x) <= positionTolerance
            && abs(y - other.y) <= positionTolerance
            && abs(width - other.width) <= sizeTolerance
            && abs(height - other.height) <= sizeTolerance
    }

    func isClose(to other: Rect, tolerance: Double) -> Bool {
        isClose(to: other, positionTolerance: tolerance, sizeTolerance: tolerance)
    }
}

