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
    /// Mirror auto-généré : projection de `stagesV2` sur le scope courant
    /// (currentDesktopKey). Mis à jour par `setCurrentDesktopKey`. Permet aux
    /// API non-scopées (createStage(id:displayName:), assign(wid:to:stageID),
    /// switchTo(stageID:), etc.) de continuer à fonctionner sur le scope visible.
    private(set) public var stages: [StageID: Stage] = [:]
    /// SPEC-022 — stage actif dérivé du dict `activeStageByDesktop[currentDesktopKey]`.
    /// Si `currentDesktopKey` est nil (boot pas encore terminé), fallback sur "1".
    public var currentStageID: StageID? {
        get {
            guard let key = currentDesktopKey else { return nil }
            return activeStageByDesktop[key]
        }
        set {
            guard let key = currentDesktopKey else { return }
            if let v = newValue { activeStageByDesktop[key] = v } else { activeStageByDesktop.removeValue(forKey: key) }
        }
    }

    private let layoutHooks: LayoutHooks?
    /// SPEC-006 : si non nil, override les hide/show via le module RoadieOpacity.
    public weak var hideOverride: StageHideOverride?

    /// Persistence scopée (V2). Source unique de vérité disque.
    private var persistenceV2: any StagePersistenceV2

    /// Vue scopée des stages — source unique de vérité en mémoire.
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

    /// Initialisation V2-only. La persistence (NestedStagePersistence par défaut)
    /// est l'unique source de vérité disque. `loadFromDisk()` doit être appelé
    /// par le caller après l'init pour peupler stagesV2.
    public init(registry: WindowRegistry, hideStrategy: HideStrategy = .corner,
                stagesDir: String = "~/.config/roadies/stages",
                baseConfigDir: String? = nil,
                persistenceV2: (any StagePersistenceV2)? = nil,
                layoutHooks: LayoutHooks? = nil) {
        self.registry = registry
        self.hideStrategy = hideStrategy
        self.layoutHooks = layoutHooks
        let expandedDir = (stagesDir as NSString).expandingTildeInPath
        self.stagesDir = expandedDir
        self.baseConfigDir = baseConfigDir.map { ($0 as NSString).expandingTildeInPath }
        self.persistenceV2 = persistenceV2 ?? NestedStagePersistence(stagesDir: expandedDir)
    }

    // MARK: API publique scopée

    /// Recharge depuis disque. À appeler par le caller après init.
    public func reloadFromPersistence() {
        stagesV2.removeAll()
        activeStageByDesktop.removeAll()
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
        guard let key = key else { stages.removeAll(); return }
        // Mirror `stages` depuis stagesV2 du SCOPE COURANT pour que les API non-scopées
        // (createStage(id:displayName:), assign(wid:to:stageID), switchTo(stageID:))
        // travaillent sur le scope visible.
        stages.removeAll()
        for (scope, stage) in stagesV2
            where scope.displayUUID == key.displayUUID && scope.desktopID == key.desktopID {
            stages[scope.stageID] = stage
        }
        // Stage actif mémorisé pour ce (display, desktop) ; fallback "1" pour un
        // (display, desktop) jamais visité.
        if activeStageByDesktop[key] == nil {
            activeStageByDesktop[key] = StageID("1")
        }
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
        guard let pv2 = persistenceV2 as? NestedStagePersistence else { return }
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

    /// Retourne les stages filtrés par scope (SPEC-018), triées par `order`
    /// croissant (SPEC-027 US3) puis par id alphanum à égalité (rétrocompat
    /// quand toutes les stages ont order=0).
    /// En mode global, `ScopeFilter.all` retourne les mêmes stages que `stages.values`.
    public func stages(in filter: ScopeFilter) -> [Stage] {
        let result: [Stage]
        switch filter {
        case .all:
            result = Array(stagesV2.values)
        case .display(let uuid):
            result = stagesV2.compactMap { scope, stage in
                scope.displayUUID == uuid ? stage : nil
            }
        case .displayDesktop(let uuid, let desktopID):
            result = stagesV2.compactMap { scope, stage in
                scope.displayUUID == uuid && scope.desktopID == desktopID ? stage : nil
            }
        case .exact(let target):
            result = stagesV2[target].map { [$0] } ?? []
        }
        return result.sorted { lhs, rhs in
            if lhs.order != rhs.order { return lhs.order < rhs.order }
            return lhs.id.value < rhs.id.value
        }
    }

    /// SPEC-027 US3 — réordonne les stages d'un scope donné : place `stageID`
    /// juste avant `targetID` dans le rail. Réécrit tous les `order` du scope
    /// avec un pas de 10 pour avoir de la marge pour des insertions futures
    /// sans avoir à tout réécrire à chaque fois (10, 20, 30, ...).
    /// Idempotent si stageID == targetID. No-op si l'un des deux n'existe pas
    /// dans le scope.
    @discardableResult
    public func reorderStage(_ stageID: StageID, before targetID: StageID,
                             in scope: StageScope) -> Bool {
        let scopeKey = DesktopKey(displayUUID: scope.displayUUID,
                                  desktopID: scope.desktopID)
        let scoped = stages(in: .displayDesktop(scopeKey.displayUUID, scopeKey.desktopID))
        guard scoped.contains(where: { $0.id == stageID }),
              scoped.contains(where: { $0.id == targetID }),
              stageID != targetID else { return false }
        // Construit la nouvelle liste : on retire stageID puis on l'insère
        // juste avant l'index courant de targetID.
        var ordered = scoped.filter { $0.id != stageID }
        guard let targetIdx = ordered.firstIndex(where: { $0.id == targetID }),
              let movingStage = scoped.first(where: { $0.id == stageID }) else { return false }
        ordered.insert(movingStage, at: targetIdx)
        // Réécrit les order avec un pas de 10.
        for (idx, stage) in ordered.enumerated() {
            let s = StageScope(displayUUID: scope.displayUUID,
                                desktopID: scope.desktopID,
                                stageID: stage.id)
            if var cur = stagesV2[s] {
                cur.order = (idx + 1) * 10
                stagesV2[s] = cur
                try? persistenceV2.save(cur, at: s)
            }
        }
        return true
    }

    /// Crée une stage au scope donné. Sync le dict mirror `stages` si le scope
    /// correspond au scope visible courant.
    @discardableResult
    public func createStage(id: StageID, displayName: String, scope: StageScope) -> Stage {
        let stage = Stage(id: id, displayName: displayName)
        stagesV2[scope] = stage
        try? persistenceV2.save(stage, at: scope)
        if let key = currentDesktopKey,
           scope.displayUUID == key.displayUUID && scope.desktopID == key.desktopID {
            stages[id] = stage
        }
        return stage
    }

    /// Supprime une stage au scope donné. Stage 1 immortelle.
    public func deleteStage(scope: StageScope) {
        if scope.stageID.value == "1" { return }
        stagesV2.removeValue(forKey: scope)
        try? persistenceV2.delete(at: scope)
        if let key = currentDesktopKey,
           scope.displayUUID == key.displayUUID && scope.desktopID == key.desktopID {
            stages.removeValue(forKey: scope.stageID)
            if currentStageID == scope.stageID { currentStageID = nil }
        }
    }

    /// Multi-desktop V2 : capture les frames du scope sortant. Le caller
    /// (main.swift) appelle ensuite `setCurrentDesktopKey` pour resynchroniser
    /// le mirror et le current-stage du nouveau scope. NE purge PAS stagesV2 :
    /// toutes les stages des autres desktops doivent rester en mémoire.
    public func reload(forDesktop id: Int) {
        flushCurrentFrames()
    }

    /// Capture les frames actuelles du stage actif avant toute transition.
    /// Sauve aussi dans `stagesV2` (source de vérité) si on connaît le scope.
    private func flushCurrentFrames() {
        guard let key = currentDesktopKey,
              let current = currentStageID else { return }
        let scope = StageScope(displayUUID: key.displayUUID,
                                desktopID: key.desktopID, stageID: current)
        guard var stage = stagesV2[scope] else { return }
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
            stagesV2[scope] = stage
            stages[current] = stage
            try? persistenceV2.save(stage, at: scope)
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
                "displays_known": String(axDisplayFrames.count)
            ])
        }
    }

    /// Compteur public lu par le bootstrap pour BootStateHealth (FR-003).
    /// `@MainActor` pour cohérence avec le reste du StageManager (toutes les
    /// écritures viennent de loadFromDisk @MainActor, et toutes les lectures
    /// viennent de bootstrap / CommandRouter @MainActor). Évite la classe de
    /// data race théorique sur un static var non-isolated.
    @MainActor public static var lastValidationInvalidatedCount: Int = 0

    /// Nombre total de members dans stagesV2. Lu par le bootstrap pour
    /// BootStateHealth.totalWids et par les compteurs de zombies purgés.
    public func totalMemberCount() -> Int {
        var n = 0
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
        for (scope, stage) in stagesV2 {
            var s = stage
            let before = s.memberWindows.count
            let purgedWids = s.memberWindows.filter { shouldPurge($0.cgWindowID) }.map { $0.cgWindowID }
            s.memberWindows.removeAll { shouldPurge($0.cgWindowID) }
            let removed = before - s.memberWindows.count
            if removed > 0 {
                stagesV2[scope] = s
                try? persistenceV2.save(s, at: scope)
                purgedCount += removed
                for wid in purgedWids { widToScope.removeValue(forKey: wid) }
            }
        }
        // Clear state.stageID des helpers : sinon `windows.list` continue à rapporter
        // `stage=1` pour ces wids et le navrail les ré-injecte au prochain refresh.
        var registryCleared = 0
        for state in registry.allWindows where state.isHelperWindow && state.stageID != nil {
            registryCleared += 1
        }
        // SPEC-019 — purger les stages persistées de sessions précédentes qui sont
        // restées vides. Stage 1 immortelle.
        var emptyStagesPurged = 0
        for (scope, stage) in stagesV2
            where stage.memberWindows.isEmpty && scope.stageID.value != "1" {
            stagesV2.removeValue(forKey: scope)
            try? persistenceV2.delete(at: scope)
            stages.removeValue(forKey: scope.stageID)
            emptyStagesPurged += 1
        }
        // Resync mirror du scope courant après les purges.
        if let key = currentDesktopKey {
            stages.removeAll()
            for (scope, stage) in stagesV2
                where scope.displayUUID == key.displayUUID && scope.desktopID == key.desktopID {
                stages[scope.stageID] = stage
            }
        }
        if purgedCount > 0 || registryCleared > 0 || emptyStagesPurged > 0 {
            logInfo("purge_orphan_windows",
                    ["members": String(purgedCount),
                     "registry_cleared": String(registryCleared),
                     "empty_stages": String(emptyStagesPurged)])
        }
    }

    private func loadFromPersistence() {
        if let all = try? persistenceV2.loadAll() {
            stagesV2 = all
        } else {
            stagesV2.removeAll()
        }
        // Resync mirror du scope courant si on en a un.
        stages.removeAll()
        if let key = currentDesktopKey {
            for (scope, stage) in stagesV2
                where scope.displayUUID == key.displayUUID && scope.desktopID == key.desktopID {
                stages[scope.stageID] = stage
            }
        }
        // Peupler activeStageByDesktop depuis disque (NestedStagePersistence._active.toml).
        loadActiveStagesByDesktop()
        logInfo("stages_loaded", [
            "count": String(stagesV2.count),
            "active_by_desktop": String(activeStageByDesktop.count)
        ])
    }

    public func saveStage(_ stage: Stage) {
        // V2-only : on a besoin du scope. Cherche dans stagesV2.
        guard let scope = stagesV2.first(where: { $0.value.id == stage.id })?.key else {
            return
        }
        try? persistenceV2.save(stage, at: scope)
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

    /// V2-only : créer une stage sans scope est ambigu — on utilise le scope
    /// courant. Si pas de currentDesktopKey, on échoue silencieusement (no-op).
    @discardableResult
    public func createStage(id: StageID, displayName: String) -> Stage {
        guard let key = currentDesktopKey else {
            return Stage(id: id, displayName: displayName)
        }
        let scope = StageScope(displayUUID: key.displayUUID,
                                desktopID: key.desktopID, stageID: id)
        return createStage(id: id, displayName: displayName, scope: scope)
    }

    /// V2-only : delete par stageID = delete dans le scope courant.
    public func deleteStage(id: StageID) {
        if id.value == "1" { return }
        guard let key = currentDesktopKey else { return }
        let scope = StageScope(displayUUID: key.displayUUID,
                                desktopID: key.desktopID, stageID: id)
        for member in stagesV2[scope]?.memberWindows ?? [] {
            widToScope.removeValue(forKey: member.cgWindowID)
        }
        deleteStage(scope: scope)
    }

    /// SPEC-014 T071 (US5) : renomme un stage. Le rename est cross-scope par
    /// design : tous les scopes qui partagent ce stageID se voient renommés.
    @discardableResult
    public func renameStage(id: StageID, newName: String) -> Bool {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 32 else { return false }
        var renamed = false
        for scope in stagesV2.keys where scope.stageID == id {
            guard var stage = stagesV2[scope] else { continue }
            stage.displayName = trimmed
            stagesV2[scope] = stage
            try? persistenceV2.save(stage, at: scope)
            if let key = currentDesktopKey,
               scope.displayUUID == key.displayUUID && scope.desktopID == key.desktopID {
                stages[id] = stage
            }
            renamed = true
        }
        return renamed
    }

    /// Garantit que le stage 1 par défaut existe et qu'un stage est actif.
    public func ensureDefaultStage(scope: StageScope? = nil) {
        let defaultID = StageID("1")
        if let scope = scope, stagesV2[scope] == nil {
            _ = createStage(id: scope.stageID, displayName: "1", scope: scope)
        } else if let key = currentDesktopKey {
            let s = StageScope(displayUUID: key.displayUUID,
                                desktopID: key.desktopID, stageID: defaultID)
            if stagesV2[s] == nil {
                _ = createStage(id: defaultID, displayName: "1", scope: s)
            }
        }
        if currentStageID == nil {
            switchTo(stageID: defaultID)
        }
    }

    /// V2-only : assign par stageID = assign dans le scope courant.
    public func assign(wid: WindowID, to stageID: StageID) {
        guard let state = registry.get(wid) else { return }
        guard !state.isHelperWindow else { return }
        guard let key = currentDesktopKey else { return }
        let scope = StageScope(displayUUID: key.displayUUID,
                                desktopID: key.desktopID, stageID: stageID)
        assign(wid: wid, to: scope)
    }

    /// SPEC-018 : overload scope-aware. Écrit dans `stagesV2` au tuple complet
    /// `(displayUUID, desktopID, stageID)` et synchronise le dict V1 par compat.
    /// La wid est retirée de tout autre scope où elle figurerait.
    public func assign(wid: WindowID, to scope: StageScope) {
        guard let state = registry.get(wid) else {
            logWarn("stage_assign_skipped", [
                "wid": String(wid), "reason": "wid_not_in_registry",
                "scope": "\(scope.displayUUID):\(scope.desktopID):\(scope.stageID.value)"
            ])
            return
        }
        guard !state.isHelperWindow else {
            logInfo("stage_assign_skipped", [
                "wid": String(wid), "reason": "helper_window",
                "frame": "\(Int(state.frame.width))x\(Int(state.frame.height))"
            ])
            return
        }
        let previousScope = widToScope[wid]
        logInfo("stage_assign", [
            "wid": String(wid),
            "src_display": String(previousScope?.displayUUID.prefix(8) ?? "nil"),
            "src_desktop": previousScope.map { String($0.desktopID) } ?? "nil",
            "src_stage": previousScope?.stageID.value ?? "nil",
            "dst_display": String(scope.displayUUID.prefix(8)),
            "dst_desktop": String(scope.desktopID),
            "dst_stage": scope.stageID.value,
            "bundle": state.bundleID
        ])
        // SPEC-028 — log de détection de duplication AVANT le retrait.
        // Liste tous les scopes où la wid figure déjà. Si > 1 → la duplication
        // est antérieure à cet assign (la wid était déjà dupliquée).
        let scopesContainingBefore: [StageScope] = stagesV2.compactMap { (s, stage) in
            stage.memberWindows.contains(where: { $0.cgWindowID == wid }) ? s : nil
        }
        if scopesContainingBefore.count > 1 {
            logWarn("assign_dupe_pre_existing", [
                "wid": String(wid),
                "scopes": scopesContainingBefore.map {
                    "\(String($0.displayUUID.prefix(8))):\($0.desktopID):\($0.stageID.value)"
                }.joined(separator: ","),
                "incoming_dst": "\(String(scope.displayUUID.prefix(8))):\(scope.desktopID):\(scope.stageID.value)"
            ])
        }
        // Retirer la wid de tous les autres scopes V2.
        var emptiedScopes: [StageScope] = []
        for (s, stage) in stagesV2 where s != scope {
            var updated = stage
            updated.memberWindows.removeAll { $0.cgWindowID == wid }
            stagesV2[s] = updated
            if updated.memberWindows.isEmpty && s.stageID.value != "1" {
                emptiedScopes.append(s)
            } else {
                try? persistenceV2.save(updated, at: s)
            }
        }
        for s in emptiedScopes {
            stagesV2.removeValue(forKey: s)
            try? persistenceV2.delete(at: s)
        }
        // SPEC-028 — log post-retrait : la wid devrait être dans 0 scope (puisqu'on
        // n'a pas encore add au scope cible) OU 1 seul (= cas re-assign même
        // scope, OK). Si dans plusieurs OU dans un scope ≠ cible, c'est un bug.
        let scopesContainingAfterRemove: [StageScope] = stagesV2.compactMap { (s, stage) in
            stage.memberWindows.contains(where: { $0.cgWindowID == wid }) ? s : nil
        }
        let leakScopes = scopesContainingAfterRemove.filter { $0 != scope }
        if !leakScopes.isEmpty {
            logWarn("assign_leak_after_removal", [
                "wid": String(wid),
                "leaked_in": leakScopes.map {
                    "\(String($0.displayUUID.prefix(8))):\($0.desktopID):\($0.stageID.value)"
                }.joined(separator: ","),
                "target_scope": "\(String(scope.displayUUID.prefix(8))):\(scope.desktopID):\(scope.stageID.value)"
            ])
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
                "desktop": String(scope.desktopID)
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
        try? persistenceV2.save(target, at: scope)
        // Sync mirror si scope visible courant.
        if let key = currentDesktopKey,
           scope.displayUUID == key.displayUUID && scope.desktopID == key.desktopID {
            stages[scope.stageID] = target
        }
        // SPEC-021 : muter widToScope APRÈS append à memberWindows (invariant I1).
        widToScope[wid] = scope
        // SPEC-028 — log final post-assign : la wid doit être dans EXACTEMENT
        // 1 scope (le scope cible). Si > 1 → duplication introduite ici.
        let scopesContainingAfter: [StageScope] = stagesV2.compactMap { (s, stage) in
            stage.memberWindows.contains(where: { $0.cgWindowID == wid }) ? s : nil
        }
        if scopesContainingAfter.count != 1 {
            logWarn("assign_dupe_post_append", [
                "wid": String(wid),
                "expected_scope": "\(String(scope.displayUUID.prefix(8))):\(scope.desktopID):\(scope.stageID.value)",
                "actual_scopes": scopesContainingAfter.map {
                    "\(String($0.displayUUID.prefix(8))):\($0.desktopID):\($0.stageID.value)"
                }.joined(separator: ","),
                "actual_count": String(scopesContainingAfter.count)
            ])
        }
        // Déplacer la wid dans le tree BSP de la nouvelle stage (via scope.stageID).
        layoutHooks?.reassignToStage(wid, scope.stageID)
    }

    // MARK: - API desktop (SPEC-011 refactor)

    /// Cache toutes les fenêtres du stage actif courant et met currentStageID à nil.
    /// Utilisé par DesktopSwitcher via DesktopStageOps pour la phase "quitter un desktop".
    /// Sans effet si aucun stage n'est actif.
    public func deactivateAll() {
        flushCurrentFrames()
        // Cacher les fenêtres de TOUS les stages du desktop courant (mirror).
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
        layoutHooks?.setActiveStage(nil, currentDesktopKey?.displayUUID)
        layoutHooks?.applyLayout()
    }

    /// Active le stage `stageID`. Affiche les fenêtres du stage cible.
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
        if let key = currentDesktopKey {
            let scope = StageScope(displayUUID: key.displayUUID,
                                    desktopID: key.desktopID, stageID: stageID)
            stagesV2[scope] = updated
            try? persistenceV2.save(updated, at: scope)
            try? persistenceV2.saveActiveStage(scope)
        }
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
        try? persistenceV2.saveActiveStage(fullScope)
        logInfo("stage_switched_scoped", [
            "stage": stageID.value,
            "display_uuid": scope.displayUUID,
            "desktop_id": String(scope.desktopID),
            "current_visible_scope_unchanged": "true"
        ])
        // Émettre stage_changed enrichi pour que le rail panel du display cible
        // re-render et marque cette stage comme active dans son state local.
        // Pas de "from" : on ne sait pas quelle était l'active du scope distant
        // (c'est le rail qui maintient ce state local).
        var payload: [String: String] = [
            "to": stageID.value,
            "to_name": stagesV2[fullScope]?.displayName ?? stageID.value,
            "desktop_id": String(scope.desktopID),
            "display_uuid": scope.displayUUID
        ]
        if let prev = previousActive, prev != stageID {
            payload["from"] = prev.value
        }
        EventBus.shared.publish(DesktopEvent(name: "stage_changed", payload: payload))
    }

    public func switchTo(stageID: StageID) {
        // V2-only : currentDesktopKey est la source de vérité du scope visible.
        guard let key = currentDesktopKey else {
            logWarn("switch: no currentDesktopKey", ["stage": stageID.value])
            return
        }
        // Resync mirror depuis stagesV2 du SCOPE COURANT.
        stages.removeAll()
        for (scope, stage) in stagesV2 where scope.displayUUID == key.displayUUID
                                          && scope.desktopID == key.desktopID {
            stages[scope.stageID] = stage
        }
        let scope = StageScope(displayUUID: key.displayUUID,
                                desktopID: key.desktopID, stageID: stageID)
        guard let targetStage = stagesV2[scope] else {
            logWarn("switch: unknown stage in current scope", [
                "stage": stageID.value, "display": key.displayUUID,
                "desktop": String(key.desktopID)
            ])
            return
        }
        // Capturer le from + name pour l'event stage_changed (V2 FR-015).
        let fromID = currentStageID
        let fromName: String = {
            guard let fid = fromID else { return "" }
            let s = StageScope(displayUUID: key.displayUUID,
                                desktopID: key.desktopID, stageID: fid)
            return stagesV2[s]?.displayName ?? ""
        }()
        let toName = targetStage.displayName

        // Capturer les frames actuelles du stage SORTANT.
        if let current = currentStageID {
            let outScope = StageScope(displayUUID: key.displayUUID,
                                      desktopID: key.desktopID, stageID: current)
            if var stage = stagesV2[outScope] {
                for i in 0..<stage.memberWindows.count {
                    let wid = stage.memberWindows[i].cgWindowID
                    if let element = registry.axElement(for: wid),
                       let frame = AXReader.bounds(element) {
                        stage.memberWindows[i].savedFrame = SavedRect(frame)
                    }
                }
                stagesV2[outScope] = stage
                stages[current] = stage
                try? persistenceV2.save(stage, at: outScope)
            }
        }

        // Masquer les wids des autres stages du SCOPE COURANT (display+desktop).
        var widDisplay: [WindowID: String] = [:]
        for (s, stage) in stagesV2 {
            for m in stage.memberWindows { widDisplay[m.cgWindowID] = s.displayUUID }
        }
        let curUUID = key.displayUUID
        var widsToHide = Set(registry.allWindows
            .filter { state in
                state.stageID != nil
                    && state.stageID != stageID
                    && (widDisplay[state.cgWindowID] ?? "") == curUUID
            }
            .map { $0.cgWindowID })
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

        // Montrer le stage cible.
        var target = targetStage
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
        layoutHooks?.setActiveStage(stageID, key.displayUUID)
        layoutHooks?.applyLayout()

        target.lastActiveAt = Date()
        stagesV2[scope] = target
        stages[stageID] = target
        try? persistenceV2.save(target, at: scope)
        // Mémoriser ce stage comme actif pour le (display, desktop) courant.
        activeStageByDesktop[key] = stageID
        currentStageID = stageID
        try? persistenceV2.saveActiveStage(scope)

        // Émission event stage_changed (FR-015).
        let desktopID: String? = String(scope.desktopID)
        let displayUUID: String? = scope.displayUUID
        var payload: [String: String] = [
            "to": stageID.value,
            "to_name": toName
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
        widToScope.removeValue(forKey: wid)
        var emptiedScopes: [StageScope] = []
        for (scope, stage) in stagesV2 {
            var s = stage
            let before = s.memberWindows.count
            s.memberWindows.removeAll { $0.cgWindowID == wid }
            if s.memberWindows.count != before {
                if s.memberWindows.isEmpty && scope.stageID.value != "1" {
                    emptiedScopes.append(scope)
                } else {
                    stagesV2[scope] = s
                    try? persistenceV2.save(s, at: scope)
                    if let key = currentDesktopKey,
                       scope.displayUUID == key.displayUUID && scope.desktopID == key.desktopID {
                        stages[scope.stageID] = s
                    }
                }
            }
        }
        // Lazy stages : auto-destroy si vidé par la destruction de fenêtre.
        for scope in emptiedScopes { deleteStage(scope: scope) }
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
            return widToScope[wid]?.stageID
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
        return violations
    }

    public func rebuildWidToScopeIndex() {
        widToScope.removeAll(keepingCapacity: true)
        // SPEC-028 — choix canonical DÉTERMINISTE en cas de duplication.
        // Si une wid figure dans plusieurs scopes, on choisit celui dont le
        // display correspond physiquement à la frame de la wid. Fallback
        // ordre alphabétique du UUID si pas de match physique.
        var widScopes: [WindowID: [StageScope]] = [:]
        for (scope, stage) in stagesV2 {
            for member in stage.memberWindows {
                widScopes[member.cgWindowID, default: []].append(scope)
            }
        }
        let displayFrames = Self.currentAXDisplayFramesByUUID()
        for (wid, scopes) in widScopes {
            let chosen: StageScope
            if scopes.count == 1 {
                chosen = scopes[0]
            } else if let state = registry.get(wid) {
                let center = CGPoint(x: state.frame.midX, y: state.frame.midY)
                let physical = scopes.first(where: { scope in
                    displayFrames[scope.displayUUID]?.contains(center) ?? false
                })
                chosen = physical
                    ?? scopes.sorted { $0.displayUUID < $1.displayUUID }.first!
            } else {
                chosen = scopes.sorted { $0.displayUUID < $1.displayUUID }.first!
            }
            widToScope[wid] = chosen
        }
        logInfo("widToScope_index_rebuilt", [
            "v2_entries": String(widToScope.count)
        ])
    }

    /// SPEC-028 — frames AX (origin top-left du primary) par display UUID.
    /// Utilisé par rebuildWidToScopeIndex pour résoudre le scope canonical
    /// d'une wid présente dans plusieurs scopes (état corrompu post-migration).
    private static func currentAXDisplayFramesByUUID() -> [String: CGRect] {
        var result: [String: CGRect] = [:]
        let primary = NSScreen.screens.first(where: { $0.frame.origin == .zero })
            ?? NSScreen.main
            ?? NSScreen.screens.first
        let primaryHeight = primary?.frame.height ?? 0
        for ns in NSScreen.screens {
            guard let cgID = ns.deviceDescription[
                NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID,
                  let cf = CGDisplayCreateUUIDFromDisplayID(cgID)?.takeRetainedValue(),
                  let uuid = CFUUIDCreateString(nil, cf) as String?
            else { continue }
            let axRect = CGRect(
                x: ns.frame.origin.x,
                y: primaryHeight - ns.frame.origin.y - ns.frame.height,
                width: ns.frame.width,
                height: ns.frame.height)
            result[uuid] = axRect
        }
        return result
    }

    // SPEC-021 T018 — retire une wid des index + memberWindows.
    public func removeWindow(_ wid: WindowID) {
        widToScope.removeValue(forKey: wid)
        for (scope, stage) in stagesV2 {
            var s = stage
            s.memberWindows.removeAll { $0.cgWindowID == wid }
            stagesV2[scope] = s
        }
        for (id, stage) in stages {
            var s = stage
            s.memberWindows.removeAll { $0.cgWindowID == wid }
            stages[id] = s
        }
    }
}
