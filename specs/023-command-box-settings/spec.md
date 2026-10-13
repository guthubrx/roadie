# Feature Specification: Boîte de commandes et fenêtre de réglages

**Feature Branch**: `023-command-box-settings`
**Created**: 2026-10-13
**Status**: Draft
**Dependencies**: SPEC-021-target-search-mode (boîte de recherche Hyper + F), SPEC-009-roadie-target-mode (mode lettres et grille), SPEC-016/017 (configuration rechargée à chaud)
**Input**: User description: « Un équivalent des commandes `/` de Codex et Claude dans Roadie, tapées dans la boîte affichée par Caps Lock + F. Une fenêtre de réglages avec une colonne de catégories à gauche et les réglages à droite. Un réglage pour la taille des étiquettes. `/settings` sans argument ouvre la fenêtre ; avec un argument, il modifie un réglage. »

> Le numéro 022 est pris par la branche `022-audit-remediation` (audit du dépôt). Cette spec prend donc le numéro 023.

## Constat de départ

- La boîte de Caps Lock + F (Hyper + F) sait seulement chercher du texte parmi les cibles à l'écran. Elle ne lance aucune commande.
- Roadie sait déjà faire les actions voulues par la ligne de commande `roadie` : déplacer, inverser, changer de stage, d'écran ou de bureau, bookmarks, grille, entretien.
- Les réglages sont dans un seul fichier de configuration (`roadies.toml`), environ 50 blocs. Rien ne les montre à l'écran. L'utilisateur doit éditer le fichier à la main.
- La configuration est rechargée à chaud : un changement du fichier s'applique sans redémarrer Roadie.
- La taille des étiquettes du mode lettres (texte de 13 points) et de la grille est fixée dans le code. Aucun réglage ne la modifie.
- L'utilisateur veut une fenêtre de réglages dans le style des préférences d'une application Mac : colonne de catégories à gauche, recherche en haut à gauche, réglages à droite, changements appliqués tout de suite, sans bouton « Enregistrer ».

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Ouvrir la fenêtre de réglages depuis la boîte (Priority: P1)

L'utilisateur appuie sur Caps Lock + F et tape `/settings`, puis Retour. Une fenêtre de réglages s'ouvre. À gauche : une recherche et la liste des catégories. À droite : les réglages de la catégorie choisie. L'utilisateur change un réglage ; il s'applique tout de suite.

**Why this priority**: c'est la demande de départ de l'utilisateur. Sans cette fenêtre, les autres parties n'ont pas d'intérêt visible.

**Independent Test**: Caps Lock + F, `/settings`, Retour. La fenêtre s'ouvre sur la première catégorie. Changer l'opacité du remplissage de la grille de 0,10 à 0,40. Lancer la grille : son fond est plus visible, sans redémarrage de Roadie.

**Acceptance Scenarios**:

1. **Given** la boîte ouverte, **When** l'utilisateur tape `/settings` puis Retour, **Then** la boîte se ferme et la fenêtre de réglages s'ouvre au premier plan.
2. **Given** la fenêtre ouverte, **When** l'utilisateur clique une catégorie à gauche, **Then** les réglages de cette catégorie s'affichent à droite.
3. **Given** un réglage affiché, **When** l'utilisateur le change, **Then** la nouvelle valeur s'applique tout de suite et reste après un redémarrage de Roadie.
4. **Given** la fenêtre déjà ouverte, **When** l'utilisateur lance `/settings` encore une fois, **Then** la même fenêtre passe au premier plan, sans seconde fenêtre.
5. **Given** la fenêtre ouverte, **When** l'utilisateur appuie sur Échap ou Cmd + W, **Then** la fenêtre se ferme et l'application qui était au premier plan avant l'ouverture reprend le focus.
6. **Given** la fenêtre ouverte, **When** le fichier de configuration change par une autre voie (édition à la main, commande `/set`), **Then** la fenêtre affiche la nouvelle valeur sans être rouverte.

---

### User Story 2 - Régler la taille des étiquettes (Priority: P1)

L'utilisateur trouve un réglage de taille pour les étiquettes du mode lettres et un autre pour la grille. Il les agrandit. Les étiquettes suivantes sont plus grosses et restent lisibles.

**Why this priority**: demande explicite. Les étiquettes sont trop petites pour l'utilisateur.

**Independent Test**: Régler la taille des étiquettes du mode lettres à 20 points. Lancer le mode lettres : les étiquettes sont plus grosses que celles à 13 points et ne se superposent pas plus qu'avant.

**Acceptance Scenarios**:

1. **Given** aucun réglage de taille posé, **When** le mode lettres ou la grille s'affiche, **Then** l'aspect est identique à celui d'avant cette fonction.
2. **Given** une taille plus grande pour le mode lettres, **When** le mode lettres s'affiche, **Then** le texte, le cadre de l'étiquette et l'espace autour grandissent en proportion.
3. **Given** une taille plus grande pour la grille, **When** la grille s'affiche, **Then** les étiquettes de la grille grandissent de la même façon.
4. **Given** une valeur hors des limites permises, **When** l'utilisateur la saisit, **Then** Roadie la refuse et dit la plage permise.

---

### User Story 3 - Lancer des commandes depuis la boîte (Priority: P1)

L'utilisateur tape `/` dans la boîte. La boîte passe en mode commande et liste les commandes. Il tape le début d'une commande, par exemple `/stage 2`, puis Retour. Roadie l'exécute et la boîte se ferme. Sans `/` au début, la boîte reste en mode recherche de texte, comme avant.

**Why this priority**: c'est le cœur de la demande « équivalent des commandes `/` de Codex et Claude ».

**Independent Test**: Avec deux stages, Caps Lock + F, `/stage 2`, Retour : le stage 2 devient visible. Caps Lock + F, `/screen droite`, Retour : le focus passe à l'écran de droite.

**Acceptance Scenarios**:

1. **Given** la boîte ouverte, **When** l'utilisateur tape `/`, **Then** la boîte affiche la liste des commandes, avec une courte description de chacune.
2. **Given** un début de commande, **When** l'utilisateur tape des lettres, **Then** la liste ne garde que les commandes qui correspondent, sans tenir compte de la casse ni des accents.
3. **Given** une commande complète, **When** l'utilisateur appuie sur Retour, **Then** Roadie l'exécute sur le contexte actif à cet instant (la fenêtre qui avait le focus à l'ouverture, sauf changement pendant la saisie), puis ferme la boîte.
4. **Given** une commande inconnue ou des arguments faux, **When** l'utilisateur appuie sur Retour, **Then** la boîte reste ouverte et affiche un message d'erreur court, avec la forme attendue de la commande.
5. **Given** la boîte en mode commande, **When** l'utilisateur efface le `/`, **Then** la boîte revient au mode recherche de texte.
6. **Given** la boîte ouverte, **When** l'utilisateur appuie sur Échap, **Then** la boîte se ferme sans action.

---

### User Story 4 - Modifier un réglage avec `/set` (Priority: P2)

L'utilisateur tape `/set target_grid.overlay_fill_opacity 0.4`. Roadie change ce réglage et l'applique. `/set target_grid.overlay_fill_opacity` seul affiche la valeur actuelle, le réglage par défaut et la plage permise. `/settings grille` ouvre la fenêtre sur la catégorie Grille.

**Why this priority**: c'est le second usage demandé de `/settings` : régler sans ouvrir la fenêtre. Elle dépend de la fenêtre (P1) pour partager la même liste de réglages.

**Independent Test**: `/set target_grid.overlay_fill_opacity 0.4`, Retour, puis ouvrir la grille : son fond est plus visible. `/set target_grid.overlay_fill_opacity`, Retour : la boîte affiche « 0.4 (défaut 0.1, de 0 à 1) ».

**Acceptance Scenarios**:

1. **Given** un nom de réglage et une valeur valides, **When** l'utilisateur lance `/set nom valeur`, **Then** la valeur est écrite dans le fichier de configuration et appliquée sans redémarrage.
2. **Given** un nom de réglage seul, **When** l'utilisateur lance `/set nom`, **Then** la boîte affiche la valeur actuelle, la valeur par défaut et la plage permise.
3. **Given** une valeur invalide, **When** l'utilisateur lance `/set nom valeur`, **Then** le fichier ne change pas, et la boîte dit pourquoi la valeur est refusée. Cela vaut aussi pour une valeur correcte en soi qui rend le fichier invalide : par exemple 4 lignes de grille avec seulement 9 lettres d'étiquettes.
4. **Given** un début de nom après `/set `, **When** l'utilisateur appuie sur Tab, **Then** la boîte complète le nom, ou propose la liste des noms qui correspondent.
5. **Given** un nom de catégorie, **When** l'utilisateur lance `/settings catégorie`, **Then** la fenêtre s'ouvre sur cette catégorie.
6. **Given** un réglage modifié, **When** l'utilisateur lance `/set nom défaut`, **Then** le réglage reprend sa valeur par défaut.

---

### User Story 5 - Commandes de fenêtre, stage, écran, bureau et disposition (Priority: P2)

L'utilisateur dispose des commandes de navigation et de disposition : `/move`, `/swap`, `/resize`, `/full`, `/max`, `/stage`, `/screen`, `/send`, `/desktop`, `/layout`, `/balance`, `/split`.

**Why this priority**: ce sont les actions les plus utiles. Elles remplacent des raccourcis difficiles à retenir. Elles ne bloquent pas le reste.

**Independent Test**: `/swap droite` inverse la fenêtre active avec sa voisine de droite. `/stage new` crée un stage. `/layout float` met le stage courant en disposition flottante.

**Acceptance Scenarios**:

1. **Given** une fenêtre active, **When** l'utilisateur lance `/move gauche`, `/swap droite` ou `/resize haut`, **Then** l'action a le même effet que la commande `roadie` correspondante.
2. **Given** une fenêtre active, **When** l'utilisateur lance `/full` ou `/max`, **Then** la fenêtre passe en plein écran natif, ou est agrandie, comme avec la commande `roadie` correspondante.
3. **Given** des stages existants, **When** l'utilisateur lance `/stage 2` ou `/stage` suivi du nom, **Then** ce stage devient visible. `/stage new` crée un stage. `/stage rename NOM` renomme le stage courant. `/stage send 3` envoie la fenêtre active dans le stage 3.
4. **Given** plusieurs écrans, **When** l'utilisateur lance `/screen droite` ou `/send 2`, **Then** le focus passe à l'écran de droite, ou la fenêtre active passe à l'écran numéro 2.
5. **Given** plusieurs bureaux, **When** l'utilisateur lance `/desktop 2`, **Then** le bureau 2 devient actif.
6. **Given** un stage, **When** l'utilisateur lance `/layout bsp|spatial|master|float`, `/balance` ou `/split h|v`, **Then** la disposition change comme avec la commande `roadie` correspondante.
7. **Given** les directions, **When** l'utilisateur les tape en français (gauche, droite, haut, bas) ou en anglais (left, right, up, down), **Then** les deux formes sont acceptées.

---

### User Story 6 - Bookmarks, grille, mode lettres et entretien (Priority: P2)

L'utilisateur lance depuis la boîte : `/bm a` (aller au bookmark a), `/bm set a` (poser le bookmark a), `/grid` et `/grid fenêtre`, `/letters`, `/doctor`, `/heal`, `/reload`, `/restart`.

**Why this priority**: les bookmarks remplacent le schéma de raccourcis Fn abandonné. L'entretien permet de réparer sans quitter le clavier.

**Independent Test**: `/bm set a` sur une fenêtre, changer de fenêtre, puis `/bm a` : le focus revient sur la première fenêtre. `/doctor` affiche le résultat du diagnostic dans la boîte.

**Acceptance Scenarios**:

1. **Given** une fenêtre active, **When** l'utilisateur lance `/bm set a` puis, plus tard, `/bm a`, **Then** la fenêtre prend le focus.
2. **Given** la boîte, **When** l'utilisateur lance `/grid` ou `/grid fenêtre`, **Then** la boîte se ferme et la grille de l'écran, ou de la fenêtre active, s'ouvre.
3. **Given** la boîte, **When** l'utilisateur lance `/letters`, **Then** la boîte se ferme et le mode lettres s'ouvre.
4. **Given** une commande d'entretien, **When** l'utilisateur lance `/doctor`, `/heal`, `/reload` ou `/restart`, **Then** la commande a le même effet que la commande `roadie` du même nom, et la boîte affiche un résultat court.

---

### User Story 7 - Confort de saisie : complétion, historique, alias (Priority: P3)

Tab complète une commande ou un argument (noms de stage, lettres de bookmark, noms de réglage). Flèche haut rappelle la dernière commande. Des alias courts existent : `/s` pour stage, `/d` pour desktop, `/b` pour bm.

**Why this priority**: améliore la vitesse, mais la boîte est utilisable sans.

**Independent Test**: `/st` puis Tab affiche `/stage `. Après `/stage 2` puis Retour, rouvrir la boîte, taper `/` puis Flèche haut : `/stage 2` revient.

**Acceptance Scenarios**:

1. **Given** un début de commande, **When** l'utilisateur appuie sur Tab, **Then** la boîte complète la commande si une seule correspond, ou fait avancer la sélection dans la liste.
2. **Given** des commandes déjà lancées, **When** l'utilisateur appuie sur Flèche haut dans la boîte en mode commande, **Then** la commande précédente revient, en remontant dans l'historique.
3. **Given** un alias, **When** l'utilisateur le tape, **Then** il agit comme la commande complète.
4. **Given** un redémarrage de Roadie, **When** l'utilisateur rouvre la boîte, **Then** l'historique des 50 dernières commandes est conservé.

---

### User Story 8 - Tous les réglages classés par catégories (Priority: P3)

La fenêtre couvre tous les réglages simples de Roadie (nombres, interrupteurs, choix, couleurs, textes) répartis dans les catégories : Général, Tuilage, Stages et bureaux, Mode lettres, Grille, Recherche, Rail, Bordures, Focus et souris, Règles (lecture seule), Avancé. La recherche en haut à gauche trouve un réglage par son nom ou sa description.

**Why this priority**: les premières catégories (Mode lettres, Grille, Recherche, Rail) donnent déjà une fenêtre utile avec les stories P1. Les autres complètent la couverture.

**Independent Test**: taper « bordure » dans la recherche : les réglages des bordures s'affichent, toutes catégories confondues. Ouvrir « Règles » : la liste des règles s'affiche, sans champ à modifier, avec un bouton qui ouvre le fichier de configuration.

**Acceptance Scenarios**:

1. **Given** la fenêtre ouverte, **When** l'utilisateur tape un mot dans la recherche, **Then** la colonne de droite affiche les réglages dont le nom ou la description contient ce mot, quelle que soit la catégorie, sans tenir compte de la casse ni des accents.
2. **Given** un réglage modifié, **When** l'utilisateur clique « Rétablir », **Then** le réglage reprend sa valeur par défaut.
3. **Given** un réglage qui n'est pas un réglage simple (liste de règles, liste de stages nommés, hooks), **When** l'utilisateur ouvre sa catégorie, **Then** il le voit en lecture seule avec un bouton « Ouvrir le fichier de configuration ».
4. **Given** chaque catégorie, **When** l'utilisateur l'ouvre, **Then** chaque réglage montre un nom lisible, une courte description, et la valeur actuelle.

---

### Edge Cases

- Le fichier de configuration est invalide : la fenêtre l'indique, ne modifie rien, et propose d'ouvrir le fichier. `/set` est refusé avec le même message.
- Le fichier de configuration contient des commentaires et des réglages inconnus : une modification les conserve tous. Seule la ligne modifiée change.
- La fenêtre de réglages et `/set` modifient le même réglage à la suite : la dernière valeur écrite gagne et la fenêtre l'affiche.
- La fenêtre active peut changer ou disparaître pendant la saisie : la commande agit sur le contexte actif à Retour. S'il n'y a plus de fenêtre active, la commande est refusée avec un message clair.
- Aucune fenêtre active : les commandes qui en demandent une sont refusées avec un message clair.
- Un seul écran : `/screen` dit qu'il n'y a pas d'autre écran, sans erreur technique. Les bureaux se créent à la demande : `/desktop N` n'échoue pas pour un bureau absent.
- Une commande non implémentée par Roadie (par exemple fermer une fenêtre) n'est pas proposée.
- Le mode recherche de texte reste inchangé quand le texte ne commence pas par `/`. Un texte qui doit commencer par `/` se tape précédé d'un espace.
- La fenêtre de réglages est ouverte quand l'utilisateur change d'écran ou de bureau : elle reste ouverte.

## Requirements *(mandatory)*

### Functional Requirements

**Boîte de commandes**

- **FR-001**: La boîte de recherche (Caps Lock + F) MUST passer en mode commande quand le premier caractère saisi est `/`, et rester en mode recherche de texte sinon.
- **FR-002**: En mode commande, la boîte MUST lister les commandes avec une description courte et MUST filtrer cette liste pendant la frappe, sans tenir compte de la casse ni des accents.
- **FR-003**: Retour MUST exécuter la commande saisie. En cas de succès, la boîte MUST se fermer, sauf pour les commandes qui rendent un résultat à lire (`/doctor`, `/heal`, `/reload`, `/set`), dont la boîte MUST afficher le résultat et rester ouverte jusqu'à la frappe suivante ou Échap. En cas d'échec, la boîte MUST rester ouverte avec un message d'erreur court qui donne la forme attendue.
- **FR-004**: Une commande MUST agir sur la fenêtre, le stage, l'écran et le bureau actifs au moment où elle s'exécute. La boîte n'enlève pas le focus à la fenêtre active : ce contexte est celui de l'ouverture, sauf si l'utilisateur change de fenêtre pendant la saisie.
- **FR-005**: Les commandes de ce périmètre MUST avoir le même effet que la commande `roadie` correspondante : `/move`, `/swap`, `/resize`, `/full`, `/max`, `/stage` (numéro, nom, `new`, `rename`, `send`), `/screen`, `/send` (numéro d'écran), `/desktop`, `/layout`, `/balance`, `/split`, `/bm`, `/grid`, `/letters`, `/doctor`, `/heal`, `/reload`, `/restart`.
- **FR-006**: Les directions MUST être acceptées en français (gauche, droite, haut, bas) et en anglais (left, right, up, down).
- **FR-007**: Tab MUST compléter une commande ou un argument. Flèche haut et Flèche bas MUST parcourir l'historique des commandes en mode commande. L'historique MUST garder les 50 dernières commandes, y compris après un redémarrage.
- **FR-008**: Des alias courts MUST exister pour les commandes les plus fréquentes : `/s` (stage), `/d` (desktop), `/b` (bm).
- **FR-009**: La boîte MUST afficher le résultat d'une commande d'information (`/doctor`, `/set nom`) dans la boîte même.
- **FR-010**: Le comportement du mode recherche de texte de la SPEC-021 MUST rester identique quand la saisie ne commence pas par `/` : même décodage des touches (les caractères ignorés restent ignorés et laissés à l'application active), mêmes correspondances.

**Fenêtre de réglages**

- **FR-011**: Roadie MUST ouvrir une fenêtre de réglages par `/settings`, avec : à gauche une zone de recherche et la liste des catégories ; à droite les réglages de la catégorie choisie.
- **FR-012**: La fenêtre MUST être unique. Une seconde demande d'ouverture MUST ramener la fenêtre existante au premier plan.
- **FR-013**: Un réglage modifié dans la fenêtre MUST être écrit dans le fichier de configuration et MUST s'appliquer sans redémarrage et sans bouton « Enregistrer ».
- **FR-014**: Chaque réglage MUST montrer un nom lisible, une description courte, un contrôle adapté à son type (interrupteur, nombre avec limites, choix dans une liste, texte, couleur) et la possibilité de reprendre la valeur par défaut.
- **FR-015**: La zone de recherche MUST filtrer les réglages de toutes les catégories par nom et par description, sans tenir compte de la casse ni des accents.
- **FR-016**: Les catégories MUST être : Général, Tuilage, Stages et bureaux, Mode lettres, Grille, Recherche, Rail, Bordures, Focus et souris, Règles, Avancé.
- **FR-017**: Les réglages qui ne sont pas simples (listes de règles, stages nommés, hooks, surcharges par écran) MUST s'afficher en lecture seule avec un bouton qui ouvre le fichier de configuration.
- **FR-018**: La fenêtre MUST suivre le fichier : un changement fait ailleurs MUST apparaître sans rouvrir la fenêtre.
- **FR-019**: La fenêtre MUST se fermer avec Échap et Cmd + W, suivre l'apparence claire ou sombre du système, et le texte de l'interface MUST être en français. Les messages techniques du validateur de configuration (identiques à ceux de `roadie config validate`) restent tels quels.

**Réglages en ligne de commande dans la boîte**

- **FR-020**: `/settings` sans argument MUST ouvrir la fenêtre ; `/settings catégorie` MUST l'ouvrir sur cette catégorie.
- **FR-021**: `/set nom valeur` MUST écrire la valeur dans le fichier de configuration après validation ; `/set nom` MUST afficher la valeur actuelle, la valeur par défaut et la plage permise ; `/set nom défaut` MUST rétablir la valeur par défaut.
- **FR-022**: Une valeur invalide MUST laisser le fichier intact, et la boîte MUST donner la raison du refus.
- **FR-023**: Un nom de réglage MUST identifier une seule clé du fichier de configuration. Il a la forme `table.clé`, où `table` est le chemin de la table sans le préfixe `experimental.` ni `fx.` (par exemple `target_grid.overlay_fill_opacity`, `app_targets.max_targets`, `rail.header.display.font_size`). Les noms MUST être les mêmes dans la fenêtre, dans `/set` et dans la complétion de la boîte.
- **FR-024**: Une modification MUST conserver les commentaires, l'ordre et les réglages inconnus du fichier de configuration. Seule la ligne concernée change.

**Taille des étiquettes**

- **FR-025**: Un réglage de taille MUST exister pour les étiquettes du mode lettres, et un autre pour les étiquettes de la grille, avec des limites minimale et maximale.
- **FR-026**: Sans valeur posée, l'aspect des étiquettes MUST rester identique à celui d'avant cette fonction.
- **FR-027**: Une taille plus grande MUST agrandir le texte, le cadre et l'espace autour, en gardant l'étiquette dans l'écran et sans plus de superposition qu'avant.

**Général**

- **FR-028**: Toute commande ou réglage nouveau MUST être documenté dans la documentation utilisateur du projet (français et anglais).
- **FR-029**: Roadie MUST journaliser (journal d'événements existant) chaque réglage modifié (nom du réglage et résultat) et chaque commande refusée (nom de la commande si elle est connue, et raison). Le journal MUST NOT contenir la valeur d'un réglage ni la saisie brute de l'utilisateur.

### Key Entities

- **Commande de la boîte** : nom, alias, description courte, forme des arguments, effet. Exemple : `stage`, alias `s`, argument numéro ou nom.
- **Réglage** : nom stable (par exemple `target_grid.overlay_fill_opacity`), catégorie, description, type (interrupteur, nombre, choix, texte, couleur), valeur par défaut, limites, valeur actuelle, caractère simple ou lecture seule.
- **Catégorie** : nom affiché, ordre, liste de réglages.
- **Historique de commandes** : les 50 dernières commandes tapées, de la plus récente à la plus ancienne.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Caps Lock + F, `/settings`, Retour ouvre la fenêtre en moins de 1 seconde.
- **SC-002**: Un réglage changé dans la fenêtre prend effet en moins de 2 secondes, sans redémarrage.
- **SC-003**: Les étiquettes du mode lettres à 20 points sont visiblement plus grosses qu'à 13 points ; sans réglage, l'aspect est identique à l'actuel (validation utilisateur à l'écran).
- **SC-004**: Chaque commande de FR-005 a un test qui montre le même effet que la commande `roadie` correspondante.
- **SC-005**: Après 20 modifications par `/set` et par la fenêtre, le fichier de configuration garde tous ses commentaires et ses réglages inconnus (comparaison avant/après de ces lignes).
- **SC-006**: Le mode recherche de texte de la SPEC-021 passe tous ses tests actuels, sans changement.
- **SC-007**: Chaque clé simple reconnue par le validateur de configuration (hors clés sans effet et hors table héritée `fx.rail.header`) apparaît dans une seule catégorie de la fenêtre ; aucune ne manque. Les clés inconnues du validateur (par exemple `persistence_ms`) ne sont pas montrées.
- **SC-008**: Une commande invalide ne modifie aucun état de Roadie et la boîte affiche la forme attendue.

## Assumptions

- La boîte et la fenêtre sont dessinées par Roadie lui-même (pas d'application tierce).
- Les commandes passent par les mêmes services que la ligne de commande `roadie` : aucune action nouvelle n'est créée, seulement un nouveau moyen de les lancer.
- Les réglages sans effet connus de Roadie (par exemple `desktops.*`, `stage_manager.enabled`) ne sont pas montrés dans la fenêtre.
- La catégorie « Général » ne contient pas de réglage : elle montre le fichier de configuration (chemin, état de validité) et les actions « Ouvrir », « Recharger » et « Diagnostic ».
- Les listes de tables du fichier (règles, stages nommés, hooks, surcharges) restent à éditer à la main dans cette version. La fenêtre les montre en lecture seule.
- L'unité de la taille des étiquettes est le point (la taille du texte). Les limites exactes sont fixées dans le plan.
- Les noms des commandes et des réglages sont en français (avec alias anglais pour les directions) ; une traduction anglaise complète de la fenêtre est hors périmètre.
- Il n'existe pas de commande « mettre une fenêtre en flottant » dans Roadie aujourd'hui (la ligne de commande la déclare non implémentée) : `/float` n'est pas proposée. `/layout float` règle la disposition du stage.
- La commande « fermer une fenêtre » n'existe pas dans Roadie aujourd'hui (la ligne de commande la déclare non implémentée) : elle est hors périmètre.
- Le raccourci Caps Lock + F reste celui de la SPEC-021 et reste réglable.

## Hors périmètre

- Éditer les règles par application, les stages nommés ou les hooks dans la fenêtre.
- Un système de plugins de commandes écrits par l'utilisateur.
- Les commandes demandant une saisie de texte libre longue (par exemple l'écriture d'un script).
- La traduction anglaise de l'interface de la fenêtre.
