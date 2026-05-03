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
    /// Déplace la wid du tree de son ancienne stage vers le tree de la nouvelle stage.
    public let reassignToStage: @MainActor (WindowID, StageID) -> Void
    /// Définit la stage active dans le LayoutEngine (change le tree utilisé par applyLayout).
    public let setActiveStage: @MainActor (StageID?) -> Void

    public init(setLeafVisible: @escaping @MainActor (WindowID, Bool) -> Void,
                applyLayout: @escaping @MainActor () -> Void,
                reassignToStage: @escaping @MainActor (WindowID, StageID) -> Void,
                setActiveStage: @escaping @MainActor (StageID?) -> Void) {
        self.setLeafVisible = setLeafVisible
        self.applyLayout = applyLayout
        self.reassignToStage = reassignToStage
        self.setActiveStage = setActiveStage
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

// MARK: - StageMode (SPEC-018)

/// Mode de stockage des stages : global (V1 flat, compat) ou per_display (V2 hiérarchique).
public enum StageMode: String, Sendable {
    case global
    case perDisplay = "per_display"
}

/// Filtre de portée pour `stages(in:)`.
public enum ScopeFilter: Sendable {
    case all
    case display(String)
    case displayDesktop(String, Int)
    case exact(StageScope)
}

/// SPEC-018 audit-cohérence F5 : clé d'un (display, desktop) sans stage. Permet
/// d'indexer le **stage actif par desktop** indépendamment des stages elles-mêmes
/// (qui sont déjà indexées par `StageScope = (display, desktop, stage)`).
public struct DesktopKey: Hashable, Sendable {
    public let displayUUID: String
    public let desktopID: Int

    public init(displayUUID: String, desktopID: Int) {
        self.displayUUID = displayUUID
        self.desktopID = desktopID
    }
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

    // MARK: SPEC-018 : persistence V2 + mode

    /// Persistence orientée scope (SPEC-018 Phase 2).
    /// Non nil si le daemon a appelé `setMode(_:persistence:)` au boot.
    private var persistenceV2: (any StagePersistenceV2)?

    /// Mode courant : global (défaut, compat V1) ou perDisplay (SPEC-018).
    private(set) public var stageMode: StageMode = .global

    /// Vue scopée des stages (SPEC-018). Synchronisée lors des chargements
    /// et mutations quand `persistenceV2` est actif.
    private(set) public var stagesV2: [StageScope: Stage] = [:]

    /// SPEC-018 audit-cohérence F5 : stage actif **par (display, desktop)**. Le
    /// scalaire `currentStageID` reste comme legacy/compat ; en mode `.perDisplay`
    /// il mirror la valeur de ce dict pour le `currentDesktopKey` actif. Sans ce dict,
    /// un aller-retour desktop 1→2→1 perdait la mémoire du stage en cours sur
    /// chaque desktop ; sur 2 displays il était impossible de retenir 2 stages
    /// actives simultanément.
    private(set) public var activeStageByDesktop: [DesktopKey: StageID] = [:]

    /// Scope desktop courant tel que vu par les call-sites (résolu via curseur ou
    /// frontmost par le daemon, qui appelle `setCurrentDesktopKey` à chaque
    /// transition). En mode `.global`, peut rester `nil` (legacy).
    private(set) public var currentDesktopKey: DesktopKey?

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

    // MARK: SPEC-018 API publique V2

    /// Configure le mode per_display (SPEC-018).
    /// Appelé par le daemon au boot selon `config.desktops.mode`.
    /// Invalide le cache en mémoire ; l'appelant doit appeler `loadFromDisk()` ensuite.
    public func setMode(_ mode: StageMode, persistence pv2: any StagePersistenceV2) {
        stageMode = mode
        persistenceV2 = pv2
        stagesV2.removeAll()
        activeStageByDesktop.removeAll()
        // SPEC-018 audit-cohérence F5/F6 : recharger depuis disque maintenant que la
        // persistence V2 est branchée. Sans ce reload, les stages V2 chargées au boot
        // (avant setMode) sont vides et activeStageByDesktop reste vide → on perd la
        // mémoire des stages persistées et le current-stage-par-desktop.
        loadFromPersistence()
    }

    // MARK: SPEC-018 audit-cohérence F5/F6 — stage actif par (display, desktop)

    /// Mis à jour par le daemon à chaque transition de scope (boot, desktop_changed,
    /// display_changed, ou résolution implicite via curseur). En mode `.perDisplay`,
    /// synchronise `currentStageID` (legacy scalaire) au stage actif du nouveau
    /// desktop **sans rien purger** des structures en mémoire — les autres desktops
    /// gardent leur état exactement.
    public func setCurrentDesktopKey(_ key: DesktopKey?) {
        currentDesktopKey = key
        guard stageMode == .perDisplay, let key = key else { return }
        // Sync `stages` V1 dict avec les stages V2 du SCOPE COURANT uniquement.
        // Sans ce sync, deactivateAll/activate (utilisés par DesktopSwitcher au
        // desktop_changed) itèrent sur stages V1 = état d'un autre (display, desktop)
        // → cachent/montrent les mauvaises wids → Grayjay reste visible alors qu'il
        // devrait être hidden (observé après desktop 1→2→1).
        stages.removeAll()
        for (scope, stage) in stagesV2
            where scope.displayUUID == key.displayUUID && scope.desktopID == key.desktopID {
            stages[scope.stageID] = stage
        }
        // Stage actif mémorisé pour ce (display, desktop) ; fallback "1" pour un
        // (display, desktop) jamais visité.
        let active = activeStageByDesktop[key] ?? StageID("1")
        // Update legacy scalaire pour que les call-sites V1 voient le bon stage.
        currentStageID = active
        // NE PAS appeler `layoutHooks?.setActiveStage(active)` ici. Ce hook itère sur
        // toutes les wids `state.stageID == active` SANS filtrer par desktop → en mode
        // multi-desktop, ça remontre les wids de TOUS les desktops avec ce stageID,
        // contredisant le deactivateAll qui vient de cacher tout. Le call-site approprié
        // (boot ou activate par DesktopSwitcher) appellera setActiveStage explicitement.
    }

    /// Stage actif pour un (display, desktop) donné. Retourne nil si jamais visité.
    public func activeStage(for key: DesktopKey) -> StageID? {
        activeStageByDesktop[key]
    }

    /// Charge depuis disque le stage actif de chaque (display, desktop) connu.
    /// Appelé après `loadFromPersistence` — peuple `activeStageByDesktop`.
    private func loadActiveStagesByDesktop() {
        guard stageMode == .perDisplay,
              let pv2 = persistenceV2 as? NestedStagePersistence else { return }
        // Toutes les paires (display, desktop) qui ont au moins une stage persistée.
        let knownDesktops = Set(stagesV2.keys.map {
            DesktopKey(displayUUID: $0.displayUUID, desktopID: $0.desktopID)
        })
        for key in knownDesktops {
            if let scope = pv2.loadActiveStage(forDisplay: key.displayUUID,
                                                desktop: key.desktopID) {
                activeStageByDesktop[key] = scope.stageID
            }
        }
    }

    /// Retourne les stages filtrés par scope (SPEC-018).
    /// En mode global, `ScopeFilter.all` retourne les mêmes stages que `stages.values`.
    public func stages(in filter: ScopeFilter) -> [Stage] {
        switch filter {
        case .all:
            return Array(stagesV2.values)
        case .display(let uuid):
            return stagesV2.compactMap { scope, stage in
                scope.displayUUID == uuid ? stage : nil
            }
        case .displayDesktop(let uuid, let desktopID):
            return stagesV2.compactMap { scope, stage in
                scope.displayUUID == uuid && scope.desktopID == desktopID ? stage : nil
            }
        case .exact(let target):
            return stagesV2[target].map { [$0] } ?? []
        }
    }

    /// Overload scopé de createStage (SPEC-018).
    /// Compat ascendante : `createStage(id:displayName:)` appelle cette méthode
    /// avec `.global(id)` quand persistenceV2 est nil.
    @discardableResult
    public func createStage(id: StageID, displayName: String, scope: StageScope) -> Stage {
        let stage = Stage(id: id, displayName: displayName)
        stagesV2[scope] = stage
        if let pv2 = persistenceV2 {
            try? pv2.save(stage, at: scope)
        }
        // En mode global, maintenir aussi le dict V1 pour compat.
        if scope.isGlobal || stageMode == .global {
            stages[id] = stage
            persistence.saveStage(stage)
        }
        return stage
    }

    /// Overload scopé de deleteStage (SPEC-018).
    public func deleteStage(scope: StageScope) {
        if scope.stageID.value == "1" { return }
        stagesV2.removeValue(forKey: scope)
        if let pv2 = persistenceV2 {
            try? pv2.delete(at: scope)
        }
        if scope.isGlobal || stageMode == .global {
            stages.removeValue(forKey: scope.stageID)
            persistence.deleteStage(scope.stageID)
            if currentStageID == scope.stageID { currentStageID = nil; saveActive() }
        }
    }

    /// Multi-desktop V2 (T030-T031) : bascule le scope du manager vers le desktop `id`.
    /// Délègue à `persistence.setDesktopID(_:)` qui est no-op en mode V1 (FileBackedStagePersistence)
    /// et met à jour l'ID courant en mode V2 (DesktopBackedStagePersistence).
    /// En mode V1, le swap de dossier physique est assuré par `reloadV1(stagesDir:)`.
    public func reload(forDesktop id: Int) {
        // Sauvegarder l'état du desktop quitté.
        flushCurrentFrames()
        persistence.saveActiveStage(currentStageID)
        // SPEC-018 audit-cohérence F6 : en mode V2, NE PAS purger stages/stagesV2 ni
        // reset currentStageID à nil. Toutes les stages des autres desktops sont
        // déjà chargées en mémoire dans stagesV2 et doivent y rester. Le legacy V1
        // dict est resync depuis stagesV2 par cohérence.
        if stageMode == .perDisplay {
            persistence.setDesktopID(id)
            if let base = baseConfigDir {
                self.stagesDir = ("\(base)/desktops/\(id)/stages" as NSString).expandingTildeInPath
            }
            // Le caller (main.swift) est responsable d'appeler `setCurrentDesktopKey`
            // après reload pour resynchroniser currentStageID au stage actif du
            // (display, desktop) entrant. Sans ce hook, on garde le stage du desktop
            // précédent — comportement de moindre surprise (l'app a juste switché
            // de desktop sans changer de stage de référence). Mieux : main.swift
            // appelle setCurrentDesktopKey en aval immédiat.
            return
        }
        // Mode V1 (legacy) : swap de dossier physique, donc purge nécessaire.
        stages.removeAll()
        currentStageID = nil
        persistence.setDesktopID(id)
        if let base = baseConfigDir {
            let newDir = ("\(base)/desktops/\(id)/stages" as NSString).expandingTildeInPath
            if persistence.requiresPhysicalDirSwap {
                self.stagesDir = newDir
                self.persistence = FileBackedStagePersistence(stagesDir: newDir)
            } else {
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

    /// SPEC-018 : réconcilie state.stageID ↔ stage.memberWindows dans les 2 sens.
    /// Sens 1 : pour chaque wid dans stage.memberWindows, set state.stageID = stage.id
    ///          (récupère l'assignation persistée que le scan AX a écrasée).
    /// Sens 2 : pour chaque wid du registry avec state.stageID = X, l'ajouter à
    ///          stage[X].memberWindows si elle n'y est pas déjà
    ///          (rattrape les fenêtres trackées au scan mais absentes du disque).
    public func reconcileStageOwnership() {
        var fixed1 = 0, fixed2 = 0
        // Sens 1 : memberWindows → state.stageID
        // Couvre V1 (stages) ET V2 (stagesV2 SPEC-018) — sinon les members persistés
        // au format per-display ne synchronisent jamais leur state.stageID après le
        // scan AX (qui écrase la valeur restaurée du disque).
        for (id, stage) in stages {
            for member in stage.memberWindows {
                let wid = member.cgWindowID
                guard let state = registry.get(wid) else { continue }
                if state.stageID != id {
                    registry.update(wid) { $0.stageID = id }
                    fixed1 += 1
                }
            }
        }
        for (scope, stage) in stagesV2 {
            for member in stage.memberWindows {
                let wid = member.cgWindowID
                guard let state = registry.get(wid) else { continue }
                if state.stageID != scope.stageID {
                    registry.update(wid) { $0.stageID = scope.stageID }
                    fixed1 += 1
                }
            }
        }
        // Sens 2 : registry → stage.memberWindows
        let defaultID = StageID("1")
        for state in registry.allWindows {
            // Skip helpers (utility/popup/tooltip <100×100). Sans ce skip, le fallback
            // `stageExists(defaultID)` ci-dessous force stage=1 sur tous les helpers et les
            // écrit dans memberWindows → ils repolluent le navrail à chaque appel à
            // windows.list (qui appelle reconcileStageOwnership en pré-amble).
            if state.isHelperWindow { continue }
            // Fall-back vers stage 1 si state.stageID pointe vers stage inexistante.
            // En mode per_display, "existe" = présence dans stagesV2 (n'importe quel
            // scope). En mode global, présence dans stages V1.
            let targetID: StageID
            let stageExists: (StageID) -> Bool = { [stagesV2, stages, stageMode] sid in
                if stageMode == .perDisplay {
                    return stagesV2.contains { $0.key.stageID == sid }
                } else {
                    return stages[sid] != nil
                }
            }
            if let sid = state.stageID, stageExists(sid) {
                targetID = sid
            } else if stageExists(defaultID) {
                targetID = defaultID
                registry.update(state.cgWindowID) { $0.stageID = defaultID }
            } else {
                continue
            }
            // SPEC-018 fix : en mode per_display, opérer DIRECTEMENT sur stagesV2
            // (pas via stages V1 qui peut être désynchronisé/vide). Sinon le sync
            // v1→v2 écrase le V2 file (avec ses members persistés) par le V1 stage
            // (potentiellement vide), résultat : V2 file vidé au reload.
            if stageMode == .perDisplay {
                guard let scope = stagesV2.keys.first(where: { $0.stageID == targetID }),
                      var stage = stagesV2[scope]
                else { continue }
                if !stage.memberWindows.contains(where: { $0.cgWindowID == state.cgWindowID }) {
                    stage.memberWindows.append(StageMember(
                        cgWindowID: state.cgWindowID,
                        bundleID: state.bundleID,
                        titleHint: state.title,
                        savedFrame: SavedRect(state.frame)))
                    stagesV2[scope] = stage
                    try? persistenceV2?.save(stage, at: scope)
                    fixed2 += 1
                }
            } else {
                guard var stage = stages[targetID] else { continue }
                let stageID = targetID
                if !stage.memberWindows.contains(where: { $0.cgWindowID == state.cgWindowID }) {
                    stage.memberWindows.append(StageMember(
                        cgWindowID: state.cgWindowID,
                        bundleID: state.bundleID,
                        titleHint: state.title,
                        savedFrame: SavedRect(state.frame)))
                    stages[stageID] = stage
                    saveStage(stage)
                    fixed2 += 1
                }
            }
        }
        if fixed1 + fixed2 > 0 {
            logInfo("reconcile_stage_ownership",
                    ["state_to_stage": String(fixed1), "stage_to_state": String(fixed2)])
        }
    }

    /// SPEC-018 : retire les wids orphelines (= pas dans le registry) de toutes les
    /// stages. À appeler au boot après scan AX initial pour éviter que des wids
    /// mortes des sessions précédentes restent référencées dans memberWindows.
    /// Aussi appelé sur handleWindowDestroyed pour nettoyer en continu.
    public func purgeOrphanWindows() {
        var purgedCount = 0
        // Critère : wid orpheline (absente du registry) OU helper (frame < seuil utile).
        // Cf. `WindowState.isHelperWindow` pour le rationnel. Un seul passage couvre les
        // deux pollutions persistées (wids mortes + utility windows).
        let shouldPurge: (WindowID) -> Bool = { [registry] wid in
            guard let state = registry.get(wid) else { return true }
            return state.isHelperWindow
        }
        // V1 dict
        for (id, stage) in stages {
            var s = stage
            let before = s.memberWindows.count
            s.memberWindows.removeAll { shouldPurge($0.cgWindowID) }
            let removed = before - s.memberWindows.count
            if removed > 0 {
                stages[id] = s
                saveStage(s)
                purgedCount += removed
            }
        }
        // V2 dict (SPEC-018)
        for (scope, stage) in stagesV2 {
            var s = stage
            let before = s.memberWindows.count
            s.memberWindows.removeAll { shouldPurge($0.cgWindowID) }
            let removed = before - s.memberWindows.count
            if removed > 0 {
                stagesV2[scope] = s
                try? persistenceV2?.save(s, at: scope)
                purgedCount += removed
            }
        }
        // Clear state.stageID des helpers : sinon `windows.list` continue à rapporter
        // `stage=1` pour ces wids et le navrail les ré-injecte au prochain refresh.
        var registryCleared = 0
        for state in registry.allWindows where state.isHelperWindow && state.stageID != nil {
            registry.update(state.cgWindowID) { $0.stageID = nil }
            registryCleared += 1
        }
        // SPEC-019 — purger les stages persistées de sessions précédentes qui sont
        // restées vides (ex: `roadie stage create 2 Personal` sans drag-drop ensuite).
        // Stage 1 est immortelle (cf. deleteStage). Cleanup défensif au boot uniquement.
        var emptyStagesPurged = 0
        for (scope, stage) in stagesV2
            where stage.memberWindows.isEmpty && scope.stageID.value != "1" {
            stagesV2.removeValue(forKey: scope)
            try? persistenceV2?.delete(at: scope)
            stages.removeValue(forKey: scope.stageID)
            emptyStagesPurged += 1
        }
        if purgedCount > 0 || registryCleared > 0 || emptyStagesPurged > 0 {
            logInfo("purge_orphan_windows",
                    ["members": String(purgedCount),
                     "registry_cleared": String(registryCleared),
                     "empty_stages": String(emptyStagesPurged)])
        }
    }

    private func loadFromPersistence() {
        let loaded = persistence.loadStages()
        stages.removeAll()
        for stage in loaded {
            stages[stage.id] = stage
        }
        currentStageID = persistence.loadActiveStage()
        // SPEC-018 : synchroniser stagesV2 si la persistence V2 est active.
        if let pv2 = persistenceV2,
           let all = try? pv2.loadAll() {
            stagesV2 = all
        } else if stageMode == .global {
            // Miroir en mode global : chaque stage V1 → scope .global.
            stagesV2 = Dictionary(uniqueKeysWithValues: stages.map { id, stage in
                (StageScope.global(id), stage)
            })
        }
        // SPEC-018 audit-cohérence F5 : peupler activeStageByDesktop depuis disque
        // après que stagesV2 soit chargé. Permet à `setCurrentDesktopKey` de retrouver
        // le bon stage actif au boot et après desktop_changed.
        loadActiveStagesByDesktop()
        logInfo("stages_loaded", [
            "count": String(stages.count),
            "current": currentStageID?.value ?? "nil",
            "active_by_desktop": String(activeStageByDesktop.count),
        ])
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
    /// SPEC-018 : en mode per_display, synchronise aussi stagesV2 pour tous les
    /// scopes qui partagent cet stageID (même ID, displays/desktops différents).
    @discardableResult
    public func renameStage(id: StageID, newName: String) -> Bool {
        guard var stage = stages[id] else { return false }
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        // FR-018 borne : 1..32 caractères.
        guard !trimmed.isEmpty, trimmed.count <= 32 else { return false }
        stage.displayName = trimmed
        stages[id] = stage
        saveStage(stage)
        // SPEC-018 : synchroniser stagesV2 si mode per_display.
        if stageMode == .perDisplay {
            for scope in stagesV2.keys where scope.stageID == id {
                stagesV2[scope] = stage
                try? persistenceV2?.save(stage, at: scope)
            }
        }
        return true
    }

    /// Garantit que le stage 1 par défaut existe et qu'un stage est actif.
    /// Appelé par bootstrap() après loadFromDisk() et après chaque reload(forDesktop:).
    public func ensureDefaultStage(scope: StageScope? = nil) {
        let defaultID = StageID("1")
        if stages[defaultID] == nil {
            _ = createStage(id: defaultID, displayName: "1")
        }
        // SPEC-018 : en mode per_display, garantir aussi la présence de la stage 1
        // dans stagesV2 au tuple courant pour que `stage 1`, `stage list` etc. la voient.
        if stageMode == .perDisplay, let scope = scope, stagesV2[scope] == nil {
            _ = createStage(id: scope.stageID, displayName: "1", scope: scope)
        }
        if currentStageID == nil {
            switchTo(stageID: defaultID)
        }
    }

    public func assign(wid: WindowID, to stageID: StageID) {
        guard let state = registry.get(wid) else { return }
        // Refus catégorique d'assigner un helper window (utility/popup/tooltip <100×100).
        // C'est la seule garantie en amont contre la pollution des stages : sans ce guard,
        // une fenêtre helper créée pendant la session se retrouve assignée au stage actif
        // puis persistée sur disque, et resurgit à chaque boot.
        guard !state.isHelperWindow else { return }
        // SPEC-018 audit-cohérence F11 : en mode per_display, déléguer à l'overload V2
        // pour que stagesV2 soit correctement nettoyé. Sans cette délégation, l'API V1
        // ne nettoie QUE le dict V1 → la wid se retrouve dans 2 entrées de stagesV2
        // simultanément (cf. observation : Grayjay 22089 dans 1.toml ET 2.toml).
        if stageMode == .perDisplay, let key = currentDesktopKey {
            let scope = StageScope(displayUUID: key.displayUUID,
                                   desktopID: key.desktopID, stageID: stageID)
            assign(wid: wid, to: scope)
            return
        }
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
        // Déplacer la wid dans le tree BSP de la nouvelle stage.
        layoutHooks?.reassignToStage(wid, stageID)
    }

    /// SPEC-018 : overload scope-aware. Écrit dans `stagesV2` au tuple complet
    /// `(displayUUID, desktopID, stageID)` et synchronise le dict V1 par compat.
    /// La wid est retirée de tout autre scope où elle figurerait.
    public func assign(wid: WindowID, to scope: StageScope) {
        guard let state = registry.get(wid) else { return }
        guard !state.isHelperWindow else { return }
        // Retirer la wid de tous les autres scopes V2.
        var emptiedScopes: [StageScope] = []
        for (s, stage) in stagesV2 where s != scope {
            var updated = stage
            updated.memberWindows.removeAll { $0.cgWindowID == wid }
            stagesV2[s] = updated
            if updated.memberWindows.isEmpty && s.stageID.value != "1" {
                emptiedScopes.append(s)
            } else {
                try? persistenceV2?.save(updated, at: s)
            }
        }
        for s in emptiedScopes {
            stagesV2.removeValue(forKey: s)
            try? persistenceV2?.delete(at: s)
        }
        // Ajouter au scope cible.
        guard var target = stagesV2[scope] else {
            logWarn("assign: unknown stage in scope", [
                "stage": scope.stageID.value,
                "display": scope.displayUUID,
                "desktop": String(scope.desktopID),
            ])
            return
        }
        if !target.memberWindows.contains(where: { $0.cgWindowID == wid }) {
            target.memberWindows.append(StageMember(
                cgWindowID: wid, bundleID: state.bundleID, titleHint: state.title,
                savedFrame: SavedRect(state.frame)))
        }
        target.lastActiveAt = Date()
        stagesV2[scope] = target
        try? persistenceV2?.save(target, at: scope)
        // Sync V1 dict pour que `switchTo(stageID:)` et autres APIs V1 trouvent la stage.
        stages[scope.stageID] = target
        persistence.saveStage(target)
        registry.update(wid) { $0.stageID = scope.stageID }
        // Déplacer la wid dans le tree BSP de la nouvelle stage (via scope.stageID).
        layoutHooks?.reassignToStage(wid, scope.stageID)
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
        layoutHooks?.setActiveStage(nil)
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
        layoutHooks?.setActiveStage(stageID)
        layoutHooks?.applyLayout()
        var updated = target
        updated.lastActiveAt = Date()
        stages[stageID] = updated
        currentStageID = stageID
        saveStage(updated)
        saveActive()
    }

    public func switchTo(stageID: StageID) {
        // SPEC-019 fix : en mode per_display, sync FULL stagesV2 → stages V1 dict
        // au début. Sans ce full sync, switchTo n'a pas de visibilité sur les wids
        // d'autres stages V2 (ex: stage 2 contenant Grayjay) → ne les hide pas →
        // elles restent visibles à l'écran malgré le switch.
        if stageMode == .perDisplay {
            for (scope, stage) in stagesV2 {
                stages[scope.stageID] = stage
            }
        }
        let targetStage: Stage
        if let s = stages[stageID] {
            targetStage = s
        } else {
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

        // Masquer les wids des autres stages.
        // SPEC-019 fix : en mode per_display, source de vérité = registry. Toute wid
        // dont state.stageID != stageID cible doit être hidée. Plus robuste que
        // d'itérer stages V1 dict (qui peut être désynchro après reassign cross-scope).
        let widsToHide: Set<WindowID>
        if stageMode == .perDisplay {
            widsToHide = Set(registry.allWindows
                .filter { $0.stageID != nil && $0.stageID != stageID }
                .map { $0.cgWindowID })
        } else {
            var s: Set<WindowID> = []
            for (id, stage) in stages where id != stageID {
                for member in stage.memberWindows { s.insert(member.cgWindowID) }
            }
            widsToHide = s
        }
        for wid in widsToHide {
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
        // Activer la stage dans le LayoutEngine AVANT applyLayout pour que le tiler
        // utilise le tree (stageID, displayID) correspondant à la nouvelle stage.
        layoutHooks?.setActiveStage(stageID)
        // Re-layout pour propager les changements de visibilité aux fenêtres tilées.
        layoutHooks?.applyLayout()

        target.lastActiveAt = Date()
        stages[stageID] = target
        currentStageID = stageID
        saveStage(target)
        saveActive()

        // SPEC-018 audit-cohérence F5 : mémoriser ce stage comme actif pour le
        // (display, desktop) courant. Persisté via _active.toml du scope. Permet
        // qu'un retour sur ce desktop restaure ce stage (au lieu de retomber sur "1").
        if stageMode == .perDisplay, let key = currentDesktopKey {
            activeStageByDesktop[key] = stageID
            let scope = StageScope(displayUUID: key.displayUUID,
                                   desktopID: key.desktopID, stageID: stageID)
            try? persistenceV2?.saveActiveStage(scope)
        }

        // Émission event V2 stage_changed (FR-015). desktop_id extrait du stagesDir
        // (.../desktops/<id>/stages → id). En mode V1, le path est .../stages → nil.
        // SPEC-019 fix : en mode per_display (V2), extractDesktopID retourne nil car
        // le stagesDir est plat. On retombe sur stagesV2 pour trouver le scope (desktop_id
        // + display_uuid) qui contient ce stageID — payload enrichi pour que le rail
        // puisse filtrer correctement par display+desktop.
        var desktopID = extractDesktopID(fromStagesDir: stagesDir)
        var displayUUID: String? = nil
        if stageMode == .perDisplay,
           let scope = stagesV2.first(where: { $0.key.stageID == stageID })?.key {
            desktopID = String(scope.desktopID)
            displayUUID = scope.displayUUID
        }
        var payload: [String: String] = [
            "to": stageID.value,
            "to_name": toName,
        ]
        if let did = desktopID {
            payload["desktop_id"] = did
        }
        if let uuid = displayUUID {
            payload["display_uuid"] = uuid
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
