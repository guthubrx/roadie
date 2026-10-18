# Changelog

Changements livrés dans chaque version. Les notes de release précisent la mise à
jour et les limites connues ; les README décrivent la version courante.

## Non publié

### Nouveautés

- Poignées dans les séparations de l'arbre persistant pour ajuster les proportions
  à la souris, activables dans Tuilage sans changer la disposition.
- Aperçu du réordonnancement dans le rail : la stage déplacée apparaît en transparence
  à sa future place, et les cartes voisines montrent l’ordre qui sera appliqué au dépôt.
  Une aimantation réglable dans les paramètres stabilise la destination.

### Corrections

- Affichage des poignées conservé avec les bordures JankyBorders, avec un repère
  plus lisible et un interrupteur immédiat dans Tuilage.
- Conservation des gestes récents face aux anciens refus de taille ; minimums appris
  liés au processus, à la stage et au mode de la fenêtre.
- Reconnaissance des notifications de placement arrivées en retard, avec un historique
  borné et priorité aux gestes de souris.
- Acquisition des relevés du rail, des bordures et du focus souris en arrière-plan,
  avec regroupement des demandes et rejet des données invalidées.
- Réduction du travail répété dans le rail, la recherche, les arbres de tuilage
  et les lectures macOS de secours, sans changer les réglages ni les dispositions.

- Rafraîchissement de l'indicateur d'enregistrement limité aux changements de son propre fichier.
- Rappel d'un stage poursuivi sur les autres fenêtres si la cible préférée est introuvable,
  avec exclusion des fermetures confirmées et restauration des fenêtres réduites.
- Identification des fenêtres dont le masquage ou la restauration échoue dans les journaux.

- Conservation des redimensionnements lorsque la lecture des fenêtres macOS est lente.
- Clics et glissements du rail, et menu de fenêtre, fondés sur la position enregistrée
  du geste même lorsque son traitement est retardé.
- Réduction des lectures répétées des fenêtres et de leurs panneaux attachés.
- Diagnostic `daemon health` exécuté avec les permissions du service Roadie.
- Ordre cohérent entre le rail, les menus de destination et les commandes par position.
- Retour des stages à leur place après reconnexion d'un écran, en conservant les
  modifications et les déplacements explicites effectués entre-temps.
- Reprises bornées après un refus de restauration ou de masquage d'une fenêtre.
- Recherche des libellés de contrôles natifs portés par leurs enfants, notamment
  les dossiers Outlook, avec moins de lectures inutiles des éléments hors fenêtre.
- Fermeture de la barre de recherche et de commandes au clic extérieur, sans
  bloquer le clic dans l’application ni déclencher un Retour encore en attente.

## 0.5.0 — 2026-10-14

### Nouveautés

- **Réglages immédiats** : les valeurs valides s'appliquent pendant la saisie.
  Les marges et espacements déclenchent le retuilage sans validation par Retour.
- **Éditeurs intégrés** : listes, stages, règles et exceptions par écran ou par
  stage se modifient dans la fenêtre. Un éditeur avancé traite les structures
  complexes et permet de réparer une configuration invalide.
- **Typographie personnalisable** : tailles indépendantes pour les paramètres,
  le rail, les lettres, la grille et la recherche. La barre propose aussi des familles
  distinctes pour la saisie et les suggestions, mises à jour dans la barre ouverte.
- **Complétion par Tab** dans la barre de recherche et de commandes : insertion du résultat ou de la suggestion
  sélectionnée, puis parcours des alternatives en mode commande.

### Améliorations et corrections

- Paramètres plus lisibles, modes de tuilage nommés en français et valeur héritée
  `balanced` correctement affichée.
- Barre de recherche et de commandes fixe, bordure fine et compteur compact ; la loupe est retirée.
- Mise à jour des noms de stages dans le rail, sans modifier les noms personnels
  des autres stages ni leurs fenêtres.
- Protection contre l'écrasement d'un changement externe à la sortie d'un champ,
  validation des règles avant écriture et application précise des écarts d'un point.
- Reprises bornées du tuilage, suspendues pendant un zoom ou sur un stage vide.

[Notes françaises](docs/releases/v0.5.0.md) ·
[English release notes](docs/releases/v0.5.0.en.md) ·
[Comparaison depuis 0.4.0](https://github.com/guthubrx/roadie/compare/v0.4.0...v0.5.0)

## 0.4.0 — 2026-10-14

### Nouveautés

- Recherche au clavier dans les fenêtres visibles, avec résultats progressifs.
- Boîte de commandes : suggestions, historique, stages, écrans, signets et diagnostics.
- Fenêtre de paramètres avec catégories, recherche et rétablissement ; commandes
  `/settings` et `/set`. Dans cette version, les listes restent en lecture seule.
- Taille des étiquettes réglable et maximisation réservant la place du navrail.
- Installation sous forme de `Roadie.app` et commandes exécutées par le daemon.

### Tuilage et fiabilité

- Arbre spatial persistant, tuilage réactif et glisser-déposer plus cohérent entre
  stages et écrans ; prise en compte des tailles minimales et de `master_ratio`.
- État enregistré de façon atomique, configuration validée au rechargement et
  restauration des fenêtres masquées après arrêt ou disparition du daemon.
- Corrections du parking des écrans, des transferts, du focus, des cibles, de la
  grille et des macros. Journaux et abonnements fiabilisés, avec signal `events.gap`.
- Installation et redémarrage conservant le certificat disponible ; arrêt des
  composants avant désinstallation et indicateurs de rail et de groupe corrigés.
- Trois parcours coûteux optimisés : appartenances, validation des dispositions
  et rapprochement géométrique. [Mesures et périmètre de validation](audits/2026-10-14/release-performance-024/report.md).

### Migration depuis 0.3.0

- `mutableBsp` et `yabai` deviennent des alias de `spatialBsp`. La migration des
  stages conserve une sauvegarde `stages.json.pre-017`.
- En mode arbre, utiliser `warp` à la place de `layout insert` ou `layout join-with`,
  et `resize` à la place de `layout width`. `layout flatten` équilibre l'arbre existant.
- Les clics vides du rail sont inertes par défaut ; `empty_click_hide_active`
  permet de retrouver l'ancien comportement.
- Vérifier les codes de sortie non nuls dans les scripts. La restauration de
  sécurité est intégrée à `roadied run` et `roadied tiler` ; `restore-safety` ne lance plus de processus.

Validation de cette version : **1 354 tests Swift et 26 tests des scripts**.
Le contrôle ciblé clôture trois constats élevés ; six moyens et six faibles restent ouverts.

[Notes françaises](docs/releases/v0.4.0.md) ·
[English release notes](docs/releases/v0.4.0.en.md) ·
[Comparaison depuis 0.3.0](https://github.com/guthubrx/roadie/compare/v0.3.0...v0.4.0)

## 0.3.0 — 2026-05-25

Runtime modulaire, BSP mutable persistant et premières stabilisations du glisser-déposer.

[Notes archivées](docs/releases/v0.3.0.md) ·
[Release et téléchargement](https://github.com/guthubrx/roadie/releases/tag/v0.3.0)

Les versions antérieures restent disponibles dans
[l'historique des releases](https://github.com/guthubrx/roadie/releases).
