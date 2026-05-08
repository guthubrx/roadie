import Foundation
import RoadieAX
import RoadieCore

public struct WindowIdentityMatch: Codable, Equatable, Sendable {
    public var savedWindowID: UInt32?
    public var liveWindowID: UInt32?
    public var score: Double
    public var accepted: Bool
    public var reason: String?

    public init(savedWindowID: UInt32?, liveWindowID: UInt32?, score: Double, accepted: Bool, reason: String? = nil) {
        self.savedWindowID = savedWindowID
        self.liveWindowID = liveWindowID
        self.score = score
        self.accepted = accepted
        self.reason = reason
    }
}

public struct WindowIdentityService {
    public static func identity(for window: WindowSnapshot, createdAt: Date? = nil) -> WindowIdentityV2 {
        WindowIdentityV2(
            bundleID: window.bundleID.isEmpty ? nil : window.bundleID,
            appName: window.appName,
            title: window.title,
            role: window.role,
            subrole: window.subrole,
            pidHint: window.pid,
            windowIDHint: window.id.rawValue,
            createdAt: createdAt
        )
    }

    public init() {}

    public func score(saved: WindowIdentityV2, live: WindowIdentityV2) -> Double {
        var score = 0.0
        if let bundle = saved.bundleID, !bundle.isEmpty, bundle == live.bundleID { score += 0.45 }
        if !saved.appName.isEmpty && saved.appName == live.appName { score += 0.2 }
        if !saved.title.isEmpty && saved.title == live.title { score += 0.25 }
        if !saved.title.isEmpty && !live.title.isEmpty && saved.title != live.title &&
            (saved.title.contains(live.title) || live.title.contains(saved.title)) { score += 0.12 }
        if saved.role != nil && saved.role == live.role { score += 0.05 }
        if saved.subrole != nil && saved.subrole == live.subrole { score += 0.05 }
        return min(score, 1.0)
    }

    public func match(saved: [RestoreWindowState], live: [WindowSnapshot], threshold: Double = 0.7) -> [WindowIdentityMatch] {
        var used: Set<UInt32> = []
        return saved.map { item in
            if let savedID = item.windowID,
               live.contains(where: { $0.id.rawValue == savedID }),
               !used.contains(savedID) {
                used.insert(savedID)
                return WindowIdentityMatch(savedWindowID: savedID, liveWindowID: savedID, score: 1, accepted: true, reason: "window_id")
            }
            let candidates = live.map { window in
                (window: window, score: score(saved: item.identity, live: Self.identity(for: window)))
            }.sorted { lhs, rhs in
                if lhs.score == rhs.score { return lhs.window.id.rawValue < rhs.window.id.rawValue }
                return lhs.score > rhs.score
            }
            guard let best = candidates.first, best.score >= threshold else {
                return WindowIdentityMatch(savedWindowID: item.windowID, liveWindowID: nil, score: candidates.first?.score ?? 0, accepted: false, reason: "below_threshold")
            }
            if candidates.dropFirst().first?.score == best.score {
                return WindowIdentityMatch(savedWindowID: item.windowID, liveWindowID: nil, score: best.score, accepted: false, reason: "ambiguous")
            }
            guard !used.contains(best.window.id.rawValue) else {
                return WindowIdentityMatch(savedWindowID: item.windowID, liveWindowID: nil, score: best.score, accepted: false, reason: "duplicate_live_window")
            }
            used.insert(best.window.id.rawValue)
            return WindowIdentityMatch(savedWindowID: item.windowID, liveWindowID: best.window.id.rawValue, score: best.score, accepted: true, reason: "identity")
        }
    }
}
