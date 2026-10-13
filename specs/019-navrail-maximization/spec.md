# Spécification : Maximisation en laissant la place au navrail

**Branche** : `019-navrail-maximization`  
**Création** : 2026-10-12  
**Statut** : Implémentée
**Demande** : Maximisation en laissant la place au navrail.

## Scénarios utilisateur et tests

### US1 — Agrandir puis retrouver la disposition (P1)

Je veux utiliser toute la zone disponible à côté du navrail pour une fenêtre. Je veux retrouver mes fenêtres et mes proportions avec la même action.

**Test indépendant** : partir de quatre fenêtres en quarts, maximiser l'une, puis désactiver la maximisation.

1. Étant donné plusieurs fenêtres dans une stage, quand je maximise une fenêtre, alors elle occupe toute la zone utile lorsque le rail est masqué, ou la zone à droite du rail visible et les voisines de cette stage sont cachées.
2. Étant donné cette maximisation, quand je répète l'action sur cette fenêtre, alors la disposition précédente revient, avec son ordre et ses proportions.
3. Étant donné une fenêtre seule, quand je maximise puis répète l'action, alors la bascule reste explicite et fonctionne.

### US2 — Garder le rail accessible (P1)

**Test indépendant** : maximiser avec le rail permanent puis avec son masquage automatique.

1. Quand le rail est visible, la fenêtre maximisée ne couvre pas sa bande.
2. Quand le rail se masque, la fenêtre occupe exactement la zone utile comme en plein écran Roadie. Quand le rail revient (survol ou pin), la fenêtre se redimensionne à côté du rail. Les réglages de masquage et d'épinglage ne changent pas.
3. Quand la largeur configurée du rail ou la zone utile de l'écran change, le cadre maximisé est recalculé.

### US3 — Choisir le mode et la fenêtre (P2)

**Test indépendant** : alterner maximisation réservée et plein écran Roadie ; cibler une fenêtre depuis son menu de titre.

1. Quand je passe de la maximisation au plein écran Roadie, la fenêtre utilise toute la zone utile. La commande inverse suit la visibilité du rail sans perdre la disposition à restaurer.
2. Quand je choisis l'action dans le menu d'une fenêtre, cette fenêtre est ciblée même si une autre avait le focus.
3. Quand je change de stage puis reviens, la maximisation réservée reste active.

### Cas limites

- Plusieurs écrans, y compris avec origine négative : seul le scope ciblé est modifié.
- Fenêtre en plein écran natif ou non redimensionnable : échec expliqué, sans cacher les voisines ni enregistrer un faux succès.
- Largeur minimale imposée par une application : si le cadre accepté recouvre le rail ou sort de la zone utile, abandonner la maximisation et tenter de rétablir le cadre initial.
- Fenêtre maximisée disparue : quitter le zoom et rendre ses voisines visibles, même en float sans focus. Une fenêtre ouverte pendant le zoom retrouve son cadre visible à la sortie. Écran absent ou zone disponible vide : aucune écriture de cadre invalide.
- Anciens états persistés : lecture inchangée, sans migration destructive.
- Modes à arbre, BSP classique, masterStack et float : restaurer par leur mécanisme actuel ; conserver les dispositions manuelles valides des modes sans arbre.

## Exigences

- **FR-001** : une action distincte active et désactive la maximisation réservée, avec ou sans voisines.
- **FR-002** : rail masqué, son cadre est celui du plein écran Roadie, sans marges ni bande de révélation réservée. Rail visible, il respecte la zone utile, les marges de fenêtre seule et la largeur complète du panneau.
- **FR-003** : quand le rail revient par survol ou pin, la fenêtre maximisée se redimensionne dans les modes resize et overlay, sans quitter le zoom ni perdre la disposition précédente. Pin réserve sa largeur immédiatement malgré une mesure périmée. Unpin ne libère la bande que lorsque le rail se replie. hide_on_maximized ne doit pas empêcher le retour du rail pour ce mode ; le plein écran natif reste prioritaire.
- **FR-004** : la sortie restaure l'ordre et les ratios des arbres persistants et la disposition manuelle valide des modes sans arbre. En float, elle restaure les cadres précédents des fenêtres toujours présentes.
- **FR-005** : les deux zooms Roadie peuvent se remplacer directement et gardent une seule disposition précédente. Le plein écran natif garde son comportement.
- **FR-006** : commandes, maintien, plans de disposition et retour de stage utilisent le même cadre réservé actualisé ; les autres scopes restent inchangés.
- **FR-007** : les refus et cadres incompatibles ne cachent pas les voisines et ne persistent pas la maximisation. Le résultat indique l'échec.
- **FR-008** : l'action est accessible par commande et par le menu de titre déjà configurable, avec cible explicite. L'aide et les documents anglais/français l'expliquent.
- **FR-009** : la persistance accepte les anciens états et conserve la maximisation au redémarrage.

### Entités

- Zoom de stage : fenêtre ciblée, mode avec ou sans réservation, disposition précédente, cadres acceptés.
- Zone utile d'écran : origine et dimensions visibles, marges, largeur du panneau de rail.

## Critères de succès

- **SC-001** : aucun recouvrement du panneau dans les scénarios automatisés de largeur, masquage et coordonnées d'écran.
- **SC-002** : les aller-retour et transitions des scénarios de disposition retrouvent les cadres ou les ratios initiaux, à la tolérance de cadre existante.
- **SC-003** : les scénarios de refus n'enregistrent aucun zoom et ne cachent aucune voisine.
- **SC-004** : la suite existante reste verte ; le service installé répond à ses contrôles de santé.

## Hypothèses et dépendances

- Nouvelle session après 017 ; dépend de 002 (CLI/menu), 016 (zoom/persistance) et 017 (arbre qui fait foi).
- La largeur du panneau est celle de sa configuration ; le contenu des cartes ne définit pas une autre surface de fenêtre.
- Le rail reste à gauche. Les marges de fenêtre seule existantes sont conservées lorsque le rail est visible. Elles sont supprimées lorsque le rail est masqué.
- Aucun changement automatique de raccourci externe, de permission ou de configuration de masquage.
