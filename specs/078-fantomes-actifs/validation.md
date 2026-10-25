# Validation 078

## Tests
- `Spec078PreviewTests` (4 tests) : le fantôme coupe la feuille active comme une nouvelle fenêtre
  (arbre), les autres moteurs font aussi la place (cadres disjoints dans l'écran), échéance et fin
  du maintien, demande d'aperçu seulement pour une destination stage d'Ouvrir dans, Envoyer vers
  ou Amener ici (pas de nouvelle stage, de bureau, de Réunir ni de stage d'origine).
- Suite complète : 2 001 tests / 268 suites réussis.

## Essai réel
- `roadie launch /System/Applications/Calculator.app --here --preview-only` (PID 97229 puis
  réinstallé) : `launcher.preview` (stage 0B31204C/3/2, fantôme, sans bascule), disposition
  suspendue 1 989 ms. Pendant l'aperçu, la fenêtre de la stage et ses deux repères passent de
  3 692 à 1 839 points de large ; après la fin, 0 fenêtre à plus de 2 points de son cadre d'avant.
- Essai au clavier impossible ici : `osascript` n'a pas le droit d'envoyer des frappes ; aucune
  frappe n'est partie (22 fenêtres inchangées).

## Limites
- Fantôme dessiné et bascule vers une stage cachée non vus en réel (pas de frappe simulée) ;
  essai utilisateur proposé (quickstart).
- Pas d'aperçu vers un autre bureau, une nouvelle stage, ni pour Réunir ses fenêtres.
- Démon multi-processus : le maintien ne traverse pas les processus.
- Preuves : diaporama non produit (écrans privés).
