# Phase 0 — Research Technique : Roadie Virtual Desktops

**Spec** : SPEC-011 | **Date** : 2026-05-02

## Contexte

Pivot architectural majeur. SPEC-003 (multi-desktop par Mac Space natif via SkyLight) est cassée par macOS Tahoe 26 (cf. yabai issue #2656). SPEC-011 adopte le pattern AeroSpace : tous les desktops virtuels dans un seul Mac Space natif, hide/show via offscreen.

Cette phase consolide les choix techniques nécessaires à l'implémentation, sans NEEDS CLARIFICATION résiduel.

---

## R-001 : Mécanisme de "hide" d'une fenêtre

**Décision** : déplacer la fenêtre à `(-30000, -30000)` via `AXUIElement` + `kAXPositionAttribute`.

**Rationale** : `setLeafVisible` interne du tiler V1 fait déjà exactement ça pour les stages. Pas besoin d'inventer. Le mécanisme est éprouvé (SPEC-001/002) et marche sur macOS 14/15/26 sans modification SIP. La position `(-30000, -30000)` place la fenêtre en dehors de tout `visibleFrame` connu (les écrans Retina vont jusqu'à ~6000 pixels en X/Y), garantissant l'invisibilité.

**Alternatives considérées** :
- `[NSWindow miniaturize]` : ne marche que sur les fenêtres possédées par l'app courante (pas via AX externe).
- `kAXMinimizedAttribute = true` : minimise dans le Dock visuellement, comportement utilisateur intrusif.
- Cacher l'app entière (`NSRunningApplication.hide()`) : trop large, affecte aussi les fenêtres qui devraient rester visibles si elles sont sur d'autres desktops appartenant à la même app.
- Attribut `kAXHiddenAttribute` : non-standard, comportement variable selon l'app.

**Validation** : déjà en production V1 pour les stages, aucun bug rapporté.

---

## R-002 : Position attendue d'une fenêtre on-screen

**Décision** : conserver dans `WindowState` une `expectedFrame: CGRect` mise à jour par observation AX (`kAXPositionChangedNotification`, `kAXSizeChangedNotification`) **uniquement quand la fenêtre est on-screen** (= `desktop_id == currentDesktopID`).

**Rationale** : si on observe les changements de position en permanence, on capturerait la position offscreen `(-30000, -30000)` comme "expectedFrame" et la prochaine restauration enverrait la fenêtre... offscreen. Filtrer par `currentDesktopID` est nécessaire et suffisant. Ce filtre est local au switcher, pas besoin de modifier l'observer AX.

**Alternatives considérées** :
- Pause de l'observer pendant une bascule : complexe, race conditions probables.
- Snapshot avant chaque bascule : doublon avec l'observer existant, deux sources de vérité.

**Validation** : pattern utilisé par AeroSpace (cf. `WindowsCache.swift` upstream).

---

## R-003 : Sérialisation des bascules concurrentes

**Décision** : queue `actor` Swift unique (`DesktopSwitcher`), une seule bascule en vol à la fois. Si une nouvelle requête arrive pendant qu'une bascule est en cours, la dernière en attente écrase les intermédiaires.

**Rationale** : l'utilisateur appuie potentiellement vite sur ⌘+& puis ⌘+é. Si on les exécute en parallèle, on a un risque réel de fenêtres laissées offscreen. Un `actor` Swift sérialise naturellement les méthodes async. Une variable `pendingTarget: Int?` collapse les requêtes en attente.

**Alternatives considérées** :
- `DispatchQueue.serial` : équivalent fonctionnel mais moins idiomatique en Swift 6.
- Lock-free atomic + spin : sur-design pour un cas où la fréquence max est ~10 Hz.
- Pas de sérialisation : risque de fenêtres orphelines offscreen, inacceptable (cf. edge case "bascule rapide").

**Validation** : cf. `Tests/RoadieDesktopsTests/DesktopSwitcherTests.swift::testRapidSwitchCollapsing`.

---

## R-004 : Format de persistance par desktop

**Décision** : un fichier TOML par desktop dans `~/.config/roadies/desktops/<id>/state.toml` :

```toml
id = 1
label = "code"
layout = "bsp"
gaps_outer = 8
gaps_inner = 4
active_stage_id = 1

[[windows]]
cgwid = 12345
bundle_id = "com.apple.Terminal"
expected_x = 100.0
expected_y = 100.0
expected_w = 800.0
expected_h = 600.0
stage_id = 1

[[windows]]
cgwid = 67890
...

[[stages]]
id = 1
label = ""
windows = [12345]
```

**Rationale** : conforme principe E (texte plat, debug avec cat/grep). TOML est déjà parsé manuellement dans `RoadieCore/Config.swift` (parser ad-hoc, ~80 LOC, no dep). Un fichier par desktop évite les écritures concurrentes sur un fichier global et simplifie la corruption recovery (si desktop 3 corrompu, desktops 1/2/4 intacts).

**Alternatives considérées** :
- JSON : plus verbose pour TOML simple, et le projet a déjà décidé non-JSON (constitution principe E).
- Format TSV maison : OK techniquement mais plus rigide pour les sections nestées (`[[windows]]`, `[[stages]]`).
- SQLite : violation principe E.
- Un seul fichier global `desktops.toml` : risque de corruption en cascade, écritures fréquentes.

**Validation** : extension naturelle du parser existant, lecture instantanée (< 5 ms par fichier sur SSD).

---

## R-005 : Migration V1 → V2 (FR-021)

**Décision** : au démarrage du daemon, si `~/.config/roadies/desktops/` est vide ou inexistant **et** que `~/.config/roadies/stages/` contient des stages V1, créer `~/.config/roadies/desktops/1/state.toml` avec :
- `id = 1`, `label = ""`
- `layout = config.tiler.default_layout`
- toutes les stages V1 dans `[[stages]]`
- toutes les fenêtres V1 dans `[[windows]]` avec `stage_id` repris du fichier V1

Le dossier `~/.config/roadies/stages/` est conservé (read-only) pour rollback éventuel pendant 1 release, puis supprimé en V2.1.

**Rationale** : pas de perte de donnée utilisateur. Migration transparente. Garde-fou de rollback.

**Alternatives considérées** :
- Forcer l'utilisateur à exécuter `roadie migrate` : friction inutile, FR-021 demande automatique.
- Lire/écrire en place dans `~/.config/roadies/stages/` : couple SPEC-001 et SPEC-011, dette future.

---

## R-006 : Migration depuis SPEC-003 deprecated (FR-022)

**Décision** : au démarrage, détecter si `~/.config/roadies/desktops/<UUID-natif>/` existe (format SPEC-003 = UUID Mac Space). Si oui :
1. Renommer le dossier en `~/.config/roadies/desktops/.archived-spec003-<UUID>/`
2. Logger un warning unique "SPEC-003 state archivé, repartir de zéro pour SPEC-011"
3. Recréer la migration depuis `~/.config/roadies/stages/` (cas R-005)

**Rationale** : pas de tentative de mapper UUID→id (les UUID Mac Space sont volatiles et le mapping serait ambigu si l'utilisateur a 3 Mac Spaces et les pose tous sur desktop 1). Archive plutôt que delete pour permettre forensic en cas de question utilisateur.

**Alternatives considérées** :
- Mapping ordinal UUID→id (1er UUID rencontré → desktop 1, etc.) : ambigu et pas reproductible (l'ordre des UUID dépend du moment de découverte).
- Suppression silencieuse : risque de perte de donnée si utilisateur avait beaucoup configuré sous SPEC-003.

---

## R-007 : Émission des events `desktop_changed`

**Décision** : pattern publish/subscribe in-memory. Un `EventBus` singleton (`actor`) maintient une liste de `AsyncStream.Continuation`, chaque souscripteur (`roadie events --follow`) reçoit son flux. Délai d'émission < 50 ms (FR-016) garanti par le fait qu'on `yield()` immédiatement après la bascule, dans le même tick.

**Rationale** : pas de socket additionnel, le canal events passe par le socket Unix existant du daemon. Le subscriber CLI ouvre une connexion long-poll et lit des JSON-lines. Idiomatique Swift 6 (`AsyncStream`), 0 dépendance.

**Alternatives considérées** :
- FIFO Unix dédiée : seconde IO à gérer, complique la rotation/cleanup.
- Notification Center distribuée : Apple spécifique, friction pour un client externe shell-script.
- ZeroMQ / WebSocket : violation principe B (dépendance tierce).

**Validation** : prototypable en ~30 LOC.

---

## R-008 : Compatibilité avec les stages V1

**Décision** : `RoadieStagePlugin/StageManager` ajoute un filtre `desktop_id == currentDesktopID` sur toutes ses opérations (list/focus/create). Lors d'une bascule de desktop, le `DesktopSwitcher` notifie le `StageManager` qui :
1. Sauvegarde l'état stages du desktop quitté
2. Charge l'état stages du desktop d'arrivée
3. Active le `active_stage_id` du desktop d'arrivée

**Rationale** : un seul `StageManager` est conservé (refonte minime). Les fichiers stages V1 disparaissent au profit du tableau `[[stages]]` dans `state.toml` du desktop. SC-003 (0 régression) vérifié par re-tester la suite stage V1 existante.

**Alternatives considérées** :
- N `StageManager` (un par desktop) : sur-abstraction, gestion mémoire/threads complexifiée.
- Refondre stages V1 entièrement : violation Article 0 minimalisme + risque de régression.

---

## R-009 : Validation statique "0 appel SkyLight pour la bascule" (SC-005)

**Décision** : test CI qui exécute :

```bash
git ls-files Sources/RoadieDesktops/ | xargs grep -lE 'CGS|SLS|SkyLight' && exit 1 || exit 0
```

Et vérifie qu'aucun fichier de `RoadieDesktops/` ne référence ces symboles. Test bloquant en CI.

**Rationale** : SC-005 est un critère mesurable simple, vérifiable par grep. Pas besoin d'analyse statique complexe.

**Alternatives considérées** :
- Inspection AST Swift (SwiftSyntax) : sur-engineering pour un grep.
- Aucun test : régression silencieuse possible si quelqu'un re-introduit CGS.

---

## R-010 : Suppression code legacy SPEC-003

**Décision** : suppression intégrale du dossier `Sources/RoadieCore/desktop/` (8 fichiers, ~600 LOC) et du `case .spaceFocus` dans `OSAXCommand.swift` (ajouté en session précédente, jamais utilisé). Le `CommandRouter` dans `roadied` est nettoyé des références à `daemon.desktopManager`.

**Rationale** : la dette mort-vivante est plus dangereuse que la suppression. SPEC-003 est deprecated, son code n'a aucune utilité future. Conformité principe A (Suckless) et principe G (LOC).

**Alternatives considérées** :
- Marquer les fichiers `@available(*, deprecated)` : symbolique, n'enlève pas le code mort.
- Garder pour "au cas où Apple fix la régression" : Apple n'a pas fix en 1 an, hypothèse spéculative.

---

## R-011 : Configuration TOML `[desktops]`

**Décision** : extension de `Config.swift` :

```toml
[desktops]
enabled = true              # default
count = 10                  # 1..16
default_focus = 1           # 1..count
back_and_forth = true
offscreen_x = -30000        # technique, rarement modifié
offscreen_y = -30000
```

**Rationale** : sémantique claire, valeurs par défaut sûres. `offscreen_x/y` exposés mais non documentés dans le README utilisateur (tuning avancé seulement).

---

## R-012 : Tests automatisés (FR-003 perf)

**Décision** : trois niveaux :
1. **Unitaires** (`Tests/RoadieDesktopsTests/`) : DesktopRegistry parse/serialize round-trip, Switcher state machine, Migration.
2. **Intégration légère** : harness lance le daemon en mode test (socket dans `/tmp/roadied-test-<pid>.sock`), envoie `desktop.focus`, lit la réponse.
3. **Performance** : test paramétré qui crée 10 fenêtres factices via `MockWindowRegistry`, mesure `switch(to:)` < 200 ms.

**Rationale** : pyramide standards. Aucune dépendance test tierce.

**Alternatives considérées** :
- Pas de tests perf : SC-001 invérifiable. Inacceptable.
- Tests E2E avec vraies fenêtres macOS : fragile, dépend de l'env CI Mac.

---

## Synthèse

Aucun NEEDS CLARIFICATION résiduel. Toutes les décisions techniques sont arrêtées, fondées sur des patterns existants (AeroSpace, V1 stages V1 setLeafVisible) ou sur des extensions naturelles du codebase actuel. La phase 1 design peut démarrer.
