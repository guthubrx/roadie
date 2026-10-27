# Validation 092

## Tests
- `Spec092GridTests` (11) : tuiles d'un JSON (présélection, espaceurs), d'une liste de chemins (image,
  icône de fichier), colonnes bornées, voisins à deux dimensions, brique Grille par script et par
  argument, surcharge `columncount` par une brique JSON, source inconnue signalée, déclencheur
  `externalid` sur une brique JSON, fiche, disposition (défilement par rangées, clic), ← → en grille.
- Suite complète : 2 097 tests / 293 suites réussis.

## Mesure (corpus de 102, `roadie workflow check /tmp/roadie-wf-corpus/mixed2`)
| | Avant (089-091) | Après |
|---|---|---|
| Complets | 79 (77 %) | 80 (78 %) |
| Avec une entrée complète | 92 (90 %) | 93 (91 %) |
System Settings Explorer : inutilisable → complet ; Thumbnail Navigation : inutilisable → partiel
(vues Texte, Image, PDF hors périmètre).

## Installation et essai réel
`make install`, `make restart` : PID 51522, santé 5/5, certificat `roadied-cert`.
`roadie workflow run com.firefingers21.systemsettingsexplorer <raccourci>` (27 octobre, 05:30:26) :
`launcher.workflow_grid` avec 56 tuiles (niveau principal ; SC-001 visait 107, total de toutes les
catégories), barre rouverte ; Retour : `launcher.workflow.run` en 3 étapes sans erreur, Réglages
Système ouvert sur « Compte Apple » (tuile présélectionnée), constaté sur une capture locale supprimée
aussitôt (données personnelles). L'utilisateur essayait la barre au même moment (`sse` tapé à
05:30:23) : l'ouverture de la grille a fermé sa barre ; plus aucun essai lancé ensuite.

## Limites
- Rendu des tuiles non capturé (capture prise après la fermeture) ; seconde grille (catégorie) non
  essayée : essai utilisateur proposé (quickstart).
- `imageaspect` non distingué (research R5).
- Preuves : pas de diaporama (essai concurrent de l'utilisateur, écran privé).
