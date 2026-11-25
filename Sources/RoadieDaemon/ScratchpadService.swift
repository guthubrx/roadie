import AppKit
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

    /// Table `windowID -> bundleID` garantissant qu'un identifiant CGWindowID réutilisé par une
    /// autre application ne soit jamais confondu avec un scratchpad enregistré (Spec 162 R1).
    public var protectedWindows: [WindowID: String] {
        var map: [WindowID: String] = [:]
        map.reserveCapacity(entries.count)
        for entry in entries.values {
            map[entry.windowID] = entry.bundleID
        }
        return map
    }
}

/// Persistance locale des scratchpads nommés (`~/.roadies/scratchpads.json`, isolée en tests via `TestEnvironment`).
public final class ScratchpadStore: Sendable {
    public let url: URL

    /// Cache en mémoire des paires `windowID -> bundleID` par fichier, publié uniquement après
    /// persistance disque réussie (Spec 162 R1).
    private static let cachedWindowsByPath = OSAllocatedUnfairLock(initialState: [String: [WindowID: String]]())

    public init(path: String? = nil) {
        let resolvedPath = path ?? TestEnvironment.launcherFile("scratchpads.json")
        self.url = URL(fileURLWithPath: NSString(string: resolvedPath).expandingTildeInPath)
    }

    public func load() -> PersistentScratchpadBook {
        let book = JSONPersistence.load(PersistentScratchpadBook.self, from: url, default: PersistentScratchpadBook())
        let protected = book.protectedWindows
        Self.cachedWindowsByPath.withLock { $0[url.path] = protected }
        return book
    }

    @discardableResult
    public func mutateChecked<T>(_ body: (inout PersistentScratchpadBook) throws -> T) throws -> T {
        var committedProtected: [WindowID: String]?
        let result = try JSONPersistence.mutateChecked(
            PersistentScratchpadBook.self,
            at: url,
            default: PersistentScratchpadBook(),
            label: "scratchpads"
        ) { book in
            let output = try body(&book)
            committedProtected = book.protectedWindows
            return output
        }
        // Publier le cache seulement une fois l'écriture atomique sur disque réussie.
        if let committedProtected {
            Self.cachedWindowsByPath.withLock { $0[url.path] = committedProtected }
        }
        return result
    }

    /// Fenêtres protégées (`windowID -> bundleID`), lecture O(1) en mémoire ; charge au premier accès.
    public static func protectedWindows(for path: String? = nil) -> [WindowID: String] {
        let resolvedPath = path ?? TestEnvironment.launcherFile("scratchpads.json")
        let resolved = URL(fileURLWithPath: NSString(string: resolvedPath).expandingTildeInPath).path
        if let existing = cachedWindowsByPath.withLock({ $0[resolved] }) {
            return existing
        }
        guard FileManager.default.fileExists(atPath: resolved) else {
            cachedWindowsByPath.withLock { $0[resolved] = [:] }
            return [:]
        }
        let book = JSONPersistence.load(PersistentScratchpadBook.self, from: URL(fileURLWithPath: resolved), default: PersistentScratchpadBook())
        let protected = book.protectedWindows
        cachedWindowsByPath.withLock { $0[resolved] = protected }
        return protected
    }

    /// Identifiants actuellement enregistrés en scratchpad (lecture O(1) en mémoire).
    public static func protectedWindowIDs(for path: String? = nil) -> Set<WindowID> {
        Set(protectedWindows(for: path).keys)
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
    private let appLauncher: @Sendable (String) -> Bool

    public init(
        service: SnapshotService = SnapshotService(),
        stageStore: StageStore? = nil,
        scratchpadStore: ScratchpadStore = ScratchpadStore(),
        events: EventLog = EventLog(),
        appLauncher: (@Sendable (String) -> Bool)? = nil
    ) {
        self.service = service
        self.stageStore = stageStore ?? service.effectiveStageStore
        self.scratchpadStore = scratchpadStore
        self.events = events
        self.appLauncher = appLauncher ?? Self.defaultAppLauncher
    }

    private static func defaultAppLauncher(bundleID: String) -> Bool {
        guard !TestEnvironment.isRunningTests, !bundleID.isEmpty,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return false
        }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: config)
        return true
    }

    /// Nom du scratchpad contenant `windowID` (vérifié par `bundleID`), ou `nil` si la fenêtre n'est pas en scratchpad.
    public func scratchpadName(for windowID: WindowID, bundleID: String) -> String? {
        let book = scratchpadStore.load()
        return book.entries.values.first { $0.windowID == windowID && $0.bundleID == bundleID }?.name
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

        // Persistance atomique : enregistrer le scratchpad d'abord, puis détacher de la stage ;
        // en cas d'échec sur stages.json, restaurer intégralement le livre scratchpads.
        let previousBook: PersistentScratchpadBook
        do {
            previousBook = try scratchpadStore.mutateChecked { book in
                let before = book
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
                return before
            }
        } catch {
            return .persistenceFailure("scratchpad assign \(name)", error)
        }

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
        } catch {
            do {
                try scratchpadStore.mutateChecked { book in
                    book = previousBook
                }
            } catch let rollbackError {
                return .partial("scratchpad assign \(name): stage persistence failed (\(error)) and rollback failed (\(rollbackError))")
            }
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
    /// Après un redémarrage ou fermeture de fenêtre, applique `tiling.scratchpad_reboot_policy`
    /// (`reattach_or_relaunch`, `reattach` ou `ephemeral`, Spec 166).
    public func toggle(name rawName: String? = nil) -> WindowCommandResult {
        guard service.effectiveConfig.tiling.scratchpadEnabled else {
            return .noChange("scratchpad toggle: disabled in configuration")
        }
        let name = ScratchpadStore.normalizedName(rawName)
        let snapshot = service.snapshot()
        guard let resolved = resolveWindow(for: name, in: snapshot) else {
            if let relaunchResult = relaunchIfConfigured(name: name, verb: "toggle") {
                return relaunchResult
            }
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
            if let relaunchResult = relaunchIfConfigured(name: name, verb: "show") {
                return relaunchResult
            }
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
    /// Si la fenêtre est masquée hors écran, la restauration de son cadre réussit avant la suppression
    /// du registre afin qu'un échec AX n'abandonne jamais une fenêtre hors écran sans référence (Spec 162 R2).
    public func release(name rawName: String? = nil) -> WindowCommandResult {
        let name = ScratchpadStore.normalizedName(rawName)
        guard let existing = scratchpadStore.load().entries[name] else {
            return WindowCommandResult(message: "scratchpad release \(name): unknown", changed: false, outcome: .noOp)
        }
        let snapshot = service.snapshot()
        if let live = snapshot.windows.first(where: {
            $0.window.id == existing.windowID && $0.window.bundleID == existing.bundleID
        })?.window,
           live.furniture?.isNativeFullscreen != true,
           HiddenWindowPlacement.isHiddenOrLegacyOffscreen(live.frame.cgRect, in: snapshot.displays) {
            guard let display = activeDisplay(in: snapshot, fallbackWindow: live) else {
                return .failure("scratchpad release \(name): no active display to restore hidden window")
            }
            let restoredFrame = Self.centeredFrame(saved: existing.floatingFrame, in: display.visibleFrame.cgRect)
            guard service.setFrame(restoredFrame, of: live) != nil else {
                return .failure("scratchpad release \(name): failed to restore hidden window")
            }
            _ = service.focus(live)
        }
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

    /// Transaction atomique partagée (`assign`, `show`/`hide` sur repli règle) : persiste d'abord
    /// l'entrée scratchpad, puis détache la fenêtre des stages si demandé ; en cas d'échec de
    /// `stages.json`, restaure le livre scratchpads à son état antérieur (Spec 162 R2).
    private func persistEntryAndDetachIfNeeded(
        commandLabel: String,
        entry: PersistentScratchpadEntry,
        window: WindowSnapshot,
        detachFromStages: Bool,
        sourceScope: StageScope?
    ) -> WindowCommandResult? {
        let previousBook: PersistentScratchpadBook
        do {
            previousBook = try scratchpadStore.mutateChecked { book in
                let before = book
                for (existingName, item) in book.entries where item.windowID == entry.windowID && existingName != entry.name {
                    book.entries.removeValue(forKey: existingName)
                }
                book.entries[entry.name] = entry
                return before
            }
        } catch {
            return .persistenceFailure(commandLabel, error)
        }

        guard detachFromStages else { return nil }
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
        } catch {
            do {
                try scratchpadStore.mutateChecked { book in
                    book = previousBook
                }
            } catch let rollbackError {
                return .partial("\(commandLabel): stage persistence failed (\(error)) and rollback failed (\(rollbackError))")
            }
            return .persistenceFailure(commandLabel, error)
        }

        if let sourceScope {
            try? service.removeLayoutIntentChecked(scope: sourceScope)
            _ = service.applyTreeScope(sourceScope, cause: "scratchpad.detach", generation: PlacementGeneration.shared.next())
        }
        return nil
    }

    private func show(
        name: String,
        snapshot: DaemonSnapshot,
        resolved: (entry: PersistentScratchpadEntry, window: WindowSnapshot, fromBook: Bool),
        display: DisplaySnapshot
    ) -> WindowCommandResult {
        guard resolved.window.furniture?.isNativeFullscreen != true else {
            return .failure("scratchpad show \(name): window is in native fullscreen")
        }
        let frame = Self.centeredFrame(saved: resolved.entry.floatingFrame, in: display.visibleFrame.cgRect)
        let nextEntry = PersistentScratchpadEntry(
            name: name,
            windowID: resolved.window.id,
            bundleID: resolved.window.bundleID,
            title: resolved.window.title,
            isVisible: true,
            floatingFrame: Rect(frame)
        )
        let sourceScope = snapshot.windows.first(where: { $0.window.id == resolved.window.id })?.scope
        if let failure = persistEntryAndDetachIfNeeded(
            commandLabel: "scratchpad show \(name)",
            entry: nextEntry,
            window: resolved.window,
            detachFromStages: !resolved.fromBook,
            sourceScope: sourceScope
        ) {
            return failure
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
        guard resolved.window.furniture?.isNativeFullscreen != true else {
            return .failure("scratchpad hide \(name): window is in native fullscreen")
        }
        let currentVisibleFrame = HiddenWindowPlacement.isHiddenOrLegacyOffscreen(resolved.window.frame.cgRect, in: snapshot.displays)
            ? resolved.entry.floatingFrame
            : resolved.window.frame
        let hiddenFrame = HiddenWindowPlacement.frame(for: resolved.window.frame.cgRect, on: display, among: snapshot.displays)
        let nextEntry = PersistentScratchpadEntry(
            name: name,
            windowID: resolved.window.id,
            bundleID: resolved.window.bundleID,
            title: resolved.window.title,
            isVisible: false,
            floatingFrame: currentVisibleFrame
        )
        let sourceScope = snapshot.windows.first(where: { $0.window.id == resolved.window.id })?.scope
        if let failure = persistEntryAndDetachIfNeeded(
            commandLabel: "scratchpad hide \(name)",
            entry: nextEntry,
            window: resolved.window,
            detachFromStages: !resolved.fromBook,
            sourceScope: sourceScope
        ) {
            return failure
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

    private func relaunchIfConfigured(name: String, verb: String) -> WindowCommandResult? {
        guard service.effectiveConfig.tiling.scratchpadRebootPolicy == "reattach_or_relaunch" else { return nil }
        guard let entry = scratchpadStore.load().entries[name], !entry.bundleID.isEmpty else { return nil }
        guard appLauncher(entry.bundleID) else { return nil }
        events.append(RoadieEvent(type: "scratchpad_relaunch", details: [
            "name": name,
            "bundleID": entry.bundleID,
        ]))
        return WindowCommandResult(
            message: "scratchpad \(verb) \(name): relaunching \(entry.bundleID)",
            changed: true,
            outcome: .changed
        )
    }

    private func resolveWindow(
        for name: String,
        in snapshot: DaemonSnapshot
    ) -> (entry: PersistentScratchpadEntry, window: WindowSnapshot, fromBook: Bool)? {
        let book = scratchpadStore.load()
        if let entry = book.entries[name],
           let live = snapshot.windows.first(where: {
               $0.window.id == entry.windowID && $0.window.bundleID == entry.bundleID
           })?.window {
            return (entry, live, true)
        }
        // Politique au redémarrage / fermeture (Spec 166) : si l'app a rouvert avec un nouveau CGWindowID,
        // rattacher sa fenêtre correspondante (priorité au titre exact, puis première fenêtre non prise).
        let policy = service.effectiveConfig.tiling.scratchpadRebootPolicy
        if policy != "ephemeral", let entry = book.entries[name], !entry.bundleID.isEmpty {
            let otherScratchpadIDs = Set(book.entries.filter { $0.key != name }.values.map(\.windowID))
            let candidates = snapshot.windows.map(\.window).filter {
                $0.bundleID == entry.bundleID
                    && !otherScratchpadIDs.contains($0.id)
                    && $0.furniture?.isNativeFullscreen != true
            }
            let matched = candidates.first(where: { !entry.title.isEmpty && $0.title == entry.title })
                ?? candidates.first(where: \.isTileCandidate)
                ?? candidates.first
            if let live = matched {
                let reattached = PersistentScratchpadEntry(
                    name: name,
                    windowID: live.id,
                    bundleID: live.bundleID,
                    title: live.title,
                    isVisible: false,
                    floatingFrame: entry.floatingFrame
                )
                return (reattached, live, false)
            }
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
