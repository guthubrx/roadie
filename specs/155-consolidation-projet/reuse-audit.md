# Audit de reutilisation de l'existant - 155-consolidation-projet

## Decision

Statut: PASS
Date: 2026-11-10
Feature dir: /Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/155-consolidation-projet/specs/155-consolidation-projet

Conclusion courte: le plan étend l'existant partout où un équivalent existe. Il ne crée
aucun doublon défendable avec une preuve `fichier:ligne`. Un existant proche est signalé
(le registre `.specify/memory/sessions/index.md`) ; la divergence est justifiée plus bas
et ne demande pas d'arbitrage. Aucune dépendance externe n'est ajoutée.

Méthode : protocole de `/Users/moi/.speckit/commands/speckit.audit-existing.md`, exécuté
directement avec `git grep` sur le commit de base `0b7de36b`. La skill de projet
`.agents/skills/speckit-audit-existing` n'existe pas dans ce dépôt. Aucun sous-agent
`Explore` n'a été lancé.

## Synthese

| Metrique | Valeur |
|---|---:|
| Items extraits du plan | 24 |
| Items audites | 24 |
| Reutilisations deja prevues | 17 |
| Existants potentiellement pertinents | 1 |
| Duplications evidentes | 0 |
| Regles/memoires applicables | 11 |
| Specs existantes applicables | 8 |

Répartition des 24 items : 17 réutilisations (tableau suivant), 1 existant proche
(item 16), 6 items `OK aucun equivalent` dans le journal de recherche (items 11, 13, 14,
17, 20 et 22).

## Reutilisations correctement identifiees

| Item du plan | Existant reutilise | Preuve | Commentaire |
|---|---|---|---|
| 1. `RoadieVersion.buildCommit` et `RoadieVersion.display` (US2) | `RoadieVersion.current`, seule source de la version | `Sources/RoadieDaemon/DaemonHealth.swift:324` | L'énumération existante est étendue. Aucun second type de version. |
| 2. Lecture de `Info.plist` par `PropertyListSerialization` (US2) | Même idiome déjà utilisé trois fois, sans aide partagée | `Sources/RoadieDaemon/AlfredWorkflow.swift:146`, `Sources/RoadieDaemon/AlfredWorkflow.swift:170`, `Sources/RoadieDaemon/LauncherBookmarks.swift:437` | Idiome repris tel quel. `Bundle.main.infoDictionary` (`Sources/RoadieDaemon/AlfredScriptRunner.swift:195`) ne convient pas : il rend `nil` par le lien symbolique (`research.md` R2). |
| 3. Champ `DaemonStatus.buildCommit` (US2) | Structure `DaemonStatus` et son fichier `daemon-status.json` | `Sources/RoadieDaemon/DaemonHealth.swift:330` | Champ facultatif ajouté au contrat de la spec 016. Aucun second fichier d'état. |
| 4. Version lue par `scripts/package-dmg` (US2) | Extraction par `sed` déjà écrite dans `scripts/install` | `scripts/install:98` | La même commande `sed` remplace le littéral de `scripts/package-dmg:8`. |
| 5. Quatrième argument de `scripts/build-app-bundle` (US2) | Script existant et son `Info.plist` généré | `scripts/build-app-bundle:54` | Une clé ajoutée au fichier généré. Aucun nouveau script de build. |
| 6. Accesseur `RoadieConfigLoader.knownKeys()` (US3) | `ConfigValidationRules.knownKeys`, `knownScalarKeys()`, `ineffectiveKeys()` | `Sources/RoadieCore/Config.swift:1900`, `Sources/RoadieCore/Config.swift:1706`, `Sources/RoadieCore/Config.swift:1716` | Accesseur de 3 lignes sur la table existante, même forme que `ineffectiveKeys()`. `knownScalarKeys()` ne suffit pas : il omet les listes (`research.md` R6). |
| 7. `Spec155ConfigGuardTests` (US3) | Gardes existantes des réglages | `Tests/RoadieDaemonTests/SettingsCatalogTests.swift:171`, `Tests/RoadieDaemonTests/ConfigTests.swift:973`, `Tests/RoadieDaemonTests/ConfigTests.swift:986` | Les deux tests nouveaux couvrent ce que ces gardes ne couvrent pas (valeurs par défaut du décodage vide, clés encodées inconnues du validateur). Aucune garde existante n'est recopiée. |
| 8. Deux gardes de type `CFGetTypeID` (US5) | Idiome déjà présent dans le même fichier | `Sources/RoadieDaemon/AppTargetQueryService.swift:974`, `Sources/RoadieDaemon/AppTargetQueryService.swift:1054` | Sites corrigés : lignes 1014 et 1083 à 1084. Aucune aide partagée créée : 2 sites seulement (règle des 3 usages). |
| 9. Commande `roadie completion zsh` (US7) | `CLICommandRouter.commandTable`, `CLICommandSpec.names`, `usageError()` | `Sources/RoadieDaemon/CLICommandRouter.swift:209`, `Sources/RoadieDaemon/CLICommandRouter.swift:79`, `Sources/RoadieDaemon/CLICommandRouter.swift:84`, `Sources/RoadieDaemon/CLICommandRouter.swift:319` | La complétion est générée depuis la table existante. Aucune seconde liste de commandes. |
| 10. `scripts/coverage` et cible `make coverage` (US7) | `scripts/test`, `scripts/with-xcode`, `Makefile` | `Makefile:3` | Le script appelle `scripts/test` avec une option. Il n'a pas sa propre commande de test. |
| 12. Fichier `ReplayableSnapshotProvider.swift` (US9) | Classe existante, déplacée sans changement | `Sources/RoadieDaemon/LayoutMaintainer.swift:4397` | Déplacement pur, vérifié par `extraire_fournisseur.py --check`. |
| 15. Commande `roadie update check` (US10) | `commandTable`, `usageError()`, `tr(fr, en)`, `RoadieVersion.current` | `Sources/RoadieDaemon/CLICommandRouter.swift:209`, `Sources/RoadieCore/UILanguage.swift:44`, `Sources/RoadieDaemon/DaemonHealth.swift:325` | Même forme que les autres commandes locales. Textes dans les deux langues par l'aide existante. |
| 18. Tests `Spec155…Tests` qui appellent le routeur (US2, US7, US10) | Précédent `CLICommandRouter()` dans les tests ; garde de `--version` | `Tests/RoadieDaemonTests/Spec150FinderShortcutTests.swift:31`, `Tests/RoadieDaemonTests/Spec061OverviewTests.swift:481`, `Tests/RoadieDaemonTests/CLICommandRouterTests.swift:95` | Convention de nom et de dossier reprise. `roadie --version` reste couvert par le test existant, inchangé. |
| 19. ADR 030 (renommé) et ADR 031 (US1, US10) | Dossier et format `docs/decisions/NNN-titre.md` | `docs/decisions/029-copie-mobile-glisser.md` | Numéros libres : le dernier est 029. Le doublon de numéro 013 est le seul doublon constaté. |
| 21. Retrait de deux événements de clic (US6) | Sites existants | `Sources/RoadieDaemon/DropPreviewController.swift:667`, `Sources/RoadieDaemon/RailController.swift:420` | Suppression de code. Rien n'est créé. |
| 23. Règles ajoutées à `.gitignore` (US1, US7) | Fichier existant | `.gitignore:1` | Lignes ajoutées au fichier existant. Aucun second fichier d'exclusion. |
| 24. Sections ajoutées à `AGENTS.md` (US4) | Fichier existant et ses marqueurs SpecKit ; pièges déjà notés dans les mémoires du projet | `AGENTS.md:1` | Le fichier est allégé puis complété. Les pièges reprennent `research.md` R14 ; aucun second fichier de consignes. |

## Existant potentiellement pertinent non mentionne

| Item du plan | Existant proche | Preuve | Decision attendue |
|---|---|---|---|
| 16. `.specify/memory/sessions/journal.md` (US4) | Registre des sessions en tableau, 83 lignes, et 16 fiches `session-NNN.md` | `.specify/memory/sessions/index.md:1` | Aucune : divergence justifiée dans « Arbitrages ». |

## Duplications evidentes

| Item propose | Doublon existant | Preuve | Action requise |
|---|---|---|---|
| Aucune | - | - | - |

## Memoires et regles applicables

| Source | Regle | Impact sur le plan |
|---|---|---|
| `/Users/moi/.speckit/constitution.md`, article XIX | Pas d'abstraction pour moins de 3 usages réels ; pas de dépendance sans justification | Pas d'aide partagée pour les gardes de type (2 sites). Pas de Sparkle ni de swift-argument-parser. |
| `/Users/moi/.speckit/constitution.md`, article XVIII | Annoter la complexité | `ShellCompletion.zsh` et le parcours des clés portent un commentaire `O(n)`. |
| `/Users/moi/.speckit/constitution.md`, article VII | ADR pour toute décision structurante | ADR 031 pour le premier appel réseau. |
| `/Users/moi/.speckit/constitution.md`, article XV | Tests avant de committer | Chaque user story finit par la suite complète, puis un commit. |
| `/Users/moi/.speckit/constitution.md`, article XX.6 | Pas de donnée privée vers l'extérieur | `update check` n'envoie aucune donnée de l'utilisateur. US6 retire une donnée d'usage. |
| `/Users/moi/Nextcloud/10.Scripts/39.roadie/AGENTS.md` | Conserver les preuves originales ; ne pas mettre de données privées dans Git | US11 ne retire rien. La purge automatique est exclue (D7). |
| `/Users/moi/.claude/CLAUDE.md` | Aucune trace d'IA dans Git ; message `type(scope): Description` | Messages de commit exacts dans `recettes.md` ; interdits rappelés dans `quickstart.md`. |
| Mémoire `commit-regularly` | Nommer les fichiers ; jamais `commit -a` | Chaque commit de `recettes.md` liste ses fichiers. |
| Mémoire `roadie-stale-test-build` | Signal 11 après un changement de structure de `RoadieCore` | Piège P1 de `quickstart.md`. |
| Mémoire `roadie-install-signing` | Une signature différente fait perdre l'accessibilité | Aucune installation dans les tâches ; règle écrite dans le nouvel `AGENTS.md`. |
| Mémoire `roadie-ui-language` | Le poste est en `en-US` ; `scripts/test` fixe le français | Les tests de `update check` comparent les textes français ; le contrôle réel de T040 attend le texte anglais. |

## Specs livrees applicables

| Spec | Pattern deja etabli | Impact |
|---|---|---|
| 016-roadie-stabilization | Contrat `contracts/daemon-status.md` | Réutilisé : un champ facultatif ajouté, contrat mis à jour dans la même tâche (T011). |
| 054, 059, 063, 128, 141 (releases) | Version changée dans `DaemonHealth.swift` et dans `scripts/package-dmg` | Corrigé : après US2, une publication change 1 seul fichier. |
| 093-audit-codebase et 129-corrections-audit | Gardes `knownScalarKeys()` et `ineffectiveKeys()` | Réutilisées et complétées (US3). |
| 126 et 127 (interface EN/FR) | Tout texte visible passe par `tr(fr, en)` | Réutilisé pour `update check`. |
| 145-apercu-entre-ecrans | Origine de `drag.real_press` (événement de mise au point) | Retiré (US6). |
| 152-sens-animations-stages | Origine de `drag.real_router_press` | Retiré (US6). |
| 150-raccourci-finder | Test d'une commande par `CLICommandRouter().run([...])` | Réutilisé dans les tests de la US7 et de la US10. |
| 124-doc-lanceur | Captures publiques sans donnée privée, générées par un test | US11 liste ces images sans les modifier. |

## Journal de recherche

| Requete | Portee | Resultat |
|---|---|---|
| `git grep -n "URLSession" 0b7de36b -- Sources` | `Sources/` | 0 ligne. Item 15 : `OK aucun equivalent` pour l'appel réseau. |
| `git grep -n -i "releases/latest\|api.github.com\|isNewer\|compareVersion" 0b7de36b -- Sources scripts` | `Sources/`, `scripts/` | 0 ligne. Item 17 (`ReleaseCheck.evaluate`, comparaison de versions) : `OK aucun equivalent`. |
| `git grep -n -i "compdef\|compadd" 0b7de36b -- Sources scripts Makefile` | `Sources/`, `scripts/`, `Makefile` | 0 ligne utile. Item 11 (`ShellCompletion.zsh`) : `OK aucun equivalent`. |
| `git grep -n -i "code-coverage\|llvm-cov\|profdata" 0b7de36b -- scripts Makefile Package.swift` | `scripts/`, `Makefile`, `Package.swift` | 0 ligne. Item 10 : aucune mesure de couverture existante. |
| `git ls-tree --name-only 0b7de36b .github/ docs/dev/` | racine | Aucun dossier. Item 13 (`.github/workflows/tests.yml`) et item 14 (`docs/dev/ajouter-un-reglage.md`) : `OK aucun equivalent`. |
| `git grep -n "knownKeys\|func knownScalarKeys\|func ineffectiveKeys" 0b7de36b -- Sources/RoadieCore/Config.swift` | `Sources/RoadieCore/` | Lignes 1706, 1716, 1900, 2025. Item 6 : réutilisation. |
| `git grep -n '0\.13\.0' 0b7de36b -- Sources scripts` | `Sources/`, `scripts/` | 2 lignes : `DaemonHealth.swift:325`, `scripts/package-dmg:8`. Items 1 et 4. |
| `git grep -n "rev-parse\|buildCommit\|RoadieBuildCommit" 0b7de36b -- Sources scripts` | `Sources/`, `scripts/` | 0 ligne. Aucune identité de build existante. |
| `git grep -n "Info.plist\|infoDictionary\|PropertyListSerialization" 0b7de36b -- Sources` | `Sources/` | 8 lignes dans 6 fichiers ; aucune aide partagée. Item 2. |
| `git grep -c "CFGetTypeID" 0b7de36b -- Sources` | `Sources/` | 11 fichiers ; `AppTargetQueryService.swift` : 2. Item 8. |
| `git grep -n "static let commandTable\|struct CLICommandSpec\|func usageError\|isDaemonRouted" 0b7de36b -- Sources/RoadieDaemon` | `Sources/RoadieDaemon/` | Lignes 79, 209, 319, 355. Items 9 et 15. |
| `git grep -n "drag.real_press\|drag.real_router_press" 0b7de36b -- Sources` | `Sources/` | 2 lignes. Item 21. |
| `git grep -n "class ReplayableSnapshotProvider" 0b7de36b -- Sources` | `Sources/` | 1 ligne : `LayoutMaintainer.swift:4397`. Item 12. |
| `git ls-tree --name-only 0b7de36b .specify/memory/sessions/` | `.specify/memory/` | 17 fichiers : `index.md` et 16 fiches. Item 16 : `POTENTIELLEMENT SIMILAIRE`. |
| `git ls-tree --name-only 0b7de36b docs/decisions/` | `docs/decisions/` | Dernier numéro 029 ; numéro 013 en double. Item 19. |
| `git grep -n -l -i "inventaire" 0b7de36b -- scripts` | `scripts/` | 0 fichier. Item 20 (`tools/inventaire.py`) : `OK aucun equivalent`. |
| `git ls-tree --name-only 0b7de36b scripts/` | `scripts/` | 18 entrées ; aucune n'applique des remplacements ni ne déplace un bloc. Item 22 (`tools/appliquer.py`, `tools/deplacer_journal.py`, `tools/extraire_fournisseur.py`) : `OK aucun equivalent`. Ces outils restent dans le dossier de la spec ; ils ne sont pas des scripts du produit. |
| Lecture de `Package.swift` | racine | 1 dépendance (TOMLKit). Le plan n'en ajoute aucune. |

## Arbitrages

| Sujet | Decision | Justification | Date |
|---|---|---|---|
| `journal.md` à côté de `index.md` | creer nouveau | `index.md` est un tableau à 5 colonnes, non tenu à jour depuis la session 144. Le journal d'`AGENTS.md` est un texte libre de 366 lignes. Le convertir en lignes de tableau demanderait de le réécrire : le critère SC-005 (« 0 ligne de journal perdue ») ne serait plus vérifiable par un outil. Le déplacement tel quel se vérifie contre le commit de base. Valeur par défaut modifiable par l'utilisateur (`decisions.md` D15). | 2026-11-10 |
| Aide partagée pour les gardes de type AX | creer nouveau (deux gardes en ligne) | 2 sites à corriger ; la règle du projet demande 3 usages réels (article XIX). | 2026-11-10 |
| Aide partagée pour lire un `Info.plist` | creer nouveau (lecture en ligne) | Les 3 sites existants lisent des fichiers différents avec des clés différentes, sans aide commune. En créer une toucherait du code hors périmètre. | 2026-11-10 |

Aucun arbitrage ne demande une décision de l'utilisateur.

## Gate avant tasks

- [x] Aucune duplication evidente non arbitree
- [x] Chaque item extrait du plan a une ligne d'audit
- [x] Les regles projet applicables ont ete lues
- [x] Les specs existantes proches ont ete verifiees
- [x] Le plan.md a ete refactore ou les divergences sont justifiees
