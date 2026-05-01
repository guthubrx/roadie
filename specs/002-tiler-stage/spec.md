# Feature Specification: Tiler + Stage Manager modulaire (roadies)

**Feature Branch**: `002-tiler-stage`
**Created**: 2026-05-01
**Status**: V1 production-ready (tiling BSP yabai-style first-split, click-to-focus, click-to-raise inter-app via SkyLight private API avec limitation Tahoe documentée, drag-to-adapt drop-based, Stage Manager opérationnel intégré au tiler via LayoutHooks, marges externes asymétriques, intégration BTT complète. Tests d'intégration shell + master-stack runtime + edge cases polish reportés.)
**Dependencies**: SPEC-001 (réutilise l'expérience CGWindowID + AX privé `_AXUIElementGetWindow`)
**Input**: User description: "Tiler + stage manager macOS modulaire en Swift, architecture en couches : daemon AX core, moteur de tiling pluggable (BSP/Master-Stack extensible), stage manager comme plugin opt-in, CLI client. Inspiré yabai et AeroSpace, sans nécessiter SIP désactivé. Click-to-focus fiable comme objectif différenciateur."

---

## User Scenarios & Testing

### User Story 1 - Tiling automatique BSP fiable (Priority: P1) 🎯 MVP

L'utilisateur ouvre plusieurs applications dans son contexte de travail (terminal, éditeur, navigateur, mail). Sans intervention manuelle, l'outil organise automatiquement ces fenêtres en partitions binaires (BSP) sur l'écran : la première occupe tout l'espace, la deuxième divise l'espace existant en deux, la troisième divise l'une des moitiés en deux à nouveau, et ainsi de suite alternativement horizontal/vertical.

**Why this priority** : c'est la valeur centrale du produit. Sans tiling automatique, l'outil n'a aucune raison d'être. C'est aussi le scénario MVP : si le tiling marche sur 1 écran, le projet livre déjà sa promesse de base.

**Independent Test** : ouvrir trois fenêtres Terminal successivement, vérifier visuellement qu'elles s'organisent en partition binaire (50/50 puis re-partition de l'une des moitiés), sans superposition ni espace mort, et que ce résultat est reproductible à chaque ouverture.

**Acceptance Scenarios** :

1. **Given** zéro fenêtre tilée, **When** une nouvelle application est lancée, **Then** sa fenêtre principale occupe 100 % de l'espace utile (moins les gaps).
2. **Given** une fenêtre A occupe l'écran, **When** une fenêtre B est créée et focalisée, **Then** A et B partagent l'espace en deux moitiés (orientation auto selon ratio écran : horizontal si large, vertical si haut), et B est dans la moitié qui était précédemment celle de A.
3. **Given** A et B en split horizontal, B focalisée, **When** une fenêtre C est créée, **Then** B est divisée en deux verticalement, B et C partagent l'ancienne moitié de B.
4. **Given** trois fenêtres tilées, **When** l'utilisateur ferme la fenêtre du milieu, **Then** les deux fenêtres restantes se redistribuent automatiquement pour remplir l'espace libéré sans laisser de zone vide.

---

### User Story 2 - Click-to-focus qui marche partout (Priority: P1) 🎯 différenciateur

L'utilisateur clique avec la souris sur n'importe quelle fenêtre tilée, y compris des applications réputées difficiles (Electron, JetBrains, Slack, Discord, VSCode, Cursor). L'outil détecte ce clic et synchronise immédiatement son état interne de focus avec ce que l'utilisateur voit. Les commandes ultérieures de navigation au clavier (`focus left/right/up/down`) partent de la fenêtre cliquée, pas d'une autre fenêtre.

**Why this priority** : c'est le défaut majeur d'AeroSpace identifié dans la recherche, et la principale raison de construire un nouvel outil. Sans cela, l'expérience est cassée pour tous les utilisateurs d'apps Electron/JetBrains.

**Independent Test** : ouvrir VSCode et un terminal côte à côte, focus initial sur VSCode, cliquer sur le terminal, exécuter `roadie focus right` (alors que l'écran montre que le terminal est à gauche). Si le binaire prend la perspective du terminal pour calculer "right", le test passe.

**Acceptance Scenarios** :

1. **Given** deux fenêtres A (gauche) et B (droite) tilées, focus initial sur A, **When** l'utilisateur clique sur B, **Then** une commande `roadie focus left` (depuis B) ramène le focus sur A et non l'inverse.
2. **Given** une fenêtre Electron (VSCode/Cursor/Slack) tilée, **When** l'utilisateur clique dessus, **Then** dans les 100 ms l'état interne du daemon reflète qu'elle est la fenêtre focalisée.
3. **Given** une fenêtre JetBrains avec un menu contextuel ouvert, **When** l'utilisateur clique sur une autre fenêtre tilée, **Then** le menu se ferme correctement et le focus interne suit la fenêtre cliquée, sans être bloqué par le menu.

---

### User Story 3 - Stages opt-in comme plugin (Priority: P1)

L'utilisateur peut activer un mode "stages" via configuration : il définit N groupes nommés ("dev", "comm", "creative", etc.). Chaque fenêtre est assignée à un groupe. Un seul groupe est actif à un moment donné — les fenêtres des autres groupes sont masquées hors écran (pas minimisées, pour ne pas interférer avec le tiling). La bascule entre groupes est instantanée et le tiling de chaque groupe est préservé.

**Why this priority** : c'est la deuxième moitié du produit, mais le tiler doit fonctionner même sans cette feature. Architecture en plugin : si l'utilisateur n'active pas le stage manager, le tiler tourne seul comme un yabai/AeroSpace standard.

**Independent Test** : avec stage manager activé, créer 2 stages ("dev" et "comm"), assigner 2 fenêtres à chaque, basculer "dev" → "comm" → "dev" et vérifier que dans chaque retour le tiling exact (positions et tailles) est restauré identique.

**Acceptance Scenarios** :

1. **Given** stage manager actif avec 2 stages "dev" et "comm" préremplis chacun de 2 fenêtres tilées, **When** l'utilisateur exécute `roadie stage comm`, **Then** les fenêtres "dev" disparaissent (déplacées hors écran), les fenêtres "comm" apparaissent à leur position tilée préservée.
2. **Given** stage "dev" actif avec un layout BSP sur 3 fenêtres, **When** l'utilisateur bascule sur "comm" puis revient sur "dev", **Then** le layout BSP exact est restauré (chaque fenêtre à sa position et taille initiales).
3. **Given** stage manager désactivé dans la config, **When** l'utilisateur lance le daemon, **Then** seul le tiling automatique fonctionne, les commandes `roadie stage *` retournent erreur "stage manager disabled" sur stderr.

---

### User Story 4 - Moteur de tiling pluggable (Priority: P2)

L'utilisateur peut changer de stratégie de tiling au runtime via configuration ou commande CLI. V1 fournit deux stratégies natives : **BSP** (binaire avec alternance auto) et **Master-Stack** (une fenêtre dominante, les autres en pile latérale). L'architecture permet d'en ajouter d'autres ultérieurement sans toucher au Core.

**Why this priority** : la modularité du tiler est un objectif explicite mais BSP seul couvre 80 % des usages. Master-Stack est un bonus V1.

**Independent Test** : avec 4 fenêtres ouvertes en BSP (4 quadrants), exécuter `roadie tiler master-stack`. Vérifier que la fenêtre focalisée occupe 60 % gauche de l'écran et les 3 autres se partagent les 40 % droits en pile verticale.

**Acceptance Scenarios** :

1. **Given** 3 fenêtres en BSP, **When** l'utilisateur exécute `roadie tiler master-stack`, **Then** la fenêtre focalisée prend la moitié gauche, les 2 autres se partagent la moitié droite en pile verticale.
2. **Given** mode Master-Stack actif, **When** une 4ème fenêtre est créée, **Then** elle rejoint la pile (3 fenêtres dans la pile droite).

---

### Edge Cases

- **Permission Accessibility manquante** : daemon refuse de démarrer, exit code 2, message stderr expliquant la procédure.
- **Apps non-tilables** : popups, dialogs, sheets, menus contextuels (subrole AX `AXDialog`, `AXSheet`, `AXSystemDialog`) sont détectés et exclus du tiling — restent flottants à leur position d'origine.
- **Plein écran natif** (`kAXFullScreenAttribute = true`) : la fenêtre est exclue du tiling tant qu'elle est en mode natif, réintégrée à la sortie.
- **Fenêtre minimisée par l'utilisateur** : retirée du tiling, autres fenêtres redistribuées. Réintégrée si l'utilisateur la dé-minimise.
- **Apps connues problématiques (Zoom, Teams)** : whitelist de bundle IDs avec workarounds (offsets d'un pixel, exclusion sub-windows particulières).
- **Apps lancées avant le daemon** : au démarrage, snapshot de toutes les fenêtres existantes via `CGWindowListCopyWindowInfo`, traitement comme si chacune venait d'être créée, dans l'ordre du `kCGWindowLayer`.
- **Daemon crash inopiné** : les fenêtres restent à leur position courante. Au redémarrage, snapshot et reprise.
- **Multi-monitor** : V1 = single-monitor strict (le daemon gère uniquement `NSScreen.main`). Si plusieurs écrans détectés, warning stderr et seul le principal est géré.
- **Stage manager avec stratégies de tiling multiples** : chaque stage mémorise sa propre stratégie. Bascule restaure aussi la stratégie.
- **CLI invoquée sans daemon** : retourne erreur explicite "roadie daemon not running, start with `roadied`" et exit non nul.

---

## Requirements

### Functional Requirements — Daemon Core

- **FR-001** : Le daemon DOIT s'enregistrer comme observateur AX (`AXObserver`) pour chaque application macOS au lancement, avec abonnement aux notifications `kAXWindowCreatedNotification`, `kAXWindowMovedNotification`, `kAXWindowResizedNotification`, `kAXFocusedWindowChangedNotification`, `kAXUIElementDestroyedNotification`, `kAXApplicationActivatedNotification`.
- **FR-002** : Le daemon DOIT maintenir un registre central des fenêtres (`WindowRegistry`) indexé par `CGWindowID` avec : `pid`, `bundleID`, `title`, `frame`, `isFloating`, `subrole`, `workspaceID`, `stageID` (si plugin actif).
- **FR-003** : Le daemon DOIT détecter le clic souris sur une fenêtre via la combinaison `kAXApplicationActivatedNotification` + `kAXFocusedWindowChangedNotification` et synchroniser son état interne dans les 100 ms.
- **FR-004** : Le daemon DOIT exposer un socket Unix dans `~/.roadies/daemon.sock` pour recevoir les commandes du CLI.
- **FR-005** : Le daemon ne DOIT JAMAIS dépendre d'une API privée **nécessitant SIP désactivé** (scripting addition Dock interdite, etc.). Les APIs privées **stables sans SIP** sont autorisées et utilisées selon le pattern de l'industrie macOS WM (`_AXUIElementGetWindow` cf. SPEC-001 ; `_SLPSSetFrontProcessWithOptions` + `SLPSPostEventRecordTo` du framework `SkyLight` pour le bring-to-front inter-app fiable sur Sonoma+/Sequoia/Tahoe — yabai, AeroSpace, Hammerspoon, Amethyst utilisent toutes ce combo). La distinction est : **SIP intact → OK**, **SIP off requis → interdit**.
- **FR-006** : Le daemon DOIT détecter les apps lancées avant lui via `NSWorkspace.runningApplications` et `CGWindowListCopyWindowInfo` au démarrage et les enregistrer comme si elles venaient d'être créées.

### Functional Requirements — Tiler

- **FR-007** : Le tiler DOIT exposer un protocole Swift `Tiler` avec les méthodes `layout(rect, windows) -> [WindowID: CGRect]`, `insertWindow(id, after:)`, `removeWindow(id)`, `moveWindow(id, direction:)`, `resizeWindow(id, direction:, delta:)`.
- **FR-008** : Une implémentation BSP DOIT être fournie comme stratégie par défaut, avec partitions binaires alternées horizontalement/verticalement et insertion d'une nouvelle fenêtre à côté de la fenêtre focalisée.
- **FR-009** : Une implémentation Master-Stack DOIT être fournie comme stratégie alternative : la fenêtre focalisée occupe le ratio configuré (60 % par défaut) à gauche, les autres se répartissent uniformément en pile à droite.
- **FR-010** : Le changement de stratégie au runtime via `roadie tiler <strategy>` DOIT recalculer les frames immédiatement et appliquer le nouveau layout sans intervention utilisateur.
- **FR-011** : Le calcul des frames DOIT respecter les gaps configurés (espace inter-fenêtres `gaps_inner` et marges écran). Les marges externes DOIVENT supporter à la fois un mode **uniforme** (`gaps_outer = N`) et un **override par côté** optionnel (`gaps_outer_top|bottom|left|right`, fallback sur `gaps_outer`) pour permettre de réserver de la place au Dock, à la barre de menu, etc.
- **FR-011a** : Au bootstrap, le LayoutEngine DOIT seeder le rect d'écran utilisable AVANT toute insertion (`setScreenRect`) afin que la 1ère insertion BSP dispose des `lastFrame` nécessaires à l'auto-orientation par aspect ratio (sinon retombe sur `parent.opposite`, donnant un split vertical sur écran 16/9 au lieu de horizontal).
- **FR-011b** : Quand l'utilisateur drag-resize ou drag-move une fenêtre tilée à la souris, le tiler DOIT adapter le tree au mouseUp (drop-based, pas pendant le drag) en transférant le delta pixel par edge → `adaptiveWeight` aux siblings appropriés. Anti-feedback-loop via timestamp `lastApply` qui ignore les notifs AX réflexes.

### Functional Requirements — Stage Manager Plugin

- **FR-012** : Le stage manager DOIT être un module séparé du tiler qui s'abonne aux events Core via une interface explicite.
- **FR-013** : Le stage manager peut être activé ou désactivé via `roadies.toml` clé `stage_manager.enabled = true|false`. Si désactivé, les commandes `roadie stage *` retournent erreur sans modifier l'état.
- **FR-014** : Quand actif, l'utilisateur DOIT pouvoir définir N stages nommés (`stages.names = ["dev", "comm", ...]`).
- **FR-015** : Une fenêtre est assignée à un stage via `roadie stage assign <name>` (assigne la frontmost). Une fenêtre = exactement un stage.
- **FR-016** : La bascule de stage via `roadie stage <name>` DOIT masquer les fenêtres des autres stages et restaurer celles du stage cible. Pour les fenêtres **tilées** : `LayoutEngine.setLeafVisible(wid, false)` (le tiler skip au layout, espace redistribué) + hide AX physique offscreen ; pour les **flottantes** : seulement hide AX. Position offscreen : reproduction littérale de la formule AeroSpace `MacWindow.hideInCorner(.bottomLeftCorner)` = `visibleRect.bottomLeftCorner + (1, -1) + (-windowWidth, 0)` (positionnement simultané hors champ en x ET en y pour évader le clamp macOS qui sinon laisse 40 px visibles près du bord). Au switch, `applyLayout()` propage les changements de visibilité.
- **FR-017** : Avant de masquer une fenêtre, le stage manager DOIT capturer sa frame courante pour pouvoir la restaurer fidèlement au prochain retour.
- **FR-018** : Pour éviter que les fenêtres masquées (hors écran) capturent le focus via Cmd+Tab, le stage manager DOIT optionnellement appeler `kAXMinimizedAttribute = true` sur celles-ci (configurable, off par défaut).

### Functional Requirements — Click-to-raise inter-app

- **FR-018a** : Le daemon DOIT fournir un click-to-raise universel : tout `leftMouseDown` global (NSEvent monitor) sur une fenêtre identifiée déclenche `kAXRaiseAction` + bring-to-front via SkyLight private API (`_SLPSSetFrontProcessWithOptions` mode 0x200 + synthetic mouseDown/mouseUp event encodé byte-par-byte) + `NSRunningApplication.activate(.activateIgnoringOtherApps)`. Différenciateur vs AeroSpace.
- **FR-018b** : Le hook NSEvent global nécessite la permission **Input Monitoring** (`kTCCServiceListenEvent`). Le daemon DOIT appeler `IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)` au démarrage de `MouseRaiser` pour forcer la prompt système (sinon `addGlobalMonitorForEvents` fail silencieusement).
- **FR-018c** : Le daemon DOIT lancer son runloop via `NSApplication.shared.run()` (avec `setActivationPolicy(.accessory)` + `LSUIElement=true` dans le bundle pour rester invisible) et non `RunLoop.main.run()`, sinon `addGlobalMonitorForEvents` ne reçoit aucun event.
- **FR-018d** : La fiabilité du click-to-raise inter-app sur macOS Sonoma+/Sequoia/Tahoe est best-effort (Apple a serré le yieldActivation pattern). Limitation documentée dans README. AeroSpace a la même limitation par design (pas de scripting addition Dock = pas de SIP désactivé).

### Functional Requirements — CLI

- **FR-019** : Le binaire CLI `roadie` DOIT communiquer avec le daemon via le socket Unix et afficher les réponses sur stdout.
- **FR-020** : Les commandes CLI DOIVENT couvrir au minimum : `focus <direction>`, `move <direction>`, `resize <direction> <delta>`, `tiler <strategy>`, `stage <name>`, `stage assign <name>`, `stage list`, `windows list`, `daemon status`, `daemon reload`.
- **FR-021** : Si le daemon n'est pas en cours d'exécution, le CLI DOIT exit non nul avec message stderr expliquant comment le démarrer.

### Functional Requirements — Configuration

- **FR-022** : Le daemon DOIT lire sa configuration depuis `~/.config/roadies/roadies.toml`. Si absent, comportement avec valeurs par défaut documentées.
- **FR-023** : Le rechargement à chaud via `roadie daemon reload` DOIT appliquer la nouvelle config sans redémarrer le daemon.

### Key Entities

- **WindowState** : `(cgWindowID, pid, bundleID, title, frame, subrole, isFloating, isMinimized, workspaceID, stageID?)` — état canonique d'une fenêtre dans le daemon.
- **TreeNode** : noeud N-aire de l'arbre de tiling, peut être un container (avec orientation horizontal/vertical et N enfants) ou une feuille (référence WindowID). `adaptiveWeight` pour les ratios variables.
- **Workspace** : racine d'un arbre TreeNode, lié à un `displayID`. V1 = un workspace unique sur l'écran principal.
- **Stage** : groupe nommé de WindowIDs, avec stratégie de tiling courante. Persisté dans `~/.config/roadies/stages/<name>.toml`.
- **TilerStrategy** : enum (`bsp`, `masterStack`, ...) — sélecteur de l'implémentation `Tiler`.
- **Command** : représentation typée d'une commande CLI (`Focus(.left)`, `Move(.right)`, `StageSwitch("dev")`, ...) sérialisée sur le socket.

---

## Success Criteria

### Measurable Outcomes

- **SC-001** : Une nouvelle fenêtre est tilée et visible à sa position correcte en moins de 200 ms après son `kAXWindowCreatedNotification`.
- **SC-002** : Un clic souris sur une fenêtre Electron (VSCode/Slack/Cursor) synchronise l'état focus interne du daemon dans les 100 ms.
- **SC-003** : Une bascule de stage avec 5 fenêtres par stage termine en moins de 500 ms.
- **SC-004** : Le binaire daemon compilé occupe moins de 5 MB ; le binaire CLI moins de 500 KB.
- **SC-005** : Aucune dépendance non-système au runtime : `otool -L roadied` ne montre que des libs `/usr/lib/` et `/System/Library/`.
- **SC-006** : Le code source total Swift est inférieur à 4 000 lignes effectives (sans commentaires ni blanches).
- **SC-007** : Le daemon survit 24 heures sans crash sous usage normal.
- **SC-008** : Sur 100 cycles de bascule de stage avec 5 fenêtres par stage, zéro fuite mémoire.
- **SC-009** : Sur 50 tests de click-to-focus sur 10 apps différentes (mix Electron, JetBrains, AppKit, Catalyst, Java), 100 % de synchronisation correcte.
- **SC-010** : L'utilisateur peut installer, configurer ses stages et basculer entre eux en moins de 10 minutes après le clone.

---

## Assumptions

- macOS 14 (Sonoma) ou ultérieur, testé prioritairement sur Sequoia (15) et Tahoe (26).
- L'utilisateur peut accorder la permission Accessibility au binaire daemon.
- L'utilisateur câble lui-même ses raccourcis clavier via Karabiner-Elements, BetterTouchTool, skhd ou autre — le daemon n'inclut pas de gestion de hotkeys (volontairement, principe Unix).
- Single-monitor strict pour V1. Multi-monitor reporté en V2.
- La stratégie de masquage hors écran reste compatible avec les futures évolutions macOS — l'expérience AeroSpace prouve sa stabilité depuis 2 ans.
- Le parser TOML est externe (dépendance acceptée à ce jour, à internaliser en V2 si besoin).

---

## Research Findings (extrait)

L'étude comparative yabai (C, ~30 KLOC) et AeroSpace (Swift, ~15 KLOC) a produit les 3 décisions architecturales suivantes (détails dans `research.md`) :

1. **AX par app, sans SkyLight ni SIP** — un thread `CFRunLoop` par process avec `AXObserver` + `Task { @MainActor }`. Ajout de `kAXApplicationActivatedNotification` (absent d'AeroSpace) pour fixer le bug click-to-focus Electron/JetBrains.
2. **Arbre N-aire avec `adaptiveWeight`** plutôt que BSP binaire pur — exprime nativement Master-Stack et facilite les futures stratégies de tiling.
3. **Masquage en coin** (stratégie AeroSpace) avec `setNativeMinimized` optionnel comme garde-fou Cmd+Tab — combine la simplicité d'AeroSpace avec une mitigation absente de l'original.

Pièges majeurs à éviter :

- yabai : dépendance SIP, `SLS*` privés fragiles, BSP binaire limitant pour Master-Stack.
- AeroSpace : click-to-focus non synchrone (corrigé via FR-003), race conditions au démarrage, `// todo` non tracés en prod.
- Communs : popups/dialogs à exclure (subrole), apps Zoom/Teams nécessitant whitelist, fenêtres au démarrage à snapshotter dans l'ordre `kCGWindowLayer`.

---

## Out of Scope (V1)

- **Multi-monitor** : reporté en V2 (architecture compatible, mais V1 = écran principal seul).
- **Hotkeys intégrées** : non, l'utilisateur câble via outils externes.
- **GUI / menu bar** : non, projet 100 % CLI suckless.
- **Spaces macOS** : non utilisés, on reste sur l'espace courant uniquement.
- **Animations de transition** : aucune (suckless = pas de fioritures).
- **Tiling fractal / spiral / mansory** : non, V1 = BSP + Master-Stack uniquement.
- **Floating windows persistents avec règles** : non, une fenêtre est tilée ou exclue automatiquement (par subrole).
- **Synchronisation cloud, multi-machine, profils** : non.
- **Compatibilité avec yabai ou AeroSpace en parallèle** : non — l'utilisateur quitte les autres avant de lancer roadied.
- **Plugins externes (tiers)** : V1 expose une API interne pour StagePlugin mais pas un système de plugins tiers chargeables.
