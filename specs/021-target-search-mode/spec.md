# Feature Specification: Mode recherche du mode lettres

**Feature Branch**: `021-target-search-mode`
**Created**: 2026-10-13
**Status**: Draft
**Dependencies**: SPEC-009-roadie-target-mode (cibles, labels, activation, picker), SPEC-018-electron-app-hints et SPEC-020-cef-web-hints (cibles applicatives dans les zones web)
**Input**: User description: "Comme dans Homerow, un raccourci qui m'ouvre une petite zone de saisie en bas d'écran, qui me permette de taper un texte, et ça illumine l'étiquette, et si je valide ça bascule." Puis : « fais tout ça » (P1 recherche, P2 variantes de clic, P3 `*` et `?`). Raccourci : « mon Caps Lock est une hyper key […] je veux que ça soit ça par défaut, mais il faut que ça soit paramétrable. »

## Constat de départ

- Le mode lettres actuel (`TargetOverlayPresenter.swift`, session interactive) n'accepte que la frappe d'un label ; Échap annule ; Retour confirme un label complet. Le type de clic est fixé au lancement (`--action`).
- La recherche par texte existe seulement en ligne de commande (`roadie targets pick`), avec une normalisation de la casse, des accents et des espaces multiples (`TargetHintService.normalized`) et un filtre « contient ».
- La hyper key de l'utilisateur (Karabiner, règle « CAPS_LOCK to HYPER ») envoie Commande + Option + Contrôle. Hyper + F n'est utilisé ni dans Karabiner ni dans BetterTouchTool. Homerow conseille Hyper + F.
- Roadie n'enregistre aucun raccourci global aujourd'hui ; le mode lettres est lancé par BetterTouchTool.
- Dans les zones web, la cible cliquable (carte, entrée de menu) n'a souvent pas de texte propre : le texte est dans ses enfants (`AXStaticText`).

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Chercher un élément par son texte et l'activer (Priority: P1)

L'utilisateur appuie sur Hyper + F. Une zone de saisie apparaît en bas de l'écran, avec les lettres des cibles. Il tape un texte. Seules les cibles qui correspondent restent visibles ; l'une d'elles est mise en avant. Il passe d'une correspondance à l'autre au clavier, puis valide : Roadie clique sur l'élément mis en avant.

**Why this priority**: c'est la demande ; c'est plus rapide qu'une lettre quand on connaît le texte de l'élément.

**Independent Test**: Bluejay au premier plan, Hyper + F, taper « subscr » : l'entrée « Subscriptions » est mise en avant ; Retour ouvre la page Abonnements.

**Acceptance Scenarios**:

1. **Given** une app au premier plan, **When** l'utilisateur appuie sur le raccourci de recherche, **Then** une zone de saisie apparaît en bas de l'écran actif et les lettres des cibles s'affichent.
2. **Given** la zone de saisie, **When** l'utilisateur tape un texte, **Then** seules les cibles dont le texte correspond restent affichées, sans tenir compte de la casse, des accents ni des espaces, et la première est mise en avant.
3. **Given** plusieurs correspondances, **When** l'utilisateur appuie sur Tab, Flèche bas ou Ctrl-N (suivante) ou Maj-Tab, Flèche haut ou Ctrl-P (précédente), **Then** la mise en avant passe à la correspondance suivante ou précédente, en boucle.
4. **Given** une correspondance mise en avant, **When** l'utilisateur appuie sur Retour, **Then** Roadie l'active (clic) et ferme la recherche.
5. **Given** des correspondances, **When** l'utilisateur tape le label d'une cible en maintenant Maj, **Then** la mise en avant saute sur cette cible.
6. **Given** la recherche ouverte, **When** l'utilisateur appuie sur Échap, **Then** elle se ferme sans action.
7. **Given** une cible de zone web sans texte propre, **When** son texte est porté par ses enfants, **Then** la recherche la trouve par ce texte.

---

### User Story 2 - Choisir le type de clic au moment de valider (Priority: P2)

**Acceptance Scenarios**:

1. **Given** une correspondance mise en avant, **When** l'utilisateur appuie sur Maj-Retour, **Then** Roadie fait un clic droit.
2. **When** Cmd-Retour, **Then** Roadie fait un Cmd-clic (ouvrir dans un nouvel onglet).
3. **When** Retour deux fois rapidement, **Then** Roadie fait un double-clic.

---

### User Story 3 - Tout afficher et inspecter (Priority: P3)

**Acceptance Scenarios**:

1. **Given** la zone de saisie, **When** l'utilisateur tape `*` ou `;`, **Then** toutes les cibles s'affichent.
2. **Given** une correspondance mise en avant, **When** l'utilisateur tape `?`, **Then** la zone affiche les propriétés recherchables de cette cible (rôle, titre, valeur, texte) jusqu'à la frappe suivante.

---

### User Story 4 - Raccourci paramétrable (Priority: P1)

**Acceptance Scenarios**:

1. **Given** une configuration sans réglage, **When** Roadie démarre, **Then** le raccourci de recherche est Commande + Option + Contrôle + F.
2. **Given** un autre raccourci dans la configuration, **When** la configuration est rechargée, **Then** le nouveau raccourci remplace l'ancien sans redémarrage.
3. **Given** un raccourci invalide, **When** la configuration est validée, **Then** Roadie le signale ; au rechargement, la dernière configuration valide reste appliquée (comportement existant). Une chaîne vide désactive le raccourci.
4. **Given** un changement de disposition clavier, **When** la touche physique du caractère change, **Then** le raccourci est réenregistré sur la nouvelle touche.

### Edge Cases

- Aucune correspondance : la zone l'indique ; Retour ne fait rien.
- Le mode lettres classique (double Commande, BetterTouchTool) reste inchangé.
- L'app au premier plan ne publie pas son arbre : seules les cibles Roadie (fenêtres, stages) sont cherchables.
- Le raccourci est déjà pris par une autre app : l'enregistrement échoue, Roadie le journalise sans planter.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: Roadie MUST ouvrir un mode recherche par un raccourci global, Commande + Option + Contrôle + F par défaut, réglable dans la configuration et rechargeable à chaud.
- **FR-002**: Le mode recherche MUST afficher une zone de saisie en bas de l'écran actif et les lettres des cibles correspondantes.
- **FR-003**: La correspondance MUST ignorer la casse, les accents et les espaces, et porter sur le titre, la valeur, le rôle et le texte des enfants pour les cibles web.
- **FR-004**: Une correspondance MUST être mise en avant visuellement ; Tab/Flèche bas/Ctrl-N et Maj-Tab/Flèche haut/Ctrl-P MUST la déplacer en boucle ; Maj + label MUST y sauter.
- **FR-005**: Retour MUST cliquer ; Maj-Retour clic droit ; Cmd-Retour Cmd-clic ; deux Retour rapprochés double-clic. Échap MUST fermer sans action.
- **FR-006**: `*` et `;` MUST afficher toutes les cibles ; `?` MUST afficher les propriétés de la cible mise en avant.
- **FR-007**: Le mode lettres existant MUST rester inchangé.
- **FR-008**: Le texte des enfants rattaché aux cibles web MUST rester dans le budget de parcours existant (`timeout_ms`).
- **FR-009** (ajout du 2026-10-13) : Le mode recherche MUST couvrir toutes les fenêtres visibles de l'espace courant, pas seulement la fenêtre active. Les fenêtres sont lues en parallèle, avec la même échéance `timeout_ms`. Un élément caché par une fenêtre placée devant n'a pas de lettre.
- **FR-010** (ajout du 2026-10-13) : Valider une cible d'une autre fenêtre MUST focaliser cette fenêtre, attendre que son application soit active (0,5 s au plus), puis cliquer.
- **FR-011** (ajout du 2026-10-13) : Le mode lettres MUST garder la fenêtre active par défaut. `app_targets.scope = "visible_windows"` MUST l'étendre aux fenêtres visibles.
- **FR-012** (correctif du 2026-10-13) : Une feuille web sans action (règle « feuille focalisable ») MUST être cliquée au centre de sa première image ou de son premier texte visible, et non au centre de l'élément. Mesure Bluejay : le centre d'une ligne de l'Historique ne réagit pas ; seuls la vignette, le titre et l'auteur ont un gestionnaire de clic.

## Success Criteria *(mandatory)*

- **SC-001**: Bluejay, « subscr » puis Retour ouvre la page Abonnements (validation utilisateur).
- **SC-002**: Le titre d'une vidéo de Bluejay (texte d'un enfant) la trouve.
- **SC-003**: Hyper + F ouvre la recherche en moins de 700 ms dans Bluejay (budget actuel).
- **SC-004**: Maj-Retour fait un clic droit et Cmd-Retour un Cmd-clic sur la cible mise en avant (validation utilisateur).
- **SC-005**: Changer le raccourci dans la configuration prend effet sans redémarrer Roadie.
- **SC-006**: Le mode lettres classique garde ses cibles : T3 Code 150, Finder 58 avec la configuration actuelle.

## Assumptions

- « Paramétrable » = une clé de la configuration Roadie ; aucune interface graphique.
- La zone de saisie est affichée par Roadie (pas de champ de texte d'une autre app).
- Le mode défilement de Homerow est hors périmètre (boîte à idées).
