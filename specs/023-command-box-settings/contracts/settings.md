# Contrat : réglages (`/set`, `/settings`, fenêtre)

## Nom d'un réglage

`table.clé`, où `table` est le chemin de la table TOML sans le préfixe `experimental.` ni `fx.`, et `clé` la clé du fichier. Le nom est unique : deux clés de même nom dans des tables différentes ont des noms différents (`target_mode.enabled`, `app_targets.enabled`, `rail.header.display.font_size`, `rail.stage_labels.font_size`). La catégorie de la fenêtre est une donnée séparée : elle sert à regrouper, pas à nommer.

Exemples : `target_grid.rows`, `target_mode.label_font_size`, `target_grid.label_font_size`, `rail.width`, `target_mode.search_hotkey`, `borders.active_color`, `tiling.gaps_outer`.

Complétion : après `/set `, Tab propose les noms qui commencent par la saisie, ou qui contiennent un de ses mots.

## Catégories (pour `/settings` et la fenêtre)

| Identifiant de catégorie | Libellé | Contenu |
|---|---|---|
| `general` | Général | pas de réglage : chemin du fichier, état de validité ; actions Ouvrir, Recharger, Diagnostic |
| `tuilage` | Tuilage | `tiling`, `window_placement`, `width_adjustment` |
| `stages` | Stages et bureaux | `stage_manager.default_stage` |
| `lettres` | Mode lettres | `experimental.target_mode` (sauf `search_hotkey`), `experimental.app_targets` |
| `grille` | Grille | `experimental.target_grid` |
| `recherche` | Recherche | `experimental.target_mode.search_hotkey` |
| `rail` | Rail | `fx.rail` et ses sous-tables |
| `bordures` | Bordures | `fx.borders` |
| `focus` | Focus et souris | `focus` |
| `regles` | Règles | lecture seule : règles, exclusions |
| `avance` | Avancé | `experimental.target_record`, `experimental.titlebar_context_menu`, listes et tableaux de tables en lecture seule |


## `/set`

| Saisie | Effet |
|---|---|
| `/set nom` | affiche « nom = valeur (défaut D, de A à B) » ou « (défaut D, choix : a, b, c) » |
| `/set nom valeur` | valide, écrit, applique ; affiche « nom = valeur » |
| `/set nom défaut` | rétablit la valeur par défaut |
| `/set` | affiche la liste des catégories |

Règles de conversion :
- Booléen : `true`, `false`, `oui`, `non`, `on`, `off`, `1`, `0`.
- Nombre : point ou virgule décimale ; refus hors de la plage ; refus d'un entier non entier.
- Choix : une valeur de la liste ; sinon refus avec la liste.
- Couleur : `#RRGGBB` ou `#RRGGBBAA`.
- Texte : la fin de la saisie, sans les espaces de bord.
- Liste ou tableau de tables : refus avec « lecture seule : modifier le fichier de configuration ».

Refus : le fichier reste intact, la boîte affiche la cause (plage, liste de choix, erreur de validation du fichier).

## `/settings`

- `/settings` : ouvre la fenêtre sur la dernière catégorie vue (Général à la première ouverture).
- `/settings catégorie` : ouvre sur cette catégorie (id sans accent, ou libellé, insensible à la casse).
- Catégorie inconnue : erreur avec la liste.

## Fenêtre

- Titre : « Réglages Roadie ». Minimum 760×520, redimensionnable.
- Colonne gauche (220 pt) : zone de recherche (placeholder « Rechercher »), puis les catégories avec une icône système (SF Symbols), la catégorie active en surbrillance.
- Zone droite : titre de la catégorie, puis les réglages en cartes : libellé, description, contrôle à droite, bouton « Rétablir » discret quand la valeur diffère du défaut.
- Contrôles : interrupteur (booléen), pas à pas + champ (entier, flottant, avec plage), liste déroulante (choix), champ texte (texte), sélecteur de couleur + champ hexadécimal (couleur).
- Recherche : à partir de 1 caractère, la zone droite montre les réglages de toutes les catégories dont le nom, le libellé ou la description contient la saisie, groupés par catégorie. Vider la recherche revient à la catégorie.
- Changement de valeur : appliqué à la validation du champ (Retour ou perte de focus), tout de suite pour un interrupteur ou une liste. Refus : le champ reprend l'ancienne valeur et une ligne rouge sous le réglage donne la cause.
- Fichier invalide : bandeau en haut « Le fichier de configuration est invalide » avec les erreurs et le bouton « Ouvrir le fichier » ; les contrôles sont désactivés.
- Suivi du fichier : un changement externe recharge les valeurs affichées sans perdre la catégorie ni la recherche en cours.
- Fermeture : Échap (hors édition d'un champ), Cmd + W, bouton de fermeture.
- Général : chemin du fichier, état (valide ou N erreurs, M avertissements), boutons « Ouvrir le fichier de configuration », « Recharger », « Diagnostic » (affiche le résultat de `doctor` dans une zone de texte).
- Règles et listes : lecture seule, avec le bouton « Ouvrir le fichier de configuration » (Finder ouvre le fichier avec l'application par défaut).

## Fichier de configuration

- Une modification ne change que la ligne de la clé ; la ligne garde son indentation et son commentaire de fin de ligne.
- Une clé absente est insérée à la fin de sa table ; une table absente est ajoutée à la fin du fichier.
- Première écriture de la session : copie `roadies.toml.bak-<horodatage>` dans le même dossier.
- Écriture atomique ; le texte résultat est validé avant écriture.
