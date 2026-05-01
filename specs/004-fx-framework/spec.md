# Feature Specification: Framework SIP-off opt-in (SPEC-004)

**Feature Branch**: `004-fx-framework`
**Created**: 2026-05-01
**Status**: Implemented (Phase 1+2+3+4 complètes 2026-05-01 — daemon Swift + osax bundle Objective-C++ + scripts install/uninstall + Makefile cibles + tests intégration shell. Validation runtime sur machine SIP partial off à faire par l'utilisateur via `make install-fx`)
**Dependencies**: SPEC-002-tiler-stage (V1), SPEC-003-multi-desktop (en cours, pas un bloqueur dur car développement parallèle via worktrees)
**Input** : « Cadre commun pour modules optionnels qui requièrent SIP partiellement désactivé. Le daemon roadie reste 100% fonctionnel sans aucun module chargé (dealbreaker sans SIP). Modules livrés dans des dynamic libraries SwiftPM séparées, jamais liées au binaire daemon. Une scripting addition `roadied.osax` est injectée dans Dock pour exposer les CGS privés sur fenêtres tierces. Modules dialoguent avec l'osax via socket Unix locale. Plafond LOC framework : 800 strict (cible 600). Famille SPECs SIP-off : SPEC-005 RoadieShadowless, SPEC-006 RoadieOpacity, SPEC-007 RoadieAnimations Bézier-style, SPEC-008 RoadieBorders, SPEC-009 RoadieBlur, SPEC-010 RoadieCrossDesktop. »

---

## Vocabulaire (CRITIQUE — à respecter strictement)

- **Daemon core** = `roadied` binaire principal + targets `RoadieCore` / `RoadieTiler` / `RoadieStagePlugin` (SPEC-001/002/003). 100 % SIP-on safe. Aucun module SIP-off n'est jamais lié statiquement à ce binaire.
- **Module FX** = un target SPM `.dynamicLibrary` séparé (`.dylib`), chargé à runtime par le daemon via `dlopen`. Chacun fait l'objet d'une SPEC dédiée (005-010 et plus tard).
- **`RoadieFXCore`** = lib partagée entre tous les modules FX (Bézier engine, animation loop, OSAX bridge). Aussi un `.dynamicLibrary`.
- **`roadied.osax`** = scripting addition macOS (bundle Cocoa Objective-C++) installée dans `/Library/ScriptingAdditions/`, injectée dans Dock via `osascript`. Unique pont vers les CGS privés en écriture (`CGSSetWindowAlpha`, etc.).
- **OSAX bridge** = client socket Unix dans `RoadieFXCore` qui parle à `roadied.osax`. Protocol JSON-lines.
- **« Vanilla »** = utilisateur sans aucun module FX ni osax. Comportement = SPEC-001 + SPEC-002 + SPEC-003 sans rien d'extra.

---

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Utilisateur vanilla (SIP plein, aucun module installé) (Priority: P1) 🎯 MVP V2

L'utilisateur Alice utilise roadie quotidiennement avec son tiling BSP, ses 2 stages par desktop et son multi-desktop awareness. Elle n'a jamais touché à SIP, n'a installé aucun module FX, ne sait même pas que SPEC-004 existe.

Quand elle fait `brew upgrade roadie`, son daemon est mis à jour avec le code SPEC-004 (loader + protocol FXModule). Au boot, elle ne voit aucune différence : aucun warning anxiogène, aucune fonctionnalité dégradée, aucun changement perceptible. `roadie fx status` (nouvelle commande) lui retourne calmement `{sip: "enabled", osax: "absent", modules: []}` si elle pose la question.

**Why this priority** : c'est la **garantie absolue de compartimentation**. Si un seul utilisateur vanilla voit une régression, l'invariant « dealbreaker sans SIP » est rompu et tout l'édifice s'effondre.

**Independent Test** : machine clean macOS avec SIP fully on, installer roadie SPEC-004, démarrer le daemon, vérifier que TOUS les tests d'acceptation SPEC-002 et SPEC-003 passent à l'identique (tiling, stages, multi-desktop, drag-to-adapt, click-to-raise, 13 raccourcis BTT, ⌥1/⌥2). `nm /usr/local/bin/roadied | grep -E 'CGSSetWindow|CGSAddWindow'` retourne 0 ligne (aucun symbole CGS d'écriture linké).

**Acceptance Scenarios** :
1. **Given** machine SIP fully on, aucun `.dylib` dans `~/.local/lib/roadie/`, aucune osax. **When** `roadied --daemon` démarre. **Then** boot sans warning, log info `FX modules: 0 loaded` discret.
2. **Given** la même machine. **When** Alice exécute `roadie fx status`. **Then** sortie JSON `{"sip": "enabled", "osax": "absent", "modules": []}`, exit 0.
3. **Given** la même machine. **When** Alice fait toutes ses actions habituelles (créer stage, switch desktop, click-to-raise, drag-to-adapt). **Then** comportement strictement identique à SPEC-003 vanilla.

---

### User Story 2 - Utilisateur power (SIP partiel off, modules + osax installés) (Priority: P1)

L'utilisateur Bob est un fou furieux qui veut son tiling avec animations Bézier, focus dimming et borders gradient (style Hyprland). Il a déjà désactivé partiellement SIP sur sa machine (`csrutil enable --without fs --without debug --without nvram`), il fait `roadied install-fx` qui dépose `roadied.osax` dans `/Library/ScriptingAdditions/` et copie les `.dylib` dans `~/.local/lib/roadie/`.

Au démarrage du daemon, Bob voit dans `daemon.log` :
```
INFO  fx_loader: SIP partial detected (filesystem off)
INFO  fx_loader: scanning ~/.local/lib/roadie/*.dylib
INFO  fx_loader: loaded RoadieShadowless v0.1
INFO  fx_loader: loaded RoadieOpacity v0.1
INFO  fx_loader: loaded RoadieAnimations v0.1
INFO  osax_bridge: connected to /var/tmp/roadied-osax.sock
INFO  fx_loader: 3 modules ready
```

Quand Bob ouvre une fenêtre Safari, elle apparaît avec un fade-in animé Bézier. Sa fenêtre non-focused est légèrement dimmed. `roadie fx status` retourne `{sip: "disabled-fs", osax: "healthy", modules: ["shadowless", "opacity", "animations"]}`.

**Why this priority** : c'est la promesse fonctionnelle du framework. Sans elle SPEC-004 n'a pas de raison d'être.

**Independent Test** : machine SIP partial off, installer 1 module fictif (test stub) qui appelle `OSAXBridge.send({"cmd": "noop"})` toutes les 2 secondes, vérifier que la commande passe (acquittement reçu sous 50 ms, log osax). Désinstaller l'osax, redémarrer Dock : le module fictif log un warning mais ne crash pas le daemon.

**Acceptance Scenarios** :
1. **Given** SIP partial off + osax installée + 3 dylibs. **When** daemon boot. **Then** 3 modules listés en log dans les 200 ms.
2. **Given** un module envoie une commande OSAX. **When** osax la reçoit. **Then** ack revient au module dans les 50 ms (median, p95 < 200 ms).
3. **Given** osax accidentellement supprimée pendant que daemon tourne. **When** un module tente d'envoyer. **Then** `OSAXBridge` détecte la déconnexion, log warning, queue la commande, retry périodique. Aucun crash.

---

### User Story 3 - Utilisateur hybride (modules partiels, certains effets seulement) (Priority: P2)

L'utilisateur Charlie veut juste le focus dimming (RoadieOpacity) et le shadowless, mais pas les animations (qu'il trouve gimmick). Il copie 2 dylibs sur 6, retire le reste.

Au boot, le daemon liste 2 modules. Les autres ne sont jamais chargés. `roadie fx status` reflète l'état réel.

**Why this priority** : confirme que la composition modulaire fonctionne (chacun choisit ses bonbons).

**Independent Test** : copier 2 dylibs spécifiques, vérifier que seules les fonctionnalités correspondantes sont actives, et que les hooks events des autres modules ne sont pas déclenchés.

**Acceptance Scenarios** :
1. **Given** machine SIP partial off + osax + 2 dylibs (shadowless+opacity). **When** daemon boot. **Then** log liste 2 modules.
2. **Given** la même machine. **When** Charlie ouvre une fenêtre. **Then** ombre off (shadowless) et alpha appliqué (opacity), MAIS pas d'animation fade-in (pas de RoadieAnimations).

---

### User Story 4 - Désinstallation propre (Priority: P2)

L'utilisateur Diane veut tester les modules pendant 1 semaine, puis revenir au comportement vanilla. Elle exécute `roadied uninstall-fx` qui :
1. Stoppe le daemon
2. Retire `/Library/ScriptingAdditions/roadied.osax`
3. Recharge les scripting additions Dock pour décharger l'osax
4. Retire `~/.local/lib/roadie/*.dylib`
5. Relance le daemon

Au redémarrage, comportement = vanilla SPEC-003. `roadie fx status` retourne `{modules: []}`.

**Why this priority** : la confiance utilisateur dépend de la réversibilité.

**Independent Test** : installer la famille complète, l'utiliser 1h, désinstaller, vérifier comportement vanilla strict + zéro résidu fichier (pas d'`/Library/ScriptingAdditions/roadied.*` ni `~/.local/lib/roadie/*`).

**Acceptance Scenarios** :
1. **Given** famille complète installée et utilisée. **When** `roadied uninstall-fx` est lancé. **Then** sortie textuelle confirme chaque étape, exit 0.
2. **Given** désinstallation faite. **When** daemon redémarre. **Then** comportement = SPEC-003 vanilla.

---

### Edge Cases

- **SIP fully on + dylibs présents** : daemon log info `FX modules skipped: SIP fully enabled (no point loading)` mais tente quand même les `dlopen`. Si chargement OK, modules s'initialisent mais leur `OSAXBridge` ne peut pas se connecter (osax pas chargée par Dock). Comportement = no-op silencieux, daemon stable. (Pas d'échec dur car Bob peut désactiver SIP plus tard sans devoir restart le daemon.)
- **osax présente mais Dock pas redémarré** : la `roadied.osax` n'est chargée par Dock qu'au démarrage Dock OU sur `osascript -e 'tell app "Dock" to load scripting additions'`. `roadied install-fx` lance cette commande, mais l'utilisateur peut avoir oublié. → `OSAXBridge` log warning explicite « osax installed but not loaded in Dock — try `osascript -e ...` ».
- **Crash module pendant init** : si `dlsym("module_init")` retourne une fonction qui throw, le loader catch, log error, continue avec les autres modules.
- **Crash module pendant runtime** : si `MODULE.handleEvent()` throw, l'EventBus catch, log error, **désinscrit le module** (pas de re-throw). Daemon reste stable.
- **osax crash dans Dock** : Dock se redémarre automatiquement par macOS, perd l'osax. `OSAXBridge` détecte la déconnexion, retry, log les commandes perdues. (Le retry périodique va aboutir si `osascript ... to load scripting additions` est appelé manuellement ou au prochain boot Dock.)
- **2 versions de la même `.dylib`** : si 2 dylibs avec le même `module_name` sont présents, le loader prend le premier scanné, log warning sur le doublon.
- **macOS upgrade casse osax** : prochain boot Dock charge un osax incompatible avec un macOS .X+1. L'osax doit `try { ... } catch` les CGS calls et log error, ne JAMAIS crash Dock.

---

## Requirements

### Functional Requirements — Loader runtime

- **FR-001** : Le daemon `roadied` DOIT au boot scanner `~/.local/lib/roadie/*.dylib` (path configurable via `[fx] dylib_dir`) et tenter `dlopen` + `dlsym("module_init")` sur chaque.
- **FR-002** : Chaque module DOIT exporter une fonction `@_cdecl("module_init")` qui retourne un `UnsafeMutablePointer<FXModuleVTable>` (vtable C-friendly pour franchir la frontière dylib).
- **FR-003** : Le daemon DOIT logger pour chaque module chargé : `name`, `version`, `loaded_at` (timestamp). Format JSON-lines cohérent avec V1.
- **FR-004** : Si `dlopen` échoue (signature, ABI, missing symbol), le daemon DOIT logger error et continuer avec les autres modules — JAMAIS crash.
- **FR-005** : Le daemon DOIT vérifier au boot l'état SIP via `csrutil status` et logger l'état détecté (`enabled` / `disabled-fs` / `disabled-debug` / `fully disabled`). Cet état est purement informatif, NON bloquant pour le chargement (le `dlopen` réussit indépendamment de SIP, c'est l'osax qui dépend de SIP côté Dock).
- **FR-006** : Le daemon NE DOIT JAMAIS appeler directement les APIs `CGSSetWindow*` / `CGSAddWindowsToSpaces` / `CGSRemoveWindowsFromSpaces` etc. depuis son code core (vérifié par `nm` au build).

### Functional Requirements — Protocol FXModule

- **FR-007** : Le protocole `FXModule` DOIT exposer minimalement : `name: String`, `version: String`, `subscribe(bus: EventBus)`, `shutdown()`. Tous les autres détails sont privés au module.
- **FR-008** : Un module NE DOIT PAS importer `RoadieCore` directement — uniquement `RoadieFXCore` qui re-expose strictement le nécessaire (subset minimum d'API publique).
- **FR-009** : Tout module DOIT pouvoir être déchargé proprement via `shutdown()` → cleanup observers, fermer connexions, libérer ressources. Le loader appelle `shutdown()` sur SIGTERM / quit du daemon.

### Functional Requirements — RoadieFXCore

- **FR-010** : `BezierEngine` DOIT calculer `sample(t: Double) -> Double` pour n'importe quelle courbe Bézier 4-points avec précision ≥ 0.005 sur intervalle [0, 1]. Implémentation : table de lookup 256 samples + interpolation linéaire entre samples (suffisant pour 60 FPS).
- **FR-011** : `AnimationLoop` DOIT proposer `register(animation)` / `unregister(animation)` thread-safe et tick à 60-120 FPS via `CVDisplayLink`. Pas de timer manuel.
- **FR-012** : `OSAXBridge` DOIT exposer `send(cmd: OSAXCommand) async -> OSAXResult` non bloquant. Si osax indisponible : queue interne (max 1000 entries), retry périodique 2 s, log warning. Pas de crash, pas de drop silencieux jusqu'à 1000 entries.

### Functional Requirements — Scripting addition (`roadied.osax`)

- **FR-013** : Bundle Cocoa Objective-C++ minimaliste, signé ad-hoc, installé dans `/Library/ScriptingAdditions/roadied.osax/` (path système requis par macOS 14+).
- **FR-014** : Au chargement par Dock, l'osax DOIT démarrer un serveur socket Unix sur `/var/tmp/roadied-osax.sock` (mode 0600, owner = utilisateur courant via `getuid()`).
- **FR-015** : L'osax DOIT exposer minimalement 8 commandes via JSON-lines : `set_alpha`, `set_shadow`, `set_blur`, `set_transform`, `set_level`, `move_window_to_space`, `set_sticky`, `noop`.
- **FR-016** : Chaque commande DOIT être idempotente (les modules peuvent renvoyer en cas de doute). Réponse JSON `{"status": "ok"}` ou `{"status": "error", "code": "<key>"}`.
- **FR-017** : L'osax DOIT s'exécuter sur le main thread Dock pour les CGS calls (sinon Dock crash). Loop accept dans thread dédié, dispatch sur main via `dispatch_async_f(dispatch_get_main_queue(), ...)`.
- **FR-018** : L'osax NE DOIT PAS exposer de commande non listée. Toute commande inconnue → `{"status": "error", "code": "unknown_command"}`.

### Functional Requirements — CLI

- **FR-019** : Nouvelle commande `roadie fx status` retourne JSON `{"sip": "<state>", "osax": "<state>", "modules": [...]}` avec exit 0 si daemon joignable, exit 3 sinon.
- **FR-020** : Nouvelle commande `roadie fx reload` ré-exécute le scan dylib + reconnect osax sans redémarrer le daemon (utile post-install).
- **FR-021** : Scripts `scripts/install-fx.sh` et `scripts/uninstall-fx.sh` livrés en même temps que la commande. Installation = `cp -R osax /Library/ScriptingAdditions/ && osascript -e '...'`. Désinstallation = inverse + cleanup `~/.local/lib/roadie/*.dylib`.

### Functional Requirements — Compatibilité ascendante

- **FR-022** : Si aucun `.dylib` n'est présent ET aucune osax n'est chargée : comportement daemon strictement identique à SPEC-003. Aucun warning anxiogène, aucune feature absente, aucune perf dégradée.
- **FR-023** : Le binaire `roadied` final NE DOIT contenir aucun symbole `CGSSetWindow*` / `CGSAddWindowsToSpaces` linké statiquement. Vérifié via `nm` dans le test SC-008.

### Functional Requirements — Sécurité

- **FR-024** : `roadied.osax` DOIT vérifier que la connexion socket entrante vient de l'utilisateur propriétaire (UID match) avant d'accepter une commande. Refus + log si autre UID. (Pas de root.)
- **FR-025** : Le daemon DOIT vérifier au boot le checksum SHA256 des `.dylib` chargés contre une liste optionnelle `~/.config/roadies/fx-checksums.toml`. Si checksum diffère : log warning explicite mais charge quand même (pas un blocage car les utilisateurs power compilent souvent eux-mêmes).

### Key Entities

- **`FXModuleVTable`** (struct C ABI) : `(name: char*, version: char*, subscribe: fn(bus*) -> void, shutdown: fn() -> void)`. Pointeur retourné par chaque dylib via `module_init`.
- **`FXModule` (Swift protocol)** : wrapper Swift autour de la vtable, manipulé par le loader.
- **`FXRegistry`** : maintient la liste des modules chargés, route les events de l'EventBus vers chaque module subscribe.
- **`OSAXCommand`** : enum Swift `set_alpha(wid, alpha)`, `set_shadow(wid, density)`, etc. Sérialisé en JSON.
- **`OSAXResult`** : `case ok` | `case error(code: String)`.

---

## Success Criteria

### Measurable Outcomes

- **SC-001** : Boot daemon sans aucun module + osax : runtime overhead ≤ **10 ms** ajouté vs SPEC-003 vanilla (mesuré via `time roadied --check`).
- **SC-002** : Boot daemon avec 6 modules + osax : modules tous chargés en moins de **200 ms** après `roadied --daemon` start.
- **SC-003** : `OSAXBridge.send(noop)` round-trip latence : médiane ≤ **20 ms**, p95 ≤ **100 ms**, p99 ≤ **300 ms** (mesuré sur 1000 envois).
- **SC-004** : Aucun crash daemon sur 24 h d'utilisation continue avec 6 modules + activité normale (≥ 50 changements stage, ≥ 20 transitions desktop).
- **SC-005** : Désinstallation `uninstall-fx` laisse zéro résidu fichier, vérifié via `find /Library/ScriptingAdditions ~/.local/lib/roadie -name 'roadied*'` retourne vide.
- **SC-006** : Aucune dépendance runtime nouvelle hors frameworks système macOS (vérifié `otool -L` sur daemon et osax).
- **SC-007** : `nm /usr/local/bin/roadied | grep -E 'CGSSetWindow|CGSAddWindowsToSpaces|CGSSetStickyWindow' | wc -l` retourne **0** (aucun symbole CGS d'écriture linké au daemon core).
- **SC-008** : LOC effectives SPEC-004 ≤ **800 strict** (cible 600). Mesure : `find Sources/RoadieFXCore Sources/roadied/FXLoader.swift osax/ -name '*.swift' -o -name '*.mm' -exec grep -vE '^\s*$|^\s*//' {} + | wc -l`.
- **SC-009** : Compatibilité ascendante stricte : tous les tests SPEC-002 et SPEC-003 passent à l'identique (`swift test`) sans aucune nouvelle dépendance ni régression.

---

## Assumptions

- L'utilisateur (Bob) a déjà désactivé partiellement SIP sur sa machine de dev avant d'attaquer SPEC-004. Pour SPEC-004 cible utilisateur = Alice (vanilla) + Bob (power), pas un public neutre.
- macOS 14 (Sonoma) min, 15 (Sequoia) prioritaire, 26 (Tahoe) supporté. Pas de support Big Sur / Monterey.
- Le pattern scripting addition + injection Dock reste fonctionnel sur les versions cibles (validé par yabai 10 ans, 2 instabilités récentes documentées sur macOS .X majeurs).
- Le daemon roadie ne sera jamais distribué via App Store (incompatible avec scripting additions tiers).
- Les utilisateurs vanilla représentent la majorité (>= 80%). Les utilisateurs power sont une minorité connue par eux-mêmes.

---

## Research Findings

Validés via investigation Phase 0 (cf. `research.md`) :

- **SwiftPM `.dynamicLibrary`** : supporté sur macOS, syntaxe `.library(name: "X", type: .dynamic, targets: ["X"])`. Symboles Swift mangling résolus via `@_cdecl`.
- **dlopen + dlsym Swift** : OK depuis daemon, requiert RPATH `@executable_path/../lib/` ou path absolu, code signing aligné (ad-hoc OK pour usage perso).
- **Scripting addition Path système requis** : `/Library/ScriptingAdditions/` (pas `~/Library/...`) pour macOS 14+ (la version utilisateur n'est plus chargée par Dock).
- **APIs CGS d'écriture** : tous les `CGSSetWindow*` requièrent la connexion WindowServer du **process owner** de la fenêtre cible. Daemon user-space ne peut pas. Dock peut (a une connection master). Donc obligation de passer par scripting addition + injection.
- **Performance 60 FPS** : tenable via osax injectée + main thread Dock (yabai référence 10 ans), à condition de batcher les commandes par tick.

Aucun **red flag** identifié. Approche techniquement éprouvée par yabai depuis une décennie.

---

## Out of Scope (SPEC-004 strict)

- **Aucune fonctionnalité visible utilisateur** : SPEC-004 est purement infrastructure. Les effets visuels sont livrés par SPEC-005 à SPEC-010.
- **Sandboxing / quarantine isolation** des modules : non fait en V1. Si module malveillant chargé, il a tous les droits du daemon. Mitigation = checksum FR-025, doc utilisateur "as-is".
- **Hot-load de nouveaux modules sans restart** : `fx reload` est best-effort, pas garanti pour tous les modules (certains peuvent avoir des observers durables non rechargeables).
- **Distribution Homebrew tap** ou autre : à voir séparément, hors scope SPEC-004.
- **macOS .X+1 future-proofing** : à traiter dans une SPEC séparée si Apple casse à nouveau le pattern scripting addition.
