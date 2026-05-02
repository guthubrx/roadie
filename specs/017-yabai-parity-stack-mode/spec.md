# Feature Specification: Yabai-parity stack mode local (gap A3)

**Feature Branch**: `017-yabai-parity-stack-mode` (à créer le moment venu)
**Status**: 🔲 **Placeholder** (pas encore en planning, pas encore en draft)
**Created**: 2026-05-02
**Dependencies**: SPEC-016 (yabai-parity tier-1 — fournit `--insert <direction>`, doit être livrée d'abord), SPEC-002 (LayoutEngine BSP), SPEC-012 (multi-display tree)
**Origin**: scope-out de SPEC-016 US5, acté en Phase 2 plan SPEC-016 (cf. [SPEC-016/plan.md](../016-yabai-parity-tier1/plan.md) §Summary). Préservation explicite des idées de A3 (ADR-006 catégorie A, gap #3).

## Pourquoi un placeholder

Cette spec **existe pour ne rien perdre**. Le mode stack local (gap A3 d'ADR-006) avait été spécifié à l'origine comme US5 de SPEC-016. À la phase plan SPEC-016, l'estimation d'effort a montré que ce seul user story représente 4-6 sessions à cause du refactor `LayoutEngine` qu'il impose (introduction d'un nouveau type de nœud `Stack`, propagation à tous les algorithmes BSP existants, gestion des fenêtres cachées via offscreen, indicateur visuel SwiftUI). Inclure US5 dans SPEC-016 aurait fait dépasser le plafond de 12 sessions (SC-016-08).

**Décision de scope** : sortir A3 de SPEC-016, créer SPEC-017 dédiée, transférer **toutes** les idées originelles de US5 dans cette spec. Aucun contenu d'origine n'est abandonné — tout est tracé ici en attendant que SPEC-016 soit livrée et que SPEC-017 démarre.

## Vision (à préciser à l'ouverture)

Permettre d'**empiler** plusieurs fenêtres dans un même nœud de l'arbre `LayoutEngine`, de manière à ce qu'elles partagent un slot visuel unique (frame partagée, une seule fenêtre visible à la fois) et qu'on puisse cycler entre elles via clavier sans perturber le reste du tile.

C'est le pattern yabai `--insert stack` + `--focus stack.next/prev`, et l'équivalent du mode `tabbed`/`stacking` de i3/sway. Utile pour grouper logiquement plusieurs fenêtres qui occupent la même "case" : 3 onglets WezTerm dans le même panneau, 2 versions d'un même éditeur en révision, plusieurs tools de monitoring sur le même slot d'un dashboard tilé.

## User stories candidates (à raffiner à l'ouverture)

Reprises **mot pour mot** depuis SPEC-016 §US5 + §FR-A3 + §Edge Cases pour ne perdre aucune idée :

### US-A3-1 — Empiler une fenêtre dans un nœud existant (P1)

**Independent Test** : focus A + `roadie window insert stack` (commande déjà fournie par SPEC-016 mais qui tombait sur fallback split) + ouvrir B → A et B empilées dans le même slot. Visuellement seule B (la dernière) est visible. `roadie focus stack.next` → A devient visible. Cycle.

**Acceptance Scenarios** (depuis SPEC-016 US5 acceptance §1, §2, §6) :
1. **Given** A floating-tilée seule, **When** `insert stack` + ouvrir B, **Then** B empilée sur A. Frame B = frame A. A cachée derrière (offscreen ou hidden, pas détruite).
2. **Given** stack [A, B, C], visible = C, **When** `roadie focus stack.next`, **Then** B visible, focus sur B. Cycle wrap-around après le dernier.
3. **Given** stack [A, B, C] et A est minimisée (close window), **When** A disparaît, **Then** stack devient [B, C], visible = next ou prev selon position.

### US-A3-2 — Layout `stack` au niveau d'un space (P2)

**Acceptance Scenario** (depuis SPEC-016 US5 §4) :
4. **Given** `roadie tiler.set stack` au niveau d'un space, **When** activation, **Then** toutes les fenêtres du space sont empilées dans un seul nœud root.

### US-A3-3 — `--toggle split` pour basculer V↔H d'un nœud parent (P2)

**Acceptance Scenario** (depuis SPEC-016 US5 §5) :
5. **Given** `roadie window toggle split` sur un nœud parent split V, **When** invocation, **Then** le split bascule en H. Frames recalculées.

### US-A3-4 — Déballer un stack vers BSP standard (P2)

**Acceptance Scenario** (depuis SPEC-016 US5 §3) :
3. **Given** stack [A, B], **When** layout space passe en `bsp` standard, **Then** stack se "déballe" : A et B redeviennent feuilles séparées. Layout réajusté.

### US-A3-5 — Indicateur visuel stack (P3, polish)

**Acceptance Scenario** (depuis SPEC-016 US5 §7) :
7. **Given** indicateur visuel stack (config `[stack] show_indicator = true`), **When** stack actif, **Then** un mini-rail vertical (3 puces) s'affiche en coin de la fenêtre visible, position courante highlight.

## Functional Requirements pré-identifiés

Reprises **mot pour mot** depuis SPEC-016 §FR-A3 :

- **FR-A3-01** : Le LayoutEngine DOIT supporter un nouveau type de nœud `Stack` qui peut contenir N fenêtres "empilées" (frame partagée, une seule visible à la fois).
- **FR-A3-02** : `roadie window toggle split` sur un nœud Split (V/H) DOIT basculer son orientation.
- **FR-A3-03** : `roadie focus stack.next/prev` DOIT cycler la fenêtre visible du stack focus.
- **FR-A3-04** : `roadie tiler.set stack` DOIT positionner toutes les fenêtres du space dans un Stack root unique.
- **FR-A3-05** : Un Stack non-visible (window cachée derrière) DOIT utiliser la stratégie offscreen (cohérent avec SPEC-002 `hide_strategy="corner"`).

## Edge Cases pré-identifiés

Repris depuis SPEC-016 §Edge Cases :

- **Stack vide** : si la dernière fenêtre du stack est fermée, le nœud Stack lui-même est supprimé du tree (pas de Stack avec 0 fenêtre).
- **Swap dans un stack** : swap les positions dans la liste du stack, pas de changement visuel sauf si l'une des deux était la "visible" (cohérence avec SPEC-016 A5).
- **Stack et drag mouse modifier (SPEC-015)** : drag d'une fenêtre visible d'un stack → sortie du stack vers floating (comme drag d'une fenêtre tilée standard).
- **Multi-display + stack** : un stack vit dans le tree d'un seul display ; pas de stack cross-display (cohérent SPEC-012).
- **`--insert stack` quand US-A3 pas encore livré** : SPEC-016 FR-A4-04 garantit déjà le fallback split par défaut + log info. À la livraison de SPEC-017, le hint sera correctement consommé.

## Architecture pré-identifiée (à valider en research SPEC-017)

- Extension du model `LayoutNode` (probablement enum) avec un cas `stack(StackNode)` en plus de `leaf` et `split(SplitNode)`.
- `StackNode` : `{ children: [LeafID], visibleIndex: Int, frame: CGRect }`.
- Extension du `LayoutEngine` :
  - `applyLayout()` : pour chaque `Stack`, applique `frame` à la fenêtre `children[visibleIndex]`, déplace les autres `children` offscreen via `HideStrategy`.
  - `focusStack(direction:)` : cycle `visibleIndex`, met à jour focus.
  - `toggleSplit(nodeID:)` : trouve le nœud parent, bascule `axis`.
  - `convertSpaceToStack(spaceID:)` : remplace le tree par un seul `Stack` root.
- Extension du `CommandRouter` :
  - `focus stack.next` / `focus stack.prev`
  - `window.toggle.split`
  - `tiler.set stack` (étend le verbe existant)
- Indicateur visuel : nouveau composant SwiftUI léger dans `RoadieRail` (ou nouveau target si pas dans le rail).

## Cible LOC estimée (à valider)

- Refactor `LayoutNode` enum + propagation : ~200 LOC
- `StackNode` + algorithmes de cycle : ~150 LOC
- `LayoutEngine` extensions : ~150 LOC
- `CommandRouter` extensions : ~80 LOC
- Indicateur visuel SwiftUI : ~120 LOC (si scope-in)
- Tests unitaires + acceptance : ~300 LOC
- **Total estimé** : ~700-900 LOC production
- Cible 700 / plafond 1000

## Out of scope (anticipé)

- Animations entre fenêtres du stack (slide, fade) : reportées à V2.
- Persistance du stack au reboot daemon : V2 si demande.
- Drag d'une fenêtre **vers** un stack pour l'ajouter : reportée à V2 (pour V1, on entre par `--insert stack`).

## Dépendances de démarrage

SPEC-017 ne peut pas démarrer avant que SPEC-016 soit **livrée et mergée**, parce que :
1. Elle s'appuie sur la commande `--insert stack` (introduite par SPEC-016 US4 mais en mode fallback).
2. Elle modifie potentiellement le format des events `window_focused` (ajout d'un champ `stack_position` si présent).
3. Le `MouseInputCoordinator` (SPEC-016) doit déjà exister pour gérer le drag d'une fenêtre visible hors d'un stack.

## Suivi

- **Date d'ouverture cible** : après livraison de SPEC-016 (probablement 2026-06).
- **Re-évaluation** : à la première `/speckit.specify` SPEC-017, valider que le contexte LayoutEngine n'a pas changé entretemps. Cette spec sera alors reprise comme base et raffinée.

## Liens

- [SPEC-016 plan.md](../016-yabai-parity-tier1/plan.md) — décision scope-out
- [SPEC-016 spec.md §US5](../016-yabai-parity-tier1/spec.md) — version originelle des user stories
- ADR-006 (interne, gitignored) — gap A3 dans le panorama yabai-parity
- [SPEC-002 spec.md](../002-tiler-stage/spec.md) — base BSP
- yabai docs : `--insert stack`, `--focus stack.next/prev`, `layout=stack`
- i3/sway : modes `tabbed` et `stacking`
