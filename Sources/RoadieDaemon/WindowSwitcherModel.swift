import Foundation
import RoadieAX
import RoadieCore

struct WindowSwitcherEntry: Identifiable, Equatable, Sendable {
    let window: WindowSnapshot
    let scope: StageScope?
    let displayName: String
    let desktopName: String
    let stageName: String
    let isMinimized: Bool
    let isHidden: Bool
    let isFullscreen: Bool
    let isAvailable: Bool
    let visibilityKnown: Bool

    var id: WindowID { window.id }

    init(
        window: WindowSnapshot,
        scope: StageScope?,
        displayName: String = "",
        desktopName: String = "",
        stageName: String = "",
        isMinimized: Bool = false,
        isHidden: Bool = false,
        isFullscreen: Bool = false,
        isAvailable: Bool = true,
        visibilityKnown: Bool = true
    ) {
        self.window = window
        self.scope = scope
        self.displayName = displayName
        self.desktopName = desktopName
        self.stageName = stageName
        self.isMinimized = isMinimized
        self.isHidden = isHidden
        self.isFullscreen = isFullscreen
        self.isAvailable = isAvailable
        self.visibilityKnown = visibilityKnown
    }
}

struct WindowSwitcherContext: Equatable, Sendable {
    var focusedWindowID: WindowID?
    var displayID: DisplayID?
    var desktopID: DesktopID?
    var stageID: StageID?
    var bundleID: String?
}

/// Ordre des fenêtres récentes, partagé par le processus. Les identifiants sont bornés à 512.
final class WindowSwitcherFocusHistory: @unchecked Sendable {
    static let shared = WindowSwitcherFocusHistory()
    static let capacity = 512

    private let lock = NSLock()
    private var ids: [WindowID] = []

    var recentIDs: [WindowID] {
        lock.withLock { ids }
    }

    func observe(_ id: WindowID?) {
        guard let id else { return }
        let left: WindowID? = lock.withLock {
            if ids.first == id { return nil }
            let previous = ids.first
            ids.removeAll { $0 == id }
            ids.insert(id, at: 0)
            if ids.count > Self.capacity {
                ids.removeLast(ids.count - Self.capacity)
            }
            return previous
        }
        // Session 136 : la fenêtre quittée reprend en photo ses zones, dans l'état où on la laisse.
        if let left { Task { @MainActor in ZoneThumbnails.shared.windowLeft(left.rawValue) } }
    }
}

/// Liste filtrée, triée et recherchable du sélecteur. Ne fait aucune E/S ni aucun focus.
struct WindowSwitcherModel {
    private var entries: [WindowSwitcherEntry]
    private var profile: WindowSwitcherShortcutConfig
    private let context: WindowSwitcherContext
    private let recentRanks: [WindowID: Int]
    private var excludedBundles: Set<String>
    private(set) var query = ""
    private(set) var matches: [WindowSwitcherEntry] = []
    private var selectedID: WindowID?

    private struct Ranked {
        let entry: WindowSwitcherEntry
        let rank: Int
        let key: String
        let recency: Int
        let offset: Int
    }

    init(
        entries: [WindowSwitcherEntry],
        profile: WindowSwitcherShortcutConfig,
        context: WindowSwitcherContext,
        recentIDs: [WindowID] = [],
        excludedBundles: [String] = []
    ) {
        self.entries = entries
        self.profile = profile
        self.context = context
        self.recentRanks = Dictionary(
            recentIDs.enumerated().map { ($0.element, $0.offset) },
            uniquingKeysWith: { first, _ in first }
        )
        self.excludedBundles = Set(excludedBundles)
        self.matches = computeMatches()
        self.selectedID = initialSelection()
    }

    var selected: WindowSwitcherEntry? {
        guard let selectedID else { return nil }
        return matches.first { $0.id == selectedID }
    }

    mutating func selectInitialBackwards() {
        guard !matches.isEmpty else { return }
        if let index = matches.firstIndex(where: { $0.id == context.focusedWindowID }) {
            selectedID = matches[(index + matches.count - 1) % matches.count].id
        } else { selectedID = matches.last?.id }
    }

    mutating func next(backwards: Bool = false) {
        guard !matches.isEmpty else {
            selectedID = nil
            return
        }
        if let index = matches.firstIndex(where: { $0.id == selectedID }) {
            selectedID = matches[(index + (backwards ? matches.count - 1 : 1)) % matches.count].id
        } else {
            selectedID = matches[backwards ? matches.count - 1 : 0].id
        }
    }

    mutating func select(id: WindowID) {
        guard matches.contains(where: { $0.id == id }) else { return }
        selectedID = id
    }

    mutating func search(_ query: String) {
        self.query = query
        matches = computeMatches()
        if !matches.contains(where: { $0.id == selectedID }) { selectedID = matches.first?.id }
    }

    mutating func configure(profile: WindowSwitcherShortcutConfig, excludedBundles: [String]) {
        self.profile = profile
        self.excludedBundles = Set(excludedBundles)
        search(query)
    }

    mutating func remove(id: WindowID) {
        let previousIndex = matches.firstIndex { $0.id == id }
        entries.removeAll { $0.id == id }
        matches = computeMatches()
        guard selectedID == id else { return }
        selectedID = matches.isEmpty ? nil : matches[min(previousIndex ?? 0, matches.count - 1)].id
    }

    private func computeMatches() -> [WindowSwitcherEntry] {
        let needle = Self.fold(query.trimmingCharacters(in: .whitespacesAndNewlines))
        let tokens = needle.split(separator: " ").map(String.init)
        var ranked: [Ranked] = []
        for (offset, entry) in entries.enumerated() where isVisible(entry) {
            let haystack = Self.fold(
                [entry.window.appName, entry.window.title, entry.stageName, entry.desktopName, entry.displayName]
                    .joined(separator: " ")
            )
            guard tokens.allSatisfy({ haystack.contains($0) }) else { continue }
            ranked.append(Ranked(
                entry: entry,
                rank: relevance(of: entry, needle: needle),
                key: needle.isEmpty ? sortKey(entry) : "",
                recency: recency(entry.id),
                offset: offset
            ))
        }
        var seenBundles = Set<String>()
        return ranked
            .sorted { ($0.rank, $0.key, $0.recency, $0.offset) < ($1.rank, $1.key, $1.recency, $1.offset) }
            .map(\.entry)
            .filter { entry in
                guard profile.onePerApp else { return true }
                return seenBundles.insert(entry.window.bundleID).inserted
            }
    }

    private func initialSelection() -> WindowID? {
        guard matches.count >= 2 else { return matches.first?.id }
        let previous = matches
            .filter { $0.id != context.focusedWindowID }
            .min { recency($0.id) < recency($1.id) }
        return previous?.id ?? matches.first?.id
    }

    private func isVisible(_ entry: WindowSwitcherEntry) -> Bool {
        guard entry.isAvailable, !excludedBundles.contains(entry.window.bundleID) else { return false }
        if !entry.visibilityKnown, !profile.includeMinimized || !profile.includeHidden || !profile.includeFullscreen { return false }
        if entry.isMinimized, !profile.includeMinimized { return false }
        if entry.isHidden, !profile.includeHidden { return false }
        if entry.isFullscreen, !profile.includeFullscreen { return false }
        return inScope(entry)
    }

    private func inScope(_ entry: WindowSwitcherEntry) -> Bool {
        switch profile.scope {
        case "stage":
            guard let displayID = context.displayID, let desktopID = context.desktopID, let stageID = context.stageID else {
                return false
            }
            return entry.scope == StageScope(displayID: displayID, desktopID: desktopID, stageID: stageID)
        case "desktop":
            guard let displayID = context.displayID, let desktopID = context.desktopID else { return false }
            return entry.scope?.displayID == displayID && entry.scope?.desktopID == desktopID
        case "display":
            guard let displayID = context.displayID else { return false }
            return entry.scope?.displayID == displayID
        case "application":
            guard let bundleID = context.bundleID else { return false }
            return entry.window.bundleID == bundleID
        default:
            return true
        }
    }

    private func sortKey(_ entry: WindowSwitcherEntry) -> String {
        switch profile.sortOrder {
        case "title":
            return Self.fold(entry.window.title)
        case "stage":
            return Self.fold([entry.displayName, entry.desktopName, entry.stageName].joined(separator: "\u{1F}"))
        default:
            return ""
        }
    }

    private func relevance(of entry: WindowSwitcherEntry, needle: String) -> Int {
        guard !needle.isEmpty else { return 0 }
        let names = [entry.window.appName, entry.window.title].map(Self.fold)
        if names.contains(where: { $0.hasPrefix(needle) }) { return 0 }
        if names.contains(where: { $0.contains(needle) }) { return 1 }
        return 2
    }

    private func recency(_ id: WindowID) -> Int {
        recentRanks[id] ?? Int.max
    }

    private static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }
}
