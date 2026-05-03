# Feature Specification: Rendus modulaires du navrail

**Feature Branch**: `019-rail-renderers`
**Status**: Draft
**Created**: 2026-05-03
**Dependencies**: SPEC-014 (Stage Rail UI)

## Vision

Le rail latéral affiche les stages sous forme de **vignettes empilées en cascade façon Stage Manager natif macOS** (vraies captures ScreenCaptureKit + halo coloré sur stage actif). Ce style est aujourd'hui codé en dur dans `WindowStack.swift`. Or différents utilisateurs ont des préférences différentes : certains veulent voir uniquement les **icônes d'app** (style classement par inventaire), d'autres une **mosaïque à plat** des fenêtres, d'autres encore une **vue parallaxe** stylisée.

Cette spec introduit un **système de rendus interchangeables** symétrique au pattern `Tiler`/`TilerRegistry` déjà éprouvé dans `Sources/RoadieTiler/`. L'utilisateur change de rendu via une seule clé TOML `[fx.rail].renderer = "..."` puis `roadie daemon reload` — sans rebuild ni redémarrage. Plusieurs rendus sont livrés progressivement, chacun dans son propre fichier ≤ 200 LOC, indépendants entre eux.

**Aucune modification d'IPC, d'événements, ou de l'état global** : le système ne touche QUE la couche View SwiftUI du rail.

## User Scenarios & Testing *(mandatory)*

### User Story 1 — Refactor non-régressif (Priority: P1)

En tant que mainteneur du projet roadie, je veux que le code de rendu actuel soit extrait dans un module modulaire (protocole + registry + 1 implémentation par défaut), pour pouvoir ajouter de nouveaux rendus sans toucher au consommateur ni risquer de régression visuelle sur le rendu existant.

**Why this priority** : c'est la fondation. Sans cette extraction, ajouter un rendu alternatif force à modifier la classe consommateur à chaque fois (anti-pattern open-closed). C'est aussi la garantie de non-régression : à la fin de cette user story, le rendu visible doit être bit-identique à avant.

**Independent Test** : un screenshot du rail avant le refactor doit être visuellement identique à un screenshot après refactor (mêmes stages, mêmes captures, même halo, même cascade, même alignement). Aucune nouvelle ligne dans la config TOML utilisateur n'est requise (compat ascendante stricte).

**Acceptance Scenarios** :
1. **Given** un utilisateur sur la branche `main` qui n'a jamais touché à `[fx.rail].renderer` dans son TOML, **When** il met à jour vers la branche 019-rail-renderers et redémarre le daemon, **Then** le rail affiche exactement les mêmes vignettes empilées en cascade qu'avant.
2. **Given** la même configuration, **When** le développeur exécute `roadie rail renderers list`, **Then** la commande retourne au minimum `stacked-previews` (le rendu actuel, marqué comme défaut).

---

### User Story 2 — Switch fonctionnel de rendu (Priority: P1)

En tant qu'utilisateur du rail, je veux pouvoir changer le rendu visuel des stages en modifiant une seule ligne TOML puis en rechargeant le daemon, pour expérimenter différents styles sans toucher au code ni redémarrer mon environnement.

**Why this priority** : c'est la valeur principale de la feature. Sans ce switch, les rendus alternatifs n'existent pas pour l'utilisateur final. Couplée à US1, cette user story constitue le **MVP livrable**.

**Independent Test** : un second rendu (`icons-only`, le plus simple) est livré. L'utilisateur passe de `stacked-previews` à `icons-only` via TOML + reload, observe un rail visuellement très différent (icônes alignées au lieu de captures empilées), revient à `stacked-previews` + reload, retrouve le rendu d'origine.

**Acceptance Scenarios** :
1. **Given** un rail affichant des vignettes empilées (`stacked-previews`), **When** l'utilisateur édite `~/.config/roadies/roadies.toml` pour mettre `[fx.rail].renderer = "icons-only"` puis exécute `roadie daemon reload`, **Then** le rail bascule en moins d'une seconde sur un affichage par icônes d'app, sans capture pixel.
2. **Given** un TOML avec une valeur de renderer inconnue (faute de frappe), **When** le daemon recharge la config, **Then** un warning est loggé et le rail bascule sur le rendu par défaut (`stacked-previews`) sans crasher.
3. **Given** l'utilisateur exécute `roadie rail renderer icons-only` (CLI direct), **When** la commande termine, **Then** le rail bascule immédiatement en icônes (pas besoin d'éditer TOML manuellement).

---

### User Story 3 — Rendu Hero Preview (Priority: P2)

En tant qu'utilisateur qui préfère voir clairement la fenêtre principale d'un stage, je veux un rendu où la frontmost window du stage est affichée en grand, avec une petite barre d'icônes des autres apps dessous, pour distinguer d'un coup d'œil ce sur quoi le stage est focalisé sans être distrait par les autres fenêtres en cascade.

**Why this priority** : optionnel — apporte un confort visuel mais pas critique pour le MVP. Cohérent avec la philosophie « 1 stage = 1 contexte de travail ».

**Independent Test** : sélection via TOML `renderer = "hero-preview"` + reload → rail affiche par stage 1 grande capture (la fenêtre frontmost) + sous elle une rangée de mini-icônes d'app pour les autres fenêtres.

**Acceptance Scenarios** :
1. **Given** un stage contenant 4 fenêtres dont Firefox au premier plan, **When** le rendu actif est `hero-preview`, **Then** le rail affiche la capture de Firefox en grand et 3 icônes d'app en dessous (les 3 autres apps).
2. **Given** un stage vide (0 fenêtre), **When** le rendu est `hero-preview`, **Then** le rail affiche un placeholder neutre cohérent (icône + texte « Empty stage »).

---

### User Story 4 — Rendu Mosaïque (Priority: P3)

En tant qu'utilisateur qui veut toutes les vignettes simultanément à plat, je veux un rendu en grille 2×2 / 3×2 selon le nombre de fenêtres, pour voir l'ensemble du contenu du stage sans cascade ni occlusion.

**Why this priority** : moins critique, sert principalement les power-users avec beaucoup de fenêtres par stage qui n'aiment pas la cascade.

**Independent Test** : sélection via TOML → rail affiche par stage une grille à plat des captures.

**Acceptance Scenarios** :
1. **Given** un stage avec 4 fenêtres, **When** le rendu est `mosaic`, **Then** le rail affiche une grille 2×2 des captures dans la cellule du stage.
2. **Given** un stage avec 1 fenêtre, **When** le rendu est `mosaic`, **Then** le rail affiche une seule grande vignette occupant toute la cellule.

---

### User Story 5 — Rendu Parallaxe 45° (Priority: P3)

En tant qu'utilisateur qui aime l'esthétique stylisée, je veux un rendu où les vignettes sont empilées avec une rotation 3D 45° sur l'axe Y et une légère animation de bounce au survol, pour que le rail prenne un aspect immersif et différencié.

**Why this priority** : pure esthétique, optionnel.

**Independent Test** : sélection via TOML → rail affiche par stage 3-5 vignettes en perspective 45° + micro-animation au hover.

**Acceptance Scenarios** :
1. **Given** un stage avec 3 fenêtres, **When** le rendu est `parallax-45`, **Then** les 3 vignettes apparaissent inclinées en perspective avec offset croissant.
2. **Given** l'utilisateur passe la souris sur une cellule de stage, **When** le rendu est `parallax-45`, **Then** une micro-animation s'exécute (scale ou bounce) en moins de 200 ms.

---

### Edge Cases

- **Renderer inconnu dans TOML** : log warning + fallback silencieux sur `stacked-previews` (pas de crash).
- **Renderer absent du registre au runtime** (ex: erreur d'init) : même fallback que ci-dessus.
- **Hot reload pendant que l'utilisateur drag-drop une fenêtre** : le drag est annulé proprement, le nouveau rendu reprend après le release.
- **Stage vide** : chaque renderer DOIT afficher un placeholder neutre (texte ou icône) sans crash ni cellule invisible.
- **Stage avec > N fenêtres** où N est la limite du renderer (5 pour stacked, 4 pour mosaic 2×2, etc.) : truncation visuelle avec indicateur « +K » lisible.
- **Migration utilisateur** : un TOML existant sans clé `[fx.rail].renderer` continue à fonctionner avec le rendu par défaut (`stacked-previews`).

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001** : Le système DOIT exposer un protocole public `StageRenderer` définissant un contrat de rendu (identifiant unique, nom d'affichage, fonction de rendu prenant le stage et son contexte de fenêtres).
- **FR-002** : Le système DOIT exposer un registre `StageRendererRegistry` permettant l'enregistrement et la récupération des renderers (symétrique à `TilerRegistry`).
- **FR-003** : Le rendu actuel (cascade de captures empilées) DOIT être extrait dans un fichier `StackedPreviewsRenderer` et enregistré dans le registre comme rendu par défaut.
- **FR-004** : La vue consommatrice (`StageStackView` ou équivalent) DOIT déléguer le rendu d'une cellule de stage au renderer sans connaître son implémentation concrète.
- **FR-005** : La sélection du renderer DOIT se faire via une clé TOML `[fx.rail].renderer = "<id>"` lue au boot et au reload.
- **FR-006** : Si la clé TOML est absente OU vaut un identifiant inconnu, le système DOIT utiliser le renderer par défaut (`stacked-previews`) et logger un warning si la valeur était fournie mais inconnue.
- **FR-007** : Le système DOIT exposer une commande CLI `roadie rail renderers list` retournant la liste des renderers compilés.
- **FR-008** : Le système DOIT exposer une commande CLI `roadie rail renderer <id>` qui modifie la clé TOML et recharge le daemon (équivalent éditer + reload manuel).
- **FR-009** : Le rechargement à chaud (`roadie daemon reload`) DOIT propager le changement de renderer au rail en moins d'une seconde, sans redémarrer le rail ni perdre l'état des stages.
- **FR-010** : Chaque renderer livré DOIT gérer le cas du stage vide (placeholder neutre) et du stage avec plus de fenêtres que sa capacité d'affichage (truncation lisible).
- **FR-011** : Aucun renderer ne DOIT modifier l'état global (`StageManager.stages`, `state.windows`, etc.) ni émettre d'événement IPC. Les renderers sont strictement des transformateurs read-only de la couche View.
- **FR-012** : Au minimum 2 renderers DOIVENT être livrés dans le MVP : `stacked-previews` (extrait de l'existant, US1) et `icons-only` (nouveau, US2). Les renderers `hero-preview`, `mosaic`, `parallax-45` peuvent être livrés en sessions ultérieures.
- **FR-013** : Le drag-drop d'une fenêtre depuis une cellule de stage vers une autre DOIT fonctionner identiquement quel que soit le renderer actif (le renderer ne prend pas en charge le drag-drop, c'est le consommateur qui le gère via les callbacks fournis).
- **FR-014** : Le halo coloré indiquant le stage actif DOIT être appliqué de manière cohérente par tous les renderers (la couleur et l'intensité viennent de `[fx.rail]` config, déjà existante).

### Key Entities

- **StageRenderer** : protocole abstrait qui définit ce qu'un renderer sait faire (identifiant, nom d'affichage, fonction de rendu).
- **StageRendererRegistry** : registre central qui mappe un identifiant de renderer à sa factory ; permet d'énumérer les renderers disponibles.
- **Renderer concret** (5 implémentations prévues) : `StackedPreviewsRenderer`, `IconsOnlyRenderer`, `HeroPreviewRenderer`, `MosaicRenderer`, `Parallax45Renderer`.
- **Configuration `[fx.rail]`** : section TOML existante, étendue avec une nouvelle clé optionnelle `renderer = "<id>"`.

## Assumptions

- Les utilisateurs power-users qui veulent un rendu alternatif sont à l'aise avec l'édition TOML ou la CLI `roadie rail renderer`. Aucune UI graphique de sélection n'est livrée dans cette spec.
- Les renderers ne sont **pas** chargés dynamiquement en runtime (`.dylib`). Ils sont compilés statiquement dans le binaire `roadie-rail`. Ajouter un nouveau renderer requiert recompilation, ce qui est acceptable pour l'audience cible (utilisateurs auto-builders).
- La performance d'un swap de renderer est dominée par le coût du `daemon reload` lui-même (~200-500 ms). Le swap pur côté View est négligeable.
- Le `parallax-45` repose sur les capacités SwiftUI standard (rotation3DEffect, animations). Aucun framework graphique tiers requis.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001** : Un utilisateur peut basculer entre 2 rendus différents en moins de 30 secondes (édition TOML + reload + observation visuelle).
- **SC-002** : Le rendu après refactor (US1 livré) est visuellement identique au rendu avant refactor sur un screenshot pixel-à-pixel d'au moins 3 stages avec contenus variés (différence < 1% des pixels, tolérance compression PNG).
- **SC-003** : Ajouter un nouveau renderer (étape future) ne nécessite la modification d'aucun fichier autre que les fichiers du renderer lui-même + 1 ligne d'enregistrement dans le bootstrap (vérifiable par `git diff` après ajout).
- **SC-004** : Au moins 1 rendu alternatif au défaut est démontrablement utilisable post-MVP (vérifié par exécution de `roadie rail renderer icons-only` retournant exit 0 et déclenchant un changement visuel observable du rail).
- **SC-005** : Aucune régression sur les tests d'acceptance existants du rail (SPEC-014) après livraison du refactor US1.
- **SC-006** : La taille du fichier consommateur (`StageStackView.swift` ou équivalent) diminue d'au moins 30% après refactor US1, signe que la logique de rendu a bien été extraite.
