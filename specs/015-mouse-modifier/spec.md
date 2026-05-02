# Feature Specification: Mouse modifier drag & resize

**Feature Branch**: `015-mouse-modifier`
**Created**: 2026-05-02
**Status**: Draft
**Dependencies**: SPEC-002 (daemon WindowRegistry), SPEC-012 (multi-display visibleFrame), SPEC-013 (mode per_display compat)
**Input**: « Modifier (Ctrl/Alt/Cmd) + clic souris pour drag-déplacer ou drag-resize une fenêtre. Configuration dans roadies.toml. Défaut Ctrl+left=move, Ctrl+right=resize. Resize multidirectionnel (quadrant-aware). »

## User Scenarios & Testing *(mandatory)*

### User Story 1 — Drag pour déplacer une fenêtre (P1, MVP)

L'utilisateur veut bouger une fenêtre avec sa souris **sans avoir à cliquer précisément sur la barre de titre**. Il maintient `Ctrl` enfoncé, clique gauche **n'importe où dans la fenêtre**, et drag → la fenêtre suit le curseur en temps réel. Au lâcher, la fenêtre reste à sa nouvelle position.

**Why this priority** : besoin numéro 1 du daily driver tiling/window manager (yabai, AeroSpace, Hammerspoon, Hyprland, KWin proposent tous ce pattern). Sans ça, déplacer une fenêtre dont la title bar est cachée par une autre est pénible.

**Independent Test** : maintenir `Ctrl`, clic gauche au milieu de n'importe quelle fenêtre, déplacer la souris de 200px → la fenêtre a bougé de 200px.

**Acceptance Scenarios** :

1. **Given** une fenêtre tilée + `[mouse] modifier="ctrl" action_left="move"` dans le toml, **When** Ctrl-clic gauche au milieu de la fenêtre + déplacement, **Then** la fenêtre suit le curseur. Au lâcher, sa nouvelle position est persistée. La fenêtre devient floating (= sortie du tile BSP) si elle était tilée.
2. **Given** une fenêtre déjà floating, **When** Ctrl-drag, **Then** elle bouge librement, reste floating.
3. **Given** Ctrl-drag d'une fenêtre vers un autre display, **When** lâcher, **Then** la fenêtre adopte le display cible (réutilise la logique drag cross-display SPEC-012).

---

### User Story 2 — Resize quadrant-aware avec modifier (P1)

L'utilisateur veut redimensionner une fenêtre **sans devoir viser le bord exact**. Il maintient `Ctrl`, clic droit dans la fenêtre, et drag → la fenêtre se redimensionne en fonction du quadrant où le clic a démarré : haut-gauche → resize coin TL (ancre = coin BR), centre-bas → resize bord bottom (ancres = bords T/L/R), etc.

**Why this priority** : second besoin majeur. yabai `mouse_action2 = resize`, Hammerspoon SpoonInstall mouse_resize, KWin `Meta+RClick`. Sans ça, on ne peut pas vite redimensionner une fenêtre dont le coin est hidden.

**Independent Test** : Ctrl-clic-droit au coin haut-gauche d'une fenêtre, drag → la fenêtre s'agrandit en haut-gauche, le coin bas-droit reste fixe.

**Acceptance Scenarios** :

1. **Given** une fenêtre + Ctrl+RClick dans son quart haut-gauche, **When** drag de 100px en haut-gauche, **Then** la fenêtre s'agrandit en haut-gauche. Coin BR fixe.
2. **Given** Ctrl+RClick dans le centre-bas (zone Sud), **When** drag de 50px vers le bas, **Then** seul le bord bottom descend. Bords T/L/R fixes.
3. **Given** une fenêtre tilée (BSP), **When** Ctrl+RClick + resize, **Then** comportement = `adaptToManualResize` SPEC-002 : adapte les ratios BSP.
4. **Given** Ctrl+RClick centre-centre, **When** drag, **Then** resize uniforme depuis le centre (pas implémenté en MVP — tombe sur le quadrant nearest).

---

### User Story 3 — Configuration TOML flexible (P2)

L'utilisateur peut customiser dans `~/.config/roadies/roadies.toml` :

```toml
[mouse]
modifier = "ctrl"               # ctrl | alt | cmd | shift | hyper | none
action_left = "move"            # move | resize | none
action_right = "resize"         # move | resize | none
action_middle = "none"          # move | resize | none
edge_threshold = 30             # pixels du bord pour le mode "edge-only resize"
```

Reload via `roadie daemon reload` ou redémarrage du daemon.

**Why this priority** : sans cette config, les utilisateurs Hyprland/yabai/AeroSpace ne peuvent pas reproduire leur muscle-memory.

**Independent Test** : changer `modifier="alt"` dans le toml + reload → Alt+LClick déplace désormais la fenêtre.

**Acceptance Scenarios** :

1. **Given** `modifier="alt"`, **When** Alt+LClick+drag, **Then** déplacement OK ; Ctrl+LClick+drag = no-op.
2. **Given** `action_left="resize", action_right="move"` (inversé), **When** clics correspondants, **Then** comportements inversés.
3. **Given** `modifier="none"`, **When** clic-drag sans aucune touche, **Then** déplacement actif (cas "always-on", utile pour testing — risqué en daily car conflit avec apps).
4. **Given** valeur invalide (`modifier="weird"`), **When** parser, **Then** fallback `ctrl` + log warn (parsing tolérant).

---

### User Story 4 — Coexistence avec MouseRaiser (P2)

L'utilisateur a déjà `MouseRaiser` (click-to-raise) actif. Quand il fait un Ctrl-clic, il s'attend à ce que **seul le drag** se déclenche, **pas le raise**. Inversement, un clic sans modifier déclenche raise (comportement actuel) sans drag.

**Why this priority** : sans ce respect, l'expérience est cassée (la fenêtre raise et drag en même temps = effet visuel sale ; ou raise active mais pas drag = pas de mouvement).

**Independent Test** : Ctrl+clic-drag → drag actif, pas de raise log. Clic simple → raise log normal, pas de drag.

**Acceptance Scenarios** :

1. **Given** mouse modifier `ctrl` actif, **When** Ctrl+LClick, **Then** drag déclenché, MouseRaiser **skipped** pour ce clic. Log `mouse-drag-start` mais pas de `click-to-raise`.
2. **Given** clic simple (pas de Ctrl), **When** LClick, **Then** MouseRaiser raise normalement, pas de drag.

---

### Edge Cases

- **Drag d'une fenêtre fullscreen native macOS** : skip silencieux (impossible techniquement). Log debug.
- **Ctrl+clic sur une zone qui n'est PAS une fenêtre** (Dock, Menu Bar, desktop) : no-op.
- **Modifier pressé en plein drag relâché avant le lâcher du clic** : continuer le drag jusqu'au mouseUp (= comportement standard, le modifier décide juste de DÉMARRER le drag).
- **Resize qui rendrait la fenêtre plus petite que minSize macOS** : macOS clamp, on accepte.
- **Multi-display drag** : mouse passe sur un autre display → la fenêtre suit le curseur, peut traverser des displays. Au lâcher : adopte le nouveau display + adopte le current desktop du target en mode per_display (cohérent SPEC-013).
- **Permission Input Monitoring non accordée** : log error explicite + désactiver la feature, ne pas crasher.
- **Conflit modifier avec un raccourci système** (ex: Ctrl+Click = Right Click sur trackpad macOS) : MVP n'adresse pas, l'utilisateur doit choisir un autre modifier.
- **Quadrant ambigu** (clic exactement au centre) : tomber sur le quadrant le plus proche du curseur après le 1er pixel de drag.

## Requirements *(mandatory)*

### Functional Requirements

#### Configuration

- **FR-001** : System MUST parser `[mouse]` section dans `~/.config/roadies/roadies.toml` avec champs `modifier`, `action_left`, `action_right`, `action_middle`, `edge_threshold`.
- **FR-002** : System MUST fallback à `modifier="ctrl"` si valeur invalide + log warn.
- **FR-003** : System MUST fallback à `action_X="none"` si valeur invalide.
- **FR-004** : System MUST recharger la config à `roadie daemon reload` sans perte d'état drag en cours.

#### Drag (déplacement)

- **FR-010** : Au mouseDown avec modifier configuré + bouton configuré comme `move`, System MUST identifier la fenêtre sous le curseur via `CGWindowList`.
- **FR-011** : Pendant mouseDragged, System MUST appliquer `setBounds` à la fenêtre avec un offset = (curseur_courant - curseur_au_mouseDown).
- **FR-012** : Si la fenêtre était tilée (BSP), au premier mouseDragged System MUST la sortir du tree (= passer en floating).
- **FR-013** : Au mouseUp, System MUST commit la nouvelle position (`registry.updateFrame`).
- **FR-014** : Au mouseUp, si la fenêtre a traversé un autre display, System MUST réassigner son arbre BSP cible et son `desktopID` selon le mode (cohérent SPEC-013 onDragDrop).

#### Resize (redimensionnement)

- **FR-020** : Au mouseDown avec modifier + bouton configuré comme `resize`, System MUST déterminer le **quadrant** du clic dans la fenêtre cible : `topLeft | topRight | bottomLeft | bottomRight | top | bottom | left | right`.
  - Quadrant "edge" si clic dans `edge_threshold` px d'un bord (sans coin proche).
  - Quadrant "corner" si proche de 2 bords adjacents.
  - Sinon (centre) : tomber sur le quadrant nearest après 1er pixel de drag.
- **FR-021** : Pendant mouseDragged, System MUST appliquer `setBounds` selon l'ancre du quadrant :
  - `topLeft` : ancre BR fixe, frame.origin = curseur, size ajustée.
  - `bottomRight` : ancre TL fixe, size ajustée.
  - `top` : ancre B + L+R fixes, size.height varie.
  - etc.
- **FR-022** : Si la fenêtre est tilée (BSP), au mouseUp System MUST appeler `LayoutEngine.adaptToManualResize` (FR existant SPEC-002) pour adapter les ratios.
- **FR-023** : Si la fenêtre est floating, au mouseUp System MUST commit `registry.updateFrame` directement.

#### Conflit MouseRaiser

- **FR-030** : Si modifier configuré est pressé au mouseDown, MouseRaiser MUST **skip** son traitement de click-to-raise pour cet event.
- **FR-031** : Sans modifier pressé, MouseRaiser MUST opérer normalement (= comportement actuel).

#### Performance & robustesse

- **FR-040** : Le drag MUST être fluide à ≥ 30 FPS perçus (= setBounds throttlé à 30ms entre les calls).
- **FR-041** : Si Input Monitoring permission absente, System MUST logger une erreur explicite et désactiver la feature au boot, sans crasher.
- **FR-042** : Le hook NSEvent MUST utiliser `addGlobalMonitorForEvents` (= déjà demandé pour MouseRaiser, pas de nouvelle permission).

### Key Entities

- **`MouseConfig`** : struct Codable depuis `[mouse]` TOML, contient `modifier: ModifierKey`, `actionLeft: MouseAction`, `actionRight: MouseAction`, `actionMiddle: MouseAction`, `edgeThreshold: Int`.
- **`ModifierKey`** : enum `ctrl | alt | cmd | shift | hyper | none`.
- **`MouseAction`** : enum `move | resize | none`.
- **`Quadrant`** : enum `topLeft | top | topRight | left | center | right | bottomLeft | bottom | bottomRight`.
- **`MouseDragSession`** : actor/struct contient `wid`, `startCursor`, `startFrame`, `mode (move|resize)`, `quadrant?`. Vit pendant la durée d'un drag.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001** : Ctrl+LClick+drag déplace la fenêtre en moins de **50 ms** entre l'event souris et le setBounds (latence perçue).
- **SC-002** : Ctrl+RClick+drag pour resize fonctionne sur **les 4 coins + 4 bords** (= 8 quadrants), avec l'ancre opposée fixe.
- **SC-003** : Une fenêtre tilée draggée perd son tile (passe floating) ; au mouseUp on peut la re-tile manuellement (`roadie window toggle floating`).
- **SC-004** : Reload de la config (`roadie daemon reload`) prend en compte le nouveau modifier en moins de **1 seconde**, drag en cours préservé.
- **SC-005** : Click simple sans modifier déclenche **uniquement** click-to-raise (pas de drag). Click avec modifier déclenche **uniquement** drag (pas de raise).
- **SC-006** : Permission Input Monitoring absente → log error explicite, daemon ne crash pas, MouseRaiser et drag tous deux désactivés.

## Assumptions

- L'utilisateur a déjà accordé Input Monitoring permission au daemon (acquise pour MouseRaiser).
- `NSEvent.addGlobalMonitorForEvents` reste suffisant pour intercepter mouseDown/Dragged/Up sans nécessiter `CGEventTap` (qui demande Accessibility avancé).
- Apple n'a pas modifié l'API `NSEvent` global monitor entre Sequoia et Tahoe.
- Le user accepte qu'une fenêtre tilée draggée perde son tile (= comportement intuitif, cohérent yabai/AeroSpace).
- Le quadrant resize est **discrétisé** en 8 zones (pas de smooth resize centre — V2 si demandé).
