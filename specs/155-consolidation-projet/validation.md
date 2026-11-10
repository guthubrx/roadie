# Validation - 155 consolidation du projet

**Livraison finale : 0.14.0 publiée et active, 53/53 tâches ; santé 5/5.**

Remplace chaque champ marqué « à remplir » (écrit en majuscules ci-dessous) par la valeur
observée (tâche T044). N'écris jamais une valeur non observée : écris « non vérifié » et la raison.

## Résultats

| Critère | Commande | Attendu | Observé |
|---------|----------|---------|---------|
| SC-001 | `grep -c "/Users/moi" README.md README.fr.md` | `README.md:0` et `README.fr.md:0` | README.md:0 et README.fr.md:0 |
| SC-002 | `grep -rl '0\.13\.0' Sources scripts` | 1 seul fichier : `Sources/RoadieDaemon/DaemonHealth.swift` (2 fichiers avant la tâche T010) | 1 fichier, DaemonHealth.swift |
| SC-003 | bundle temporaire de T012, `plutil -extract RoadieBuildCommit raw …` | le commit court | abc12345 ; roadied 0.13.0 (abc12345) |
| SC-004 | `./scripts/test --no-parallel --filter Spec155ConfigGuardTests` | 2 tests réussis | 2 tests réussis |
| SC-005 | `wc -c AGENTS.md` | moins de 8 000 | 3736 octets ; 366 lignes conservées |
| SC-006 | `grep -c "CFGetTypeID" Sources/RoadieDaemon/AppTargetQueryService.swift` | 5 (2 avant la tâche T019) | 5 contrôles CFGetTypeID |
| SC-007 | `grep -rn "drag.real_press\|drag.real_router_press" Sources/` | aucune ligne | 0 occurrence |
| SC-008 | `.build/debug/roadie completion zsh \| zsh -n ; echo $?` | 0 | 0 |
| SC-009 | `make coverage ; echo $?` | une ligne `coverage : lignes …`, puis 0 | 71,30 % lignes ; 68,51 % fonctions ; 64,64 % régions ; code 0 |
| SC-010 | `time .build/debug/roadie update check` | réponse en 6 s au plus, code 0 ou 1 | GitHub : à jour, code 0, 0,320 s |
| SC-011 | `wc -l Sources/RoadieDaemon/LayoutMaintainer.swift` | au plus 4 400 (attendu : 4 392) | 4392 lignes, 69 lignes déplacées sans changement |
| SC-012 | `./scripts/test --no-parallel` | 2 538 tests / 387 suites, code 0 | 2538 tests / 387 suites, code 0 |
| SC-012 | `python3 -I -B -m unittest discover -s scripts/tests` | 28 tests, `OK` | 28 tests, OK |
| SC-013 | relecture des commandes lancées | aucune CI ni dépense ; publication autorisée après les gates | Aucune dépense, aucune CI ; publication à venir selon reprise |
| FR-021 | `grep -rl "URLSession" Sources` | 1 seul fichier : `Sources/RoadieDaemon/ReleaseCheck.swift` | ReleaseCheck.swift uniquement |

## Tâches non terminées

Aucune tâche préparatoire T001–T045 ouverte ; reprise T046–T053 en cours.

## Non vérifié

- Installation réelle (`make install`) : hors tâches. `roadied --version` de l'application
  installée n'a donc pas été relu.
- Workflow GitHub : jamais lancé (décision D5 de `decisions.md`).
- Complétion dans un terminal interactif (Tab) : seul `zsh -n` est vérifié.
- Pas d’essai Tab dans un terminal interactif ; syntaxe et sortie du routeur vérifiées.

## Décisions en attente de l'utilisateur

Voir `specs/155-consolidation-projet/decisions.md` : D1 à D5 et D8.

## Reprise du 10 novembre

Les mentions « hors tâches » ci-dessus appartiennent à la préparation. Installation et
publication sont maintenant autorisées et seront vérifiées avant clôture.

## Compléments vérifiés avant audit

- Licence Apache-2.0 officielle et notices TOMLKit/toml++ intégrées au bundle.
- 26 tests ciblés de 155 ; 29 tests de scripts (dont clean/dirty suivi/dirty non suivi).
- 7 tests Launcher, cas avant en échec puis après réussi ; édition réelle du fichier en test.
- Contrôle des 20 modifications de réglages conservé et réussi après correction des commentaires.
- CI YAML relue : workflow_dispatch seul, contents:read et checkout SHA épinglé, jamais exécutée.
- 21 diaporamas retirés après archive SHA-256 ; 26 images gardées, dont les deux preuves liées à l'audit 131.
- Convergence du code : CONVERGED, un passage, aucune tâche ajoutée ; détails dans validation/convergence.md.
- Une suite complète a rencontré le test intermittent Spec151 ; 19 tests de recontrôle isolé passent.

Les opérations de publication et d'installation restent en cours (T053).

## Audit V15 du code

Révision 1 : decision=pass, release_blocked=false, 14/14 contrôles, aucun finding ouvert.
Correction : référence checkout du gabarit/recette épinglée. Historique entier : 18 alertes
réfutées par égalité SHA-256 avec les fichiers source historiques ; aucune exception de scanner.
Build Release réussi dans le runner (266,935 s). Validation déterministe de l'audit réussie.
Deux passages de convergence, aucun manque de code nouveau. La revue du commit exact suit
l'audit local car Bridget exige un commit pour la vue immuable ; intégration et publication
restent suspendues à cette revue. La qualification du runtime de 0.14.0 reste T053.

Dernière suite complète : 2549 tests / 388 suites, code 0, 81,709 s.
Rapport d'audit : audits/2026-11-10/session-2026-11-10-consolidation-155-01/.
Le verdict A/100 de grade.json mesure les défauts ouverts et la décision du gate ;
il ne remplace pas les notes de qualité par axe (56–75/100 avant activation).
Les 42 justifications et limites sont conservées dans axis-scoring.md.

## Livraison réelle — 2026-11-10 17:21:10 CET

**Implémentation : Implemented, 53/53 tâches. Pipeline : Livré. Première tâche non cochée : aucune.**

### Périmètre et déroulement

Reformulation montrée puis reprise dans la spec : terminer 155 avec Apache-2.0, section
Launcher compatible, toutes les corrections préparées, CI manuelle seule, signature
existante sans compte Apple, retrait des preuves inutiles, puis release et installation.
Apport : configuration plus claire et ancien format préservé, version et code identifiables,
dépôt réutilisable sans nouvelle dépense. Aucune extension ni nouveau paquet.

Phases exécutées : sync, cadrage, mise à jour Specify/Plan/Tasks et audit de réutilisation,
Analyze avec corrections et seconde lecture, Implement, contre-revues, Converge (2 passages,
aucune tâche ajoutée par Converge), audit V15 fix et revue locale finale readonly, livraison,
nettoyage. Génération intégrale des artefacts sautée : ils existaient déjà. CI distante jamais
lancée ; notarisation et Intel exclus par le contrat. Aucun outil requis indisponible.

ETA initiale : 82–150 min. ETA après Tasks : 70–125 min restantes pour 53 tâches.
Durée à la rédaction du reçu : 104.8 min. Écart au point milieu initial (116 min) :
-9.7 %. Les gabarits préparés ont réduit le travail de saisie ; les principaux écarts
locaux viennent de TOMLKit superDecoder non implémenté, du commentaire scalaire, du test
intermittent 151 et des deux modes de compilation Release. Aucun gain produit extrapolé.

Nouveaux fichiers de production : ShellCompletion.swift, ReleaseCheck.swift, scripts/coverage
et workflow manuel ; ReplayableSnapshotProvider.swift est un déplacement. Cinq suites de
tests Spec155 ajoutées. Réutilisés : TargetModeConfig, catalogue, éditeur, service de réglages,
routeur, statut, scripts de bundle/install/DMG. Arbitrages dans reuse-audit.md ; aucun nouveau
module de configuration, wrapper de service ou paquet externe.

### Git et publication

Remote : origin, https://github.com/guthubrx/roadie.git ; branche cible main.
Base : 0b7de36be40f459bb1096466a7b1b544aa5a8340.
Préparation reprise : 8a5c76eeac1c3704747ff8719dc8d972eee29765 et 1b08c06d1596f2b38f1a574ac0f918086b0590ee.
Nettoyage : 753219eace3084aaa1312ebd94482a5a68e660f5.
Code testé, audité, publié et chargé : 3e324502fb36bd75649a1fc320a42838c8291553.
Intégration fast-forward ; main distant vérifié identique par git ls-remote avant publication.
Tag annoté v0.14.0 : ef248d303733f53224840c27691dc3b4b3b35428, cible 3e324502.
Release publiée, hors brouillon/préversion, Latest vérifiée :
https://github.com/guthubrx/roadie/releases/tag/v0.14.0.
GitHub détecte Apache-2.0 ; aucune exécution de CI visible après push/tag/release.

DMG arm64, macOS 14 minimum, signé ad hoc sans compte Apple ni notarisation. Vérification
hdiutil, montage lecture seule, app et lien Applications, codesign --deep --strict,
licence et notices présentes. DMG et somme retéléchargés depuis GitHub et identiques.
SHA-256 : d9a5a4e09fce622ca13b1ca0f3ac9bc86afdd09b3eac506d18e5fc7c2d052caf.

### Disque et runtime

Installé par make install puis make restart. PID 59138, roadied 0.14.0 (3e324502),
roadie 0.14.0. UUID installé identique au paquet : 5399441F-1977-3F85-88AB-3A88C1470BCC.
Signature vérifiée ; exigence désignée et certificat identiques à l'installation précédente.
Accessibilité conservée, configuration SHA-256 identique à la base. Santé : 5/5 après
installation et après retrait du worktree. Premier contrôle immédiat : socket pas encore
accessible (code 69) ; le contrôle repris et les suivants ont réussi. Aucune correction
hypothétique appliquée à ce démarrage.
Complétion installée valide selon zsh -n ; update check dit à jour (0.14.0).
Pas de nouvelle interface graphique : preuves techniques, aucun diaporama nouveau requis.
Le parcours Gatekeeper sur poste neuf et Tab dans un terminal interactif ne sont pas vérifiés.

### Revues, audit et limites

Revue du plan : BLOCKED sur l'ancien dossier, objections vérifiées et traitées.
Revue du commit : APPROVE_WITH_CHANGES partiel, aucun bloquant dans les zones lues ; deux
recommandations non retenues avec preuves dans adversarial-review-code.md. Aucune
approbation indépendante complète inventée. V15 local : decision=pass, release_blocked=false,
14/14 contrôles. 18 alertes historiques réfutées par SHA-256, aucun finding ouvert.
Les notes par axe restent celles du gate avant activation (56–75/100), avec 42 justifications
dans le rapport d'audit ; le verdict A des défauts ouverts ne les remplace pas. Limites :
pas de benchmark ni plafond mémoire du corps GitHub ; pas de SemVer complète pour préversions.
La revue indépendante ne remplace pas les preuves locales des zones non couvertes.

### Nettoyage et conservation

Worktree /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/155-consolidation-projet retiré
après propreté, fusion et contrôle lsof sans usage ; branche locale 155-consolidation-projet
supprimée. Build nettoyé par la commande projet, DMG intermédiaire retiré avec le worktree,
bundle temporaire et scripts d'essai retirés après copie vérifiée. Aucun travail étranger
embarqué et aucune identité Git modifiée.

Preuves brutes, 21 diaporamas retirés du suivi, manifeste SHA, configuration, ancien app
signé, DMG officiel retéléchargé et générateur de recettes conservés sous :
/Users/moi/.local/state/roadies/validation/155-consolidation-projet.
La sauvegarde de constitution originale est conservée aussi à son chemin d'origine, ignorée.
Les 26 images utiles restent, dont les deux images liées à l'audit 131.

Conservations justifiées :
- /private/tmp/roadie155-audit-source-20261110 : source figée du validateur et preuves ;
  archive durable audit-source-frozen.tar.gz sous le dossier privé ci-dessus (empreinte vérifiée).
- /tmp/roadie155-probe : initialement conservé ; archivé et retiré lors du nettoyage
  complémentaire décrit ci-dessous.
- /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/025-settings-readability : fil préexistant,
  hors du périmètre de cette reprise.
- Les vues distantes de revue restent conservées sous garde native Bridget ; résultats lus,
  tâches terminées, aucun retrait non autorisé de leurs fichiers.

Reste à faire dans le périmètre : aucun. Première tâche non cochée : aucune.
Le dernier commit documentaire de ce reçu est poussé et son SHA est vérifié à la clôture,
sans reconstruction du binaire puisque le code est inchangé depuis 3e324502.

### Nettoyage complémentaire demandé après livraison — 10 novembre 2026

Avant intervention, main et origin/main pointaient tous deux sur
292452e0c320bd792a6451d3e09905025cd9c819 ; arbre propre, une seule branche locale
et distante (main), aucun worktree périmé signalé par git worktree prune --dry-run.
La branche et le worktree de la session 155 avaient déjà été retirés. Aucun build
ni dossier dist ne subsistait dans le dépôt principal ou la copie figée de l'audit.

53 éléments temporaires de la session ont été retirés : 52 fichiers et le dossier
de simulations /private/tmp/roadie155-probe. Aucun usage ouvert détecté par lsof
avant retrait. Les 10 221 entrées ont été archivées ; chaque fichier ordinaire a
été contrôlé par SHA-256 contre l'archive et la source, les liens par leur cible.
Archive et manifeste privés, hors Git :
/Users/moi/.local/state/roadies/validation/155-consolidation-projet/temporary-residuals-20261110.tar.gz
/Users/moi/.local/state/roadies/validation/155-consolidation-projet/temporary-residuals-20261110-manifest.json
SHA-256 de l'archive : 01c1557b7ab5efb6817a0703649b9ebaad10cd1510452a6113bd518b601ee109.

La copie figée /private/tmp/roadie155-audit-source-20261110 reste nécessaire au
validateur : le manifeste d'audit référence ce chemin. Le worktree préexistant
/Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/025-settings-readability reste
hors périmètre ; son absence d'usage par un autre fil n'est pas établie.
Preuves originales archivées, installation active et retour arrière sont conservés.

Contrôle runtime : roadied 0.14.0 (3e324502), PID 59138, santé 5/5. Aucune modification
de code, aucun redémarrage ni nouvelle compilation nécessaires pour ce nettoyage.
