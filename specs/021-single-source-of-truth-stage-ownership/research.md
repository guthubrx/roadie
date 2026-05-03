# Research: Single Source of Truth — Stage/Desktop Ownership

**Spec**: SPEC-021 | **Created**: 2026-05-03

## Pourquoi ce research

Avant de tuer un mécanisme de cache, il faut être certain qu'il ne servait à rien. Et avant d'introduire un nouvel appel SLS privé, il faut valider que c'est stable, sans SIP off, et performant. Cette research adresse les 2 questions.

## Pattern AeroSpace — source unique via arête arbre

**Source** : `~/11.Repositories/aerospace/Sources/AppBundle/tree/{TreeNode.swift, TreeNodeEx.swift, MacWindow.swift}`

```swift
// TreeNode.swift
fileprivate final weak var _parent: NonLeafTreeNodeObject? = nil
final var parent: NonLeafTreeNodeObject? { _parent }

// TreeNodeEx.swift:28
var nodeWorkspace: Workspace? {
    self as? Workspace ?? parent?.nodeWorkspace
}
```

**Décision** : chaque fenêtre a UN seul `parent` (référence faible). Pour connaître son workspace, on remonte les parents. Source unique = arête de l'arbre. Drift impossible par construction.

**Adaptation à roadie** : on n'a pas d'arbre généralisé (BSP est local au tiling, pas global). Mais la logique « un seul stockage de membership » s'applique : `Stage.memberWindows` est l'arête, et `WindowState.stageID` était le doublon à tuer.

**Performance** : remonter les parents = O(depth). Avec arbre BSP roadie typique de 4-8 leaves par stage, depth max ~5. Pour roadie, `widToScope[wid]` lookup = O(1) amorti via Dictionary, encore plus simple.

**Limite identifiée** : AeroSpace n'utilise PAS les desktops macOS (workspaces virtuels). Donc le pattern arbre seul ne couvre pas le cas Mission Control. → besoin du complément yabai.

## Pattern yabai — desktop info via SkyLight on-demand

**Source** : `~/11.Repositories/yabai/src/window.c:67-87`

```c
uint64_t window_space(uint32_t wid) {
    CFArrayRef window_list_ref = cfarray_of_cfnumbers(&wid, sizeof(uint32_t), 1, kCFNumberSInt32Type);
    CFArrayRef space_list_ref = SLSCopySpacesForWindows(g_connection, 0x7, window_list_ref);
    if (!space_list_ref) goto err;

    int count = CFArrayGetCount(space_list_ref);
    if (!count) goto free;

    CFNumberRef id_ref = CFArrayGetValueAtIndex(space_list_ref, 0);
    CFNumberGetValue(id_ref, CFNumberGetType(id_ref), &sid);

    /* ... */
    return sid ? sid : window_display_space(wid);
}
```

**Décision** : yabai n'a PAS de cache local du desktop d'une wid. À chaque besoin, il appelle `SLSCopySpacesForWindows(connID, mask: 0x7, [wid])` qui interroge SkyLight (le window server macOS). L'OS est la source unique. Drift impossible — il n'y a rien à synchroniser.

**Stabilité** :
- API privée mais utilisée par yabai depuis 5+ ans en prod.
- Lecture seule, **aucune écriture** — pas besoin de SIP off.
- Stable d'une release macOS à l'autre (yabai a survécu Big Sur, Monterey, Ventura, Sonoma, Sequoia, Tahoe sans modification de cette API spécifique).

**Performance attendue** :
- Latence per-call : ~100-500 µs en charge typique (< 100 wids). Bench yabai sur Issue tracker confirme.
- Coût négligeable si appelé seulement sur events (focus change, poll 2s).
- Si on l'appelle en hot path AX (per-frame), risque d'overhead. NFR-001 interdit explicitement ce hot path.

**Bridging Swift** :

```swift
@_silgen_name("SLSCopySpacesForWindows")
private func SLSCopySpacesForWindows(_ cid: Int, _ mask: UInt32, _ wids: CFArray) -> CFArray?

@_silgen_name("_CGSDefaultConnection")
private func _CGSDefaultConnection() -> Int
```

Pattern utilisé par yabai en C, AeroSpace en Swift, SketchyBar en Objective-C. Réplique directe possible.

**Mask `0x7`** : combine current + other (toutes les spaces qu'une fenêtre habite, en cas de sticky / fullscreen natif). Pour roadie, on veut le space courant — `0x7` retourne typiquement [current_space_id] en premier élément.

## Validation de la perte du cache `state.stageID`

### Ce que le cache faisait

Le champ `WindowState.stageID` (stored) servait à 4 endroits identifiés :

1. **`MouseRaiser.swift:119`** : detect click-in-other-stage pour proposer un raise. Lookup `state.stageID` au moment du click pour savoir vers quel stage rebasculer.
2. **`LayoutEngine.insertWindow`** : déterminer le tree BSP cible quand une nouvelle wid est créée. Lookup `state.stageID` pour sélectionner le bon scope.
3. **`CommandRouter.swift:45`** : payload IPC `windows.list` retourne `"stage": state.stageID?.value` pour le client (rail, scripts).
4. **`registry.update(wid) { $0.stageID = X }`** : 8 call-sites qui mutent pour synchroniser après assign/registration.

### Validation : tout est calculable depuis `memberWindows`

- (1) MouseRaiser : `stageManager.scopeOf(wid)?.stageID` — O(1) via index inverse.
- (2) LayoutEngine : `stageManager.scopeOf(wid)?.stageID` — idem.
- (3) CommandRouter : `stageManager.stageIDOf(wid)?.value ?? ""` — idem.
- (4) Mutations : disparaissent (le champ n'est plus stored).

**Conclusion** : aucun call-site n'a besoin du champ stored. Le cache était redondant.

## Validation de la suppression de `reconcileStageOwnership`

### Ce que la fonction faisait

`StageManager.reconcileStageOwnership` (~90 LOC) parcourait dans les 2 sens :

1. Sens 1 : pour chaque `(stage, member)`, si `state.stageID != stage.id`, écrire `state.stageID = stage.id`.
2. Sens 2 : pour chaque `state` avec `state.stageID = sid`, si `sid` ne correspond plus à aucun stage existant, fallback `defaultID` ; ajouter aux `memberWindows` du stage cible si absent.

Appelée à 4 call-sites : `windows.list` IPC, `stage.list` IPC, et 2× au boot.

### Pourquoi devient obsolète

- Sens 1 : disparu — il n'y a plus de champ `state.stageID` à synchroniser.
- Sens 2 : disparu — il n'y a plus de `state.stageID` qui pourrait pointer vers un stage inexistant. Le scope est calculé à la demande depuis `widToScope`, qui n'est mis à jour que sur des mutations valides (assign, createStage, etc.).

**Cas restant** : wids orphelines (présentes dans `memberWindows` mais absentes du registry car app fermée). Ce cas est traité par un nettoyage simple au boot : `for stage in stages: stage.memberWindows.removeAll { registry.get($0.cgWindowID) == nil }`. ~15 LOC inline, pas besoin d'une fonction dédiée à 90 LOC.

## Coût d'opportunité

**Si on garde le double state** :
- Drift continu, bugs récurrents (observés en sessions 2026-05-02 + 2026-05-03)
- Patches symptomatiques (`reconcileStageOwnership` re-tourne à chaque IPC = ~5-10 ms gaspillés × N appels/jour)
- Confusion conceptuelle — quelle source de vérité au final ?

**Coût du refactor** :
- Net ≥ -50 LOC (cible NFR-004), réaliste -26 LOC après ajout du SkyLight tracker. Borderline.
- ~3-5 jours dev pour US1+US2+tests
- Risque de régression sur SPEC-013 (HideStrategy) bordé par tests existants

**ROI** : positif, surtout que le drift se manifeste désormais visiblement à l'utilisateur dans le navrail (vignettes manquantes/dupliquées). C'est un bug récurrent qui pollue chaque session.

## Sources externes

- [AeroSpace — TreeNode.swift](https://github.com/nikitabobko/AeroSpace/blob/main/Sources/AppBundle/tree/TreeNode.swift)
- [yabai — window.c L67](https://github.com/koekeishiya/yabai/blob/master/src/window.c)
- [SketchyBar — uses SLSCopySpacesForWindows](https://github.com/FelixKratz/SketchyBar)
- Tests internes : `Tests/RoadieDesktopsTests/MigrationTests.swift` (validation persistance V2)
- Logs session 2026-05-03 : 2 incidents distincts de drift (wid 12 iTerm2 vs Mission Control + wid 22 stage 1 vs stage 2)
