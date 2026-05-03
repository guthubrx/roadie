# Feature Specification: Animation hide/show ciblée vers la vignette du navrail

**Feature Branch**: `020-rail-targeted-hide-animation`
**Status**: Draft
**Created**: 2026-05-03
**Dependencies**: SPEC-014 (Stage Rail UI), SPEC-018 (stages per-display), SPEC-019 (renderers modulaires)

## Vision

Quand le stage manager masque ou révèle une fenêtre lors d'une transition de stage (manuelle via raccourci, drag-drop dans le rail, ou auto-switch via `stage_follows_focus`), la fenêtre s'anime physiquement **vers la position de sa vignette dans le navrail** plutôt que d'être parquée dans le coin bas-gauche par `HideStrategy.corner`. Effet visuel : la fenêtre semble « se ranger » dans le rail, à l'identique du « minimize to Dock » natif macOS, mais ciblé sur le rectangle exact de la vignette qui la représente.

Lors de la transition inverse (le stage redevient actif), la fenêtre se déplie depuis sa vignette vers son `expectedFrame` initial.

L'effet est **opt-in** via TOML (`[stage_manager.animation].target = "rail"`), avec fallback gracieux sur le comportement actuel (`corner`) si :
- le rail n'est pas en cours d'exécution (binaire `roadie-rail` absent du process tree),
- la wid n'a pas de vignette identifiable côté rail (overflow `+N` du renderer, ou stage non rendu),
- l'IPC de lookup vignette dépasse un timeout court (< 50 ms),
- l'utilisateur a configuré `target = "corner"` (défaut).

Aucune modification du comportement de `HideStrategy.show()` actuel n'est requise au niveau de l'API publique : c'est un **nouveau path** d'animation qui s'insère entre la décision de masquage et l'appel `setBounds` final.

## Pourquoi cette priorité

Le ressenti utilisateur actuel — fenêtres qui glissent vers le coin bas-gauche — est perçu comme « bizarre » et « hors propos » dès qu'on remarque le mouvement (depuis l'introduction de `stage_follows_focus`, l'effet est devenu très visible). Pointer l'animation vers la vignette du rail rend le comportement **lisible** : « ma fenêtre va se ranger là », au lieu de « ma fenêtre disparaît bizarrement ».

C'est aussi un différenciateur fort vs Stage Manager natif d'Apple, qui anime vers le côté écran sans cible précise (pas de zone de dépôt visible).

## Out of scope

- Animation des fenêtres tilées **non masquées** (déplacements lors de relayout BSP) — laisse aux app clientes leur animation native par défaut.
- Animation pendant un drag-drop dans le rail (la wid est déjà à destination quand le drop arrive). Une fonctionnalité « ghost preview qui suit le curseur » serait une SPEC séparée.
- Effet de scale/rotation/3D pendant l'animation. Cette spec ne couvre que **position + size linéairement interpolées** (et optionnellement opacity).
- Impact sur les fenêtres natives non-Cocoa (Electron, Qt). Si l'app cliente refuse `kAXSizeAttribute` ou `kAXPositionAttribute` à mi-animation, le mouvement sera saccadé — best-effort, pas de garantie.

## User Scenarios & Testing *(mandatory)*

### User Story 1 — Animation hide ciblée vers vignette (Priority: P1, MVP)

En tant qu'utilisateur du stage manager, je veux que les fenêtres qui sont masquées lors d'un changement de stage s'animent **vers leur vignette dans le navrail**, pour avoir un retour visuel clair de l'endroit où elles vont.

**Why this priority** : c'est la valeur principale de la feature. Sans ce path d'animation ciblée, on reste sur le comportement actuel (corner-park) que l'utilisateur a explicitement signalé comme indésirable.

**Independent Test** : avec `[stage_manager.animation].target = "rail"`, déclencher un switch de stage (ex: ⌥1 → ⌥2). Les fenêtres du stage 1 s'animent en N frames sur ~250 ms vers le rectangle exact de leur vignette dans le rail. À la fin, elles sont parquées offscreen (comportement final identique au corner-hide).

**Acceptance Scenarios** :
1. **Given** un stage 1 contenant 3 fenêtres (Firefox, iTerm2, Slack) rendues comme vignettes dans le rail (renderer parallax-45), **When** l'utilisateur passe à stage 2 (raccourci ⌥2), **Then** chacune des 3 fenêtres s'anime simultanément depuis sa position d'écran vers le rectangle de sa vignette respective dans le rail (avec shrink de la size en parallèle), pendant `duration_ms` (défaut 250).
2. **Given** la même configuration, **When** l'utilisateur switche entre stages plusieurs fois rapidement (< 100 ms entre deux switch), **Then** les animations sont annulées proprement (les fenêtres sautent à leur position finale offscreen sans rester à mi-trajectoire) et la nouvelle animation prend le relais.
3. **Given** une fenêtre Firefox dans stage 1 qui n'apparaît pas dans la cellule visible (overflow renderer mosaic max 9, indicateur `+N`), **When** stage 1 est masqué, **Then** Firefox s'anime vers le **centre de la cellule du stage** (zone `+N`), pas vers une vignette spécifique.

### User Story 2 — Animation show inverse (Priority: P1)

En tant qu'utilisateur, je veux que la transition réciproque (stage redevient actif) soit aussi animée : les fenêtres se déplient **depuis leur vignette dans le rail** vers leur position cible (`expectedFrame`).

**Why this priority** : sans cette symétrie, on a un effet « rangement » à l'aller mais un « pop instantané » au retour, incohérent. La courbe d'animation peut être différente du hide (easing différent) si l'utilisateur le souhaite.

**Independent Test** : depuis stage 2, switch retour vers stage 1. Les 3 fenêtres précédemment rangées se déplient depuis leur vignette vers leur frame d'origine, avec interpolation position + size sur `duration_ms`.

**Acceptance Scenarios** :
1. **Given** stage 1 masqué (fenêtres parquées par animation hide précédente), **When** l'utilisateur revient sur stage 1 (⌥1), **Then** chaque fenêtre s'anime depuis le rectangle de sa vignette dans le rail vers son `expectedFrame` (récupéré du `WindowRegistry`).
2. **Given** un stage 1 actif au boot du daemon (jamais masqué auparavant), **When** l'utilisateur switche dessus, **Then** aucune animation show n'est nécessaire (les fenêtres sont déjà à leur place — fast path identique au comportement actuel).

### User Story 3 — Configuration durée et courbe d'easing (Priority: P2)

En tant qu'utilisateur power, je veux pouvoir configurer la durée et la courbe d'animation via TOML, pour ajuster la sensation (snappy vs fluide).

**Why this priority** : tuning visuel — pas critique pour le MVP. Une seule paire de defaults raisonnables (250 ms, easeOut) suffit pour un premier livrable.

**Acceptance Scenarios** :
1. **Given** `duration_ms = 0` dans le TOML, **When** un switch de stage déclenche un hide, **Then** les fenêtres sautent instantanément à leur position offscreen, sans animation (équivalent fonctionnel au comportement corner-hide actuel).
2. **Given** `duration_ms = 600`, **When** un switch est déclenché, **Then** l'animation dure 600 ms (à 60 fps = ~36 frames), perceptiblement plus lente.
3. **Given** `easing = "easeIn"`, **When** un switch est déclenché, **Then** l'animation démarre lentement et accélère vers la vignette (vs `easeOut` qui démarre vite et ralentit en arrivant).

### User Story 4 — Fallback gracieux quand le rail n'est pas disponible (Priority: P1)

En tant qu'utilisateur qui peut désactiver le rail (`fx.rail.enabled = false`) ou le quitter manuellement, je veux que le stage manager continue de fonctionner sans animation cassée, en retombant sur le comportement corner-hide actuel.

**Why this priority** : robustesse. Le daemon ne doit jamais bloquer ni crasher si le rail répond pas. Bug-prone path à blinder.

**Acceptance Scenarios** :
1. **Given** `roadie-rail` n'est pas dans le process tree, **When** un switch de stage est déclenché, **Then** le daemon détecte l'absence (timeout IPC < 50 ms ou ENOENT sur socket de query) et utilise `HideStrategy.corner` legacy. Aucune erreur visible utilisateur, juste un log info.
2. **Given** le rail tourne mais une wid donnée n'est pas représentée (renderer `icons-only` qui n'a pas de cellule pour cette wid car overflow), **When** le hide est déclenché pour cette wid, **Then** le daemon utilise corner-hide pour cette wid spécifiquement (les autres wids du même switch animent normalement vers leur vignette).

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001** : le daemon DOIT exposer un nouveau mode de masquage `target` configurable via `[stage_manager.animation].target = "corner" | "rail"`. Default `corner` (compat ascendante stricte).
- **FR-002** : quand `target = "rail"`, le daemon DOIT, avant chaque appel à `HideStrategy.hide(wid)`, requêter le rail via IPC pour obtenir le rectangle (en coordonnées AX) de la vignette correspondante.
- **FR-003** : la requête IPC `rail.vignette_frame` DOIT retourner soit `(x, y, w, h)` AX du rectangle de la vignette, soit `null` si la wid n'est pas représentée dans le rail courant (stage non rendu, renderer non visible, overflow `+N`).
- **FR-004** : si la requête échoue (timeout > 50 ms, socket fermé, rail non lancé) OU retourne `null`, le daemon DOIT fallback sur `HideStrategy.corner` legacy pour cette wid uniquement (les autres wids du même batch ne sont pas affectées).
- **FR-005** : l'animation DOIT interpoler **position ET size** linéairement (ou avec courbe d'easing configurable) entre `state.frame` (point de départ) et le rectangle de vignette (point d'arrivée).
- **FR-006** : à la fin de l'animation, le daemon DOIT envoyer la position finale offscreen (équivalent corner-hide) pour que la fenêtre soit invisible mais reste valide AX. La taille reste celle de la vignette à ce stade (la fenêtre est invisible, sa size n'a plus d'importance UX).
- **FR-007** : l'animation reverse (show) DOIT interpoler depuis le rectangle de vignette vers `expectedFrame` (sauvegardé pré-hide). Même durée et easing que hide par défaut, configurables séparément si besoin (`show_duration_ms`, `show_easing`).
- **FR-008** : pendant l'animation, les events `kAXWindowMovedNotification` et `kAXWindowResizedNotification` générés par les `setBounds` intermédiaires DOIVENT être ignorés par le daemon (anti-feedback) — un flag `inAnimation: Bool` sur `WindowState` ou un set `animatingWids: Set<WindowID>` côté Daemon.
- **FR-009** : si un nouveau switch de stage est déclenché alors qu'une animation est en cours pour une wid, l'animation existante DOIT être annulée (sa wid saute à sa position finale offscreen) et la nouvelle animation démarre depuis cette position. Pas d'accumulation de Tasks d'animation.
- **FR-010** : la durée d'animation DOIT être configurable via `[stage_manager.animation].duration_ms` (entier 0..2000, default 250).
- **FR-011** : la courbe d'easing DOIT être configurable via `[stage_manager.animation].easing = "linear" | "easeIn" | "easeOut" | "easeInOut"` (default `easeOut`).
- **FR-012** : le rail DOIT exposer côté serveur IPC une commande `rail.vignette_frame {wid: <CGWindowID>}` qui retourne soit `{frame: [x, y, w, h]}` (AX coords) soit `{frame: null}`.
- **FR-013** : chaque renderer DOIT pouvoir calculer la position de la vignette d'une wid donnée dans son layout. Pour les renderers à offset (stacked, parallax) : retourne la position du rectangle après application des offsets et scaleEffect. Pour mosaic : la cellule de la grille. Pour hero-preview : le rectangle de la fenêtre hero ou l'icône latérale. Pour icons-only : le rectangle de l'icône.
- **FR-014** : si la wid existe dans le stage mais est en overflow (au-delà de `maxVisible`), le renderer DOIT retourner soit la position de la zone `+N` (mosaic, icons-only), soit le centre de la cellule du stage (stacked, parallax, hero), soit `null` (laisser le daemon fallback corner).
- **FR-015** : l'IPC `rail.vignette_frame` DOIT répondre en moins de 20 ms en moyenne, 50 ms p99. Au-delà, le daemon timeout et fallback corner pour ne pas bloquer le hide.
- **FR-016** : fallback explicite si `[stage_manager.animation].target` absent du TOML utilisateur : behavior = `corner`.

### Non-Functional Requirements

- **NFR-001** : aucun frame drop visible (60 fps minimum) sur un switch de stage avec jusqu'à 8 fenêtres animées simultanément. Animations tournent dans une `Task @MainActor` partagée, pas N tasks concurrentes.
- **NFR-002** : le daemon ne doit jamais bloquer plus de 50 ms sur un appel IPC vers le rail. Timeout strict.
- **NFR-003** : aucune fuite mémoire — les Tasks d'animation s'auto-cleanup à fin ou cancel.
- **NFR-004** : LOC plafond strict pour cette feature : 400 LOC totales (animation engine + IPC client/serveur + renderer hooks). Dépassement → audit HIGH bloquant merge.
- **NFR-005** : compat ascendante stricte — un utilisateur sans la section `[stage_manager.animation]` ne voit aucun changement de comportement (target = "corner" implicite).

## Success Criteria *(mandatory)*

- **SC-001** : `[stage_manager.animation].target = "rail"` activé, switch ⌥1 → ⌥2 sur un stage de 3 fenêtres : toutes les 3 fenêtres s'animent vers leurs vignettes respectives en 250 ms (mesuré à `duration_ms` ± 30 ms).
- **SC-002** : avec rail désactivé, comportement strictement identique à HEAD (zéro régression visuelle ou fonctionnelle sur corner-hide existant).
- **SC-003** : `rail.vignette_frame` IPC répond en p50 ≤ 5 ms, p99 ≤ 50 ms sous charge typique (< 50 wids tracked).
- **SC-004** : `wc -l` cumulé sur `Sources/RoadieStagePlugin/Animation*.swift` + `Sources/RoadieRail/IPC/VignetteFrameProvider*.swift` + ajouts dans renderers ≤ 400 LOC effectives.
- **SC-005** : un switch rapide aller-retour ⌥1 → ⌥2 → ⌥1 en moins de 200 ms ne laisse aucune fenêtre dans un état intermédiaire (toutes finissent à `expectedFrame` ou parkées offscreen, jamais à mi-trajectoire).

## Edge Cases

- **EC-001** : wid détruite (app fermée) pendant l'animation → la Task détecte `registry.get(wid) == nil`, cancel propre, pas de crash.
- **EC-002** : rail crashe pendant un switch → IPC timeout, fallback corner pour les wids restantes du batch.
- **EC-003** : panel rail repositionné (changement display, hot-plug) entre la query `rail.vignette_frame` et l'envoi du `setBounds` final → la position cible reste celle au moment de la query (snapshot). Pas de re-query.
- **EC-004** : utilisateur drag une fenêtre pendant l'animation hide → AX events viennent de l'utilisateur, pas du daemon. La fenêtre s'arrête de s'animer (Task cancel via lookup `inAnimation` qui devient false sur user-initiated move). Comportement à valider en test manuel.
- **EC-005** : multiple displays, fenêtre traverse displays au moment du switch → utiliser le panel rail du display contenant la fenêtre AU MOMENT du hide.
- **EC-006** : opacité de la fenêtre customisée (par un module FX SIP-off) → non géré dans cette spec, l'animation modifie position + size uniquement.
- **EC-007** : `duration_ms = 0` → skip l'animation, snap direct à la position finale (équivalent fonctionnel à `target = "corner"` mais via le path animation, donc même `inAnimation` flag).

## Assumptions

- **A-001** : le rail tourne dans un process séparé du daemon (architecture actuelle). Si jamais on les fusionne, l'IPC devient un appel direct, simplification mais hors scope.
- **A-002** : les apps Cocoa standard respectent `kAXSizeAttribute` et `kAXPositionAttribute` à 60 Hz sans throttling visible. Les apps Electron/Qt peuvent saccader — best-effort.
- **A-003** : `expectedFrame` du `WindowState` est correctement maintenu par `HideStrategy.hide` (déjà vérifié SPEC-013). On peut s'y fier pour le show reverse.
- **A-004** : la position du panel rail est obtenable via `NSScreen` + offset connu du `RailController`. Pas besoin de query AX.

## Dependencies

- **SPEC-014** : Stage Rail UI — fournit le binaire `roadie-rail` et son architecture de panels.
- **SPEC-018** : stages per-display — la query `rail.vignette_frame` doit être scope-aware (cherche dans le bon panel par display).
- **SPEC-019** : renderers modulaires — chaque renderer doit implémenter `vignetteFrame(for: WindowID, in: Cell) -> CGRect?`.

## Décisions à valider AVANT démarrage plan

1. **Direction d'IPC** : daemon → rail (rail expose `vignette_frame`) OU rail → daemon (rail push les positions à chaque relayout) ? **Reco** : daemon → rail (pull-on-demand, plus simple, pas de cache à invalider).
2. **Animation engine** : lerp manuel via `Timer` 60 Hz côté daemon, OU `CADisplayLink` natif, OU Task async sleep ? **Reco** : `Task @MainActor` avec `try await Task.sleep(nanoseconds: ~16ms)` — simple, OS-friendly.
3. **show animation** : duration partagée avec hide, OU configurable séparément ? **Reco** : partagée par défaut, override optionnel via `show_duration_ms`.
4. **Fallback timeout** : 50 ms (FR-015) — assumé non-impactant. À valider en test perf.
5. **Renderer Mosaic overflow** : retourne la zone `+N` (rectangle visible) — confirmer qu'on a l'info côté renderer ou à calculer.
