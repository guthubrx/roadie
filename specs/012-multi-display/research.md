# Phase 0 — Research Technique : Roadie Multi-Display

**Spec** : SPEC-012 | **Date** : 2026-05-02

## Contexte

Extension SPEC-011 pour multi-écran. SPEC-011 gère déjà le hide multi-display (formule offscreen dynamique via `NSScreen.screens`). SPEC-012 ajoute le **tiling per-display** + **déplacement entre écrans** + **détection dynamique** + **persistance écran d'origine**.

## R-001 : Identifiant stable d'écran

**Décision** : utiliser `CGDirectDisplayID` (UInt32) pour l'identification interne, et `CGDisplayCreateUUIDFromDisplayID()` (CoreGraphics public) pour un UUID stable cross-reboot.

**Rationale** :
- `CGDirectDisplayID` est stable pendant la session mais peut changer entre reboots (selon ordre de détection hardware).
- L'UUID retourné par `CGDisplayCreateUUIDFromDisplayID` est stable entre reboots pour le même hardware (basé sur EDID + VID/PID), idéal pour persistance.
- `NSScreen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")]` expose le `CGDirectDisplayID` depuis un `NSScreen`.

**Alternatives** :
- `NSScreen.localizedName` : pas unique (ex: 2 écrans Dell identiques).
- `NSScreen.frame` : change selon position, pas stable.

**Validation** : pattern utilisé par AeroSpace, Hammerspoon, Phoenix.

---

## R-002 : Observer changement de configuration d'écran

**Décision** : `NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification)`. Notif émise par AppKit à chaque branch/débranch/repositionnement/changement résolution.

**Rationale** :
- API publique stable depuis macOS 10.7.
- Notif émise sur le main thread (sûre pour UI/AX).
- Délivrée 1-2 secondes après le changement physique (le temps que macOS ré-énumère les écrans).

**Alternatives** :
- `CGDisplayRegisterReconfigurationCallback` (CoreGraphics private) : pas plus rapide, plus complexe.
- Polling périodique de `NSScreen.screens.count` : inutilement coûteux.

---

## R-003 : Mapping fenêtre → écran

**Décision** : pour une `WindowState.frame` donnée, calculer le centre `(x + w/2, y + h/2)` et tester quel `NSScreen.visibleFrame` le contient. En coords AX top-left, conversion nécessaire vers Quartz bottom-left avant test (NSScreen.screens utilise Quartz).

**Rationale** :
- Le centre est plus robuste que l'origin top-left (une fenêtre légèrement à cheval sera attribuée à l'écran qui en contient le plus).
- AeroSpace utilise le même critère.

**Alternatives** :
- Plus grande surface visible : équivalent en pratique mais plus coûteux.
- L'origine top-left : cas pathologique si la fenêtre déborde du haut d'un écran portrait.

**Edge case** : fenêtre 100% hors-écran (offscreen, cas SPEC-011) → fallback primary screen.

---

## R-004 : Tiling multi-rect

**Décision** : `LayoutEngine` maintient un `[CGDirectDisplayID: TilingContainer]` (un arbre par écran). `applyAll()` itère sur tous les écrans connectés et appelle le tiler de chacun avec son `visibleFrame`.

**Rationale** :
- Architecture la plus simple : N arbres indépendants au lieu d'un arbre unique avec partition logique.
- Permet stratégie différente par écran (BSP sur 1, master-stack sur 2) sans complexité.
- Pattern AeroSpace.

**Alternatives** :
- 1 arbre global avec contraintes "subtree par écran" : violation de l'invariant tiler (un node = un rect contigu).
- Layout déclaratif (CSS-grid-like) : sur-engineering.

**Implémentation** : `LayoutEngine.workspace.rootsByDisplay: [CGDirectDisplayID: TilingContainer]`. Chaque méthode (`insertWindow`, `removeWindow`, `applyAll`, `setLeafVisible`) gère le routage par display.

---

## R-005 : Déplacement de fenêtre entre écrans

**Décision** : `roadie window display N` :
1. Détermine l'écran source (via centre de la frame courante).
2. Retire le wid de l'arbre source via `tiler.removeWindow(wid, fromDisplay: srcID)`.
3. Calcule la nouvelle frame : centre dans le `visibleFrame` de l'écran cible, taille préservée mais ajustée si elle dépasse.
4. Applique la nouvelle frame via `AXReader.setBounds`.
5. Insère le wid dans l'arbre cible via `tiler.insertWindow(wid, intoDisplay: dstID)`.
6. Update `WindowEntry.displayUUID = dstUUID` dans le DesktopRegistry.
7. Re-applique le layout des deux écrans (source + cible).

**Rationale** : déplacement atomique côté logique, deux applyLayout côté visuel pour rétablir la cohérence par écran.

**Alternatives** :
- Pas de mise à jour displayUUID : régression au prochain boot.

---

## R-006 : Recovery branch/débranch

**Décision** : à `didChangeScreenParameters` :
1. Calculer diff `oldDisplays` vs `newDisplays`.
2. Pour chaque écran retiré : pour chaque fenêtre attachée, ajuster sa frame pour l'amener dans le `visibleFrame` du primary screen (clamp), insérer dans l'arbre primary.
3. Pour chaque écran ajouté : initialiser un nouvel arbre vide. Les fenêtres y arriveront naturellement quand l'utilisateur les déplacera.
4. `applyAll()` final.

**Rationale** :
- Conservative : on ne ramène pas automatiquement les fenêtres sur le nouvel écran (FR-016) — c'est ambigu (mêmes fenêtres ? autre arrangement ?).
- Sûr : aucune fenêtre ne reste hors-écran après débranchement.

**Alternatives** :
- Mémoriser le mapping et restaurer à la reconnexion : ambigu si l'écran reconnecté n'est pas le même hardware.

---

## R-007 : Persistance displayUUID

**Décision** : étendre `WindowEntry` avec `displayUUID: String?` (optionnel). Backward-compatible :
- Anciennes entrées sans le champ → `nil` → fallback primary à la restauration.
- Sérialisation TOMLKit : champs optionnels gérés nativement (omitif vide).

**Format** :
```toml
[[windows]]
cgwid = 12345
bundle_id = "com.apple.terminal"
expected_x = 100.0
expected_y = 100.0
expected_w = 800.0
expected_h = 600.0
stage_id = 1
display_uuid = "37D8832A-2D66-02CA-B9F7-8F30A301B230"  # optional
```

**Validation** : round-trip parse/encode en TOMLKit déjà testé pour autres champs optionnels.

---

## R-008 : Per-display config

**Décision** : section TOML `[[displays]]` (array of tables). Match par `match_index` OU `match_uuid` OU `match_name` (au moins un). Champs override : `default_strategy`, `gaps_outer`, `gaps_inner`.

**Format** :
```toml
[[displays]]
match_uuid = "37D8832A-2D66-02CA-B9F7-8F30A301B230"
default_strategy = "master_stack"
gaps_outer = 16
gaps_inner = 8

[[displays]]
match_index = 0
gaps_outer = 4
```

**Rationale** : conforme aux autres specs (rules `[[desktops]]` etc.). Match par UUID le plus stable, par index le plus pratique.

**Alternatives** : config globale unique : pas assez fin.

---

## R-009 : Events display_changed

**Décision** : `display_changed` émis quand l'écran qui contient la fenêtre frontmost change. Détection : à chaque `axDidChangeFocusedWindow`, recalculer l'écran de la fenêtre focus, comparer avec le précédent, émettre si différent.

**Format** :
```json
{"event":"display_changed","from":"0","to":"1","ts":1714672389123}
```

**Rationale** : utile pour SketchyBar (afficher l'écran actif comme l'application active).

---

## R-010 : Validation statique no-CGS étendue

**Décision** : étendre `Tests/StaticChecks/no-cgs.sh` pour inclure `Sources/RoadieCore/DisplayRegistry.swift` et `Sources/RoadieCore/Display.swift` dans le périmètre de check. Aucun `CGS|SLS|SkyLight` ne doit y apparaître hors commentaires.

**Rationale** : SC-007 (0 dépendance privée nouvelle).

---

## R-011 : Tests sans display réel

**Décision** : injecter une `DisplayProvider` protocol dans `DisplayRegistry`. Implémentation `NSScreenDisplayProvider` lit `NSScreen.screens` ; `MockDisplayProvider` pour tests retourne une liste fixée.

**Rationale** : tests unitaires sans dépendance hardware. Pattern déjà utilisé pour `WindowMover` SPEC-011 (avant suppression).

---

## R-012 : Migration backward-compat

**Décision** : au boot du daemon, charger `state.toml` peut contenir des `WindowEntry` sans `display_uuid`. Comportement : pour chaque telle entrée, calculer le `display_uuid` cible depuis la position courante (champ `expected_frame`) au moment du chargement, et persister immédiatement. Au prochain boot, le champ est rempli.

**Rationale** : migration silencieuse sans intervention utilisateur. Backward-compat.

**Alternatives** : forcer migration explicite : friction inutile.

---

## Synthèse

Aucun NEEDS CLARIFICATION résiduel. Toutes les décisions techniques sont arrêtées, fondées sur des APIs macOS publiques stables (NSScreen, NSNotificationCenter, CGDisplayCreateUUIDFromDisplayID) et des patterns éprouvés (AeroSpace, Hammerspoon, Phoenix).
