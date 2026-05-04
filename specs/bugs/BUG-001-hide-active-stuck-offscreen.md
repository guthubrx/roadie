# BUG-001 — `stage.hide_active` : fenêtres restent offscreen après switch back

**Date** : 2026-05-04
**Sévérité** : MEDIUM (UX dégradée mais workaround utilisateur disponible)
**Composants** : `Sources/roadied/CommandRouter.swift` (`stage.hide_active`), `Sources/RoadieCore/HideStrategy.swift`, `Sources/RoadieTiler/LayoutEngine.swift`
**Introduit par** : commit 914b98e (`feat(rail): empty-click hide active stage — Apple Stage Manager pattern`)

## Symptôme

Après un click vide sur le rail (qui déclenche `stage.hide_active`), les fenêtres de la stage active sont déplacées offscreen via `HideStrategyImpl.hide()` (frame Y=-2117 typiquement). Quand l'utilisateur revient sur cette stage via `stage.switch` (CLI ou tap thumbnail rail), les fenêtres **restent à Y=-2117**. Elles n'apparaissent plus à l'écran malgré le switch.

Reproductible :

1. Avoir 2-3 fenêtres dans stage 2
2. Click vide sur le rail → toutes hidden via `HideStrategyImpl.hide(corner)`
3. `roadie stage 1` puis `roadie stage 2`
4. Observer : `roadie windows list` montre frame `-X,-2117` pour les fenêtres → toujours offscreen

Le rail compte ces fenêtres dans le thumbnail count (3 par exemple) alors que l'utilisateur ne les voit nulle part.

## Cause racine présumée (à confirmer)

`HideStrategyImpl.hide()` (Sources/RoadieCore/HideStrategy.swift:14) :

- Lit la frame courante via AX
- Si `isOnScreen(frame)` → sauvegarde dans `state.expectedFrame`
- Si `frame` déjà offscreen → ne touche PAS `expectedFrame` (commentaire "2nd BUGFIX")
- Puis `moveOffScreen(element)` → frame devient offscreen

`HideStrategyImpl.show()` (HideStrategy.swift:40) :

- `target = state.expectedFrame != .zero ? state.expectedFrame : state.frame`
- `setBounds(element, frame: target)`

**Cas pathologique** : si `expectedFrame == .zero` (jamais initialisée pour cette wid) ET `state.frame` est déjà offscreen → `target = state.frame = offscreen` → `setBounds` no-op → fenêtre reste offscreen.

Cause possible du cas pathologique :

1. Au boot, `loadFromDisk()` charge des stages avec `memberWindows` mais l'AX subscribe ne capte pas `frame` initiale → `state.frame` resté à `.zero` ou hérité d'une ancienne valeur offscreen.
2. `stage.hide_active` parcourt `memberWindows` et appelle `hide()` sur chacune. Pour une wid dont la frame courante est déjà offscreen (cas double-hide ou état incohérent), `expectedFrame` reste `.zero`.
3. Au prochain `show()`, fallback sur `state.frame` qui est offscreen → no-op.

## Tentative de fix échouée (cette session)

Ajout dans `stage.switch` après `sm.switchTo(...)` :

```swift
for wid in widsToShow {
    daemon.layoutEngine.setLeafVisible(wid, true)
    HideStrategyImpl.show(wid, registry: ..., strategy: ...)
}
daemon.applyLayout()
```

**Résultat** : pas d'effet observable. Les fenêtres restent à Y=-2117 même après que `applyLayout()` ait re-tilé. Le revert a été appliqué (le code n'est pas commité).

Hypothèses pour expliquer l'échec du fix :

A. `applyLayout()` est async (Task @MainActor avec coalescing `applyLayoutInFlight`). Mon `applyLayout()` a peut-être été coalescé avec le précédent qui était déjà en vol.
B. `applyAll` itère sur `displays` et applique le tree de la stage active du display. Mais ces fenêtres pourraient être membres d'une stage scope LG alors que le tree LG ne contient pas leur leaf (drift tree vs memberWindows).
C. `setLeafVisible(wid, true)` retourne `false` silencieusement (la wid n'est pas dans le tree) → pas de leaf à rendre visible → `applyAll` n'inclut pas la wid dans ses frames calculées.

## Workarounds utilisateur

1. **Fermer + rouvrir** les apps concernées : roadie les capte fraîches et les place via le tree.
2. **Drag-drop dans le rail** : `roadie stage assign <other_stage_id> --wid <wid>` puis re-assign à la stage active force un re-positioning (parfois suffit).
3. **`roadie daemon audit --fix`** : peut détecter et corriger via `windowDesktopReconciler` si `offscreen_with_active_scope` est implémenté pour ce cas (à vérifier).

## Investigation requise (SPEC dédiée)

À traiter dans une SPEC-025 (ou bug fix branch dédié) :

1. **Confirmer la cause** : ajouter logs dans `HideStrategyImpl.hide/show` pour tracer `expectedFrame` avant/après chaque appel sur les wids problématiques.
2. **Vérifier le tree** : `setLeafVisible(wid, true)` retourne-t-il `true` pour ces wids ? Si non, le tree n'a pas de leaf pour elles → comprendre pourquoi (membre de stage mais pas inséré dans tree ?).
3. **Stratégie de fix** :
   - Option A : dans `stage.hide_active`, n'autoriser le hide que si `state.expectedFrame` est valide (nouvelle frame) — sinon skip le hide pour cette wid.
   - Option B : dans `stage.switch`, recalculer la target frame depuis le tree slot (pas depuis expectedFrame) et forcer setBounds.
   - Option C : si `state.frame` est offscreen au moment du `show()`, fallback sur `displayManager.workArea.center` (= au centre du display, mieux que rien).
4. **Évaluer** : est-ce que `stage.hide_active` reste utile en l'état ? Si le bug est trop coûteux à fixer, considérer revert du commit 914b98e.

## Tests

À ajouter quand fix livré :

- `test_stage_hide_active_then_switch_back_restores_frames` : crée 2 fenêtres dans stage 1, hide_active, switch stage 2, switch stage 1 → frames doivent être visible (X≥0, Y≥0 sur primary display).
- `test_stage_hide_active_with_zero_expectedFrame` : cas où `expectedFrame == .zero` au moment du hide → le show suivant doit quand même placer la fenêtre dans l'écran (fallback workArea.center).
