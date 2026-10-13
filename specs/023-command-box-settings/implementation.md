# Journal d'implémentation - Boîte de commandes et fenêtre de réglages

## Métadonnées
- **Spec** : 023-command-box-settings
- **Branche** : 023-command-box-settings (worktree `.worktrees/023-command-box-settings`)
- **Démarré** : 2026-10-13
- **Terminé** : En cours (validation à l'écran en attente)

## Méthode
Lots à fichiers exclusifs, un agent par lot, build et tests dans un répertoire de build propre à chaque lot (`/tmp/roadie-build-023-<lot>`), commits par lot par l'orchestrateur avec fichiers nommés. Contre-revue du plan par Codex avant les tâches (10 objections, 10 retenues ou corrigées : `adversarial-review-codex.md`).

## Progression

| Lot | Tâches | Commit | Tests |
|---|---|---|---|
| A | T001, T002 | `912f6d43` | ConfigTests 45 verts |
| C | T004, T005, T006 | `231805ba` | SettingsCatalogTests 16 verts (dérive, défauts, plages) |
| E | T011 | `d9b6063e` | SlashCommandModelTests 17 verts |
| F | T008, T012 | `82f2db0b` | TargetSearchModelTests + TargetOverlayStyleTests 22 verts |
| L | T023, T026 | `3710e3e1` | liens vérifiés (aucun test Swift) |
| D | T010 | `ab7aa90f` | SlashCommandCatalogTests 22 verts (49 formes d'argv exactes) |
| B | T003 | `f4e07d48` | ConfigFileEditorTests 21 verts |
| G | T007 | `587d484f` | SettingsServiceTests 15 verts |
| I | T013, T016, T020, T021 | `989a5549` | SlashCommandRunnerTests 21 verts |
| K | T017, T018, T022 | `bc737ad6` | SettingsViewModelTests 11 verts |
| J | T009, T014, T014b, T019 | `e002c32b` | CommandBoxSessionTests + TargetModeRuntimeControllerTests verts |

Suite complète (`./scripts/test`, scratch `/tmp/roadie-build-023-base`) : **1028 tests, 102 suites, 0 échec** (2026-10-13 13:25).

## Notes et découvertes
- Le copier de scratch `/tmp/roadie-build-023-base` vers un autre dossier échoue (chemin du cache de modules figé) : chaque lot a refait un build complet (~1 min).
- `/set target_grid.rows 4` est refusé avec la configuration par défaut : 12 cases demandent 12 lettres, `hint_characters` n'en a que 9. Le refus est correct (validation avant écriture). Exemples de spec, quickstart et docs remplacés par `target_grid.overlay_fill_opacity`.
- Le routeur ne signale jamais « pas d'autre bureau » (bureaux créés à la demande) : le message du contrat est retiré.
- Le fichier candidat de validation s'appelle `roadies.candidate-<uuid>` (et non `roadies.toml.candidate-…`) pour que `generatedRulesPath` retrouve `roadies.generated.toml` (règles générées validées avec le candidat).
- Lecture des réglages : `readLiteral` reparcourt le fichier (≈ 2 ms par réglage) ; le view model lit le fichier une fois par rafraîchissement et seulement les réglages affichés (Rail 75 réglages ≈ 0,20 s en debug sous forte charge, recherche globale ≈ 0,3 s). Une lecture groupée en un passage reste possible si la lenteur se voit à l'écran.
- Non vérifié par l'agent (nécessite l'écran) : tout le rendu, l'activation et le focus de la fenêtre, Échap/Cmd + W, Space plein écran, non-tuilage, `/grid` et `/letters` différés dans le daemon réel, `/restart`, AZERTY réel.

## Restant
- T015 et T025 : vérification à l'écran après `make install` (section « Livraison »).
