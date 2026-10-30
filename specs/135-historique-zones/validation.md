# Validation - Session 135

**Date** : 30 octobre 2026

- `scripts/test --no-parallel` : 2 339 tests dans 348 suites réussis (68,1 s).
- Roadie installé (PID 51230, santé 5/5, signature roadied-cert, configuration valide). Raccourcis enregistrés :
  `target_mode.zone_hotkey` « alt+tab » et `target_mode.zone_back_hotkey` « shift+alt+tab ».
- ⌥Tab libre : BTT n'a que ⌘Tab et ⌘⇧Tab sur Tab ; la règle Karabiner « Tab tenu = ⌃⌥ » ne vise que Tab seul.
- Configuration sauvegardée (`roadies.toml.bak-135-*`) avant l'ajout de `zone_history_hotkey = "alt+tab"`.

## Limites

- Parcours réel (zone cliquée, changement de stage, ⌥Tab) laissé à l'utilisateur : frappes simulées refusées sur ce
  poste ; aucun diaporama. L'historique commence à cette installation.
- Zone dans une page qui a défilé ou changé : l'élément mémorisé peut avoir disparu ; si la fenêtre a gardé sa taille,
  le clic suit la position relative, qui peut alors viser autre chose.
