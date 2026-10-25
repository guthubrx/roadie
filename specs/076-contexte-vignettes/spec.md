# Spécification 076 - Classement selon la stage active et vignettes réelles

Demande du 25 octobre 2026 (`/my.specify-all 075 a 082`), idées A et B du cadrage « lanceur
propre à Roadie », validées par l'utilisateur.

## Demande reformulée
Le lanceur tient compte de l'endroit où l'on travaille : dans la stage « Com », `o` propose
d'abord ce que l'on y choisit d'habitude (Outlook) ; dans « Dev », autre chose (OrbStack). Les
fenêtres de la liste montrent leur vignette réelle, déjà capturée par Roadie, au lieu de
l'icône de leur application.

## Dépendances
SPEC-073 (classement appris), SPEC-016 et 056 (vignettes du rail et du sélecteur,
`RailThumbnailStore`), SPEC-074/075 (liste riche).

## Exigences
- **FR-001 Mémoire par stage.** Chaque choix est retenu aussi pour la stage active au moment du
  choix : abréviations tapées et fréquence-récence propres à cette stage, en plus de la mémoire
  globale. Une stage nommée est reconnue par son nom (unique, SPEC-067), une stage anonyme par
  sa place.
- **FR-002 Ordre.** Pour une même requête : choix appris dans cette stage, puis choix appris
  partout, puis requêtes plus longues, puis qualité de l'appariement, puis fréquence-récence
  dans cette stage, puis fréquence-récence globale. Une stage sans historique donne l'ordre
  actuel.
- **FR-003 Bornes.** Au plus 6 stages retenues par objet (les moins récentes partent). Le fichier
  `~/.roadies/launcher-ranking.json` reste lisible par l'ancienne version et inversement.
- **FR-004 Vignettes.** Une fenêtre de la liste montre sa dernière vignette nette (vue
  d'ensemble) ou sa vignette du rail, dans le carré de l'icône, aux proportions de la fenêtre,
  coins arrondis, avec l'icône de son application en pastille. Sans vignette : l'icône de
  l'application (076 ne lance aucune capture).

## Critères de réussite
- Test : après trois choix d'Outlook avec `o` dans « Com » et trois d'OrbStack avec `o` dans
  « Dev », `o` donne Outlook dans Com et OrbStack dans Dev.
- Un fichier de classement 073 se lit sans perte ; un fichier 076 se lit par le décodeur 073.
- La liste reste à jour en moins de 50 ms par frappe (aucune capture, lecture du cache seule).
- 1 983 tests existants réussis.

## Hors périmètre
Capture de nouvelles vignettes pour la liste ; contexte par bureau ou par écran.
