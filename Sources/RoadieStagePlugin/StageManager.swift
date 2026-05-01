import Foundation
import TOMLKit
import RoadieCore

/// Module opt-in : gère les groupes nommés de fenêtres.
/// Closure type pour décorréler le module Stage du module Tiler. Le daemon injecte
/// les fonctions du LayoutEngine pour que le StageManager puisse marquer les leaves
/// invisibles et déclencher un re-layout sans avoir une dépendance directe.
public struct LayoutHooks: Sendable {
    public let setLeafVisible: @MainActor (WindowID, Bool) -> Void
    public let applyLayout: @MainActor () -> Void
    public init(setLeafVisible: @escaping @MainActor (WindowID, Bool) -> Void,
                applyLayout: @escaping @MainActor () -> Void) {
        self.setLeafVisible = setLeafVisible
        self.applyLayout = applyLayout
    }
}

/// SPEC-006 RoadieOpacity peut s'enregistrer comme override pour intercepter
/// les hide/show des stages et appliquer α=0 au lieu d'offscreen. Si nil :
/// fallback sur HideStrategyImpl V2 (corner/minimize/hybrid).
@MainActor
public protocol StageHideOverride: AnyObject {
    func hide(wid: WindowID, isTileable: Bool)
    func show(wid: WindowID, isTileable: Bool)
}

@MainActor
public final class StageManager {
    private let registry: WindowRegistry
    private(set) public var hideStrategy: HideStrategy
    private(set) public var stages: [StageID: Stage] = [:]
    private(set) public var currentStageID: StageID?
    private let layoutHooks: LayoutHooks?
    /// SPEC-006 : si non nil, override les hide/show via le module RoadieOpacity.
    public weak var hideOverride: StageHideOverride?

    /// Dossier de persistance courant. En mode V1, c'est `~/.config/roadies/stages`.
    /// En mode V2 multi-desktop, le DesktopManager swap via `reload(stagesDir:)` pour
    /// pointer vers `~/.config/roadies/desktops/<uuid>/stages` à chaque transition.
    private(set) public var stagesDir: String

    public init(registry: WindowRegistry, hideStrategy: HideStrategy = .corner,
                stagesDir: String = "~/.config/roadies/stages",
                layoutHooks: LayoutHooks? = nil) {
        self.registry = registry
        self.hideStrategy = hideStrategy
        self.layoutHooks = layoutHooks
        self.stagesDir = (stagesDir as NSString).expandingTildeInPath
        try? FileManager.default.createDirectory(atPath: self.stagesDir, withIntermediateDirectories: true)
    }

    /// Multi-desktop V2 : swap atomique du dossier de persistance.
    /// 1) Sauve l'état du desktop quitté (frames courantes + saveActive).
    /// 2) Reset l'état en mémoire.
    /// 3) Pointe `stagesDir` vers le nouveau path.
    /// 4) Recharge depuis disque (loadFromDisk).
    /// FR-004 (sauvegarde avant quitter) + FR-005 (state isolé par UUID).
    public func reload(stagesDir newDir: String) {
        // 1) Capture frames courantes du stage actif (cohérent avec switchTo).
        if let current = currentStageID, var stage = stages[current] {
            for i in 0..<stage.memberWindows.count {
                let wid = stage.memberWindows[i].cgWindowID
                if let element = registry.axElement(for: wid),
                   let frame = AXReader.bounds(element) {
                    stage.memberWindows[i].savedFrame = SavedRect(frame)
                }
            }
            stages[current] = stage
            saveStage(stage)
        }
        saveActive()

        // 2-3) Reset + swap path
        stages.removeAll()
        currentStageID = nil
        let expanded = (newDir as NSString).expandingTildeInPath
        self.stagesDir = expanded
        try? FileManager.default.createDirectory(atPath: expanded, withIntermediateDirectories: true)

        // 4) Recharge
        loadFromDisk()
    }

    public func loadFromDisk() {
        guard let entries = try? FileManager.default.contentsOfDirectory(atPath: stagesDir) else { return }
        for entry in entries where entry.hasSuffix(".toml") && entry != "active.toml" {
            let path = "\(stagesDir)/\(entry)"
            guard let raw = try? String(contentsOfFile: path, encoding: .utf8),
                  let stage = try? TOMLDecoder().decode(Stage.self, from: raw) else {
                logWarn("stage file corrupt", ["path": path])
                continue
            }
            stages[stage.id] = stage
        }
        // Active stage
        let activePath = "\(stagesDir)/active.toml"
        if let raw = try? String(contentsOfFile: activePath, encoding: .utf8),
           let parsed = try? TOMLDecoder().decode([String: String].self, from: raw),
           let active = parsed["current_stage"] {
            currentStageID = StageID(active)
        }
        logInfo("stages loaded", ["count": String(stages.count), "current": currentStageID?.value ?? "nil"])
    }

    public func saveStage(_ stage: Stage) {
        let path = "\(stagesDir)/\(stage.id.value).toml"
        do {
            let toml = try TOMLEncoder().encode(stage)
            try toml.write(toFile: path, atomically: true, encoding: .utf8)
        } catch {
            logError("stage save failed", ["id": stage.id.value, "err": "\(error)"])
        }
    }

    private func saveActive() {
        let path = "\(stagesDir)/active.toml"
        let dict: [String: String] = ["current_stage": currentStageID?.value ?? ""]
        if let toml = try? TOMLEncoder().encode(dict) {
            try? toml.write(toFile: path, atomically: true, encoding: .utf8)
        }
    }

    // MARK: - API publique

    public func createStage(id: StageID, displayName: String) -> Stage {
        let stage = Stage(id: id, displayName: displayName)
        stages[id] = stage
        saveStage(stage)
        return stage
    }

    public func deleteStage(id: StageID) {
        stages.removeValue(forKey: id)
        let path = "\(stagesDir)/\(id.value).toml"
        try? FileManager.default.removeItem(atPath: path)
        if currentStageID == id { currentStageID = nil; saveActive() }
    }

    public func assign(wid: WindowID, to stageID: StageID) {
        guard let state = registry.get(wid) else { return }
        // Retirer de tout autre stage
        for (id, stage) in stages where id != stageID {
            var s = stage
            s.memberWindows.removeAll { $0.cgWindowID == wid }
            stages[id] = s
            saveStage(s)
        }
        // Ajouter au stage cible
        guard var target = stages[stageID] else {
            logWarn("assign: unknown stage", ["stage": stageID.value])
            return
        }
        if !target.memberWindows.contains(where: { $0.cgWindowID == wid }) {
            target.memberWindows.append(StageMember(
                cgWindowID: wid, bundleID: state.bundleID, titleHint: state.title,
                savedFrame: SavedRect(state.frame)))
        }
        target.lastActiveAt = Date()
        stages[stageID] = target
        saveStage(target)
        registry.update(wid) { $0.stageID = stageID }
    }

    public func switchTo(stageID: StageID) {
        guard let targetStage = stages[stageID] else {
            logWarn("switch: unknown stage", ["stage": stageID.value])
            return
        }
        // Capturer le from + name pour l'event stage_changed (V2 FR-015).
        let fromID = currentStageID
        let fromName = fromID.flatMap { stages[$0]?.displayName } ?? ""
        let toName = targetStage.displayName

        // Capturer les frames actuelles des fenêtres du stage actuel pour restauration future.
        if let current = currentStageID, var stage = stages[current] {
            for i in 0..<stage.memberWindows.count {
                let wid = stage.memberWindows[i].cgWindowID
                if let element = registry.axElement(for: wid),
                   let frame = AXReader.bounds(element) {
                    stage.memberWindows[i].savedFrame = SavedRect(frame)
                }
            }
            stages[current] = stage
            saveStage(stage)
        }

        // Masquer les autres stages.
        // - Fenêtre tilée : (1) marquer la leaf invisible (tiler la skip au layout,
        //   espace redistribué aux voisines), (2) hide AX physique (offscreen) car
        //   sans ça la fenêtre reste visible à sa dernière position.
        // - Fenêtre flottante : hide AX physique seulement.
        // SPEC-006 : si un override `hideOverride` est posé (ex : RoadieOpacity en
        // mode α=0), il prend le pas sur HideStrategyImpl pour les fenêtres
        // floating et appliquer α=0 au lieu d'offscreen.
        for (id, stage) in stages where id != stageID {
            for member in stage.memberWindows {
                let wid = member.cgWindowID
                let isTileable = registry.get(wid)?.isTileable ?? false
                if isTileable, let hooks = layoutHooks {
                    hooks.setLeafVisible(wid, false)
                }
                if let override = hideOverride {
                    override.hide(wid: wid, isTileable: isTileable)
                } else {
                    HideStrategyImpl.hide(wid, registry: registry, strategy: hideStrategy)
                }
            }
        }

        // Montrer le stage cible (symétrique).
        // - Tilée : (1) setLeafVisible(true), (2) le applyLayout qui suit la replacera
        //   à la bonne position dans le tree.
        // - Flottante : show AX + restaurer frame sauvegardée.
        guard var target = stages[stageID] else { return }
        for member in target.memberWindows {
            let wid = member.cgWindowID
            let isTileable = registry.get(wid)?.isTileable ?? false
            if isTileable, let hooks = layoutHooks {
                hooks.setLeafVisible(wid, true)
                // Pas de show ici : applyLayout va setBounds au bon endroit.
                if let override = hideOverride { override.show(wid: wid, isTileable: true) }
            } else {
                if let override = hideOverride {
                    override.show(wid: wid, isTileable: false)
                } else {
                    HideStrategyImpl.show(wid, registry: registry, strategy: hideStrategy)
                }
                if let saved = member.savedFrame, let element = registry.axElement(for: wid) {
                    AXReader.setBounds(element, frame: saved.cgRect)
                }
            }
        }
        // Re-layout pour propager les changements de visibilité aux fenêtres tilées.
        layoutHooks?.applyLayout()

        target.lastActiveAt = Date()
        stages[stageID] = target
        currentStageID = stageID
        saveStage(target)
        saveActive()

        // Émission event V2 stage_changed (FR-015). desktop_uuid extrait du stagesDir
        // (.../desktops/<uuid>/stages → uuid). En mode V1, le path est .../stages → ""
        // et l'event est quand même publié pour les subscribers (filtrable côté client).
        let desktopUUID = extractDesktopUUID(fromStagesDir: stagesDir)
        var payload: [String: String] = [
            "desktop_uuid": desktopUUID,
            "to": stageID.value,
            "to_name": toName,
        ]
        if let from = fromID {
            payload["from"] = from.value
            payload["from_name"] = fromName
        }
        EventBus.shared.publish(DesktopEvent(name: "stage_changed", payload: payload))

        logInfo("stage switched", ["to": stageID.value])
    }

    /// Extrait l'UUID du desktop depuis le path `.../desktops/<uuid>/stages`.
    /// Retourne "" si le path est `.../stages` (mode V1) ou inattendu.
    private func extractDesktopUUID(fromStagesDir dir: String) -> String {
        let parts = dir.split(separator: "/").map(String.init)
        guard parts.count >= 2,
              parts.last == "stages",
              let desktopIdx = parts.firstIndex(of: "desktops"),
              parts.indices.contains(desktopIdx + 1) else { return "" }
        return parts[desktopIdx + 1]
    }

    public func handleWindowDestroyed(_ wid: WindowID) {
        for (id, stage) in stages {
            var s = stage
            let before = s.memberWindows.count
            s.memberWindows.removeAll { $0.cgWindowID == wid }
            if s.memberWindows.count != before {
                stages[id] = s
                saveStage(s)
            }
        }
    }
}
