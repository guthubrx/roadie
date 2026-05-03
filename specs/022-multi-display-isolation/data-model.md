# Data Model: Multi-Display Per-(Display, Desktop, Stage) Isolation

**Spec**: SPEC-022

## Vue d'ensemble

Aucun nouveau type. Refactor du **statut** d'un champ existant : `StageManager.currentStageID` passe de `stored property` à `computed property`. La source de vérité bascule vers `activeStageByDesktop[DesktopKey]`.

## Types touchés

### `StageManager` (Sources/RoadieStagePlugin/StageManager.swift)

#### Avant

```swift
public final class StageManager {
    private(set) public var currentStageID: StageID?  // STORED, source de vérité
    private var activeStageByDesktop: [DesktopKey: StageID] = [:]  // miroir/persistence
    private(set) public var currentDesktopKey: DesktopKey?
    // ...

    public func switchTo(stageID: StageID) {
        // mutation directe de currentStageID, hide/show all wids
        currentStageID = stageID
        // ...
    }
}
```

#### Après

```swift
public final class StageManager {
    /// COMPUTED. Dérivé de `activeStageByDesktop[currentDesktopKey]`.
    /// Setter: mutate `activeStageByDesktop[currentDesktopKey]` (preserve compat).
    public var currentStageID: StageID? {
        get {
            guard let key = currentDesktopKey else { return nil }
            return activeStageByDesktop[key]
        }
        set {
            guard let key = currentDesktopKey else { return }
            if let newValue { activeStageByDesktop[key] = newValue }
            else { activeStageByDesktop.removeValue(forKey: key) }
        }
    }

    private(set) var activeStageByDesktop: [DesktopKey: StageID] = [:]  // SOURCE DE VÉRITÉ
    private(set) public var currentDesktopKey: DesktopKey?

    // ...

    /// Wrapper compat — résout le scope depuis currentDesktopKey.
    public func switchTo(stageID: StageID) {
        guard let key = currentDesktopKey else {
            // Fallback global (mode .global) : ancien comportement
            switchToGlobal(stageID: stageID)
            return
        }
        let scope = StageScope(displayUUID: key.displayUUID,
                               desktopID: key.desktopID, stageID: stageID)
        switchTo(stageID: stageID, scope: scope)
    }

    /// NOUVELLE API. Mutation scopée : ne hide/show que les wids de ce scope.
    public func switchTo(stageID: StageID, scope: StageScope) {
        // 1. Update activeStageByDesktop pour ce scope
        let key = DesktopKey(displayUUID: scope.displayUUID, desktopID: scope.desktopID)
        activeStageByDesktop[key] = stageID

        // 2. Persist _active.toml de ce scope
        try? persistenceV2?.saveActiveStage(scope)

        // 3. Hide/show scoped : itère uniquement les wids du scope
        let widsToHide = registry.allWindows
            .filter { $0.displayUUID == scope.displayUUID
                   && $0.desktopID == scope.desktopID
                   && $0.stageID != stageID }
            .map { $0.cgWindowID }
        for wid in widsToHide {
            HideStrategyImpl.hide(wid, registry: registry, strategy: hideStrategy)
        }
        // Show wids du stage cible
        guard let stage = stagesV2[scope] else { return }
        for member in stage.memberWindows {
            HideStrategyImpl.show(member.cgWindowID, registry: registry, strategy: hideStrategy)
        }

        // 4. layoutHooks?.setActiveStage(stageID) + applyLayout
        // (uniquement si scope == currentDesktopKey, sinon pas d'impact visuel global)
        if key == currentDesktopKey {
            layoutHooks?.setActiveStage(stageID)
            layoutHooks?.applyLayout()
        }

        // 5. Émettre event stage_changed enrichi (display_uuid + desktop_id)
        // ...
    }
}
```

#### Champs/méthodes inchangés

- `stages`, `stagesV2` (data des stages elles-mêmes)
- `setCurrentDesktopKey` (déjà correct, maintient activeStageByDesktop)
- `ensureDefaultStage(scope:)` (déjà correct)
- `assign(wid:to:)` et l'overload scope (inchangés)

### `WindowState` (Sources/RoadieCore/Types.swift)

**Pas de changement**. Les champs `stageID`, `desktopID`, et `displayUUID` (resolved par DesktopRegistry) suffisent.

### `Stage` (model)

**Pas de changement**.

### `StageScope`

**Pas de changement**. Type déjà introduit par SPEC-018, structure `(displayUUID: String, desktopID: Int, stageID: StageID)`.

## Renderers (Sources/RoadieRail/Renderers/)

Pour chaque renderer, le pattern actuel :

```swift
@ViewBuilder
private var content: some View {
    if stage.windowIDs.isEmpty {
        emptyPlaceholder  // ← rend "Empty stage" + icône
    } else {
        actualContent
    }
}
```

devient :

```swift
@ViewBuilder
private var content: some View {
    if stage.windowIDs.isEmpty {
        EmptyView()  // ← rien rendu, cellule conserve sa zone d'interaction
    } else {
        actualContent
    }
}
```

`emptyPlaceholder` peut être conservé en private dead code avec un `// SPEC-022 : not rendered, kept for potential debug mode`.

## Persistence

### Avant

- `~/.config/roadies/stages/active.toml` : `current_stage = "X"` (scalaire global)
- `~/.config/roadies/stages/<UUID>/<desktopID>/_active.toml` : `current_stage = "Y"` (per-(display, desktop), introduit SPEC-018)

### Après

- `active.toml` (global) : **deprecated, ignoré silencieusement**. Pas de suppression (defensive — au cas où un downgrade aurait besoin).
- `_active.toml` per-(display, desktop) : **source de vérité**. Format inchangé.

**Migration** : aucune. Le boot lit `_active.toml` comme avant via `loadActiveStagesByDesktop()`.

## Invariants

- **INV-1** : pour chaque (display, desktop) qui a au moins une stage en data, `activeStageByDesktop[(display, desktop)]` est non-nil. Garanti par `ensureDefaultStage` au boot et après chaque desktop_changed.
- **INV-2** : `currentDesktopKey` est non-nil dès que `bootstrap()` a tourné. Maintenu par `setCurrentDesktopKey` aux moments clé (boot, reload, desktop_changed).
- **INV-3** : pour toute window tilée, `windowState.stageID == activeStageByDesktop[(window.displayUUID, window.desktopID)]` ssi la window est on-screen. Si différent, la window est hidée par HideStrategy.
