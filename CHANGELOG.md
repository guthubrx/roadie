# Changelog

Ce journal décrit les changements visibles depuis la dernière release publiée.
Chaque entrée décrit la version correspondante. Les README présentent les sources courantes.

## À publier

### Corrections

- Réglages plus lisibles : textes et champs agrandis, fenêtre plus grande et
  explications au-dessus des contrôles. Les modes de tuilage portent des noms français.
- La valeur héritée `balanced` apparaît dans le menu de découpage de l'espace.
  Ouvrir les réglages conserve le fichier de configuration existant.
- Tailles de police indépendantes dans les paramètres, le rail, les lettres,
  la grille et la recherche. Curseurs et saisie valide appliquent les changements
  immédiatement ; les fenêtres et sessions déjà visibles sont redessinées.
- Barre Caps+F stable et sobre : largeur fixe bornée à l'écran, police proportionnelle,
  bordure fine, loupe retirée et compteur dans une pastille à droite.
- Tab complète le titre du résultat de recherche choisi sans cliquer. En mode
  commande, Tab accepte la suggestion sélectionnée avant de parcourir les alternatives.

## 0.4.0 — 2026-10-14

Comparaison : [v0.3.0 → sources intégrées](https://github.com/guthubrx/roadie/compare/v0.3.0...96c3d462).
180 commits pour les nouveautés intégrées jusqu’à `96c3d462`, puis les corrections de la session 024. La dernière release précédente date du 25 mai 2026.

### Ajouts

- Recherche au clavier dans toutes les fenêtres visibles. La barre s'ouvre immédiatement
  et reçoit les résultats au fil de la lecture des fenêtres. Les derniers résultats
  ont des étiquettes courtes et un cadre visible.
- Boîte de commandes dans cette même barre : un `/` initial donne accès à 21 commandes,
  aux suggestions et à l'historique des 50 dernières commandes réussies. Directions
  en français ou en anglais, stages par numéro ou nom, signets et réglages.
- Fenêtre de réglages avec catégories, recherche, changements immédiats et bouton
  de rétablissement. `/settings` l'ouvre ; `/set` lit, écrit ou rétablit un réglage.
  Les commentaires TOML sont conservés, une sauvegarde précède la première écriture
  de la session et les changements invalides sont refusés. Les listes restent en lecture seule.
- Taille des étiquettes réglable de 8 à 48 points pour les lettres, la recherche
  et la grille. Valeur par défaut : 13 points.
- Maximisation qui garde la bande du nav rail libre et suit son masquage automatique.
  Quitter le zoom restaure la disposition précédente. Le plein écran Roadie et le
  plein écran natif macOS restent des actions distinctes.
- Installation du daemon comme `Roadie.app`, visible sous ce nom dans les permissions
  macOS. Les commandes passent normalement par le socket du daemon et utilisent
  ses permissions, plutôt que celles du lanceur de raccourcis.

### Disposition et gestes

- L'arbre `spatialBsp` devient la référence persistante de la disposition. Les commandes,
  les changements de stage et les gestes utilisent cet arbre. Une absence temporaire
  ne supprime pas la place enregistrée de la fenêtre.
- Tuilage réactif piloté par les événements, regroupement des rafales de changements,
  suivi des gestes et limitation des écritures de cadres répétées.
- Glisser-déposer plus cohérent dans un stage et entre écrans : échange au centre,
  insertion sur un bord, aperçu sur l'écran sous le pointeur et prise en compte
  des tailles minimales imposées par les applications.
- `master_ratio` est transmis au moteur de disposition et pris en compte pour
  les nouvelles fenêtres en mode `masterStack`.
- Réduction des parcours répétés dans le BSP, les aperçus de groupes et les recherches
  de taille minimale. Ces changements ne constituent pas une mesure globale de latence.

### Fiabilité

- État enregistré de façon atomique sous verrou ; les échecs d'écriture remontent aux
  commandes. Les identifiants de fenêtre ou de stage invalides sont refusés proprement.
- Configuration rechargée dans le daemon actif ; une configuration invalide conserve
  la précédente. Les types invalides et les stratégies inconnues ne deviennent plus
  silencieusement des valeurs par défaut.
- Restauration des fenêtres masquées à l'arrêt et après disparition du daemon.
  Conservation des associations de fenêtres temporairement absentes, des signets
  et des actions des règles générées.
- Parking et retour des écrans, bureaux, transferts de stages, sélection de largeur,
  focus souris et dépôt dans le rail corrigés sur plusieurs cas limites.
- Activation des cibles affichées et revalidation des éléments d'application avant clic.
  La grille clique dans la case de l'écran effectivement sélectionné. Le replay
  des macros préserve davantage le contexte souris et relâche les appuis tronqués.
- Rotation des journaux et abonnements aux événements fiabilisés ; les ruptures du flux
  sont signalées par `events.gap`.
- Installation et redémarrage conservent le certificat exact quand il est disponible.
  La désinstallation arrête aussi les composants modulaires et les instances autonomes.
  Elle conserve les fichiers si un composant refuse de s'arrêter.
- Le rail distingue les fenêtres agrandies et celles en plein écran natif.
  L'indicateur de groupe est affiché sur la bordure de la fenêtre active.

### Migration depuis 0.3.0

- `mutableBsp` et `yabai` deviennent des alias de `spatialBsp`. Les anciens stages
  sont migrés une fois, avec sauvegarde `stages.json.pre-017`.
- En `spatialBsp`, remplace `layout insert` et `layout join-with` par `warp`, et
  `layout width` par `resize`. `layout flatten` équilibre l'arbre existant ; il ne
  le reconstruit pas depuis les positions des fenêtres.
- Les clics dans le vide du rail sont inertes par défaut. Pour retrouver le changement
  vers un stage vide, active `empty_click_hide_active` dans `[fx.rail]`.
- Les scripts doivent traiter les codes de sortie non nuls des commandes refusées.
  Un message contenant un nom utilisateur ne sert plus à déduire le statut d'échec.
- La restauration de sécurité tourne dans `roadied run` et `roadied tiler`.
  L'ancienne commande `roadied restore-safety` affiche un message puis sort.
- La recherche graphique et les réglages exigent un daemon démarré et
  `[experimental.target_mode].overlay_enabled = true`. Les clics dans les applications
  demandent aussi leurs activations explicites. La fenêtre de réglages est en français.

### Corrections finales de performance

La session 024 ferme les trois HIGH de l’audit précédent : construction groupée
des appartenances, validation unique par scope et index temporaire de rapprochement.
À 400 fenêtres, les microbenchmarks debug passent respectivement de 15,399 à 0,443 ms,
de 6 622,379 à 17,085 ms et de 117,742 à 16,076 ms pour les homonymes ambigus.
Les résultats restent identiques. Ces mesures ne décrivent pas la latence globale
de l’interface. Le pire cas géométrique est documenté.

### Vérification et limites connues

- **1 354 tests Swift dans 143 suites et 26 tests des scripts réussis** après correction.
- Revue indépendante favorable et [audit ciblé de clôture des trois HIGH](audits/2026-10-14/release-performance-024/report.md).
  Les six MEDIUM et six LOW du précédent audit restent ouverts.
- Binaires et application alignés sur 0.4.0. Construction et vérification du DMG
  consignées dans le dossier de release.
- Le packaging reste signé ad hoc, sans notarisation Apple. Le contrôle des Spaces
  natifs, `window close` et `toggle floating` ne font pas partie des fonctions livrées.

[Notes de release, en français et en anglais](docs/releases/v0.4.0.md).

## 0.3.0 — 2026-05-25

Runtime modulaire, BSP mutable persistant et premières stabilisations du glisser-déposer.

[Notes archivées](docs/releases/v0.3.0.md) ·
[Release publiée et DMG](https://github.com/guthubrx/roadie/releases/tag/v0.3.0).

Les releases antérieures sont conservées dans [l'historique des releases](https://github.com/guthubrx/roadie/releases).
