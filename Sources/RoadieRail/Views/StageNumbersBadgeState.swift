import Foundation
import SwiftUI

/// SPEC-026 — état partagé du badge "numéro de stage" dans le navrail.
/// `configEnabled` : flag TOML `[fx.rail].stage_numbers_enabled` (permanent).
/// `flashUntil` : timestamp transitoire activable via `roadie rail stage-numbers
/// flash <seconds>` (apparition temporaire à la demande).
///
/// Le badge est visible si l'un des deux est actif.
@MainActor
public final class StageNumbersBadgeState: ObservableObject {
    public static let shared = StageNumbersBadgeState()

    @Published public var configEnabled: Bool = false
    @Published public var flashUntil: Date? = nil
    /// SPEC-026 — paramètres visuels du badge, settable depuis main.swift au boot et au reload.
    @Published public var offsetX: Double = 4
    @Published public var offsetY: Double = -30
    @Published public var fontSize: Double = 64
    @Published public var opacity: Double = 0.22

    public init() {}

    public var isVisible: Bool {
        if configEnabled { return true }
        if let until = flashUntil, Date() < until { return true }
        return false
    }

    /// Active le badge pour `seconds` secondes (utilisé par le raccourci flash).
    /// Auto-clear via Task.sleep — pas besoin de timer Combine.
    public func flash(seconds: TimeInterval) {
        let target = Date().addingTimeInterval(seconds)
        flashUntil = target
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            // Ne reset que si le flashUntil n'a pas été repoussé entre temps.
            if let cur = self?.flashUntil, cur <= Date() {
                self?.flashUntil = nil
            }
        }
    }
}
