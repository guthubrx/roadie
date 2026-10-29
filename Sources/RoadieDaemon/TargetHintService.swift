import CoreGraphics
import Foundation
import RoadieAX
import RoadieCore

public enum TargetKind: String, Codable, Equatable, Sendable {
    case window
    case stage
    case display
    case desktop
    case bookmark
    case appElement
    case gridCell
}

public enum TargetSource: String, Codable, Equatable, Sendable {
    case roadie
    case app
    case all
}

public enum TargetActionVerb: String, Codable, Equatable, Sendable {
    case focus
    case `switch`
    case sendActive = "send-active"
    case inspect
    case click
    case doubleClick = "double-click"
    case rightClick = "right-click"
    /// Cmd-clic (ouvrir dans un nouvel onglet), mode recherche SPEC-021.
    case commandClick = "command-click"

    var isAppMouseAction: Bool {
        switch self {
        case .click, .doubleClick, .rightClick, .commandClick:
            return true
        case .focus, .switch, .sendActive, .inspect:
            return false
        }
    }
}

public struct TargetScopeSnapshot: Codable, Equatable, Sendable {
    public var displayId: String?
    public var desktopId: Int?
    public var stageId: String?
    public var windowId: UInt32?

    public init(displayId: String? = nil, desktopId: Int? = nil, stageId: String? = nil, windowId: UInt32? = nil) {
        self.displayId = displayId
        self.desktopId = desktopId
        self.stageId = stageId
        self.windowId = windowId
    }

    public init(scope: StageScope?, windowId: WindowID? = nil) {
        self.displayId = scope?.displayID.rawValue
        self.desktopId = scope?.desktopID.rawValue
        self.stageId = scope?.stageID.rawValue
        self.windowId = windowId?.rawValue
    }
}

public struct RoadieTarget: Codable, Equatable, Sendable {
    public var id: String
    public var label: String
    public var kind: TargetKind
    public var title: String
    public var subtitle: String
    public var source: TargetSource
    public var matchText: String
    public var scope: TargetScopeSnapshot
    public var frame: Rect?
    public var isActive: Bool
    public var actions: [TargetActionVerb]
    public var diagnostics: [String]
    /// Texte des enfants d'une cible web, pour le mode recherche (SPEC-021) ; absent sinon.
    public var searchText: String?
    /// Zone visée par le clic d'une feuille web (SPEC-021) : son premier contenu visible. Absent : `frame`.
    public var clickFrame: Rect?

    public init(
        id: String,
        label: String = "",
        kind: TargetKind,
        title: String,
        subtitle: String = "",
        source: TargetSource,
        matchText: String = "",
        scope: TargetScopeSnapshot = TargetScopeSnapshot(),
        frame: Rect? = nil,
        isActive: Bool = false,
        actions: [TargetActionVerb],
        diagnostics: [String] = [],
        searchText: String? = nil,
        clickFrame: Rect? = nil
    ) {
        self.searchText = searchText
        self.clickFrame = clickFrame
        self.id = id
        self.label = label
        self.kind = kind
        self.title = title
        self.subtitle = subtitle
        self.source = source
        self.matchText = matchText.isEmpty ? Self.normalizedMatchText([id, title, subtitle, kind.rawValue]) : matchText
        self.scope = scope
        self.frame = frame
        self.isActive = isActive
        self.actions = actions
        self.diagnostics = diagnostics
    }

    public static func normalizedMatchText(_ values: [String]) -> String {
        TargetHintService.normalized(values.joined(separator: " "))
    }
}

public struct TargetQueryOptions: Codable, Equatable, Sendable {
    public var source: TargetSource
    public var filter: String?
    public var maxResults: Int
    public var includeHidden: Bool
    public var includeAppTargets: Bool

    public init(
        source: TargetSource = .roadie,
        filter: String? = nil,
        maxResults: Int = 120,
        includeHidden: Bool = false,
        includeAppTargets: Bool = false
    ) {
        self.source = source
        self.filter = filter
        self.maxResults = max(1, maxResults)
        self.includeHidden = includeHidden
        self.includeAppTargets = includeAppTargets
    }
}

public struct TargetQueryReport: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var generatedAt: Date
    public var query: TargetQueryOptions
    public var targets: [RoadieTarget]
    public var partial: Bool
    public var error: String?

    public init(
        schemaVersion: Int = 1,
        generatedAt: Date = Date(),
        query: TargetQueryOptions,
        targets: [RoadieTarget],
        partial: Bool = false,
        error: String? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.generatedAt = generatedAt
        self.query = query
        self.targets = targets
        self.partial = partial
        self.error = error
    }
}

public enum TargetResolutionError: Error, Equatable, CustomStringConvertible {
    case unknownTarget(String)
    case ambiguousTarget(String, [String])

    public var description: String {
        switch self {
        case .unknownTarget(let value):
            return "unknown_target: \(value)"
        case .ambiguousTarget(let value, let ids):
            return "ambiguous_target: \(value) -> \(ids.joined(separator: ","))"
        }
    }
}

public struct TargetActionResult: Codable, Equatable, Sendable {
    public var changed: Bool
    public var message: String
    public var target: RoadieTarget?
    public var error: String?

    public init(changed: Bool, message: String, target: RoadieTarget? = nil, error: String? = nil) {
        self.changed = changed
        self.message = message
        self.target = target
        self.error = error
    }
}

public struct TargetPickResult: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var query: String
    public var action: TargetActionVerb?
    public var selected: RoadieTarget?
    public var candidates: [RoadieTarget]
    public var result: TargetActionResult?
    public var error: String?

    public init(
        schemaVersion: Int = 1,
        query: String,
        action: TargetActionVerb? = nil,
        selected: RoadieTarget? = nil,
        candidates: [RoadieTarget] = [],
        result: TargetActionResult? = nil,
        error: String? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.query = query
        self.action = action
        self.selected = selected
        self.candidates = candidates
        self.result = result
        self.error = error
    }
}

public struct TargetOverlayState: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var visible: Bool
    public var labelsOnly: Bool
    public var generatedAt: Date
    public var expiresAt: Date?
    public var report: TargetQueryReport

    public init(
        schemaVersion: Int = 1,
        visible: Bool,
        labelsOnly: Bool,
        generatedAt: Date = Date(),
        expiresAt: Date? = nil,
        report: TargetQueryReport
    ) {
        self.schemaVersion = schemaVersion
        self.visible = visible
        self.labelsOnly = labelsOnly
        self.generatedAt = generatedAt
        self.expiresAt = expiresAt
        self.report = report
    }
}

public struct TargetHintService {
    private let service: SnapshotService
    private let stageStore: StageStore
    private let eventLog: EventLog
    private let appTargetService: AppTargetQueryService
    private let targetModeConfig: TargetModeConfig
    private let appTargetsConfig: AppTargetsConfig

    public init(
        service: SnapshotService = SnapshotService(),
        stageStore: StageStore? = nil,
        eventLog: EventLog = EventLog(),
        appTargetService: AppTargetQueryService = AppTargetQueryService(),
        targetModeConfig: TargetModeConfig? = nil,
        appTargetsConfig: AppTargetsConfig? = nil
    ) {
        self.service = service
        self.stageStore = stageStore ?? service.effectiveStageStore
        self.eventLog = eventLog
        self.appTargetService = appTargetService
        self.targetModeConfig = targetModeConfig ?? service.effectiveConfig.experimental.targetMode
        self.appTargetsConfig = appTargetsConfig ?? service.effectiveConfig.experimental.appTargets
    }

    /// `snapshot` : relevé déjà pris par l'appelant (barre, session 123), pour ne pas relire les fenêtres.
    public func list(_ options: TargetQueryOptions = TargetQueryOptions(), snapshot provided: DaemonSnapshot? = nil) -> TargetQueryReport {
        guard targetModeConfig.enabled else {
            eventLog.append(RoadieEvent(type: "targets.list_failed", details: [
                "source": options.source.rawValue,
                "error": "target_mode_disabled",
            ]))
            return TargetQueryReport(query: options, targets: [], error: "target_mode_disabled")
        }
        let snapshot = provided ?? service.snapshot(followFocus: false)
        let state = stageStore.state()
        var report = Self.report(from: snapshot, state: state, options: options)
        if options.source == .app || (options.source == .all && (appTargetsConfig.enabled || options.includeAppTargets)) {
            let appReport = appTargetService.query(config: appTargetsConfig, enabledOverride: options.includeAppTargets)
            for scan in [appReport.scan].compactMap(\.self) + appReport.windowScans {
                eventLog.append(RoadieEvent(type: "targets.app_scan", details: scan.eventDetails))
            }
            report.targets.append(contentsOf: appReport.targets)
            report.partial = report.partial || appReport.partial
            report.error = report.error ?? appReport.error
            report.targets = Self.assignLabels(to: Self.filtered(report.targets, options: options), alphabet: appTargetsConfig.hintCharacters)
        }
        eventLog.append(RoadieEvent(type: "targets.list", details: [
            "source": options.source.rawValue,
            "count": String(report.targets.count),
            "partial": String(report.partial),
        ]))
        return report
    }

    public static func report(from snapshot: DaemonSnapshot, state: PersistentStageState, options: TargetQueryOptions) -> TargetQueryReport {
        let roadieTargets = options.source == .app ? [] : roadieTargets(from: snapshot, state: state, includeHidden: options.includeHidden)
        let filtered = filtered(roadieTargets, options: options)
        return TargetQueryReport(query: options, targets: assignLabels(to: filtered, alphabet: "asdfghjkl"))
    }

    public func resolve(_ value: String, options: TargetQueryOptions = TargetQueryOptions()) throws -> RoadieTarget {
        try Self.resolve(value, in: list(options).targets)
    }

    public func pick(_ query: String, action requestedAction: TargetActionVerb? = nil, options: TargetQueryOptions = TargetQueryOptions(source: .all)) -> TargetPickResult {
        guard targetModeConfig.enabled else {
            eventLog.append(RoadieEvent(type: "targets.pick_failed", details: ["query": query, "error": "target_mode_disabled"]))
            return TargetPickResult(query: query, action: requestedAction, error: "target_mode_disabled")
        }
        guard targetModeConfig.pickerEnabled else {
            eventLog.append(RoadieEvent(type: "targets.pick_failed", details: ["query": query, "error": "target_picker_disabled"]))
            return TargetPickResult(query: query, action: requestedAction, error: "target_picker_disabled")
        }
        let report = list(options)
        let action: TargetActionVerb?
        let target: RoadieTarget
        do {
            target = try Self.resolve(query, in: report.targets)
            action = requestedAction ?? target.actions.first
        } catch TargetResolutionError.ambiguousTarget(let value, let ids) {
            let idSet = Set(ids)
            let candidates = report.targets.filter { idSet.contains($0.id) }
            let message = TargetResolutionError.ambiguousTarget(value, ids).description
            eventLog.append(RoadieEvent(type: "targets.pick_failed", details: ["query": query, "error": message]))
            return TargetPickResult(query: query, action: requestedAction, candidates: candidates, error: "ambiguous_target")
        } catch {
            eventLog.append(RoadieEvent(type: "targets.pick_failed", details: ["query": query, "error": String(describing: error)]))
            return TargetPickResult(query: query, action: requestedAction, error: String(describing: error))
        }

        let result = perform(target, requestedAction: action)
        return TargetPickResult(
            query: query,
            action: action,
            selected: target,
            result: result,
            error: result.error
        )
    }

    public func overlayState(options: TargetQueryOptions = TargetQueryOptions(), labelsOnly: Bool = true, visible: Bool = true) -> TargetOverlayState {
        let effectiveLabelsOnly = labelsOnly || targetModeConfig.overlayLabelsOnly
        let generatedAt = Date()
        let expiresAt = visible ? generatedAt.addingTimeInterval(targetModeConfig.overlayDurationSeconds) : nil
        return TargetOverlayState(
            visible: visible && targetModeConfig.enabled,
            labelsOnly: effectiveLabelsOnly,
            generatedAt: generatedAt,
            expiresAt: expiresAt,
            report: list(options)
        )
    }

    public static func resolve(_ value: String, in targets: [RoadieTarget]) throws -> RoadieTarget {
        let raw = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if let exactID = targets.first(where: { $0.id == raw }) {
            return exactID
        }
        if let exactLabel = targets.first(where: { $0.label.caseInsensitiveCompare(raw) == .orderedSame }) {
            return exactLabel
        }
        let normalizedQuery = normalized(raw)
        let matches = targets.filter { $0.matchText.contains(normalizedQuery) || normalized($0.id).contains(normalizedQuery) }
        if matches.count == 1 {
            return matches[0]
        }
        if matches.isEmpty {
            throw TargetResolutionError.unknownTarget(value)
        }
        throw TargetResolutionError.ambiguousTarget(value, matches.map(\.id))
    }

    public func activate(_ value: String, action requestedAction: TargetActionVerb? = nil) -> TargetActionResult {
        guard targetModeConfig.enabled else {
            let message = "target_mode_disabled"
            eventLog.append(RoadieEvent(type: "targets.activate_failed", details: ["target": value, "error": message]))
            return TargetActionResult(changed: false, message: message, error: message)
        }
        let options = TargetQueryOptions(source: .all, includeAppTargets: appTargetsConfig.enabled)
        let target: RoadieTarget
        do {
            target = try resolve(value, options: options)
        } catch {
            eventLog.append(RoadieEvent(type: "targets.activate_failed", details: ["target": value, "error": String(describing: error)]))
            return TargetActionResult(changed: false, message: String(describing: error), error: String(describing: error))
        }

        return activate(target: target, action: requestedAction)
    }

    /// Active une cible déjà résolue, sans nouvelle liste : le mode recherche (SPEC-021) clique ainsi
    /// exactement l'élément choisi, même si l'ordre des cibles a changé depuis.
    public func activate(target: RoadieTarget, action requestedAction: TargetActionVerb? = nil) -> TargetActionResult {
        guard targetModeConfig.enabled else {
            let message = "target_mode_disabled"
            eventLog.append(RoadieEvent(type: "targets.activate_failed", details: ["target": target.id, "error": message]))
            return TargetActionResult(changed: false, message: message, error: message)
        }
        let result = perform(target, requestedAction: requestedAction)
        eventLog.append(RoadieEvent(type: "targets.activate", details: [
            "target": target.id,
            "label": target.label,
            "action": (requestedAction ?? target.actions.first ?? .inspect).rawValue,
            "changed": String(result.changed),
            "error": result.error ?? "",
        ]))
        return result
    }

    private func perform(_ target: RoadieTarget, requestedAction: TargetActionVerb?) -> TargetActionResult {
        let action = requestedAction ?? target.actions.first ?? .inspect
        if target.source == .app && action.isAppMouseAction && !targetModeConfig.appMouseActionsEnabled {
            let message = "app_mouse_actions_disabled: \(action.rawValue) for \(target.id)"
            eventLog.append(RoadieEvent(type: "targets.activate_failed", details: ["target": target.id, "error": message]))
            return TargetActionResult(changed: false, message: message, target: target, error: "app_mouse_actions_disabled")
        }
        guard target.actions.contains(action) else {
            let message = "unsupported_action: \(action.rawValue) for \(target.id)"
            eventLog.append(RoadieEvent(type: "targets.activate_failed", details: ["target": target.id, "error": message]))
            return TargetActionResult(changed: false, message: message, target: target, error: "unsupported_action")
        }

        let result: TargetActionResult
        switch action {
        case .focus:
            result = activateFocus(target)
        case .switch:
            result = activateSwitch(target)
        case .sendActive:
            result = activateSendActive(target)
        case .click, .doubleClick, .rightClick, .commandClick:
            // Cible d'une fenêtre visible quelconque (SPEC-021) : focaliser puis cliquer. Fenêtre déjà
            // active (portée `frontmost_window`, REL-012) : aucune demande, donc ni relecture complète
            // des fenêtres ni déplacement du pointeur avant le clic.
            if let windowID = target.scope.windowId, target.source == .app,
               service.focusedWindowID()?.rawValue != windowID {
                _ = WindowCommandService(service: service, stageStore: stageStore).focus(windowID: WindowID(rawValue: windowID))
            }
            result = appTargetService.click(target, action: action)
        case .inspect:
            result = TargetActionResult(changed: false, message: "inspect \(target.id)", target: target)
        }
        return result
    }

    private func activateFocus(_ target: RoadieTarget) -> TargetActionResult {
        switch target.kind {
        case .window:
            guard let rawID = target.scope.windowId else {
                return TargetActionResult(changed: false, message: "stale_target: \(target.id)", target: target, error: "stale_target")
            }
            let result = WindowCommandService(service: service, stageStore: stageStore).focus(windowID: WindowID(rawValue: rawID))
            return TargetActionResult(changed: result.changed, message: result.message, target: target, error: result.changed ? nil : "focus_failed")
        case .display:
            guard let displayID = target.scope.displayId,
                  let display = service.snapshot(followFocus: false).displays.first(where: { $0.id.rawValue == displayID })
            else {
                return TargetActionResult(changed: false, message: "stale_target: \(target.id)", target: target, error: "stale_target")
            }
            let result = DisplayCommandService(service: service, store: stageStore, events: eventLog).focus(index: display.index)
            return TargetActionResult(changed: result.changed, message: result.message, target: target)
        case .bookmark:
            let name = bookmarkName(from: target)
            let result = WindowBookmarkCommandService(service: service, store: stageStore, events: eventLog).focus(name)
            return TargetActionResult(changed: result.changed, message: result.message, target: target, error: result.changed ? nil : "bookmark_focus_failed")
        default:
            return TargetActionResult(changed: false, message: "unsupported_action: focus for \(target.kind.rawValue)", target: target, error: "unsupported_action")
        }
    }

    private func activateSwitch(_ target: RoadieTarget) -> TargetActionResult {
        guard target.kind == .stage,
              let displayID = target.scope.displayId,
              let stageID = target.scope.stageId
        else {
            return TargetActionResult(changed: false, message: "unsupported_action: switch for \(target.kind.rawValue)", target: target, error: "unsupported_action")
        }
        if let refused = refusedOutsideCurrentDesktop(target, displayID: displayID) { return refused }
        let result = StageCommandService(service: service, store: stageStore, events: eventLog).switchTo(stageID, displayID: DisplayID(rawValue: displayID))
        return TargetActionResult(changed: result.changed, message: result.message, target: target, error: result.changed ? nil : "switch_failed")
    }

    private func activateSendActive(_ target: RoadieTarget) -> TargetActionResult {
        guard target.kind == .stage,
              let displayID = target.scope.displayId,
              let stageID = target.scope.stageId
        else {
            return TargetActionResult(changed: false, message: "unsupported_action: send-active for \(target.kind.rawValue)", target: target, error: "unsupported_action")
        }
        if let refused = refusedOutsideCurrentDesktop(target, displayID: displayID) { return refused }
        let snapshot = service.snapshot(followFocus: false)
        guard let activeID = snapshot.focusedWindowID ?? snapshot.windows.first(where: { $0.window.isTileCandidate && $0.scope != nil })?.window.id else {
            return TargetActionResult(changed: false, message: "send-active: no active window", target: target, error: "no_active_window")
        }
        let result = StageCommandService(service: service, store: stageStore, events: eventLog)
            .assign(windowID: activeID, to: stageID, displayID: DisplayID(rawValue: displayID), focusAssignedWindow: service.effectiveConfig.focus.assignFollowsFocus)
        return TargetActionResult(changed: result.changed, message: result.message, target: target, error: result.changed ? nil : "assign_failed")
    }

    /// REL-037 : les commandes de stage agissent sur le bureau courant de l'écran. Une stage d'un autre
    /// bureau est refusée, sinon sa stage homonyme du bureau courant serait modifiée. O(d), d écrans.
    private func refusedOutsideCurrentDesktop(_ target: RoadieTarget, displayID: String) -> TargetActionResult? {
        guard target.scope.desktopId != stageStore.state().currentDesktopID(for: DisplayID(rawValue: displayID)).rawValue else {
            return nil
        }
        return TargetActionResult(
            changed: false, message: "target_desktop_not_active: \(target.id)", target: target, error: "target_desktop_not_active"
        )
    }

    public static func labels(count: Int, alphabet: String = "asdfghjkl") -> [String] {
        guard count > 0 else { return [] }
        let chars = Array(alphabet.isEmpty ? "asdfghjkl" : alphabet).map(String.init)
        var result: [String] = []
        var width = 1
        while result.count < count {
            appendLabels(prefix: "", width: width, chars: chars, into: &result, limit: count)
            width += 1
        }
        return result
    }

    public static func normalized(_ value: String) -> String {
        value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .lowercased()
    }

    private static func appendLabels(prefix: String, width: Int, chars: [String], into result: inout [String], limit: Int) {
        guard result.count < limit else { return }
        if width == 0 {
            result.append(prefix.uppercased())
            return
        }
        for char in chars {
            appendLabels(prefix: prefix + char, width: width - 1, chars: chars, into: &result, limit: limit)
            if result.count >= limit { return }
        }
    }

    private static func assignLabels(to targets: [RoadieTarget], alphabet: String) -> [RoadieTarget] {
        let generated = labels(count: targets.count, alphabet: alphabet)
        return targets.enumerated().map { index, target in
            var updated = target
            updated.label = generated[index]
            return updated
        }
    }

    private static func filtered(_ targets: [RoadieTarget], options: TargetQueryOptions) -> [RoadieTarget] {
        let sourceFiltered = targets.filter { target in
            options.source == .all || target.source == options.source
        }
        let textFiltered: [RoadieTarget]
        if let filter = options.filter, !filter.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let normalizedFilter = normalized(filter)
            textFiltered = sourceFiltered.filter { $0.matchText.contains(normalizedFilter) || normalized($0.id).contains(normalizedFilter) }
        } else {
            textFiltered = sourceFiltered
        }
        return Array(textFiltered.prefix(options.maxResults))
    }

    private static func roadieTargets(from snapshot: DaemonSnapshot, state: PersistentStageState, includeHidden: Bool) -> [RoadieTarget] {
        var targets: [RoadieTarget] = []
        let liveWindowIDs = Set(snapshot.windows.map(\.window.id))
        let liveWindowFramesByID = Dictionary(snapshot.windows.map { ($0.window.id, $0.window.frame) }, uniquingKeysWith: { first, _ in first })
        let railFramesByStageKey = railStageFrames(from: snapshot, state: state)
        // Deux ecrans peuvent partager un UUID (clones, docks) : on garde le premier au lieu de planter.
        let displayIndexByID = Dictionary(snapshot.displays.map { ($0.id, $0.index) }, uniquingKeysWith: { first, _ in first })
        let focusedWindowID = snapshot.focusedWindowID

        for display in snapshot.displays.sorted(by: { $0.index < $1.index }) {
            let active = state.activeDisplayID == display.id
            targets.append(RoadieTarget(
                id: "display:\(display.id.rawValue)",
                kind: .display,
                title: display.name,
                subtitle: tr("Écran", "Display") + " \(display.index)",
                source: .roadie,
                scope: TargetScopeSnapshot(displayId: display.id.rawValue),
                frame: display.frame,
                isActive: active,
                actions: [.focus, .inspect],
                diagnostics: [active ? "active" : "inactive", display.isMain ? "main" : "secondary"]
            ))
        }

        let scopes = state.scopes.sorted { lhs, rhs in
            let left = (displayIndexByID[lhs.displayID] ?? Int.max, lhs.desktopID.rawValue)
            let right = (displayIndexByID[rhs.displayID] ?? Int.max, rhs.desktopID.rawValue)
            return left == right ? lhs.activeStageID.rawValue < rhs.activeStageID.rawValue : left < right
        }
        for scope in scopes {
            let displayIndex = displayIndexByID[scope.displayID] ?? 0
            targets.append(RoadieTarget(
                id: "desktop:\(scope.displayID.rawValue)/\(scope.desktopID.rawValue)",
                kind: .desktop,
                title: "Desktop \(scope.desktopID.rawValue)",
                subtitle: tr("Écran", "Display") + " \(displayIndex)",
                source: .roadie,
                scope: TargetScopeSnapshot(displayId: scope.displayID.rawValue, desktopId: scope.desktopID.rawValue),
                isActive: state.currentDesktopID(for: scope.displayID) == scope.desktopID,
                actions: [.inspect],
                diagnostics: ["scope_known"]
            ))

            let onCurrentDesktop = state.currentDesktopID(for: scope.displayID) == scope.desktopID
            for stage in scope.stages {
                let hasLiveMembers = stage.members.contains { liveWindowIDs.contains($0.windowID) }
                let isActive = stage.id == scope.activeStageID && onCurrentDesktop
                guard includeHidden || hasLiveMembers || isActive else { continue }
                targets.append(RoadieTarget(
                    id: "stage:\(scope.displayID.rawValue)/\(scope.desktopID.rawValue)/\(stage.id.rawValue)",
                    kind: .stage,
                    title: stage.name,
                    subtitle: tr("Bureau \(scope.desktopID.rawValue) · \(stage.members.count) fenêtre(s)",
                                  "Desktop \(scope.desktopID.rawValue) · \(stage.members.count) window(s)"),
                    source: .roadie,
                    scope: TargetScopeSnapshot(displayId: scope.displayID.rawValue, desktopId: scope.desktopID.rawValue, stageId: stage.id.rawValue),
                    frame: railFramesByStageKey[stageKey(displayID: scope.displayID, desktopID: scope.desktopID, stageID: stage.id)]
                        ?? unionFrame(for: stage, framesByID: liveWindowFramesByID),
                    isActive: isActive,
                    // REL-037 : switch et send-active ne visent que le bureau courant.
                    actions: onCurrentDesktop ? [.switch, .sendActive, .inspect] : [.inspect],
                    diagnostics: [
                        isActive ? "active" : "inactive",
                        hasLiveMembers ? "non_empty" : "empty",
                        "mode=\(stage.mode.rawValue)",
                    ]
                ))
            }
        }

        let sortedWindows = snapshot.windows.sorted(by: { lhs, rhs in
            let leftDisplay = (lhs.scope?.displayID).flatMap { displayIndexByID[$0] } ?? Int.max
            let rightDisplay = (rhs.scope?.displayID).flatMap { displayIndexByID[$0] } ?? Int.max
            if leftDisplay != rightDisplay { return leftDisplay < rightDisplay }
            if lhs.window.frame.y != rhs.window.frame.y { return lhs.window.frame.y < rhs.window.frame.y }
            return lhs.window.frame.x < rhs.window.frame.x
        })
        for entry in sortedWindows {
            let window = entry.window
            guard window.isTileCandidate || entry.scope != nil else { continue }
            let diagnostics = windowDiagnostics(entry)
            targets.append(RoadieTarget(
                id: "window:\(window.id.rawValue)",
                kind: .window,
                title: window.appName,
                subtitle: window.title,
                source: .roadie,
                scope: TargetScopeSnapshot(scope: entry.scope, windowId: window.id),
                frame: window.frame,
                isActive: window.id == focusedWindowID,
                actions: [.focus, .inspect],
                diagnostics: diagnostics
            ))
        }

        for bookmark in state.windowBookmarks.sorted(by: { $0.name.localizedStandardCompare($1.name) == .orderedAscending }) {
            targets.append(RoadieTarget(
                id: "bookmark:\(bookmark.name)",
                kind: .bookmark,
                title: bookmark.name,
                subtitle: "\(bookmark.bundleID) - \(bookmark.title)",
                source: .roadie,
                scope: TargetScopeSnapshot(scope: bookmark.scope, windowId: bookmark.windowID),
                frame: bookmark.frame,
                isActive: bookmark.windowID == focusedWindowID,
                actions: [.focus, .inspect],
                diagnostics: [bookmark.missingSince == nil ? "live_or_unknown" : "missing"]
            ))
        }

        return targets
    }

    private static func stageKey(displayID: DisplayID, desktopID: DesktopID, stageID: StageID) -> String {
        "\(displayID.rawValue)/\(desktopID.rawValue)/\(stageID.rawValue)"
    }

    private static func railStageFrames(from snapshot: DaemonSnapshot, state: PersistentStageState) -> [String: Rect] {
        let displaysByID = Dictionary(snapshot.displays.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let settings = RailSettings.load()
        var frames: [String: Rect] = [:]

        for scope in state.scopes {
            guard state.currentDesktopID(for: scope.displayID) == scope.desktopID,
                  let display = displaysByID[scope.displayID]
            else { continue }

            let visibleStages = scope.stages.filter { stage in
                stage.id == scope.activeStageID || !stage.members.isEmpty
            }
            guard !visibleStages.isEmpty else { continue }

            for (index, stage) in visibleStages.enumerated() {
                let frame = railCardFrame(
                    display: display,
                    index: index,
                    count: visibleStages.count,
                    settings: settings
                )
                frames[stageKey(displayID: scope.displayID, desktopID: scope.desktopID, stageID: stage.id)] = Rect(frame)
            }
        }

        return frames
    }

    private static func railCardFrame(display: DisplaySnapshot, index: Int, count: Int, settings: RailSettings) -> CGRect {
        let displayFrame = display.frame.cgRect
        let stageHeight = railStageHeight(settings)
        let spacing = CGFloat(settings.stages.gap > 0 ? settings.stages.gap : settings.layout.spacing)
        let totalStageHeight = CGFloat(count) * stageHeight + CGFloat(max(0, count - 1)) * spacing
        let topPadding = CGFloat(settings.layout.topPadding)
        let bottomPadding = CGFloat(settings.layout.bottomPadding)
        let headerPosition = settings.layout.headerPosition
        let headerVisible = headerPosition != "hidden" && (settings.displayLabel.enabled || settings.desktopLabel.enabled)
        let headerHeight = max(CGFloat(settings.displayLabel.fontSize + settings.desktopLabel.fontSize + 12), 1)

        let currentTop: CGFloat
        switch headerPosition {
        case "top" where headerVisible:
            currentTop = topPadding + headerHeight + spacing * 2
        case "bottom", "hidden":
            currentTop = topPadding + spacing
        default:
            currentTop = topPadding + spacing
        }

        let centeredTop = max(20, floor((displayFrame.height - totalStageHeight) / 2))
        let targetTop: CGFloat
        let stagesPosition = settings.stages.position
        switch stagesPosition {
        case "top":
            targetTop = currentTop
        case "bottom":
            targetTop = max(currentTop, displayFrame.height - totalStageHeight - bottomPadding)
        default:
            targetTop = centeredTop
        }

        let x = displayFrame.minX + 6
        let y = displayFrame.minY + targetTop + CGFloat(index) * (stageHeight + spacing)
        return CGRect(
            x: x,
            y: y,
            width: max(28, CGFloat(settings.width) - 12),
            height: stageHeight
        ).integral
    }

    private static func railStageHeight(_ settings: RailSettings) -> CGFloat {
        if settings.renderer == "icons-only" || settings.renderer == "icons" {
            return max(78, CGFloat(settings.stages.slotHeight))
        }
        if settings.stages.slotHeight > 0 { return max(80, CGFloat(settings.stages.slotHeight)) }
        let previewHeight = (settings.renderer == "parallax-45" || settings.renderer == "parallax")
            ? settings.parallax.height
            : settings.preview.height
        return max(150, CGFloat(previewHeight) + 66)
    }

    private static func windowDiagnostics(_ entry: ScopedWindowSnapshot) -> [String] {
        var values: [String] = []
        values.append(entry.window.isTileCandidate ? "tileable" : "not_tileable")
        values.append(entry.scope == nil ? "unscoped" : "scoped")
        if entry.pin != nil { values.append("pinned") }
        if let role = entry.window.role { values.append("role=\(role)") }
        if let subrole = entry.window.subrole { values.append("subrole=\(subrole)") }
        if let furniture = entry.window.furniture {
            if furniture.isModal { values.append("modal") }
            if !furniture.isResizable { values.append("not_resizable") }
            if furniture.fullscreenButtonDisabled { values.append("fullscreen_disabled") }
        }
        return values
    }

    private static func unionFrame(for stage: PersistentStage, framesByID: [WindowID: Rect]) -> Rect? {
        let frames = stage.members.compactMap { framesByID[$0.windowID]?.cgRect }
        guard var union = frames.first else { return nil }
        for frame in frames.dropFirst() {
            union = union.union(frame)
        }
        return Rect(union.integral)
    }

    private func bookmarkName(from target: RoadieTarget) -> String {
        if target.id.hasPrefix("bookmark:") {
            return String(target.id.dropFirst("bookmark:".count))
        }
        return target.title
    }
}
