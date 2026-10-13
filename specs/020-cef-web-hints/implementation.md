# Journal d'Implémentation - Lettres d'accès dans Bluejay

## Métadonnées
- **Spec** : 020-cef-web-hints
- **Branches** : Roadie `020-cef-web-hints` (worktree `.worktrees/020-cef-web-hints`) ; Grayjay `pr/029-macos-renderer-accessibility` (worktree `/Users/moi/11.Repositories/grayjay-pr-029-macos-a11y`)
- **Démarré** : 2026-10-13
- **Terminé** : 2026-10-13

## Diagnostic (preuves)

| Preuve | Constat |
|---|---|
| `~/.roadies/events.jsonl` 04:00Z | Grayjay : 6-7 éléments, 4 candidats, aucune zone web |
| `JustCef/native/src/main_mac.mm` | `SharedApplication` ne gère aucun attribut d'accessibilité |
| `strings` sur le binaire CEF 141 | `AXEnhancedUserInterface` présent, `AXManualAccessibility` absent |
| `Program.cs:148-173` | `ReconstructArgs` transmet l'option sans filtre |
| Lancement avec `--force-renderer-accessibility` | zone web publiée, 410 éléments, profondeur 11, 7 candidats |
| Relevé jetable (supprimé) | 405 éléments ; 38 focalisables ; feuilles focalisables = barre latérale (14), cartes (17), boutons ronds (2), recherche |

## Progression

### T001 : branche Bluejay
- **Statut** : ✅ `pr/029-macos-renderer-accessibility` = `f306a00`, basée sur `4063164` (FUTO, « New live chat impl »).
- **Note** : une première version basée sur `origin/master` (`521a67e`) entrait en conflit avec l'intégration (`Program.cs` réécrit par FUTO : Widevine, nouvelles tentatives ; `README.md`). Recréée sur le dernier commit FUTO de `Program.cs` présent dans l'intégration ; fusion à blanc propre.

### T002-T006 : règle « feuille focalisable » et mesure
- **Statut** : ✅ 831 tests verts. Contre-revue du plan BLOCKED, 5 corrections appliquées (voir `adversarial-review-codex.md`).

### T007 : documentation FR/EN
- **Statut** : ✅

### T008 : suite complète
- **Statut** : ✅ 831 tests, build OK.

### T009 : mesures
| Moment | App | Version | Résultat |
|---|---|---|---|
| référence | T3 Code | main | 150 candidats, `limit`, 373 lus, 127 ms |
| référence | Finder | main | 58 candidats, `timeout`, 121 lus, 251 ms |
| référence | Bluejay (lancé avec l'option) | main | 7 candidats, `complete`, 407 lus, 153 ms |
| 020 | T3 Code | 020 | 117 candidats, `complete`, 423 lus, 177 ms, `focusableAdded=0` (contenu de T3 Code différent : fil en cours d'écriture) |
| 020 | Finder | 020 | 58 candidats, `timeout`, 115 lus, 254 ms, `focusableAdded=0` |
| 020 | Bluejay | 020 | 4 candidats, 6-7 lus : **Bluejay relancé à 06:24:04 sans l'option** (`ps`), mesure non valable |

Fausses pistes écartées par les données : fenêtre cachée en bord d'écran (remesurée affichée : toujours vide) ; code 020 (le moteur CEF n'avait plus l'option).

### T010 : build Bluejay
- Worktree d'intégration restauré (`git worktree prune`, 10 entrées mortes ; `git worktree add ../grayjay-bluejay-all-features bluejay/all-features`).
- `build-bluejay-with-prs.sh` : intégration `84d80cb` (« Merge branch 'pr/029-macos-renderer-accessibility' »). Le script s'arrête ensuite sur sa ligne 154 (`${#SKIPPED_BRANCHES[@]:-0}` : bad substitution, bash 5.3) avant la build ; l'étape suivante du script (`build-bluejay-clean.sh` du worktree d'intégration) est lancée à la main, à l'identique.

### T010 (suite) : build et installation
- Sous-modules absents du worktree d'intégration ; les URL relatives visent `github.com/guthubrx/FUTO.MDNS.git`, inexistant. Clonés depuis les clones locaux du checkout principal par options `-c` (configuration partagée vérifiée inchangée par empreinte).
- Course de téléchargement parallèle de `JustCefNative-osx-arm64.zip` au 1er essai ; 2e essai OK (archive en cache).
- `dist/BlueJay.app` : option présente (chaîne UTF-16 dans l'exécutable), absente de l'app installée ; `wwwroot/web/assets` identiques (60 fichiers, `diff -rq` vide).
- Installation après fermeture par l'utilisateur ; ancienne app déplacée dans `/Users/moi/.local/share/bluejay-backups/BlueJay-20261013-064132.app`. Lancement sans argument : `justcefnative` reçoit `--force-renderer-accessibility` (`ps`).

### T009 (final) : mesures
| App | Version | Résultat |
|---|---|---|
| Bluejay | 020, anti-doublon v1, boost | 7 candidats puis 0 feuille ajoutée (blocage sous `AXGroup` géant) |
| Bluejay | 020, anti-doublon v2, boost | 14 candidats, 11 feuilles, `timeout`, 62-73 lus |
| Bluejay | 020, sans boost en zone web, 250 ms | 14 candidats, 11 feuilles, `timeout`, 1 516-1 544 lus |
| Bluejay | idem, 500 ms | **79 candidats, 72 feuilles, `complete`, 3 317 lus, 440-468 ms** |
| T3 Code | final, 500 ms | 150, `limit`, 368 lus, 43 ms (référence main : 150, `limit`, 373 lus, 127 ms) |
| Finder | final, 500 ms | 58, `timeout`, 145 lus, 502 ms (référence : 58) |

- **SC-001** ✅ 79 ≥ 20. **SC-002** ✅ validé par l'utilisateur (la lettre d'une entrée de barre latérale ouvre la page). **SC-003** ✅ Finder 58, T3 Code 150. **SC-004** ✅ aucun doublon (validation utilisateur).

### T011 : convergence
- **Statut** : ✅ artefacts mis à jour (research, data-model, implementation).

### T012 : retour utilisateur, page Abonnements
| Étape | Bluejay Abonnements |
|---|---|
| avant T012 | 20 cibles, 14 feuilles : aucune carte vidéo (capture utilisateur) |
| `CFIdentitySet` + élagage des traits | 50 cibles, 43 feuilles, complet, 3 080 lus, 448-470 ms |
| marqueur « inconnu » seulement si ≤ 1 point | **80 cibles, 73 feuilles**, complet, 463 ms |

T3 Code 150 (`limit`, 55 ms), Finder 58 (`timeout`, 510 ms). Validation utilisateur : lettres sur les cartes, ouverture de la vidéo, aucun doublon.

### Contre-revue round 5 et budget
- Anti-doublon bidirectionnel ajouté. Essai « élaguer seulement le contenu caché » : régression (cartes sans lettre, validation utilisateur), retiré.
- `timeout_ms` 500 → 700 (choix utilisateur, marge) ; sauvegarde `~/.config/roadies/roadies.toml.bak-020-20261013-071312`.
- Audit 02 : note A (99,7) ; QUAL-001 (`scan()` long) laissé ouvert, découpage non demandé.
