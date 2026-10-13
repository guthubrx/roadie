# Implementation Plan: Boîte de commandes et fenêtre de réglages

**Branch**: `023-command-box-settings` | **Date**: 2026-10-13 | **Spec**: [spec.md](spec.md)

## Summary

La boîte de recherche de la SPEC-021 (Caps Lock + F) passe en mode commande quand le premier caractère est `/`. Une commande est analysée par un catalogue pur, puis exécutée dans le processus `roadied` par le routeur de commandes `roadie` existant (`CLICommandRouter.run`). Aucune action nouvelle n'est créée.

`/settings` ouvre une fenêtre de réglages (colonne de catégories + recherche à gauche, réglages à droite). `/set table.clé valeur` modifie un réglage sans fenêtre. Les deux passent par le même service de réglages. Un éditeur de texte du fichier `roadies.toml` change une seule ligne, valide le résultat, puis écrit le fichier d'un coup (écriture atomique). Les commentaires et les clés inconnues restent intacts. Le rechargement à chaud existant applique la valeur.

Deux clés nouvelles règlent la taille des étiquettes : `experimental.target_mode.label_font_size` (lettres et recherche) et `experimental.target_grid.label_font_size` (grille). Défaut : 13 points, l'aspect actuel.

## Technical Context

**Language/Version**: Swift 6, macOS 14+
**Primary Dependencies**: AppKit, SwiftUI (nouveau, pour le contenu de la fenêtre de réglages), TOMLKit déjà présent (lecture seulement). Aucune dépendance ajoutée.
**Storage**: `~/.config/roadies/roadies.toml` (source unique des réglages) ; `~/.local/state/roadies/command-history.json` (historique, 50 entrées).
**Testing**: Swift Testing (`./scripts/test`). Tests purs pour le catalogue, le modèle de boîte, l'éditeur de fichier, le catalogue de réglages et le style des étiquettes. Test du lanceur avec le routeur et un fournisseur factice (modèle : `CLICommandRouterTests`). Test manuel à l'écran pour la boîte et la fenêtre.
**Target Platform**: macOS 14+, daemon `roadied` en mode `run` (un seul processus).
**Project Type**: daemon macOS (bibliothèques SwiftPM + exécutables).
**Performance Goals**: ouverture de la fenêtre < 1 s (SC-001) ; effet d'un réglage < 2 s (SC-002) ; filtrage de la liste de commandes à chaque frappe en O(c), c = 19 commandes ; recherche de réglages en O(n·m), n = 167 réglages.
**Constraints**: mode recherche de la SPEC-021 inchangé hors du préfixe `/` (FR-010) ; aucune interception clavier hors session ; le fichier de configuration ne perd ni commentaire ni clé inconnue (FR-024) ; Roadie ne tuile pas sa propre fenêtre de réglages.
**Scale/Scope**: 19 commandes, 167 réglages simples dans 9 catégories, 1 fenêtre, 2 clés de configuration nouvelles.

## Constitution Check

| Article | Vérification | Statut |
|---|---|---|
| III | spec, plan, tâches avant code | OK |
| XVI | worktree `.worktrees/023-command-box-settings` | OK |
| XVIII | catalogue : filtre O(c) par frappe ; réglages : recherche O(n·m) par frappe, n ≤ 167 ; éditeur : une passe O(L) sur L lignes du fichier (774 lignes) ; historique : 50 entrées | OK |
| XIX | pas de nouvelle commande CLI ; le routeur existant fait le travail ; un seul éditeur de fichier réutilisé par `/set` et la fenêtre (2 usages, plus le test) ; pas de SwiftUI ailleurs | OK, voir « Écarts justifiés » |
| XX | logique pure et testable (catalogue, modèle, éditeur, catalogue de réglages) séparée de l'affichage | OK |

## Décisions de conception (détail dans research.md)

1. **Exécution** : `CLICommandRouter().run(argv)` en process, sur le MainActor. Les commandes de grille et de lettres (qui postent une notification au contrôleur de mode cible) et `/restart` s'exécutent après la fermeture de la boîte (R2).
2. **Clavier de la boîte** : `TargetSearchModel.isCommandMode` aiguille toutes les touches vers le mode commande avant la logique de recherche. Le décodeur accepte les caractères de commande (`/ . - _ , :` et lettres accentuées) à partir du caractère produit (AZERTY). Tab complète, Flèche haut/bas parcourt l'historique, Ctrl-N / Ctrl-P parcourt les suggestions. Le mode recherche garde ses touches (R3).
3. **Affichage** : la barre de recherche existante gagne une liste de suggestions et une zone de message, dessinées au-dessus de la barre (R4).
4. **Éditeur de fichier** : édition ligne à ligne avec un automate (chaînes, commentaires, valeurs multi-lignes), limitée aux clés du catalogue ; refus des cas ambigus. Validation d'un fichier candidat du même dossier, contrôle du contenu avant `rename`, sauvegarde `roadies.toml.bak-<horodatage>` à la première écriture de la session (R5).
5. **Catalogue de réglages** : une table statique de 167 descripteurs (nom unique `table.clé`, libellé, description, type, défaut, plage). Un test compare cette table aux clés connues du validateur (API publique `RoadieConfigLoader.knownScalarKeys()`) et aux défauts de `RoadieConfig` : une dérive casse le test (R6).
6. **Fenêtre** : `NSWindow` AppKit + contenu SwiftUI (`NSHostingController`). Fenêtre unique, politique `accessory` conservée, `[.moveToActiveSpace, .fullScreenAuxiliary]`, focus mémorisé puis restauré à la fermeture, Échap et Cmd + W gérés par la fenêtre (R7).
7. **Taille des étiquettes** : un facteur d'échelle `taille / 13` porté par `TargetOverlayStyle` et appliqué aux constantes de taille de `TargetOverlayView` (R8).

## Project Structure

```text
Sources/RoadieCore/Config.swift                       # label_font_size x2 (+ validation, knownKeys) ; RoadieConfigLoader.knownScalarKeys()/ineffectiveKeys()
Sources/RoadieDaemon/SlashCommandCatalog.swift        # NOUVEAU : 19 commandes, alias, analyse -> argv ou action
Sources/RoadieDaemon/SlashCommandModel.swift          # NOUVEAU : état pur de la boîte (saisie, suggestions, historique, message)
Sources/RoadieDaemon/SlashCommandRunner.swift         # NOUVEAU : exécution (routeur, réglages, actions différées)
Sources/RoadieDaemon/ConfigFileEditor.swift           # NOUVEAU : modification d'une ligne du fichier TOML
Sources/RoadieDaemon/SettingsCatalog.swift            # NOUVEAU : 167 descripteurs, 9 catégories
Sources/RoadieDaemon/SettingsService.swift            # NOUVEAU : lecture des valeurs, /set, validation, rétablissement
Sources/RoadieDaemon/SettingsWindowController.swift   # NOUVEAU : fenêtre unique + suivi du fichier
Sources/RoadieDaemon/SettingsView.swift               # NOUVEAU : contenu SwiftUI
Sources/RoadieDaemon/TargetOverlayPresenter.swift     # mode commande dans la session, barre étendue, style à échelle
Sources/RoadieDaemon/TargetModeRuntimeController.swift # config transmise à la session, actions différées
Tests/RoadieDaemonTests/SlashCommandCatalogTests.swift     # NOUVEAU
Tests/RoadieDaemonTests/SlashCommandModelTests.swift       # NOUVEAU
Tests/RoadieDaemonTests/SlashCommandRunnerTests.swift      # NOUVEAU
Tests/RoadieDaemonTests/ConfigFileEditorTests.swift        # NOUVEAU
Tests/RoadieDaemonTests/SettingsCatalogTests.swift         # NOUVEAU
Tests/RoadieDaemonTests/TargetOverlayStyleTests.swift      # NOUVEAU
Tests/RoadieDaemonTests/TargetSearchModelTests.swift       # étendu : décodage de `/`
docs/fr/features.md, docs/en/features.md, docs/fr/cli.md, README.md, examples/roadies.toml
```

## Écarts justifiés

- **SwiftUI** : premier usage dans le dépôt. Raison : 167 contrôles de 5 types, avec filtre et recherche. En AppKit pur, la fenêtre demande environ 3 fois plus de code. Risque : activation d'une fenêtre dans un daemon `accessory` (R7). Garde-fou : la logique reste dans `SettingsService`, la vue est un affichage mince.
- **Table de 167 descripteurs** : volume élevé, mais c'est une donnée (libellés français, plages) sans logique. Elle remplace une interface qui n'existe pas. Le test de dérive la garde juste.

## Complexity Tracking

Aucune violation de constitution.
