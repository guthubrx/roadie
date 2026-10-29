# Brief des lots de traduction - session 127

## But
Toute l'interface de Roadie s'affiche en anglais ou en français, selon la langue de macOS. La session 126 a traduit la
barre, le sélecteur et la vue d'ensemble. La session 127 traduit tout le reste : paramètres, rail, menus, messages.

## Mécanisme (déjà en place)
- `tr(_ fr: String, _ en: String) -> String`, public, dans `Sources/RoadieCore/UILanguage.swift`.
  Exemple : `"Fenêtres"` devient `tr("Fenêtres", "Windows")`.
- Un fichier de `RoadieDaemon` qui utilise `tr` doit contenir `import RoadieCore`.
- Exemples réels : `Sources/RoadieDaemon/LauncherActions.swift`, `Sources/RoadieDaemon/WindowSwitcherPanel.swift`.

## Règles
1. Le texte français reste identique, caractère pour caractère. Les tests vérifient le français
   (`scripts/test` fixe `ROADIE_LANGUAGE=fr`).
2. Ne traduire que ce qu'un humain lit : libellés, aides, titres, menus, boutons, messages, notifications, infobulles,
   textes d'accessibilité.
3. Ne jamais traduire : clés de configuration (`window_placement.new_apps_target`), identifiants, valeurs écrites dans
   le TOML, types d'événements, détails de journal, sorties `clé=valeur` lues par des scripts, AppleScript, noms de
   symboles SF.
4. Si un texte sert aussi de clé ou est comparé ailleurs (`tab == "Fenêtres"`, `case "Rail":`), garder une clé stable
   et traduire seulement l'affichage, ou traduire les deux côtés de façon cohérente. Chercher les usages avant de toucher.
5. Un texte interpolé se traduit en entier : `tr("Bureau \(n)", "Desktop \(n)")`, pas morceau par morceau,
   sauf si l'ordre des mots est le même.
6. Anglais naturel et court, style macOS (sentence case pour les aides, Title Case non requis).
7. Ne pas modifier d'autres fichiers que ceux de votre lot. Ne pas committer.

## Glossaire
| Français | English |
|---|---|
| stage | stage |
| bureau | desktop |
| écran | display |
| écran principal | main display |
| tuilage, tuiler | tiling, tile |
| flottante, faire flotter | floating, float |
| rail | rail |
| barre (de recherche) | bar (search bar) |
| lanceur | launcher |
| sélecteur de fenêtres | window switcher |
| vue d'ensemble | overview |
| raccourci | shortcut |
| Paramètres (de Roadie) | Settings |
| Réglages Système | System Settings |
| poignée | handle |
| vignette | thumbnail |
| aperçu | preview |
| règle | rule |
| espacement, marge | gap, margin |
| plein écran natif | native full screen |
| par défaut | default |
| Activé / Désactivé | On / Off |

## Vérification par lot
- Compiler avec un dossier de compilation à vous :
  `scripts/with-xcode swift build --scratch-path /tmp/roadie-build-<lot>`
- Tests ciblés :
  `ROADIE_LANGUAGE=fr scripts/test --scratch-path /tmp/roadie-build-<lot> --no-parallel --filter <Suite>`
- Contrôle du reste : `grep -n '"[^"]*[éèàçêù][^"]*"' <fichier> | grep -v 'tr("'` ne doit plus montrer de texte lu par
  un humain.
- Rapport final : fichiers modifiés, nombre de textes traduits, textes laissés en français et pourquoi, résultat de la
  compilation.
