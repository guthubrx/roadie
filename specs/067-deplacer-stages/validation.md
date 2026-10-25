# Validation 067

## Tests
- `Spec067StageNamesTests` : doublons, écran branché prioritaire, workspaces, refus de
  renommage, déplacement de stage (autre bureau, même bureau, sans effet).
- `Spec067OverviewDragTests` : places d'insertion, cible d'une fenêtre, clic natif qui
  ouvre et glisser natif qui déplace.
- Rendus natifs du glisser (stage, fenêtre, bureau) générés sur données fictives et
  relus, puis le test provisoire a été retiré.

## Nettoyage réel des doublons
- Origine : workspaces Work/Perso/Com recopiés dans 24 bureaux de tous les écrans.
- Sauvegarde `~/.roadies/stages.json.bak-20261025-avant067`. Premier passage : 70 stages
  modifiées, 23 membres avant et après. « Com » de l'écran courant était devenue « Com 2 »
  au profit d'une copie d'écran débranché (10 membres anciens) : règle corrigée, noms
  remis depuis la sauvegarde démon arrêté, second passage. Résultat : Com, Work, Perso
  sur l'écran courant ; Work 2 et Perso 2 occupées ; aucun doublon ; santé 5/5.

## Essai utilisateur
Glisser des stages et fenêtres confirmé conforme (« exactement ce que je voulais »),
avec la demande d'un trait plus fin, traitée en 066.

## Limites
- Glisser limité au même écran ; fenêtres réduites ou sur un autre Space non déplaçables.
- Stage nommée vide sans carte : pas de cible pour une fenêtre.
- Preuves : pas de diaporama (contenus privés à l'écran).
