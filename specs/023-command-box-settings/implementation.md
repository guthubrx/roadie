# Journal d'implémentation - Boîte de commandes et fenêtre de réglages

## Métadonnées
- **Spec** : 023-command-box-settings
- **Branche** : 023-command-box-settings (worktree `.worktrees/023-command-box-settings`)
- **Démarré** : 2026-10-13
- **Terminé** : 2026-10-13 (code livré ; validation à l'écran T015 et T025 en attente de l'utilisateur)

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

## Convergence

### Passage 1 (agent Converge, lecture seule + contre-revue Codex de l'implémentation)
Verdict : non convergé, 13 tâches ajoutées (T027 à T039). Défauts les plus graves corrigés :
- touches (`#`, `+`, `~`…) laissées à l'application active en mode commande, et ponctuation entrée dans la recherche (FR-010) : indicateur de mode lu par le tap, décodeur du mode recherche rétabli à l'identique (16141d94) ;
- `/set` sur fichier invalide, illisible (UTF-8), lien symbolique, permissions, relecture avant `rename`, commentaire de fin de ligne perdu au rétablissement (`d05348f9`) ;
- réglages en lecture seule sans valeur, bouton Rétablir faux, surveillance d'un fichier absent (`d05348f9`, `a4615c2d`) ;
- `/heal`, `/reload`, messages et usage des échecs, échec des actions différées journalisé, tests d'effet (`0554db16`).
Suite complète après corrections : **1053 tests, 102 suites, 0 échec**.

### Passage 2
Les 13 tâches sont prouvées dans le code et les tests. Un manque de classe (d) : T040 (`/heal` et `/reload` en échec affichés comme résultat). Aucun test de la SPEC-021 retiré ou relâché (SC-006 tient). Tests relâchés listés par l'agent : tous justifiés par T030, T031 (heal/reload en info), T034, T036 ; seul `reload` en échec ne l'était pas, ce que T040 rétablit.

### Incident disque
Le disque est monté à 100 % pendant le lot N1 (ENOSPC) : le code du lot n'a pu être compilé qu'après avoir supprimé les dossiers `/tmp/roadie-build-023-{a,b,c,d,e,f,g,i,j,k}` (environ 5 Go). Le lot a ensuite été vérifié par la suite complète.

### Passage 3
T040 corrigé (`/heal`, `/reload` en échec = erreur visible, sans historique, journalisé sans saisie). En relisant le correctif, défaut trouvé et corrigé avant commit : la traduction `status=` → « Rechargement refusé. » s'appliquait aussi à `/doctor` et `/heal` (qui écrivent `status=ok`) ; elle est désormais limitée à `config reload`, avec deux tests sur les vraies formes de sortie. Verdict : CONVERGED (les 40 tâches de code cochées ; T015 et T025, validation à l'écran, restent à faire).

## Audit v14 (mode fix, 1 cycle + cycle final)
Session : `audits/2026-10-13/session-2026-10-13-023-command-box-settings-01/`. **Note A (98,9)**, 0 critique, 0 élevé, 5 moyens, 13 faibles au cycle 1 ; 9 corrigés (couleur à chiffres pleine chasse refusée, doublons de décodage de couleur, de recherche de commande et de plage supprimés, test de rechargement ajouté, boucle de test sans assertion corrigée). Suite : **1058 tests, 0 échec**.
Restants, avec justification (constitution XVIII et XIX) :
- PERF-001 (moyen) : `SettingsViewModel` relit le fichier par réglage affiché (≈ 0,15 s pour les 75 réglages du Rail, à chaque prise de focus de la fenêtre, build debug sous charge). Mesuré, documenté dans le code ; une lecture groupée en un passage reste possible si la lenteur se voit à l'écran (quickstart §3 mesure l'ouverture < 1 s). Pas d'optimisation sans gain mesuré (article XXII).
- TEST-004 : `/send`, `/desktop`, `/split`, `/stage send` couverts par le tableau d'argv exacts (même routeur que la CLI, dont les effets sont testés par `CLICommandRouterTests`), sans test d'effet dédié.
- TEST-005 à TEST-009, MIN-003, MIN-004 : faibles, laissés (choix de l'auteur).
`audits/latest` n'est pas commité : la branche `022-audit-remediation` le modifie aussi (évite un conflit de fusion).

## Correctif T041 (2026-10-13, signalé par l'utilisateur : « le panneau ne s'est pas ouvert »)
Diagnostic par données réelles : les événements montraient `command_box_settings` (la boîte avait bien reconnu `/settings`), et `CGWindowListCopyWindowInfo` montrait la fenêtre « Roadie » 860 x 632 présente et à l'écran mais au rang 14, derrière Teams (rang 0) et T3 Code (rang 2) qui couvrent tout l'écran externe ; l'application active était Teams. Cause : `NSApp.activate()` ne peut pas activer un processus d'arrière-plan depuis macOS 14, donc `makeKeyAndOrderFront` ne la plaçait pas devant. C'était un des points « à vérifier à l'écran » du rapport : le test unitaire ne pouvait pas le voir. Correction : panneau non activant flottant, centré sur l'écran du pointeur (voir research R7). À revalider par l'utilisateur à l'écran.

## Livraison (2026-10-13)
- Intégration : fast-forward de `023-command-box-settings` dans `main` (base `acc10e13`, cible `282d2559`), push sans force vers `origin/main`, SHA distant lu par `git ls-remote` = `282d255936a1b09fcd8fabdf32a66ed50e3daf86` = SHA local.
- Installation : `make install` (signature : remplacement de la signature existante, identifiant `com.roadie.roadied`) puis `make restart` ; `roadie query health` : process, daemon-status (`accessibility=true`, `config_valid=true`) et self-test `ok`, 7 fenêtres tuilées ; `roadie config show` expose `label_font_size = 13` pour `target_mode` et `target_grid`.
- Preuve sur une copie du vrai `roadies.toml` (775 lignes, test jetable retiré ensuite) : 8 réglages écrits par `SettingsService` (`target_grid.overlay_fill_opacity`, `borders.active_color` avec `#` dans la chaîne, `rail.width`, deux `label_font_size` insérés, `focus.mouse_follows_focus` par `oui`, `tiling.gaps_outer`, `target_mode.search_hotkey`) ; seules les 5 lignes visées ont été remplacées et 3 lignes ajoutées (775 → 778) ; le fichier reste valide (0 erreur) ; une sauvegarde `roadies.toml.bak-…` ; aucun commentaire perdu.
- Non vérifié par l'agent (nécessite l'écran et le clavier de l'utilisateur) : T015 et T025 (voir `quickstart.md`) : boîte `/`, fenêtre de réglages (activation, focus, Échap, Cmd + W, Space plein écran, non-tuilage), `/grid` et `/letters` différés dans le daemon réel, `/restart`, tailles 13/20/48 à l'écran, AZERTY réel, mesures SC-001 (< 1 s) et SC-002 (< 2 s).
