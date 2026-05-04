import Foundation

// SPEC-025 FR-003 — Health metric capturé à la fin du bootstrap.
// Sert à détecter proactivement les états corrompus persistés et à alerter
// l'utilisateur via terminal-notifier si verdict != healthy.

public struct BootStateHealth: Codable, Sendable {
    public let totalWids: Int
    public let widsOffscreenAtRestore: Int   // par Stage.validateMembers (FR-001)
    public let widsZombiesPurged: Int        // par purgeOrphanWindows (FR-002)
    public let widToScopeDriftsFixed: Int    // par auditOwnership.count avant rebuild (FR-002)
    public let timestamp: Date

    public init(totalWids: Int,
                widsOffscreenAtRestore: Int,
                widsZombiesPurged: Int,
                widToScopeDriftsFixed: Int,
                timestamp: Date = Date()) {
        self.totalWids = totalWids
        self.widsOffscreenAtRestore = widsOffscreenAtRestore
        self.widsZombiesPurged = widsZombiesPurged
        self.widToScopeDriftsFixed = widToScopeDriftsFixed
        self.timestamp = timestamp
    }

    public enum Verdict: String, Codable, Sendable {
        case healthy
        case degraded
        case corrupted
    }

    public var verdict: Verdict {
        let touched = widsOffscreenAtRestore + widsZombiesPurged + widToScopeDriftsFixed
        guard totalWids > 0 else { return .healthy }
        if touched == 0 { return .healthy }
        let pct = Double(touched) / Double(totalWids)
        return pct < 0.30 ? .degraded : .corrupted
    }

    /// Sérialisation aplatie pour `[String: String]` du DesktopEvent.payload.
    public func toLogPayload() -> [String: String] {
        [
            "total_wids": String(totalWids),
            "offscreen_at_restore": String(widsOffscreenAtRestore),
            "zombies_purged": String(widsZombiesPurged),
            "drifts_fixed": String(widToScopeDriftsFixed),
            "verdict": verdict.rawValue,
        ]
    }
}
