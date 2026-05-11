# Recherche : Pins de Fenêtres

## Décision 1 : état de pin persistant dans `PersistentStageState`

**Décision** : ajouter les pins de fenêtres à l'état persistant des stages/desktops/displays existant, plutôt que créer un fichier ou store séparé.

**Justification** : un pin dépend directement du display, du desktop Roadie et de la fenêtre suivie. `PersistentStageState` est déjà l'autorité pour l'appartenance des fenêtres, les desktops courants, les stages actives et le nettoyage des fenêtres absentes. Centraliser l'état évite les divergences entre plusieurs fichiers.

**Alternatives étudiées** :

- Store séparé `window-pins.json` : rejeté, car il faudrait synchroniser deux sources de vérité lors des assignations, suppressions, migrations display et cleanup.
- Dupliquer la fenêtre dans chaque stage : rejeté, car cela casserait les invariants existants et relancerait des problèmes de focus/layout.

## Décision 2 : pin comme visibilité transverse, pas comme membership multiple

**Décision** : une fenêtre pinée conserve un contexte d'origine unique, mais possède un `Pin Scope` qui autorise sa visibilité dans d'autres contextes.

**Justification** : Roadie a besoin de savoir d'où vient la fenêtre pour nettoyer, retirer le pin et revenir à un comportement normal. En revanche, la visibilité pinée ne doit pas modifier l'arbre de layout, ni créer plusieurs propriétaires pour la même fenêtre.

**Alternatives étudiées** :

- Déplacer la fenêtre vers la stage active à chaque switch : rejeté, car cela rendrait l'historique et le retrait du pin imprévisibles.
- Créer une stage spéciale "pinned" : rejeté, car cela expose un concept technique à l'utilisateur et complique les raccourcis de stage.

## Décision 3 : scopes supportés limités à `desktop` et `all_desktops`

**Décision** : supporter deux scopes : toutes les stages du desktop courant, et tous les desktops Roadie du même display.

**Justification** : cela correspond exactement au besoin exprimé. Le scope display-crossing est volontairement exclu pour cette version, car le déplacement vers un autre écran existe déjà et implique une autre logique de géométrie.

**Alternatives étudiées** :

- Pin global sur tous les displays : rejeté pour cette version, car une fenêtre macOS n'existe physiquement que sur un écran à la fois; la "visibilité globale" impliquerait soit un déplacement automatique, soit un comportement surprenant.
- Pin par stage nommée : rejeté, car le besoin est de traverser les stages, pas de créer une règle de routage.

## Décision 4 : exclusion du layout sans perdre le suivi Roadie

**Décision** : une fenêtre pinée doit rester suivie par Roadie, mais ne doit pas contribuer au `RoadieState.stage.windowIDs` utilisé par `ApplyPlan`.

**Justification** : l'utilisateur veut une fenêtre qui flotte de manière stable au-dessus des contextes. Si elle reste dans le layout automatique, chaque changement de stage/desktop peut provoquer une réorganisation des autres fenêtres.

**Alternatives étudiées** :

- Mettre `isTileCandidate = false` globalement : risqué, car ce champ sert aussi à d'autres filtres et peut affecter bordures, focus et diagnostics au-delà du pin.
- Ajouter un filtre uniquement dans `ApplyPlan` : nécessaire mais insuffisant si `hideInactiveStageWindows` continue à cacher la fenêtre.

## Décision 5 : actions depuis le menu de barre de titre existant

**Décision** : ajouter les actions de pin/unpin dans le menu Roadie existant de barre de titre, sous une section dédiée à la fenêtre.

**Justification** : le menu sait déjà identifier une fenêtre éligible sans interférer avec le contenu applicatif. Réutiliser ce point d'entrée évite un nouveau mécanisme souris ou clavier.

**Alternatives étudiées** :

- Ajouter immédiatement des commandes CLI : utile pour les tests ou l'automatisation, mais non nécessaire pour la première valeur utilisateur.
- Ajouter une interaction dans le navrail : rejeté pour cette feature, car le pin concerne une fenêtre précise et non une stage.

## Décision 6 : nettoyage opportuniste des pins orphelins

**Décision** : nettoyer automatiquement un pin quand la fenêtre n'est plus présente dans les fenêtres live suivies par Roadie.

**Justification** : les fenêtres macOS ont des IDs temporaires. Un pin orphelin ne doit pas rester actif ni réapparaître sur une mauvaise fenêtre.

**Alternatives étudiées** :

- Conserver les pins par signature stable app/titre/frame : rejeté pour cette version, car cela pourrait pinner une nouvelle fenêtre par erreur après relance d'application.
- Exiger un unpin manuel : rejeté, car l'utilisateur ne peut pas retirer un pin d'une fenêtre fermée.
