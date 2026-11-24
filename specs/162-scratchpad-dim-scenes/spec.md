# Spec 162 — Scratchpad flottant, Dim Inactive & Scènes de travail enrichies (Lot 5)

## Contexte et objectif

Ajouter trois fonctions avancées de gestion de fenêtres et d'espace de travail, 100 % locales et toutes désactivables dans les Paramètres :

1. **Scratchpad flottant nommé** (`tiling.scratchpad_enabled = true`) :
   - Registre local persistant (`~/.roadies/scratchpads.json`) de fenêtres flottantes nommées (`default` ou nom libre, ex. `notes`, `terminal`).
   - Commandes `roadie scratchpad assign|toggle|show|hide|release|list [NAME]` (routées vers le daemon) et commande lanceur `Scratchpad (afficher/masquer)`.
   - À l'affichage (`toggle`/`show`), la fenêtre est centrée sur la zone utile de l'écran actif (70 % × 75 % par défaut ou dernier cadre mémorisé, borné à l'écran) et reçoit le focus. Au second appel (`toggle`/`hide`), son cadre est mémorisé et elle est masquée hors écran. Les fenêtres affectées au scratchpad ne sont pas retuilées automatiquement.
2. **Assombrissement des fenêtres inactives (`fx.dim_inactive`)** :
   - Réglages `fx.dim_inactive.enabled` (faux par défaut) et `fx.dim_inactive.opacity` (0,22 par défaut, plage `0.05...0.75`) dans **Paramètres > Effets**.
   - Contrôleur léger `DimInactiveController` utilisant des panneaux `NSPanel` non activants et traversants aux clics (`ignoresMouseEvents = true`), ordonnés directement au-dessus de chaque fenêtre tuilée visible non focalisée (`order(.above, relativeTo:)`), excluant le plein écran natif et les fenêtres masquées. Lorsque désactivé : 0 panneau, 0 timer, 0 surcharge CPU/RAM.
3. **Scènes de travail enrichies (`StageProject` / `roadie project`)** :
   - Extension rétrocompatible de `StageProject` avec `extraURLs`, `launchApps`, `displayCount` et `notes` (les anciens fichiers `projects.json` restent 100 % décodables).
   - Plan de lancement pur (`StageProject.launchPlan`) relançant les applications manquantes, ouvrant URLs/dossiers associés et restaurant l'arbre BSP.
   - Enrichissement de `roadie project save|open|delete|list|info` (options `--url`, `--app`, `--note` et inspection `info [--json]`).

## Critères d'acceptation

- `tiling.scratchpad_enabled`, `fx.dim_inactive.enabled` et `fx.dim_inactive.opacity` sont validés dans `ConfigValidationRules.knownKeys`, exposés dans `SettingsCatalog` (FR/EN), classés dans `SettingsOrganization`, et couverts par `SettingsCatalogTests`.
- `DimInactiveController.computeTargets` exclut toujours la fenêtre focalisée, les fenêtres hors écran, les fenêtres plein écran natif et retourne `[]` lorsque `enabled == false`.
- `ScratchpadCommandService` est atomique, gère assign/toggle/show/hide/release/list et respecte `tiling.scratchpad_enabled == false`.
- Zéro avertissement de compilation, 100 % des tests Swift et Python au vert.
