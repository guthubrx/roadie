# Spécification 099 - Présentation des résultats : liste, grille ou grandes tuiles

Demande du 27 octobre 2026. Point de départ : « j'avais pensé à émoji, il me les affiche en colonne et
moi je voudrais en grille, ou si j'explore un folder pour certains je pourrais vouloir en grille ».
Choix de l'utilisateur : mémoire par dossier ; aussi pour les fichiers de la recherche ; touche
réglable dans les Paramètres (⌘G par défaut, danger d'un raccourci global capté ailleurs) qui fait
défiler les présentations ; noms selon le contenu ; « un chip à droite pour changer la vue » ; « go ».

## Demande reformulée
Là où les résultats sont des objets visuels (lignes d'un workflow comme `emoji`, contenu d'un dossier
exploré, fichiers de la recherche), l'utilisateur choisit leur présentation : liste, grille ou grandes
tuiles. Une touche réglable (⌘G par défaut) et un chip cliquable à droite de la barre font passer à la
présentation suivante. Roadie retient le choix par workflow, par dossier, et pour les fichiers de la
recherche. Ailleurs, la liste reste la seule présentation.

## Exigences
- **FR-001 Sources.** Une seule entrée de workflow active (Script Filter, filtre de liste ou de
  fichiers) : source `wf:<entrée>`. Chemin tapé : source `path:<dossier>`. Recherche ordinaire avec des
  fichiers : source `files`. Aucune autre situation n'a de chip ni de bascule (grille d'un workflow de
  la 092 comprise : son auteur décide).
- **FR-002 Présentations.** Liste (actuelle), grille (7 colonnes) et grandes tuiles (4 colonnes) ; dans
  les deux dernières, les titres de section disparaissent ; pour la source `files`, seuls les fichiers
  restent (les applications et fenêtres reviennent en liste).
- **FR-003 Noms.** Workflow dont les lignes ne sont pas des fichiers (émojis) : nom de la tuile choisie
  en pied. Fichiers et dossiers : nom sous chaque tuile.
- **FR-004 Images.** En grille, un fichier image montre son contenu (vignette réduite) ; les autres
  fichiers leur icône.
- **FR-005 Touche.** Réglage `view_cycle_hotkey` (Paramètres > Recherche, enregistreur de raccourci),
  défaut `command+g`, vide : désactivée. La touche fait passer liste → grille → grandes tuiles → liste.
- **FR-006 Chip.** Quand une source existe, une icône à droite de la saisie (☰, ▦, ▣) montre la
  présentation ; un clic fait passer à la suivante.
- **FR-007 Mémoire.** Présentation retenue par source dans `~/.roadies/launcher-views.json` ; liste par
  défaut ; 500 sources au plus (les plus anciennes partent).
- **FR-008 Clavier.** En grille : ← → tuile voisine, ↑ ↓ rangée voisine (comme la 092), Tab et Retour
  inchangés.

## Critères de réussite
- SC-001 `emoji coeur` puis ⌘G : les émojis en grille, le nom de l'émoji choisi en pied ; rouvert plus
  tard, `emoji` revient en grille.
- SC-002 `~/Pictures/` puis clic sur le chip : les images en grille avec leur contenu ; un autre dossier
  reste en liste.
- SC-003 Tests : sources, cycle, mémoire bornée, résolution de la touche, filtrage des lignes, vignette.

## Hors périmètre
Grille pour applications, fenêtres, commandes, calcul, web ; forme des tuiles d'Alfred (`imageaspect`).
