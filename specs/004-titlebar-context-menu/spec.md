# Spécification Fonctionnelle : Menu Contextuel de Barre de Titre

**Branche** : `029-titlebar-context-menu`  
**Créée le** : 2026-05-10  
**Statut** : Brouillon  
**Entrée utilisateur** : "Ajouter une fonctionnalite experimentale, configurable dans le TOML, qui affiche un menu Roadie quand l'utilisateur fait clic droit dans la zone de barre de titre d'une fenetre. Le menu doit permettre d'envoyer la fenetre vers une autre stage, un autre desktop ou un autre display, sans interferer avec les menus contextuels internes des applications."

## Scénarios Utilisateur et Tests *(obligatoire)*

### Récit Utilisateur 1 - Ouvrir un menu Roadie depuis la barre de titre (Priorité : P1)

En tant qu'utilisateur Roadie, je veux faire clic droit dans la zone haute d'une fenetre et voir un menu Roadie uniquement a cet endroit, afin d'agir sur la fenetre sans perturber les menus contextuels propres aux applications.

**Pourquoi cette priorité** : C'est la condition de securite d'usage de toute la fonctionnalite : si Roadie intercepte les clics droits dans le contenu des applications, l'experience devient intrusive.

**Test indépendant** : Activer la fonctionnalite experimentale, faire clic droit dans la zone haute d'une fenetre geree, puis verifier qu'un menu Roadie apparait ; faire clic droit dans le contenu de la meme fenetre, puis verifier que Roadie ne montre pas son menu.

**Scénarios d'acceptation** :

1. **Étant donné** la fonctionnalite experimentale activee et une fenetre geree par Roadie, **lorsque** l'utilisateur fait clic droit dans la zone de barre de titre reconnue, **alors** Roadie affiche un menu d'actions pour cette fenetre.
2. **Étant donné** la fonctionnalite experimentale activee et une fenetre geree par Roadie, **lorsque** l'utilisateur fait clic droit dans le contenu de l'application, **alors** Roadie ne montre pas son menu et laisse l'application gerer le clic droit.
3. **Étant donné** la fonctionnalite experimentale desactivee, **lorsque** l'utilisateur fait clic droit n'importe ou dans une fenetre, **alors** Roadie ne montre aucun menu de fenetre.

---

### Récit Utilisateur 2 - Configurer la zone experimentale de detection (Priorité : P2)

En tant qu'utilisateur, je veux pouvoir activer ou desactiver ce comportement et ajuster sa zone de detection dans la configuration Roadie, afin de l'adapter aux applications dont les barres de titre sont differentes.

**Pourquoi cette priorité** : La notion de barre de titre varie selon les applications. La fonctionnalite doit donc rester experimentale, reversible et ajustable sans changer le reste de Roadie.

**Test indépendant** : Modifier les parametres experimentaux, recharger la configuration, puis verifier que la zone qui declenche le menu change comme attendu ou que la fonctionnalite se desactive completement.

**Scénarios d'acceptation** :

1. **Étant donné** le reglage experimental desactive, **lorsque** la configuration est rechargee, **alors** Roadie ne capture aucun clic droit de barre de titre.
2. **Étant donné** une hauteur de detection configuree, **lorsque** l'utilisateur clique dans cette hauteur depuis le haut de la fenetre, **alors** Roadie considere le clic comme eligible au menu.
3. **Étant donné** des marges d'exclusion configurees a gauche ou a droite, **lorsque** l'utilisateur clique dans ces marges, **alors** Roadie ne montre pas son menu pour eviter les controles de fenetre ou de toolbar.

---

### Récit Utilisateur 3 - Envoyer la fenetre vers un autre contexte Roadie (Priorité : P3)

En tant qu'utilisateur, je veux que le menu Roadie propose les destinations utiles pour la fenetre, afin de l'envoyer rapidement vers une autre stage, un autre desktop ou un autre ecran.

**Pourquoi cette priorité** : Le menu n'a de valeur que s'il donne acces aux actions frequentes de rangement de fenetre, mais il depend d'abord de la detection non intrusive et de la configuration experimentale.

**Test indépendant** : Ouvrir le menu Roadie depuis une fenetre, choisir une destination de stage, de desktop ou d'ecran, puis verifier que seule la fenetre cible est deplacee vers la destination choisie.

**Scénarios d'acceptation** :

1. **Étant donné** plusieurs stages disponibles, **lorsque** l'utilisateur choisit une autre stage dans le menu, **alors** la fenetre cible est affectee a cette stage.
2. **Étant donné** plusieurs desktops Roadie disponibles, **lorsque** l'utilisateur choisit un autre desktop dans le menu, **alors** la fenetre cible est envoyee vers ce desktop selon le comportement Roadie existant.
3. **Étant donné** plusieurs ecrans disponibles, **lorsque** l'utilisateur choisit un autre ecran dans le menu, **alors** la fenetre cible est envoyee vers cet ecran.
4. **Étant donné** une destination identique au contexte courant de la fenetre, **lorsque** le menu est ouvert, **alors** cette destination est absente ou indiquee comme indisponible.

### Cas Limites

- Si la fenetre sous le curseur n'est pas geree par Roadie, Roadie ne doit pas afficher le menu experimental.
- Si la fenetre est une popup, une palette, un dialogue systeme ou une fenetre transitoire, Roadie ne doit pas afficher le menu experimental.
- Si la zone de clic est ambigue ou impossible a associer a une fenetre, Roadie doit ne rien faire.
- Si une destination disparait entre l'ouverture du menu et la selection, l'action doit echouer proprement sans deplacer la fenetre ailleurs.
- Si un seul ecran, un seul desktop ou une seule stage est disponible, les sous-menus correspondants doivent rester utiles en masquant ou desactivant les destinations impossibles.
- Si l'application utilise une barre de titre personnalisee, Roadie doit privilegier l'absence d'interception plutot qu'un menu affiche au mauvais endroit.

## Exigences *(obligatoire)*

### Exigences Fonctionnelles

- **FR-001**: Le systeme DOIT fournir une option experimentale permettant d'activer ou de desactiver le menu contextuel de barre de titre.
- **FR-002**: Le comportement DOIT etre desactive par defaut.
- **FR-003**: Le systeme DOIT permettre de configurer la hauteur de la zone eligible depuis le haut de la fenetre.
- **FR-004**: Le systeme DOIT permettre de configurer une marge d'exclusion a gauche de la zone eligible.
- **FR-005**: Le systeme DOIT permettre de configurer une marge d'exclusion a droite de la zone eligible.
- **FR-006**: Le systeme DOIT permettre de limiter le menu aux fenetres gerees par Roadie.
- **FR-007**: Le systeme DOIT afficher le menu Roadie uniquement lorsque le clic droit est reconnu dans la zone eligible d'une fenetre cible.
- **FR-008**: Le systeme NE DOIT PAS afficher le menu Roadie lorsque le clic droit est dans le contenu de l'application.
- **FR-009**: Le menu DOIT proposer une action pour envoyer la fenetre cible vers une autre stage disponible.
- **FR-010**: Le menu DOIT proposer une action pour envoyer la fenetre cible vers un autre desktop Roadie disponible.
- **FR-011**: Le menu DOIT proposer une action pour envoyer la fenetre cible vers un autre ecran disponible.
- **FR-012**: Le menu NE DOIT PAS proposer comme destination active la stage, le desktop ou l'ecran deja associe a la fenetre cible, sauf sous forme indisponible.
- **FR-013**: Le systeme DOIT echouer sans effet visible si la fenetre cible ou la destination choisie n'existe plus au moment de l'action.
- **FR-014**: Le systeme DOIT journaliser un resultat utilisateur ou diagnostic pour les actions reussies, ignorees et echouees.
- **FR-015**: Le comportement experimental NE DOIT PAS modifier les raccourcis, le drag-and-drop du navrail ou les menus contextuels internes des applications.

### Entités Clés

- **Réglages du menu contextuel de barre de titre** : Preferences experimentales controlant l'activation, la hauteur de detection, les marges d'exclusion et l'eligibilite des fenetres.
- **Action contextuelle de fenetre** : Action demandee depuis le menu pour une fenetre cible, avec un type de destination : stage, desktop ou ecran.
- **Destination de fenetre** : Destination utilisateur visible et valide pour la fenetre cible, excluant le contexte courant quand il n'y a rien a changer.

## Critères de Succès *(obligatoire)*

### Résultats Mesurables

- **SC-001**: Avec l'option activee, un clic droit dans la zone eligible d'une fenetre geree affiche le menu Roadie dans au moins 95% des essais sur les fenetres standard testees.
- **SC-002**: Avec l'option activee, un clic droit dans le contenu de l'application ne declenche pas le menu Roadie dans 100% des essais de validation.
- **SC-003**: Avec l'option desactivee, Roadie n'affiche jamais le menu experimental lors des essais de clic droit.
- **SC-004**: Un utilisateur peut envoyer une fenetre vers une autre stage, un autre desktop ou un autre ecran en trois interactions maximum apres le clic droit initial.
- **SC-005**: Les actions vers une destination indisponible ou disparue ne causent aucune perte de fenetre et laissent la fenetre dans son contexte d'origine.
- **SC-006**: Les parametres experimentaux peuvent etre changes puis pris en compte sans redemarrer toute la session utilisateur.

## Hypothèses

- La premiere version utilise une detection heuristique de la barre de titre, car toutes les applications ne representent pas cette zone de la meme maniere.
- La fonctionnalite est reservee aux fenetres que Roadie considere gerables afin d'eviter les popups, palettes et dialogues systeme.
- Les destinations proposees suivent les stages, desktops et ecrans deja connus par Roadie.
- La configuration experimentale expose au minimum : activation, hauteur de detection, marge gauche, marge droite et restriction aux fenetres gerees.
- Les libelles du menu peuvent etre simples dans la premiere version, tant que les destinations sont clairement distinguables pour l'utilisateur.
