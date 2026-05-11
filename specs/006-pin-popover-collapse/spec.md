# Feature Specification: Pin Popover Collapse

**Feature Branch**: `006-pin-popover-collapse`  
**Created**: 2026-05-11  
**Status**: Draft  
**Input**: User description: "un menu comme ca, déclenché par un pseudo bouton cercle bleu qui ressemble aux boutons macos en type (cercle) et taille, qui doublonne les fonctionalités qu'on a sur le clic droit sur les barre de titre et qui ajoute le repliage d'une fenetre comme tu recommandes option 2) et ca permettrait aussi de gerer les mode pins qui restera a affiner dans un secon temps"

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Ouvrir un menu de pin depuis un bouton visible (Priority: P1)

En tant qu'utilisateur, je veux voir un petit bouton circulaire bleu sur les fenêtres pinées afin d'accéder rapidement aux actions de pin sans devoir retrouver le clic droit sur la barre de titre.

**Why this priority**: C'est le point d'entrée de toute la feature. Sans bouton visible et fiable, le menu ne résout pas le problème d'accessibilité des actions de pin.

**Independent Test**: Pinner une fenêtre, vérifier qu'un bouton circulaire bleu apparaît dans la zone de titre sans masquer les boutons natifs essentiels, cliquer dessus, puis vérifier que le menu affiche les mêmes actions principales que le menu existant de barre de titre.

**Acceptance Scenarios**:

1. **Given** une fenêtre pinée visible, **When** l'utilisateur regarde sa barre de titre, **Then** un bouton circulaire bleu de taille comparable aux boutons macOS est visible et identifiable comme contrôle Roadie.
2. **Given** une fenêtre pinée visible, **When** l'utilisateur clique sur le bouton circulaire bleu, **Then** un menu compact de style macOS apparaît à proximité du bouton.
3. **Given** une fenêtre non pinée, **When** l'utilisateur regarde sa barre de titre, **Then** aucun bouton de pin permanent n'est affiché sauf si Roadie est dans un mode explicitement prévu pour pinner cette fenêtre.

---

### User Story 2 - Utiliser un menu visuel cohérent avec les actions existantes (Priority: P1)

En tant qu'utilisateur, je veux que le menu du bouton donne accès aux mêmes actions que le clic droit de barre de titre afin de ne pas avoir deux modèles mentaux différents pour déplacer, pinner ou dépinner une fenêtre.

**Why this priority**: Le menu ne doit pas devenir un second système divergent. Il doit rendre les actions existantes plus découvrables, pas ajouter de confusion.

**Independent Test**: Depuis une fenêtre pinée, ouvrir le menu bouton et vérifier que les actions de stage, desktop, écran et pin disponibles dans le clic droit sont présentes avec des libellés cohérents et des destinations filtrées de la même manière.

**Acceptance Scenarios**:

1. **Given** une fenêtre pinée, **When** l'utilisateur ouvre le menu du bouton, **Then** il peut envoyer la fenêtre vers une stage, un desktop ou un écran selon les mêmes règles que le menu de barre de titre.
2. **Given** une fenêtre pinée en mode "ce desktop", **When** l'utilisateur ouvre le menu, **Then** il voit clairement l'état actif et l'action permettant de passer vers "tous les desktops".
3. **Given** une fenêtre pinée en mode "tous les desktops", **When** l'utilisateur ouvre le menu, **Then** il voit clairement l'état actif et l'action permettant de revenir vers "ce desktop".
4. **Given** une action indisponible dans le contexte courant, **When** le menu est affiché, **Then** l'action est absente ou désactivée avec une présentation non ambiguë.

---

### User Story 3 - Replier une fenêtre pinée en proxy de titre (Priority: P2)

En tant qu'utilisateur, je veux replier une fenêtre pinée pour libérer la vue sur les fenêtres dessous, tout en gardant un repère visible et restaurable.

**Why this priority**: Les pins peuvent masquer des fenêtres dans d'autres stages ou desktops. Le repliage est la réponse fonctionnelle principale au problème "comment voir ce qui est dessous ?".

**Independent Test**: Pinner une fenêtre qui recouvre une autre fenêtre, la replier depuis le menu, vérifier que la fenêtre réelle ne masque plus la fenêtre dessous, puis restaurer la fenêtre depuis le proxy visible.

**Acceptance Scenarios**:

1. **Given** une fenêtre pinée visible, **When** l'utilisateur choisit "Replier" dans le menu, **Then** la fenêtre ne masque plus le contenu dessous et un proxy compact reste visible à l'emplacement attendu.
2. **Given** une fenêtre pinée repliée, **When** l'utilisateur clique ou active le proxy, **Then** la fenêtre retrouve son état visible précédent avec sa position et sa taille précédentes.
3. **Given** une fenêtre pinée repliée, **When** l'utilisateur change de stage ou de desktop dans le scope du pin, **Then** le proxy reste disponible sans déclencher de saut de layout.
4. **Given** une fenêtre pinée repliée, **When** l'utilisateur retire le pin, **Then** le proxy disparaît et la fenêtre redevient une fenêtre normale dans un contexte unique.

---

### User Story 4 - Préparer l'affinage futur des modes de pin (Priority: P3)

En tant qu'utilisateur avancé, je veux que le menu puisse exposer les modes de pin actuels et futurs sans réorganiser toute l'interface plus tard.

**Why this priority**: Les modes exacts de pin restent à affiner, mais l'interface doit déjà réserver une zone claire pour les modes afin d'éviter de casser l'expérience utilisateur lors d'une évolution.

**Independent Test**: Ouvrir le menu d'une fenêtre pinée et vérifier qu'une zone "Pin" ou équivalente regroupe les modes actuels, l'état actif et les actions liées au pin sans mélanger ces choix avec les déplacements de fenêtre.

**Acceptance Scenarios**:

1. **Given** une fenêtre pinée, **When** le menu est ouvert, **Then** les modes de pin sont regroupés dans une zone dédiée et lisible.
2. **Given** l'ajout futur d'un nouveau mode de pin, **When** ce mode est exposé dans le menu, **Then** il peut être ajouté dans la zone des modes sans changer les actions principales de déplacement.

### Edge Cases

- Une fenêtre est trop petite pour afficher le bouton sans masquer des contrôles utiles.
- Une application dessine une barre de titre personnalisée ou très dense.
- Une fenêtre pinée est en plein écran natif ou dans un état où les overlays Roadie ne doivent pas gêner les contrôles système.
- Le menu est ouvert puis la fenêtre disparaît, change de stage ou est dépinnée par un autre raccourci.
- Plusieurs fenêtres pinées sont proches ou se chevauchent.
- Le proxy d'une fenêtre repliée risque de masquer un élément critique ou de sortir de l'écran.
- Une fenêtre repliée appartient à une application qui se ferme ou recrée sa fenêtre.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: Roadie MUST display a compact circular blue control on pinned windows when the feature is enabled.
- **FR-002**: The control MUST visually resemble a macOS titlebar control in shape and approximate size while remaining identifiable as a Roadie control.
- **FR-003**: The control MUST avoid covering native close, minimize, zoom, fullscreen, or common titlebar controls whenever there is enough space.
- **FR-004**: Users MUST be able to open a compact contextual menu from the control.
- **FR-005**: The menu MUST use a macOS-like visual hierarchy: grouped actions, compact spacing, clear active states, separators where needed, and no marketing or explanatory copy.
- **FR-006**: The menu MUST expose the same window movement destinations already available from the titlebar context menu when those destinations are valid for the current window.
- **FR-007**: The menu MUST expose the current pin state and allow switching between the current supported pin scopes.
- **FR-008**: The menu MUST allow removing the pin from the selected window.
- **FR-009**: The menu MUST allow collapsing a pinned window into a compact proxy without resizing the underlying application window as the primary user-facing behavior.
- **FR-010**: A collapsed pinned window MUST preserve enough visible identity for the user to recognize it, including at least its application or title.
- **FR-011**: Users MUST be able to restore a collapsed pinned window from its proxy.
- **FR-012**: Collapsing and restoring MUST preserve the user's previous window position and size as perceived before collapse.
- **FR-013**: A collapsed pin MUST remain associated with the same pin scope until the user changes or removes the pin.
- **FR-014**: The proxy for a collapsed pin MUST not participate in the normal tiling layout.
- **FR-015**: The menu MUST keep pin-mode choices grouped separately from stage, desktop, and display movement actions.
- **FR-016**: Roadie MUST provide a way to disable this visible pin control while keeping the existing titlebar context menu behavior available.
- **FR-017**: If the control cannot be placed safely on a specific window, Roadie MUST avoid displaying it on that window rather than covering native application controls.
- **FR-018**: The feature MUST not change the behavior of non-pinned windows unless the user explicitly invokes a pin-related action.
- **FR-019**: The feature MUST not trigger layout oscillation, stage switching, or focus redirection merely because the menu or collapsed proxy is visible.
- **FR-020**: Roadie MUST expose enough user-facing state to understand whether a pinned window is visible, collapsed, pinned to the current desktop, or pinned to all desktops.

### Key Entities

- **Pinned Window Control**: The small circular visible entry point attached to a pinned window.
- **Pin Action Menu**: The compact menu opened from the control, grouping movement actions, pin state, pin modes, collapse, restore, and unpin.
- **Collapsed Pin Proxy**: A compact visible representation of a collapsed pinned window that can restore the real window.
- **Pin Presentation State**: The user-visible state of a pin: visible, collapsed, restored, current scope, and safe placement status.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: In manual testing, users can find and open the pin menu from a pinned window in under 2 seconds without being told to right-click the titlebar.
- **SC-002**: 95% of menu openings appear adjacent to the intended pinned window control without covering native window controls.
- **SC-003**: Users can collapse and restore a pinned window 20 consecutive times without the window losing its previous perceived position or size.
- **SC-004**: After collapsing a pinned window, the previously covered window or desktop area becomes interactable in under 1 second.
- **SC-005**: Switching stage or desktop 20 times with one collapsed pin produces no unexpected stage changes, focus loops, or layout jumps.
- **SC-006**: The menu exposes all actions already available from the titlebar context menu for the same window context, except actions that are intentionally unavailable in that context.
- **SC-007**: Users can disable the visible pin control and still use the existing titlebar context menu workflow.

## Assumptions

- The first version targets pinned windows only; non-pinned windows keep the existing titlebar context menu as the main entry point.
- The visual objective is inspired by the macOS window control popover, but the feature is a Roadie control menu, not a clone of macOS tiling behavior.
- Collapsing uses a Roadie-owned proxy as the intended UX model rather than attempting to force every application window to a real titlebar-only height.
- The exact future pin modes are intentionally out of scope; this feature only reserves and organizes the menu area that will host them.
- Existing pin scopes remain the initial supported modes: current desktop and all desktops on the same display.
- Safety is preferred over always showing the button: if placement is ambiguous or risky, the visible control may be omitted for that window.
