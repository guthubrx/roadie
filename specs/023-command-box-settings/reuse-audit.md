# Audit de réutilisation de l'existant — 023-command-box-settings

## Decision

Statut: PASS
Date: 2026-10-13
Feature dir: /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/023-command-box-settings/specs/023-command-box-settings
Méthode: la primitive `speckit-audit-existing` n'est pas installée dans `.agents/skills` (seule `~/.speckit/commands/speckit.audit-existing.md` existe) : audit manuel avec la structure obligatoire, recherches `rg` sur `Sources/`.

Conclusion courte: les commandes réutilisent intégralement le routeur `roadie` (aucune action nouvelle), la session clavier et la barre de la SPEC-021, la normalisation de texte, le suivi de fichier du rail, la persistance JSON et la purge des sauvegardes de configuration. Neuf fichiers nouveaux, tous sans équivalent. Deux fonctions privées deviennent internes pour être réutilisées.

## Synthese

| Metrique | Valeur |
|---|---:|
| Items extraits du plan | 14 |
| Items audites | 14 |
| Reutilisations deja prevues | 8 |
| Existants potentiellement pertinents | 3 |
| Duplications evidentes | 0 |
| Regles/memoires applicables | 4 |
| Specs existantes applicables | 4 |

## Reutilisations correctement identifiees

| Item du plan | Existant reutilise | Preuve | Commentaire |
|---|---|---|---|
| Exécution des commandes | `CLICommandRouter.run(_:)` | `Sources/RoadieDaemon/CLICommandRouter.swift:103` | en process, sans socket ; aucun service rappelé à la main |
| Session de saisie, tap clavier | `TargetSearchSession`, `installEventTap`, `SearchKeyInput` | `Sources/RoadieDaemon/TargetOverlayPresenter.swift:195-242, 806-838, 914-977` | le mode commande s'ajoute à la session existante |
| Barre de saisie | `TargetSearchBar`, `drawSearchBar` | `TargetOverlayPresenter.swift:1143, 1190-1215` | + liste de suggestions et message |
| Style des étiquettes | `TargetOverlayStyle` | `TargetOverlayPresenter.swift:4-48` | + `labelFontSize` ; seul objet qui atteint la vue |
| Suivi du fichier de configuration | `RailFileWatcher` | `Sources/RoadieDaemon/RailFileWatchers.swift:10-49` | même classe pour la fenêtre (pas de second watcher) |
| Application de la valeur | `ConfigReloadService.shared.currentConfig()` | `Sources/RoadieDaemon/ConfigReloadService.swift:115` | relecture par `stat` ; le rail se recharge par son watcher |
| Historique | `JSONPersistence.load/write` | `Sources/RoadieDaemon/JSONPersistence.swift:30,109` | fichier `~/.local/state/roadies/command-history.json` |
| Sauvegarde du fichier | préfixe `roadies.toml.b` déjà purgé (3 conservées) | `Sources/RoadieDaemon/FileAdministration.swift:149-154` | la sauvegarde de `/set` suit ce nom |

## Existant potentiellement pertinent non mentionne

| Item du plan | Existant proche | Preuve | Decision attendue |
|---|---|---|---|
| Commande la plus proche d'une commande inconnue | `ConfigValidationRules.editDistance` / `suggestionSuffix` (privé) | `Sources/RoadieCore/Config.swift:1353-1385` | REUTILISER : rendre `editDistance` accessible (`static`, interne au module Core, exposé en `public`) ; ne pas écrire une seconde distance d'édition |
| Recherche insensible à la casse et aux accents | `TargetHintService.normalized` | `Sources/RoadieDaemon/TargetHintService.swift:487-515` | REUTILISER pour le filtre de commandes, de réglages et la complétion |
| Clés connues du validateur pour le test de dérive | `ConfigValidationRules.knownKeys` (privé) | `Sources/RoadieCore/Config.swift:1216` | REUTILISER : accesseur en lecture (`knownKeys`, `ineffectiveKeys`) ; pas de seconde liste de clés |
| Détection des fenêtres de réglages transitoires | `isLikelyTransientSettingsWindow` | `Sources/RoadieDaemon/DaemonSnapshot.swift:842` | information : filet de sécurité pour la fenêtre de réglages, aucune modification |

## Duplications evidentes

| Item propose | Doublon existant | Preuve | Action requise |
|---|---|---|---|
| aucune | - | - | - |

## Memoires et regles applicables

| Source | Regle | Impact sur le plan |
|---|---|---|
| `roadie-install-signing` | `make install` produit une Roadie.app signée ; sinon l'Accessibilité saute | livraison (build + installation signée) |
| `t3-delegate-review-runtime` | contre-revue en `runtimeMode: auto` | contre-revue adverse |
| `roadie-shortcuts-location` | hyper key et raccourcis côté droit dans Karabiner | aucun raccourci ajouté ; Caps Lock + F existe |
| constitution XIX | abstraction ≥ 3 usages | `ConfigFileEditor` : `/set`, fenêtre, rétablissement (3 usages) ; `SettingsCatalog` : fenêtre, `/set`, complétion, test de dérive |

## Specs livrees applicables

| Spec | Pattern deja etabli | Impact |
|---|---|---|
| 021 | boîte de recherche, session, barre, modèle pur testable sans écran | base du mode commande |
| 009 | mode lettres, grille, `TargetOverlayStyle` | cibles de la taille des étiquettes |
| 016 / 017 | configuration rechargée à chaud, validation | écriture du fichier + validation avant écriture |
| 019 | rail, `RailSettings`, watcher | catégorie Rail, suivi du fichier |

## Journal de recherche

| Requete | Portee | Resultat |
|---|---|---|
| `rg -n "slash\|Slash\|palette"` | `Sources/` | aucune commande `/` existante |
| `rg -n "SettingsCatalog\|SettingDescriptor\|SettingsService\|SettingsWindow"` | `Sources/` | aucun ; seul `isLikelyTransientSettingsWindow` (heuristique de tuilage) |
| `rg -n "NSWindow\(\|NSWindowController\|NSHostingController"` | `Sources/` | aucune vraie fenêtre, aucun SwiftUI |
| `rg -n "history\|History"` | `Sources/` | aucun historique de commandes |
| `rg -n "levenshtein\|editDistance\|suggest"` | `Sources/` | `editDistance` privé dans `Config.swift` |
| `rg -n "ConfigFileEditor\|replacingLine\|writeConfig\|roadies.toml"` | `Sources/` | aucune écriture de `roadies.toml` ; seuls des lecteurs et la purge des sauvegardes |
| `rg -n "label_font_size\|labelFontSize\|fontSize"` | `Sources/` | polices du rail seulement ; aucune taille d'étiquette cible |
| `rg -n "diacriticInsensitive"` | `Sources/` | `TargetHintService.normalized` |

## Arbitrages

| Sujet | Decision | Justification | Date |
|---|---|---|---|
| `SlashCommandCatalog`, `SlashCommandModel` | creer nouveau | pas de commande `/` dans Roadie ; logique pure testable sans écran | 2026-10-13 |
| `SlashCommandRunner` | creer nouveau | traduit `CLIResponse` en résultat de boîte et gère les actions différées ; 3 voies d'exécution (routeur, réglages, fenêtre) | 2026-10-13 |
| `ConfigFileEditor` | creer nouveau | aucune écriture de `roadies.toml` ; TOMLKit ne conserve pas les commentaires (non vérifié) et le rail lit le fichier ligne à ligne | 2026-10-13 |
| `SettingsCatalog`, `SettingsService` | creer nouveau | aucun réglage décrit à l'écran ; libellés et plages ne sont pas dans le code | 2026-10-13 |
| `SettingsWindowController`, `SettingsView` | creer nouveau | aucune fenêtre ordinaire ; SwiftUI justifié par 167 contrôles (plan, « Écarts justifiés ») | 2026-10-13 |
| Distance d'édition | reutiliser (rendre accessible) | évite une seconde implémentation | 2026-10-13 |
| `knownKeys` | reutiliser (accesseur lecture) | évite une seconde liste de clés ; le test de dérive la compare au catalogue | 2026-10-13 |
| Watcher de fichier | reutiliser `RailFileWatcher` | même besoin ; classe interne au module | 2026-10-13 |

## Gate avant tasks

- [x] Aucune duplication evidente non arbitree
- [x] Chaque item extrait du plan a une ligne d'audit
- [x] Les regles projet applicables ont ete lues
- [x] Les specs existantes proches ont ete verifiees
- [x] Le plan.md a ete refactore ou les divergences sont justifiées
