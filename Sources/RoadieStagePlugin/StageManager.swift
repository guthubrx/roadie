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

@MainActor
public final class StageManager {
    private let registry: WindowRegistry
    private(set) public var hideStrategy: HideStrategy
    private(set) public var stages: [StageID: Stage] = [:]
    private(set) public var currentStageID: StageID?
    private let layoutHooks: LayoutHooks?

    private let stagesDir: String

    public init(registry: WindowRegistry, hideStrategy: HideStrategy = .corner,
                stagesDir: String = "~/.config/roadies/stages",
                layoutHooks: LayoutHooks? = nil) {
        self.registry = registry
        self.hideStrategy = hideStrategy
        self.layoutHooks = layoutHooks
        self.stagesDir = (stagesDir as NSString).expandingTildeInPath
        try? FileManager.default.createDirectory(atPath: self.stagesDir, withIntermediateDirectories: true)
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
        guard stages[stageID] != nil else {
            logWarn("switch: unknown stage", ["stage": stageID.value])
            return
        }
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
        for (id, stage) in stages where id != stageID {
            for member in stage.memberWindows {
                let wid = member.cgWindowID
                let isTileable = registry.get(wid)?.isTileable ?? false
                if isTileable, let hooks = layoutHooks {
                    hooks.setLeafVisible(wid, false)
                }
                HideStrategyImpl.hide(wid, registry: registry, strategy: hideStrategy)
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
            } else {
                HideStrategyImpl.show(wid, registry: registry, strategy: hideStrategy)
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
        logInfo("stage switched", ["to": stageID.value])
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
