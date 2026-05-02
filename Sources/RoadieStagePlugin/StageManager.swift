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

    /// Source de vérité pour la persistance. Injecté à l'init ou substitué via
    /// `setPersistence(_:)` après création (mode V2, quand DesktopRegistry est disponible).
    /// Mode V1 (défaut) : FileBackedStagePersistence.
    /// Mode V2 multi-desktop : DesktopBackedStagePersistence (injecté par le daemon).
    private var persistence: any StagePersistence

    /// Dossier de persistance courant. Conservé pour `extractDesktopID` (mode V1).
    /// En mode V2 ce champ est ignoré pour la lecture/écriture (le persistence s'en charge).
    private(set) public var stagesDir: String

    /// Répertoire de base config (~/.config/roadies). Utilisé par reload(forDesktop:)
    /// pour construire le path `desktops/<id>/stages` en mode V1 fallback.
    private let baseConfigDir: String?

    /// T048 (SPEC-011 US5) : callback optionnel appelé après chaque bascule de stage.
    /// Le daemon l'utilise pour relayer l'event vers DesktopEventBus sans créer de
    /// dépendance RoadieDesktops → RoadieStagePlugin.
    /// Signature : (desktopID: String, fromStageID: String, toStageID: String) -> Void
    public var onStageChanged: (@MainActor (String, String, String) -> Void)?

    /// Initialisation mode V1 (fallback fichiers stages/*.toml).
    /// Conservé pour la compatibilité descendante et les tests existants.
    public init(registry: WindowRegistry, hideStrategy: HideStrategy = .corner,
                stagesDir: String = "~/.config/roadies/stages",
                baseConfigDir: String? = nil,
                layoutHooks: LayoutHooks? = nil) {
        self.registry = registry
        self.hideStrategy = hideStrategy
        self.layoutHooks = layoutHooks
        let expandedDir = (stagesDir as NSString).expandingTildeInPath
        self.stagesDir = expandedDir
        self.baseConfigDir = baseConfigDir.map { ($0 as NSString).expandingTildeInPath }
        self.persistence = FileBackedStagePersistence(stagesDir: expandedDir)
    }

    /// Initialisation mode V2 : source de vérité = DesktopRegistry via `persistence`.
    /// Le `stagesDir` passé sert uniquement à `extractDesktopID` pour les events.
    public init(registry: WindowRegistry, hideStrategy: HideStrategy = .corner,
                stagesDir: String = "~/.config/roadies/stages",
                baseConfigDir: String? = nil,
                persistence: any StagePersistence,
                layoutHooks: LayoutHooks? = nil) {
        self.registry = registry
        self.hideStrategy = hideStrategy
        self.layoutHooks = layoutHooks
        self.stagesDir = (stagesDir as NSString).expandingTildeInPath
        self.baseConfigDir = baseConfigDir.map { ($0 as NSString).expandingTildeInPath }
        self.persistence = persistence
    }

    /// Substitue la persistence après création (injection différée, mode V2).
    /// Appelé par le daemon après l'init du DesktopRegistry, avant le premier
    /// `reload(forDesktop:)`. Invalide le cache en mémoire des stages.
    public func setPersistence(_ newPersistence: any StagePersistence) {
        persistence = newPersistence
        stages.removeAll()
        currentStageID = nil
    }

    /// Multi-desktop V2 (T030-T031) : bascule le scope du manager vers le desktop `id`.
    /// Délègue à `persistence.setDesktopID(_:)` qui est no-op en mode V1 (FileBackedStagePersistence)
    /// et met à jour l'ID courant en mode V2 (DesktopBackedStagePersistence).
    /// En mode V1, le swap de dossier physique est assuré par `reloadV1(stagesDir:)`.
    public func reload(forDesktop id: Int) {
        // Sauvegarder l'état du desktop quitté.
        flushCurrentFrames()
        persistence.saveActiveStage(currentStageID)
        stages.removeAll()
        currentStageID = nil
        // Notifier la persistence du nouvel ID (no-op V1, essentiel V2).
        persistence.setDesktopID(id)
        if let base = baseConfigDir {
            let newDir = ("\(base)/desktops/\(id)/stages" as NSString).expandingTildeInPath
            if persistence.requiresPhysicalDirSwap {
                // Mode V1 : créer une nouvelle FileBackedStagePersistence pour le nouveau
                // dossier. La persistence V1 ne supporte pas le hot-swap de dossier — elle
                // lit toujours depuis le path donné à l'init.
                self.stagesDir = newDir
                self.persistence = FileBackedStagePersistence(stagesDir: newDir)
            } else {
                // Mode V2 : mettre à jour uniquement pour extractDesktopID (events).
                self.stagesDir = newDir
            }
        }
        loadFromPersistence()
    }

    /// V1 uniquement : swap atomique du dossier de persistance.
    /// Utilisé en interne et dans les tests de scope qui testent le comportement V1.
    public func reload(stagesDir newDir: String) {
        reloadV1(stagesDir: newDir)
    }

    private func reloadV1(stagesDir newDir: String) {
        flushCurrentFrames()
        persistence.saveActiveStage(currentStageID)

        stages.removeAll()
        currentStageID = nil
        let expanded = (newDir as NSString).expandingTildeInPath
        self.stagesDir = expanded
        try? FileManager.default.createDirectory(atPath: expanded, withIntermediateDirectories: true)

        loadFromPersistence()
    }

    /// Capture les frames actuelles du stage actif avant toute transition.
    private func flushCurrentFrames() {
        guard let current = currentStageID, var stage = stages[current] else { return }
        var changed = false
        for i in 0..<stage.memberWindows.count {
            let wid = stage.memberWindows[i].cgWindowID
            if let element = registry.axElement(for: wid),
               let frame = AXReader.bounds(element) {
                stage.memberWindows[i].savedFrame = SavedRect(frame)
                changed = true
            }
        }
        if changed {
            stages[current] = stage
            persistence.saveStage(stage)
        }
    }

    public func loadFromDisk() {
        loadFromPersistence()
    }

    private func loadFromPersistence() {
        let loaded = persistence.loadStages()
        stages.removeAll()
        for stage in loaded {
            stages[stage.id] = stage
        }
        currentStageID = persistence.loadActiveStage()
        logInfo("stages loaded", ["count": String(stages.count), "current": currentStageID?.value ?? "nil"])
    }

    public func saveStage(_ stage: Stage) {
        persistence.saveStage(stage)
    }

    private func saveActive() {
        persistence.saveActiveStage(currentStageID)
    }

    // MARK: - API publique

    public func createStage(id: StageID, displayName: String) -> Stage {
        let stage = Stage(id: id, displayName: displayName)
        stages[id] = stage
        saveStage(stage)
        return stage
    }

    public func deleteStage(id: StageID) {
        // Stage 1 immortel : stage par défaut de chaque desktop, jamais détruit.
        // L'auto-destroy on-empty (assign / handleWindowDestroyed) saute ce cas.
        if id.value == "1" { return }
        stages.removeValue(forKey: id)
        persistence.deleteStage(id)
        if currentStageID == id { currentStageID = nil; saveActive() }
    }

    /// SPEC-014 T071 (US5) : renomme un stage. Persiste sur disque et notifie.
    /// Le caller (CommandRouter) émet l'event `stage_renamed` après succès.
    @discardableResult
    public func renameStage(id: StageID, newName: String) -> Bool {
        guard var stage = stages[id] else { return false }
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        // FR-018 borne : 1..32 caractères.
        guard !trimmed.isEmpty, trimmed.count <= 32 else { return false }
        stage.displayName = trimmed
        stages[id] = stage
        saveStage(stage)
        return true
    }

    /// Garantit que le stage 1 par défaut existe et qu'un stage est actif.
    /// Appelé par bootstrap() après loadFromDisk() et après chaque reload(forDesktop:).
    public func ensureDefaultStage() {
        let defaultID = StageID("1")
        if stages[defaultID] == nil {
            _ = createStage(id: defaultID, displayName: "1")
        }
        if currentStageID == nil {
            switchTo(stageID: defaultID)
        }
    }

    public func assign(wid: WindowID, to stageID: StageID) {
        guard let state = registry.get(wid) else { return }
        // Retirer de tout autre stage. Lazy stages : un stage qui devient vide
        // suite à ce retrait est auto-détruit (UX "le stage existe par son contenu").
        var emptied: [StageID] = []
        for (id, stage) in stages where id != stageID {
            var s = stage
            s.memberWindows.removeAll { $0.cgWindowID == wid }
            stages[id] = s
            if s.memberWindows.isEmpty {
                emptied.append(id)
            } else {
                saveStage(s)
            }
        }
        for id in emptied { deleteStage(id: id) }
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

    // MARK: - API desktop (SPEC-011 refactor)

    /// Cache toutes les fenêtres du stage actif courant et met currentStageID à nil.
    /// Utilisé par DesktopSwitcher via DesktopStageOps pour la phase "quitter un desktop".
    /// Sans effet si aucun stage n'est actif.
    public func deactivateAll() {
        // Capturer les frames du stage actif pour restauration future.
        if let current = currentStageID, var updated = stages[current] {
            for i in 0..<updated.memberWindows.count {
                let wid = updated.memberWindows[i].cgWindowID
                if let element = registry.axElement(for: wid),
                   let frame = AXReader.bounds(element) {
                    updated.memberWindows[i].savedFrame = SavedRect(frame)
                }
            }
            stages[current] = updated
            saveStage(updated)
        }
        // Cacher les fenêtres de TOUS les stages du desktop courant (pas seulement
        // le stage actif). Sans ça, une fenêtre assignée à un stage non-actif
        // resterait visible après bascule de desktop, créant l'illusion d'un
        // "stage qui suit" l'utilisateur entre desktops.
        var seenWids: Set<WindowID> = []
        for stage in stages.values {
            for member in stage.memberWindows {
                let wid = member.cgWindowID
                guard seenWids.insert(wid).inserted else { continue }
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
        currentStageID = nil
        saveActive()
        layoutHooks?.applyLayout()
    }

    /// Active le stage `stageID` en supposant qu'aucun stage n'est actuellement actif
    /// (currentStageID == nil). Affiche les fenêtres du stage cible.
    /// Utilisé par DesktopSwitcher via DesktopStageOps pour la phase "entrer dans un desktop".
    public func activate(stageID: StageID) {
        guard let target = stages[stageID] else {
            logWarn("activate: unknown stage", ["stage": stageID.value])
            return
        }
        for member in target.memberWindows {
            let wid = member.cgWindowID
            let isTileable = registry.get(wid)?.isTileable ?? false
            if isTileable, let hooks = layoutHooks {
                hooks.setLeafVisible(wid, true)
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
        layoutHooks?.applyLayout()
        var updated = target
        updated.lastActiveAt = Date()
        stages[stageID] = updated
        currentStageID = stageID
        saveStage(updated)
        saveActive()
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

        // Émission event V2 stage_changed (FR-015). desktop_id extrait du stagesDir
        // (.../desktops/<id>/stages → id). En mode V1, le path est .../stages → nil
        // (M5) et l'event est quand même publié pour les subscribers (filtrable côté client).
        let desktopID = extractDesktopID(fromStagesDir: stagesDir)
        var payload: [String: String] = [
            "to": stageID.value,
            "to_name": toName,
        ]
        if let did = desktopID {
            payload["desktop_id"] = did
        }
        if let from = fromID {
            payload["from"] = from.value
            payload["from_name"] = fromName
        }
        EventBus.shared.publish(DesktopEvent(name: "stage_changed", payload: payload))

        // T048 : notifier DesktopEventBus via closure (pas de dépendance directe)
        let fromStr = fromID?.value ?? ""
        onStageChanged?(desktopID ?? "", fromStr, stageID.value)

        logInfo("stage switched", ["to": stageID.value])
    }

    /// Extrait l'ID du desktop depuis le path `.../desktops/<id>/stages`.
    /// M5 : retourne nil (et non "") si le path est `.../stages` (mode V1) ou inattendu.
    /// Les appelants doivent traiter nil comme "desktop inconnu / mode V1".
    private func extractDesktopID(fromStagesDir dir: String) -> String? {
        let parts = dir.split(separator: "/").map(String.init)
        guard parts.count >= 2,
              parts.last == "stages",
              let desktopIdx = parts.firstIndex(of: "desktops"),
              parts.indices.contains(desktopIdx + 1) else { return nil }
        return parts[desktopIdx + 1]
    }

    public func handleWindowDestroyed(_ wid: WindowID) {
        var emptied: [StageID] = []
        for (id, stage) in stages {
            var s = stage
            let before = s.memberWindows.count
            s.memberWindows.removeAll { $0.cgWindowID == wid }
            if s.memberWindows.count != before {
                if s.memberWindows.isEmpty {
                    emptied.append(id)
                } else {
                    stages[id] = s
                    saveStage(s)
                }
            }
        }
        // Lazy stages : auto-destroy si vidé par la destruction de fenêtre.
        for id in emptied { deleteStage(id: id) }
    }
}
