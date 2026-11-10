# Feature Specification: Consolidation du projet Roadie

**Feature Branch**: `155-consolidation-projet`
**Created**: 2026-11-10
**Status**: In Progress
**Input**: « tout jusqu'a avant l'implémentation pour un modle qui sera moins fort que toi (openai sol) »

## Cadrage

### Demande initiale

La revue du projet du 10 novembre 2026 a livré 15 propositions. L'utilisateur demande de
préparer « tout », jusqu'à l'étape qui précède l'implémentation. Un autre modèle, moins
capable, écrira le code.

### Demande reformulée

Préparer un dossier de spécification complet pour les 15 propositions de la revue. Chaque
proposition reçoit un de ces trois sorts : un lot de travail, une décision à prendre par
l'utilisateur, ou une exclusion avec sa raison mesurée. Le dossier s'arrête avant le code.
Il doit suffire à un modèle moins capable : chaque tâche donne le fichier, le texte avant,
le texte après, la commande de contrôle et le résultat attendu. Aucune tâche ne laisse un
choix de conception à l'implémenteur.

### Ce que cela apporte

- Les propositions de la revue ont été mesurées avant d'être retenues. Deux d'entre elles
  ont changé : la purge automatique ne libère que 2,35 Mo et supprime des sauvegardes
  nommées à la main ; les lectures d'accessibilité dispersées se réduisent à deux gardes de
  type manquantes.
- Les choix qui engagent l'utilisateur (licence, publication, dépense) sont sortis des
  tâches. Ils sont dans `decisions.md`.
- Les extraits de code ont été compilés et exécutés pendant la préparation. Les résultats
  sont dans `research.md`.

### Critères de réussite du cadrage

- Chaque proposition 1 à 15 figure dans la table de traçabilité ci-dessous.
- Aucune tâche ne dépend d'une décision ouverte.
- Chaque tâche de code a une commande de contrôle avec un résultat attendu.

### Vocabulaire utile

- **Garde de type** : contrôle qui vérifie le type d'une valeur avant de la convertir. Sans
  ce contrôle, une conversion forcée arrête le programme si le type est inattendu.
- **Complétion** : aide du terminal qui propose les commandes quand on appuie sur Tab.
- **Couverture** : part du code exécutée par les tests.
- **CI** (intégration continue) : service qui lance les tests sur une machine distante.
- **Commit du build** : identifiant Git du code qui a servi à construire l'application
  installée.

## Traçabilité des 15 propositions

| N° | Proposition de la revue | Sort | Référence |
|----|-------------------------|------|-----------|
| 1 | Pas de licence | Décision bloquante | `decisions.md` D1 |
| 2 | Version installée en retard, version déclarée deux fois | Lot | US2 |
| 3 | Purge jamais automatique | Exclue par la mesure | `decisions.md` D7, `research.md` R3 |
| 4 | Journal d'événements bruyant | Lot | US6 |
| 5 | Chemin personnel dans `README.fr.md` | Lot | US1 |
| 6 | Captures et preuves publiées | Lot (inventaire seul) | US11, `decisions.md` D8 |
| 7 | Coût d'ajout d'un réglage | Lot | US3 |
| 8 | Section `[launcher]` absente | Décision | `decisions.md` D3 |
| 9 | Très gros fichiers | Lot réduit | US9, `decisions.md` D11 |
| 10 | Lectures d'accessibilité dispersées | Lot réduit | US5 |
| 11 | Pas de CI | Lot (déclenchement manuel) | US8, `decisions.md` D5 |
| 12 | Installation difficile | Lot partiel | US10, `decisions.md` D2, D4, D9, D10 |
| 13 | Outils absents (complétion, formatage, couverture) | Lot partiel | US7, `decisions.md` D12 |
| 14 | `AGENTS.md` trop long | Lot | US4 |
| 15 | Incohérences du dépôt | Lot partiel | US1, `decisions.md` D13 |

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Documentation publique propre (Priority: P1)

Un visiteur du dépôt lit le guide d'installation français. Il voit des chemins valables
pour tout le monde. Un mainteneur cherche une décision d'architecture par son numéro. Il
trouve un seul fichier par numéro.

**Why this priority**: corrections sans risque, visibles par tout lecteur du dépôt.

**Independent Test**: rechercher `/Users/moi` dans les deux README, lister les numéros des
décisions d'architecture, lister les fichiers de sauvegarde suivis par Git.

**Acceptance Scenarios**:

1. **Given** `README.fr.md`, **When** on recherche `/Users/moi`, **Then** aucun résultat.
2. **Given** `docs/decisions/`, **When** on liste les numéros, **Then** chaque numéro
   apparaît une seule fois.
3. **Given** le dépôt, **When** on liste les fichiers suivis dont le nom contient `.bak-`,
   **Then** aucun résultat.

---

### User Story 2 - Version unique et identité du build (Priority: P1)

L'utilisateur veut savoir quel code tourne sur sa machine. Aujourd'hui Roadie affiche
`0.13.0` alors que quinze sessions ont été installées depuis cette version. Il veut voir le
commit du build. Le mainteneur veut changer le numéro de version à un seul endroit.

**Why this priority**: sans identité du build, un rapport de bogue ne dit pas quel code est
en cause.

**Independent Test**: installer, puis lire `roadied --version` et
`~/.roadies/daemon-status.json`.

**Acceptance Scenarios**:

1. **Given** Roadie installé par `make install` depuis un dépôt Git propre, **When**
   l'utilisateur lance `roadied --version`, **Then** la sortie est
   `roadied <version> (<8 caractères du commit>)`.
2. **Given** un dépôt avec des changements non commités, **When** on installe, **Then** le
   commit affiché finit par `-dirty`.
3. **Given** un binaire lancé hors de Roadie.app, **When** on lance `roadied --version`,
   **Then** la sortie est `roadied <version>` sans parenthèses.
4. **Given** le daemon installé en marche, **When** on lit `daemon-status.json`, **Then**
   le champ `buildCommit` contient le même commit.
5. **Given** `scripts/package-dmg`, **When** on change la version dans le code source,
   **Then** le DMG prend cette version sans autre modification.
6. **Given** `roadie --version`, **When** on le lance, **Then** la sortie reste
   `roadie <version>` (inchangée).

---

### User Story 3 - Garde-fous des réglages (Priority: P2)

Un développeur ajoute un réglage. S'il oublie de le déclarer au validateur, un test échoue
et nomme le réglage. Il suit une recette écrite qui liste tous les endroits à modifier.

**Why this priority**: 313 réglages ; un oubli produit un réglage refusé ou ignoré chez
l'utilisateur.

**Independent Test**: lancer les deux nouveaux tests ; ils passent. Ajouter un réglage sans
le déclarer ; un test échoue.

**Acceptance Scenarios**:

1. **Given** la configuration par défaut, **When** on compare ses clés aux clés connues du
   validateur, **Then** aucune clé n'est inconnue.
2. **Given** un fichier de configuration vide, **When** on le charge, **Then** le résultat
   est égal à la configuration par défaut.
3. **Given** la recette, **When** un développeur la suit, **Then** elle nomme chaque
   fichier à modifier et le test qui contrôle chaque étape.

---

### User Story 4 - Consignes des agents allégées (Priority: P2)

Un agent ouvre le dépôt. Il lit les règles en quelques lignes. Il trouve les pièges connus
du projet. Le journal des sessions reste disponible dans un fichier séparé.

**Why this priority**: `AGENTS.md` pèse 39 858 octets ; il est chargé dans chaque
conversation.

**Independent Test**: mesurer la taille d'`AGENTS.md`, compter les marqueurs, compter les
lignes du journal déplacé.

**Acceptance Scenarios**:

1. **Given** `AGENTS.md`, **When** on mesure sa taille, **Then** elle est inférieure à
   8 000 octets.
2. **Given** le journal déplacé, **When** on compte ses lignes de journal, **Then** le
   compte égale celui des lignes retirées d'`AGENTS.md`.
3. **Given** `AGENTS.md`, **When** on cherche les quatre marqueurs SpecKit, **Then** chacun
   apparaît une fois, dans le même ordre qu'avant.
4. **Given** `AGENTS.md`, **When** un agent cherche les règles de nettoyage, de revue et
   les pièges connus, **Then** il les trouve dans ce fichier.

---

### User Story 5 - Lectures d'accessibilité sûres (Priority: P2)

Une application répond à une lecture d'accessibilité par une valeur d'un type inattendu.
Roadie ignore cette valeur. Il ne s'arrête pas.

**Why this priority**: un arrêt du daemon coupe le tuilage de toutes les fenêtres.

**Independent Test**: lire les deux sites du code ; chaque conversion forcée est précédée
d'un contrôle de type.

**Acceptance Scenarios**:

1. **Given** les deux sites recensés, **When** on lit le code, **Then** chaque conversion
   vers un élément ou une valeur d'accessibilité suit un contrôle de type.
2. **Given** la suite de tests, **When** on la lance, **Then** elle passe sans régression.

---

### User Story 6 - Journal sans position des clics (Priority: P2)

Roadie n'écrit plus dans son journal la position de chaque clic de souris.

**Why this priority**: ces deux événements font environ 21 % des lignes du journal ; aucun
code ne les lit ; ils enregistrent chaque clic.

**Independent Test**: rechercher les deux noms d'événement dans le code source.

**Acceptance Scenarios**:

1. **Given** le code source, **When** on recherche `drag.real_press` et
   `drag.real_router_press`, **Then** aucun résultat.
2. **Given** Roadie installé, **When** l'utilisateur clique dix fois, **Then** le journal
   ne gagne aucune ligne de ces deux types.
3. **Given** les événements de diagnostic du glisser (`drag.duplicate_press`, annulations),
   **When** on lit le code, **Then** ils sont inchangés.

---

### User Story 7 - Complétion et couverture (Priority: P3)

L'utilisateur tape `roadie` puis Tab dans son terminal ; il voit les commandes. Le
mainteneur lance une commande et lit la part du code exécutée par les tests.

**Why this priority**: confort ; aucun effet sur le produit installé.

**Independent Test**: `roadie completion zsh | zsh -n` ; `make coverage`.

**Acceptance Scenarios**:

1. **Given** `roadie completion zsh`, **When** on vérifie sa sortie avec `zsh -n`, **Then**
   le code de retour est 0.
2. **Given** un terminal zsh qui a chargé la sortie, **When** l'utilisateur tape
   `roadie` puis Tab, **Then** il voit les commandes de premier niveau.
3. **Given** `roadie display` puis Tab, **Then** il voit `list`, `current` et `focus`.
4. **Given** une commande ajoutée à la table des commandes, **When** on régénère la
   complétion, **Then** la commande y figure sans autre modification.
5. **Given** `make coverage`, **When** on le lance, **Then** il affiche un pourcentage
   global ou le chemin du rapport.

---

### User Story 8 - Tests à la demande sur GitHub (Priority: P3)

Le mainteneur lance les tests sur une machine GitHub par un bouton. Rien ne se lance sans
son action.

**Why this priority**: le premier essai dépend d'une action de l'utilisateur ; la
compatibilité de la machine distante n'est pas vérifiée.

**Independent Test**: le fichier existe, il est lisible comme YAML, son seul déclencheur
est manuel.

**Acceptance Scenarios**:

1. **Given** le fichier de workflow, **When** on lit ses déclencheurs, **Then** le seul
   déclencheur est `workflow_dispatch`.
2. **Given** un push ou une demande de fusion, **Then** aucun workflow ne démarre.

---

### User Story 9 - Un premier extrait du plus gros fichier (Priority: P3)

Le mainteneur trouve le fournisseur de relevés rejouables dans son propre fichier.

**Why this priority**: gain de lisibilité limité ; déplacement mécanique.

**Independent Test**: le type existe une fois, dans le nouveau fichier ; la suite passe.

**Acceptance Scenarios**:

1. **Given** le code, **When** on cherche la déclaration du type, **Then** elle se trouve
   dans le nouveau fichier seulement.
2. **Given** `LayoutMaintainer.swift`, **When** on compte ses lignes, **Then** il en a au
   plus 4 400.
3. **Given** la suite de tests, **Then** elle passe sans modification des tests.

---

### User Story 10 - Savoir si une version plus récente existe (Priority: P3)

L'utilisateur lance `roadie update check`. Roadie lui dit s'il est à jour et donne le lien
de la dernière version. Roadie ne contacte Internet qu'à cette commande.

**Why this priority**: premier appel réseau du produit ; utile mais non essentiel.

**Independent Test**: lancer la commande avec et sans réseau.

**Acceptance Scenarios**:

1. **Given** une version publiée plus récente, **When** l'utilisateur lance la commande,
   **Then** la sortie nomme les deux versions et le lien ; le code de retour est 0.
2. **Given** la version courante égale ou supérieure, **Then** la sortie dit que Roadie est
   à jour ; le code de retour est 0.
3. **Given** aucun réseau, **Then** la commande répond en 6 secondes au plus, écrit la
   raison sur la sortie d'erreur et rend le code 1.
4. **Given** le daemon en marche sans commande de l'utilisateur, **Then** Roadie
   n'effectue aucun appel réseau.

---

### User Story 11 - Inventaire des images et preuves publiées (Priority: P3)

L'utilisateur reçoit la liste des images et des diaporamas de preuves suivis par Git. Il
décide lui-même s'il en retire.

**Why this priority**: la session 064 a déjà retiré des captures au contenu privé ; la
décision appartient à l'utilisateur.

**Independent Test**: le rapport existe et ses totaux égalent ceux de Git.

**Acceptance Scenarios**:

1. **Given** le rapport, **When** on compare ses totaux à `git ls-files`, **Then** ils
   sont égaux.
2. **Given** le dépôt après le lot, **Then** aucune image ni preuve n'a été retirée ou
   modifiée.

### Edge Cases

- Installation depuis une archive sans dossier `.git` : aucun commit n'est inscrit ; la
  version s'affiche seule.
- `~/.local/bin/roadied` est un lien vers le binaire de l'application : le commit est lu
  malgré le lien.
- `daemon-status.json` écrit par une version antérieure, sans champ `buildCommit` : il se
  lit sans erreur.
- Complétion chargée avant l'initialisation de la complétion de zsh : le chargement ne
  produit pas d'erreur.
- Dernière version publiée avec un nom inattendu (`v0.14.0-beta`) : la comparaison ne
  plante pas.
- GitHub répond par une erreur ou une limite de débit : la commande rend le code 1 avec la
  raison.
- Commande marquée « not implemented » dans la table : elle n'apparaît pas dans la
  complétion.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: `README.fr.md` NE DOIT contenir aucun chemin de dossier personnel absolu.
- **FR-002**: chaque décision d'architecture DOIT avoir un numéro unique.
- **FR-003**: aucun fichier de sauvegarde `.bak-` NE DOIT être suivi par Git.
- **FR-004**: le numéro de version DOIT être déclaré à un seul endroit ; les scripts
  DOIVENT le lire à cet endroit. La variable `ROADIE_VERSION` reste une surcharge possible.
- **FR-005**: l'installation DOIT inscrire le commit du build dans l'application ; un dépôt
  modifié DOIT ajouter `-dirty`.
- **FR-006**: `roadied --version` DOIT afficher la version et, s'il est connu, le commit.
- **FR-007**: `daemon-status.json` DOIT exposer le commit dans un champ facultatif ; un
  fichier sans ce champ DOIT rester lisible.
- **FR-008**: `roadie --version` NE DOIT PAS changer.
- **FR-009**: un test DOIT échouer si une clé de la configuration par défaut est inconnue
  du validateur.
- **FR-010**: un test DOIT échouer si un fichier de configuration vide ne donne pas la
  configuration par défaut.
- **FR-011**: une recette écrite DOIT lister les étapes d'ajout d'un réglage et le test de
  chaque étape.
- **FR-012**: `AGENTS.md` DOIT garder les règles, les marqueurs SpecKit et un pointeur vers
  le journal ; le journal des sessions DOIT être conservé en entier dans un fichier séparé.
- **FR-013**: `AGENTS.md` DOIT contenir une section des pièges connus avec leurs remèdes.
- **FR-014**: les deux sites recensés DOIVENT contrôler le type avant toute conversion
  forcée d'une valeur d'accessibilité.
- **FR-015**: Roadie NE DOIT PLUS écrire les événements `drag.real_press` et
  `drag.real_router_press`.
- **FR-016**: `roadie completion zsh` DOIT produire un script zsh valide, généré depuis la
  table des commandes, limité aux commandes implémentées.
- **FR-017**: `make coverage` DOIT lancer les tests avec mesure de couverture et afficher
  le résultat.
- **FR-018**: un workflow GitHub DOIT exister avec un déclenchement manuel seulement.
- **FR-019**: `ReplayableSnapshotProvider` DOIT se trouver dans son propre fichier, sans
  changement de comportement.
- **FR-020**: `roadie update check` DOIT comparer la version courante à la dernière version
  publiée, répondre en 6 secondes au plus, et rendre 0 si la réponse est connue, 1 sinon.
- **FR-021**: Roadie NE DOIT effectuer aucun appel réseau hors de `roadie update check`.
- **FR-022**: un rapport DOIT lister les images et diaporamas suivis par Git ; le lot NE
  DOIT retirer aucun fichier de preuve.
- **FR-023**: `CHANGELOG.md` (section « Non publié ») et la documentation des commandes en
  français et en anglais DOIVENT décrire les changements visibles.
- **FR-024**: aucune tâche NE DOIT publier, pousser, dépenser ou supprimer des données
  locales de l'utilisateur.

### Key Entities

- **Version de Roadie** : numéro déclaré une fois dans le code.
- **Commit du build** : 8 premiers caractères de l'identifiant Git, avec `-dirty` si le
  dépôt était modifié ; inscrit dans l'application à l'installation.
- **État publié du daemon** : fichier `daemon-status.json`, qui gagne un champ facultatif.
- **Table des commandes** : liste unique des commandes, source de l'aide et de la
  complétion.
- **Dernière version publiée** : nom et lien de la dernière release GitHub.
- **Journal des sessions** : historique des livraisons, déplacé hors d'`AGENTS.md`.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: 0 occurrence de `/Users/moi` dans `README.md` et `README.fr.md`.
- **SC-002**: le numéro de version littéral apparaît dans 1 seul fichier de `Sources/` et
  `scripts/` (`grep -rl '0\.13\.0' Sources scripts` rend 1 fichier ; 2 avant).
- **SC-003**: dans un bundle construit avec un commit, `roadied --version` affiche ce
  commit de 8 caractères et `DaemonStatus.buildCommit` le reprend. Les tâches le
  contrôlent sur un bundle temporaire ; le contrôle sur l'application installée
  appartient à la livraison.
- **SC-004**: 2 nouveaux tests de garde passent ; un réglage ajouté sans déclaration fait
  échouer au moins un test.
- **SC-005**: `AGENTS.md` passe de 39 858 octets à moins de 8 000 ; 0 ligne de journal
  perdue.
- **SC-006**: 0 conversion forcée sans contrôle de type dans les deux sites recensés.
- **SC-007**: 0 occurrence des deux événements de clic dans `Sources/`.
- **SC-008**: `roadie completion zsh | zsh -n` rend 0 ; la complétion couvre toutes les
  commandes implémentées de la table.
- **SC-009**: `make coverage` se termine avec le code 0 et affiche un résultat.
- **SC-010**: `roadie update check` répond en 6 secondes au plus dans tous les cas.
- **SC-011**: `LayoutMaintainer.swift` a au plus 4 400 lignes (4 462 avant).
- **SC-012**: la suite complète (`./scripts/test --no-parallel`) passe avec 2 538 tests
  dans 387 suites (base mesurée : 2 523 dans 383 ; 15 tests ajoutés dans 4 suites) ; les
  28 tests de scripts passent.
- **SC-013**: 0 action sortante exécutée par les tâches (push, publication, dépense).

## Assumptions

- La licence, la publication d'une version, la notarisation et le déclenchement automatique
  de la CI sont des décisions de l'utilisateur. Elles sont hors des tâches.
- L'implémenteur travaille dans le worktree
  `/Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/155-consolidation-projet`.
- Le dépôt GitHub `guthubrx/roadie` est public ; son API de releases répond sans jeton
  (vérifié le 10 novembre 2026).
- Les rapports d'audit et les anciens dossiers `specs/` sont des archives. Ils ne sont pas
  modifiés, même s'ils contiennent des chemins personnels.
- L'installation réelle sur le poste de l'utilisateur fait partie de la livraison, pas de
  cette préparation.

## Dependencies

- Spec 016 : contrat `specs/016-roadie-stabilization/contracts/daemon-status.md` (champ
  ajouté, schéma compatible).
- Specs 054, 059, 063, 128 : emballage du DMG et lecture de la version.
- Spec 093 (audit de la base de code) et spec 129 (corrections d'audit) : garde-fous de
  configuration existants, réutilisés.
- Spec 145 et spec 152 : origine des deux événements de clic.
