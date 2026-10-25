# Spécification 077 - Fichiers dans le lanceur, un fichier ouvert mène à sa fenêtre

Demande du 25 octobre 2026 (`/my.specify-all 075 a 082`) : priorité 1 de la référence Alfred
(fichiers et dossiers dans la même liste, recherche rapide, Montrer dans le Finder) et idée C
du cadrage (un fichier déjà ouvert mène à sa fenêtre, sinon il s'ouvre dans la stage où l'on
travaille avec son dossier), avec Quick Look et ⌘C (priorité 2).

## Demande reformulée
Taper le nom d'un fichier ou d'un dossier dans Capslock + F le trouve, avec son icône et son
emplacement. Retour va à la fenêtre qui l'affiche déjà, dans sa stage ; sinon l'ouvre dans la
stage où l'on ouvre d'habitude les fichiers de ce dossier, ou dans la stage active. Une espace en
tête ne cherche que des fichiers. Les verbes ajoutent : ouvrir dans une stage, amener ici,
montrer dans le Finder, aperçu, copier le chemin.

## Dépendances
SPEC-073 à 076 (lanceur, verbes, variantes, mémoire par stage), F5 (intention de placement).

## Exigences
- **FR-001 Recherche.** À partir de 3 caractères (2 avec l'espace en tête), Spotlight cherche
  dans le dossier personnel, hors `~/Library`, les dossiers, documents, textes, images, PDF,
  tableurs et présentations dont le nom contient la saisie. 40 réponses au plus, les plus
  récemment utilisées d'abord, puis classées comme les autres lignes. Section « Fichiers » (5
  lignes) après « Fenêtres ». Les frappes rapides annulent la recherche précédente.
- **FR-002 Recherche rapide.** Une espace ou une apostrophe en tête : seulement des fichiers.
- **FR-003 Ligne.** Icône du fichier, nom, dossier abrégé en `~`.
- **FR-004 Ouvrir.** Retour : fenêtre qui affiche déjà ce fichier (document lu par
  l'accessibilité) → Roadie y va ; sinon le fichier s'ouvre avec son application par défaut, et
  sa nouvelle fenêtre rejoint la stage la plus utilisée pour son dossier (ou un dossier parent,
  trois niveaux au plus), sinon la stage active ; Roadie y va.
- **FR-005 Verbes.** Ouvrir, Ouvrir dans…, Amener ici, Montrer dans le Finder, Aperçu (Quick
  Look), Copier le chemin. Variantes : ⌘ nouvelle stage, ⌥ amener ici, ⌃ web.
- **FR-006 ⌘C.** Sans texte sélectionné dans le champ, ⌘C copie la ligne choisie : chemin
  d'un fichier ou d'une application, titre d'une fenêtre. La ligne l'indique.
- **FR-007 ⌘Y.** Aperçu Quick Look du fichier choisi.
- **FR-008 Commande.** `roadie launch CHEMIN [--stage NOM | --new-stage]` ouvre un fichier, un
  dossier ou une application comme Retour dans la barre.
- **FR-009 Applications.** Le catalogue lit aussi `/System/Library/CoreServices/Applications`
  et `/Applications/Xcode.app/Contents/Applications`.

## Critères de réussite
- `roadie launch /tmp/roadie-077/essai.txt` deux fois : une seule fenêtre TextEdit, la seconde
  commande la met devant.
- Aucun chemin de fichier dans le journal : seuls les identifiants d'application et le résultat.
- Liste mise à jour en moins de 50 ms par frappe ; les réponses de Spotlight arrivent ensuite.

## Hors périmètre
Navigation dans les dossiers, recherche dans le contenu (`in`), étiquettes (`tags`) ; onglets
de navigateur (082).
