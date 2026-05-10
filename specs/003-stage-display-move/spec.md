# Feature Specification: Stage Display Move

**Feature Branch**: `028-stage-display-move`  
**Created**: 2026-05-10  
**Status**: Draft  
**Input**: User description: "1 ok. 2 ok, ok pour la valeur par défaut mais moi je veux pas le follow. 3 ok et je voudrais un menu contextuel sur clic droit avec une entrée pour envoyer vers un autre écran"

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Envoyer la stage active vers un autre écran (Priority: P1)

En tant qu'utilisateur multi-écran, je veux envoyer la stage active vers un autre écran par une action directe, afin de réorganiser mon espace de travail sans déplacer les fenêtres une par une.

**Why this priority**: C'est le besoin central : Roadie gère déjà des stages et plusieurs écrans, mais il manque une action explicite pour déplacer une stage entière entre écrans.

**Independent Test**: Créer une stage contenant plusieurs fenêtres sur l'écran A, demander son envoi vers l'écran B, puis vérifier que les fenêtres de cette stage sont visibles sur l'écran B et que l'écran A reste dans un état exploitable.

**Acceptance Scenarios**:

1. **Given** une stage active contenant plusieurs fenêtres sur l'écran courant et un second écran disponible, **When** l'utilisateur envoie la stage vers le second écran, **Then** toutes les fenêtres de la stage sont déplacées vers le second écran et conservent leur appartenance à la même stage.
2. **Given** une stage active sur un écran source avec d'autres stages disponibles, **When** la stage active est envoyée vers un écran cible, **Then** l'écran source active une stage restante pertinente au lieu de rester dans un état vide ou incohérent.
3. **Given** un écran cible qui contient déjà ses propres stages, **When** une stage est envoyée vers cet écran, **Then** la stage déplacée y devient disponible sans fusionner accidentellement ses fenêtres avec une autre stage.

---

### User Story 2 - Choisir si le focus suit la stage déplacée (Priority: P2)

En tant qu'utilisateur, je veux choisir si le focus suit la stage quand je l'envoie vers un autre écran, afin de pouvoir soit continuer à travailler sur l'écran source, soit suivre la stage déplacée selon mon usage.

**Why this priority**: La valeur par défaut peut suivre la stage pour rendre l'action visible, mais l'utilisateur a explicitement demandé de pouvoir désactiver ce suivi dans sa configuration personnelle.

**Independent Test**: Configurer le comportement "ne pas suivre", envoyer une stage vers un autre écran, puis vérifier que la stage est déplacée mais que le focus utilisateur reste sur l'écran source.

**Acceptance Scenarios**:

1. **Given** le réglage de suivi du focus activé, **When** l'utilisateur envoie la stage active vers un autre écran, **Then** le focus utilisateur passe sur la stage déplacée sur l'écran cible.
2. **Given** le réglage de suivi du focus désactivé, **When** l'utilisateur envoie la stage active vers un autre écran, **Then** la stage est déplacée mais le focus utilisateur reste sur l'écran source.
3. **Given** aucun réglage utilisateur explicite, **When** une stage est déplacée vers un autre écran, **Then** le comportement par défaut suit la stage déplacée.

---

### User Story 3 - Envoyer une stage depuis le menu contextuel du rail (Priority: P3)

En tant qu'utilisateur, je veux faire un clic droit sur une stage dans le navrail et choisir "envoyer vers un autre écran", afin de déclencher l'action sans mémoriser une commande ou un raccourci.

**Why this priority**: Le menu contextuel rend la fonctionnalité découvrable et plus naturelle pour les opérations ponctuelles, mais il dépend de la logique de déplacement déjà disponible.

**Independent Test**: Ouvrir le menu contextuel d'une carte de stage dans le navrail, choisir un écran cible, puis vérifier que cette stage est déplacée vers l'écran choisi.

**Acceptance Scenarios**:

1. **Given** plusieurs écrans disponibles, **When** l'utilisateur fait un clic droit sur une stage dans le navrail, **Then** le menu propose une action pour envoyer cette stage vers les autres écrans disponibles.
2. **Given** un seul écran disponible, **When** l'utilisateur ouvre le menu contextuel d'une stage, **Then** l'action d'envoi vers un autre écran est absente ou clairement indisponible.
3. **Given** une stage inactive affichée dans le rail, **When** l'utilisateur l'envoie vers un autre écran via le menu contextuel, **Then** la stage ciblée est déplacée sans changer les fenêtres d'une autre stage.

### Edge Cases

- Si l'écran cible n'existe plus au moment de l'action, l'opération échoue proprement et aucune fenêtre n'est perdue.
- Si la stage source est la seule stage de l'écran source, l'écran source doit conserver une stage saine, même vide, pour rester utilisable.
- Si la stage déplacée porte le même identifiant qu'une stage déjà présente sur l'écran cible, le système doit préserver les fenêtres et éviter toute fusion accidentelle non demandée.
- Si la stage déplacée contient des fenêtres qui ne peuvent pas être déplacées ou redimensionnées, les fenêtres déplaçables doivent être traitées et l'utilisateur doit pouvoir diagnostiquer l'échec partiel.
- Si deux écrans ont une disposition spatiale ambigue, les actions par direction doivent refuser les cibles ambigues plutôt que déplacer vers un écran inattendu.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: L'utilisateur DOIT pouvoir envoyer la stage active vers un autre ecran en choisissant un ecran cible.
- **FR-002**: L'utilisateur DOIT pouvoir cibler un ecran par son index visible.
- **FR-003**: L'utilisateur DOIT pouvoir cibler un ecran voisin par direction quand la topologie d'ecrans rend cette direction non ambigue.
- **FR-004**: Le systeme DOIT deplacer toutes les fenetres appartenant a la stage selectionnee vers l'ecran cible en preservant la stage comme groupe coherent.
- **FR-005**: Le systeme DOIT laisser l'ecran source dans un etat utilisable apres le depart d'une stage.
- **FR-006**: Le systeme DOIT fournir une preference utilisateur controlant si le focus suit la stage deplacee.
- **FR-007**: Le comportement par defaut DOIT suivre la stage deplacee, sauf si l'utilisateur a explicitement desactive ce suivi.
- **FR-008**: Quand le suivi du focus est desactive, le deplacement d'une stage DOIT garder le contexte actif de l'utilisateur sur l'ecran source.
- **FR-009**: L'utilisateur DOIT pouvoir ouvrir un menu contextuel depuis une stage du navrail et choisir un ecran cible pour cette stage.
- **FR-010**: Le menu contextuel DOIT proposer uniquement des ecrans cibles valides et NE DOIT PAS proposer l'ecran courant comme cible.
- **FR-011**: Le systeme DOIT permettre de deplacer une stage inactive depuis le navrail sans d'abord la rendre active.
- **FR-012**: Le systeme DOIT echouer sans danger quand l'ecran cible est indisponible, en preservant la stage et ses fenetres sur l'ecran source.
- **FR-013**: Le systeme DOIT exposer un resultat utilisateur clair pour les cas succes, no-op, cible invalide et echec partiel.
- **FR-014**: Les IDs et l'ordre des stages existantes DOIVENT rester stables ; en cas de collision d'ID sur l'ecran cible, Roadie DOIT renumeroter la stage deplacee plutot que fusionner ou supprimer une stage existante non vide.

### Key Entities

- **Stage**: A user-visible group of windows within a Roadie desktop. Key attributes include identity, visible order, active/inactive state, display association, and window membership.
- **Display**: A physical screen known to Roadie. Key attributes include visible index, position relative to other displays, and current active stage.
- **Stage Move Operation**: A user action that selects a source stage and target display, with a focus-follow policy and an observable result.
- **Focus Follow Preference**: A user preference determining whether the user's active context moves with the stage or remains on the source display.
- **Navrail Context Menu**: A contextual interaction attached to a stage card, exposing valid stage-level actions.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A user can move a stage containing at least three windows to another display in one action.
- **SC-002**: In at least 95% of successful stage moves, all movable windows from the stage appear on the target display within one second.
- **SC-003**: With focus following disabled, the user's active context remains on the source display after 100% of successful moves.
- **SC-004**: With focus following enabled or unspecified, the moved stage becomes the active context on the target display after 100% of successful moves.
- **SC-005**: The navrail context menu allows a user to complete a stage-to-display move in no more than two interactions after opening the menu.
- **SC-006**: Invalid or unavailable target display attempts produce no lost windows and leave the original stage membership intact.

## Assumptions

- Roadie already knows the available displays and can identify their relative positions.
- Display indexes are user-visible and stable enough for a single action, but may change when monitor topology changes.
- The first implementation does not need to support dragging a stage card between rails; the required discoverable UI is the contextual menu.
- Focus following defaults to enabled for general users, while this user's configuration should explicitly disable it.
- Moving a stage means moving the stage's windows and stage ownership, not copying or duplicating the stage.
- Existing commands and shortcuts that target stages by ID or visible position must continue to behave as they do today.
