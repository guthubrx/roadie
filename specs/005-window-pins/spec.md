# Feature Specification: Window Pins

**Feature Branch**: `030-window-pins`  
**Created**: 2026-05-11  
**Status**: Draft  
**Input**: User description: "Ajouter des pins de fenêtres depuis le menu contextuel de barre de titre : pin sur une stage du même desktop, pin visible sur toutes les stages du desktop courant, pin visible sur tous les desktops, avec options de retrait du pin et sans re-tiler les fenêtres flottantes."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Pin a Window Within the Current Desktop (Priority: P1)

Un utilisateur veut garder une fenêtre utile visible lorsqu'il change de stage dans le même desktop, sans que cette fenêtre apparaisse dans les autres desktops Roadie.

**Why this priority**: C'est le besoin principal exprimé : garder une fenêtre de référence ou un panneau utile sous les yeux tout en changeant de contexte dans le même desktop, sans polluer les autres desktops.

**Independent Test**: Peut être testé avec une fenêtre visible, deux stages dans le même desktop, et au moins un autre desktop. Le test est réussi si la fenêtre reste visible en changeant de stage dans le desktop courant, puis disparaît quand l'utilisateur change de desktop.

**Acceptance Scenarios**:

1. **Given** une fenêtre visible sur une stage active, **When** l'utilisateur choisit "Pin sur ce desktop" depuis le menu de barre de titre, **Then** la fenêtre reste visible sur toutes les stages du desktop courant.
2. **Given** une fenêtre pinée sur le desktop courant, **When** l'utilisateur passe à un autre desktop Roadie, **Then** la fenêtre n'est plus visible.
3. **Given** une fenêtre pinée sur le desktop courant, **When** l'utilisateur revient au desktop d'origine, **Then** la fenêtre redevient visible sans changer de stage active.

---

### User Story 2 - Pin a Window Across All Roadie Desktops (Priority: P2)

Un utilisateur veut garder une fenêtre visible quel que soit le desktop Roadie actif, par exemple un outil de monitoring, une documentation ou une fenêtre de contrôle.

**Why this priority**: Ce mode couvre les fenêtres vraiment transverses, sans obliger l'utilisateur à les déplacer ou à les recréer dans chaque desktop.

**Independent Test**: Peut être testé avec deux desktops et plusieurs stages. Le test est réussi si la fenêtre reste visible après chaque changement de stage et de desktop, sans être dupliquée dans les listes ou menus.

**Acceptance Scenarios**:

1. **Given** une fenêtre visible sur une stage active, **When** l'utilisateur choisit "Pin sur tous les desktops", **Then** la fenêtre reste visible lors des changements de stage et de desktop Roadie sur le même écran.
2. **Given** une fenêtre pinée sur tous les desktops, **When** l'utilisateur change plusieurs fois de stage et de desktop, **Then** la fenêtre conserve sa position et ne déclenche pas de réorganisation du layout.
3. **Given** une fenêtre pinée sur tous les desktops, **When** l'utilisateur la déplace manuellement, **Then** sa nouvelle position reste respectée lors des prochains changements de contexte.

---

### User Story 3 - Remove a Pin Safely (Priority: P3)

Un utilisateur veut retirer le pin d'une fenêtre depuis le même menu, et retrouver un comportement normal sans perdre la fenêtre ni provoquer de saut de layout.

**Why this priority**: Tout état persistant ou transversal doit être réversible directement par l'utilisateur, sinon la fonctionnalité devient vite confuse.

**Independent Test**: Peut être testé en pinant une fenêtre, puis en retirant le pin. Le test est réussi si la fenêtre redevient liée à une seule stage et suit à nouveau les règles normales de visibilité.

**Acceptance Scenarios**:

1. **Given** une fenêtre pinée sur le desktop courant, **When** l'utilisateur choisit "Retirer le pin", **Then** la fenêtre reste sur la stage active et disparaît des autres stages du même desktop.
2. **Given** une fenêtre pinée sur tous les desktops, **When** l'utilisateur choisit "Retirer le pin", **Then** la fenêtre reste visible uniquement dans le contexte actif courant.
3. **Given** une fenêtre non pinée, **When** l'utilisateur ouvre le menu de barre de titre, **Then** les actions de pin sont proposées et l'action de retrait n'est pas présentée comme active.

---

### Edge Cases

- Une fenêtre déjà exclue du tiling doit pouvoir être pinée sans devenir tileable.
- Une fenêtre tileable pinée doit rester hors du calcul de layout pendant qu'elle est pinée, afin d'éviter les sauts de layout.
- Une fenêtre pinée puis fermée doit être retirée automatiquement des états de pin.
- Une fenêtre pinée déplacée vers une autre stage, un autre desktop ou un autre écran doit avoir un état de pin cohérent avec sa nouvelle destination.
- Une fenêtre pinée ne doit jamais apparaître plusieurs fois dans les menus de destination ou dans le rail.
- Si le menu de barre de titre est désactivé, aucun nouveau point d'entrée de pin n'est requis pour cette version.
- Les fenêtres système transitoires, dialogues, panneaux de sauvegarde et popups ne doivent pas être pinées par accident.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: Roadie MUST allow the user to pin an eligible window so it remains visible across all stages of the current desktop only.
- **FR-002**: Roadie MUST allow the user to pin an eligible window so it remains visible across all Roadie desktops on the same display.
- **FR-003**: Roadie MUST provide a clear way to remove an existing pin from an eligible pinned window.
- **FR-004**: Roadie MUST expose pin and unpin actions from the existing title bar context menu when that menu is enabled.
- **FR-005**: Roadie MUST clearly distinguish a desktop-scoped pin from an all-desktops pin in user-facing labels.
- **FR-006**: Roadie MUST preserve the current position and size of a pinned window unless the user moves or resizes it.
- **FR-007**: Roadie MUST keep pinned windows out of automatic tiled layout calculations while they are pinned.
- **FR-008**: Roadie MUST continue to hide pinned windows when their pin scope does not include the active desktop or stage context.
- **FR-009**: Roadie MUST clean up pin state automatically when the pinned window closes or can no longer be found.
- **FR-010**: Roadie MUST prevent duplicate ownership of a pinned window across stages, desktops, or displays.
- **FR-011**: Roadie MUST keep existing stage switching, desktop switching, and floating-window behavior unchanged for windows that are not pinned.
- **FR-012**: Roadie MUST avoid offering pin actions for transient system panels where pinning would create confusing or unstable behavior.
- **FR-013**: Roadie MUST make the current pin state understandable from the menu before the user changes it.

### Key Entities

- **Pinned Window**: A window selected by the user to remain visible beyond its normal stage membership. Key attributes include the target window, the pin scope, and the last known placement.
- **Pin Scope**: The visibility boundary chosen by the user. Supported scopes for this feature are current desktop and all desktops on the same display.
- **Pin State**: The durable state that determines whether a window is pinned, how it should be shown or hidden during context changes, and when it should be removed.
- **Eligible Window**: A user-facing window that Roadie can safely manage for visibility without treating transient system panels as persistent work items.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: In manual testing, a desktop-scoped pinned window remains visible across 10 consecutive stage changes in the same desktop and is hidden on 10 consecutive switches to another desktop.
- **SC-002**: In manual testing, an all-desktops pinned window remains visible across 10 consecutive desktop changes and 10 consecutive stage changes on the same display.
- **SC-003**: Removing a pin returns the window to normal single-context visibility in under 2 seconds from the user's action.
- **SC-004**: Pinning and unpinning a window does not cause unrelated tiled windows to move in at least 95% of repeated stage and desktop switch checks.
- **SC-005**: Closed pinned windows are removed from visible pin behavior with no user action required during the next normal Roadie refresh.
- **SC-006**: Users can identify the active pin state and choose the correct pin action from the title bar context menu without needing to know internal stage IDs.

## Assumptions

- Pinning is limited to windows that Roadie already tracks as belonging to a display and user context.
- "Tous les desktops" means all Roadie virtual desktops on the same display; moving a pinned window to another display is handled by existing move actions.
- A pinned window should behave visually like a floating window, not as an extra tile in the current layout.
- The title bar context menu remains the primary entry point for this feature.
- Pin actions are intentionally separate from stage assignment and desktop assignment actions.
- Existing safeguards for transient panels and system popups continue to apply.
