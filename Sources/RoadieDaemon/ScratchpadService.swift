import CoreGraphics
import Foundation
import os
import RoadieAX
import RoadieCore
import RoadieTiler

/// Entrée persistée d'un scratchpad flottant nommé (Spec 162).
public struct PersistentScratchpadEntry: Codable, Equatable, Sendable {
    public var name: String
    public var windowID: WindowID
    public var bundleID: String
    public var title: String
    public var isVisible: Bool
    public var floatingFrame: Rect

    public init(
        name: String,
        windowID: WindowID,
        bundleID: String,
        title: String,
        isVisible: Bool,
        floatingFrame: Rect
    ) {
        self.name = name
        self.windowID = windowID
        self.bundleID = bundleID
        self.title = title
        self.isVisible = isVisible
        self.floatingFrame = floatingFrame
    }
}

public struct PersistentScratchpadBook: Codable, Equatable, Sendable {
    public var entries: [String: PersistentScratchpadEntry]

    public init(entries: [String: PersistentScratchpadEntry] = [:]) {
        self.entries = entries
    }

    public var windowIDs: Set<WindowID> {
        Set(entries.values.map(\.windowID))
    }
}

/// Persistance locale des scratchpads nommés (`~/.roadies/scratchpads.json`, isolée en tests via `TestEnvironment`).
public final class ScratchpadStore: Sendable {
    public let url: URL

    /// Cache en mémoire des identifiants protégés par fichier, évitant toute lecture disque par snapshot.
    private static let cachedIDsByPath = OSAllocatedUnfairLock(initialState: [String: Set<WindowID>]())

    public init(path: String? = nil) {
        let resolvedPath = path ?? TestEnvironment.launcherFile("scratchpads.json")
        self.url = URL(fileURLWithPath: NSString(string: resolvedPath).expandingTildeInPath)
    }

    public func load() -> PersistentScratchpadBook {
        let book = JSONPersistence.load(PersistentScratchpadBook.self, from: url, default: PersistentScratchpadBook())
        let ids = book.windowIDs
        Self.cachedIDsByPath.withLock { $0[url.path] = ids }
        return book
    }

    @discardableResult
    public func mutateChecked<T>(_ body: (inout PersistentScratchpadBook) throws -> T) throws -> T {
        let result = try JSONPersistence.mutateChecked(
            PersistentScratchpadBook.self,
            at: url,
            default: PersistentScratchpadBook(),
            label: "scratchpads"
        ) { book in
            let output = try body(&book)
            let ids = book.windowIDs
            Self.cachedIDsByPath.withLock { $0[url.path] = ids }
            return output
        }
        return result
    }

    /// Identifiants actuellement enregistrés en scratchpad (lecture O(1) en mémoire ; charge au premier accès).
    public static func protectedWindowIDs(for path: String? = nil) -> Set<WindowID> {
        let resolvedPath = path ?? TestEnvironment.launcherFile("scratchpads.json")
        let resolved = URL(fileURLWithPath: NSString(string: resolvedPath).expandingTildeInPath).path
        if let existing = cachedIDsByPath.withLock({ $0[resolved] }) {
            return existing
        }
        guard FileManager.default.fileExists(atPath: resolved) else {
            cachedIDsByPath.withLock { $0[resolved] = [] }
            return []
        }
        let book = JSONPersistence.load(PersistentScratchpadBook.self, from: URL(fileURLWithPath: resolved), default: PersistentScratchpadBook())
        let ids = book.windowIDs
        cachedIDsByPath.withLock { $0[resolved] = ids }
        return ids
    }

    public static func normalizedName(_ raw: String?) -> String {
        let trimmed = (raw ?? "default").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return trimmed.isEmpty ? "default" : trimmed
    }
}

/// Service de commandes du scratchpad flottant nommé (`roadie scratchpad`, Spec 162).
public struct ScratchpadCommandService {
    private let service: SnapshotService
    private let stageStore: StageStore
    private let scratchpadStore: ScratchpadStore
    private let events: EventLog

    public init(
        service: SnapshotService = SnapshotService(),
        stageStore: StageStore? = nil,
        scratchpadStore: ScratchpadStore = ScratchpadStore(),
        events: EventLog = EventLog()
    ) {
        self.service = service
        self.stageStore = stageStore ?? service.effectiveStageStore
        self.scratchpadStore = scratchpadStore
        self.events = events
    }

    /// Calcule un cadre flottant centré dans `visibleFrame` (70 % × 75 % par défaut si aucun cadre sauvegardé).
    public static func centeredFrame(saved: Rect?, in visibleFrame: CGRect) -> CGRect {
        let minWidth = min(320, visibleFrame.width)
        let minHeight = min(240, visibleFrame.height)
        let targetWidth: CGFloat
        let targetHeight: CGFloat
        if let saved, saved.width >= 120, saved.height >= 120 {
            targetWidth = min(visibleFrame.width * 0.92, max(minWidth, CGFloat(saved.width)))
            targetHeight = min(visibleFrame.height * 0.92, max(minHeight, CGFloat(saved.height)))
        } else {
            targetWidth = (visibleFrame.width * 0.70).rounded()
            targetHeight = (visibleFrame.height * 0.75).rounded()
        }
        return CGRect(
            x: (visibleFrame.midX - targetWidth / 2).rounded(),
            y: (visibleFrame.midY - targetHeight / 2).rounded(),
            width: targetWidth.rounded(),
            height: targetHeight.rounded()
        ).integral
    }

    /// Affecte une fenêtre (ou la fenêtre focalisée) au scratchpad `name`, la retire du tuilage et la centre.
    public func assign(name rawName: String? = nil, windowID: WindowID? = nil) -> WindowCommandResult {
        guard service.effectiveConfig.tiling.scratchpadEnabled else {
            return .noChange("scratchpad assign: disabled in configuration")
        }
        let name = ScratchpadStore.normalizedName(rawName)
        let snapshot = service.snapshot()
        let targetEntry: ScopedWindowSnapshot?
        if let windowID {
            targetEntry = snapshot.windows.first { $0.window.id == windowID }
        } else if let focusedID = service.focusedWindowID() ?? snapshot.focusedWindowID {
            targetEntry = snapshot.windows.first { $0.window.id == focusedID }
        } else {
            targetEntry = nil
        }
        guard let targetEntry,
              let display = activeDisplay(in: snapshot, fallbackWindow: targetEntry.window)
        else {
            return WindowCommandResult(message: "scratchpad assign \(name): no target window", changed: false, outcome: .noOp)
        }
        guard targetEntry.window.furniture?.isNativeFullscreen != true else {
            return .failure("scratchpad assign \(name): cannot assign native fullscreen window")
        }
        let window = targetEntry.window
        let frame = Self.centeredFrame(saved: nil, in: display.visibleFrame.cgRect)
        let sourceScope = targetEntry.scope

        do {
            try stageStore.mutateChecked { state in
                for idx in state.scopes.indices {
                    state.scopes[idx].remove(windowID: window.id)
                }
                if let sourceScope, let tree = state.bspTree(for: sourceScope) {
                    state.setBSPTree(tree.removing(window.id), for: sourceScope)
                }
                state.suppressRulePlacement(window: window)
            }
            try scratchpadStore.mutateChecked { book in
                // Une fenêtre ne peut appartenir qu'à un seul scratchpad à la fois.
                for (existingName, entry) in book.entries where entry.windowID == window.id && existingName != name {
                    book.entries.removeValue(forKey: existingName)
                }
                book.entries[name] = PersistentScratchpadEntry(
                    name: name,
                    windowID: window.id,
                    bundleID: window.bundleID,
                    title: window.title,
                    isVisible: true,
                    floatingFrame: Rect(frame)
                )
            }
        } catch {
            return .persistenceFailure("scratchpad assign \(name)", error)
        }

        _ = service.setFrame(frame, of: window)
        _ = service.focus(window)
        if let sourceScope {
            try? service.removeLayoutIntentChecked(scope: sourceScope)
            _ = service.applyTreeScope(sourceScope, cause: "scratchpad.assign", generation: PlacementGeneration.shared.next())
        }
        events.append(RoadieEvent(type: "scratchpad_assign", details: [
            "name": name,
            "windowID": String(window.id.rawValue),
            "bundleID": window.bundleID,
        ]))
        return WindowCommandResult(message: "scratchpad assign \(name): window=\(window.id.rawValue)", changed: true, outcome: .changed)
    }

    /// Bascule l'affichage du scratchpad `name` (visible sur l'écran actif ↔ masqué hors écran).
    public func toggle(name rawName: String? = nil) -> WindowCommandResult {
        guard service.effectiveConfig.tiling.scratchpadEnabled else {
            return .noChange("scratchpad toggle: disabled in configuration")
        }
        let name = ScratchpadStore.normalizedName(rawName)
        let snapshot = service.snapshot()
        guard let resolved = resolveWindow(for: name, in: snapshot) else {
            return WindowCommandResult(message: "scratchpad toggle \(name): no window assigned", changed: false, outcome: .noOp)
        }
        guard let display = activeDisplay(in: snapshot, fallbackWindow: resolved.window) else {
            return .failure("scratchpad toggle \(name): no active display")
        }
        let isHiddenNow = HiddenWindowPlacement.isHiddenOrLegacyOffscreen(resolved.window.frame.cgRect, in: snapshot.displays)
        let isOnActiveDisplay = display.frame.cgRect.contains(resolved.window.frame.center)
        if resolved.entry.isVisible && !isHiddenNow && isOnActiveDisplay {
            return hide(name: name, snapshot: snapshot, resolved: resolved, display: display)
        }
        return show(name: name, snapshot: snapshot, resolved: resolved, display: display)
    }

    public func show(name rawName: String? = nil) -> WindowCommandResult {
        guard service.effectiveConfig.tiling.scratchpadEnabled else {
            return .noChange("scratchpad show: disabled in configuration")
        }
        let name = ScratchpadStore.normalizedName(rawName)
        let snapshot = service.snapshot()
        guard let resolved = resolveWindow(for: name, in: snapshot) else {
            return WindowCommandResult(message: "scratchpad show \(name): no window assigned", changed: false, outcome: .noOp)
        }
        guard let display = activeDisplay(in: snapshot, fallbackWindow: resolved.window) else {
            return .failure("scratchpad show \(name): no active display")
        }
        return show(name: name, snapshot: snapshot, resolved: resolved, display: display)
    }

    public func hide(name rawName: String? = nil) -> WindowCommandResult {
        guard service.effectiveConfig.tiling.scratchpadEnabled else {
            return .noChange("scratchpad hide: disabled in configuration")
        }
        let name = ScratchpadStore.normalizedName(rawName)
        let snapshot = service.snapshot()
        guard let resolved = resolveWindow(for: name, in: snapshot) else {
            return WindowCommandResult(message: "scratchpad hide \(name): no window assigned", changed: false, outcome: .noOp)
        }
        guard let display = activeDisplay(in: snapshot, fallbackWindow: resolved.window) else {
            return .failure("scratchpad hide \(name): no active display")
        }
        return hide(name: name, snapshot: snapshot, resolved: resolved, display: display)
    }

    /// Détache le scratchpad `name` pour laisser la fenêtre revenir dans le cycle normal.
    public func release(name rawName: String? = nil) -> WindowCommandResult {
        let name = ScratchpadStore.normalizedName(rawName)
        let removed: PersistentScratchpadEntry?
        do {
            removed = try scratchpadStore.mutateChecked { book in
                book.entries.removeValue(forKey: name)
            }
        } catch {
            return .persistenceFailure("scratchpad release \(name)", error)
        }
        guard let removed else {
            return WindowCommandResult(message: "scratchpad release \(name): unknown", changed: false, outcome: .noOp)
        }
        events.append(RoadieEvent(type: "scratchpad_release", details: [
            "name": name,
            "windowID": String(removed.windowID.rawValue),
        ]))
        return WindowCommandResult(message: "scratchpad release \(name): window=\(removed.windowID.rawValue)", changed: true, outcome: .changed)
    }

    public func list() -> [PersistentScratchpadEntry] {
        scratchpadStore.load().entries.values.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    // MARK: - Internes

    private func show(
        name: String,
        snapshot: DaemonSnapshot,
        resolved: (entry: PersistentScratchpadEntry, window: WindowSnapshot, fromBook: Bool),
        display: DisplaySnapshot
    ) -> WindowCommandResult {
        if !resolved.fromBook {
            detachFromStagesIfNeeded(window: resolved.window, in: snapshot)
        }
        let frame = Self.centeredFrame(saved: resolved.entry.floatingFrame, in: display.visibleFrame.cgRect)
        do {
            try scratchpadStore.mutateChecked { book in
                book.entries[name] = PersistentScratchpadEntry(
                    name: name,
                    windowID: resolved.window.id,
                    bundleID: resolved.window.bundleID,
                    title: resolved.window.title,
                    isVisible: true,
                    floatingFrame: Rect(frame)
                )
            }
        } catch {
            return .persistenceFailure("scratchpad show \(name)", error)
        }
        let placed = service.setFrame(frame, of: resolved.window) != nil
        _ = service.focus(resolved.window)
        events.append(RoadieEvent(type: "scratchpad_show", details: [
            "name": name,
            "windowID": String(resolved.window.id.rawValue),
            "placed": String(placed),
        ]))
        return WindowCommandResult.changedOrFailed(
            "scratchpad show \(name): window=\(resolved.window.id.rawValue)",
            changed: placed
        )
    }

    private func hide(
        name: String,
        snapshot: DaemonSnapshot,
        resolved: (entry: PersistentScratchpadEntry, window: WindowSnapshot, fromBook: Bool),
        display: DisplaySnapshot
    ) -> WindowCommandResult {
        if !resolved.fromBook {
            detachFromStagesIfNeeded(window: resolved.window, in: snapshot)
        }
        let currentVisibleFrame = HiddenWindowPlacement.isHiddenOrLegacyOffscreen(resolved.window.frame.cgRect, in: snapshot.displays)
            ? resolved.entry.floatingFrame
            : resolved.window.frame
        let hiddenFrame = HiddenWindowPlacement.frame(for: resolved.window.frame.cgRect, on: display, among: snapshot.displays)
        do {
            try scratchpadStore.mutateChecked { book in
                book.entries[name] = PersistentScratchpadEntry(
                    name: name,
                    windowID: resolved.window.id,
                    bundleID: resolved.window.bundleID,
                    title: resolved.window.title,
                    isVisible: false,
                    floatingFrame: currentVisibleFrame
                )
            }
        } catch {
            return .persistenceFailure("scratchpad hide \(name)", error)
        }
        let moved = service.setFrame(hiddenFrame, of: resolved.window) != nil
        events.append(RoadieEvent(type: "scratchpad_hide", details: [
            "name": name,
            "windowID": String(resolved.window.id.rawValue),
            "moved": String(moved),
        ]))
        return WindowCommandResult.changedOrFailed(
            "scratchpad hide \(name): window=\(resolved.window.id.rawValue)",
            changed: moved
        )
    }

    private func detachFromStagesIfNeeded(window: WindowSnapshot, in snapshot: DaemonSnapshot) {
        let sourceScope = snapshot.windows.first(where: { $0.window.id == window.id })?.scope
        try? stageStore.mutateChecked { state in
            for idx in state.scopes.indices {
                state.scopes[idx].remove(windowID: window.id)
            }
            if let sourceScope, let tree = state.bspTree(for: sourceScope) {
                state.setBSPTree(tree.removing(window.id), for: sourceScope)
            }
            state.suppressRulePlacement(window: window)
        }
        if let sourceScope {
            try? service.removeLayoutIntentChecked(scope: sourceScope)
            _ = service.applyTreeScope(sourceScope, cause: "scratchpad.detach", generation: PlacementGeneration.shared.next())
        }
    }

    private func resolveWindow(
        for name: String,
        in snapshot: DaemonSnapshot
    ) -> (entry: PersistentScratchpadEntry, window: WindowSnapshot, fromBook: Bool)? {
        let book = scratchpadStore.load()
        if let entry = book.entries[name],
           let live = snapshot.windows.first(where: { $0.window.id == entry.windowID })?.window {
            return (entry, live, true)
        }
        // Repli sur les règles `action.scratchpad = "<name>"` si la fenêtre correspond à une règle configurée.
        let rules = service.effectiveConfig.rules
        if !rules.isEmpty {
            let engine = WindowRuleEngine(rules: rules)
            for scoped in snapshot.windows {
                let matchContext = WindowRuleMatchContext(role: scoped.window.role, subrole: scoped.window.subrole)
                let app = engine.evaluate(window: scoped.window, context: matchContext)
                if let tag = app.scratchpad, ScratchpadStore.normalizedName(tag) == name {
                    let entry = PersistentScratchpadEntry(
                        name: name,
                        windowID: scoped.window.id,
                        bundleID: scoped.window.bundleID,
                        title: scoped.window.title,
                        isVisible: !HiddenWindowPlacement.isHiddenOrLegacyOffscreen(scoped.window.frame.cgRect, in: snapshot.displays),
                        floatingFrame: scoped.window.frame
                    )
                    return (entry, scoped.window, false)
                }
            }
        }
        return nil
    }

    private func activeDisplay(in snapshot: DaemonSnapshot, fallbackWindow: WindowSnapshot) -> DisplaySnapshot? {
        if let focusedID = service.focusedWindowID() ?? snapshot.focusedWindowID,
           let focused = snapshot.windows.first(where: { $0.window.id == focusedID }) {
            if let displayID = focused.scope?.displayID,
               let display = snapshot.displays.first(where: { $0.id == displayID }) {
                return display
            }
            if let display = snapshot.displays.first(where: { $0.frame.cgRect.contains(focused.window.frame.center) }) {
                return display
            }
        }
        if let activeID = stageStore.state().activeDisplayID,
           let display = snapshot.displays.first(where: { $0.id == activeID }) {
            return display
        }
        if let display = snapshot.displays.first(where: { $0.frame.cgRect.contains(fallbackWindow.frame.center) }) {
            return display
        }
        return snapshot.displays.first(where: \.isMain) ?? snapshot.displays.first
    }
}
