import Foundation
import RoadieAX
import RoadieCore
import RoadieStages

public struct LogicalDisplayID: RawRepresentable, Hashable, Codable, Sendable, CustomStringConvertible {
    public let rawValue: String

    public init(rawValue: String) {
        precondition(!rawValue.isEmpty, "LogicalDisplayID must not be empty")
        self.rawValue = rawValue
    }

    public init(displayID: DisplayID) {
        self.init(rawValue: "display:\(displayID.rawValue)")
    }

    public var description: String { rawValue }
}

public struct DisplayFingerprint: Equatable, Codable, Sendable {
    public var nameKey: String
    public var sizeKey: String
    public var visibleSizeKey: String
    public var positionKey: String
    public var mainHint: Bool
    public var previousDisplayID: DisplayID?

    public init(
        nameKey: String,
        sizeKey: String,
        visibleSizeKey: String,
        positionKey: String,
        mainHint: Bool,
        previousDisplayID: DisplayID? = nil
    ) {
        self.nameKey = nameKey
        self.sizeKey = sizeKey
        self.visibleSizeKey = visibleSizeKey
        self.positionKey = positionKey
        self.mainHint = mainHint
        self.previousDisplayID = previousDisplayID
    }

    public init(display: DisplaySnapshot) {
        self.init(
            nameKey: Self.normalized(display.name),
            sizeKey: Self.sizeKey(display.frame),
            visibleSizeKey: Self.sizeKey(display.visibleFrame),
            positionKey: Self.positionKey(display.frame),
            mainHint: display.isMain,
            previousDisplayID: display.id
        )
    }

    private static func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .lowercased()
    }

    private static func sizeKey(_ rect: Rect) -> String {
        "\(Int(rect.width.rounded()))x\(Int(rect.height.rounded()))"
    }

    private static func positionKey(_ rect: Rect) -> String {
        "\(Int(rect.x.rounded())):\(Int(rect.y.rounded()))"
    }
}

public enum StageParkingState: String, Codable, Sendable {
    case native
    case parked
    case restored
}

public struct StageOrigin: Equatable, Codable, Sendable {
    public var logicalDisplayID: LogicalDisplayID
    public var displayID: DisplayID
    public var desktopID: DesktopID
    public var stageID: StageID
    public var position: Int
    public var nameAtParking: String
    public var parkedAt: Date

    public init(
        logicalDisplayID: LogicalDisplayID,
        displayID: DisplayID,
        desktopID: DesktopID,
        stageID: StageID,
        position: Int,
        nameAtParking: String,
        parkedAt: Date
    ) {
        self.logicalDisplayID = logicalDisplayID
        self.displayID = displayID
        self.desktopID = desktopID
        self.stageID = stageID
        self.position = position
        self.nameAtParking = nameAtParking
        self.parkedAt = parkedAt
    }
}

public enum ParkingSessionStatus: String, Codable, Sendable {
    case active
    case restored
    case ambiguous
    case abandoned
}

public struct ParkingSessionState: Equatable, Codable, Sendable {
    public var sessionID: String
    public var originLogicalDisplayID: LogicalDisplayID
    public var originDisplayID: DisplayID
    public var hostDisplayID: DisplayID
    public var startedAt: Date
    public var restoredAt: Date?
    public var stageIDs: [StageID]
    public var status: ParkingSessionStatus

    public init(
        sessionID: String,
        originLogicalDisplayID: LogicalDisplayID,
        originDisplayID: DisplayID,
        hostDisplayID: DisplayID,
        startedAt: Date,
        restoredAt: Date? = nil,
        stageIDs: [StageID],
        status: ParkingSessionStatus = .active
    ) {
        self.sessionID = sessionID
        self.originLogicalDisplayID = originLogicalDisplayID
        self.originDisplayID = originDisplayID
        self.hostDisplayID = hostDisplayID
        self.startedAt = startedAt
        self.restoredAt = restoredAt
        self.stageIDs = stageIDs
        self.status = status
    }
}

public struct StageStore: Sendable {
    private let url: URL

    public init(path: String = Self.defaultPath()) {
        self.url = URL(fileURLWithPath: NSString(string: path).expandingTildeInPath)
    }

    public static func defaultPath() -> String {
        if ProcessInfo.processInfo.processName.lowercased().contains("test") {
            return "\(NSTemporaryDirectory())roadie-test-stages-\(ProcessInfo.processInfo.processIdentifier)-\(UUID().uuidString).json"
        }
        return "~/.roadies/stages.json"
    }

    public func state() -> PersistentStageState {
        load()
    }

    public func save(_ state: PersistentStageState) {
        write(state)
    }

    private func load() -> PersistentStageState {
        JSONPersistence.load(PersistentStageState.self, from: url, default: PersistentStageState())
    }

    private func write(_ state: PersistentStageState) {
        JSONPersistence.write(state, to: url, label: "stages")
    }
}

public struct PersistentStageState: Equatable, Codable, Sendable {
    public var scopes: [PersistentStageScope]
    public var desktopSelections: [PersistentDesktopSelection]
    public var desktopLabels: [PersistentDesktopLabel]
    public var windowPins: [PersistentWindowPin]
    public var windowBookmarks: [PersistentWindowBookmark]
    public var rulePlacementOverrides: [PersistentRulePlacementOverride]
    public var activeDisplayID: DisplayID?
    public var commandFocusProtection: CommandFocusProtection?

    public init(
        scopes: [PersistentStageScope] = [],
        desktopSelections: [PersistentDesktopSelection] = [],
        desktopLabels: [PersistentDesktopLabel] = [],
        windowPins: [PersistentWindowPin] = [],
        windowBookmarks: [PersistentWindowBookmark] = [],
        rulePlacementOverrides: [PersistentRulePlacementOverride] = [],
        activeDisplayID: DisplayID? = nil,
        commandFocusProtection: CommandFocusProtection? = nil
    ) {
        self.scopes = scopes
        self.desktopSelections = desktopSelections
        self.desktopLabels = desktopLabels
        self.windowPins = Self.uniquePins(windowPins)
        self.windowBookmarks = Self.uniqueBookmarks(windowBookmarks)
        self.rulePlacementOverrides = Self.uniqueRulePlacementOverrides(rulePlacementOverrides)
        self.activeDisplayID = activeDisplayID
        self.commandFocusProtection = commandFocusProtection
    }

    enum CodingKeys: String, CodingKey {
        case scopes
        case desktopSelections
        case desktopLabels
        case windowPins
        case windowBookmarks
        case rulePlacementOverrides
        case activeDisplayID
        case commandFocusProtection
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.scopes = try c.decodeIfPresent([PersistentStageScope].self, forKey: .scopes) ?? []
        self.desktopSelections = try c.decodeIfPresent([PersistentDesktopSelection].self, forKey: .desktopSelections) ?? []
        self.desktopLabels = try c.decodeIfPresent([PersistentDesktopLabel].self, forKey: .desktopLabels) ?? []
        self.windowPins = Self.uniquePins(try c.decodeIfPresent([PersistentWindowPin].self, forKey: .windowPins) ?? [])
        self.windowBookmarks = Self.uniqueBookmarks(try c.decodeIfPresent([PersistentWindowBookmark].self, forKey: .windowBookmarks) ?? [])
        self.rulePlacementOverrides = Self.uniqueRulePlacementOverrides(try c.decodeIfPresent([PersistentRulePlacementOverride].self, forKey: .rulePlacementOverrides) ?? [])
        self.activeDisplayID = try c.decodeIfPresent(DisplayID.self, forKey: .activeDisplayID)
        self.commandFocusProtection = try c.decodeIfPresent(CommandFocusProtection.self, forKey: .commandFocusProtection)
    }

    private static func uniquePins(_ pins: [PersistentWindowPin]) -> [PersistentWindowPin] {
        var byWindow: [WindowID: PersistentWindowPin] = [:]
        for pin in pins {
            byWindow[pin.windowID] = pin
        }
        return byWindow.values.sorted { $0.windowID.rawValue < $1.windowID.rawValue }
    }

    private static func uniqueBookmarks(_ bookmarks: [PersistentWindowBookmark]) -> [PersistentWindowBookmark] {
        var byName: [String: PersistentWindowBookmark] = [:]
        for bookmark in bookmarks {
            byName[bookmark.name] = bookmark
        }
        return byName.values.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private static func uniqueRulePlacementOverrides(_ overrides: [PersistentRulePlacementOverride]) -> [PersistentRulePlacementOverride] {
        var byWindow: [WindowID: PersistentRulePlacementOverride] = [:]
        for override in overrides {
            byWindow[override.windowID] = override
        }
        return byWindow.values.sorted { $0.windowID.rawValue < $1.windowID.rawValue }
    }

    public mutating func scope(
        displayID: DisplayID,
        desktopID: DesktopID = DesktopID(rawValue: 1),
        defaultMode: WindowManagementMode = .bsp
    ) -> PersistentStageScope {
        if let existing = scopes.first(where: { $0.displayID == displayID && $0.desktopID == desktopID }) {
            return existing
        }
        let created = PersistentStageScope(displayID: displayID, desktopID: desktopID, defaultMode: defaultMode)
        scopes.append(created)
        return created
    }

    public mutating func update(_ scope: PersistentStageScope) {
        scopes.removeAll { $0.displayID == scope.displayID && $0.desktopID == scope.desktopID }
        scopes.append(scope)
    }

    // Complexite : O(scopes * stages * members) au pire en lookup unique.
    // Si plusieurs lookups consecutifs sont prevus, utiliser stageScopeIndex() pour
    // construire un index inverse une seule fois (O(total_members)) puis lookups O(1).
    public func stageScope(for windowID: WindowID) -> StageScope? {
        for scope in scopes {
            for stage in scope.stages where stage.members.contains(where: { $0.windowID == windowID }) {
                return StageScope(displayID: scope.displayID, desktopID: scope.desktopID, stageID: stage.id)
            }
        }
        return nil
    }

    // Complexite : O(total_members). Index inverse pour batch lookups.
    public func stageScopeIndex() -> [WindowID: StageScope] {
        var index: [WindowID: StageScope] = [:]
        for scope in scopes {
            for stage in scope.stages {
                let stageScope = StageScope(displayID: scope.displayID, desktopID: scope.desktopID, stageID: stage.id)
                for member in stage.members {
                    index[member.windowID] = stageScope
                }
            }
        }
        return index
    }

    public func pin(for windowID: WindowID) -> PersistentWindowPin? {
        windowPins.first { $0.windowID == windowID }
    }

    public func isPinned(_ windowID: WindowID) -> Bool {
        pin(for: windowID) != nil
    }

    public func bookmark(named name: String) -> PersistentWindowBookmark? {
        windowBookmarks.first { $0.name == PersistentWindowBookmark.normalizedName(name) }
    }

    public func suppressesRulePlacement(windowID: WindowID, ruleID: String?) -> Bool {
        guard let override = rulePlacementOverrides.first(where: { $0.windowID == windowID }) else { return false }
        guard let overrideRuleID = override.ruleID, let ruleID else { return true }
        return overrideRuleID == ruleID
    }

    @discardableResult
    public mutating func suppressRulePlacement(
        window: WindowSnapshot,
        ruleID: String? = nil,
        reason: String = "manual_window_move",
        now: Date = Date()
    ) -> PersistentRulePlacementOverride {
        let createdAt = rulePlacementOverrides.first { $0.windowID == window.id }?.createdAt ?? now
        let override = PersistentRulePlacementOverride(
            windowID: window.id,
            ruleID: ruleID,
            bundleID: window.bundleID,
            title: window.title,
            reason: reason,
            createdAt: createdAt,
            updatedAt: now
        )
        rulePlacementOverrides.removeAll { $0.windowID == window.id }
        rulePlacementOverrides.append(override)
        rulePlacementOverrides = Self.uniqueRulePlacementOverrides(rulePlacementOverrides)
        return override
    }

    @discardableResult
    public mutating func removeRulePlacementOverride(windowID: WindowID) -> PersistentRulePlacementOverride? {
        guard let index = rulePlacementOverrides.firstIndex(where: { $0.windowID == windowID }) else { return nil }
        return rulePlacementOverrides.remove(at: index)
    }

    @discardableResult
    public mutating func setBookmark(
        name: String,
        window: WindowSnapshot,
        scope: StageScope,
        now: Date = Date()
    ) -> PersistentWindowBookmark {
        let normalized = PersistentWindowBookmark.normalizedName(name)
        let bookmark = PersistentWindowBookmark(
            name: normalized,
            windowID: window.id,
            scope: scope,
            bundleID: window.bundleID,
            title: window.title,
            frame: window.frame,
            createdAt: windowBookmarks.first { $0.name == normalized }?.createdAt ?? now,
            updatedAt: now,
            lastSeenAt: now,
            missingSince: nil
        )
        windowBookmarks.removeAll { $0.name == normalized }
        windowBookmarks.append(bookmark)
        windowBookmarks = Self.uniqueBookmarks(windowBookmarks)
        return bookmark
    }

    @discardableResult
    public mutating func removeBookmark(named name: String) -> PersistentWindowBookmark? {
        let normalized = PersistentWindowBookmark.normalizedName(name)
        guard let index = windowBookmarks.firstIndex(where: { $0.name == normalized }) else { return nil }
        return windowBookmarks.remove(at: index)
    }

    @discardableResult
    public mutating func removeBookmarks(for windowID: WindowID) -> [PersistentWindowBookmark] {
        let removed = windowBookmarks.filter { $0.windowID == windowID }
        windowBookmarks.removeAll { $0.windowID == windowID }
        return removed
    }

    @discardableResult
    public mutating func pruneMissingBookmarks(
        keeping liveWindowIDs: Set<WindowID>,
        missingGrace: TimeInterval = 45,
        now: Date = Date()
    ) -> [PersistentWindowBookmark] {
        var pruned: [PersistentWindowBookmark] = []
        for index in windowBookmarks.indices {
            if liveWindowIDs.contains(windowBookmarks[index].windowID) {
                windowBookmarks[index].lastSeenAt = now
                windowBookmarks[index].missingSince = nil
            } else if let missingSince = windowBookmarks[index].missingSince {
                if now.timeIntervalSince(missingSince) >= missingGrace {
                    pruned.append(windowBookmarks[index])
                }
            } else {
                windowBookmarks[index].missingSince = now
            }
        }
        guard !pruned.isEmpty else { return [] }
        let prunedNames = Set(pruned.map(\.name))
        windowBookmarks.removeAll { prunedNames.contains($0.name) }
        return pruned
    }

    public mutating func updateBookmarkObservation(window: WindowSnapshot, scope: StageScope, now: Date = Date()) {
        for index in windowBookmarks.indices where windowBookmarks[index].windowID == window.id {
            windowBookmarks[index].scope = scope
            windowBookmarks[index].bundleID = window.bundleID
            windowBookmarks[index].title = window.title
            windowBookmarks[index].frame = window.frame
            windowBookmarks[index].lastSeenAt = now
            windowBookmarks[index].missingSince = nil
        }
    }

    @discardableResult
    public mutating func setPin(
        window: WindowSnapshot,
        homeScope: StageScope,
        pinScope: WindowPinScope,
        now: Date = Date()
    ) -> PinMutation {
        if let index = windowPins.firstIndex(where: { $0.windowID == window.id }) {
            let previous = windowPins[index]
            windowPins[index].homeScope = homeScope
            windowPins[index].pinScope = pinScope
            windowPins[index].bundleID = window.bundleID
            windowPins[index].title = window.title
            windowPins[index].lastFrame = window.frame
            windowPins[index].updatedAt = now
            return PinMutation(
                pin: windowPins[index],
                previous: previous,
                created: false,
                scopeChanged: previous.pinScope != pinScope
            )
        }

        let pin = PersistentWindowPin(
            windowID: window.id,
            homeScope: homeScope,
            pinScope: pinScope,
            bundleID: window.bundleID,
            title: window.title,
            lastFrame: window.frame,
            createdAt: now,
            updatedAt: now
        )
        windowPins.append(pin)
        return PinMutation(pin: pin, previous: nil, created: true, scopeChanged: false)
    }

    @discardableResult
    public mutating func removePin(windowID: WindowID) -> PersistentWindowPin? {
        guard let index = windowPins.firstIndex(where: { $0.windowID == windowID }) else { return nil }
        return windowPins.remove(at: index)
    }

    @discardableResult
    public mutating func pruneMissingPins(keeping liveWindowIDs: Set<WindowID>) -> [PersistentWindowPin] {
        let pruned = windowPins.filter { !liveWindowIDs.contains($0.windowID) }
        guard !pruned.isEmpty else { return [] }
        windowPins.removeAll { !liveWindowIDs.contains($0.windowID) }
        return pruned
    }

    public mutating func updatePinFrame(window: WindowSnapshot, now: Date = Date()) {
        guard let index = windowPins.firstIndex(where: { $0.windowID == window.id }) else { return }
        windowPins[index].bundleID = window.bundleID
        windowPins[index].title = window.title
        windowPins[index].lastFrame = window.frame
        windowPins[index].updatedAt = now
    }

    @discardableResult
    public mutating func updatePinHomeScope(windowID: WindowID, to scope: StageScope?, now: Date = Date()) -> PersistentWindowPin? {
        guard let scope,
              let index = windowPins.firstIndex(where: { $0.windowID == windowID })
        else { return nil }
        windowPins[index].homeScope = scope
        windowPins[index].updatedAt = now
        return windowPins[index]
    }

    public mutating func reconcileWindowIDs(with liveWindows: [WindowSnapshot]) {
        let tileableWindows = liveWindows.filter(\.isTileCandidate)
        let liveWindowIDs = Set(tileableWindows.map(\.id))
        var claimedWindowIDs = Set<WindowID>()
        for scope in scopes {
            for stage in scope.stages {
                for member in stage.members where liveWindowIDs.contains(member.windowID) {
                    claimedWindowIDs.insert(member.windowID)
                }
            }
        }

        var windowsBySignature: [StableWindowSignature: [WindowSnapshot]] = [:]
        for window in tileableWindows {
            windowsBySignature[StableWindowSignature(window: window), default: []].append(window)
        }

        var remapped: [WindowID: WindowID] = [:]
        for scopeIndex in scopes.indices {
            for stageIndex in scopes[scopeIndex].stages.indices {
                for memberIndex in scopes[scopeIndex].stages[stageIndex].members.indices {
                    let member = scopes[scopeIndex].stages[stageIndex].members[memberIndex]
                    guard !liveWindowIDs.contains(member.windowID),
                          let replacement = bestReplacement(
                              for: member,
                              in: windowsBySignature[StableWindowSignature(member: member)] ?? [],
                              claimed: claimedWindowIDs
                          )
                    else { continue }

                    remapped[member.windowID] = replacement.id
                    claimedWindowIDs.insert(replacement.id)
                    scopes[scopeIndex].stages[stageIndex].members[memberIndex].windowID = replacement.id
                    scopes[scopeIndex].stages[stageIndex].members[memberIndex].bundleID = replacement.bundleID
                    scopes[scopeIndex].stages[stageIndex].members[memberIndex].title = replacement.title
                    scopes[scopeIndex].stages[stageIndex].members[memberIndex].frame = replacement.frame
                }
            }
        }

        guard !remapped.isEmpty else { return }
        for index in windowPins.indices {
            guard let replacementID = remapped[windowPins[index].windowID] else { continue }
            windowPins[index].windowID = replacementID
        }
        for index in windowBookmarks.indices {
            guard let replacementID = remapped[windowBookmarks[index].windowID] else { continue }
            windowBookmarks[index].windowID = replacementID
        }
        for scopeIndex in scopes.indices {
            for stageIndex in scopes[scopeIndex].stages.indices {
                var stage = scopes[scopeIndex].stages[stageIndex]
                if let focused = stage.focusedWindowID, let replacement = remapped[focused] {
                    stage.focusedWindowID = replacement
                }
                if let previous = stage.previousFocusedWindowID, let replacement = remapped[previous] {
                    stage.previousFocusedWindowID = replacement
                }
                stage.groups = stage.groups.compactMap { group in
                    var updated = group
                    updated.windowIDs = updated.windowIDs.map { remapped[$0] ?? $0 }
                    var seen: Set<WindowID> = []
                    updated.windowIDs = updated.windowIDs.filter { seen.insert($0).inserted }
                    if let active = updated.activeWindowID, let replacement = remapped[active] {
                        updated.activeWindowID = replacement
                    }
                    return updated.windowIDs.count >= 2 ? updated : nil
                }
                scopes[scopeIndex].stages[stageIndex] = stage
            }
        }
    }

    @discardableResult
    public mutating func pruneMissingWindows(
        keeping liveWindowIDs: Set<WindowID>,
        missingGrace: TimeInterval = 45,
        now: Date = Date()
    ) -> MissingWindowReconciliationReport {
        var report = MissingWindowReconciliationReport()
        for scopeIndex in scopes.indices {
            report.merge(scopes[scopeIndex].pruneMissingWindows(keeping: liveWindowIDs, missingGrace: missingGrace, now: now))
        }
        rulePlacementOverrides.removeAll { !liveWindowIDs.contains($0.windowID) }
        return report
    }

    @discardableResult
    public mutating func pruneMissingWindows(
        keeping liveWindowIDs: Set<WindowID>,
        liveDisplayIDs: Set<DisplayID>,
        missingGrace: TimeInterval = 45,
        now: Date = Date()
    ) -> MissingWindowReconciliationReport {
        var report = MissingWindowReconciliationReport()
        for scopeIndex in scopes.indices where liveDisplayIDs.contains(scopes[scopeIndex].displayID) {
            report.merge(scopes[scopeIndex].pruneMissingWindows(keeping: liveWindowIDs, missingGrace: missingGrace, now: now))
        }
        rulePlacementOverrides.removeAll { !liveWindowIDs.contains($0.windowID) }
        return report
    }

    public mutating func remove(windowID: WindowID) {
        for scopeIndex in scopes.indices {
            scopes[scopeIndex].remove(windowID: windowID)
        }
    }

    public func currentDesktopID(for displayID: DisplayID) -> DesktopID {
        desktopSelections.first { $0.displayID == displayID }?.currentDesktopID ?? DesktopID(rawValue: 1)
    }

    public func lastDesktopID(for displayID: DisplayID) -> DesktopID? {
        desktopSelections.first { $0.displayID == displayID }?.lastDesktopID
    }

    public mutating func focusDisplay(_ displayID: DisplayID) {
        activeDisplayID = displayID
    }

    public func label(displayID: DisplayID, desktopID: DesktopID) -> String? {
        desktopLabels.first { $0.displayID == displayID && $0.desktopID == desktopID }?.label
    }

    public mutating func setLabel(_ label: String, displayID: DisplayID, desktopID: DesktopID) {
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        desktopLabels.removeAll { $0.displayID == displayID && $0.desktopID == desktopID }
        guard !trimmed.isEmpty else { return }
        desktopLabels.append(PersistentDesktopLabel(displayID: displayID, desktopID: desktopID, label: trimmed))
    }

    public mutating func switchDesktop(displayID: DisplayID, to desktopID: DesktopID) {
        if let index = desktopSelections.firstIndex(where: { $0.displayID == displayID }) {
            let current = desktopSelections[index].currentDesktopID
            if current != desktopID {
                desktopSelections[index].lastDesktopID = current
                desktopSelections[index].currentDesktopID = desktopID
            }
        } else {
            desktopSelections.append(PersistentDesktopSelection(
                displayID: displayID,
                currentDesktopID: desktopID,
                lastDesktopID: desktopID == DesktopID(rawValue: 1) ? nil : DesktopID(rawValue: 1)
            ))
        }
    }

    public mutating func protectCommandFocus(
        displayID: DisplayID,
        desktopID: DesktopID,
        stageID: StageID,
        windowID: WindowID?,
        now: Date = Date(),
        duration: TimeInterval = 2.0
    ) {
        commandFocusProtection = CommandFocusProtection(
            displayID: displayID,
            desktopID: desktopID,
            stageID: stageID,
            windowID: windowID,
            expiresAt: now.addingTimeInterval(duration)
        )
    }

    public mutating func pruneExpiredCommandFocusProtection(now: Date = Date()) {
        if commandFocusProtection.map({ $0.expiresAt <= now }) == true {
            commandFocusProtection = nil
        }
    }

    public func commandFocusProtectionBlocks(
        focusedScope: StageScope,
        focusedWindowID: WindowID?,
        now: Date = Date()
    ) -> Bool {
        guard let protection = commandFocusProtection,
              protection.expiresAt > now,
              protection.displayID == focusedScope.displayID
        else { return false }

        let protectedScope = StageScope(
            displayID: protection.displayID,
            desktopID: protection.desktopID,
            stageID: protection.stageID
        )
        if focusedScope == protectedScope { return false }
        if let protectedWindowID = protection.windowID,
           focusedWindowID == protectedWindowID {
            return false
        }
        return true
    }
}

public struct CommandFocusProtection: Equatable, Codable, Sendable {
    public var displayID: DisplayID
    public var desktopID: DesktopID
    public var stageID: StageID
    public var windowID: WindowID?
    public var expiresAt: Date

    public init(
        displayID: DisplayID,
        desktopID: DesktopID,
        stageID: StageID,
        windowID: WindowID?,
        expiresAt: Date
    ) {
        self.displayID = displayID
        self.desktopID = desktopID
        self.stageID = stageID
        self.windowID = windowID
        self.expiresAt = expiresAt
    }
}

public enum WindowPinScope: String, Codable, Sendable {
    case desktop
    case allDesktops = "all_desktops"
}

public struct PersistentWindowPin: Equatable, Codable, Sendable {
    public var windowID: WindowID
    public var homeScope: StageScope
    public var pinScope: WindowPinScope
    public var bundleID: String
    public var title: String
    public var lastFrame: Rect
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        windowID: WindowID,
        homeScope: StageScope,
        pinScope: WindowPinScope,
        bundleID: String,
        title: String,
        lastFrame: Rect,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.windowID = windowID
        self.homeScope = homeScope
        self.pinScope = pinScope
        self.bundleID = bundleID
        self.title = title
        self.lastFrame = lastFrame
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public func visibility(in activeScope: StageScope?) -> PinVisibilityDecision {
        guard let activeScope,
              activeScope.displayID == homeScope.displayID
        else {
            return PinVisibilityDecision(
                windowID: windowID,
                shouldBeVisible: false,
                effectiveScope: nil,
                homeScope: homeScope,
                reason: .outOfScope
            )
        }

        if activeScope == homeScope {
            return PinVisibilityDecision(
                windowID: windowID,
                shouldBeVisible: true,
                effectiveScope: activeScope,
                homeScope: homeScope,
                reason: .home
            )
        }

        switch pinScope {
        case .desktop:
            return PinVisibilityDecision(
                windowID: windowID,
                shouldBeVisible: activeScope.desktopID == homeScope.desktopID,
                effectiveScope: activeScope.desktopID == homeScope.desktopID ? activeScope : nil,
                homeScope: homeScope,
                reason: activeScope.desktopID == homeScope.desktopID ? .desktopPin : .outOfScope
            )
        case .allDesktops:
            return PinVisibilityDecision(
                windowID: windowID,
                shouldBeVisible: true,
                effectiveScope: activeScope,
                homeScope: homeScope,
                reason: .allDesktopsPin
            )
        }
    }

    public var eventDetails: [String: String] {
        [
            "windowID": String(windowID.rawValue),
            "bundleID": bundleID,
            "title": title,
            "pinScope": pinScope.rawValue,
            "displayID": homeScope.displayID.rawValue,
            "desktopID": String(homeScope.desktopID.rawValue),
            "stageID": homeScope.stageID.rawValue,
        ]
    }
}

public struct PinMutation: Equatable, Sendable {
    public var pin: PersistentWindowPin
    public var previous: PersistentWindowPin?
    public var created: Bool
    public var scopeChanged: Bool
}

public struct PersistentWindowBookmark: Equatable, Codable, Sendable {
    public var name: String
    public var windowID: WindowID
    public var scope: StageScope
    public var bundleID: String
    public var title: String
    public var frame: Rect
    public var createdAt: Date
    public var updatedAt: Date
    public var lastSeenAt: Date?
    public var missingSince: Date?

    public init(
        name: String,
        windowID: WindowID,
        scope: StageScope,
        bundleID: String,
        title: String,
        frame: Rect,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        lastSeenAt: Date? = nil,
        missingSince: Date? = nil
    ) {
        self.name = Self.normalizedName(name)
        self.windowID = windowID
        self.scope = scope
        self.bundleID = bundleID
        self.title = title
        self.frame = frame
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.lastSeenAt = lastSeenAt
        self.missingSince = missingSince
    }

    public static func normalizedName(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "default" : trimmed
    }
}

public struct PersistentRulePlacementOverride: Equatable, Codable, Sendable {
    public var windowID: WindowID
    public var ruleID: String?
    public var bundleID: String
    public var title: String
    public var reason: String
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        windowID: WindowID,
        ruleID: String? = nil,
        bundleID: String,
        title: String,
        reason: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.windowID = windowID
        self.ruleID = ruleID
        self.bundleID = bundleID
        self.title = title
        self.reason = reason
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public enum PinVisibilityReason: String, Codable, Sendable {
    case home
    case desktopPin = "desktop_pin"
    case allDesktopsPin = "all_desktops_pin"
    case outOfScope = "out_of_scope"
    case stale
}

public struct PinVisibilityDecision: Equatable, Codable, Sendable {
    public var windowID: WindowID
    public var shouldBeVisible: Bool
    public var effectiveScope: StageScope?
    public var homeScope: StageScope
    public var reason: PinVisibilityReason
}

public struct PersistentDesktopLabel: Equatable, Codable, Sendable {
    public var displayID: DisplayID
    public var desktopID: DesktopID
    public var label: String

    public init(displayID: DisplayID, desktopID: DesktopID, label: String) {
        self.displayID = displayID
        self.desktopID = desktopID
        self.label = label
    }
}

public struct PersistentDesktopSelection: Equatable, Codable, Sendable {
    public var displayID: DisplayID
    public var currentDesktopID: DesktopID
    public var lastDesktopID: DesktopID?

    public init(displayID: DisplayID, currentDesktopID: DesktopID = DesktopID(rawValue: 1), lastDesktopID: DesktopID? = nil) {
        self.displayID = displayID
        self.currentDesktopID = currentDesktopID
        self.lastDesktopID = lastDesktopID
    }
}

public struct PersistentStageScope: Equatable, Codable, Sendable {
    public var displayID: DisplayID
    public var desktopID: DesktopID
    public var activeStageID: StageID
    public var logicalDisplayID: LogicalDisplayID?
    public var lastKnownDisplayFingerprint: DisplayFingerprint?
    public var stages: [PersistentStage]

    public init(
        displayID: DisplayID,
        desktopID: DesktopID = DesktopID(rawValue: 1),
        activeStageID: StageID = StageID(rawValue: "1"),
        logicalDisplayID: LogicalDisplayID? = nil,
        lastKnownDisplayFingerprint: DisplayFingerprint? = nil,
        stages: [PersistentStage]? = nil,
        defaultMode: WindowManagementMode = .bsp
    ) {
        self.displayID = displayID
        self.desktopID = desktopID
        self.activeStageID = activeStageID
        self.logicalDisplayID = logicalDisplayID
        self.lastKnownDisplayFingerprint = lastKnownDisplayFingerprint
        self.stages = stages ?? [PersistentStage(id: activeStageID, mode: defaultMode)]
    }

    enum CodingKeys: String, CodingKey {
        case displayID
        case desktopID
        case activeStageID
        case logicalDisplayID
        case lastKnownDisplayFingerprint
        case stages
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.displayID = try c.decode(DisplayID.self, forKey: .displayID)
        self.desktopID = try c.decodeIfPresent(DesktopID.self, forKey: .desktopID) ?? DesktopID(rawValue: 1)
        self.activeStageID = try c.decodeIfPresent(StageID.self, forKey: .activeStageID) ?? StageID(rawValue: "1")
        self.logicalDisplayID = try c.decodeIfPresent(LogicalDisplayID.self, forKey: .logicalDisplayID)
        self.lastKnownDisplayFingerprint = try c.decodeIfPresent(DisplayFingerprint.self, forKey: .lastKnownDisplayFingerprint)
        self.stages = try c.decodeIfPresent([PersistentStage].self, forKey: .stages) ?? [PersistentStage(id: activeStageID)]
    }

    public mutating func ensureStage(_ id: StageID, mode: WindowManagementMode = .bsp) {
        guard !stages.contains(where: { $0.id == id }) else { return }
        stages.append(PersistentStage(id: id, mode: mode))
    }

    public mutating func applyConfiguredStages(_ config: StageManagerConfig, defaultMode: WindowManagementMode = .bsp) {
        if stages.isEmpty {
            activeStageID = StageID(rawValue: config.defaultStage)
        }
        for workspace in config.workspaces {
            let id = StageID(rawValue: workspace.id)
            if let index = stages.firstIndex(where: { $0.id == id }) {
                if stages[index].name == "Stage \(id.rawValue)" {
                    stages[index].name = workspace.displayName
                }
            } else {
                stages.append(PersistentStage(id: id, name: workspace.displayName, mode: defaultMode))
            }
        }
    }

    public mutating func adoptDefaultModeForEmptyDefaultStages(_ defaultMode: WindowManagementMode) {
        guard defaultMode != .bsp else { return }
        for index in stages.indices where stages[index].members.isEmpty && stages[index].mode == .bsp {
            stages[index].mode = defaultMode
        }
    }

    public mutating func createStage(_ id: StageID, name: String? = nil, mode: WindowManagementMode = .bsp) -> Bool {
        guard !stages.contains(where: { $0.id == id }) else { return false }
        stages.append(PersistentStage(id: id, name: name, mode: mode))
        return true
    }

    public mutating func renameStage(_ id: StageID, to name: String) -> Bool {
        guard let index = stages.firstIndex(where: { $0.id == id }) else { return false }
        stages[index].name = name
        return true
    }

    public mutating func reorderStage(_ id: StageID, to position: Int) -> Bool {
        guard let index = stages.firstIndex(where: { $0.id == id }) else { return false }
        let stage = stages.remove(at: index)
        let targetIndex = min(max(position - 1, 0), stages.count)
        stages.insert(stage, at: targetIndex)
        return true
    }

    public mutating func deleteEmptyInactiveStage(_ id: StageID) -> Bool {
        guard id != activeStageID,
              let index = stages.firstIndex(where: { $0.id == id }),
              stages[index].members.isEmpty
        else { return false }
        stages.remove(at: index)
        return true
    }

    // Complexite : O(stages * members). Pre-conditions : le total members est borne (~60-100).
    // Le balayage de toutes les stages est necessaire pour deplacer la fenetre depuis un stage
    // d'origine inconnu et nettoyer les groupes orphelins.
    public mutating func assign(
        window: WindowSnapshot,
        to stageID: StageID,
        insertionIndex: Int? = nil,
        focusWindow: Bool = true,
        defaultMode: WindowManagementMode = .bsp
    ) {
        ensureStage(stageID, mode: defaultMode)
        for index in stages.indices {
            stages[index].members.removeAll { $0.windowID == window.id }
            stages[index].groups = stages[index].groups.compactMap { group in
                var updated = group
                updated.remove(window.id)
                return updated.windowIDs.count >= 2 ? updated : nil
            }
            if stages[index].focusedWindowID == window.id {
                stages[index].previousFocusedWindowID = stages[index].focusedWindowID
                stages[index].focusedWindowID = stages[index].members.last?.windowID
            }
        }
        guard let index = stages.firstIndex(where: { $0.id == stageID }) else { return }
        let member = PersistentStageMember(
            windowID: window.id,
            bundleID: window.bundleID,
            title: window.title,
            frame: window.frame,
            lastSeenAt: Date(),
            missingSince: nil
        )
        if let insertionIndex {
            let targetIndex = min(max(insertionIndex, 0), stages[index].members.count)
            stages[index].members.insert(member, at: targetIndex)
        } else {
            stages[index].members.append(member)
        }
        if focusWindow || stages[index].focusedWindowID == nil {
            stages[index].focusedWindowID = window.id
        }
    }

    public mutating func setMode(_ mode: WindowManagementMode, for stageID: StageID) {
        ensureStage(stageID)
        guard let index = stages.firstIndex(where: { $0.id == stageID }) else { return }
        stages[index].mode = mode
    }

    // Complexite : O(stages * members). Idem `assign` : balayage complet pour nettoyer
    // members + groups + focused.
    public mutating func remove(windowID: WindowID) {
        for index in stages.indices {
            stages[index].members.removeAll { $0.windowID == windowID }
            stages[index].groups = stages[index].groups.compactMap { group in
                var updated = group
                updated.remove(windowID)
                return updated.windowIDs.count >= 2 ? updated : nil
            }
            if stages[index].focusedWindowID == windowID {
                stages[index].previousFocusedWindowID = stages[index].focusedWindowID
                stages[index].focusedWindowID = stages[index].members.last?.windowID
            }
        }
    }

    public mutating func setFocusedWindow(_ windowID: WindowID, in stageID: StageID) {
        guard let index = stages.firstIndex(where: { $0.id == stageID }),
              stages[index].members.contains(where: { $0.windowID == windowID })
        else { return }
        if stages[index].focusedWindowID != windowID {
            stages[index].previousFocusedWindowID = stages[index].focusedWindowID
        }
        stages[index].focusedWindowID = windowID
    }

    public mutating func orderMembers(_ orderedWindowIDs: [WindowID], in stageID: StageID) {
        guard let index = stages.firstIndex(where: { $0.id == stageID }) else { return }
        let membersByID = Dictionary(uniqueKeysWithValues: stages[index].members.map { ($0.windowID, $0) })
        var seen: Set<WindowID> = []
        var ordered: [PersistentStageMember] = []
        for id in orderedWindowIDs {
            guard let member = membersByID[id], !seen.contains(id) else { continue }
            ordered.append(member)
            seen.insert(id)
        }
        ordered.append(contentsOf: stages[index].members.filter { !seen.contains($0.windowID) })
        stages[index].members = ordered
    }

    // Complexite : O(stages * members) au pire, O(stages) en moyenne avec exit precoce.
    // Une fenetre n'apparait que dans un stage en etat valide -> on sort des qu'elle est trouvee.
    public mutating func updateFrame(window: WindowSnapshot) {
        for stageIndex in stages.indices {
            guard let memberIndex = stages[stageIndex].members.firstIndex(where: { $0.windowID == window.id }) else {
                continue
            }
            stages[stageIndex].members[memberIndex].frame = window.frame
            stages[stageIndex].members[memberIndex].bundleID = window.bundleID
            stages[stageIndex].members[memberIndex].title = window.title
            stages[stageIndex].members[memberIndex].lastSeenAt = Date()
            stages[stageIndex].members[memberIndex].missingSince = nil
            return
        }
    }

    @discardableResult
    public mutating func pruneMissingWindows(
        keeping liveWindowIDs: Set<WindowID>,
        missingGrace: TimeInterval = 45,
        now: Date = Date()
    ) -> MissingWindowReconciliationReport {
        var report = MissingWindowReconciliationReport()
        for stageIndex in stages.indices {
            var prunedWindowIDs: Set<WindowID> = []
            for memberIndex in stages[stageIndex].members.indices {
                let windowID = stages[stageIndex].members[memberIndex].windowID
                if liveWindowIDs.contains(windowID) {
                    if stages[stageIndex].members[memberIndex].missingSince != nil {
                        report.restoredWindowIDs.insert(windowID)
                    }
                    stages[stageIndex].members[memberIndex].lastSeenAt = now
                    stages[stageIndex].members[memberIndex].missingSince = nil
                } else if let missingSince = stages[stageIndex].members[memberIndex].missingSince {
                    if now.timeIntervalSince(missingSince) >= missingGrace {
                        prunedWindowIDs.insert(windowID)
                    }
                } else {
                    stages[stageIndex].members[memberIndex].missingSince = now
                    report.markedMissingWindowIDs.insert(windowID)
                }
            }
            report.prunedWindowIDs.formUnion(prunedWindowIDs)
            stages[stageIndex].members.removeAll { prunedWindowIDs.contains($0.windowID) }
            stages[stageIndex].groups = stages[stageIndex].groups.compactMap { group in
                var updated = group
                for windowID in group.windowIDs where prunedWindowIDs.contains(windowID) {
                    updated.remove(windowID)
                }
                return updated.windowIDs.count >= 2 ? updated : nil
            }
            if let focusedWindowID = stages[stageIndex].focusedWindowID,
               prunedWindowIDs.contains(focusedWindowID) {
                stages[stageIndex].focusedWindowID = stages[stageIndex].members.last?.windowID
            }
        }
        return report
    }

    public func memberIDs(in stageID: StageID) -> [WindowID] {
        stages.first(where: { $0.id == stageID })?.members.map(\.windowID) ?? []
    }

    mutating func mergeDisconnectedScope(_ source: PersistentStageScope) {
        if stages.allSatisfy(\.members.isEmpty) {
            activeStageID = source.activeStageID
        }
        for sourceStage in source.stages {
            ensureStage(sourceStage.id)
            guard let targetIndex = stages.firstIndex(where: { $0.id == sourceStage.id }) else { continue }
            if stages[targetIndex].members.isEmpty {
                stages[targetIndex].mode = sourceStage.mode
                stages[targetIndex].name = sourceStage.name
            }
            for member in sourceStage.members {
                remove(windowID: member.windowID)
                stages[targetIndex].members.append(member)
            }
            if let focusedWindowID = sourceStage.focusedWindowID {
                stages[targetIndex].focusedWindowID = focusedWindowID
            }
        }
    }
}

public struct PersistentStage: Equatable, Codable, Sendable {
    public var id: StageID
    public var name: String
    public var mode: WindowManagementMode
    public var focusedWindowID: WindowID?
    public var previousFocusedWindowID: WindowID?
    public var parkingState: StageParkingState
    public var origin: StageOrigin?
    public var hostDisplayID: DisplayID?
    public var restoredAt: Date?
    public var members: [PersistentStageMember]
    public var groups: [WindowGroup]

    public init(
        id: StageID,
        name: String? = nil,
        mode: WindowManagementMode = .bsp,
        focusedWindowID: WindowID? = nil,
        previousFocusedWindowID: WindowID? = nil,
        parkingState: StageParkingState = .native,
        origin: StageOrigin? = nil,
        hostDisplayID: DisplayID? = nil,
        restoredAt: Date? = nil,
        members: [PersistentStageMember] = [],
        groups: [WindowGroup] = []
    ) {
        self.id = id
        self.name = name ?? "Stage \(id.rawValue)"
        self.mode = mode
        self.focusedWindowID = focusedWindowID
        self.previousFocusedWindowID = previousFocusedWindowID
        self.parkingState = parkingState
        self.origin = origin
        self.hostDisplayID = hostDisplayID
        self.restoredAt = restoredAt
        self.members = members
        self.groups = groups
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case mode
        case focusedWindowID
        case previousFocusedWindowID
        case parkingState
        case origin
        case hostDisplayID
        case restoredAt
        case members
        case groups
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(StageID.self, forKey: .id)
        self.name = try c.decodeIfPresent(String.self, forKey: .name) ?? "Stage \(id.rawValue)"
        self.mode = try c.decodeIfPresent(WindowManagementMode.self, forKey: .mode) ?? .bsp
        self.focusedWindowID = try c.decodeIfPresent(WindowID.self, forKey: .focusedWindowID)
        self.previousFocusedWindowID = try c.decodeIfPresent(WindowID.self, forKey: .previousFocusedWindowID)
        self.parkingState = try c.decodeIfPresent(StageParkingState.self, forKey: .parkingState) ?? .native
        self.origin = try c.decodeIfPresent(StageOrigin.self, forKey: .origin)
        self.hostDisplayID = try c.decodeIfPresent(DisplayID.self, forKey: .hostDisplayID)
        self.restoredAt = try c.decodeIfPresent(Date.self, forKey: .restoredAt)
        self.members = try c.decodeIfPresent([PersistentStageMember].self, forKey: .members) ?? []
        self.groups = try c.decodeIfPresent([WindowGroup].self, forKey: .groups) ?? []
    }
}

public struct MissingWindowReconciliationReport: Equatable, Sendable {
    public var markedMissingWindowIDs: Set<WindowID>
    public var restoredWindowIDs: Set<WindowID>
    public var prunedWindowIDs: Set<WindowID>

    public init(
        markedMissingWindowIDs: Set<WindowID> = [],
        restoredWindowIDs: Set<WindowID> = [],
        prunedWindowIDs: Set<WindowID> = []
    ) {
        self.markedMissingWindowIDs = markedMissingWindowIDs
        self.restoredWindowIDs = restoredWindowIDs
        self.prunedWindowIDs = prunedWindowIDs
    }

    public var isEmpty: Bool {
        markedMissingWindowIDs.isEmpty && restoredWindowIDs.isEmpty && prunedWindowIDs.isEmpty
    }

    public mutating func merge(_ other: MissingWindowReconciliationReport) {
        markedMissingWindowIDs.formUnion(other.markedMissingWindowIDs)
        restoredWindowIDs.formUnion(other.restoredWindowIDs)
        prunedWindowIDs.formUnion(other.prunedWindowIDs)
    }
}

public struct PersistentStageMember: Equatable, Codable, Sendable {
    public var windowID: WindowID
    public var bundleID: String
    public var title: String
    public var frame: Rect
    public var lastSeenAt: Date?
    public var missingSince: Date?

    public init(
        windowID: WindowID,
        bundleID: String,
        title: String,
        frame: Rect,
        lastSeenAt: Date? = nil,
        missingSince: Date? = nil
    ) {
        self.windowID = windowID
        self.bundleID = bundleID
        self.title = title
        self.frame = frame
        self.lastSeenAt = lastSeenAt
        self.missingSince = missingSince
    }
}

private struct StableWindowSignature: Hashable {
    var bundleID: String
    var title: String

    init(window: WindowSnapshot) {
        self.bundleID = Self.normalized(window.bundleID)
        self.title = Self.normalized(window.title)
    }

    init(member: PersistentStageMember) {
        self.bundleID = Self.normalized(member.bundleID)
        self.title = Self.normalized(member.title)
    }

    private static func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .lowercased()
    }
}

private func bestReplacement(
    for member: PersistentStageMember,
    in candidates: [WindowSnapshot],
    claimed: Set<WindowID>
) -> WindowSnapshot? {
    let available = candidates.filter { !claimed.contains($0.id) }
    guard !available.isEmpty else { return nil }

    if available.count == 1,
       !member.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        return available[0]
    }

    let scored = available
        .map { window in (window: window, score: frameDistance(member.frame, window.frame)) }
        .sorted { lhs, rhs in lhs.score < rhs.score }
    guard let best = scored.first else { return nil }
    let second = scored.dropFirst().first?.score ?? .greatestFiniteMagnitude
    guard best.score <= 360,
          second - best.score >= 120
    else { return nil }
    return best.window
}

private func frameDistance(_ lhs: Rect, _ rhs: Rect) -> Double {
    let lhsRect = lhs.cgRect
    let rhsRect = rhs.cgRect
    return abs(lhsRect.midX - rhsRect.midX)
        + abs(lhsRect.midY - rhsRect.midY)
        + abs(lhs.width - rhs.width) / 2
        + abs(lhs.height - rhs.height) / 2
}
