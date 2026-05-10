# Research: Stage Display Move

## Decision 1: etendre `stage move-to-display` au lieu de creer une nouvelle commande

**Decision**: conserver `roadie stage move-to-display TARGET` et accepter `TARGET` sous deux formes : index visible d'ecran ou direction `left|right|up|down`.

**Rationale**: Roadie possede deja une commande publique pour deplacer la stage active vers un ecran par index. L'etendre limite la surface utilisateur et evite de multiplier les verbes.

**Alternatives considered**:

- `roadie stage send-to-display` : plus clair, mais introduit un synonyme inutile.
- `roadie display receive-stage` : inverse le point de vue utilisateur et rend les raccourcis moins naturels.

## Decision 2: preference dediee dans `[focus]`

**Decision**: ajouter `stage_move_follows_focus` dans la section `[focus]`, avec valeur par defaut `true`.

**Rationale**: la fonctionnalite decide ou reste le contexte actif apres une action. La section `[focus]` contient deja `stage_follows_focus` et `assign_follows_focus`; une cle dediee evite d'etendre abusivement le sens de ces reglages existants.

**Alternatives considered**:

- Reutiliser `assign_follows_focus` : rejetee, car l'assignation de fenetre et le deplacement d'une stage entiere sont deux workflows differents.
- Placer la cle dans `[stage_manager]` : possible, mais moins lisible car l'effet principal est le focus.

## Decision 3: primitive daemon unique

**Decision**: creer ou extraire une primitive de type `moveStageToDisplay(stageID:sourceDisplayID:targetDisplayID:followPolicy:)`, appelee par la CLI et par le navrail.

**Rationale**: la CLI manipule souvent la stage active, alors que le rail doit pouvoir manipuler une stage inactive. Une primitive centrale evite deux implementations divergentes et reduit les regressions focus/bordure deja rencontrees.

**Alternatives considered**:

- Activer la stage puis appeler la commande existante : rejetee, car cela change le focus avant l'action et produit des effets visibles.
- Implementer le menu rail separement : rejetee, car le meme bug pourrait etre corrige dans une surface et pas l'autre.

## Decision 4: resolution directionnelle via `DisplayTopology`

**Decision**: reutiliser `DisplayTopology.neighbor(from:direction:in:)` pour `left|right|up|down`.

**Rationale**: Roadie a deja une logique de voisinage d'ecrans utilisee par les commandes display/focus. Reutiliser cette logique garde un comportement coherent entre focus d'ecran et deplacement de stage.

**Alternatives considered**:

- Trier les ecrans par origine `x/y` directement dans la commande : rejetee, car cela ignore les recouvrements partiels et duplique une logique existante.
- Demander uniquement un index : rejetee, car l'utilisateur veut des raccourcis naturels par direction.

## Decision 5: collision d'identifiant sans perte

**Decision**: si l'ecran cible contient deja une stage avec le meme ID que la stage deplacee, l'implementation doit conserver les deux groupes. Elle peut garder l'ID si la stage cible homonyme est vide et remplacee explicitement, sinon elle doit attribuer un nouvel ID stable a la stage entrante et conserver son nom visible.

**Rationale**: plusieurs ecrans peuvent avoir une stage `1`. Supprimer la stage cible homonyme serait destructif. L'utilisateur se fiche souvent de l'ID interne, mais ne doit jamais perdre ses fenetres.

**Alternatives considered**:

- Fusionner les fenetres des deux stages : rejetee, car non demande et irreversible dans l'experience utilisateur.
- Refuser tout conflit d'ID : surprotege, mais rendrait le multi-ecran tres penible avec des stages numerotees.

## Decision 6: menu contextuel natif sur carte de stage

**Decision**: ajouter un menu contextuel sur `StageCardView` ou son wrapper, avec une entree `Envoyer vers` listant uniquement les autres ecrans.

**Rationale**: la carte de stage est l'objet visible que l'utilisateur veut deplacer. Le menu doit etre decouvrable et ne pas dependre d'un raccourci BTT.

**Alternatives considered**:

- Ajouter un bouton permanent dans chaque stage card : rejetee, car encombre le rail.
- Drag stage card entre rails : interessant mais hors scope v1 ; le besoin valide est le clic droit.
