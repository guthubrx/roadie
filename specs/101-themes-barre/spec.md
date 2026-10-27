# Session 101 - Thèmes de la barre

## Demande

« Regarder les thèmes d'Alfred et faire la même chose. »

## Référence relevée

Alfred 5 livre ses thèmes sous forme de fichiers `.alfredappearance` (JSON) dans
`Alfred Framework.framework/Resources` : Alfred, Alfred Dark, Alfred Modern, Alfred Modern Dark,
Alfred macOS, Alfred macOS Dark, Frosty Teal, High Contrast Light, Large Avenir (Alfred Classic est vide).
Chaque thème décrit la fenêtre (couleur, contour, arrondi, flou, largeur), le champ de saisie (fond,
texte, police) et les résultats (sélection, titre, sous-titre, raccourcis, tailles). Les options d'Alfred
ajoutent un thème pour le mode sombre de macOS et le nombre de résultats montrés.

## Exigences

- FR-001 : réglage `theme` ; thèmes fournis : `roadie` (aspect actuel, défaut) et les neuf thèmes d'Alfred
  ci-dessus, avec leurs valeurs.
- FR-002 : un thème exporté d'Alfred (`.alfredappearance` ou `.json`) dans `~/.config/roadies/themes`, ou un
  thème personnel créé dans Alfred (`Alfred.alfredpreferences/themes/*/theme.json`), s'ajoute à la liste.
- FR-003 : `theme_dark` : thème quand macOS est en mode sombre ; vide = `theme`.
- FR-004 : un thème d'Alfred apporte couleurs, polices (`System Light`, Avenir…), tailles, arrondis,
  largeur, contour et flou (matière claire ou sombre derrière la barre et la liste). `roadie` garde les
  tailles et familles réglées dans Paramètres.
- FR-005 : `visible_results` : nombre de lignes de résultats montrées (0 : autant que la place, 3 à 20).
- FR-006 : le texte tapé et le curseur prennent la couleur du thème.
- FR-007 : Paramètres > Recherche propose les thèmes par leur nom.

## Hors périmètre

Éditeur visuel de thème (Alfred : cliquer et glisser sur l'aperçu) ; barre de défilement.
