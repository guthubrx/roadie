# Validation 081

## Tests
- `Spec081MemoryTests` (7 tests) : trois déplacements de Slack vers Com → une proposition ; règle
  existante, « Plus tard » (24 h) et « Jamais » la retirent ; déplacements dispersés ne font pas
  une habitude ; seul le dernier déplacement de moins de 10 minutes, fenêtre restée sur place, est
  annulable ; 200 déplacements au plus ; fermées récentes (12 h, une par titre, plus récentes
  d'abord) ; aucun enregistrement sans changement de stage ; liste vide et chip.
- Suite complète : 2 024 tests / 275 suites réussis.

## Essai réel
- Document TextEdit « ici » (stage 2), `roadie stage assign 80`, puis `roadie undo` : la fenêtre
  revient dans la stage 2 (`launcher.undo changed true`).
- Défaut trouvé : la suite de tests écrivait 38 déplacements fictifs dans le vrai
  `~/.roadies/launcher-moves.json` (`~` = vrai dossier personnel malgré `HOME` isolé). Les
  fichiers du lanceur suivent maintenant `TestEnvironment` (fichiers temporaires pendant les
  tests) ; suite relancée, empreintes des fichiers réels inchangées. Sauvegardes :
  `~/.roadies/backups/2026-10-25-launcher-081/` ; déplacements de test retirés, 4 entrées
  `folder:/tmp/roadie-07x` (essais réels) retirées du classement.
- Document fermé avant de quitter TextEdit, fichier supprimé. Santé 5/5.

## Limites
- Liste vide, chip et choix de règle non essayés au clavier (pas de frappe simulée).
- Chip sur le rail non fait (la barre seulement).
- Rouvrir ne rend pas le document ; une application relancée le retrouve souvent par la
  restauration de macOS.
