# Feature Specification: Etat fullscreen dans le navrail

**Feature Branch**: `015-navrail-fullscreen-state`  
**Created**: 2026-05-25  
**Status**: Draft  
**Dependencies**: SPEC-010-layout-stability-hardening, SPEC-011-atomic-components  
**Input**: User description: "Afficher dans le navrail les fenêtres `maximized` et `nativeFullscreen`, en gardant le même modèle de stage/layout, avec une bordure à quatre coins pour `maximized` et une bordure complète pour `nativeFullscreen`. Le calcul d'état doit être partagé entre mode modulaire et monolithique, et le navrail doit représenter ces fenêtres sans les réintégrer abusivement dans les commandes de layout."

## Research Findings

- Apple décrit les fenêtres macOS comme des éléments servant à délimiter visuellement le contenu applicatif et à soutenir le multitâche. Roadie doit donc conserver dans le navrail la notion de fenêtre, même lorsqu'une fenêtre occupe presque tout l'espace.
- WCAG 2.2 SC 1.4.11 impose que les indicateurs graphiques porteurs d'état restent suffisamment contrastés lorsqu'ils sont nécessaires à la compréhension. Les bordures `maximized` et `nativeFullscreen` doivent donc être discernables sans dépendre uniquement d'une couleur subtile.
- Le principe UX retenu est la reconnaissance plutôt que le rappel : l'utilisateur doit voir où se trouve une fenêtre maximisée sans devoir se souvenir du stage qui la contient.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Voir une fenêtre maximized dans sa stage (Priority: P1)

En tant qu'utilisateur Roadie, je veux qu'une fenêtre maximisée reste visible dans le navrail à l'intérieur de sa stage, afin de comprendre qu'elle existe toujours dans le modèle Roadie même si elle occupe tout l'espace utile.

**Why this priority**: C'est le défaut actuellement gênant : une fenêtre maximisée peut disparaître de la représentation mentale alors qu'elle reste active et importante.

**Independent Test**: Ouvrir une stage contenant une fenêtre normale, la maximiser au sens Roadie/yabai-like, puis vérifier que le navrail affiche toujours la fenêtre dans sa stage avec un indicateur `maximized`.

**Acceptance Scenarios**:

1. **Given** une fenêtre Roadie dans une stage active, **When** elle couvre presque tout le `visibleFrame` sans être en fullscreen natif macOS, **Then** le navrail l'affiche dans sa stage avec une bordure à quatre coins.
2. **Given** une fenêtre `maximized` dans une stage inactive, **When** la stage est masquée ou parkée, **Then** le navrail conserve la fenêtre dans cette stage et conserve l'indicateur `maximized`.
3. **Given** une fenêtre `maximized`, **When** l'utilisateur clique sa représentation dans le navrail, **Then** Roadie active la même stage et focalise la fenêtre comme pour une fenêtre normale.

---

### User Story 2 - Distinguer le fullscreen natif macOS (Priority: P1)

En tant qu'utilisateur Roadie, je veux distinguer une fenêtre en fullscreen natif macOS d'une fenêtre simplement maximisée, afin de comprendre quand macOS peut imposer un comportement de Space spécial.

**Why this priority**: Les deux états se ressemblent visuellement à l'écran, mais n'ont pas les mêmes garanties de gestion par Roadie. Les confondre rend le diagnostic et la navigation ambigus.

**Independent Test**: Mettre une fenêtre en fullscreen natif macOS, puis vérifier que le navrail l'identifie avec l'état `nativeFullscreen` et une bordure complète.

**Acceptance Scenarios**:

1. **Given** une fenêtre détectée comme fullscreen natif macOS, **When** le navrail la représente, **Then** il affiche une bordure continue complète autour de la vignette.
2. **Given** une fenêtre qui pourrait aussi couvrir le `visibleFrame`, **When** elle est identifiée comme fullscreen natif, **Then** l'état `nativeFullscreen` prime sur `maximized`.
3. **Given** une fenêtre `nativeFullscreen`, **When** Roadie ne peut pas appliquer une action de layout normale, **Then** le navrail la représente quand même sans prétendre qu'elle est tilable normalement.

---

### User Story 3 - Garder la parité monolithique et modulaire (Priority: P1)

En tant qu'utilisateur qui lance Roadie en mode monolithique ou modulaire, je veux que le navrail affiche exactement les mêmes états de présentation dans les deux modes, afin d'éviter deux comportements concurrents.

**Why this priority**: Roadie doit rester fiable quel que soit le mode de lancement. Toute divergence entre `roadied run` et les composants modulaires rendrait le debug runtime imprévisible.

**Independent Test**: Lancer Roadie en mode monolithique puis en mode modulaire sur le même état de fenêtres, et vérifier que le navrail expose les mêmes états `normal`, `maximized`, `nativeFullscreen`.

**Acceptance Scenarios**:

1. **Given** le même snapshot de fenêtres, **When** le navrail est alimenté par le mode monolithique puis par le mode modulaire, **Then** les états de présentation affichés sont identiques.
2. **Given** une correction de détection d'état, **When** elle est livrée, **Then** elle s'applique au chemin partagé consommé par les deux modes.

---

### User Story 4 - Ne pas perturber le layout (Priority: P2)

En tant qu'utilisateur Roadie, je veux que l'ajout d'indicateurs dans le navrail ne déclenche aucun relayout inattendu, afin que la représentation visuelle ne modifie pas le comportement des fenêtres.

**Why this priority**: Le navrail est une carte de navigation. Il ne doit pas réintégrer des fenêtres fullscreen ou maximized dans des commandes de layout qui contredisent leur état.

**Independent Test**: Afficher une fenêtre `maximized` ou `nativeFullscreen` dans le navrail, puis vérifier qu'aucune commande de layout additionnelle n'est planifiée à cause de cet affichage.

**Acceptance Scenarios**:

1. **Given** une fenêtre `maximized` affichée dans le navrail, **When** le rail se rafraîchit, **Then** aucune commande de layout nouvelle n'est émise uniquement à cause de l'indicateur.
2. **Given** une fenêtre `nativeFullscreen`, **When** le rail la représente, **Then** elle ne devient pas une cible de tiling automatique par effet secondaire.

### Edge Cases

- Une fenêtre couvre presque tout l'écran mais laisse une marge due au Dock, à la barre de menu, aux gaps Roadie ou à un clamp macOS.
- Une fenêtre est déplacée hors écran pour masquer une stage inactive tout en gardant son dernier état de présentation connu.
- Une fenêtre change rapidement entre normale, maximized et native fullscreen pendant que le navrail se rafraîchit.
- Une application expose des informations Accessibility incomplètes ou contradictoires sur son état fullscreen.
- Une fenêtre native fullscreen n'est pas observable sur le Space courant, mais reste connue dans l'état Roadie.
- Plusieurs fenêtres existent dans la même stage et l'une d'elles est maximized : la représentation ne doit pas faire disparaître les autres membres de la stage.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: Roadie MUST expose a presentation state for each significant window represented in the navrail.
- **FR-002**: The presentation state MUST include exactly these user-facing values for this feature: `normal`, `maximized`, `nativeFullscreen`.
- **FR-003**: Roadie MUST classify a window as `maximized` when it covers the usable display area closely enough to behave as a maximized window while remaining a normal Roadie window.
- **FR-004**: Roadie MUST classify a window as `nativeFullscreen` when macOS fullscreen semantics are detected or when Roadie has enough evidence that the window belongs to native fullscreen behavior.
- **FR-005**: `nativeFullscreen` MUST take precedence over `maximized` when both signals could apply.
- **FR-006**: The navrail MUST continue to show `maximized` windows inside their existing stage instead of moving them to a special fullscreen stage.
- **FR-007**: The navrail MUST render `maximized` windows with a four-corner border indicator.
- **FR-008**: The navrail MUST render `nativeFullscreen` windows with a continuous full-border indicator.
- **FR-009**: The visual indicators MUST remain distinguishable at navrail thumbnail size without relying only on hue.
- **FR-010**: The same presentation state source MUST be consumed by monolithic and modular Roadie modes.
- **FR-011**: The presentation state MUST be visible through Roadie's automation/state surfaces when those surfaces already expose windows or navrail data.
- **FR-012**: Displaying a presentation state in the navrail MUST NOT cause a window to be added to layout commands that would otherwise ignore or suppress that window.
- **FR-013**: A window returning from `maximized` or `nativeFullscreen` to normal MUST return to `normal` in the navrail without losing its stage membership.
- **FR-014**: Existing navrail interactions on a represented window MUST continue to work unless macOS native fullscreen restrictions make the interaction impossible.
- **FR-015**: Roadie MUST log or expose enough diagnostic information to distinguish a detection failure from a rendering failure.

### Key Entities

- **Window Presentation State**: User-facing state attached to a window representation. Values: `normal`, `maximized`, `nativeFullscreen`.
- **Navrail Window Representation**: Visual entry for a window inside a stage card or rail item, including identity, stage membership and presentation state.
- **Stage Membership**: Existing relationship between a window and its Roadie stage. This feature preserves the relationship and adds display metadata.
- **Detection Evidence**: Snapshot signals used to infer presentation state, such as frame coverage, display visible frame and fullscreen/native fullscreen hints.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: In manual validation, 100% of tested `maximized` windows remain visible in their current navrail stage with a four-corner border.
- **SC-002**: In manual validation, 100% of tested native fullscreen windows that Roadie can observe are represented with a continuous border.
- **SC-003**: In automated tests, the same synthetic snapshot produces identical presentation states through the monolithic and modular data path.
- **SC-004**: In automated tests, adding presentation state rendering causes zero additional layout commands for fullscreen/maximized windows.
- **SC-005**: The state distinction is readable in the navrail at normal rail size in under 2 seconds during manual inspection.
- **SC-006**: Existing navrail stage switching and window focus tests continue to pass unchanged.

## Assumptions

- `maximized` and `fullscreen-like` are the same user-facing concept for this feature; the exposed term is `maximized`.
- `nativeFullscreen` means macOS fullscreen behavior, including cases where macOS manages a separate fullscreen Space.
- The v1 scope is representation and state exposure, not adding a new command to toggle fullscreen.
- The v1 scope does not create a dedicated fullscreen stage.
- A tolerance-based detection is acceptable for `maximized` because menu bar, Dock, display scale, gaps and macOS clamping can prevent exact frame equality.
- When native fullscreen cannot be observed on the current Space, Roadie may preserve the last known presentation state if doing so is less misleading than dropping the window entirely.
