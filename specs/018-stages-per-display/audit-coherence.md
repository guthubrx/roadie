# Audit cohérence display × desktop × stage

**Date** : 2026-05-03
**Contexte** : SPEC-018 livrée, mais l'observation utilisateur a révélé qu'une fenêtre (Grayjay) restait visible alors que son stage était inactif. Audit en profondeur de toutes les confusions display/desktop/stage possibles.

## Modèle attendu (rappel SPEC-018)

```
┌─ Display A (UUID-A) ─┬─ Display B (UUID-B) ─┐
│ Desktop 1            │ Desktop 1            │
│   stage actif: "1"   │   stage actif: "5"   │
│   stages [1,2,3]     │   stages [1,5]       │
│ Desktop 2            │ Desktop 2            │
│   stage actif: "2"   │   stage actif: "1"   │
│   stages [1,2]       │   stages [1]         │
└──────────────────────┴──────────────────────┘
```

3 dimensions strictement orthogonales. **Chaque (display, desktop) doit retenir son propre stage actif.**

## Findings

### F1 — Helpers windows polluaient les stages [FIX appliqué]

- **Cause** : pas de filtre par taille dans `isTileable`, `assign(wid:to:)`, `reconcileStageOwnership`, `purgeOrphanWindows`.
- **Symptôme** : 4-8 wids 66×20 px (Firefox WebExtension, Grayjay/Electron tooltips, iTerm popovers) attribuées à stage 1 et persistées sur disque, repolluant à chaque boot.
- **Fix** : `WindowState.isHelperWindow` + gardes en amont aux 4 endroits. Voir `Sources/RoadieCore/Types.swift`.

### F2 — Hide non déclenché au boot [FIX appliqué]

- **Cause** : au boot, `currentStageID` est restauré depuis disque mais aucun `switchTo` n'est appelé → wids des stages non-actives gardent leur frame on-screen.
- **Symptôme** : Grayjay (stage 2) visible au boot alors que stage 1 actif.
- **Fix** : `main.swift` Task post-boot appelle `sm.switchTo(currentStageID)` pour propager hide.

### F3 — `MouseRaiser` ignorait le scope [FIX appliqué]

- **Cause** : click sur une fenêtre élève `kAXRaiseAction` sans regarder son `state.stageID`.
- **Symptôme** : si une fenêtre se retrouve on-screen pour une raison X (Cmd+Tab, bug, …), cliquer dessus la maintient visible sans switcher de stage.
- **Fix** : callback `onClickInOtherStage` qui délègue au daemon, lequel fait `switchTo(targetStage)` avant de raise.

### F4 — `axDidChangeFocusedWindow` ne suivait pas le stage [FIX appliqué]

- **Cause** : Cmd+Tab → focus change AX → `registry.setFocus(wid)`. Suivait le `desktop` mais pas le `stage`.
- **Symptôme** : Cmd+Tab vers Grayjay (stage 2) le rend focused mais hidden offscreen — l'app peut alors se forcer on-screen → état incohérent.
- **Fix** : ajout du pendant `if state.stageID != currentStageID → switchTo(stageID)`.

### F5 — `currentStageID` est un scalaire global [FIX en cours]

- **Cause** : `StageManager.currentStageID: StageID?` ne stocke qu'**une** valeur. Inadéquat pour multi-display où chaque (display, desktop) doit retenir son stage actif indépendamment.
- **Symptôme** :
  - Sur 2 displays, on ne peut pas avoir simultanément Display A → stage "1" et Display B → stage "5".
  - Au desktop_changed, on perd le contexte du desktop précédent.
- **Fix** : ajouter `activeStageByDesktop: [DesktopKey: StageID]` (cf F6).

### F6 — `reload(forDesktop:)` reset `currentStageID` à nil [FIX en cours]

- **Cause** : ligne 206 de StageManager. Utile en mode V1 (swap de dossier physique), inadéquat en mode V2 où `stagesV2` reste chargé.
- **Symptôme** : aller-retour desktop 1↔2 perd la mémoire du stage actif sur le desktop quitté.
- **Fix** : en mode V2, conserver les structures, juste relire `loadActiveStage(forDisplay:desktop:)`.

### F7 — `LayoutEngine.workspace.activeStageID` est scalaire global [TODO]

- **Cause** : un seul `activeStageID` dans Workspace, partagé entre tous les displays.
- **Symptôme** : `applyAll(displayRegistry:)` itère sur tous les displays mais utilise la **même** stageID partout. Impossible que Display A montre stage "1" pendant que Display B montre stage "5".
- **Status** : non corrigé dans cette session — nécessite refonte de `Workspace` + `applyAll`. Cas d'usage encore théorique tant que F5 + F6 ne sont pas livrés.

### F8 — `windows.list` n'expose pas le scope [TODO mineur]

- **Cause** : champ `stage` retourné, pas de `display_uuid` ni `desktop_id` dans la response.
- **Symptôme** : un client externe (rail, sketchybar) ne peut pas filtrer les fenêtres par scope sans appeler `daemon.status` en parallèle.
- **Status** : ajouter trois champs à la réponse. Trivial.

### F9 — `WallpaperStageCoordinator.handleClick` utilise l'API V1 [TODO mineur]

- **Cause** : ligne 65 `sm.assign(wid:to: stageID)` (overload V1) au lieu de `sm.assign(wid:to: scope)`.
- **Symptôme** : en mode V2, la stage créée par wallpaper-click est dans le scope courant via auto-sync, mais l'assignment des wids passe par le path V1 → potentiel mismatch si la souris a bougé entre les deux opérations.
- **Status** : remplacer par l'overload V2.

### F11 — `assign(wid:to: stageID:)` V1 ne nettoyait pas stagesV2 [FIX appliqué]

- **Cause** : l'overload V1 retire la wid des autres entrées **stages V1** mais pas des entrées **stagesV2**. En mode per_display, des call-sites legacy (wallpaper-click, registerWindow auto-assign) appellent l'API V1 → la wid se retrouve dans 2 entrées de stagesV2 simultanément.
- **Symptôme observé** : `Grayjay (wid 22089)` dans `1.toml` ET `2.toml`. Au boot, `reconcileStageOwnership` Sens 1 itère stagesV2 et `state.stageID` finit non-déterministe (selon ordre dict).
- **Fix** : en mode `.perDisplay`, l'overload V1 délègue à l'overload V2 avec le scope construit depuis `currentDesktopKey`. Le V2 fait correctement le ménage cross-scope.

### F10 — `registerWindow` initial avec `desktopID = 1` hardcodé [TODO mineur]

- **Cause** : ligne 807 `stageID: 1` constant pour `WindowEntry`.
- **Symptôme** : une fenêtre créée alors qu'on est sur desktop 2 est néanmoins enregistrée avec `desktopID=1`. Corrigé après par les events AX, mais transient.
- **Status** : remplacer par `currentDesktopID(for: displayID)` du registry desktop.

## Ordre des fixes

| Sévérité | F# | Status | Note |
|---|---|---|---|
| Critique | F1 | DONE | Helper invariant |
| Critique | F2 | DONE | Hide au boot |
| Important | F3 | DONE | MouseRaiser respect scope |
| Important | F4 | DONE | Cmd+Tab respect scope |
| Important | F5 | DONE | activeStageByDesktop |
| Important | F6 | DONE | Préserver stagesV2 sur desktop_changed |
| Important | F11 | DONE | assign V1 délègue à V2 (anti double-attribution) |
| **Critique** | **F12** | **DONE** | setMode V2 + setCurrentDesktopKey AVANT registerExistingWindows |
| **Critique** | **F13** | **DONE** | registerWindow propage state.stageID depuis stagesV2 avant insertWindow |
| **Critique** | **F14** | **DONE** | registerWindow skip auto-assign si wid déjà persistée |
| **Important** | **F15** | **DONE** | reconcileStageOwnership AVANT auto-assign orphelines |
| **Important** | **F16** | **DONE** | Émission window_created / window_destroyed pour resync rail |
| **Important** | **F17** | **DONE** | setCurrentDesktopKey sync stages V1 dict avec scope courant |
| **Important** | **F18** | **DONE** | setCurrentDesktopKey ne fait plus setActiveStage (cause showing wids cross-desktop) |
| **Critique** | **F19** | **DONE** | desktop.focus per_display filtre par activeStageOnTarget (montrait toutes wids du desktop) |
| Important | F7 | TODO | LayoutEngine multi-display réel (Workspace.activeStageByDisplay) |
| Trivial | F8 | TODO | scope dans windows.list |
| Trivial | F9 | TODO | WallpaperStageCoordinator API V2 |
| Trivial | F10 | TODO | desktopID initial cohérent |

## Validation finale (cycle complet, 2026-05-03 ~10h)

**Test visuel (screenshots dans `/tmp/roadie-debug/`)** :

| Action | État registry | Visuel |
|---|---|---|
| Boot D1 stage 1 | Grayjay `-1909,1248 stage=2` | Cursor + Firefox + 2 terminals visibles, pas de Grayjay |
| Switch stage 2 | Grayjay `125,43 1910x1172 stage=2` | Grayjay seul plein écran |
| D1 → D2 | Toutes wids `-1909,1248` ou `-949,1252` | Écran propre (fond Earth) |
| D2 → D1 (mémoire stage 2) | Grayjay visible, autres offscreen | Grayjay seul plein écran ✓ |
| Switch stage 1 | Cursor/Firefox/terminals visibles, Grayjay `-1909,1248` | Cursor + Firefox + 2 terminals |

**Le bug "Grayjay visible alors que stage 2 inactif" est définitivement éliminé** par les fixes F12 (timing), F13/F14 (respect persistence), F19 (desktop.focus filtre stage).

## Validation manuelle effectuée

- ✅ Boot frais : `current_stage=1`, Grayjay (stage 2) hidden offscreen.
- ✅ `roadie stage 2` → Grayjay plein écran ; `roadie stage 1` → cachée.
- ✅ Switch desktop 1→2→1 : `current_stage` retrouve la valeur mémorisée pour D1 (était `2` → reste `2`, pas reset à `1`).
- ✅ Disque cohérent : Grayjay 22089 présent uniquement dans `2.toml` après les manipulations (avant : doublon dans `1.toml` + `2.toml`).

## Critères de validation

Tests manuels qui doivent passer après F5+F6 :
1. Démarrer sur desktop 1, switcher stage 1 → 2. Switcher desktop 1 → 2. Switcher desktop 2 → 1. Vérifier que stage actif sur desktop 1 est bien "2" (pas "1").
2. Sur 2 displays (mode per_display) : créer "stage 5" sur Display B (curseur sur B), vérifier que `roadie stage list` (curseur sur Display A) ne le retourne pas.
3. Déplacer curseur sur Display B → `roadie stage list` retourne "stage 5".
