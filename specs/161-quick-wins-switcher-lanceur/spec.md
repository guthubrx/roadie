# Spec 161 — Quick Wins Switcher & Lanceur (Lot 4)

## Contexte et objectif

Enrichir le sélecteur de fenêtres (`switcher`) et la barre lanceur (`experimental.target_mode`) avec des raccourcis et utilitaires locaux à fort gain quotidien, 100 % hors ligne et tous désactivables dans les Paramètres :

1. **Actions clavier directes dans le Switcher** (`switcher.action_keys_enabled = true`) : tant que le sélecteur est ouvert hors édition de recherche (`!isSearchEditing`), appuyer sur `W` (fermer), `Q` (quitter l'app), `M` (réduire/restaurer), `H` (masquer l'app), ou `S` (rapatrier la fenêtre sélectionnée dans la stage active — nouvelle action `.summon`, aussi disponible dans le menu Actions).
2. **Filtres rapides de portée en session dans le Switcher** : hors édition de recherche, `A` bascule un filtre dynamique sur l'application courante et `D` sur l'écran courant, sans modifier le profil enregistré, avec indicateur visuel dans le pied du panneau.
3. **Convertisseur hors ligne dans le Lanceur** (`experimental.target_mode.calc_conversions = true`) : conversions d'unités (longueur, masse, température, données SI/binaires, temps, vitesse), de bases numériques (`0xff`, `0b101010`, `0o755`, `255 in hex`, `42 to bin`, `0xff to dec`) et de fuseaux horaires (`time Tokyo`, `heure Paris`, `14:00 EST in Paris`, `9:30 UTC to Tokyo`), sans aucun appel réseau.
4. **Pipette de couleur native (`color` / `couleur`)** : commande système du lanceur déclenchant `NSColorSampler`, copiant `#RRGGBB` dans le presse-papiers et formatant HEX / RGB / HSL.
5. **Sélecteur d'émojis et symboles typographiques hors ligne (`emoji …` / `:…`)** (`experimental.target_mode.emoji_picker = true`) : catalogue bilingue FR/EN (~140 entrées incluant symboles macOS `⌘ ⌥ ⇧ ⌃` et typographie `— • … € ± ≈ ≠`), copie immédiate sur Retour.
6. **Minuteur & Pomodoro natifs (`timer …` / `pomodoro` + CLI `roadie timer`)** (`experimental.target_mode.timer_enabled = true`) : démarrage, consultation du temps restant, annulation et notification locale macOS à échéance.

## Critères d'acceptation

- `switcher.action_keys_enabled`, `experimental.target_mode.calc_conversions`, `experimental.target_mode.emoji_picker` et `experimental.target_mode.timer_enabled` sont tous validés dans `ConfigValidationRules.knownKeys`, exposés dans `SettingsCatalog` (FR/EN) et couverts par `SettingsCatalogTests` et `Spec155ConfigGuardTests`.
- Aucune régression sur le calcul arithmétique existant (`LauncherCalculator`), ni sur la saisie de recherche du sélecteur (lorsque `isSearchEditing == true`, les lettres `w/q/m/h/s/a/d` vont au champ de recherche).
- Zéro appel réseau, zéro avertissement de compilation, 100 % des tests Swift et Python au vert.
