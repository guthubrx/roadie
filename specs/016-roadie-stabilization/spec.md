# Feature Specification: Stabilisation de Roadie

**Feature Branch**: `016-roadie-stabilization`
**Created**: 2026-10-10
**Status**: Implemented (validation manuelle en attente)
**Dependencies**: SPEC-010-layout-stability-hardening, SPEC-011-atomic-components, SPEC-012-component-lifecycle-unification, SPEC-013-persistent-bsp-tree, SPEC-014-bsp-tree-manipulation, SPEC-015-navrail-fullscreen-state
**Input**: User description: "Corriger l'ensemble des 39 constats de la revue de stabilité, de robustesse, de performance et d'utilisabilité (points 1 à 39)."
**Source détaillée des constats**: [review-findings.md](./review-findings.md)

## Contexte

Une revue du 2026-10-10 a produit 39 constats consolidés. Les journaux réels (`~/.roadies/events.jsonl`) montrent 16 887 relayouts supprimés, 6 337 rattachements d'identité heuristiques et 36 932 reconstructions du navrail. La suite de tests passe (518 tests) mais ne couvre pas les scénarios runtime qui posent problème.

Les constats se regroupent en six causes racines :

- **C1** Plusieurs processus écrivent les mêmes fichiers d'état sans transaction.
- **C2** Les appels Accessibility n'ont pas de délai maximal et bloquent le fil principal.
- **C3** Un cache d'attributs de fenêtre garde 10 minutes des états qui changent.
- **C4** L'identité des fenêtres est devinée par application et titre.
- **C5** Des seuils en pixels sont pris pour des états (plein écran, maximisé).
- **C6** Rien ne ramène les fenêtres masquées quand Roadie s'arrête.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Aucune fenêtre perdue ni cachée à tort (Priority: P1)

En tant qu'utilisateur, je veux que Roadie ne cache jamais une fenêtre sans raison et qu'il ramène toutes mes fenêtres quand il s'arrête, afin de ne jamais perdre une fenêtre.

**Why this priority**: Une fenêtre perdue casse la confiance dans l'outil. C'est le défaut le plus visible (constats 1, 3, 4, 8, 10, 14, 21).

**Independent Test**: Créer une stage avec une seule fenêtre tilée, ouvrir une seconde fenêtre, puis arrêter Roadie. Les deux fenêtres restent visibles, puis toutes les fenêtres des stages inactives reviennent à l'écran.

**Acceptance Scenarios**:

1. **Given** une stage contient une seule fenêtre tilée qui remplit la zone utile moins les marges, **When** l'utilisateur ouvre une nouvelle fenêtre dans cette stage, **Then** la nouvelle fenêtre est tilée et visible, et aucune n'est traitée comme plein écran.
2. **Given** une fenêtre est en plein écran par commande Roadie et ses voisines sont cachées, **When** l'utilisateur donne le focus à une voisine cachée, **Then** la voisine devient visible et le maintien de la disposition continue.
3. **Given** trois fenêtres en grille dont deux ont une taille minimale imposée, **When** la disposition est calculée, **Then** aucune fenêtre n'est cachée si une disposition valide existe.
4. **Given** des stages inactives contiennent des fenêtres masquées, **When** Roadie s'arrête proprement ou plante, **Then** toutes les fenêtres masquées reviennent sur un écran visible à leur dernière position visible connue.
5. **Given** l'utilisateur ferme un Terminal « zsh » dans la stage 2, **When** il ouvre un nouveau Terminal « zsh » dans la stage 1 active, **Then** la nouvelle fenêtre reste dans la stage 1.
6. **Given** une fenêtre épinglée est minimisée, **When** elle est restaurée moins de 45 s plus tard, **Then** son épinglage existe toujours.
7. **Given** une application refuse une taille, **When** le refus date de plus de 30 s ou la fenêtre disparaît, **Then** Roadie oublie ce refus et réessaie.
8. **Given** l'utilisateur veut récupérer toutes ses fenêtres, **When** il lance `roadie restore unhide-all`, **Then** toutes les fenêtres masquées reviennent à l'écran.

---

### User Story 2 - État partagé cohérent entre processus (Priority: P1)

En tant qu'utilisateur, je veux qu'un changement de stage ou une commande ne soit jamais annulé par un autre processus Roadie, afin que mes actions soient fiables.

**Why this priority**: Les écritures concurrentes causent des retours en arrière et des fenêtres qui apparaissent puis disparaissent (constats 2, 5, 6, 13, 16, 29).

**Independent Test**: Lancer en boucle `roadie stage switch` pendant que le daemon tourne. Chaque changement demandé est conservé.

**Acceptance Scenarios**:

1. **Given** le daemon effectue un tick, **When** une commande CLI modifie l'état en même temps, **Then** aucune des deux modifications n'est perdue.
2. **Given** un processus en mode lecteur (bordure, focus-souris), **When** il prend un snapshot, **Then** il n'écrit aucun fichier d'état.
3. **Given** l'état n'a pas changé, **When** un tick se termine, **Then** aucun fichier d'état n'est réécrit.
4. **Given** le fichier d'état des stages est illisible, **When** Roadie le charge, **Then** il garde une copie du fichier fautif, journalise l'erreur et refuse d'écraser le fichier.
5. **Given** une fenêtre est en plein écran natif sur l'écran 1, **When** l'utilisateur ouvre une fenêtre sur l'écran 2, **Then** l'écran 2 est tilé normalement.
6. **Given** un scope est en période de stabilisation, **When** l'utilisateur redimensionne une fenêtre sur un autre écran, **Then** ce changement est traité.
7. **Given** l'utilisateur modifie `roadies.toml`, **When** le daemon tourne, **Then** le daemon applique la nouvelle configuration sans redémarrage.
8. **Given** un daemon Roadie tourne déjà, **When** un second daemon démarre, **Then** le second refuse de démarrer avec un message clair.

---

### User Story 3 - Roadie ne gèle jamais et reste léger (Priority: P1)

En tant qu'utilisateur, je veux que Roadie reste réactif même quand une application ne répond plus, et qu'il consomme peu de processeur, afin qu'il ne dégrade pas ma machine.

**Why this priority**: Un gel bloque le rail, la bordure et les clics (constats 7, 22, 23, 24).

**Independent Test**: Mettre une application en pause (`kill -STOP <pid>`) et vérifier que le rail et les commandes continuent de répondre en moins d'une seconde.

**Acceptance Scenarios**:

1. **Given** une application ne répond plus, **When** Roadie interroge ses fenêtres, **Then** chaque appel abandonne en moins de 0,5 s et l'application est mise de côté temporairement.
2. **Given** Roadie tourne en mode monolithique sans activité, **When** on mesure sur 60 s, **Then** il ne prend pas plus d'un snapshot complet par tick partagé entre composants et n'écrit aucun fichier.
3. **Given** la souris survole la zone du rail, **When** elle ne touche aucune carte, **Then** le rail ne prend aucun snapshot complet.
4. **Given** rien n'a changé, **When** le timer du rail se déclenche, **Then** le rail ne reconstruit pas ses vues.
5. **Given** le rail affiche des vignettes, **When** on mesure la mémoire, **Then** chaque vignette est stockée à une taille réduite proche de sa taille d'affichage.

---

### User Story 4 - Comportement prévisible (Priority: P1)

En tant qu'utilisateur, je veux que les fenêtres et les stages ne bougent que quand je le demande, afin de garder le contrôle.

**Why this priority**: Les stages qui changent seules et les fenêtres qui sautent rendent l'outil pénible (constats 11, 12, 15, 17, 20, et C3).

**Independent Test**: Redimensionner une fenêtre par son bord pendant 3 s, bouton enfoncé : Roadie n'intervient pas avant le relâchement.

**Acceptance Scenarios**:

1. **Given** macOS donne le focus à une fenêtre d'une stage cachée sans action de l'utilisateur, **When** le snapshot suivant arrive, **Then** la stage active ne change pas.
2. **Given** le bouton de la souris est enfoncé, **When** un tick arrive, **Then** Roadie ne réapplique aucune disposition.
3. **Given** une stage en BSP ne contient qu'une fenêtre, **When** une nouvelle fenêtre prend le focus, **Then** elle est insérée immédiatement dans l'arbre.
4. **Given** une application répond lentement, **When** ses attributs reviennent vides, **Then** la fenêtre garde son dernier classement connu.
5. **Given** l'utilisateur fait Cmd-Tab vers une fenêtre B alors que la souris repose sur A, **When** le focus-souris est actif, **Then** A ne reprend pas le focus tant que la souris ne bouge pas.
6. **Given** une fenêtre déjà connue passe en plein écran natif, **When** le snapshot suivant arrive, **Then** Roadie la voit en plein écran natif.

---

### User Story 5 - Navrail juste et robuste (Priority: P2)

En tant qu'utilisateur, je veux un navrail qui affiche l'état réel des fenêtres, sans fantômes ni faux indicateurs (constats 9, 18, 19, et sous-constats rail).

**Why this priority**: Le rail est l'interface principale des stages, mais ses défauts ne font pas perdre de fenêtres.

**Independent Test**: Fermer la seule fenêtre d'une stage : la carte disparaît en moins de 15 s. Une stage à une fenêtre tilée n'affiche pas la bordure `maximized`.

**Acceptance Scenarios**:

1. **Given** la seule fenêtre d'une stage est fermée, **When** 15 s passent, **Then** la carte ne la montre plus.
2. **Given** une fenêtre tilée seule dans sa stage, **When** le rail la dessine, **Then** il n'affiche pas l'indicateur `maximized`.
3. **Given** le fichier de configuration est remplacé de façon atomique, **When** le rail relance sa surveillance, **Then** aucun autre fichier n'est fermé par erreur et la surveillance continue.
4. **Given** une fenêtre est agrandie hors plein écran natif, **When** le rail est en mode overlay, **Then** le comportement de masquage du rail suit un réglage documenté.
5. **Given** la permission Screen Recording manque, **When** le rail affiche une carte, **Then** il affiche l'icône de l'application et journalise l'absence de permission.

---

### User Story 6 - Installation et exploitation simples (Priority: P2)

En tant que nouvel utilisateur, je veux installer, démarrer, diagnostiquer et désinstaller Roadie sans connaître le dépôt, afin de l'adopter facilement (constats 25 à 31, 34, 35).

**Why this priority**: Sans cela, Roadie reste utilisable seulement par son auteur.

**Independent Test**: Sur une machine avec les seuls Command Line Tools, suivre le README : installation, démarrage, `roadie doctor`, désinstallation.

**Acceptance Scenarios**:

1. **Given** une machine sans Xcode.app, **When** l'utilisateur lance `make install`, **Then** l'installation passe ou explique clairement le prérequis manquant.
2. **Given** Roadie est installé, **When** l'utilisateur lance `roadie daemon restart` ou `make restart`, **Then** le service installé redémarre, sans chemin personnel codé en dur.
3. **Given** la config contient une faute de frappe dans un nom de clé, **When** l'utilisateur lance `roadie config validate`, **Then** il obtient la clé fautive et une suggestion.
4. **Given** la config devient invalide pendant que le daemon tourne, **When** le daemon recharge, **Then** il garde la dernière config valide et signale l'erreur.
5. **Given** l'utilisateur lance `roadie doctor`, **When** le daemon tourne, **Then** le rapport donne l'état du daemon, ses permissions Accessibility et Screen Recording, et la validité de la config.
6. **Given** l'utilisateur veut partir, **When** il lance `make uninstall`, **Then** les fenêtres sont restaurées et le service, les binaires et le plist sont retirés.
7. **Given** un nouvel utilisateur, **When** il cherche un point de départ, **Then** il trouve une config d'exemple et des raccourcis d'exemple.

---

### User Story 7 - Ligne de commande cohérente et rapide (Priority: P2)

En tant qu'utilisateur qui pilote Roadie par raccourcis, je veux une CLI rapide, documentée et cohérente (constats 32, 33).

**Why this priority**: Chaque raccourci passe par la CLI.

**Independent Test**: `roadie --help` sort en code 0, `roadie --version` affiche la version, `roadie focus left` répond via le daemon.

**Acceptance Scenarios**:

1. **Given** le daemon tourne, **When** l'utilisateur lance une commande d'action, **Then** la commande est exécutée par le daemon sans scan Accessibility dans le processus CLI.
2. **Given** l'utilisateur tape `roadie --help` ou `roadie -h`, **When** la commande se termine, **Then** le code de retour est 0.
3. **Given** une action n'a rien à changer, **When** elle se termine, **Then** le code de retour est 0.
4. **Given** l'utilisateur demande `--json`, **When** la commande le supporte, **Then** la sortie est un JSON valide et propre à la commande demandée.

---

### User Story 8 - Code maintenable (Priority: P3)

En tant que mainteneur, je veux un code découpé, des seuils centralisés et des tests sur les zones à risque (constats 36 à 39).

**Why this priority**: Indispensable à moyen terme, sans effet direct sur l'utilisateur.

**Independent Test**: Les seuils de tolérance viennent d'un seul endroit. `RoadieAX` a une cible de tests. Aucune API retirée du SDK macOS 15 n'est appelée.

**Acceptance Scenarios**:

1. **Given** le code du mainteneur de disposition, **When** une garde doit exclure un scope, **Then** elle exclut ce scope sans arrêter le tick pour les autres.
2. **Given** un seuil de tolérance, **When** on cherche sa définition, **Then** il est défini une seule fois et relié aux marges configurées quand c'est pertinent.
3. **Given** la suite de tests, **When** elle tourne, **Then** elle couvre la corruption d'état, les écritures concurrentes, la restauration des fenêtres masquées et le rattachement d'identité.

### Edge Cases

- Deux écrans identiques renvoient le même UUID.
- L'horloge système recule pendant que Roadie tourne.
- La machine passe en veille pendant un drag.
- L'écran le plus à droite est décalé verticalement par rapport aux autres.
- Une application relance son processus et ses fenêtres changent d'identifiant.
- Le fichier d'état est écrit par une version plus récente de Roadie.
- La permission Accessibility est retirée pendant que le daemon tourne.

## Requirements *(mandatory)*

### Functional Requirements

Chaque exigence cite le ou les constats de [review-findings.md](./review-findings.md) qu'elle couvre.

**Fenêtres et disposition (US1, US4)**

- **FR-001** (1, 13, C5): Roadie MUST traiter une fenêtre comme plein écran uniquement si macOS la signale en plein écran natif ou si une commande Roadie explicite de plein écran l'a placée ainsi. La seule taille d'une fenêtre MUST NOT suffire.
- **FR-002** (3): Une fenêtre qui reçoit le focus MUST devenir visible ; le maintien de la disposition MUST NOT rester bloqué sur un plan vide.
- **FR-003** (4): Roadie MUST NOT cacher des fenêtres d'un scope si une disposition respectant les tailles minimales connues existe ; le masquage reste un dernier recours journalisé.
- **FR-004** (14): Les refus de taille et les échecs mémorisés MUST expirer (30 s au plus) et MUST être purgés pour les fenêtres disparues. La position MUST rester applicable quand seule la taille est refusée.
- **FR-005** (15): Une nouvelle fenêtre MUST être insérée dans l'arbre BSP de sa stage dès son apparition, à côté du dernier membre focalisé de cette stage.
- **FR-006** (10, C4): Roadie MUST NOT rattacher une fenêtre neuve à un membre disparu tant que le processus d'origine de ce membre est vivant. Un rattachement MUST exiger aussi la proximité de cadre.
- **FR-007** (21): Les épinglages MUST survivre à une absence de 45 s au moins (minimisation, autre Space, plein écran natif).
- **FR-008** (17): Une fenêtre déjà classée MUST garder son classement quand ses attributs ne peuvent pas être lus.
- **FR-009** (11): Le suivi du focus par la stage MUST ignorer les changements de focus non initiés par l'utilisateur, notamment dans les 500 ms qui suivent la disparition d'une fenêtre.
- **FR-010** (12): Roadie MUST suspendre la réapplication de disposition tant qu'un bouton de souris est enfoncé, quelle que soit la zone de la fenêtre et même sans rail.
- **FR-011** (20): Le focus-souris MUST agir seulement après un mouvement réel du curseur, et jamais pendant un clic ou un drag.
- **FR-012** (7 du moteur): `toggleFullscreen` MUST enregistrer une intention cohérente avec l'état réellement appliqué.

**État partagé (US2)**

- **FR-013** (6, C1): Toute modification d'un fichier d'état MUST se faire en transaction lecture-modification-écriture exclusive.
- **FR-014** (5 robustesse, 2 instabilité): Un processus lecteur MUST NOT écrire de fichier d'état. Aucun processus MUST NOT réécrire un fichier dont le contenu n'a pas changé.
- **FR-015** (5 critique): Un fichier d'état illisible MUST être conservé sous un nom horodaté, journalisé, et MUST NOT être écrasé automatiquement.
- **FR-016** (2): Une fenêtre en plein écran natif MUST exclure seulement son propre scope du maintien de disposition.
- **FR-017** (16): La période de stabilisation d'un scope MUST exclure seulement ce scope. Activer un scope MUST NOT compter comme un changement de membres.
- **FR-018** (13 instabilité): Le daemon MUST recharger la configuration quand le fichier change, en gardant la dernière configuration valide si la nouvelle est invalide.
- **FR-019** (29): Un seul daemon tiler MUST pouvoir tourner par session ; un second démarrage MUST échouer avec un message clair.
- **FR-020** (intents): Les intentions de disposition d'un écran absent MUST être conservées pendant une période de grâce.

**Réactivité et ressources (US3)**

- **FR-021** (7, C2): Chaque appel Accessibility MUST avoir un délai maximal de 0,5 s ; une application qui dépasse ce délai MUST être mise de côté temporairement.
- **FR-022** (C3): Seuls les attributs stables d'une fenêtre (rôle, sous-rôle, boutons) MAY être mis en cache. Les attributs d'état (plein écran, focus, principal, modal) MUST être relus à chaque snapshot.
- **FR-023** (22, 24): Les composants d'un même processus MUST partager un snapshot par cycle et MUST NOT relire la configuration à chaque tick.
- **FR-024** (23): Le rail MUST NOT prendre de snapshot complet pour un survol, MUST reconstruire ses vues seulement si son état visible change, MUST redessiner ses cartes seulement pendant une animation, et MUST stocker les vignettes à taille réduite.
- **FR-025** (23): Pendant un drag depuis le rail, la prévisualisation MUST réutiliser un snapshot pris au début du drag.

**Navrail (US5)**

- **FR-026** (9): Les surveillances de fichiers MUST fermer chaque descripteur une seule fois.
- **FR-027** (18, 5 rail): L'indicateur `maximized` MUST NOT s'afficher pour une fenêtre tilée seule, et une fenêtre fermée MUST disparaître du rail en 15 s au plus.
- **FR-028** (19): Le masquage du rail devant une fenêtre agrandie MUST suivre un réglage explicite et documenté.
- **FR-029** (rail): Le rail MUST vérifier la permission Screen Recording, afficher l'icône d'application en cas d'absence, et traiter une capture transparente comme vide.
- **FR-030** (rail): La zone de révélation du rail MUST rester dans son propre écran ; un drag interrompu MUST être réinitialisé ; le clic sur le fond d'une carte MUST activer la stage.

**Installation et exploitation (US6)**

- **FR-031** (25): Aucun chemin propre à un utilisateur MUST NOT figurer dans le code ou les scripts livrés.
- **FR-032** (26): Les scripts MUST fonctionner avec les seuls Command Line Tools quand Xcode.app est absent, ou expliquer le prérequis.
- **FR-033** (27, 28): `make restart` et `roadie daemon restart` MUST redémarrer le service installé ; le démarrage de développement MUST être une cible distincte ; les logs MUST être conservés par rotation, pas vidés.
- **FR-034** (30, 31): La validation MUST signaler les clés inconnues avec suggestion, traduire les erreurs de décodage en messages lisibles, accepter les tables réellement lues (`fx.rail.*`) et signaler les clés sans effet.
- **FR-035** (34): `roadie doctor` MUST rapporter l'état réel du daemon, ses permissions Accessibility et Screen Recording, et la validité de la configuration.
- **FR-036** (35): Le projet MUST fournir une config d'exemple, des raccourcis d'exemple, une cible de désinstallation et une rotation des logs.
- **FR-037** (C6, 8): À l'arrêt, Roadie MUST ramener à l'écran toutes les fenêtres masquées. Le snapshot de restauration MUST être tenu à jour et MUST NOT contenir de position masquée. Une commande `roadie restore unhide-all` MUST exister.

**Ligne de commande (US7)**

- **FR-038** (32): Les commandes d'action MUST être exécutées par le daemon quand il tourne, via un canal local.
- **FR-039** (33): `--help`, `-h` et `help` MUST sortir en code 0 ; `--version` MUST exister ; une action sans changement MUST sortir en code 0 ; `--json` MUST produire une sortie propre à la commande.

**Maintenabilité (US8)**

- **FR-040** (36): Les gardes du tick MUST exclure des scopes au lieu d'arrêter tout le tick ; le bloc « appliquer, réparer, émettre » MUST exister une seule fois.
- **FR-041** (37): Les seuils de tolérance MUST être définis une seule fois et dérivés des marges configurées quand c'est pertinent.
- **FR-042** (38): Les zones à risque MUST avoir des tests : corruption d'état, écritures concurrentes, restauration masquée, rattachement d'identité, expiration des refus, garde plein écran par scope.
- **FR-043** (39): Le code MUST NOT appeler d'API retirée du SDK macOS 15 ni d'option ignorée depuis macOS 14 sans repli.

### Key Entities

- **Fichier d'état des stages**: stages, membres, arbres BSP, épinglages, signets ; écrit par transaction.
- **Intention de disposition**: disposition voulue par une commande pour un scope ; conservée pendant une grâce si l'écran disparaît.
- **Snapshot de restauration**: dernière position visible connue de chaque fenêtre gérée ; jamais une position masquée.
- **Registre de mise de côté**: applications qui ne répondent pas, avec date de reprise.
- **Mémoire des refus**: refus de taille et échecs par fenêtre, avec expiration.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: 0 fenêtre reste hors écran après un arrêt propre ou un crash simulé (test automatisé et test manuel).
- **SC-002**: Sur 100 changements de stage concurrents avec un tick actif, 0 modification perdue (test automatisé).
- **SC-003**: Avec une application suspendue, chaque commande Roadie répond en moins de 1 s.
- **SC-004**: En mode monolithique au repos, 0 écriture de fichier d'état sur 60 s.
- **SC-005**: Le survol du rail sans carte déclenche 0 snapshot complet.
- **SC-006**: Une stage à une fenêtre tilée n'affiche jamais l'indicateur `maximized`, et ses nouvelles fenêtres sont tilées dans 100 % des cas testés.
- **SC-007**: Les 518 tests existants et les nouveaux tests passent ; la compilation passe sans erreur.
- **SC-008**: `roadie --help` et `roadie --version` sortent en code 0 ; aucun chemin `/Users/` ne reste dans `Sources/` et `scripts/`.
- **SC-009**: Une config avec une clé mal orthographiée produit un avertissement nommant la clé.

## Assumptions

- Les tests manuels sur le bureau réel (permissions, multi-écran, veille) sont faits par l'utilisateur ; les tests automatisés utilisent les doubles existants (`PowerUserProvider`).
- Le mode monolithique (`roadied run`) et le mode modulaire restent tous deux supportés.
- Le canal local CLI vers daemon peut réutiliser un mécanisme existant du projet ; s'il n'est pas disponible, la CLI garde son exécution directe en repli.
- Les raccourcis clavier intégrés et une icône de barre de menus complète sont hors périmètre : le constat 35 est couvert par des exemples de raccourcis et la documentation, pas par un nouveau gestionnaire de raccourcis.
- La migration de `CGWindowListCreateImage` vers ScreenCaptureKit est faite seulement si elle reste compatible macOS 14 ; sinon un repli documenté est accepté.
