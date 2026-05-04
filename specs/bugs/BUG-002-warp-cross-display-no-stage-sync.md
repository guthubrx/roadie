# BUG-002 — `warp` cross-display ne synchronise pas StageManager + DesktopRegistry

**Date observation** : 2026-05-04 (session daily-driving SPEC-025)
**Sévérité** : MEDIUM (fenêtre invisible perçue comme cassée par utilisateur ; workaround manuel disponible)
**Composants** : `Sources/RoadieTiler/LayoutEngine.swift::warp`, `LayoutEngine.swift::moveWindow`, `Sources/roadied/CommandRouter.swift::warp` handler
**Introduit par** : pré-existant (depuis l'ajout de `warp_cross_display_edge` dans LayoutEngine, antérieur à SPEC-025)
**Statut** : **FIXED** dans SPEC-025 amendement (commit à venir post-investigation)

## Symptôme

Après un `roadie warp <direction>` qui traverse une frontière de display (ex: warp depuis le Built-in vers le LG HDR 4K) :

- La fenêtre apparaît correctement sur le display destination dans l'instant
- Au prochain restart du daemon (ou recharge state), la fenêtre est marquée `stage=1` du display source mais physiquement présente sur le display destination → **drift physique vs logique**
- Conséquence : la stage active du display source contient une wid orpheline (member fantôme), tandis que le display destination ne sait pas qu'elle a une fenêtre supplémentaire
- Au switch de stage, la fenêtre disparaît visuellement parce que la stage source du display source la masque

Reproduit en daily-driving le 2026-05-04 :

```
13:28:05  wid 2752 (Firefox) auto_assign_orphan_to_display → Built-in stage=1
13:29:41  wid 2752 move_window_cross_display from=1 to=3 stage=1   (= warp_cross_display_edge)
13:30:10  warp_cross_display_edge wid=2752 from=3 to=1
13:31:41  wid 2752 move_window_cross_display from=1 to=3 stage=1
13:32:23  (RESTART daemon — auto_assign_orphan_to_display Firefox → LG stage=1 depuis state persisté)
13:33+    Firefox physiquement à (125,43) sur Built-in mais scope = LG/stage 1 → ne s'affiche plus
```

## Cause racine

`LayoutEngine.warp(_:direction:)` (ligne 421 et 444 dans LayoutEngine.swift), quand il détecte qu'il faut traverser une frontière de display, appelle `LayoutEngine.moveWindow(_:fromDisplay:toDisplay:near:)`.

**`LayoutEngine.moveWindow` (ligne 290-320)** :

1. ✅ Retire le leaf du tree source
2. ✅ Crée un nouveau leaf dans le tree destination
3. ❌ **NE met PAS à jour `stageManager.memberWindows`** — la wid reste member de la stage du **source display**
4. ❌ **NE met PAS à jour `desktopRegistry.updateWindowDisplayUUID`**
5. ❌ **NE fait PAS de `setBounds` physique explicite** — compte sur `applyAll` suivant pour repositionner

Le handler CLI `warp` dans CommandRouter (avant fix) :

```swift
let warped = daemon.layoutEngine.warp(wid, direction: direction)
daemon.applyLayout()
return .success(["warped": AnyCodable(warped)])
```

Aucune sync avec StageManager ni DesktopRegistry → drift garanti.

**Comparaison** : le handler `window.display` (CommandRouter:1466-1531) fait correctement les 7 étapes (setBounds + updateFrame + moveWindow + updateWindowDisplayUUID + update desktopID + sm.assign + publish event). C'était le bon modèle ; warp n'avait juste pas reçu le même traitement historiquement.

## Pourquoi `roadie heal` (avant fix) ne corrigeait pas

`runIntegrityCheck(autoFix:true)` couvrait 3 cas :
- `degenerate_frames`
- `offscreen_with_active_scope` (frame Y/X hors tous displays)
- `tree_leaf_wrong_display` (leaf dans tree A, mais wid scope = display B)

**Aucun ne couvrait** : "wid member de la stage du display A, mais frame physique on-screen sur display B (= dans le rect d'un display connu, juste pas celui du scope)". C'est précisément ce drift.

## Fix structurel (SPEC-025 amendement)

### Fix de la cause (handler `warp`)

`Sources/roadied/CommandRouter.swift::case "warp"` modifié pour :

1. Capturer `srcDisplayID = layoutEngine.displayIDForWindow(wid)` AVANT le warp
2. Capturer `dstDisplayID = layoutEngine.displayIDForWindow(wid)` APRÈS le warp
3. Si `src != dst` : appliquer le même pattern que `window.display` :
   - `registry.update { $0.desktopID = targetDeskID }`
   - `dRegistry.updateWindowDisplayUUID`
   - `sm.assign(wid: to: targetScope)` ← critique
   - publish `window_assigned` event
4. Logger `warp_cross_display_synced` pour traçabilité

~30 LOC ajoutées dans le handler.

### Filet de secours (CHECK 4 dans `runIntegrityCheck`)

Nouveau check `member_on_wrong_display` ajouté dans `WindowDesktopReconciler.tick(autoFix:)` :

```swift
for state in windows {
    guard let scope = stageManager.scopeOf(wid: state.cgWindowID) else { continue }
    let center = CGPoint(x: state.frame.midX, y: state.frame.midY)
    guard let physicalDisplay = displays.first(where: { $0.frame.contains(center) }) else {
        continue  // frame offscreen : déjà CHECK 2
    }
    guard physicalDisplay.uuid != scope.displayUUID else { continue }
    // → drift détecté, ré-étiqueter
    if autoFix {
        // ... assign au scope physique, update registry, publish event
    }
}
```

`IntegrityReport.memberOnWrongDisplay` ajouté au struct. Reporté dans `daemon.audit` payload + comptabilisé dans `fixedCount`.

→ Tous les drifts résiduels (= warp pré-fix, ou autres voies de drift inconnues) sont auto-corrigés au prochain `roadie heal` ou tick périodique du reconciler.

## Tests

- **Manuel** : `roadie warp left/right/up/down` traversant une frontière de display, observer que `roadie windows list` montre la wid avec le bon `stage=` après warp (cohérent avec le display physique)
- **Restart soak** : warp cross-display + restart daemon, vérifier qu'au boot le state est cohérent (pas de re-drift)
- **`integrity_drift_member_wrong_display` log** : si jamais le drift réapparaît malgré le fix de cause, le log apparaît dans `daemon.log` au prochain `roadie heal` ou tick reconciler

## Logs structurés ajoutés (US7 SPEC-025)

- `warp_cross_display_synced` : le handler warp a détecté un cross-display et appliqué la sync (fix de cause appliqué)
- `integrity_drift_member_wrong_display` : le filet de secours a détecté un drift résiduel et l'a corrigé

Si vous suspectez un drift, lancer `roadie diag` pour packager les logs et les envoyer pour analyse.

## Crédit investigation

Cause racine identifiée par analyse des logs `move_window_cross_display`, `warp_cross_display_edge`, `auto_assign_orphan_to_display` capturés dans `~/.local/state/roadies/daemon.log` lors de la session du 2026-05-04 13:28-13:32. C'est précisément ce que les logs structurés US7 (FR-017) doivent permettre — diagnostic post-mortem reproductible.
