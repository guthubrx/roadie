# Feature Specification: Stage Manager Suckless

**Feature Branch**: `001-stage-manager`
**Created**: 2026-05-01
**Status**: Draft
**Dependencies**: None
**Input**: User description: "Stage Manager macOS suckless en Swift mono-fichier (stage.swift), zéro dépendance externe, frameworks système macOS uniquement. Permet de définir 2 stages (groupes de fenêtres) et basculer entre eux. État persistant en texte plat dans ~/.stage/. CLI minimaliste : `stage 1|2` (switch), `stage assign 1|2` (frontmost vers stage). Cible 150 lignes Swift max. Auto-GC des fenêtres fermées. Fail loud sur erreurs."

---

## User Scenarios & Testing

### User Story 1 - Basculer entre 2 contextes de travail (Priority: P1)

L'utilisateur travaille sur deux contextes distincts (ex. *développement* et *communication*). Chaque contexte regroupe un ensemble de fenêtres applicatives (terminaux, navigateur, éditeur, mail, chat). Au lieu de jongler avec Mission Control ou de minimiser à la main, l'utilisateur tape une commande unique pour faire disparaître les fenêtres du contexte qu'il quitte et faire réapparaître celles du contexte qu'il rejoint.

**Why this priority** : c'est la valeur centrale du produit. Sans cette capacité, l'outil n'a aucun intérêt. C'est aussi le scénario de validation MVP : si la bascule fonctionne entre deux stages préassignés, le produit livre déjà sa promesse.

**Independent Test** : avec deux stages déjà préremplis (un terminal dans chacun), exécuter la commande de bascule doit faire disparaître la fenêtre d'un stage et apparaître celle de l'autre, en moins d'une seconde, sans intervention manuelle.

**Acceptance Scenarios** :

1. **Given** stage 1 contient une fenêtre Terminal et stage 2 contient une fenêtre Safari, l'utilisateur est sur stage 1, **When** il tape la commande de bascule vers stage 2, **Then** la fenêtre Terminal devient invisible (minimisée) et la fenêtre Safari devient visible et focalisable.
2. **Given** l'utilisateur est sur stage 2, **When** il rebascule vers stage 1, **Then** la fenêtre Terminal qu'il avait précédemment minimisée redevient visible exactement à sa place et taille initiales.
3. **Given** un stage vide est demandé, **When** l'utilisateur bascule, **Then** toutes les fenêtres assignées aux autres stages sont masquées et le bureau apparaît vide (comportement attendu, pas une erreur).

---

### User Story 2 - Assigner la fenêtre courante à un stage (Priority: P1)

L'utilisateur a une fenêtre active devant lui (la fenêtre frontmost) et veut la rattacher à un stage donné. Il tape une commande qui, sans déplacer la fenêtre ni modifier sa visibilité immédiate, l'inscrit dans la liste persistante du stage cible. Si elle était déjà dans un autre stage, elle en est retirée automatiquement (une fenêtre = exactement un stage).

**Why this priority** : sans cette capacité, l'outil démarre toujours avec deux stages vides et ne sert à rien. C'est le mécanisme par lequel l'utilisateur construit ses stages. Aussi prioritaire que la bascule.

**Independent Test** : avec un terminal au premier plan et aucun stage assigné, exécuter la commande d'assignation au stage 1 doit créer une entrée dans le fichier d'état persistant du stage 1 contenant un identifiant stable de cette fenêtre. Vérifiable avec `cat ~/.stage/1`.

**Acceptance Scenarios** :

1. **Given** une fenêtre Terminal est au premier plan et aucun stage n'a encore été configuré, **When** l'utilisateur exécute l'assignation au stage 1, **Then** le fichier `~/.stage/1` contient une ligne identifiant cette fenêtre, et le fichier `~/.stage/2` reste vide ou inexistant.
2. **Given** une fenêtre est déjà assignée au stage 1, **When** l'utilisateur réassigne la même fenêtre au stage 2, **Then** la ligne disparaît du fichier `~/.stage/1` et apparaît dans `~/.stage/2`.
3. **Given** aucune fenêtre n'a le focus (cas pathologique), **When** l'utilisateur tente l'assignation, **Then** l'outil affiche une erreur explicite sur la sortie d'erreur et ne modifie aucun fichier d'état.

---

### User Story 3 - Tolérance aux fenêtres disparues (Priority: P2)

Au cours du temps, des applications sont fermées par l'utilisateur. Les identifiants de fenêtres correspondants deviennent obsolètes dans les fichiers d'état. L'outil ne doit jamais planter ni rester silencieusement incohérent à cause de ces entrées mortes.

**Why this priority** : sans tolérance aux fenêtres disparues, l'outil se dégrade naturellement et devient inutilisable au bout de quelques jours. C'est P2 (et non P1) parce que ça n'apparaît qu'après plusieurs heures d'usage.

**Independent Test** : préremplir un stage avec une fenêtre, fermer l'application correspondante, puis demander une bascule. L'outil doit rapporter l'identifiant invalide sur la sortie d'erreur, retirer la ligne du fichier d'état, et terminer la bascule normalement avec les fenêtres restantes.

**Acceptance Scenarios** :

1. **Given** stage 1 référence trois fenêtres dont une dont l'application a été quittée, **When** l'utilisateur bascule vers stage 1, **Then** les deux fenêtres encore vivantes sont restaurées, l'identifiant mort est listé sur stderr, et le fichier `~/.stage/1` ne contient plus que les deux lignes vivantes.
2. **Given** un stage entier ne référence que des fenêtres mortes, **When** l'utilisateur y bascule, **Then** le fichier est vidé, un message d'avertissement est émis, et la bascule réussit (le bureau apparaît vide).

---

### Edge Cases

- **Aucune permission Accessibility** : l'outil détecte au démarrage qu'il n'est pas autorisé, affiche un message clair indiquant comment l'autoriser dans Réglages Système → Confidentialité et sécurité → Accessibilité, et termine avec un code de sortie non nul. Aucune action sur fenêtre n'est tentée.
- **Argument invalide** : un numéro de stage inexistant (3, 0, "abc") doit produire un message d'usage et un code de sortie non nul, sans toucher l'état.
- **Fichier d'état corrompu** : une ligne malformée (mauvais nombre de champs) doit être loguée sur stderr puis ignorée. Les autres lignes du même fichier restent traitées normalement.
- **Fenêtre minimisée par l'utilisateur entre deux bascules** : si l'utilisateur a manuellement minimisé une fenêtre du stage actif, à la prochaine bascule sortante elle reste minimisée (état déjà correct), et au retour elle est dé-minimisée comme les autres.
- **Deux fenêtres de la même application dans le même stage** : chaque fenêtre est tracée individuellement par son identifiant unique. Aucune ambiguïté.
- **Application multi-fenêtre dont une seule fenêtre est dans un stage** : seule cette fenêtre est cachée/restaurée. Les autres fenêtres de l'app continuent leur vie normalement.

---

## Requirements

### Functional Requirements

- **FR-001** : Le système DOIT exposer une commande `stage <N>` (où N = 1 ou 2) qui rend visibles toutes les fenêtres assignées au stage N et masque toutes les fenêtres assignées aux autres stages.
- **FR-002** : Le système DOIT exposer une commande `stage assign <N>` qui inscrit l'identifiant de la fenêtre actuellement au premier plan dans la liste persistante du stage N et le retire de tout autre stage où il pourrait figurer.
- **FR-003** : Une fenêtre DOIT être identifiée par un identifiant numérique stable au cours de la vie de la fenêtre, indépendant de son titre, de sa position ou de l'espace virtuel sur lequel elle se trouve.
- **FR-004** : L'état des stages DOIT être persistant entre invocations de la commande, stocké sous forme de fichiers texte dans le répertoire personnel de l'utilisateur (`~/.stage/`).
- **FR-005** : Le format de stockage DOIT être en texte plat lisible et éditable manuellement, avec un séparateur de champs unique (TAB), une ligne par fenêtre.
- **FR-006** : Le système DOIT, à chaque bascule, retirer automatiquement des fichiers d'état toute entrée dont l'identifiant de fenêtre n'existe plus dans la liste système courante des fenêtres.
- **FR-007** : Le système DOIT vérifier au démarrage qu'il dispose des permissions Accessibility système ; en cas d'absence, il DOIT afficher un message d'instruction et terminer avec un code d'erreur sans tenter d'action.
- **FR-008** : Toute erreur (fenêtre introuvable, permission manquante, argument invalide, fichier corrompu) DOIT être affichée sur la sortie d'erreur standard avec un message explicite ; le code de sortie DOIT être non nul en cas d'erreur réelle. La table normative des codes de sortie (0/1/2/64) est définie dans `contracts/cli-contract.md`.
- **FR-009** : La sortie standard DOIT rester silencieuse en cas de succès (philosophie suckless : pas de bruit en mode nominal).
- **FR-010** : Le système DOIT mémoriser le stage actuellement actif dans un fichier dédié (`~/.stage/current`) afin que les invocations successives puissent connaître l'état courant sans introspecter le système.
- **FR-011** : L'utilisateur DOIT pouvoir éditer manuellement les fichiers d'état (par ex. avec un éditeur de texte) et l'outil DOIT respecter ces modifications à la prochaine invocation.
- **FR-012** : Le système ne DOIT JAMAIS modifier la position, la taille ou l'ordre Z des fenêtres autrement que par le mécanisme de masquage/affichage natif de macOS (préservation de l'expérience utilisateur).

### Key Entities

- **Stage** : un groupe nommé numériquement (1 ou 2) qui contient zéro ou plusieurs références de fenêtres. Représenté par un fichier `~/.stage/<N>`. Les stages sont mutuellement exclusifs : une fenêtre n'appartient qu'à un seul stage à la fois.
- **Window Reference** : un triplet `(pid, bundle_id, window_id)` qui identifie de façon unique une fenêtre macOS pour la durée de sa vie. Sérialisé sur une ligne du fichier de stage avec TAB comme séparateur.
- **Current Stage Marker** : valeur scalaire ("1" ou "2") stockée dans `~/.stage/current`, indiquant le stage présentement actif. Mise à jour atomiquement à chaque bascule réussie.

---

## Success Criteria

### Measurable Outcomes

- **SC-001** : La bascule entre deux stages contenant chacun jusqu'à 10 fenêtres se termine en moins de 500 millisecondes, du moment où l'utilisateur appuie sur Entrée jusqu'au retour du prompt.
- **SC-002** : L'assignation d'une fenêtre frontmost à un stage se termine en moins de 200 millisecondes.
- **SC-003** : Le binaire compilé occupe moins de 500 kilooctets sur disque (suckless de fait).
- **SC-004** : Aucune dépendance externe : le binaire ne charge que des bibliothèques système macOS au runtime (vérifiable par `otool -L`).
- **SC-005** : Sur 100 cycles de bascule consécutifs avec 5 fenêtres par stage, zéro fuite mémoire et zéro plantage.
- **SC-006** : Après 24 heures d'usage normal incluant la fermeture de plusieurs applications, les fichiers d'état ne contiennent aucune ligne morte (auto-GC effectif).
- **SC-007** : Un utilisateur déjà familier avec un terminal peut configurer ses deux stages, basculer entre eux et comprendre le format des fichiers d'état en moins de 5 minutes après installation.

---

## Assumptions

- L'utilisateur est sur macOS 11 (Big Sur) ou ultérieur. Les versions antérieures ne sont pas supportées (les API utilisées sont stables depuis 10.7 mais le testing se fait sur 14+).
- L'utilisateur peut accorder la permission Accessibility au binaire dans les Réglages Système. Cette étape manuelle est acceptée comme préalable d'installation, équivalent à ce que demandent yabai, AeroSpace ou Hammerspoon.
- L'usage cible est le développement personnel sur poste de travail. Pas de scénarios multi-utilisateur, pas de synchronisation entre machines, pas de cloud.
- Deux stages suffisent pour la version initiale. L'extension à N stages est triviale au niveau du format (un fichier par stage) mais hors scope de cette spec.
- Les fenêtres du système (menu bar, Dock, Spotlight) sont hors champ : seules les fenêtres applicatives ordinaires sont gérées.
- Pas de hotkey global intégrée. L'utilisateur câble sa propre touche via skhd, BetterTouchTool, Karabiner ou un alias shell. Hors scope.
- Pas de GUI, pas de menu bar item, pas de notification : strictement CLI.

---

## Research Findings

Recherche préalable réalisée sur les solutions existantes (cf. session conversationnelle préliminaire) :

- **Aucun clone open source crédible de Stage Manager** n'existe. Les rares projets (BetterStage commercial, StageControl abandonné) ne reproduisent pas le mécanisme de groupes ; ils contournent ou toggle on/off le Stage Manager natif d'Apple.
- **Limites du Stage Manager natif détectées par la communauté yabai** (issues `asmvik/yabai#1580`, `#1899`, `#1867`) : les API privées d'Apple n'exposent pas le grouping. Les seuls hooks disponibles sont les Gesture Blocking Overlays (proxy "minimisé/visible") et les window tags (récupérables via `_AXUIElementGetWindow` + `CGSCopyWindowProperty`), sans information de groupe.
- **Décision de scope** : ne pas tenter de reproduire le rendu visuel (sidebar avec thumbnails) du Stage Manager Apple, qui nécessite un compositor custom. Se contenter d'un mécanisme de masquage/affichage par groupes — c'est 90 % de la valeur d'usage avec 5 % de la complexité.
- **Aucun red flag bloquant** : la combinaison AX API publique + `_AXUIElementGetWindow` privé est utilisée en production par yabai, AeroSpace, Hammerspoon, Rectangle, Amethyst. Stabilité prouvée depuis macOS 10.7.

---

## Out of Scope (V1)

- Plus de 2 stages.
- Hotkey globale intégrée à l'outil (à câbler externement).
- Interface graphique (menu bar, sidebar visuelle, thumbnails).
- Synchronisation cloud ou multi-machine.
- Auto-assignation par règles (ex. "Slack toujours dans stage 2").
- Préservation de l'ordre Z relatif des fenêtres dans un stage.
- Backup/restore de la configuration.
- Animation des transitions.
