# Spécification 092 - Vue Grille des workflows

Demande du 27 octobre 2026 (`/my.specify-all 092 093`). Demande initiale, après l'explication de la
vue Grille d'Alfred : « on n'a pas besoin de → car ça marche avec Tab pour les verbes » ; session
proposée : la barre affiche les briques Grille des workflows en tuiles.

## Demande reformulée
Quand un workflow atteint une brique Grille (`userinterface.grid`, Alfred 5.5), la barre Capslock + F
montre des tuiles au lieu de lignes : grande image, titre, sous-titre (sur la tuile ou en pied de
grille), au nombre de colonnes du workflow, même s'il est changé en cours de schéma par une brique
JSON. Les tuiles viennent d'un script lancé une fois, ou de ce que la brique reçoit (JSON d'un Script
Filter, ou liste de fichiers dont les images montrent leur contenu). ← → ↑ ↓ se déplacent dans la
grille, la frappe filtre (grille filtrable), Tab garde son rôle, Échap ferme ; Retour, avec ou sans
⌘ ⌥ ⌃ ⇧, envoie la tuile à la suite du workflow avec ses variables ; `preselect` choisit une tuile à
l'ouverture. Un déclencheur externe peut viser n'importe quelle brique qui le déclare
(`inboundconfig.externalid`, Alfred 5.5), ce qui permet à un workflow de rouvrir sa grille.

## Ce que cela apporte
Le workflow marche de bout en bout, pas seulement l'affichage : la surcharge du nombre de colonnes
par une brique JSON, les branches par modificateur et le retour par déclencheur externe sont
nécessaires à System Settings Explorer (installé chez l'utilisateur) et à Thumbnail Navigation
(corpus). Le déclencheur externe sur une brique quelconque sert aussi à 1Password, Alfred Gallery et
Shimmering Obsidian (corpus : 4 workflows).

## Mesure de départ
`roadie workflow list` : System Settings Explorer « inutilisable », manque `userinterface.grid`.
Corpus de 102 workflows (`/tmp/roadie-wf-corpus/mixed2`) : 2 grilles (System Settings Explorer,
Thumbnail Navigation) ; 4 objets déclarent `inboundconfig.externalid`.

## Dépendances
SPEC-088 (moteur, réponse des Script Filters, barre), SPEC-089 (déclencheurs externes, fiche),
SPEC-073/074 (barre riche, verbes par Tab), SPEC-091 (⌥ + flèches).

## Exigences
- **FR-001 Brique Grille.** Le moteur exécute `userinterface.grid` : il prépare les tuiles puis ouvre
  la barre en grille et s'arrête ; la suite part de la grille au Retour.
- **FR-002 Sources.** `inputtype` 1 : le script `inputfile` du dossier du workflow, lancé une fois avec
  l'argument et les variables ; sa sortie est un JSON de Script Filter. `inputtype` 0 : l'argument
  reçu, JSON de Script Filter s'il en est un, sinon une liste de chemins (un par argument ou par
  ligne). Autre source : brique manquante, nommée dans la fiche.
- **FR-003 Tuiles.** Colonnes `columncount` (1 à 12) ; titre si `showtitles`, sous-titre si
  `showsubtitles` ; `subtitlesinfooter` / `titlesinfooter` : affichés en pied de grille pour la tuile
  choisie au lieu de la tuile. Icône du JSON (image, icône d'un fichier) ; une image (`png`, `jpg`,
  `gif`, `heic`, `tiff`, `webp`) de la liste de fichiers montre son contenu, un autre fichier son
  icône. Tuile sans titre ni icône (espaceur d'Alfred) : vide, non choisie au clavier.
- **FR-004 Clavier et souris.** ← → : tuile voisine ; ↑ ↓ : même colonne, rangée voisine ; la grille
  défile pour garder la tuile choisie visible. Clic : choisit et ouvre. Tab : rôle actuel (complétion
  `autocomplete`, verbes d'un fichier). Échap ferme.
- **FR-005 Filtre.** `filterable` : la saisie filtre mot par mot, dans n'importe quel ordre (mode 2
  existant) ; sinon la saisie ne filtre pas. `fixedorder` : l'ordre du script (aucun classement appris).
- **FR-006 Retour.** Retour envoie l'`arg` de la tuile (le chemin pour un fichier) à la suite du
  schéma ; les variables du schéma au moment de la grille, de la réponse, de la tuile et du
  modificateur tenu s'ajoutent ; une flèche par modificateur est suivie comme ailleurs. Tuile
  `valid: false` : rien ne part.
- **FR-007 Présélection.** `preselect` du JSON : la tuile dont l'`uid` vaut ce texte est choisie à
  l'ouverture ; sinon la première tuile choisissable.
- **FR-008 Surcharge de configuration.** La clé `config` de la sortie d'une brique JSON (et d'un Run
  Script qui rend `alfredworkflow.config`) remplace les réglages de la brique suivante pour ce passage.
- **FR-009 Déclencheur externe sur une brique.** `roadie workflow trigger`, la sortie « Call External
  Trigger » et la fiche trouvent la brique dont `inboundconfig.externalid` vaut le nom, si aucun
  `trigger.external` ne le porte.
- **FR-010 Fiche.** `roadie workflow list` / `check` comptent la Grille comme gérée.

## Critères de réussite
- SC-001 : `sse`, Retour : les volets du niveau principal (56 tuiles mesurées, 107 toutes catégories), 7 colonnes (réglage « Icon Size » par
  défaut) ; Retour sur Wi-Fi ouvre le volet ; une catégorie ouvre sa seconde grille (essai utilisateur).
- SC-002 : Tests : grille par script et par liste de fichiers, colonnes surchargées, présélection,
  navigation à deux dimensions, Retour avec variables et modificateur, déclencheur `externalid`.
- SC-003 : System Settings Explorer n'est plus « inutilisable » ; corpus recompté avec
  `roadie workflow check` (aucune baisse).

## Hors périmètre
Vues Texte, Image et PDF ; aspect des images (`imageaspect`) au-delà d'un ajustement sans
déformation ; grille hors des workflows ; changement du rôle de → dans la liste habituelle.
