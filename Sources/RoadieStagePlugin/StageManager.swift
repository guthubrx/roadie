import Foundation
import TOMLKit
import RoadieCore
import AppKit
import ApplicationServices

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
    /// SPEC-022 : displayUUID optionnel — si fourni, scope la mutation à ce display
    /// uniquement (mode perDisplay). Si nil, comportement legacy (apply à tous).
    public let setActiveStage: @MainActor (StageID?, String?) -> Void

    public init(setLeafVisible: @escaping @MainActor (WindowID, Bool) -> Void,
                applyLayout: @escaping @MainActor () -> Void,
                reassignToStage: @escaping @MainActor (WindowID, StageID) -> Void,
                setActiveStage: @escaping @MainActor (StageID?, String?) -> Void) {
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
    /// SPEC-022 T010 — computed property. En mode perDisplay avec currentDesktopKey non-nil,
    /// dérivée de `activeStageByDesktop[currentDesktopKey]`. En mode global (V1) ou si
    /// currentDesktopKey est nil, retombe sur `_currentStageIDV1` (compat backward).
    public var currentStageID: StageID? {
        get {
            if stageMode == .perDisplay {
                guard let key = currentDesktopKey else {
                    // T015 : cas pathologique — perDisplay mais key pas encore settée au boot.
                    logWarn("currentStageID_derived_nil", ["reason": "currentDesktopKey_not_set"])
                    return _currentStageIDV1
                }
                return activeStageByDesktop[key]
            }
            return _currentStageIDV1
        }
        set {
            if stageMode == .perDisplay, let key = currentDesktopKey {
                if let v = newValue { activeStageByDesktop[key] = v }
                else { activeStageByDesktop.removeValue(forKey: key) }
            } else {
                _currentStageIDV1 = newValue
            }
        }
    }

    /// Source V1 (mode global / currentDesktopKey nil). Ne pas accéder directement —
    /// passer par `currentStageID`. SPEC-022 : remplacé par activeStageByDesktop en mode perDisplay.
    private var _currentStageIDV1: StageID?
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

    // SPEC-021 : index inverse wid → scope (mode V2 perDisplay).
    // Mis à jour incrémentalement par assign/removeWindow/deleteStage.
    // Reconstruit au boot via rebuildWidToScopeIndex().
    private var widToScope: [WindowID: StageScope] = [:]
    /// SPEC-026 US4 — closure injectée par le daemon. Si retourne true, la wid
    /// est exemptée du hide cross-stage (sticky). Appelée depuis le main actor.
    public var shouldKeepWidStickyAcrossStages: ((WindowID) -> Bool)?
    // SPEC-021 : index inverse wid → stageID (mode V1 global).
    private var widToStageV1: [WindowID: StageID] = [:]

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
        // SPEC-025 FR-001 : valider les savedFrame chargés contre les displays
        // physiquement connectés. Toute frame dont le centre est hors écran
        // connu est invalidée (savedFrame = nil) → le tree calculera un slot
        // fresh au prochain applyLayout au lieu de restaurer aveuglément
        // une position offscreen persistée (cause racine BUG-001).
        let axDisplayFrames = Self.currentAXDisplayFrames()
        var totalInvalidated = 0
        for (id, var stage) in stages {
            let n = stage.validateMembers(againstDisplayFrames: axDisplayFrames)
            if n > 0 { stages[id] = stage; totalInvalidated += n }
        }
        for (scope, var stage) in stagesV2 {
            let n = stage.validateMembers(againstDisplayFrames: axDisplayFrames)
            if n > 0 { stagesV2[scope] = stage; totalInvalidated += n }
        }
        Self.lastValidationInvalidatedCount = totalInvalidated
        if totalInvalidated > 0 {
            logInfo("loadFromDisk_validated", [
                "invalidated_savedFrames": String(totalInvalidated),
                "displays_known": String(axDisplayFrames.count),
            ])
        }
    }

    /// Compteur public lu par le bootstrap pour BootStateHealth (FR-003).
    /// `@MainActor` pour cohérence avec le reste du StageManager (toutes les
    /// écritures viennent de loadFromDisk @MainActor, et toutes les lectures
    /// viennent de bootstrap / CommandRouter @MainActor). Évite la classe de
    /// data race théorique sur un static var non-isolated.
    @MainActor public static var lastValidationInvalidatedCount: Int = 0

    /// Nombre total de members across stagesV1 + stagesV2. Lu par le bootstrap
    /// pour BootStateHealth.totalWids et par les compteurs de zombies purgés.
    public func totalMemberCount() -> Int {
        var n = 0
        for (_, stage) in stages { n += stage.memberWindows.count }
        for (_, stage) in stagesV2 { n += stage.memberWindows.count }
        return n
    }

    /// Calcule les rects AX (origin top-left du primary) de tous les NSScreens
    /// connectés. Format aligné avec `WindowState.frame` (AX coords).
    private static func currentAXDisplayFrames() -> [CGRect] {
        let primary = NSScreen.screens.first(where: { $0.frame.origin == .zero })
            ?? NSScreen.main
            ?? NSScreen.screens.first
        let primaryHeight = primary?.frame.height ?? 0
        return NSScreen.screens.map { ns in
            // AX y = primaryHeight - ns.origin.y - ns.height
            CGRect(
                x: ns.frame.origin.x,
                y: primaryHeight - ns.frame.origin.y - ns.frame.height,
                width: ns.frame.width,
                height: ns.frame.height
            )
        }
    }

    /// SPEC-021 T028 : `reconcileStageOwnership` supprimée. Devenue sans objet :
    /// `widToScope` (resp. `widToStageV1`) est l'unique source de vérité — pas de
    /// double state à synchroniser. Le sens "memberWindows → state.stageID" disparaît
    /// (state.stageID est computed). Le sens "registry → memberWindows" pour les
    /// fenêtres scannées AX absentes du disque est désormais traité au boot par
    /// `purgeOrphanWindows` + auto-assign explicite côté daemon, plus juste.

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
            // SPEC-021 fix invariant I1 : capturer les wids supprimées pour
            // nettoyer aussi les index inverses (sinon widToStageV1 reste avec
            // des entrées orphelines pointant vers stages qui ne les contiennent
            // plus → drift observé).
            let purgedWids = s.memberWindows.filter { shouldPurge($0.cgWindowID) }.map { $0.cgWindowID }
            s.memberWindows.removeAll { shouldPurge($0.cgWindowID) }
            let removed = before - s.memberWindows.count
            if removed > 0 {
                stages[id] = s
                saveStage(s)
                purgedCount += removed
                for wid in purgedWids { widToStageV1.removeValue(forKey: wid) }
            }
        }
        // V2 dict (SPEC-018)
        for (scope, stage) in stagesV2 {
            var s = stage
            let before = s.memberWindows.count
            let purgedWids = s.memberWindows.filter { shouldPurge($0.cgWindowID) }.map { $0.cgWindowID }
            s.memberWindows.removeAll { shouldPurge($0.cgWindowID) }
            let removed = before - s.memberWindows.count
            if removed > 0 {
                stagesV2[scope] = s
                try? persistenceV2?.save(s, at: scope)
                purgedCount += removed
                for wid in purgedWids { widToScope.removeValue(forKey: wid) }
            }
        }
        // Clear state.stageID des helpers : sinon `windows.list` continue à rapporter
        // `stage=1` pour ces wids et le navrail les ré-injecte au prochain refresh.
        var registryCleared = 0
        // SPEC-021 : registry.update { $0.stageID = nil } supprimé (computed).
        // Les helpers n'apparaissent pas dans widToScope donc stageID retourne nil automatiquement.
        for state in registry.allWindows where state.isHelperWindow && state.stageID != nil {
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

    /// SPEC-022 T013 : en mode perDisplay, `active.toml` global est deprecated.
    /// La persistence per-(display, desktop) est gérée via `persistenceV2?.saveActiveStage(scope)`
    /// dans `switchTo` et `activate`. En mode V1 (global), délègue à V1 persistence.
    private func saveActive() {
        guard stageMode == .global else { return }
        persistence.saveActiveStage(_currentStageIDV1)
    }

    // MARK: - API publique

    // SPEC-021 — API publique index inverse

    /// Résout le scope complet (displayUUID, desktopID, stageID) d'une wid en O(1).
    /// Source unique de vérité pour le desktop-aware stage ownership (mode V2).
    public func scopeOf(wid: WindowID) -> StageScope? {
        widToScope[wid]
    }

    // stageIDOf(wid:) est déclaré dans l'extension StageManager: StageManagerProtocol
    // en bas du fichier (nonisolated, pour appel depuis WindowState.stageID computed).

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
        // SPEC-021 T017 : nettoyer l'index inverse pour toutes les wids du stage supprimé.
        if let stage = stages[id] {
            for member in stage.memberWindows {
                widToStageV1.removeValue(forKey: member.cgWindowID)
            }
        }
        for (scope, stage) in stagesV2 where scope.stageID == id {
            for member in stage.memberWindows {
                widToScope.removeValue(forKey: member.cgWindowID)
            }
        }
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
        // SPEC-021 fix invariant I1 (V1) : muter widToStageV1 SEULEMENT après que
        // l'append à memberWindows soit garanti. Avant ce fix, on mutait
        // widToStageV1 en premier, et si stages[stageID] n'existait pas, le
        // guard early-return laissait widToStageV1 orphelin.
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
        // Muter ici (après memberWindows peuplé) pour garantir l'invariant I1.
        widToStageV1[wid] = stageID
        // Déplacer la wid dans le tree BSP de la nouvelle stage.
        layoutHooks?.reassignToStage(wid, stageID)
    }

    /// SPEC-018 : overload scope-aware. Écrit dans `stagesV2` au tuple complet
    /// `(displayUUID, desktopID, stageID)` et synchronise le dict V1 par compat.
    /// La wid est retirée de tout autre scope où elle figurerait.
    public func assign(wid: WindowID, to scope: StageScope) {
        guard let state = registry.get(wid) else {
            logWarn("stage_assign_skipped", [
                "wid": String(wid), "reason": "wid_not_in_registry",
                "scope": "\(scope.displayUUID):\(scope.desktopID):\(scope.stageID.value)",
            ])
            return
        }
        guard !state.isHelperWindow else {
            logInfo("stage_assign_skipped", [
                "wid": String(wid), "reason": "helper_window",
                "frame": "\(Int(state.frame.width))x\(Int(state.frame.height))",
            ])
            return
        }
        let previousScope = widToScope[wid]
        logInfo("stage_assign", [
            "wid": String(wid),
            "from": previousScope.map { "\($0.displayUUID):\($0.desktopID):\($0.stageID.value)" } ?? "nil",
            "to": "\(scope.displayUUID):\(scope.desktopID):\(scope.stageID.value)",
            "bundle": state.bundleID,
        ])
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
        // SPEC-021 fix invariant I1 : muter widToScope SEULEMENT après que
        // l'append à memberWindows soit garanti. Avant ce fix, on mutait
        // widToScope en premier, et si stagesV2[scope] n'existait pas, le
        // guard early-return laissait widToScope orphelin → drift observé
        // par auditOwnership.
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
        // SPEC-021 : registry.update { $0.stageID = } supprimé (computed via
        // widToScope). Muter ici, après que memberWindows soit peuplé, garantit
        // l'invariant I1 (widToScope[wid] ⇒ wid ∈ memberWindows[scope]).
        widToScope[wid] = scope
        widToStageV1[wid] = scope.stageID  // sync pour compat lecture V1.
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
        layoutHooks?.setActiveStage(nil, currentDesktopKey?.displayUUID)
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
        layoutHooks?.setActiveStage(stageID, currentDesktopKey?.displayUUID)
        layoutHooks?.applyLayout()
        var updated = target
        updated.lastActiveAt = Date()
        stages[stageID] = updated
        currentStageID = stageID
        saveStage(updated)
        saveActive()
    }

    /// SPEC-022 — switchTo scopé. Si `scope` correspond au `currentDesktopKey` actuel,
    /// délègue à `switchTo(stageID:)` (comportement complet : hide/show, layout, global).
    /// Sinon : ne mute QUE `activeStageByDesktop[scope]` et persiste `_active.toml` du
    /// scope cible — pas d'effet sur le scope visible courant. C'est le fix multi-display
    /// du bug "click sur stage du panel display X → switch view de display Y".
    public func switchTo(stageID: StageID, scope: StageScope) {
        let targetKey = DesktopKey(displayUUID: scope.displayUUID, desktopID: scope.desktopID)
        // Cas A : le scope cible EST le scope visible courant → comportement legacy complet.
        if let cur = currentDesktopKey, cur == targetKey {
            switchTo(stageID: stageID)
            return
        }
        // Cas B : scope distant. Ne pas toucher au layout/hide/show de l'utilisateur courant.
        // Vérifier que la stage cible existe (lazy auto-create si non, cohérent avec stage.assign).
        let fullScope = StageScope(displayUUID: scope.displayUUID,
                                   desktopID: scope.desktopID, stageID: stageID)
        if stagesV2[fullScope] == nil {
            _ = createStage(id: stageID, displayName: "stage \(stageID.value)",
                            scope: fullScope)
        }
        // T022 — hide/show scope-aware : seules les wids du scope (displayUUID, desktopID)
        // cible sont affectées. Le scope courant de l'utilisateur n'est pas touché.
        // FR-006 : WindowState n'expose pas displayUUID → itérer stagesV2 du scope cible.
        var widsToHide: Set<WindowID> = []
        for (s, stage) in stagesV2 where s.displayUUID == scope.displayUUID
                                      && s.desktopID == scope.desktopID
                                      && s.stageID != stageID {
            for member in stage.memberWindows { widsToHide.insert(member.cgWindowID) }
        }
        // SPEC-026 US4 — exclure les sticky.
        if let isSticky = shouldKeepWidStickyAcrossStages {
            widsToHide = widsToHide.filter { !isSticky($0) }
        }
        for wid in widsToHide {
            let isTileable = registry.get(wid)?.isTileable ?? false
            if let override = hideOverride {
                override.hide(wid: wid, isTileable: isTileable)
            } else {
                HideStrategyImpl.hide(wid, registry: registry, strategy: hideStrategy)
            }
        }
        if let targetStage = stagesV2[fullScope] {
            for member in targetStage.memberWindows {
                let wid = member.cgWindowID
                let isTileable = registry.get(wid)?.isTileable ?? false
                if let override = hideOverride {
                    override.show(wid: wid, isTileable: isTileable)
                } else {
                    HideStrategyImpl.show(wid, registry: registry, strategy: hideStrategy)
                }
            }
        }
        // T023 : layoutHooks?.setActiveStage + applyLayout uniquement si scope courant.
        // Ici scope != currentDesktopKey (Cas B), donc pas d'appel layout.

        // Capturer l'ancienne active pour l'event "from" avant mutation.
        let previousActive = activeStageByDesktop[targetKey]
        // Mémoriser comme stage active du scope cible. Persiste _active.toml.
        activeStageByDesktop[targetKey] = stageID
        try? persistenceV2?.saveActiveStage(fullScope)
        logInfo("stage_switched_scoped", [
            "stage": stageID.value,
            "display_uuid": scope.displayUUID,
            "desktop_id": String(scope.desktopID),
            "current_visible_scope_unchanged": "true",
        ])
        // Émettre stage_changed enrichi pour que le rail panel du display cible
        // re-render et marque cette stage comme active dans son state local.
        // Pas de "from" : on ne sait pas quelle était l'active du scope distant
        // (c'est le rail qui maintient ce state local).
        var payload: [String: String] = [
            "to": stageID.value,
            "to_name": stagesV2[fullScope]?.displayName ?? stageID.value,
            "desktop_id": String(scope.desktopID),
            "display_uuid": scope.displayUUID,
        ]
        if let prev = previousActive, prev != stageID {
            payload["from"] = prev.value
        }
        EventBus.shared.publish(DesktopEvent(name: "stage_changed", payload: payload))
    }

    public func switchTo(stageID: StageID) {
        // SPEC-019 fix : en mode per_display, sync FULL stagesV2 → stages V1 dict
        // au début. Sans ce full sync, switchTo n'a pas de visibilité sur les wids
        // d'autres stages V2 (ex: stage 2 contenant Grayjay) → ne les hide pas →
        // elles restent visibles à l'écran malgré le switch.
        // SPEC-022 — sync V1 dict UNIQUEMENT depuis stagesV2 du SCOPE COURANT
        // (currentDesktopKey). Avant : sync depuis TOUS les scopes → collision sur
        // stageID, last write wins → V1 dict pouvait contenir le stage du mauvais
        // display. Conséquence : show des members du mauvais display + perte de
        // savedFrame du bon scope.
        if stageMode == .perDisplay, let key = currentDesktopKey {
            for (scope, stage) in stagesV2 where scope.displayUUID == key.displayUUID
                                              && scope.desktopID == key.desktopID {
                stages[scope.stageID] = stage
            }
        }
        // SPEC-022 — targetStage depuis stagesV2 du scope courant en perDisplay
        // pour ne pas dépendre de l'ordre d'iteration du dict V1.
        let targetStage: Stage
        if stageMode == .perDisplay, let key = currentDesktopKey {
            let scope = StageScope(displayUUID: key.displayUUID,
                                    desktopID: key.desktopID, stageID: stageID)
            guard let s = stagesV2[scope] else {
                logWarn("switch: unknown stage in current scope", [
                    "stage": stageID.value, "display": key.displayUUID,
                    "desktop": String(key.desktopID),
                ])
                return
            }
            targetStage = s
        } else {
            guard let s = stages[stageID] else {
                logWarn("switch: unknown stage", ["stage": stageID.value])
                return
            }
            targetStage = s
        }
        // Capturer le from + name pour l'event stage_changed (V2 FR-015).
        let fromID = currentStageID
        let fromName: String = {
            if stageMode == .perDisplay, let key = currentDesktopKey, let fid = fromID {
                let s = StageScope(displayUUID: key.displayUUID,
                                    desktopID: key.desktopID, stageID: fid)
                return stagesV2[s]?.displayName ?? ""
            }
            return fromID.flatMap { stages[$0]?.displayName } ?? ""
        }()
        let toName = targetStage.displayName

        // Capturer les frames actuelles des fenêtres du stage SORTANT pour restauration future.
        // SPEC-022 — récupérer depuis stagesV2 du scope courant en perDisplay.
        if let current = currentStageID {
            if stageMode == .perDisplay, let key = currentDesktopKey {
                let scope = StageScope(displayUUID: key.displayUUID,
                                        desktopID: key.desktopID, stageID: current)
                if var stage = stagesV2[scope] {
                    for i in 0..<stage.memberWindows.count {
                        let wid = stage.memberWindows[i].cgWindowID
                        if let element = registry.axElement(for: wid),
                           let frame = AXReader.bounds(element) {
                            stage.memberWindows[i].savedFrame = SavedRect(frame)
                        }
                    }
                    stagesV2[scope] = stage
                    stages[current] = stage  // sync V1 mirror
                    try? persistenceV2?.save(stage, at: scope)
                }
            } else if var stage = stages[current] {
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
        }

        // Masquer les wids des autres stages.
        // SPEC-022 fix critique : en mode per_display, restreindre le hide aux wids
        // du SCOPE COURANT (currentDesktopKey.displayUUID). Sans ça, switcher la stage
        // du display X hide aussi les windows des autres displays → "tout descend
        // sur le petit écran" (bug observé). Ownership wid→display dérivée de stagesV2
        // (un wid appartient à la stage qui le contient via memberWindows).
        var widsToHide: Set<WindowID>
        if stageMode == .perDisplay {
            var widDisplay: [WindowID: String] = [:]
            for (s, stage) in stagesV2 {
                for m in stage.memberWindows { widDisplay[m.cgWindowID] = s.displayUUID }
            }
            let curUUID = currentDesktopKey?.displayUUID ?? ""
            widsToHide = Set(registry.allWindows
                .filter { state in
                    state.stageID != nil
                        && state.stageID != stageID
                        && (widDisplay[state.cgWindowID] ?? "") == curUUID
                }
                .map { $0.cgWindowID })
        } else {
            var s: Set<WindowID> = []
            for (id, stage) in stages where id != stageID {
                for member in stage.memberWindows { s.insert(member.cgWindowID) }
            }
            widsToHide = s
        }
        // SPEC-026 US4 — exclure les sticky du hide cross-stage.
        if let isSticky = shouldKeepWidStickyAcrossStages {
            widsToHide = widsToHide.filter { !isSticky($0) }
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
        // SPEC-022 fix critique : en perDisplay, target depuis stagesV2 du SCOPE courant
        // (currentDesktopKey + stageID), PAS du V1 dict stages[stageID] qui collapse
        // les scopes (last write wins). Sans ça, on showait les members d'un autre
        // display → wids physiquement étrangères au scope local apparaissaient.
        var target: Stage
        if stageMode == .perDisplay, let key = currentDesktopKey {
            let scope = StageScope(displayUUID: key.displayUUID,
                                    desktopID: key.desktopID, stageID: stageID)
            guard let scoped = stagesV2[scope] else { return }
            target = scoped
        } else {
            guard let v1 = stages[stageID] else { return }
            target = v1
        }
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
        layoutHooks?.setActiveStage(stageID, currentDesktopKey?.displayUUID)
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

// SPEC-021 T013 — conformance au protocol du service locator (RoadieCore).
// `nonisolated` : le protocol n'est pas actor-isolated pour permettre l'appel
// depuis la computed property nonisolated de WindowState.
// Le daemon étant single-threaded sur MainActor, c'est sûr en pratique.
extension StageManager: StageManagerProtocol {
    nonisolated public func stageIDOf(wid: WindowID) -> StageID? {
        // Accès aux champs MainActor depuis nonisolated : assumeIsolated est la voie
        // correcte dans Swift 5.9+ pour les contextes où on sait être sur MainActor.
        MainActor.assumeIsolated {
            if stageMode == .perDisplay {
                return widToScope[wid]?.stageID
            }
            return widToStageV1[wid]
        }
    }
}

// SPEC-021 T014 — reconstruction de l'index inverse au boot.
extension StageManager {
    /// Reconstruit widToScope/widToStageV1 depuis memberWindows (source de vérité).
    /// À appeler après loadFromPersistence(). O(stages × members).
    /// SPEC-021 T068 (US4) — audit read-only des invariants de propriété.
    /// Vérifie 3 propriétés :
    ///   I1. Pour chaque entrée widToScope[wid] = scope, la wid figure dans
    ///       stagesV2[scope].memberWindows.
    ///   I2. Pour chaque (scope, stage) dans stagesV2, pour chaque member,
    ///       widToScope[member.cgWindowID] == scope.
    ///   I3. Pour chaque paire (s1, s2) avec s1 ≠ s2, l'intersection des
    ///       memberWindows est vide (une wid ne figure que dans un scope).
    /// Retourne la liste des violations (vide = sain). Read-only, pas de mutation.
    public func auditOwnership() -> [String] {
        var violations: [String] = []
        if stageMode == .perDisplay {
            // I1 : widToScope → memberWindows
            for (wid, scope) in widToScope {
                guard let stage = stagesV2[scope] else {
                    violations.append("widToScope[\(wid)] points to unknown scope \(scope.stageID.value)@\(scope.displayUUID)/\(scope.desktopID)")
                    continue
                }
                if !stage.memberWindows.contains(where: { $0.cgWindowID == wid }) {
                    violations.append("wid \(wid) in widToScope[\(scope.stageID.value)] but not in memberWindows")
                }
            }
            // I2 : memberWindows → widToScope
            for (scope, stage) in stagesV2 {
                for member in stage.memberWindows {
                    if widToScope[member.cgWindowID] != scope {
                        violations.append("wid \(member.cgWindowID) member of \(scope.stageID.value)@\(scope.displayUUID)/\(scope.desktopID) but widToScope says \(widToScope[member.cgWindowID]?.stageID.value ?? "nil")")
                    }
                }
            }
            // I3 : pas de wid dans 2 scopes simultanément
            let scopes = Array(stagesV2.keys)
            for i in 0..<scopes.count {
                for j in (i + 1)..<scopes.count {
                    let s1 = scopes[i], s2 = scopes[j]
                    let m1 = Set(stagesV2[s1]?.memberWindows.map { $0.cgWindowID } ?? [])
                    let m2 = Set(stagesV2[s2]?.memberWindows.map { $0.cgWindowID } ?? [])
                    let inter = m1.intersection(m2)
                    for wid in inter {
                        violations.append("wid \(wid) in 2 scopes : \(s1.stageID.value)@\(s1.displayUUID)/\(s1.desktopID) AND \(s2.stageID.value)@\(s2.displayUUID)/\(s2.desktopID)")
                    }
                }
            }
        } else {
            // V1 : équivalent simplifié sur stages
            for (wid, sid) in widToStageV1 {
                guard let stage = stages[sid] else {
                    violations.append("widToStageV1[\(wid)] points to unknown stage \(sid.value)")
                    continue
                }
                if !stage.memberWindows.contains(where: { $0.cgWindowID == wid }) {
                    violations.append("wid \(wid) in widToStageV1[\(sid.value)] but not in memberWindows")
                }
            }
            for (sid, stage) in stages {
                for member in stage.memberWindows {
                    if widToStageV1[member.cgWindowID] != sid {
                        violations.append("wid \(member.cgWindowID) member of stage \(sid.value) but widToStageV1 says \(widToStageV1[member.cgWindowID]?.value ?? "nil")")
                    }
                }
            }
        }
        return violations
    }

    public func rebuildWidToScopeIndex() {
        widToScope.removeAll(keepingCapacity: true)
        widToStageV1.removeAll(keepingCapacity: true)
        if stageMode == .perDisplay {
            for (scope, stage) in stagesV2 {
                for member in stage.memberWindows {
                    widToScope[member.cgWindowID] = scope
                }
            }
        } else {
            for (sid, stage) in stages {
                for member in stage.memberWindows {
                    widToStageV1[member.cgWindowID] = sid
                }
            }
        }
        logInfo("widToScope_index_rebuilt", [
            "v2_entries": String(widToScope.count),
            "v1_entries": String(widToStageV1.count),
        ])
    }

    // SPEC-021 T018 — retire une wid des index + memberWindows.
    public func removeWindow(_ wid: WindowID) {
        widToScope.removeValue(forKey: wid)
        widToStageV1.removeValue(forKey: wid)
        for (id, stage) in stages {
            var s = stage
            s.memberWindows.removeAll { $0.cgWindowID == wid }
            stages[id] = s
        }
        for (scope, stage) in stagesV2 {
            var s = stage
            s.memberWindows.removeAll { $0.cgWindowID == wid }
            stagesV2[scope] = s
        }
    }
}
