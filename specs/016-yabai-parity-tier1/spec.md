# Feature Specification: Yabai-parity tier-1 (catégorie A complète)

**Feature Branch**: `016-yabai-parity-tier1`
**Created**: 2026-05-02
**Status**: Draft
**Dependencies**: SPEC-002 (daemon WindowRegistry, LayoutEngine, EventBus), SPEC-011 (virtual desktops — pour `space=N` rules), SPEC-012 (multi-display — pour `display=N` rules), SPEC-015 (mouse modifier — pour cohabitation `focus_follows_mouse`)
**Input**: « Combler les 6 gaps majeurs identifiés dans ADR-006 catégorie A : (A1) règles déclaratives `[[rules]]`, (A2) signals shell `[[signals]]`, (A3) stack mode local, (A4) insertion directionnelle `--insert`, (A5) `--swap`, (A6) `focus_follows_mouse` / `mouse_follows_focus`. Architecture intégrée à RoadieCore. »

## User Scenarios & Testing *(mandatory)*

### User Story 1 — Swap + focus follows mouse (P1, MVP)

**US1a — Swap deux fenêtres sans toucher à l'arbre**

L'utilisateur a son layout BSP comme il l'aime. Il veut juste **échanger** la fenêtre focus avec sa voisine de gauche, en gardant exactement la même structure d'arbre (ratios, splits, parents). C'est différent de `move` qui réorganise l'arbre.

**Why this priority** : le pattern `swap_window_left/right/up/down` est dans yabai, AeroSpace, i3, sway. C'est le geste le plus fréquent quand on veut "envoyer la fenêtre de droite à gauche" sans repenser le layout. Aujourd'hui on perd la structure dès qu'on touche à `move`.

**Independent Test** : layout BSP avec 3 fenêtres `[A | B / C]`. Focus B. `roadie window swap left` → `[B | A / C]` — A et B échangées, le split horizontal A/C reste, les ratios sont préservés.

**Acceptance Scenarios** :

1. **Given** un layout BSP `[A | B]`, focus sur B, **When** `roadie window swap left`, **Then** `[B | A]`. Focus reste sur B. Ratio préservé.
2. **Given** un layout `[A | (B / C)]`, focus sur A, **When** `roadie window swap right`, **Then** A est échangée avec sa voisine directionnelle "right" (ici B, première feuille trouvée vers la droite). Le sous-arbre `(_ / C)` reste intact.
3. **Given** focus sur la seule fenêtre du tile, **When** swap, **Then** no-op + warning log.
4. **Given** focus floating, **When** swap, **Then** no-op + warning log.
5. **Given** swap inter-display, **When** la voisine "right" est sur le display 2, **Then** échange OK, les fenêtres adoptent les frames cibles dans leurs trees respectifs.

---

**US1b — `focus_follows_mouse` : focus la fenêtre sous le curseur**

L'utilisateur active `focus_follows_mouse = true` dans `roadies.toml`. Quand il déplace son curseur sur une autre fenêtre **sans cliquer**, le focus migre vers cette fenêtre après un court délai d'idle (anti-jitter).

**Why this priority** : pattern fondateur des WMs Linux (i3, sway, bspwm). yabai `focus_follows_mouse autofocus|autoraise|off`. Réduit drastiquement les clics dans une journée de travail.

**Independent Test** : `[mouse] focus_follows_mouse = "autofocus"` + reload. Bouger le curseur sur une fenêtre voisine sans cliquer → après ~200ms, cette fenêtre devient focused (titre s'éclaircit, border switch via SPEC-008).

**Acceptance Scenarios** :

1. **Given** `focus_follows_mouse = "autofocus"`, **When** curseur immobile pendant 200ms sur une fenêtre non-focused, **Then** focus migre. Pas de raise (la fenêtre ne passe pas devant les autres).
2. **Given** `focus_follows_mouse = "autoraise"`, **When** idem, **Then** focus + raise (la fenêtre passe devant).
3. **Given** `focus_follows_mouse = "off"`, **When** idem, **Then** aucun changement (comportement actuel).
4. **Given** curseur en mouvement continu (jitter), **When** survol furtif d'une fenêtre, **Then** focus ne migre pas tant que le curseur ne s'est pas immobilisé `idle_threshold_ms` (200 par défaut).
5. **Given** survol du Dock, Menu Bar, ou desktop, **When** idle, **Then** aucun changement de focus (ces zones ne comptent pas comme fenêtre).
6. **Given** drag actif (SPEC-015 mouse modifier), **When** mouvement, **Then** `focus_follows_mouse` est suspendu jusqu'au release.

---

**US1c — `mouse_follows_focus` : téléporter le curseur sur le focus**

L'utilisateur active `mouse_follows_focus = true`. Quand il change de focus via clavier (`roadie focus right`, ou un BTT shortcut), le curseur se téléporte au centre de la nouvelle fenêtre focused.

**Why this priority** : indispensable quand `focus_follows_mouse` est aussi actif (sinon le curseur reste sur l'ancienne fenêtre et le focus sautille bizarrement). Pattern yabai standard.

**Independent Test** : `mouse_follows_focus = true`. Focus sur fenêtre A à l'écran 1. `roadie focus right` → curseur instantané au centre de la fenêtre devenue focused.

**Acceptance Scenarios** :

1. **Given** `mouse_follows_focus = true`, **When** focus change via commande clavier (focus, swap, warp, window.display, desktop.focus, stage.switch), **Then** curseur téléporté au centre de la nouvelle fenêtre focused.
2. **Given** `mouse_follows_focus = false`, **When** idem, **Then** curseur ne bouge pas.
3. **Given** focus change via clic souris, **When** clic, **Then** curseur ne se téléporte pas (il est déjà sur la fenêtre par construction).
4. **Given** focus passe sur une fenêtre cachée (stage off, desktop off-screen), **When** la fenêtre redevient visible et focused, **Then** curseur téléporté à sa nouvelle position visible.

---

### User Story 2 — Système de règles déclaratif (P1)

L'utilisateur veut écrire dans `roadies.toml` des **règles** qui s'appliquent automatiquement à certaines apps : « 1Password mini ne doit jamais être tilé », « Slack toujours sur desktop 5 », « Activity Monitor en floating + sticky ». Aujourd'hui chaque cas exige un script externe ou une intervention manuelle.

**Why this priority** : sans règles, chaque app récalcitrante (dialogs Adobe, Activity Monitor, 1Password mini, panneaux flottants Sketch, popups WhatsApp, etc.) ralentit le daily. Pattern yabai `yabai -m rule --add app="X" manage=off`. C'est le plus gros impact qualité de vie de la catégorie A.

**Independent Test** : ajouter dans toml :
```toml
[[rules]]
app = "1Password"
title = "1Password mini"
manage = "off"
```
Ouvrir 1Password mini → la fenêtre n'entre pas dans le tile BSP, reste à sa position d'origine.

**Acceptance Scenarios** :

1. **Given** rule `app="Activity Monitor", manage="off"`, **When** Activity Monitor s'ouvre, **Then** la fenêtre est marquée non-tileable (équivalent `tiling.reserve` automatique). Aucune entrée dans le tree BSP.
2. **Given** rule `app="Slack", space=5`, **When** Slack s'ouvre, **Then** la fenêtre est immédiatement déplacée vers le desktop virtuel 5.
3. **Given** rule `app="Activity Monitor", float=true, sticky=true`, **When** la fenêtre s'ouvre, **Then** elle est floating + visible sur tous les desktops (sticky).
4. **Given** rule `app="WezTerm", display=2`, **When** ouverture sur display 1, **Then** la fenêtre migre vers display 2 et entre dans son tree.
5. **Given** rule `app="Calculator", grid="4:4:3:3:1:1"` (grille 4x4, place coin bas-droit, taille 1x1), **When** ouverture, **Then** fenêtre placée dans le quart bas-droit du visibleFrame.
6. **Given** 2 rules qui matchent la même fenêtre, **When** application, **Then** **première rule wins** (top-down dans le toml). Les rules suivantes sont skippées avec log debug.
7. **Given** rule avec `title` regex (ex. `title = "^Settings$"`), **When** match, **Then** application uniquement aux fenêtres dont le titre matche le regex.
8. **Given** rule invalide (champ inconnu, regex cassé), **When** parser, **Then** rule skip + log warn, autres rules continuent.
9. **Given** rule `app="X", manage="off"` puis `roadie tiling.reserve <wid> false` manuel, **When** override CLI, **Then** la commande CLI gagne pour la session, la rule s'appliquera à la prochaine ouverture.
10. **Given** modification du toml + `roadie daemon reload`, **When** rules rechargées, **Then** s'appliquent aux **nouvelles** fenêtres (les fenêtres déjà ouvertes ne sont pas re-évaluées sauf via `roadie rules apply --all` opt-in).

---

### User Story 3 — Signals utilisateur shell (P1)

L'utilisateur veut **réagir aux événements** du daemon depuis ses propres scripts shell, sans devoir polling `roadie events --follow`. Pattern yabai `yabai -m signal --add event=window_created action="..."`.

**Why this priority** : déverrouille l'écosystème user. Permet : notification quand une app cible s'ouvre, log dans un fichier, déclenchement d'un script de mise en forme spécifique, lancement d'un automator par display switch, etc. Sans ça, chaque automatisation user nécessite un wrapper Python qui parse le stream events.

**Independent Test** : ajouter dans toml :
```toml
[[signals]]
event = "window_focused"
action = "echo $ROADIE_WINDOW_BUNDLE >> /tmp/focus.log"
```
Reload daemon. Cliquer sur 3 fenêtres différentes → `/tmp/focus.log` contient 3 bundles.

**Acceptance Scenarios** :

1. **Given** signal `event="window_created", action="..."`, **When** une fenêtre se crée, **Then** la commande shell est exécutée avec env vars `ROADIE_WINDOW_ID`, `ROADIE_WINDOW_PID`, `ROADIE_WINDOW_BUNDLE`, `ROADIE_WINDOW_TITLE`, `ROADIE_WINDOW_FRAME`.
2. **Given** signal sans filtre `app`, **When** event sur n'importe quelle fenêtre, **Then** action exécutée pour chaque event.
3. **Given** signal avec `app = "Slack"`, **When** event sur fenêtre Slack uniquement, **Then** action exécutée. Autres apps : skip silencieux.
4. **Given** event `space_changed`, **When** switch de desktop virtuel, **Then** action exécutée avec env vars `ROADIE_SPACE_FROM`, `ROADIE_SPACE_TO`.
5. **Given** action shell qui prend > 5s, **When** exec, **Then** processus tué (timeout) + log warn. Les signaux suivants ne sont pas bloqués (exec async).
6. **Given** action shell qui retourne exit code != 0, **When** exec, **Then** log warn avec stderr capturé. Comportement reste : continuer.
7. **Given** signal mal formé (event inconnu, action vide), **When** parser, **Then** skip + log warn. Autres signals continuent.
8. **Given** 100+ events/seconde (rafale), **When** signals matchent, **Then** dégradation gracieuse : queue interne bornée à 1000, drop les plus anciens si saturée + log warn.
9. **Given** event `mouse_dropped` (drag-and-drop SPEC-015), **When** drop sur un autre display, **Then** action exécutée avec `ROADIE_DROP_DISPLAY`, `ROADIE_DROP_FRAME`.

**Liste des events supportés** (correspond à l'EventBus existant) :
- `window_created`, `window_destroyed`, `window_focused`, `window_moved`, `window_resized`, `window_title_changed`
- `application_launched`, `application_terminated`, `application_front_switched`, `application_visible`, `application_hidden`
- `space_changed`, `space_created`, `space_destroyed`
- `display_added`, `display_removed`, `display_changed`
- `mouse_dropped`
- `stage_switched`, `stage_created`, `stage_destroyed` (spécifique roadie)

---

### User Story 4 — Insertion directionnelle (P2)

L'utilisateur veut **pré-décider** où sa prochaine fenêtre ouverte va se splitter. Sans ça, BSP coupe toujours selon l'algo split-largest (ou la dernière direction utilisée), ce qui n'est pas toujours ce qu'on veut.

**Why this priority** : pattern yabai `yabai -m window --insert east` puis ouverture d'une nouvelle fenêtre → split à l'est. Indispensable pour construire des layouts précis sans drag-and-drop manuel après coup.

**Independent Test** : focus fenêtre A. `roadie window insert south`. Ouvrir une nouvelle fenêtre → split horizontal A en haut, nouvelle fenêtre en bas.

**Acceptance Scenarios** :

1. **Given** focus sur A + `roadie window insert east`, **When** une nouvelle fenêtre B est créée, **Then** split vertical à droite : `[A | B]`. Le hint est consommé.
2. **Given** focus sur A + `roadie window insert south`, **When** B créée, **Then** split horizontal en bas : `[A / B]`.
3. **Given** focus sur A + `roadie window insert stack`, **When** B créée, **Then** B empilée sur A (cf. US5 stack mode). Si US5 pas implémenté → fallback split par défaut + log info.
4. **Given** hint posé puis 2 minutes sans nouvelle fenêtre, **When** timeout, **Then** hint expire silencieusement. Comportement default reprend.
5. **Given** hint posé, **When** focus change avant qu'une fenêtre soit créée, **Then** hint reste attaché à la fenêtre originale (la cible du split).
6. **Given** hint posé sur fenêtre A floating, **When** B créée, **Then** B prend la place attendue mais en **floating** également (cohérence : si A n'est pas dans le tree, B n'y entre pas non plus).
7. **Given** `roadie window insert <direction>` sans cible focused, **When** invocation, **Then** error `no focused window`.
8. **Given** indicateur visuel optionnel (config `[insert] show_hint = true`), **When** hint actif, **Then** un fin overlay coloré s'affiche sur le bord cible de la fenêtre A pour rappeler la direction. Disparaît à la consommation/expiration.

---

### User Story 5 — Stack mode local (P2, **scope-out possible vers SPEC-017**)

L'utilisateur veut **empiler** plusieurs fenêtres dans le même nœud de l'arbre, et naviguer entre elles via clavier. Pattern yabai `--insert stack` + `--focus stack.next/prev`, et i3/sway tabbed/stacking layouts.

**Why this priority** : utile pour grouper logiquement plusieurs fenêtres qui occupent la même "case" (ex. 3 onglets WezTerm dans un même panneau). Mais c'est le user story le plus invasif (touche LayoutEngine, model nœud, rendu indicateur). Si effort > 8 sessions à l'analyse Phase 2 plan : **scope-out vers SPEC-017** dédiée.

**Independent Test** : focus A + `roadie window insert stack` + ouvrir B et C → A, B, C empilées dans le même slot. Visuellement seule la dernière (C) est visible. `roadie focus stack.next` → A devient visible. Cycle.

**Acceptance Scenarios** :

1. **Given** A floating-tilée seule, **When** `insert stack` + ouvrir B, **Then** B empilée sur A. Frame B = frame A. A cachée derrière (offscreen ou hidden, pas détruite).
2. **Given** stack [A, B, C], visible = C, **When** `roadie focus stack.next`, **Then** B visible, focus sur B. Cycle wrap-around après le dernier.
3. **Given** stack [A, B], **When** layout space passe en `bsp` standard, **Then** stack se "déballe" : A et B redeviennent feuilles séparées. Layout réajusté.
4. **Given** `roadie tiler.set stack` au niveau d'un space, **When** activation, **Then** toutes les fenêtres du space sont empilées dans un seul nœud root.
5. **Given** `roadie window toggle split` sur un nœud parent split V, **When** invocation, **Then** le split bascule en H. Frames recalculées.
6. **Given** stack [A, B, C] et A est minimisée (close window), **When** A disparaît, **Then** stack devient [B, C], visible = next ou prev selon position.
7. **Given** indicateur visuel stack (config `[stack] show_indicator = true`), **When** stack actif, **Then** un mini-rail vertical (3 puces) s'affiche en coin de la fenêtre visible, position courante highlight.
8. **Given** US5 scope-out vers SPEC-017, **When** Phase 2 plan détermine effort > 8 sessions, **Then** US5 est retirée de SPEC-016, `--insert stack` (US4) tombe sur fallback split, US5 est tracée dans SPEC-017 placeholder.

---

### Edge Cases

**Génériques** :
- **Daemon redémarre** : règles + signals rechargés au boot, hints insert sont perdus (état runtime non persisté), focus_follows_mouse reprend selon config.
- **Config TOML invalide** : daemon démarre quand même, sections cassées sont skippées avec warning, sections valides s'appliquent.
- **Reload pendant qu'une action signal tourne** : action en cours termine, prochain trigger utilisera la nouvelle config.

**A1 (rules)** :
- Rule `app=".*", manage="off"` (regex match-all) → Anti-pattern dangereux : detect au parsing, log error explicit "rule too broad would disable tiling for all apps", rule skippée.
- Rule cible une app pas encore lancée → rule en attente, s'applique à la première window de cette app.
- Window change de title après création (ex. browser tab switch) → re-évaluation des rules `title=...` opt-in via `[[rules]] reapply_on_title_change = true`. Default off (perf).

**A2 (signals)** :
- Action shell crée une fenêtre → ne pas générer un signal en cascade infini (filtre re-entrancy via flag `_inside_signal`).
- 1000+ rules ou 1000+ signals → perf check : O(n) match acceptable jusqu'à n=500. Au-delà, recommander structure groupée (warning au parser).
- Action référence une env var inexistante → exec quand même, var = "" string.

**A5 (swap)** :
- Swap d'une fenêtre tilée avec une fenêtre floating → no-op + warning (mismatch de domaine, comportement non défini).
- Swap dans un stack (US5) → swap les positions dans la liste du stack, pas de changement visuel sauf si l'une des deux était la "visible".

**A6 (focus follows mouse)** :
- Mode présentation (clavier seul, souris en idle long) → si `mouse_follows_focus = true`, l'utilisateur ne voit pas le curseur bouger entre 2 commandes, c'est OK (effet attendu).
- Multi-display avec curseur sur display 2 mais focus clavier sur display 1 → `mouse_follows_focus` téléporte le curseur sur display 1 sur la fenêtre focus.
- Modale système ouverte (Save dialog Apple) → `focus_follows_mouse` suspendu (la modale capture l'event handling), reprend au close.

**A4 (insert hint)** :
- Hint posé puis fenêtre cible fermée → hint orphelin, supprimé silencieusement.
- Hint posé puis tiler change de strategy (BSP → masterStack) → hint annulé, log info.

## Requirements *(mandatory)*

### Functional Requirements

**A1 — Système de règles** :

- **FR-A1-01** : Le daemon DOIT charger une section `[[rules]]` du TOML au boot et au `daemon reload`.
- **FR-A1-02** : Une rule DOIT supporter au minimum les champs : `app` (string, exact match ou regex), `title` (regex, optionnel), `manage` (`on`/`off`), `float` (bool), `sticky` (bool), `space` (int 1..16), `display` (int), `grid` (string `"R:C:r:c:w:h"`).
- **FR-A1-03** : Le daemon DOIT évaluer les rules à la création de chaque fenêtre (event `window_created`), dans l'ordre top-down du toml, **première match wins**.
- **FR-A1-04** : Les rules invalides (regex cassé, champ inconnu, valeur hors plage) DOIVENT être skippées avec log warn explicite, sans bloquer les autres rules.
- **FR-A1-05** : Une nouvelle commande CLI `roadie rules list` DOIT lister les rules chargées avec un index. `roadie rules apply --all` DOIT re-évaluer les rules sur toutes les fenêtres existantes (opt-in pour éviter side effects au reload).
- **FR-A1-06** : La rule `manage=off` DOIT marquer la fenêtre `isTileable = false` dans WindowRegistry (équivalent de `tiling.reserve` automatisé).
- **FR-A1-07** : La rule `space=N` DOIT déclencher un `desktop.move` interne vers le desktop N immédiatement après détection.
- **FR-A1-08** : Le pattern dangereux `app=".*"` (anti-pattern match-all) DOIT être rejeté au parsing.

**A2 — Signals** :

- **FR-A2-01** : Le daemon DOIT charger une section `[[signals]]` du TOML au boot et au reload.
- **FR-A2-02** : Un signal DOIT supporter les champs : `event` (string parmi liste fermée), `action` (string shell), `app` (filtre optionnel exact ou regex), `title` (filtre optionnel regex).
- **FR-A2-03** : L'EventBus interne DOIT propager les events listés (US3) vers le SignalDispatcher.
- **FR-A2-04** : L'action shell DOIT être exécutée via `/bin/sh -c <action>` en process child, **async** (ne bloque pas le daemon).
- **FR-A2-05** : Le child process DOIT recevoir des env vars contextuelles préfixées `ROADIE_` selon l'event (cf. US3 §1, §4, §9).
- **FR-A2-06** : Timeout par action : 5 secondes (configurable via `[signals] timeout_ms`). Au timeout : SIGTERM → SIGKILL après 1s grâce, log warn.
- **FR-A2-07** : Le SignalDispatcher DOIT borner sa queue interne à 1000 events. Au-delà, drop FIFO + log warn.
- **FR-A2-08** : Re-entrancy guard : un event déclenché par une action de signal NE DOIT PAS re-déclencher une autre action de signal (flag `_inside_signal` propagé sur le sous-arbre d'exec).

**A3 — Stack mode** (sous réserve scope-in) :

- **FR-A3-01** : Le LayoutEngine DOIT supporter un nouveau type de nœud `Stack` qui peut contenir N fenêtres "empilées" (frame partagée, une seule visible à la fois).
- **FR-A3-02** : `roadie window toggle split` sur un nœud Split (V/H) DOIT basculer son orientation.
- **FR-A3-03** : `roadie focus stack.next/prev` DOIT cycler la fenêtre visible du stack focus.
- **FR-A3-04** : `roadie tiler.set stack` DOIT positionner toutes les fenêtres du space dans un Stack root unique.
- **FR-A3-05** : Un Stack non-visible (window cachée derrière) DOIT utiliser la stratégie offscreen (cohérent avec SPEC-002 hide_strategy="corner").

**A4 — Insertion directionnelle** :

- **FR-A4-01** : Une nouvelle commande `roadie window insert <direction>` (north/south/east/west/stack) DOIT poser un hint runtime attaché à la fenêtre focused.
- **FR-A4-02** : Le LayoutEngine DOIT consommer le hint à la prochaine création de fenêtre dans le tree de la fenêtre cible.
- **FR-A4-03** : Le hint DOIT expirer après 120s sans utilisation (configurable `[insert] hint_timeout_ms`).
- **FR-A4-04** : Le hint `stack` DOIT déclencher US5 si implémenté, sinon fallback split par défaut + log info.
- **FR-A4-05** : Si `[insert] show_hint = true`, un overlay visuel discret (border colorée 2px sur le côté cible) DOIT s'afficher tant que le hint est actif.

**A5 — Swap** :

- **FR-A5-01** : Une nouvelle commande `roadie window swap <direction>` DOIT échanger les références des 2 fenêtres dans le tree, **sans modifier la structure** (parent, splits, ratios).
- **FR-A5-02** : Le focus DOIT rester sur la même fenêtre logique (qui a changé de position).
- **FR-A5-03** : Si pas de voisine dans la direction → no-op + warning, exit code != 0.
- **FR-A5-04** : Swap inter-display DOIT être supporté (réutilise la résolution de neighbor cross-display déjà en place SPEC-012).

**A6 — Focus / mouse follows** :

- **FR-A6-01** : Section TOML `[mouse]` DOIT supporter `focus_follows_mouse` parmi (`off`, `autofocus`, `autoraise`) et `mouse_follows_focus` parmi (`true`, `false`).
- **FR-A6-02** : Un nouveau watcher `MouseFollowFocusWatcher` DOIT observer la position du curseur (CGEvent tap ou polling 50ms), détecter la fenêtre survolée et déclencher focus après `idle_threshold_ms` (default 200) d'immobilité.
- **FR-A6-03** : Le watcher DOIT être désactivé pendant un drag actif (coordination avec MouseModifier SPEC-015).
- **FR-A6-04** : Le watcher DOIT ignorer les zones non-fenêtre (Dock, Menu Bar, desktop empty area).
- **FR-A6-05** : Quand `mouse_follows_focus = true`, **toutes** les commandes qui changent le focus (focus, swap, warp, window.display, desktop.focus, stage.switch) DOIVENT téléporter le curseur via `CGWarpMouseCursorPosition` au centre du visibleFrame de la nouvelle fenêtre focused.
- **FR-A6-06** : La téléportation DOIT être skippée si le focus a été déclenché par un event souris (clic, autofocus survol) — détection via flag `focus_source` interne.

**Transverses** :

- **FR-T-01** : Toutes les nouvelles commandes DOIVENT être exposées via le CLI `roadie` ET via le routeur socket `CommandRouter`.
- **FR-T-02** : `daemon reload` DOIT recharger rules + signals + config mouse sans redémarrer le daemon, sans casser les fenêtres en place.
- **FR-T-03** : Un test d'acceptation shell (`Tests/16-*.sh`) DOIT valider chaque user story de bout en bout via le binaire compilé.
- **FR-T-04** : La constitution Article 0 (minimalisme) DOIT être respectée : aucun nouveau module externe (Cargo, npm) ; tout en pure Swift Foundation/AppKit/CoreGraphics.

### Key Entities

- **Rule** : entrée du TOML (`app`, `title?`, `manage?`, `float?`, `sticky?`, `space?`, `display?`, `grid?`, `reapply_on_title_change?`). Évaluée à `window_created` et opt-in à `apply --all`.
- **Signal** : entrée du TOML (`event`, `action`, `app?`, `title?`). Pré-compilée en SignalHandler avec regex compilés.
- **InsertHint** : runtime, attaché à un `windowID` cible. Champs : `direction` (north/south/east/west/stack), `expiresAt` (timestamp).
- **StackNode** : extension du LayoutTree. Champs : `windows: [WindowID]`, `visibleIndex: Int`. Frame partagée par toutes les fenêtres ; gestion offscreen pour les non-visibles.
- **MouseFollowState** : runtime. Champs : `lastCursorPos`, `lastMoveAt`, `currentHoverWindow?`, `dragActive: Bool`.

## Success Criteria *(mandatory)*

### Measurable Outcomes

**Adoption / fluidité daily driver** :
- **SC-016-01** : 100% des cas de tests acceptance des US1 (swap + focus_follows + mouse_follows) passent automatisés sur la machine cible.
- **SC-016-02** : Avec `focus_follows_mouse = autofocus`, l'utilisateur peut alterner entre 5 fenêtres voisines en 5 secondes sans toucher la souris (juste mouvement curseur), zéro clic.
- **SC-016-03** : Une rule `app="X", manage="off"` appliquée prend effet en moins de 100 ms après `window_created`.

**Robustesse** :
- **SC-016-04** : Un signal action qui crash ne fait pas crasher le daemon (zéro crash daemon imputable au SignalDispatcher sur 1000 events de stress test).
- **SC-016-05** : Un fichier `roadies.toml` avec 50% de rules cassées garde le reste fonctionnel (parser tolérant).
- **SC-016-06** : Sous rafale de 100 events/sec pendant 30s, latence de dispatch p99 < 50 ms, zéro signal perdu hors saturation explicite (queue cap).

**Effort scope** :
- **SC-016-07** : Si à la Phase 2 plan, l'estimation US5 (stack mode) > 8 sessions, US5 est scope-out documentée vers SPEC-017 dans la même Phase 2 (pas en Phase 5 implementation).
- **SC-016-08** : Spec totale tient sous 12 sessions implementation (estimée P1 + P2 hors stack).

**UX cohérence yabai-parity** :
- **SC-016-09** : Un utilisateur yabai existant peut migrer son fichier `~/.yabairc` rules vers `roadies.toml` `[[rules]]` avec un mapping 1-pour-1 documenté pour 80% des champs courants (`manage`, `sticky`, `float`, `space`, `display`, `grid`, `app`, `title`).
- **SC-016-10** : Un utilisateur yabai existant retrouve `swap`, `focus_follows_mouse`, `mouse_follows_focus`, `--insert` avec sémantique identique (test : reproduire 3 muscle-memories yabai sans repenser).

**Non-régression** :
- **SC-016-11** : Tous les tests existants des SPECs 002, 011, 012, 013 continuent de passer après merge SPEC-016.
- **SC-016-12** : Aucune rule ne peut casser une fenêtre déjà ouverte tant que `apply --all` n'est pas explicitement invoqué (rules s'appliquent uniquement aux fenêtres futures).

## Assumptions

- **A1** : Les regex Swift `NSRegularExpression` sont suffisantes (pas de PCRE étendu). Si un user pousse un regex non supporté → log warn skip rule, pas d'incident.
- **A2** : Les actions shell tournent avec l'env du daemon (PATH minimal). Si un user a besoin de PATH étendu, il passe par `[signals] env_path = "..."` (à ajouter en Phase 2 plan si demandé) ou wrap dans `bash -lc`.
- **A3** : Stack mode n'introduit pas d'animation native (juste swap visible/hidden). Animations relèvent de la famille SPEC-007 (bloquée Tahoe ADR-005 de toute façon).
- **A4** : Hint insert est purement runtime mémoire daemon (perdu au crash daemon). Pas de persistance car cycle de vie attendu < 2 minutes.
- **A5** : Swap inter-display réutilise la logique multi-tree SPEC-012 sans nouveau code de coordination.
- **A6** : `focus_follows_mouse` utilise polling 50ms par défaut pour éviter besoin Accessibility-tap qui peut conflicter avec MouseRaiser SPEC-002. Si latence ressentie trop forte, opt-in CGEventTap en Phase 2 plan.
- **Conflits SPEC-015** : MouseFollowFocusWatcher et MouseModifier (SPEC-015) coexistent via un coordinator partagé `MouseInputCoordinator` qui dispatch selon état modifier/drag.
- **Persistance rules/signals** : aucune. Tout est rechargé depuis le TOML à chaque reload. Pas de DB, pas de cache, pas de side file. Cohérent constitution minimalisme.
- **i18n** : pas de messages user-facing localisés ; tous les logs/CLI restent en anglais (cohérent avec specs antérieures).

## Hors scope (NE PAS confondre)

- **Layers / topmost** (B6) : pas dans SPEC-016. Sera SPEC-019.
- **Mission Control / show-desktop** (B1) : non, hors scope.
- **Spaces dynamiques create/destroy** (B4) : non, count fixe maintenu.
- **Padding/gaps dynamiques par space** (B2) : non, statique conservé.
- **`--query` JSON riche** (C3) : non, `windows.list` actuel reste.
- **PiP, zoom-parent, minimize/deminimize** (C1, C2, B7) : non.
- **Tout effet visuel SIP-off** (D) : reste bloqué ADR-005, hors scope éternel tant qu'osax non rétabli.
