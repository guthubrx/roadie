# Recherche - 155 Consolidation du projet

Date des mesures : 10 novembre 2026. Base : `main` au commit `0b7de36b`.
Chaque entrée dit ce qui est **constaté** (mesuré ou exécuté), **déduit** ou **non vérifié**.

## R1 - Version déclarée deux fois

- **Constaté** : `Sources/RoadieDaemon/DaemonHealth.swift` déclare
  `public static let current = "0.13.0"`. `scripts/package-dmg` ligne 8 déclare
  `app_version="${ROADIE_VERSION:-0.13.0}"`. `scripts/install` lit déjà la version du
  fichier Swift par `sed`.
- **Décision** : `scripts/package-dmg` reprend la même lecture `sed` ; `ROADIE_VERSION`
  reste une surcharge.
- **Alternative rejetée** : un fichier `VERSION` à la racine. Il ajoute un troisième
  endroit et oblige à générer du code Swift.

## R2 - Identité du build

- **Constaté par sonde** : `~/.local/bin/roadied` est un lien symbolique vers
  `~/Applications/Roadie.app/Contents/MacOS/roadied`. Lancé par ce lien,
  `Bundle.main.object(forInfoDictionaryKey:)` rend `nil`. La lecture directe du fichier
  `Info.plist`, trouvée à partir de l'exécutable après résolution des liens, fonctionne
  dans les trois cas : lancement direct, lancement par le lien, binaire hors application
  (résultat `nil`).
- **Décision** : `scripts/build-app-bundle` accepte un quatrième argument facultatif et
  écrit la clé `RoadieBuildCommit`. `scripts/install` calcule le commit court (8
  caractères) et ajoute `-dirty` si `git status --porcelain` liste un fichier (modifié ou
  non suivi). Le code lit la clé par lecture directe du fichier.
- **Constaté** : `Tests/RoadieDaemonTests/CLICommandRouterTests.swift` exige
  `roadie --version` égal à `roadie <version>` suivi d'un saut de ligne. Cette sortie ne
  change pas.
- **Constaté** : `scripts/tests/test_lifecycle.py` remplace `build-app-bundle` par un faux
  script qui lit seulement ses deux premiers arguments. Un quatrième argument ne le casse
  pas. `git` n'est pas remplacé ; dans le dépôt de test (hors Git) la commande échoue et la
  valeur reste vide grâce à `|| true`.
- **Alternative rejetée** : générer un fichier Swift à la compilation. Cela demande un
  plugin SwiftPM et rend le build dépendant de Git.

## R3 - Purge automatique (proposition 3 de la revue)

- **Constaté** : `roadie cleanup --json` (simulation) propose 80 actions, toutes « old
  roadies.toml backup », pour 2,35 Mo. Certaines sauvegardes portent un nom donné à la
  main (`roadies.toml.bak-018-…`, `-020-…`, `-132-…`, `-133-…`).
- **Constaté** : `~/.roadies` pèse 378 Mo, dont `diagnostics` 333 Mo.
  `~/.local/state/roadies` pèse 537 Mo, dont `validation` 531,8 Mo. Ces dossiers sont des
  preuves de sessions écrites par les agents, pas par le code de Roadie. Le journal
  `events.jsonl` tourne déjà seul à 10 Mo.
- **Décision** : aucune purge automatique. Voir `decisions.md` D7.

## R4 - Événements de clic

- **Constaté** : `Sources/RoadieDaemon/DropPreviewController.swift` (ligne 663 à 667)
  écrit `drag.real_press`. `Sources/RoadieDaemon/RailController.swift` (ligne 419 à 421)
  écrit `drag.real_router_press`. Une recherche des deux noms dans `Sources`, `Tests`,
  `docs` et `scripts` ne trouve que ces deux écritures. Aucun lecteur.
- **Constaté** : introduits par le commit `edd99a41` (session 145), retouchés par
  `71dc794d` (session 152). Environ 21 % des lignes du journal local (comptage par type,
  sans lecture du contenu).
- **Décision** : retirer les deux écritures et rien d'autre. Dans
  `DropPreviewController.swift`, les trois lignes `pressDetails`, `let events = events` et
  `Task { … }` forment un bloc ; les lignes suivantes (`pointerSequence &+= 1`, etc.)
  restent.

## R5 - Lectures d'accessibilité

- **Constaté** : 18 conversions forcées `as! AXUIElement` ou `as! AXValue` dans `Sources`.
  16 suivent un contrôle `CFGetTypeID`. Deux sites n'ont pas de contrôle, dans
  `Sources/RoadieDaemon/AppTargetQueryService.swift` : la fonction
  `copyElementAttribute` (vers la ligne 1009) et la lecture de position et de taille (vers
  la ligne 1073).
- **Décision** : ajouter le contrôle dans les gardes existantes de ces deux sites.
- **Alternative rejetée** : une fonction partagée. Les aides privées ne sont recopiées que
  dans deux fichiers ; la règle du projet demande trois usages.

## R6 - Garde-fous de configuration

- **Constaté** : trois gardes existent déjà :
  `Tests/RoadieDaemonTests/SettingsCatalogTests.swift` (compte `expected.count == 313`,
  ligne 153 à 173, et test suivant ligne 175),
  `Tests/RoadieDaemonTests/ConfigTests.swift` (tests `knownScalarKeysExposeScalarsOnly`
  ligne 973 et `ineffectiveKeysAndEditDistanceAreExposed` ligne 986). Le dossier
  `Tests/RoadieCoreTests` n'existe pas : les tests de `RoadieCore` vivent dans
  `Tests/RoadieDaemonTests`.
- **Constaté** : `RoadieConfigLoader.knownScalarKeys()` existe déjà. Il omet les listes et
  les tableaux de tables : il ne suffit pas pour comparer toutes les clés encodées.
- **Constaté par essai à blanc** (code dans `gabarits/Spec155ConfigGuardTests.swift`,
  tâche T014) :
  `TOMLDecoder().decode(RoadieConfig.self, from: "")` est égal à `RoadieConfig()`, 0
  différence. Le parcours des clés encodées de `RoadieConfig()` contre les clés connues du
  validateur ne trouve aucune clé inconnue et aucune table non vérifiée. Deux valeurs à la
  racine ne sont pas des tables : `rules` et `shortcuts` (tableaux de tables).
- **Limite constatée** : les réglages facultatifs à `nil` ne sont pas encodés, donc pas
  contrôlés. Les tableaux de tables vides ne sont pas parcourus.
- **Décision** : exposer les clés connues par un accesseur public (même forme que
  `ineffectiveKeys()`), ajouter deux tests, écrire la recette.

## R7 - `AGENTS.md`

- **Constaté** : 408 lignes, 39 858 octets. Structure : règle de nettoyage (ligne 1 à 3),
  marqueur `<!-- SPECKIT START -->` (ligne 5), journal des sessions 029 à 138, bloc
  « Current SpecKit feature », marqueur `<!-- SPECKIT END -->`, règle des revues
  indépendantes, bloc `<!-- SPECKIT-USER START -->` à `<!-- SPECKIT-USER END -->`, puis
  journal des sessions 139 à 153 jusqu'à la fin du fichier.
- **Constaté** : aucun script de `.specify/scripts/bash/` n'écrit entre ces marqueurs.
  `.agents/skills/speckit-plan/SKILL.md` demande de mettre à jour la référence du plan
  entre `SPECKIT START` et `SPECKIT END`.
- **Décision** : déplacer les deux blocs de journal dans
  `.specify/memory/sessions/journal.md`, par un script fourni ; garder les marqueurs et le
  bloc « Current SpecKit feature ».

## R8 - Complétion zsh

- **Constaté** : `CLICommandRouter.commandTable` a 79 entrées, dont 1 non implémentée.
  `CLICommandRouter` est isolé sur l'acteur principal : un test qui lit `commandTable`
  doit porter `@MainActor`, sinon la compilation échoue (« main actor-isolated class
  property 'commandTable' can not be referenced from a nonisolated context »).
- **Constaté par sonde** : la fonction de `gabarits/ShellCompletion.swift` (tâche T026)
  produit un script valide. Mesuré après la US10 : `roadie completion zsh | wc -l` rend
  `50`. Le nombre de lignes avant la US10 n'a pas été relevé.
  `zsh -n` rend 0. Avec `compinit` chargé, `_roadie` est défini et lié à `roadie`. Sans
  `compinit`, le chargement fonctionne ; la dernière ligne doit être un `if` et non un
  `&&`, sinon le code de retour du chargement est 1.
- **Constaté** : `CLICommandRouter.isDaemonRouted` ne liste ni `completion` ni `update`.
  Ces commandes s'exécutent donc dans le processus `roadie`, sans le daemon.
- **Alternative rejetée** : la bibliothèque swift-argument-parser. Nouvelle dépendance et
  réécriture de 79 commandes.

## R9 - Couverture

- **Constaté** : `scripts/test` transmet ses arguments à `swift test`.
- **Constaté** (10 novembre 2026) : avec `--enable-code-coverage`, la suite en parallèle
  donne 54 échecs de tests sensibles au temps. En série (`--no-parallel`), un essai donne
  1 échec, un autre 0.
- **Constaté** : quand un test échoue, SwiftPM n'écrit pas son rapport
  `codecov/roadie.json`. Les relevés bruts restent dans
  `.build/arm64-apple-macosx/debug/codecov/*.profraw`. Leurs noms contiennent une espace.
- **Constaté par essai réel** du script `gabarits/coverage` (tâche T028), de 14:11:21 à
  14:14:25 CET, recompilation comprise : 2 523 tests réussis, code de retour 0, total
  `lignes 71.27% | fonctions 68.48% | régions 64.62%`.
- **Décision** : script `scripts/coverage`, appelé par `make coverage`. Il lance
  `scripts/test --enable-code-coverage --no-parallel`, fusionne lui-même les relevés par
  `llvm-profdata merge`, puis affiche la ligne `TOTAL` de `llvm-cov report`. Un échec de
  test pendant la mesure est annoncé sur la sortie d'erreur mais ne change pas le code de
  retour : `make test` fait foi pour les tests. Aucun seuil.
- **Alternative rejetée** : une seule ligne dans le `Makefile`. Elle n'affiche rien quand
  un test sensible au temps échoue.

## R10 - CI

- **Constaté** : le dépôt n'a pas de dossier `.github`.
- **Non vérifié** : version de Swift des machines `macos-15` de GitHub ; comportement des
  tests sans écran.
- **Décision** : workflow à déclenchement manuel seul. Le premier essai est une action de
  l'utilisateur (`decisions.md` D5).

## R11 - Extrait de `LayoutMaintainer.swift`

- **Constaté** : `ReplayableSnapshotProvider` occupe la fin du fichier, de son
  commentaire de documentation (trois lignes `///`) à la dernière accolade (ligne 4 462).
  La classe n'utilise aucun membre privé du reste du fichier. Sept fichiers de test
  l'utilisent par son nom public.
- **Décision** : déplacer le bloc tel quel dans
  `Sources/RoadieDaemon/ReplayableSnapshotProvider.swift`, avec les six mêmes `import`.

## R12 - Vérification de mise à jour

- **Constaté** : aucun fichier de `Sources` n'utilise `URLSession`. Ce sera le premier
  appel réseau du produit.
- **Constaté par sonde** : le code de `gabarits/ReleaseCheck.swift` (tâche T037) compile avec
  `swiftc -swift-version 6` et rend `tag=v0.13.0
  url=https://github.com/guthubrx/roadie/releases/tag/v0.13.0`. L'API publique répond sans
  jeton.
- **Décision** : commande `roadie update check`, exécutée dans le processus `roadie`.
  Délai de 5 secondes, garde de 6 secondes. Comparaison des versions par une fonction pure
  testée. Aucun appel en arrière-plan. ADR 031.
- **Alternative rejetée** : Sparkle (mise à jour automatique). Nouvelle dépendance, clé de
  signature, flux à héberger.

## R13 - Images et preuves suivies

- **Constaté** : 26 images suivies (24 dans `docs/assets`, 2 dans `audits/2026-10-29`) et
  21 fichiers `preuves-corrections/**/preuves.html` (environ 3 Mo).
- **Décision** : rapport d'inventaire seul ; aucun retrait.

## R14 - Pièges connus du projet (à écrire dans `AGENTS.md`)

- **Signature** : installer avec le certificat `roadied-cert`. Une signature différente
  fait perdre la permission d'accessibilité.
- **Build de test périmé** : après l'ajout d'un champ à une structure de `RoadieCore`
  (par exemple `RoadieConfig`), les tests peuvent planter au signal 11 (« outlined
  destroy »). Remède : supprimer
  `.build/arm64-apple-macosx/debug/RoadieTilerTests.build`, puis relancer
  `scripts/test --no-parallel`.
- **Symbole introuvable à l'édition de liens** (« Undefined symbols …
  TargetModeConfig.init ») : `touch Sources/RoadieDaemon/OverviewController.swift`, puis
  relancer.
- **Processus enfants** : `roadied` ignore SIGTERM ; un enfant en hérite. Rétablir les
  signaux par défaut au lancement de l'enfant.
- **Audit V15** : le lancer sur un checkout hors de `.worktrees`.
- **Avertissement sans gravité** : `scripts/test` utilise un dossier personnel
  temporaire ; SwiftPM affiche « failed loading cached manifest … Not a directory ». Ce
  n'est pas une erreur.
- **Commits** : nommer les fichiers (`git add -- <fichiers>`), jamais `git commit -a`.

## R15 - Base de référence des tests

Mesures du 10 novembre 2026 sur le commit `0b7de36b`, machine chargée (charge de 16 à 25).

| Commande | Résultat | Durée |
|----------|----------|-------|
| `./scripts/test --no-parallel` | 2 523 tests dans 383 suites réussis, code 0 | 79 s sans recompilation |
| `./scripts/test` (parallèle) | 2 523 tests, 68 échecs dans 16 suites sensibles au temps, code 1 | 43 s sans recompilation |
| `python3 -I -B -m unittest discover -s scripts/tests` | 28 tests réussis | 30 s |

- **Constaté** : les 68 échecs du mode parallèle touchent des suites qui mesurent des
  délais (`Spec033DragFlowTests` 27, `Spec148AcquisitionTests` 6, `Spec149…`, `Spec151…`,
  `Spec153…`, `Settings027IPC…`). La même suite passe en série sur le même commit.
- **Décision** : la commande de contrôle de toutes les tâches est
  `./scripts/test --no-parallel`. Le mode parallèle n'est pas un critère d'acceptation
  sur une machine chargée.
- **Non vérifié** : le résultat du mode parallèle sur une machine au repos.
- **Constaté** : `AGENTS.md` cite 2 512 tests pour la session 153. Deux commits de
  correction ont suivi ; la base mesurée est 2 523 tests dans 383 suites.
- **Décision** : SC-012 vise le nombre final exact, 2 538 tests dans 387 suites
  (2 523 + 15 tests de la spec 155 dans 4 suites). Voir R16 pour les nombres par palier.

## R16 - Essais à blanc des recettes

Tous les essais datent du 10 novembre 2026. Ils partent du commit `0b7de36b`.

- **Constaté - code** : tous les changements de code et de scripts ont été appliqués dans
  le worktree par `tools/appliquer.py`, compilés et testés, puis annulés. État final :
  `./scripts/test --no-parallel` rend 2 538 tests dans 387 suites, code 0.
- **Constaté - indentation** : un texte « avant » relevé de mémoire était faux pour la
  tâche T022. Le remplacement exact a refusé de s'appliquer. C'est le rôle de la règle R0
  de `quickstart.md` : un texte « avant » introuvable arrête la tâche.
- **Constaté - essai par paliers n°1** : la suite a été lancée à chaque point de commit.
  Le palier de la US7 a échoué : deux attentes des tests de complétion portaient sur la
  commande `update`, qui arrive à la US10. Le gabarit
  `gabarits/Spec155ShellCompletionTests.swift` a été corrigé : l'égalité entre les
  commandes du script et celles de la table couvre `update` dès qu'elle existe.
- **Constaté - essai par paliers n°2** (après correction), suite complète à chaque palier :

  | Palier | Code | Tests | Suites | Durée |
  |--------|-----:|------:|-------:|------:|
  | US2 (après T012) | 0 | 2 527 | 384 | 79,6 s |
  | US3 (après T015) | 0 | 2 529 | 385 | 80,5 s |
  | US5 et US6 (après T024) | 0 | 2 529 | 385 | 81,6 s |
  | US7 (après T030) | 0 | 2 533 | 386 | 80,8 s |
  | US9 (après T034) | 0 | 2 533 | 386 | 79,1 s |
  | US10 (après T040) | 0 | 2 538 | 387 | 79,2 s |

  Les paliers de la US5 et de la US6 ont été mesurés ensemble, en un seul lancement.
- **Constaté - parcours complet des fiches** : les 45 fiches de `recettes.md` ont été
  jouées dans un clone jetable, sans compilation : 13 commits aux messages exacts,
  `git status --short` vide à la fin. Les tâches de documentation en font partie.
- **Constaté - égalité** : le code produit par ce parcours est identique au code testé
  par l'essai n°2 (`diff -r Sources` sans différence ; 4 fichiers de test identiques).
- **Constaté - autres contrôles** : `./scripts/coverage` rend le code 0 (environ 3 minutes) ;
  `roadie completion zsh | zsh -n` rend 0 ; `roadie update check` a répondu
  « Roadie is up to date (0.13.0). » avec le code 0 ; le bundle temporaire de T012 affiche
  `roadied 0.13.0 (abc12345)`.
- **Constaté - test sensible au temps** : `Spec151ModifierGestureTests.aNewGenerationNeverRestoresAnObsoleteLayout`
  a échoué une fois sous charge, puis réussi seul. D'où le piège P3 et l'option
  `--no-parallel` dans toutes les commandes.
- **Limites** : les fiches n'ont pas été jouées par un autre modèle. Les outils
  `deplacer_journal.py` et `extraire_fournisseur.py` n'ont pas été lancés deux fois sans
  option ; les fiches l'évitent par un garde `test -e`. La mesure de couverture n'a été
  faite qu'une fois. Le workflow GitHub n'a jamais été lancé.

## Références de base

- Baseline : `~/.speckit/research/03-cognitive-load-productivity.md` (charge cognitive) :
  appliqué à US4 (consignes courtes) et à la forme des tâches.
- La feature ne touche ni agent IA, ni donnée personnelle nouvelle. US6 retire une
  donnée d'usage (positions des clics). US10 ajoute un appel sortant à la demande, sans
  donnée de l'utilisateur dans la requête.

## Reprise — décisions techniques

[launcher] réutilise TargetModeConfig ; décodage de chaque clé sur les valeurs anciennes,
éditeur ciblé canonique ; aucun réencodage global ni type de réglages en double.
Sources officielles consultées le 10 novembre : Apache LICENSE-2.0.txt et Apple
https://support.apple.com/en-us/102445 (Réglages Système > Confidentialité et sécurité >
Ouvrir quand même après une première tentative). Aucun compte payant créé.

Vérification documentaire tests : swiftlang/swift-testing (README officiel) confirme
les traits de suite et les tests paramétrés, sans nouvelle dépendance. API URLProtocol
Apple consultée ; rendu Markdown indisponible dans le navigateur de recherche.
La qualification repose donc sur compilation Swift et test local du vrai URLSession.

Compatibilité TOMLKit vérifiée : superDecoder(forKey:) appelle fatalError dans
KeyedDecodingContainerProtocol.swift:297. Premier essai Launcher arrêté sur ce chemin.
Correction : réutiliser nestedContainer, implémenté aux lignes 241–265, et passer les
conteneurs au même initialiseur TargetModeConfig. Aucun adaptateur Decoder ajouté.

Test transport : le protocole bloqué déclenche réellement URLError.timedOut (-1001)
avant la garde externe. L'assertion accepte cette erreur native ou la garde timeout ;
la durée bornée et stopLoading restent exigés. Ce constat provient du payload réel.
