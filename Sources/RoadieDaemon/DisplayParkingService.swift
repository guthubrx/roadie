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
        var firstOriginDisplayID: DisplayID?
        var firstLogicalDisplayID: LogicalDisplayID?

        for scopeIndex in staleScopeIndexes {
            var staleScope = state.scopes[scopeIndex]
            let logicalDisplayID = staleScope.logicalDisplayID ?? LogicalDisplayID(displayID: staleScope.displayID)
            staleScope.logicalDisplayID = logicalDisplayID
            firstOriginDisplayID = firstOriginDisplayID ?? staleScope.displayID
            firstLogicalDisplayID = firstLogicalDisplayID ?? logicalDisplayID

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
                    parkedAt: now
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
        let parkedStages = state.scopes
            .flatMap { scope in scope.stages }
            .filter { $0.parkingState == .parked && $0.origin != nil && !$0.members.isEmpty }
        guard !parkedStages.isEmpty else { return nil }

        let grouped = Dictionary(grouping: parkedStages) { stage in
            stage.origin!.logicalDisplayID
        }

        for (logicalDisplayID, stages) in grouped {
            guard let origin = stages.compactMap(\.origin).first else { continue }
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

            let sortedStages = stages.sorted {
                ($0.origin?.position ?? Int.max, $0.id.rawValue) < ($1.origin?.position ?? Int.max, $1.id.rawValue)
            }
            let parkedIDs = Set(sortedStages.map(\.id))
            removeParkedStages(parkedIDs, from: &state)

            var targetScope = state.scope(displayID: restoredDisplayID, desktopID: origin.desktopID)
            targetScope.logicalDisplayID = logicalDisplayID
            if let display = liveDisplays.first(where: { $0.id == restoredDisplayID }) {
                targetScope.lastKnownDisplayFingerprint = DisplayFingerprint(display: display)
            }

            for parkedStage in sortedStages {
                var restoredStage = parkedStage
                let originalStageID = parkedStage.origin?.stageID ?? parkedStage.id
                targetScope.stages.removeAll { stage in
                    stage.id == originalStageID
                        && stage.members.isEmpty
                        && stage.parkingState == .parked
                }
                restoredStage.id = uniqueRestoredStageID(originalStageID, in: targetScope)
                restoredStage.parkingState = .restored
                restoredStage.hostDisplayID = nil
                restoredStage.restoredAt = now
                targetScope.stages.append(restoredStage)
            }
            state.update(targetScope)

            if state.activeDisplayID.map({ !Set(liveDisplays.map(\.id)).contains($0) }) == true {
                state.activeDisplayID = liveDisplays.first(where: \.isMain)?.id ?? liveDisplays.first?.id
            }

            return DisplayParkingReport(
                kind: .restore,
                reason: .displayRestored,
                originDisplayID: origin.displayID,
                originLogicalDisplayID: logicalDisplayID,
                restoredDisplayID: restoredDisplayID,
                restoredStageCount: sortedStages.count,
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

    private func removeParkedStages(_ parkedIDs: Set<StageID>, from state: inout PersistentStageState) {
        for scopeIndex in state.scopes.indices {
            state.scopes[scopeIndex].stages.removeAll { stage in
                parkedIDs.contains(stage.id) && stage.parkingState == .parked && !stage.members.isEmpty
            }
            if !state.scopes[scopeIndex].stages.contains(where: { $0.id == state.scopes[scopeIndex].activeStageID }),
               let firstStage = state.scopes[scopeIndex].stages.first {
                state.scopes[scopeIndex].activeStageID = firstStage.id
            }
        }
    }

    @discardableResult
    private func pruneEmptyParkedResidues(state: inout PersistentStageState) -> Int {
        var prunedCount = 0
        for scopeIndex in state.scopes.indices {
            let beforeCount = state.scopes[scopeIndex].stages.count
            state.scopes[scopeIndex].stages.removeAll { stage in
                stage.parkingState == .parked
                    && stage.origin != nil
                    && stage.members.isEmpty
            }
            let removedCount = beforeCount - state.scopes[scopeIndex].stages.count
            guard removedCount > 0 else { continue }

            prunedCount += removedCount
            if state.scopes[scopeIndex].stages.isEmpty {
                state.scopes[scopeIndex].stages = [PersistentStage(id: state.scopes[scopeIndex].activeStageID)]
            } else if !state.scopes[scopeIndex].stages.contains(where: { $0.id == state.scopes[scopeIndex].activeStageID }),
                      let firstStage = state.scopes[scopeIndex].stages.first {
                state.scopes[scopeIndex].activeStageID = firstStage.id
            }
        }
        return prunedCount
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
