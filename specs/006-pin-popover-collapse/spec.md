# Spécification Fonctionnelle : Menu Pin et Repliage

**Branche** : `030-window-pins`  
**Créée le** : 2026-05-11  
**Statut** : Brouillon  
**Entrée utilisateur** : "un menu comme ca, déclenché par un pseudo bouton cercle bleu qui ressemble aux boutons macos en type (cercle) et taille, qui doublonne les fonctionalités qu'on a sur le clic droit sur les barre de titre et qui ajoute le repliage d'une fenetre comme tu recommandes option 2) et ca permettrait aussi de gerer les mode pins qui restera a affiner dans un secon temps"

## Scénarios Utilisateur & Tests *(obligatoire)*

### Récit Utilisateur 1 - Ouvrir un menu de pin depuis un bouton visible (Priorité : P1)

En tant qu'utilisateur, je veux voir un petit bouton circulaire bleu sur les fenêtres gérées afin d'accéder rapidement aux actions de pin sans devoir retrouver le clic droit sur la barre de titre.

**Pourquoi cette priorité** : C'est le point d'entrée de toute la fonctionnalité. Sans bouton visible et fiable, le menu ne résout pas le problème d'accessibilité des actions de pin.

**Test indépendant** : Afficher une fenêtre gérée, vérifier qu'un bouton circulaire bleu apparaît dans la zone de titre sans masquer les boutons natifs essentiels, cliquer dessus, puis vérifier que le menu affiche les mêmes actions principales que le menu existant de barre de titre.

**Scénarios d'acceptation** :

1. **Étant donné** une fenêtre gérée visible, **lorsque** l'utilisateur regarde sa barre de titre, **alors** un bouton circulaire bleu de taille comparable aux boutons macOS est visible et identifiable comme contrôle Roadie.
2. **Étant donné** une fenêtre gérée visible, **lorsque** l'utilisateur clique sur le bouton circulaire bleu, **alors** un menu compact de style macOS apparaît à proximité du bouton.
3. **Étant donné** une fenêtre non pinée et `show_on_unpinned = true`, **lorsque** l'utilisateur ouvre le menu, **alors** les actions de pin sont disponibles sans action de repliage.

---

### Récit Utilisateur 2 - Utiliser un menu visuel cohérent avec les actions existantes (Priorité : P1)

En tant qu'utilisateur, je veux que le menu du bouton donne accès aux mêmes actions que le clic droit de barre de titre afin de ne pas avoir deux modèles mentaux différents pour déplacer, pinner ou dépinner une fenêtre.

**Pourquoi cette priorité** : Le menu ne doit pas devenir un second système divergent. Il doit rendre les actions existantes plus découvrables, pas ajouter de confusion.

**Test indépendant** : Depuis une fenêtre pinée, ouvrir le menu bouton et vérifier que les actions de stage, desktop, écran et pin disponibles dans le clic droit sont présentes avec des libellés cohérents et des destinations filtrées de la même manière.

**Scénarios d'acceptation** :

1. **Étant donné** une fenêtre pinée, **lorsque** l'utilisateur ouvre le menu du bouton, **alors** il peut envoyer la fenêtre vers une stage, un desktop ou un écran selon les mêmes règles que le menu de barre de titre.
2. **Étant donné** une fenêtre pinée en mode "ce desktop", **lorsque** l'utilisateur ouvre le menu, **alors** il voit clairement l'état actif et l'action permettant de passer vers "tous les desktops".
3. **Étant donné** une fenêtre pinée en mode "tous les desktops", **lorsque** l'utilisateur ouvre le menu, **alors** il voit clairement l'état actif et l'action permettant de revenir vers "ce desktop".
4. **Étant donné** une action indisponible dans le contexte courant, **lorsque** le menu est affiché, **alors** l'action est absente ou désactivée avec une présentation non ambiguë.

---

### Récit Utilisateur 3 - Replier une fenêtre pinée en proxy de titre (Priorité : P2)

En tant qu'utilisateur, je veux replier une fenêtre pinée pour libérer la vue sur les fenêtres dessous, tout en gardant un repère visible et restaurable.

**Pourquoi cette priorité** : Les pins peuvent masquer des fenêtres dans d'autres stages ou desktops. Le repliage est la réponse fonctionnelle principale au problème "comment voir ce qui est dessous ?".

**Test indépendant** : Pinner une fenêtre qui recouvre une autre fenêtre, la replier depuis le menu, vérifier que la fenêtre réelle ne masque plus la fenêtre dessous, puis restaurer la fenêtre depuis le proxy visible.

**Scénarios d'acceptation** :

1. **Étant donné** une fenêtre pinée visible, **lorsque** l'utilisateur choisit "Replier" dans le menu, **alors** la fenêtre ne masque plus le contenu dessous et un proxy compact reste visible à l'emplacement attendu.
2. **Étant donné** une fenêtre pinée repliée, **lorsque** l'utilisateur clique ou active le proxy, **alors** la fenêtre retrouve son état visible précédent avec sa position et sa taille précédentes.
3. **Étant donné** une fenêtre pinée repliée, **lorsque** l'utilisateur change de stage ou de desktop dans le scope du pin, **alors** le proxy reste disponible sans déclencher de saut de layout.
4. **Étant donné** une fenêtre pinée repliée, **lorsque** l'utilisateur retire le pin, **alors** le proxy disparaît et la fenêtre redevient une fenêtre normale dans un contexte unique.

---

### Récit Utilisateur 4 - Préparer l'affinage futur des modes de pin (Priorité : P3)

En tant qu'utilisateur avancé, je veux que le menu puisse exposer les modes de pin actuels et futurs sans réorganiser toute l'interface plus tard.

**Pourquoi cette priorité** : Les modes exacts de pin restent à affiner, mais l'interface doit déjà réserver une zone claire pour les modes afin d'éviter de casser l'expérience utilisateur lors d'une évolution.

**Test indépendant** : Ouvrir le menu d'une fenêtre pinée et vérifier qu'une zone "Pin" ou équivalente regroupe les modes actuels, l'état actif et les actions liées au pin sans mélanger ces choix avec les déplacements de fenêtre.

**Scénarios d'acceptation** :

1. **Étant donné** une fenêtre pinée, **lorsque** le menu est ouvert, **alors** les modes de pin sont regroupés dans une zone dédiée et lisible.
2. **Étant donné** l'ajout futur d'un nouveau mode de pin, **lorsque** ce mode est exposé dans le menu, **alors** il peut être ajouté dans la zone des modes sans changer les actions principales de déplacement.

### Cas Limites

- Une fenêtre est trop petite pour afficher le bouton sans masquer des contrôles utiles.
- Une application dessine une barre de titre personnalisée ou très dense.
- Une fenêtre pinée est en plein écran natif ou dans un état où les overlays Roadie ne doivent pas gêner les contrôles système.
- Le menu est ouvert puis la fenêtre disparaît, change de stage ou est dépinnée par un autre raccourci.
- Plusieurs fenêtres pinées sont proches ou se chevauchent.
- Le proxy d'une fenêtre repliée risque de masquer un élément critique ou de sortir de l'écran.
- Une fenêtre repliée appartient à une application qui se ferme ou recrée sa fenêtre.

## Exigences *(obligatoire)*

### Exigences Fonctionnelles

- **FR-001** : Roadie DOIT afficher un contrôle circulaire bleu compact sur les fenêtres gérées lorsque cette fonctionnalité est activée avec `show_on_unpinned = true`, et au minimum sur les fenêtres pinées lorsque ce réglage est désactivé.
- **FR-002** : Le contrôle DOIT ressembler visuellement à un contrôle de barre de titre macOS par sa forme et sa taille approximative, tout en restant identifiable comme un contrôle Roadie.
- **FR-003** : Le contrôle DOIT éviter de couvrir les boutons natifs fermer, minimiser, zoom, plein écran ou les contrôles courants de barre de titre lorsqu'il y a assez de place.
- **FR-004** : L'utilisateur DOIT pouvoir ouvrir un menu contextuel compact depuis ce contrôle.
- **FR-005** : Le menu DOIT utiliser une hiérarchie visuelle proche de macOS : groupes d'actions, espacement compact, états actifs clairs, séparateurs si nécessaire, et aucun texte marketing ou explicatif.
- **FR-006** : Le menu DOIT exposer les mêmes destinations de déplacement de fenêtre que le menu contextuel de barre de titre lorsque ces destinations sont valides pour la fenêtre courante.
- **FR-007** : Le menu DOIT exposer l'état de pin courant et permettre de basculer entre les scopes de pin actuellement supportés.
- **FR-008** : Le menu DOIT permettre de retirer le pin de la fenêtre sélectionnée.
- **FR-009** : Le menu DOIT permettre de replier une fenêtre pinée dans un proxy compact sans redimensionner la fenêtre applicative sous-jacente comme comportement utilisateur principal.
- **FR-010** : Une fenêtre pinée repliée DOIT conserver une identité visible suffisante pour que l'utilisateur la reconnaisse, incluant au minimum son application ou son titre.
- **FR-011** : L'utilisateur DOIT pouvoir restaurer une fenêtre pinée repliée depuis son proxy.
- **FR-012** : Le repliage et la restauration DOIVENT préserver la position et la taille précédentes perçues par l'utilisateur.
- **FR-013** : Un pin replié DOIT rester associé au même scope de pin jusqu'à ce que l'utilisateur change ou retire le pin.
- **FR-014** : Le proxy d'un pin replié NE DOIT PAS participer au layout automatique.
- **FR-015** : Le menu DOIT garder les choix de modes de pin regroupés séparément des actions de déplacement vers stage, desktop et écran.
- **FR-016** : Roadie DOIT fournir un moyen de désactiver ce contrôle visible tout en conservant le comportement du menu contextuel de barre de titre existant.
- **FR-017** : Si le contrôle ne peut pas être placé sans risque sur une fenêtre précise, Roadie DOIT éviter de l'afficher sur cette fenêtre plutôt que couvrir les contrôles natifs de l'application.
- **FR-018** : La fonctionnalité NE DOIT PAS changer le comportement des fenêtres non pinées sauf si l'utilisateur invoque explicitement une action liée au pin; l'affichage du bouton seul ne doit pas pinner, déplacer ni replier la fenêtre.
- **FR-019** : La fonctionnalité NE DOIT PAS déclencher d'oscillation de layout, de changement de stage ou de redirection de focus seulement parce que le menu ou le proxy replié est visible.
- **FR-020** : Roadie DOIT exposer assez d'état utilisateur pour comprendre si une fenêtre pinée est visible, repliée, pinée au desktop courant ou pinée à tous les desktops.

### Entités Clés

- **Contrôle de Fenêtre Pinée** : petit point d'entrée circulaire visible attaché à une fenêtre pinée.
- **Menu d'Actions de Pin** : menu compact ouvert depuis le contrôle, regroupant déplacement, état de pin, modes de pin, repliage, restauration et retrait du pin.
- **Proxy de Pin Replié** : représentation compacte visible d'une fenêtre pinée repliée, permettant de restaurer la vraie fenêtre.
- **État de Présentation du Pin** : état visible du pin : visible, replié, restauré, scope courant et sûreté du placement.

## Critères de Succès *(obligatoire)*

### Résultats Mesurables

- **SC-001** : En test manuel, l'utilisateur trouve et ouvre le menu de pin depuis une fenêtre pinée en moins de 2 secondes sans qu'on lui indique de faire un clic droit sur la barre de titre.
- **SC-002** : 95 % des ouvertures de menu apparaissent près du contrôle de fenêtre pinée attendu sans couvrir les contrôles natifs de la fenêtre.
- **SC-003** : L'utilisateur peut replier et restaurer une fenêtre pinée 20 fois consécutives sans que la fenêtre perde sa position ou sa taille précédente perçue.
- **SC-004** : Après repliage d'une fenêtre pinée, la fenêtre ou zone du bureau précédemment couverte devient interactable en moins d'une seconde.
- **SC-005** : Changer de stage ou de desktop 20 fois avec un pin replié ne produit aucun changement de stage inattendu, boucle de focus ou saut de layout.
- **SC-006** : Le menu expose toutes les actions déjà disponibles depuis le menu de barre de titre pour le même contexte de fenêtre, sauf les actions intentionnellement indisponibles dans ce contexte.
- **SC-007** : L'utilisateur peut désactiver le contrôle de pin visible et continuer à utiliser le workflow existant du menu contextuel de barre de titre.

## Hypothèses

- La première version affiche le bouton sur les fenêtres gérées quand `show_on_unpinned = true`; les popups, dialogues et fenêtres non gérées restent exclus.
- L'objectif visuel est inspiré du popover macOS des contrôles de fenêtre, mais la fonctionnalité reste un menu Roadie, pas une copie du tiling macOS.
- Le repliage utilise un proxy possédé par Roadie comme modèle d'expérience, plutôt qu'une tentative de forcer toutes les fenêtres applicatives à une hauteur réelle de barre de titre.
- Les futurs modes de pin exacts sont hors périmètre ; cette fonctionnalité réserve et organise seulement la zone de menu qui les accueillera.
- Les scopes de pin existants restent les modes supportés initiaux : desktop courant et tous les desktops du même écran.
- La sûreté prime sur l'affichage systématique : si le placement est ambigu ou risqué, le contrôle visible peut être omis pour cette fenêtre.
