# Validation - Session 136

**Date** : 30 octobre 2026

- `scripts/test --no-parallel` : 2 343 tests dans 349 suites réussis (69,5 s).
- Roadie installé (PID 26288, santé 5/5, signature roadied-cert, configuration valide). Profil « Zones »
  (`alt+tab`, `source = "zones"`) ajouté chez l'utilisateur, `zone_history_hotkey` retiré, configuration sauvegardée
  (`roadies.toml.bak-136-*`). Aucun problème de raccourci signalé par le sélecteur.
- Code partagé : les zones passent par le modèle, le panneau, la navigation et la validation du sélecteur de
  fenêtres ; le panneau propre de la session 135 (`ZoneSwitcher.swift`) est supprimé.

## Non vérifié

- Parcours réel (⌥Tab, flèches, souris, retour et clic) et zones des clics ordinaires : frappes et clics simulés
  refusés sur ce poste ; aucune zone de clic observée dans les 20 secondes suivant l'installation.
- Les photos contiennent le contenu des fenêtres cliquées ; elles restent sur le poste, 24 heures au plus.

## Correction après essai (30 octobre 2026)

⌥Tab répété ne faisait pas l'aller-retour : quatre retours vers une zone (08:27:15 à 08:27:23) cliqués, mais l'ordre
de l'historique inchangé ; toutes les zones étant dans la même fenêtre de T3 Code, la sélection initiale reproposait
la même deuxième zone. Une zone où l'on revient remonte désormais en tête (`ZoneHistory.touch`), comme une fenêtre
activée par ⌘Tab. Test `repeatedSwitchesGoBackAndForth` (B, A, B). Zones des clics ordinaires observées
(08:27:26 et 08:28:07).
- **⌘Tab montrait les zones** : BTT lance `roadie switcher cycle --hold cmd` sans profil ; le sélecteur prenait le
  premier profil actif, devenu « Zones » après son ajout en tête de la configuration. Sans profil précisé, il prend
  désormais le premier profil actif de fenêtres (test `commandTabWithoutProfileKeepsWindows`).
