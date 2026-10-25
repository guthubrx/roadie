# Changelog

Changements livrés dans chaque version. Les notes de release précisent la mise à
jour et les limites connues ; les README décrivent la version courante.

## Non publié

### Nouveautés

- Réordonnancement des bureaux dans la vue d’ensemble : glisser la puce d’un bureau
  entre deux autres bureaux du même écran, ou avant le premier, l’insère à cette
  place et renumérote les bureaux comme dans Mission Control.
  Stages, fenêtres, nom, épinglages et historique suivent le bureau ; aucune fenêtre
  ne bouge. Même opération en CLI : `roadie desktop move N POSITION`.

### Corrections

- Le sélecteur et la vue d’ensemble ne proposent plus une fenêtre fermée que son
  application garde en mémoire sans l’afficher (par exemple les réglages d’AlDente).
  Son choix affichait « Action refusée par l’application ».

## 0.8.0 - 2026-10-24

### Nouveautés

- Vue d’ensemble des écrans, bureaux et stages, sur une seule page et sans
  défilement : Archipel (écrans en colonnes) ou Baies (écrans en bandes), une
  grille de cartes de même taille par bureau, au format 16:10, avec la stage de
  chaque fenêtre en puce. Fond d’écran de l’utilisateur flouté (0–100 %, défaut
  20 %, aperçu en direct dans les paramètres). Loupe qui agrandit le bureau survolé
  de 100 à 250 %. Contour de sélection réglable (couleur, 1–8 points), au départ
  sur la fenêtre active. Captures à la définition des cartes, gardées nettes
  10 minutes pour une réouverture immédiate. CLI `overview show|toggle|hide|status`
  et raccourci interne facultatif ; réglages dans Paramètres > Vue d’ensemble.

- Cinq organisations du sélecteur au choix : colonnes par stage, bureaux en onglets,
  navigation hiérarchique, grille par sections et vue d'ensemble des bureaux.
  Réglage commun ou propre à chaque profil, appliqué sans redémarrage. La grille
  classique, les raccourcis et le comportement au relâchement sont conservés.

### Corrections

- Les fenêtres des stages masquées ne rétrécissent plus après Mission Control. Roadie
  suspend la disposition et la mémorisation des cadres pendant Mission Control, gare
  les fenêtres sans toucher leur taille et reprend une écriture restée sans réponse
  de l’application au lieu d’accepter l’ancienne taille.
- Le sélecteur et la vue d’ensemble partent de la fenêtre au premier plan selon macOS,
  et non de la fenêtre retenue par la stage active du premier écran.
- Captures des fenêtres justes sur les écrans à 1 pixel par point : la fenêtre est mise
  à l’échelle au lieu d’occuper un coin de l’image ; captures d’un lot en parallèle.
- `roadie desktop focus next|prev|last|back|back-and-forth`, documenté dans l’aide et les
  README, est accepté au même titre que `roadie desktop next|prev…` ; l’aide liste les deux formes.
- Présentations du sélecteur rapprochées des maquettes : panneau adapté à l’écran,
  vignettes groupées compactes, icônes et titres sans contexte répété, détail
  avec chemin bureau/stage et aperçu intégral. Largeur des colonnes répartie
  selon leur contenu et cartes spatiales remplies sur toute leur hauteur.
  En mode automatique, recherche d'une disposition sur une page, avec bureaux
  répartis en colonnes si nécessaire et police conservée.

## 0.7.0 - 2026-10-23

### Nouveautés

- Sélecteur de fenêtres intégré aux bureaux, stages et écrans Roadie : recherche,
  navigation aux flèches ou à la souris, grille avec grand aperçu et présentations
  en vignettes, icônes ou liste. La fenêtre choisie retrouve son contexte d'origine.
- Jusqu'à neuf profils : portée, tri, filtres, apparence et comportement au
  relâchement. Raccourcis enregistrés au clavier, gérés par Roadie ou BetterTouchTool ;
  commandes CLI disponibles pour les outils externes, dont Karabiner.
- Plein écran Roadie sans rail, même au survol, sans utiliser le plein écran natif
  macOS. Répéter `roadie toggle fullscreen` restaure la disposition précédente.

### Changements

- Paramètres regroupés par usage, formulaires compacts et alignés, règles
  repliables, onglets pleine largeur et aides défilables. Les contrôles suivent
  la taille de texte choisie, y compris dans une fenêtre étroite.

### Corrections

- Navigation du sélecteur avec les modificateurs maintenus, restauration des
  fenêtres réduites, filtres d'état et actualisation après un échec d'activation.
- Vérification et retour arrière des liaisons BetterTouchTool pour éviter les
  doubles déclenchements lors d'un changement de gestionnaire.

Aucun raccourci global d'ouverture du sélecteur n'est réservé par défaut.
La configuration et les liaisons existantes sont conservées.

[Notes françaises](docs/releases/v0.7.0.md) ·
[English release notes](docs/releases/v0.7.0.en.md) ·
[Comparaison depuis 0.6.0](https://github.com/guthubrx/roadie/compare/v0.6.0...v0.7.0)

## 0.6.0 - 2026-10-21

### Nouveautés

- Poignées réglables entre les groupes du tuilage persistant pour ajuster les
  proportions à la souris, en complément des bords natifs des fenêtres.
- Aperçu des futures positions lors du réordonnancement des stages, avec
  aimantation réglable dans les paramètres du rail.
- Mode flottant pour une fenêtre de la stage courante, via le menu Fenêtre ou
  `roadie toggle floating` ; la même action la remet au tuilage.
- Diagnostic de santé des réglages macOS qui peuvent gêner le tuilage. La
  maximisation Roadie par double-clic de titre est optionnelle, désactivée par défaut.

### Changements

- Les nouvelles fenêtres rejoignent par défaut la stage de l'écran actif Roadie.
  Cette valeur remplace le placement macOS lorsque la préférence est absente ou
  invalide ; les choix explicites `mouse` et `macos` sont conservés.
- Le rail conserve l'ordre choisi et défile dans la zone utilisable de l'écran.
  Sur une carte, le dépôt ajoute la fenêtre à cette stage. En haut, entre deux
  cartes ou en bas, il crée une stage à cet endroit, y compris entre écrans.
- Les stages nommées vides gardent un contour, leur nom et la mention « Vide »
  après le fondu des libellés. Les cartes restent fixes pendant les dépôts.
- Réutilisation des relevés et des cartes : demandes regroupées hors du fil principal pour les
  lecteurs visuels, vignettes mises à jour sans recréer les cartes, caches et
  parcours de recherche et d'arbre de tuilage simplifiés.

### Corrections

- Gestes de redimensionnement conservés malgré les lectures macOS lentes,
  réponses retardées, refus de taille et bordures décoratives JankyBorders.
- Ordre et destinations cohérents entre rail, menus et commandes par position ;
  fermetures confirmées retirées du rail sans attendre la grâce d'absence temporaire.
- Récupération des fenêtres au démarrage sans leur écran d'origine et retour des
  stages à la reconnexion. Réutilisation des emplacements vides compatibles,
  sans fusionner les homonymes ambigus ni remplacer la stage active.
- Édition native macOS dans la barre de recherche et de commandes, sélection des
  suggestions au clavier ou au clic, et fermeture au clic extérieur sans le bloquer.
- Recherche des libellés natifs portés par les enfants, notamment les dossiers Outlook.
- Rappel poursuivi sur les autres fenêtres si la cible préférée manque ; fenêtres
  réduites restaurées avant le focus. Reprises de placement et restauration bornées.

[Notes françaises](docs/releases/v0.6.0.md) ·
[English release notes](docs/releases/v0.6.0.en.md) ·
[Comparaison depuis 0.5.0](https://github.com/guthubrx/roadie/compare/v0.5.0...v0.6.0)

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
