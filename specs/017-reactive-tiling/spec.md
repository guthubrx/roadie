# Feature Specification: Tiling réactif façon yabai

**Feature Branch**: `017-reactive-tiling`
**Created**: 2026-10-11
**Status**: Implemented (validation manuelle en attente)
**Dependencies**: SPEC-013-persistent-bsp-tree, SPEC-014-bsp-tree-manipulation, SPEC-016-roadie-stabilization (branche de base, non fusionnée)
**Input**: User description: "Je veux que tu fasses le plus propre possible pour avoir un comportement et une réactivité comme yabai."

## Contexte

Le 2026-10-11, l'utilisateur a observé que Roadie range les fenêtres lentement et qu'elles « sautent ». Le journal réel (`~/.roadies/events.jsonl`) et deux analyses de code (Roadie et yabai, dépôt `<yabai-checkout>`) donnent les faits suivants.

- Roadie détecte un changement en 73 ms. Il met ensuite environ 6 s à poser une disposition stable après une sortie de plein écran natif : environ 1 s d'animation macOS, 2 s d'attente fixe, puis 7 passes de placement espacées de 500 ms.
- Le mode utilisé (`mutableBsp`) n'a pas de structure de disposition qui fait autorité. Il recalcule l'ordre, le sens et les proportions depuis la position observée des fenêtres. Chaque passe change cette position, donc la suivante aussi.
- Roadie prend parfois ses propres placements pour des gestes de l'utilisateur. Le journal montre une oscillation de 7 s où une fenêtre reçoit tour à tour 97 px puis 25 px de haut.
- Une fenêtre qui sort du plein écran reçoit une part calculée sur sa taille de transition (33 %) au lieu d'une moitié. Elle refuse cette taille, ce qui relance des passes.
- yabai traite chaque événement une seule fois. Son arbre en mémoire fait foi. Il calcule toute la disposition, puis pose chaque fenêtre une fois, sans relire l'écran. Il accepte qu'une fenêtre refuse sa taille après une seule nouvelle tentative.

Le projet a déjà un mode à arbre persistant (`spatialBsp`, SPEC-013 et SPEC-014). Cette spec rend la réactivité et la stabilité de yabai à l'usage quotidien de l'utilisateur.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Les fenêtres se rangent tout de suite (Priority: P1)

L'utilisateur ouvre, ferme, sort du plein écran ou change de stage. La disposition finale apparaît sans délai perceptible, en un seul mouvement.

**Why this priority**: c'est le défaut signalé. Il rend Roadie pénible à l'usage.

**Independent Test**: sortir une fenêtre du plein écran natif dans une stage de 3 fenêtres. Mesurer le temps entre la fin de l'animation macOS et la disposition stable, et compter les passes de placement.

**Acceptance Scenarios**:

1. **Given** une stage de 2 fenêtres, **When** l'utilisateur ouvre une 3e fenêtre, **Then** la disposition finale est posée en une passe, en moins de 150 ms après l'apparition de la fenêtre.
2. **Given** une fenêtre en plein écran natif, **When** l'utilisateur en sort, **Then** Roadie la range en une passe dès que le bureau utilisateur est de nouveau actif, sans attente fixe.
3. **Given** une stage de 3 fenêtres, **When** l'utilisateur ferme l'une d'elles, **Then** seule la fenêtre voisine récupère la place libérée, en une passe.
4. **Given** deux stages, **When** l'utilisateur passe de l'une à l'autre, **Then** les fenêtres de la stage cible sont à leur place en une passe, sans correction ultérieure.

---

### User Story 2 - Les fenêtres ne sautent plus (Priority: P1)

Une fois rangée, une fenêtre ne bouge plus tant que l'utilisateur ne fait rien. Roadie ne réagit jamais à ses propres placements.

**Why this priority**: les sauts rendent l'usage imprévisible et cassent la confiance.

**Independent Test**: laisser une stage rangée sans interaction pendant 60 s, et compter les placements dans le journal.

**Acceptance Scenarios**:

1. **Given** une stage rangée, **When** aucun événement utilisateur ne survient, **Then** Roadie ne pose aucun placement.
2. **Given** Roadie vient de placer une fenêtre, **When** l'application confirme ce placement avec quelques points d'écart, **Then** Roadie ne l'interprète pas comme un geste manuel.
3. **Given** une fenêtre refuse la taille demandée (taille minimale, pas de redimensionnement d'un terminal), **When** Roadie la place, **Then** il fait au plus une nouvelle tentative, puis accepte la taille obtenue sans relancer de passes.

---

### User Story 3 - Une disposition structurée et prévisible (Priority: P1)

La disposition suit un arbre comme celui de yabai. Une nouvelle fenêtre coupe en deux la fenêtre active. Une fenêtre fermée rend sa place à sa voisine. Les autres fenêtres ne bougent pas.

**Why this priority**: c'est la propreté des placements demandée par l'utilisateur. Elle conditionne aussi la vitesse, car on calcule une fois au lieu de tâtonner.

**Independent Test**: avec 3 fenêtres rangées, ouvrir une 4e quand la fenêtre active est connue. Vérifier que seule la fenêtre active est divisée.

**Acceptance Scenarios**:

1. **Given** un arbre de fenêtres, **When** une fenêtre s'ouvre, **Then** elle divise uniquement la fenêtre active, à 50/50, selon la dimension dominante.
2. **Given** une fenêtre sort du plein écran, **When** elle revient dans la stage, **Then** elle reprend sa place dans l'arbre si elle y est encore, sinon elle est insérée comme une nouvelle fenêtre.
3. **Given** l'utilisateur redimensionne une fenêtre à la souris, **When** il relâche, **Then** la proportion de l'arbre est mise à jour et les voisines s'ajustent une seule fois.
4. **Given** l'utilisateur avait le mode `mutableBsp`, **When** il démarre la nouvelle version, **Then** ses stages gardent leurs fenêtres et leur ordre, et la nouvelle disposition s'applique sans action de sa part.

---

### User Story 4 - Les commandes et le glisser-déposer restent complets (Priority: P2)

Les commandes de l'utilisateur (focus, move, warp, resize, swap, balance, toggle-split, glisser-déposer par la souris et par le navrail) fonctionnent sur l'arbre avec la même réactivité.

**Why this priority**: les raccourcis BetterTouchTool de l'utilisateur en dépendent.

**Independent Test**: exécuter chaque commande des raccourcis actuels et vérifier le résultat attendu et le nombre de passes.

**Acceptance Scenarios**:

1. **Given** un arbre de 3 fenêtres, **When** l'utilisateur lance `roadie move left`, **Then** la fenêtre change de place dans l'arbre et la disposition est posée en une passe.
2. **Given** l'utilisateur glisse une fenêtre sur une autre, **When** il relâche, **Then** la fenêtre est insérée du côté indiqué par l'aperçu, en une passe.

---

### User Story 5 - Mesurer la réactivité (Priority: P2)

Le mainteneur peut mesurer la latence et le nombre de passes, avant et après chaque changement, sur le journal réel.

**Why this priority**: l'Article XXII impose de mesurer avant et après une optimisation.

**Independent Test**: lancer l'outil de mesure sur le journal et obtenir la médiane, le p90 et le maximum de la durée jusqu'à stabilité et du nombre de passes.

**Acceptance Scenarios**:

1. **Given** le journal d'événements, **When** le mainteneur lance l'outil de mesure, **Then** il obtient pour chaque épisode la durée jusqu'à stabilité en millisecondes et le nombre de passes.

---

### Edge Cases

- L'utilisateur sort du plein écran pendant que l'animation de bureau est encore en cours.
- Plusieurs fenêtres apparaissent en rafale (lancement d'une application avec plusieurs fenêtres).
- Une application ne répond pas pendant un placement (quarantaine de la SPEC-016).
- Une fenêtre a une taille minimale supérieure à sa part (terminal, T3 Code).
- Un geste manuel et un événement système arrivent dans la même fenêtre de temps.
- La CLI ou une autre instance modifie l'état persisté pendant que le daemon garde un état en mémoire.
- Les écrans changent (branchement, débranchement) pendant une passe.
- L'arbre persisté contient des fenêtres fermées depuis longtemps.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: Roadie MUST traiter un changement de fenêtre (création, destruction, déplacement, redimensionnement, minimisation, changement de focus, changement de bureau) dès sa notification, sans attendre un cycle périodique.
- **FR-002**: Une passe MUST rassembler tous les placements (règles, épinglages, focus, masquage, disposition) dans un seul plan, dédoublonné par fenêtre, puis l'appliquer une fois. Dans les modes à arbre, les placements MUST NOT être répartis sur plusieurs passes. Les modes `bsp` et `masterStack` gardent leur stratégie, mais profitent du plan unique et de la reconnaissance d'écho.
- **FR-003**: La disposition des modes à arbre MUST être calculée depuis l'arbre en mémoire. La position observée des fenêtres MUST NOT modifier l'arbre, sauf geste manuel de l'utilisateur.
- **FR-004**: Roadie MUST reconnaître l'écho de ses propres placements. Un geste manuel MUST être reconnu par une session de souris (clic puis relâchement sur la fenêtre). Un changement hors session et hors écho MUST être traité comme un changement externe : une seule réécriture vers la disposition de l'arbre, sans modifier l'arbre.
- **FR-005**: Pour une même version de disposition, chaque fenêtre MUST recevoir au plus 2 écritures : l'écriture initiale et une correction après un refus de taille confirmé. Les voisines touchées par cette correction MUST la recevoir dans le même budget. Roadie MUST ensuite accepter la taille obtenue.
- **FR-006**: Roadie MUST NOT imposer d'attente fixe après un changement de membres. Il MUST attendre seulement tant qu'une transition de bureau est en cours, et au plus une durée bornée.
- **FR-007**: Une fenêtre qui revient du plein écran MUST reprendre sa place dans l'arbre si elle y figure encore, sinon être insérée comme une nouvelle fenêtre.
- **FR-008**: Une nouvelle fenêtre MUST diviser la fenêtre active à 50/50 selon la dimension dominante. Une fenêtre fermée MUST rendre sa place à sa voisine directe.
- **FR-009**: L'écriture d'une frame MUST suivre l'ordre taille, position, taille, et neutraliser l'animation d'interface des applications qui l'activent (`AXEnhancedUserInterface`) pendant l'écriture.
- **FR-010**: Une seule tolérance de comparaison de frames MUST décider à la fois « placement réussi » et « placement à refaire ».
- **FR-011**: Le daemon MUST NOT relire ni décoder l'état persisté plusieurs fois par passe. Il MUST voir les écritures faites par la CLI ou un autre processus avant la passe suivante.
- **FR-012**: Les commandes existantes (focus, move, warp, resize, swap, balance, toggle-split, glisser-déposer par la souris et par le navrail, assignation de stage) MUST fonctionner sur l'arbre avec une seule passe par commande.
- **FR-013**: Les stages en mode `mutableBsp` MUST être migrées sans perte de fenêtres, d'ordre ni de stage. Les configurations qui nomment `mutableBsp` MUST rester valides.
- **FR-014**: Un changement de membres isolé MUST déclencher une passe immédiate. Une stabilisation par scope reste due pour une rafale (au moins 2 changements en moins de 300 ms, exigence FR-017 de la SPEC-016). Elle MUST se terminer après 100 ms de calme, plafonnée à 1 s, et MUST relancer immédiatement la passe à son expiration.
- **FR-015**: Chaque passe de placement MUST être tracée avec un horodatage à la milliseconde et la cause qui l'a déclenchée.
- **FR-016**: Un outil MUST calculer, depuis le journal, la durée jusqu'à disposition stable et le nombre de passes par épisode.
- **FR-017**: Un cycle périodique lent MAY rester comme filet de sécurité. Il MUST NOT déplacer une fenêtre dont la frame correspond à l'arbre.
- **FR-018**: Le code rendu inutile par ces changements MUST être supprimé.

### Key Entities

- **Arbre de disposition**: par stage, un arbre binaire. Les feuilles sont des fenêtres. Les nœuds internes portent un sens de division et une proportion. Il fait autorité pour la disposition.
- **Frame écrite**: dernière frame demandée par Roadie pour une fenêtre, avec l'instant d'écriture. Sert à reconnaître l'écho.
- **Épisode de placement**: suite de passes déclenchées par une même cause, jusqu'à la disposition stable.
- **Transition de bureau**: période pendant laquelle macOS anime un changement de bureau ou de plein écran.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Ouverture, fermeture et changement de stage, mesurés depuis le dernier événement d'une rafale : la disposition est stable en moins de 150 ms au p90, en une passe dans au moins 95 % des épisodes. Référence actuelle : environ 2 à 6 s et 2 à 7 passes.
- **SC-002**: Sortie de plein écran natif : la disposition est stable en moins de 300 ms après la fin de l'animation macOS. Référence actuelle : environ 5 s.
- **SC-003**: Stage rangée sans interaction pendant 60 s : zéro placement.
- **SC-004**: Zéro événement « geste manuel » ou « propagation » dans la seconde qui suit un placement de Roadie sans action de l'utilisateur. Référence actuelle : 13 sur 33.
- **SC-005**: Fenêtre qui refuse sa taille : au plus 2 écritures pour cette fenêtre et pour chaque voisine par version de disposition.
- **SC-006**: Les raccourcis actuels de l'utilisateur fonctionnent tous, et la suite de tests passe à 100 %.
- **SC-007**: Le nombre de lectures de l'état persisté par passe tombe à 0 quand aucun autre processus n'a écrit.

## Assumptions

- L'animation macOS de changement de bureau (environ 1 s) n'est pas réductible par Roadie. Les objectifs se comptent après sa fin.
- Le mode `spatialBsp` des SPEC-013 et 014 sert de base à l'arbre. Le plan arbitrera entre l'étendre ou en faire l'unique moteur à arbre.
- Le thread principal reste le lieu des appels Accessibilité et AppKit, sauf preuve contraire au plan.
- Les API privées de macOS (SkyLight) ne sont utilisées que si aucune API publique ne couvre le besoin. Ce choix est justifié par une ADR.
- La mesure fine (milliseconde) exige d'enrichir le journal. Les mesures de référence actuelles ont une précision d'une seconde.
- La garantie « une passe » vise les modes à arbre (`spatialBsp` et ses alias). Les modes `bsp`, `masterStack` et `float` ne sont pas réécrits (voir research.md, A3).
- La garde de transition de bureau lit en lecture seule le type du bureau courant par une API privée (`CGSCopyManagedDisplaySpaces`), avec un repli public. Ce choix est justifié par l'ADR 010.
- Les liserés JankyBorders sont déjà exclus du rangement (commit `8f64410`).
