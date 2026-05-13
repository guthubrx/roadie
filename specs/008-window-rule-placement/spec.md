# Feature Specification: Placement des fenêtres par règle

**Feature Branch**: `008-window-rule-placement`  
**Created**: 2026-05-13  
**Status**: Draft  
**Input**: Demande utilisateur : "permettre qu'une application s'ouvre toujours sur une stage particulière et sur un écran particulier"

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Ouvrir une application sur sa stage cible (Priority: P1)

L'utilisateur définit une règle pour une application donnée afin que toute nouvelle fenêtre gérée par Roadie rejoigne automatiquement une stage cible, sans devoir la déplacer manuellement après ouverture.

**Why this priority**: C'est le besoin principal : retrouver une organisation prévisible par application, équivalente à des règles de placement de window manager avancé.

**Independent Test**: Configurer une règle pour une application de test vers une stage nommée, lancer une nouvelle fenêtre, vérifier que la fenêtre est membre de cette stage et que la stage existe si nécessaire.

**Acceptance Scenarios**:

1. **Given** une règle qui associe "BlueJay" à la stage "Media", **When** une nouvelle fenêtre BlueJay apparaît, **Then** Roadie l'assigne à la stage "Media".
2. **Given** la stage "Media" n'existe pas encore sur le desktop courant, **When** une fenêtre matche la règle, **Then** Roadie crée ou matérialise une stage "Media" et y place la fenêtre.

---

### User Story 2 - Ouvrir une application sur un écran cible (Priority: P1)

L'utilisateur définit une règle pour qu'une application s'ouvre sur un écran précis, afin de garder les applications métiers, médias ou monitoring à l'endroit attendu.

**Why this priority**: Le placement par stage seul est insuffisant en multi-écran ; l'utilisateur a explicitement demandé le ciblage écran.

**Independent Test**: Configurer une règle avec écran cible, simuler deux écrans, créer une fenêtre qui matche, vérifier que sa stage d'appartenance est portée par l'écran cible.

**Acceptance Scenarios**:

1. **Given** une règle qui associe "Slack" à l'écran "LG HDR 4K" et à la stage "Com", **When** une fenêtre Slack apparaît, **Then** Roadie l'assigne à la stage "Com" de cet écran.
2. **Given** l'écran cible est absent, **When** une fenêtre matche la règle, **Then** Roadie ne casse pas l'état courant et reporte le placement avec un événement observable.

---

### User Story 3 - Contrôler le suivi du focus (Priority: P2)

L'utilisateur choisit si le placement automatique doit basculer vers la stage/écran cible ou rester sur le contexte courant.

**Why this priority**: Le comportement par défaut ne doit pas voler le focus, mais certains usages peuvent vouloir suivre l'application lancée.

**Independent Test**: Configurer deux règles identiques sauf `follow`, puis vérifier que l'état actif change uniquement lorsque `follow = true`.

**Acceptance Scenarios**:

1. **Given** une règle avec `follow = false`, **When** une fenêtre est placée automatiquement, **Then** la fenêtre change de stage mais l'utilisateur reste sur sa stage active.
2. **Given** une règle avec `follow = true`, **When** une fenêtre est placée automatiquement, **Then** Roadie active la stage cible et focalise l'écran cible si possible.

### Edge Cases

- L'écran cible peut être absent, renommé ou avoir changé d'identifiant après débranchement/rebranchement.
- Plusieurs règles peuvent matcher la même fenêtre ; la priorité existante des règles reste l'arbitre.
- Une fenêtre déjà déplacée manuellement ne doit pas être remise en boucle dans sa destination de règle.
- Les popups, dialogs et fenêtres exclues du tiling ne doivent pas être placées de force sauf règle explicite `manage = true`.
- Une stage cible peut être désignée par son ID ou par son nom visible.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: Roadie MUST allow a rule action to declare a target display for matched windows.
- **FR-002**: Roadie MUST allow a rule action to declare a target stage for matched windows.
- **FR-003**: Roadie MUST resolve target displays by stable display ID first, then by display name.
- **FR-004**: Roadie MUST resolve target stages by stage ID first, then by configured or persisted stage name.
- **FR-005**: Roadie MUST create or reuse the target stage on the target display/desktop when a matched managed window appears.
- **FR-006**: Roadie MUST avoid repeated automatic re-placement of a window after it has already reached the requested destination.
- **FR-007**: Roadie MUST leave focus on the current user context by default after automatic placement.
- **FR-008**: Roadie MUST support an explicit `follow` action to activate the target context after automatic placement.
- **FR-009**: Roadie MUST emit an observable event when a placement is applied, skipped, or deferred.
- **FR-010**: Roadie MUST fail safely when the target display is unavailable: no layout corruption, no stage merge, no destructive fallback.

### Key Entities

- **Window Placement Rule**: Existing Roadie rule extended with destination actions: target display, target stage, optional follow behavior.
- **Placement Destination**: Resolved display, desktop and stage where a matching window should belong.
- **Placement Decision**: Runtime result: applied, already satisfied, deferred, or skipped.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A matching new application window is placed in the configured stage/display within one maintainer tick after it becomes visible.
- **SC-002**: Repeated ticks after placement do not move the same window again while it remains at the requested destination.
- **SC-003**: If the target display is absent, Roadie emits a deferred event and preserves the existing stage state.
- **SC-004**: Existing rule behavior for matching, priority, manage/exclude/floating/layout/scratchpad remains compatible.
- **SC-005**: Automated tests cover placement to stage, placement to display+stage, absent target display, and follow/no-follow behavior.

## Assumptions

- La configuration se fait dans le TOML existant `[[rules]]`.
- Le ciblage desktop n'est pas demandé explicitement ; la première version cible le desktop courant de l'écran cible, sauf si `assign_desktop` est déjà fourni.
- Le comportement par défaut est `follow = false`, pour ne pas voler le focus.
- Les fenêtres non gérées ou explicitement exclues ne sont pas déplacées sauf règle de gestion explicite.
