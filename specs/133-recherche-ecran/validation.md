# Validation - Session 133

**Date** : 30 octobre 2026

- `scripts/test --no-parallel` : 2 328 tests dans 346 suites réussis (94,4 s), après suppression des
  compilations de test périmées (signal 11 connu après un changement de `TargetModeConfig`).
- Roadie installé (PID 52979, santé 5/5, signature roadied-cert). Raccourcis enregistrés au démarrage :
  `search_hotkey` ⌘Espace, `actions_hotkey` ⌘⌃⌥⇧F, `screen_search_hotkey` ⌘⌃⌥F (`registered`).
- `roadie targets screen` : `target_mode.search_started` (54 cibles), barre de 613 × 55 points, sans liste.
- BetterTouchTool : aucun raccourci sur ⌘⌃⌥F dans la base en service (6.944) ; dossier « Yabai » déjà
  désactivé et vide. Rien n'a été modifié dans BTT.
- Configuration de l'utilisateur sauvegardée (`roadies.toml.bak-133-*`) avant l'ajout de
  `screen_search_hotkey`.

## Limites

- Essai au clavier réel (Capslock + F, saisie d'un mot visible, Retour) laissé à l'utilisateur : les clics et
  frappes simulés sont refusés sur ce poste ; aucun diaporama.
