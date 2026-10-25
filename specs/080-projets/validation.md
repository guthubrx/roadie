# Validation 080

## Tests
- `Spec080ProjectsTests` (4 tests) : capture des fenêtres vivantes dans l'ordre, arbre par rangs
  (feuille fermée retirée, son frère remonte), arbre remis rang pour rang et refusé s'il manque une
  fenêtre, projet vide utilisable, remplacement par nom et suppression, section Projets et verbes,
  abréviation refusée pour un projet.
- Défaut trouvé par les tests : rang 0 refusé par `WindowID` (identifiant positif) ; rangs à
  partir de 1.
- Suite complète : 2 017 tests / 273 suites réussis.

## Essai réel
- Stage d'essai créée et nommée « Essai080 », deux documents TextEdit placés par `roadie launch`
  (a.txt à gauche x 1662, b.txt à droite x 3509, 1 837 × 2 114 chacun).
- `roadie project save Essai080` : `windows 2, documents 2, tree true`.
- Documents fermés, `roadie project open Essai080` : `reopened 2, tree true` ; a.txt et b.txt aux
  mêmes cadres, au point près.
- Nettoyage : documents fermés, TextEdit quitté, projet supprimé, stage de départ remise. La stage
  d'essai garde deux membres d'une application quittée (purge normale après 30 min) : renommée
  « Stage 80 », supprimée au nettoyage final.

## Limites
- Applications sans document exposé (Firefox, iTerm2, Teams) : nouvelle fenêtre vide.
- Une application qui ouvre le document dans un onglet d'une fenêtre existante ne crée pas de
  fenêtre : la disposition n'est alors pas remise.
- Verbe et section Projets non essayés au clavier (pas de frappe simulée).
