# Plan - Session 133

- **Réutiliser** : la barre garde son modèle de recherche d'avant la session 073 (`TargetSearchModel` : étiquettes,
  ↑/↓, Maj + étiquette, Retour, double Retour). Le mode « à l'écran » n'ajoute qu'un indicateur `screenOnly` à
  `TargetSearchSession` : `refreshLauncher()` ne construit aucune liste, le rendu reprend celui d'avant 073
  (`renderScreenSearch`), Maj + lettre appelle `model.typeLabel`.
- **Raccourci** : troisième `TargetSearchHotkey` (Carbon, comme les verbes de SPEC-075), signature `RDSC`,
  événement `target_mode.screen_search_hotkey`, commande `targets.screen`.
- **Contexte du lanceur** : `.disabled` pour ce mode (ni index des applications ni destinations).
- **Réglage** : `screen_search_hotkey`, vide par défaut, car le défaut de `search_hotkey` est déjà ⌘⌃⌥F ;
  Paramètres > Raccourcis ; validation des modificateurs.
- **CLI** : `roadie targets screen`.
- **Dépendances** : aucune.
