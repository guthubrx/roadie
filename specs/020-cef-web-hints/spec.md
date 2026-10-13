# Feature Specification: Lettres d'accès dans Bluejay (CEF et contenu web sans sémantique)

**Feature Branch**: `020-cef-web-hints`
**Created**: 2026-10-13
**Status**: Implemented
**Dependencies**: SPEC-009-roadie-target-mode, SPEC-018-electron-app-hints (événement `targets.app_scan`, parcours borné, filtre visible)
**Input**: User description: "Je voudrais qu'on fasse pareil pour Grayjay. Je souhaiterais qu'on ne modifie pas Grayjay mais qu'on comprenne pourquoi ça marche pas et qu'on fasse le nécessaire dans Roadie." Puis : "J'utilise mon propre build de Grayjay qui est Bluejay, on peut pas forcer le --force-renderer-accessibility dedans ?" Choix utilisateur : option toujours active dans Bluejay (branche `pr/*`), Grayjay officiel non modifié.

## Constat de départ

- `~/.roadies/events.jsonl`, 2026-10-13 vers 04:00 UTC : trois sessions dans `com.futo.grayjay.desktop`, 6 à 7 éléments lus, 4 candidats (boutons de fenêtre), aucune zone web, `manualAccessibility=skipped`.
- Grayjay et Bluejay embarquent CEF 141 (`Chromium Embedded Framework.framework`), pas Electron. Le binaire CEF ne contient pas `AXManualAccessibility`. La classe application de JustCef (`JustCef/native/src/main_mac.mm`) ne gère aucun attribut d'accessibilité : une demande externe est sans effet.
- Lancé avec `--force-renderer-accessibility` (transmis par `ReconstructArgs`, `Grayjay.Desktop.CEF/Program.cs:148`), Grayjay publie sa zone web : 410 éléments lus, profondeur 11. Mais Roadie ne retient que 7 cibles.
- L'interface est en SolidJS : 134 `<div onClick>` contre 39 `<button>` et 2 liens. SolidJS délègue les clics au document : Chromium ne marque pas ces `div` comme cliquables.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Bluejay publie son contenu (Priority: P1)

L'utilisateur lance Bluejay normalement (Dock, Spotlight). Bluejay publie son arbre d'accessibilité sans option à taper.

**Why this priority**: sans arbre publié, aucun tri ne peut fonctionner.

**Independent Test**: Bluejay lancé depuis le Dock ; un double Commande écrit `targets.app_scan` avec `sawWebArea=true`.

**Acceptance Scenarios**:

1. **Given** Bluejay construit avec la branche d'accessibilité, **When** l'utilisateur le lance sans argument, **Then** le moteur CEF reçoit `--force-renderer-accessibility` sur macOS.
2. **Given** Grayjay officiel, **When** il est lancé, **Then** rien ne change pour lui (aucune modification du dépôt amont).

---

### User Story 2 - Des lettres sur les éléments cliquables d'une page web sans sémantique (Priority: P1)

Dans Bluejay, l'utilisateur appuie deux fois sur Commande. Les entrées de la barre latérale, les vignettes vidéo et les boutons visibles reçoivent une lettre. Une lettre ouvre l'élément visé.

**Why this priority**: c'est le résultat attendu ; l'arbre seul donne 7 cibles.

**Independent Test**: Bluejay sur la page d'accueil, double Commande : au moins 20 cibles, dont les entrées de la barre latérale ; la lettre d'une entrée ouvre la page correspondante.

**Acceptance Scenarios**:

1. **Given** une zone web dont les éléments cliquables n'exposent pas d'action, **When** Roadie construit les cibles, **Then** il retient ces éléments selon une règle mesurée sur l'arbre réel de Bluejay.
2. **Given** un élément cliquable qui contient du texte et une image, **When** Roadie construit les cibles, **Then** il pose une seule lettre pour l'élément, pas une par enfant.
3. **Given** une application native (Finder) ou T3 Code, **When** l'utilisateur lance le mode lettres, **Then** le nombre de cibles reste celui mesuré avant la feature (Finder 58, T3 Code 150 avec la configuration actuelle).

---

### User Story 3 - Un tri mesurable (Priority: P2)

L'événement `targets.app_scan` indique la répartition des rôles lus et écartés, pour ajuster le tri avec des chiffres.

**Independent Test**: après une session, l'événement contient la répartition des rôles écartés.

### Edge Cases

- Une page très longue : la limite `max_targets` et le filtre visible de la spec 018 restent appliqués.
- Un élément ni focalisable ni doté d'action : pas de lettre (le critère est la focalisabilité exposée par Chromium, pas le contenu).
- Bluejay lancé sans la branche d'accessibilité : comportement d'aujourd'hui, sans erreur.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: Bluejay MUST passer `--force-renderer-accessibility` au moteur CEF sur macOS, par une branche locale `pr/*` intégrée à la build Bluejay. Grayjay amont MUST NOT être modifié.
- **FR-002**: Dans une zone web (`AXWebArea`), Roadie MUST retenir comme cibles les éléments cliquables qui n'exposent pas d'action, selon une règle fondée sur la mesure de l'arbre réel de Bluejay (research.md).
- **FR-003**: Roadie MUST poser au plus une lettre par élément cliquable : un élément situé sous une cible de zone web déjà retenue, ou contenant un autre élément focalisable, ne reçoit pas de lettre en plus.
- **FR-004**: Hors zone web, le tri MUST rester inchangé.
- **FR-005**: `targets.app_scan` MUST indiquer la répartition des rôles écartés.
- **FR-006**: Aucune nouvelle clé de configuration, sauf si la mesure prouve qu'un réglage utilisateur est indispensable.

## Success Criteria *(mandatory)*

- **SC-001**: Bluejay, page d'accueil : au moins 20 cibles, contre 7 avec l'arbre publié et le tri actuel.
- **SC-002**: La lettre d'une entrée de la barre latérale ouvre la page correspondante (validation utilisateur).
- **SC-003**: Finder et T3 Code : nombre de cibles inchangé (± 5 %).
- **SC-004**: Aucune cible en double pour un même élément cliquable dans Bluejay.

## Assumptions

- La règle de tri visera les signaux exposés par Chromium dans l'arbre (rôle, texte, image, actions, attributs DOM exposés) ; elle sera choisie après mesure.
- Le coût CPU de l'arbre toujours actif dans Bluejay est accepté par l'utilisateur.
- Le worktree d'intégration Bluejay (`grayjay-bluejay-all-features`) est absent du disque ; sa restauration fait partie de la livraison Bluejay.
