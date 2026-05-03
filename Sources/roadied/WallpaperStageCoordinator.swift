import Foundation
import AppKit
import Darwin
import RoadieCore
import RoadieStagePlugin
import TOMLKit

// SPEC-014 T060-T063 (US4) — geste signature : click sur le bureau crée un stage
// rangeant toutes les fenêtres tilées du desktop courant.
//
// Garde-fous :
//   T061 : skip si rail pas lancé (~/.roadies/rail.pid absent ou PID mort)
//   T062 : skip si [fx.rail] wallpaper_click_to_stage = false
//   T063 : skip si aucune fenêtre tilée présente (no-op silencieux)

@MainActor
final class WallpaperStageCoordinator {
    private let registry: WindowRegistry
    private weak var stageManager: StageManager?
    private let railPidPath: String
    private let configPath: String

    init(registry: WindowRegistry,
         stageManager: StageManager,
         railPidPath: String = (NSString(string: "~/.roadies/rail.pid")
                                .expandingTildeInPath as String),
         configPath: String = (NSString(string: "~/.config/roadies/roadies.toml")
                               .expandingTildeInPath as String)) {
        self.registry = registry
        self.stageManager = stageManager
        self.railPidPath = railPidPath
        self.configPath = configPath
    }

    /// Appelé par WallpaperClickWatcher.onWallpaperClick. Tous les garde-fous sont
    /// vérifiés ici. Émet un event `wallpaper_click` puis crée la stage si conditions OK.
    func handleClick(at point: NSPoint) {
        EventBus.shared.publish(DesktopEvent.wallpaperClick(
            x: Int(point.x), y: Int(point.y), displayID: CGMainDisplayID()))

        guard isRailRunning() else {
            logInfo("wallpaper_click: skipped (rail not running)")
            return
        }
        guard isFeatureEnabled() else {
            logInfo("wallpaper_click: skipped (fx.rail.wallpaper_click_to_stage = false)")
            return
        }
        guard let sm = stageManager else { return }

        // T063 : snapshot des wid tilées (filtre isTileable && !isFloating).
        let tileds = registry.allWindows.filter { $0.isTileable && !$0.isFloating }
        guard !tileds.isEmpty else {
            logInfo("wallpaper_click: skipped (no tiled windows)")
            return
        }

        // T060 : nouvelle stage avec ID auto-incrémenté.
        let nextID = nextStageID(in: sm)
        let stageID = StageID(String(nextID))
        let stage = sm.createStage(id: stageID, displayName: "Stage \(nextID)")

        // Migration : assigner toutes les wid à la nouvelle stage.
        for state in tileds {
            sm.assign(wid: state.cgWindowID, to: stageID)
        }

        // Switch sur la nouvelle stage (qui devient vide visuellement après hide).
        sm.switchTo(stageID: stageID)

        logInfo("wallpaper_click: created stage \(nextID) with \(tileds.count) windows")
        _ = stage
    }

    // MARK: - Garde-fous

    /// T061 : lit ~/.roadies/rail.pid, vérifie que le PID répond à kill(0).
    private func isRailRunning() -> Bool {
        guard let data = FileManager.default.contents(atPath: railPidPath),
              let s = String(data: data, encoding: .utf8),
              let pid = Int32(s.trimmingCharacters(in: .whitespacesAndNewlines))
        else { return false }
        // kill(pid, 0) : retourne 0 si vivant, -1 sinon (pas d'envoi de signal réel).
        return Darwin.kill(pid, 0) == 0
    }

    /// T062 : lit [fx.rail] wallpaper_click_to_stage, default true (FR-031).
    private func isFeatureEnabled() -> Bool {
        guard let data = FileManager.default.contents(atPath: configPath),
              let toml = String(data: data, encoding: .utf8),
              let root = try? TOMLTable(string: toml),
              let fx = root["fx"]?.table,
              let rail = fx["rail"]?.table
        else { return true }  // default
        return rail["wallpaper_click_to_stage"]?.bool ?? true
    }

    /// Calcule le prochain ID numérique disponible (max + 1, fallback "2" si seul "1" existe).
    /// SPEC-022 : en perDisplay union de stagesV2 (toutes scopes) car le V1 dict
    /// stages peut être incomplet (collisions cross-scope sur stage "1").
    private func nextStageID(in sm: StageManager) -> Int {
        let nums: [Int]
        if sm.stageMode == .perDisplay {
            nums = sm.stagesV2.keys.compactMap { Int($0.stageID.value) }
        } else {
            nums = sm.stages.keys.compactMap { Int($0.value) }
        }
        return (nums.max() ?? 0) + 1
    }
}
