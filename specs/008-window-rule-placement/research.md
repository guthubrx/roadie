# Research: Placement des fenêtres par règle

## Decision: étendre `RuleAction`

**Choix**: Ajouter `assign_display` et `follow` à l'action de règle existante.

**Rationale**: Les règles supportent déjà `assign_stage` et `assign_desktop` côté modèle et événements. Ajouter le display au même endroit évite une seconde syntaxe et garde le TOML lisible.

**Alternatives considered**:
- Nouvelle section `[app_placement]` : rejetée, duplication du matching app/title/regex.
- Commande CLI uniquement : rejetée, ne répond pas au besoin "toujours ouvrir".

## Decision: résolution destination par ID puis nom

**Choix**: Résoudre l'écran par `DisplayID.rawValue`, puis par `DisplaySnapshot.name`. Résoudre la stage par ID, puis par nom persistant.

**Rationale**: L'ID est stable quand disponible, le nom est plus ergonomique pour l'utilisateur. Même logique pour stage : l'utilisateur pense souvent en nom visible, mais les raccourcis peuvent utiliser des ID.

**Alternatives considered**:
- Nom uniquement : fragile si deux écrans/stages ont le même nom.
- ID uniquement : trop peu ergonomique.

## Decision: application par le maintainer

**Choix**: Le `LayoutMaintainer` applique le placement après snapshot/rule evaluation, avant les relayouts habituels.

**Rationale**: Le maintainer est déjà la boucle qui observe les nouvelles fenêtres et applique les corrections de layout. Cela permet de garder la logique "une fois puis stabilité" au même endroit.

**Alternatives considered**:
- Appliquer directement dans `SnapshotService` : rejeté, snapshot doit rester principalement observation + état.
- Appliquer dans les commandes stage : rejeté, ce sont des actions utilisateur explicites, pas des règles automatiques.

## Decision: no-follow par défaut

**Choix**: `follow` vaut `false` par défaut.

**Rationale**: Le placement automatique ne doit pas voler le focus ni changer la stage visible de façon surprenante.

**Alternatives considered**:
- Follow implicite : rejeté, trop intrusif pour une app qui se lance en arrière-plan.
