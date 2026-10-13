# Feature Specification: Lettres d'accès dans les applications Electron

**Feature Branch**: `018-electron-app-hints`
**Created**: 2026-10-12
**Status**: Implemented
**Dependencies**: SPEC-009-roadie-target-mode (mode lettres, découverte des cibles applicatives, User Story 15 « AX boost »)
**Input**: User description: "Quand on fait deux fois Commande, ça affiche des petites lettres pour accéder directement. Ça marche très bien, sauf dans les applications Electron comme T3 Code. Est-ce qu'on sait le faire mieux maintenant ?"

## Constat de départ

Le journal `~/.roadies/events.jsonl` du 2026-10-12 montre trois sessions de lettres dans T3 Code (pid 60116). Chaque session a trouvé une seule cible applicative : la fenêtre elle-même (`app:60116/0`). Le parcours s'est terminé sans dépassement de temps (`partial=false`). L'application n'a donc rien publié sous sa fenêtre. Dans Outlook, le même mécanisme trouve des éléments profonds (`app:17531/0.7.0.0.2.0.1`).

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Des lettres sur les éléments d'une application Electron (Priority: P1)

L'utilisateur est dans T3 Code. Il appuie deux fois sur Commande. Roadie affiche des lettres sur les éléments cliquables visibles de la fenêtre : fils de la barre latérale, boutons, champ de saisie. L'utilisateur tape une lettre et Roadie clique sur l'élément.

**Why this priority**: c'est la demande. Aujourd'hui, le mode lettres ne sert à rien dans les applications Electron.

**Independent Test**: T3 Code au premier plan, double Commande. Plus de 10 lettres apparaissent sur des éléments visibles de T3 Code. La lettre d'un fil de la barre latérale ouvre ce fil.

**Acceptance Scenarios**:

1. **Given** une application Electron au premier plan qui n'a jamais publié son contenu, **When** l'utilisateur lance le mode lettres, **Then** Roadie demande à l'application de publier son contenu ; dès la session suivante, il affiche des lettres sur ses éléments cliquables. *(Amendé le 2026-10-13 après mesure et décision utilisateur : l'application construit son arbre en arrière-plan, la toute première session peut ne montrer que la fenêtre.)*
2. **Given** une application Electron qui publie déjà son contenu, **When** l'utilisateur lance le mode lettres, **Then** Roadie n'attend pas et affiche les lettres immédiatement.
3. **Given** une application native (Finder, Outlook), **When** l'utilisateur lance le mode lettres, **Then** le résultat est identique à aujourd'hui, sans attente supplémentaire.

---

### User Story 2 - Seulement des lettres utiles et cliquables (Priority: P2)

Une application web contient souvent des éléments hors de la partie visible : historique de conversation défilé, menus repliés. Roadie ne pose une lettre que sur un élément visible dans la fenêtre. Ainsi, une lettre ne clique jamais sur une autre fenêtre placée au même endroit.

**Why this priority**: sans ce tri, les éléments cachés consomment la limite de cibles. Pire, un clic sur un élément caché tombe sur ce qui est affiché à cet endroit de l'écran.

**Independent Test**: un test unitaire fournit des éléments dans et hors du cadre de la fenêtre. Seuls les éléments visibles reçoivent une lettre.

**Acceptance Scenarios**:

1. **Given** un élément dont le cadre est entièrement hors de la fenêtre, **When** Roadie construit les cibles, **Then** cet élément n'a pas de lettre.
2. **Given** un élément partiellement visible, **When** Roadie construit les cibles, **Then** il a une lettre.

---

### User Story 3 - Un parcours mesurable (Priority: P2)

Chaque parcours d'application laisse une trace : application, nombre d'éléments lus, profondeur atteinte, durée, raison d'arrêt, état de la publication du contenu. Ainsi, on peut régler la profondeur et le budget de temps avec des chiffres, pas des suppositions.

**Why this priority**: la profondeur réelle de l'arbre de T3 Code est inconnue. Sans mesure, le réglage de `max_depth` et `timeout_ms` reste une hypothèse.

**Independent Test**: après une session de lettres, `~/.roadies/events.jsonl` contient ces champs pour l'application au premier plan.

**Acceptance Scenarios**:

1. **Given** une session de lettres, **When** le parcours se termine, **Then** l'événement indique la raison d'arrêt : `complete`, `timeout` ou `limit`.
2. **Given** un parcours qui atteint la profondeur maximale, **When** il se termine, **Then** l'événement indique combien d'éléments se trouvaient à cette profondeur sans que leurs enfants soient lus.

### Edge Cases

- L'application refuse ou ignore la demande de publication (application native) : le parcours continue normalement, sans attente.
- L'application publie son contenu lentement : Roadie attend un délai court et borné, puis affiche ce qu'il a.
- L'application est quittée pendant le parcours : le parcours s'arrête avec un résultat partiel, sans erreur bloquante.
- Une application Electron qui change de comportement quand on publie son contenu (par exemple un mode lecteur d'écran) : la désactivation du boost dans la configuration désactive aussi la demande de publication.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: Avant le parcours, Roadie MUST demander à l'application Electron au premier plan de publier son contenu d'accessibilité, quand le boost AX est actif pour cette application.
- **FR-002**: Quand l'application est une application Electron et qu'un parcours complet (ni coupé par la profondeur, le temps ou la limite) ne trouve pas de zone web, Roadie MUST relancer le parcours après une attente courte, avec une attente totale bornée.
- **FR-003**: Roadie MUST NOT attendre pour une application qui publiait déjà son contenu ou qui ne gère pas la demande.
- **FR-004**: Roadie MUST NOT désactiver la publication après le parcours. Les sessions suivantes sont ainsi immédiates.
- **FR-005**: Roadie MUST exclure des cibles applicatives tout élément dont le cadre ne recoupe pas le cadre de la fenêtre parcourue, et MUST réduire le cadre d'un élément à cheval à sa partie visible, pour que son point de clic reste dans la fenêtre.
- **FR-006**: Roadie MUST journaliser pour chaque parcours : identifiant de l'application, éléments lus, cibles retenues, profondeur atteinte, éléments à la profondeur maximale non explorés, durée, raison d'arrêt, état de la publication, nombre de relances.
- **FR-007**: Le parcours MUST rester isolé du placement des fenêtres (exigence FR-006 de la spec 009) : aucun relayout, aucun changement de stage.
- **FR-008**: Les réglages existants (`ax_boost_enabled`, `additional_boost_bundle_ids`, `max_depth`, `timeout_ms`, `max_targets`) MUST rester les seuls leviers. Aucune nouvelle clé de configuration n'est ajoutée.

### Key Entities

- **Parcours applicatif** : une lecture bornée de l'arbre d'accessibilité de la fenêtre au premier plan. Il porte ses statistiques (éléments lus, profondeur, durée, raison d'arrêt, relances).
- **État de publication** : `enabled` (demande acceptée), `unsupported` (refusée ou ignorée), `skipped` (boost inactif).

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Dans T3 Code, une session de lettres trouve plus de 10 cibles applicatives, contre 1 aujourd'hui.
- **SC-002**: Dans T3 Code, la lettre d'un fil de la barre latérale ouvre ce fil.
- **SC-003**: Pour une application déjà publiée ou native, la durée du parcours ne dépasse pas `timeout_ms` (pas de relance).
- **SC-004**: Une session dure au plus `timeout_ms` + 300 ms, à un appel AX près. *(Amendé le 2026-10-13 : la première session n'est pas garantie complète, voir AS1.1.)*
- **SC-005**: Aucune cible applicative n'a un cadre hors de la fenêtre parcourue.

## Assumptions

- Les applications Electron publient leur contenu quand un outil active l'attribut `AXManualAccessibility` sur l'application. Homerow et Vimac utilisent ce mécanisme. L'attribut est sans effet sur les applications natives.
- La configuration de l'utilisateur active déjà le boost pour toutes les applications (`ax_boost_enabled = true`).
- Le réglage final de `max_depth` et `timeout_ms` dans la configuration de l'utilisateur se fera d'après les mesures de la User Story 3.
- Les navigateurs Chromium (Chrome) utilisent un autre déclencheur (`AXEnhancedUserInterface`), que la spec 017 neutralise pendant l'écriture des cadres. Ils sont hors périmètre.
