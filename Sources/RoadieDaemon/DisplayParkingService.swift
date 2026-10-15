import Foundation
import RoadieAX
import RoadieCore

public enum DisplayParkingTransitionKind: String, Codable, Sendable {
    case park
    case restore
    case noop
    case ambiguous
}

public enum DisplayParkingReason: String, Codable, Sendable {
    case displayRemoved = "display_removed"
    case displayRestored = "display_restored"
    case ambiguousMatch = "ambiguous_match"
    case noLiveHost = "no_live_host"
    case noParkedStages = "no_parked_stages"
    case alreadyStable = "already_stable"
    case deferredUntilStable = "deferred_until_stable"
    case windowMoveFailedVisible = "window_move_failed_visible"
    case parkedStagesRecovered = "parked_stages_recovered"
}

public struct DisplayParkingReport: Equatable, Codable, Sendable {
    public var kind: DisplayParkingTransitionKind
    public var reason: DisplayParkingReason
    public var originDisplayID: DisplayID?
    public var originLogicalDisplayID: LogicalDisplayID?
    public var hostDisplayID: DisplayID?
    public var restoredDisplayID: DisplayID?
    public var parkedStageCount: Int
    public var restoredStageCount: Int
    public var skippedStageCount: Int
    public var candidateDisplayIDs: [DisplayID]
    public var confidence: Double?

    public init(
        kind: DisplayParkingTransitionKind,
        reason: DisplayParkingReason,
        originDisplayID: DisplayID? = nil,
        originLogicalDisplayID: LogicalDisplayID? = nil,
        hostDisplayID: DisplayID? = nil,
        restoredDisplayID: DisplayID? = nil,
        parkedStageCount: Int = 0,
        restoredStageCount: Int = 0,
        skippedStageCount: Int = 0,
        candidateDisplayIDs: [DisplayID] = [],
        confidence: Double? = nil
    ) {
        self.kind = kind
        self.reason = reason
        self.originDisplayID = originDisplayID
        self.originLogicalDisplayID = originLogicalDisplayID
        self.hostDisplayID = hostDisplayID
        self.restoredDisplayID = restoredDisplayID
        self.parkedStageCount = parkedStageCount
        self.restoredStageCount = restoredStageCount
        self.skippedStageCount = skippedStageCount
        self.candidateDisplayIDs = candidateDisplayIDs
        self.confidence = confidence
    }
}

public struct DisplayParkingService: Sendable {
    private struct RestoreCandidate {
        var displayID: DisplayID
        var desktopID: DesktopID
        var stage: PersistentStage
    }

    public init() {}

    public func transition(
        state: inout PersistentStageState,
        liveDisplays: [DisplaySnapshot],
        windows: [WindowSnapshot],
        now: Date = Date()
    ) -> DisplayParkingReport {
        let liveDisplayIDs = Set(liveDisplays.map(\.id))
        guard !state.scopes.isEmpty else {
            return DisplayParkingReport(kind: .noop, reason: .alreadyStable)
        }
        guard let hostDisplay = hostDisplay(for: state, liveDisplays: liveDisplays) else {
            return DisplayParkingReport(kind: .noop, reason: .noLiveHost)
        }

        if let restoreReport = restoreParkedStages(state: &state, liveDisplays: liveDisplays, now: now) {
            stampLiveDisplayMetadata(state: &state, liveDisplays: liveDisplays)
            _ = pruneEmptyParkedResidues(state: &state)
            return restoreReport
        }

        let recoveredParkedCount = materializeExpiredParkedStages(
            state: &state,
            liveDisplays: liveDisplays,
            now: now
        )
        if recoveredParkedCount > 0 {
            stampLiveDisplayMetadata(state: &state, liveDisplays: liveDisplays)
            _ = pruneEmptyParkedResidues(state: &state)
            return DisplayParkingReport(
                kind: .noop,
                reason: .parkedStagesRecovered,
                restoredStageCount: recoveredParkedCount
            )
        }

        var hostScope = state.scope(displayID: hostDisplay.id, desktopID: state.currentDesktopID(for: hostDisplay.id))
        let staleScopeIndexes = state.scopes.indices.filter { index in
            !liveDisplayIDs.contains(state.scopes[index].displayID)
        }
        guard !staleScopeIndexes.isEmpty else {
            stampLiveDisplayMetadata(state: &state, liveDisplays: liveDisplays)
            let prunedCount = pruneEmptyParkedResidues(state: &state)
            guard prunedCount == 0 else {
                return DisplayParkingReport(
                    kind: .noop,
                    reason: .alreadyStable,
                    skippedStageCount: prunedCount
                )
            }
            return DisplayParkingReport(kind: .noop, reason: .alreadyStable)
        }

        var parkedCount = 0
        var skippedCount = 0
        var deferredCount = 0
        var firstOriginDisplayID: DisplayID?
        var firstLogicalDisplayID: LogicalDisplayID?
        let liveWindowIDs = Set(windows.map(\.id))

        for scopeIndex in staleScopeIndexes {
            var staleScope = state.scopes[scopeIndex]
            let logicalDisplayID = staleScope.logicalDisplayID ?? LogicalDisplayID(displayID: staleScope.displayID)
            staleScope.logicalDisplayID = logicalDisplayID
            for stageIndex in staleScope.stages.indices {
                let sourceStage = staleScope.stages[stageIndex]
                guard !sourceStage.members.isEmpty else {
                    skippedCount += 1
                    continue
                }
                guard sourceStage.parkingState != .parked else {
                    skippedCount += 1
                    continue
                }
                if !windows.isEmpty {
                    guard sourceStage.members.contains(where: { liveWindowIDs.contains($0.windowID) }) else {
                        deferredCount += 1
                        continue
                    }
                }

                firstOriginDisplayID = firstOriginDisplayID ?? staleScope.displayID
                firstLogicalDisplayID = firstLogicalDisplayID ?? logicalDisplayID

                let parkedID = uniqueParkedStageID(
                    originDisplayID: staleScope.displayID,
                    originStageID: sourceStage.id,
                    in: hostScope
                )
                let origin = StageOrigin(
                    logicalDisplayID: logicalDisplayID,
                    displayID: staleScope.displayID,
                    desktopID: staleScope.desktopID,
                    stageID: sourceStage.id,
                    position: stageIndex + 1,
                    nameAtParking: sourceStage.name,
                    parkedAt: now,
                    modeAtParking: sourceStage.mode
                )

                var parkedStage = sourceStage
                parkedStage.id = parkedID
                parkedStage.parkingState = .parked
                parkedStage.origin = origin
                parkedStage.hostDisplayID = hostDisplay.id
                parkedStage.restoredAt = nil
                hostScope.stages.append(parkedStage)

                staleScope.stages[stageIndex].members = []
                staleScope.stages[stageIndex].groups = []
                staleScope.stages[stageIndex].focusedWindowID = nil
                staleScope.stages[stageIndex].previousFocusedWindowID = nil
                staleScope.stages[stageIndex].parkingState = .parked
                staleScope.stages[stageIndex].origin = origin
                staleScope.stages[stageIndex].hostDisplayID = hostDisplay.id
                parkedCount += 1
            }

            state.scopes[scopeIndex] = staleScope
        }

        state.update(hostScope)
        stampLiveDisplayMetadata(state: &state, liveDisplays: liveDisplays)

        guard parkedCount > 0 else {
            skippedCount += pruneEmptyParkedResidues(state: &state)
            if deferredCount > 0 {
                return DisplayParkingReport(
                    kind: .noop,
                    reason: .deferredUntilStable,
                    originDisplayID: firstOriginDisplayID,
                    originLogicalDisplayID: firstLogicalDisplayID,
                    hostDisplayID: hostDisplay.id,
                    skippedStageCount: skippedCount + deferredCount
                )
            }
            return DisplayParkingReport(
                kind: .noop,
                reason: .noParkedStages,
                originDisplayID: firstOriginDisplayID,
                originLogicalDisplayID: firstLogicalDisplayID,
                hostDisplayID: hostDisplay.id,
                skippedStageCount: skippedCount
            )
        }

        return DisplayParkingReport(
            kind: .park,
            reason: .displayRemoved,
            originDisplayID: firstOriginDisplayID,
            originLogicalDisplayID: firstLogicalDisplayID,
            hostDisplayID: hostDisplay.id,
            parkedStageCount: parkedCount,
            skippedStageCount: skippedCount
        )
    }

    private func restoreParkedStages(
        state: inout PersistentStageState,
        liveDisplays: [DisplaySnapshot],
        now: Date
    ) -> DisplayParkingReport? {
        let parkedStages = restoreCandidates(in: state)
        guard !parkedStages.isEmpty else { return nil }

        let grouped = Dictionary(grouping: parkedStages) { candidate in
            candidate.stage.origin!.logicalDisplayID
        }

        for (logicalDisplayID, stages) in grouped {
            guard let origin = stages.compactMap({ $0.stage.origin }).first else { continue }
            let fingerprint = fingerprintForRestore(
                state: state,
                origin: origin,
                logicalDisplayID: logicalDisplayID
            )
            let decision = DisplayTopology.recognizeDisplay(for: fingerprint, in: liveDisplays)
            if decision.isAmbiguous {
                return DisplayParkingReport(
                    kind: .ambiguous,
                    reason: .ambiguousMatch,
                    originDisplayID: origin.displayID,
                    originLogicalDisplayID: logicalDisplayID,
                    restoredStageCount: 0,
                    skippedStageCount: stages.count,
                    candidateDisplayIDs: decision.candidateDisplayIDs,
                    confidence: decision.confidence
                )
            }
            guard let restoredDisplayID = decision.displayID else { continue }

            // Un écran, plusieurs bureaux : chaque bureau d'origine est restauré dans son propre
            // scope (REL-017). Les stages d'un autre bureau ne migrent pas vers celui du premier.
            let stagesByDesktop = Dictionary(grouping: stages) { $0.stage.origin!.desktopID }
            var restoredCount = 0
            for desktopID in stagesByDesktop.keys.sorted() {
                let sortedStages = stagesByDesktop[desktopID, default: []].sorted {
                    ($0.stage.origin?.position ?? Int.max, $0.stage.id.rawValue)
                        < ($1.stage.origin?.position ?? Int.max, $1.stage.id.rawValue)
                }
                removeRestoreCandidates(sortedStages, from: &state)

                // L'identité physique peut changer à la reconnexion. Garder le scope
                // d'origine et son ordre quand aucun scope n'existe encore sous le nouvel ID.
                if !state.scopes.contains(where: { $0.displayID == restoredDisplayID && $0.desktopID == desktopID }),
                   let originalScopeIndex = state.scopes.firstIndex(where: {
                       $0.displayID == origin.displayID && $0.desktopID == desktopID
                   }) {
                    state.scopes[originalScopeIndex].displayID = restoredDisplayID
                }

                var targetScope = state.scope(displayID: restoredDisplayID, desktopID: desktopID)
                targetScope.logicalDisplayID = logicalDisplayID
                if let display = liveDisplays.first(where: { $0.id == restoredDisplayID }) {
                    targetScope.lastKnownDisplayFingerprint = DisplayFingerprint(display: display)
                }

                for candidate in sortedStages {
                    let parkedStage = candidate.stage
                    var restoredStage = parkedStage
                    let originalStageID = parkedStage.origin?.stageID ?? parkedStage.id
                    restoredStage.parkingState = .restored
                    restoredStage.hostDisplayID = nil
                    restoredStage.restoredAt = now
                    if let placeholderIndex = targetScope.stages.firstIndex(where: {
                        $0.id == originalStageID && $0.origin == parkedStage.origin
                            && isIntactPlaceholder($0)
                    }) {
                        restoredStage.id = originalStageID
                        targetScope.stages[placeholderIndex] = restoredStage
                    } else {
                        // Une modification du placeholder lui donne sa propre existence.
                        // La copie retrouve sa position sans écraser ce choix utilisateur.
                        if let editedIndex = targetScope.stages.firstIndex(where: {
                            $0.id == originalStageID && $0.origin == parkedStage.origin && $0.parkingState == .parked
                        }) {
                            targetScope.stages[editedIndex].parkingState = .native
                            targetScope.stages[editedIndex].origin = nil
                            targetScope.stages[editedIndex].hostDisplayID = nil
                        }
                        restoredStage.id = uniqueRestoredStageID(originalStageID, in: targetScope)
                        let position = parkedStage.origin?.position ?? Int.max
                        let index = position <= 1 ? 0 : min(position - 1, targetScope.stages.count)
                        targetScope.stages.insert(restoredStage, at: index)
                    }
                }
                state.update(targetScope)
                restoredCount += sortedStages.count
            }

            if state.activeDisplayID.map({ !Set(liveDisplays.map(\.id)).contains($0) }) == true {
                state.activeDisplayID = liveDisplays.first(where: \.isMain)?.id ?? liveDisplays.first?.id
            }

            return DisplayParkingReport(
                kind: .restore,
                reason: .displayRestored,
                originDisplayID: origin.displayID,
                originLogicalDisplayID: logicalDisplayID,
                restoredDisplayID: restoredDisplayID,
                restoredStageCount: restoredCount,
                candidateDisplayIDs: decision.candidateDisplayIDs,
                confidence: decision.confidence
            )
        }

        return nil
    }

    private func hostDisplay(for state: PersistentStageState, liveDisplays: [DisplaySnapshot]) -> DisplaySnapshot? {
        if let activeDisplayID = state.activeDisplayID,
           let active = liveDisplays.first(where: { $0.id == activeDisplayID }) {
            return active
        }
        if let main = liveDisplays.first(where: \.isMain) {
            return main
        }
        return liveDisplays.sorted { lhs, rhs in lhs.index < rhs.index }.first
    }

    private func stampLiveDisplayMetadata(state: inout PersistentStageState, liveDisplays: [DisplaySnapshot]) {
        for display in liveDisplays {
            guard let index = state.scopes.firstIndex(where: { $0.displayID == display.id }) else { continue }
            if state.scopes[index].logicalDisplayID == nil {
                state.scopes[index].logicalDisplayID = LogicalDisplayID(displayID: display.id)
            }
            state.scopes[index].lastKnownDisplayFingerprint = DisplayFingerprint(display: display)
        }
    }

    private func uniqueParkedStageID(
        originDisplayID: DisplayID,
        originStageID: StageID,
        in scope: PersistentStageScope
    ) -> StageID {
        let base = "parked-\(sanitized(originDisplayID.rawValue))-\(originStageID.rawValue)"
        var candidate = StageID(rawValue: base)
        var suffix = 2
        let existing = Set(scope.stages.map(\.id))
        while existing.contains(candidate) {
            candidate = StageID(rawValue: "\(base)-\(suffix)")
            suffix += 1
        }
        return candidate
    }

    private func uniqueRestoredStageID(_ originalStageID: StageID, in scope: PersistentStageScope) -> StageID {
        var candidate = originalStageID
        var suffix = 2
        let existing = Set(scope.stages.map(\.id))
        while existing.contains(candidate) {
            candidate = StageID(rawValue: "\(originalStageID.rawValue)-restored-\(suffix)")
            suffix += 1
        }
        return candidate
    }

    private func restoreCandidates(in state: PersistentStageState) -> [RestoreCandidate] {
        state.scopes.flatMap { scope in
            scope.stages.compactMap { stage -> RestoreCandidate? in
                guard let origin = stage.origin, !stage.members.isEmpty else { return nil }
                let isElsewhere = scope.displayID != origin.displayID
                    && scope.logicalDisplayID != origin.logicalDisplayID
                let hasPendingReturn = stage.parkingState == .parked
                    || (stage.parkingState == .restored && hasPendingPlaceholder(for: origin, in: state))
                guard isElsewhere, hasPendingReturn else { return nil }
                return RestoreCandidate(displayID: scope.displayID, desktopID: scope.desktopID, stage: stage)
            }
        }
    }

    private func hasPendingPlaceholder(for origin: StageOrigin, in state: PersistentStageState) -> Bool {
        // Un ancien état « restored » sans placeholder ne prouve pas qu'un retour
        // reste attendu : la stage a pu être déplacée volontairement entre-temps.
        state.scopes.contains { scope in
            scope.desktopID == origin.desktopID
                && (scope.displayID == origin.displayID || scope.logicalDisplayID == origin.logicalDisplayID)
                && scope.stages.contains { stage in
                    stage.id == origin.stageID && stage.parkingState == .parked && stage.origin == origin
                }
        }
    }

    private func isIntactPlaceholder(_ stage: PersistentStage) -> Bool {
        guard stage.parkingState == .parked, stage.members.isEmpty, let origin = stage.origin else { return false }
        // Les anciens fichiers ne mémorisent pas le mode. Préserver un mode personnalisé
        // plutôt que de risquer de supprimer une modification non identifiable.
        return stage.name == origin.nameAtParking && stage.mode == (origin.modeAtParking ?? .bsp)
    }

    private func removeRestoreCandidates(_ candidates: [RestoreCandidate], from state: inout PersistentStageState) {
        for scopeIndex in state.scopes.indices {
            let scope = state.scopes[scopeIndex]
            let localCandidates = candidates.filter { $0.displayID == scope.displayID && $0.desktopID == scope.desktopID }
            guard !localCandidates.isEmpty else { continue }
            state.scopes[scopeIndex].stages.removeAll { stage in
                localCandidates.contains { $0.stage.id == stage.id && $0.stage.origin == stage.origin }
                    && !stage.members.isEmpty
            }
            if !state.scopes[scopeIndex].stages.contains(where: { $0.id == state.scopes[scopeIndex].activeStageID }),
               let firstStage = firstSelectableStage(in: state.scopes[scopeIndex]) {
                state.scopes[scopeIndex].activeStageID = firstStage.id
            }
        }
    }

    @discardableResult
    private func pruneEmptyParkedResidues(state: inout PersistentStageState) -> Int {
        var prunedCount = 0
        let originsWithCopies = restoreCandidates(in: state).compactMap { $0.stage.origin }
        for scopeIndex in state.scopes.indices {
            let beforeCount = state.scopes[scopeIndex].stages.count
            state.scopes[scopeIndex].stages = state.scopes[scopeIndex].stages.compactMap { stage in
                guard stage.parkingState == .parked, let origin = stage.origin, stage.members.isEmpty else { return stage }
                if originsWithCopies.contains(origin) { return stage }
                if isIntactPlaceholder(stage) { return nil }
                var editedStage = stage
                editedStage.parkingState = .native
                editedStage.origin = nil
                editedStage.hostDisplayID = nil
                return editedStage
            }
            let removedCount = beforeCount - state.scopes[scopeIndex].stages.count
            guard removedCount > 0 else { continue }

            prunedCount += removedCount
            if state.scopes[scopeIndex].stages.isEmpty {
                state.scopes[scopeIndex].stages = [PersistentStage(id: state.scopes[scopeIndex].activeStageID)]
            } else if !state.scopes[scopeIndex].stages.contains(where: { $0.id == state.scopes[scopeIndex].activeStageID }),
                      let firstStage = firstSelectableStage(in: state.scopes[scopeIndex]) {
                state.scopes[scopeIndex].activeStageID = firstStage.id
            }
        }
        return prunedCount
    }

    private func materializeExpiredParkedStages(
        state: inout PersistentStageState,
        liveDisplays: [DisplaySnapshot],
        now: Date,
        minimumParkedAge: TimeInterval = 60
    ) -> Int {
        let liveDisplayIDs = Set(liveDisplays.map(\.id))
        var recoveredCount = 0

        for scopeIndex in state.scopes.indices where liveDisplayIDs.contains(state.scopes[scopeIndex].displayID) {
            var scope = state.scopes[scopeIndex]
            var remappedActiveStageID: StageID?

            var stageIndex = scope.stages.startIndex
            while stageIndex < scope.stages.endIndex {
                let stage = scope.stages[stageIndex]
                guard stage.parkingState == .parked,
                      let origin = stage.origin,
                      !stage.members.isEmpty,
                      now.timeIntervalSince(origin.parkedAt) >= minimumParkedAge
                else {
                    stageIndex += 1
                    continue
                }

                let fingerprint = fingerprintForRestore(
                    state: state,
                    origin: origin,
                    logicalDisplayID: origin.logicalDisplayID
                )
                let decision = DisplayTopology.recognizeDisplay(for: fingerprint, in: liveDisplays)
                guard decision.displayID == nil, !decision.isAmbiguous else {
                    stageIndex += 1
                    continue
                }

                let originalID = stage.id
                var recoveredStage = stage
                let preferredID = materializedStageID(for: recoveredStage, in: scope, excluding: stageIndex)
                recoveredStage.id = preferredID
                recoveredStage.parkingState = .restored
                recoveredStage.hostDisplayID = nil
                recoveredStage.restoredAt = now
                if preferredID != originalID,
                   let emptyConflictIndex = scope.stages.firstIndex(where: {
                       $0.id == preferredID && canReuseMaterializationSlot($0, for: stage)
                   }) {
                    scope.stages[emptyConflictIndex] = recoveredStage
                    scope.stages.remove(at: stageIndex)
                } else {
                    scope.stages[stageIndex] = recoveredStage
                }

                if scope.activeStageID == originalID {
                    remappedActiveStageID = preferredID
                }
                recoveredCount += 1
                stageIndex = scope.stages.startIndex
            }

            if let remappedActiveStageID {
                scope.activeStageID = remappedActiveStageID
            }
            if !scope.stages.contains(where: { $0.id == scope.activeStageID }),
               let fallback = firstSelectableStage(in: scope) {
                scope.activeStageID = fallback.id
            }
            state.scopes[scopeIndex] = scope
        }

        return recoveredCount
    }

    private func materializedStageID(
        for stage: PersistentStage,
        in scope: PersistentStageScope,
        excluding excludedIndex: Int
    ) -> StageID {
        if let sameNameEmpty = scope.stages.enumerated().first(where: { item in
            item.offset != excludedIndex
                && item.element.parkingState != .parked
                && canReuseMaterializationSlot(item.element, for: stage)
        })?.element.id {
            return sameNameEmpty
        }

        let preferred = stage.origin?.stageID ?? stage.id
        let existing = scope.stages.enumerated().filter { $0.offset != excludedIndex }
        if !existing.contains(where: { $0.element.id == preferred }) {
            return preferred
        }
        if existing.contains(where: { $0.element.id == preferred && canReuseMaterializationSlot($0.element, for: stage) }) {
            return preferred
        }

        var suffix = 2
        var candidate = StageID(rawValue: "\(preferred.rawValue)-recovered-\(suffix)")
        while existing.contains(where: { $0.element.id == candidate }) {
            suffix += 1
            candidate = StageID(rawValue: "\(preferred.rawValue)-recovered-\(suffix)")
        }
        return candidate
    }

    private func canReuseMaterializationSlot(_ slot: PersistentStage, for stage: PersistentStage) -> Bool {
        slot.parkingState != .parked && slot.members.isEmpty
            && slot.name == stage.name && slot.mode == stage.mode
            && slot.groups.isEmpty && slot.bspTree == nil
    }

    private func firstSelectableStage(in scope: PersistentStageScope) -> PersistentStage? {
        scope.stages.first { $0.parkingState != .parked || !$0.members.isEmpty }
            ?? scope.stages.first
    }

    private func fingerprintForRestore(
        state: PersistentStageState,
        origin: StageOrigin,
        logicalDisplayID: LogicalDisplayID
    ) -> DisplayFingerprint {
        if let scope = state.scopes.first(where: {
            $0.logicalDisplayID == logicalDisplayID || $0.displayID == origin.displayID
        }),
           let fingerprint = scope.lastKnownDisplayFingerprint {
            return fingerprint
        }
        return DisplayFingerprint(
            nameKey: "",
            sizeKey: "",
            visibleSizeKey: "",
            positionKey: "",
            mainHint: false,
            previousDisplayID: origin.displayID
        )
    }

    private func sanitized(_ raw: String) -> String {
        raw.map { char in
            char.isLetter || char.isNumber ? char : "-"
        }
        .reduce(into: "") { result, char in
            if char == "-", result.last == "-" { return }
            result.append(char)
        }
        .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }
}
