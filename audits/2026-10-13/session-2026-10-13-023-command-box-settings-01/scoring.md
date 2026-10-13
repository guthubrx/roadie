# Audit de code v14 - Roadie, feature 023 (boîte de commandes et fenêtre de réglages)

**Date** : 2026-10-13
**Mode** : fix (MAX_CYCLES=1) puis cycle final en lecture seule | grille : all, périmètre restreint | scope_mode : diff `acc10e13..HEAD`
**Session** : `/Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/023-command-box-settings/audits/2026-10-13/session-2026-10-13-023-command-box-settings-01/`
**Score global** : A (98,9 pondéré) - aucun constat critique ou élevé, `release_blocked = false`
**Coverage** : 100 % du périmètre restreint (lecture intégrale des 10 fichiers neufs et des diffs des 5 fichiers modifiés)

Raccourcis assumés (borne de 45 minutes) : modules 03 à 08 et 12 exécutés par lecture directe, sauf le module 06 (tests) confié à un sous-agent en lecture seule puis recoupé. Pas de jscpd (duplication par lecture et grep). Les données des catalogues (`SettingsCatalog.swift`, `SettingsCatalogRail.swift`) ont été survolées : leurs défauts et plages sont couverts par les tests de dérive. Docs et `examples/roadies.toml` non relus en détail.

## Tendance (vs session précédente du même scope)

Première session pour ce scope. Aucune baseline (`audits/baseline.json` absent) : section « supprimés » vide.

| Domaine | Précédent | Actuel | Delta constats |
|---------|-----------|--------|----------------|
| Global  | -         | A      | 18 relevés au cycle 1, 9 corrigés, 9 restants |

## Résumé exécutif

Notes du cycle final (constats restants seulement) :

| Domaine       | Note | CRIT | HIGH | MED | LOW |
|---------------|------|------|------|-----|-----|
| Sécurité      | A    | 0    | 0    | 0   | 0   |
| Qualité       | A    | 0    | 0    | 0   | 0   |
| Complexité    | A    | 0    | 0    | 1   | 0   |
| Performance   | A    | 0    | 0    | 0   | 0   |
| Tests         | A    | 0    | 0    | 2   | 4   |
| Duplication   | A    | 0    | 0    | 0   | 0   |
| Minimalisme   | A    | 0    | 0    | 0   | 2   |
| Fiabilité     | A    | 0    | 0    | 0   | 0   |

Constats du cycle 1 : 0 CRITICAL, 0 HIGH, 5 MEDIUM, 13 LOW (18). Corrigés : 1 MEDIUM qualité, 1 MEDIUM tests, 7 LOW. Restants : 3 MEDIUM, 6 LOW.

**Top à traiter** :
1. PERF-001 - relecture du fichier entier pour chaque réglage affiché, à chaque prise de focus (O(v·L)).
2. TEST-004 - SC-004 : effet de `/send`, `/desktop`, `/split`, `/stage send` non testé par le lanceur.
3. TEST-005 - enchaînement session/boîte (`handleCommand`, `execute`) non testé.

**Dette technique** : faible. **Hotspots** : `TargetOverlayPresenter.swift` (+524 lignes, aiguillage clavier), `SettingsService.swift` (écriture du fichier), `ConfigFileEditor.swift` (automate TOML).

## Sécurité (module 03)

Aucun constat. Points vérifiés dans le code :
- Écriture du fichier : candidat créé dans le dossier de la cible réelle (lien symbolique suivi, lien conservé), fichier de départ puis candidat validés, relecture juste avant `rename` atomique, sauvegarde unique par instance, mode et propriétaire recopiés (`SettingsService.swift:157-246`).
- Injection dans le littéral TOML : `quoted()` échappe `\` et `"` ; sauts de ligne refusés (`isNewline`, donc `\r` aussi) ; caractères de contrôle refusés par la validation du candidat (prouvé par un test ajouté) ; choix et couleurs bornés par le catalogue.
- Journal : nom du réglage ou de la commande et code de résultat seulement, jamais la valeur ni la saisie (`SettingsService.swift:268`, `SlashCommandRunner.swift:236`, `runDeferred` : `argv.first`).
- Handlers de touches : en mode commande toute touche sans Commande est retenue ; état lu par le tap sous `OSAllocatedUnfairLock`, remis à `.search` au nettoyage.
- Historique persistant des commandes (`~/.local/state/roadies/command-history.json`) : exigé par FR-007, hors journal.

## Findings par sévérité (cycle 1)

### MEDIUM (5)
- QUAL-001 - couleur acceptée avec chiffres pleine chasse - **corrigé**
- TEST-001 - rechargement après écriture (FR-013) jamais vérifié - **corrigé**
- PERF-001 - O(v·L) dans `loadVisibleValues` - ouvert
- TEST-004 - SC-004, effets non testés - ouvert
- TEST-005 - collage session/boîte non testé - ouvert

### LOW (13)
- DUP-001, DUP-002, DUP-003, MIN-001, MIN-002, TEST-002, TEST-003 - **corrigés**
- TEST-006, TEST-007, TEST-008, TEST-009, MIN-003, MIN-004 - ouverts

## Détail des findings

Corrigés au cycle 1 :

| ID | Fichier:ligne (avant correction) | Correction | Preuve |
|----|----------------------------------|------------|--------|
| QUAL-001 | `Sources/RoadieDaemon/SettingsService.swift:324` | `digits.allSatisfy({ $0.isASCII && $0.isHexDigit })` | `"ＦＦＦＦＦＦ".allSatisfy(\.isHexDigit)` = true et `UInt64(_, radix: 16)` = nil (script exécuté) ; cas ajouté à `SettingsServiceTests.conversions` |
| DUP-001 | `Sources/RoadieDaemon/SettingsView.swift:257` | `NSColor(hex:).map { Color(nsColor: $0) }`, extension `Color.init?(hex:)` supprimée | build et suite verts |
| DUP-002 | `Sources/RoadieDaemon/SlashCommandRunner.swift:289` | `commandName` appelle `SlashCommandCatalog.command(named:)` (devenue interne) | `SlashCommandRunnerTests` verts |
| DUP-003 | `Sources/RoadieDaemon/SettingsViewModel.swift:137` | `rangeText` appelle `SettingsService.display(_ range:)` (devenues internes) | `SettingsViewModelTests` verts |
| MIN-001 | `Sources/RoadieDaemon/SlashCommandRunner.swift:116` | `currentStages` calculé une fois | `SlashCommandRunnerTests` verts |
| MIN-002 | `Sources/RoadieDaemon/SlashCommandModel.swift:31` | `maxHistory = CommandHistoryStore.maxEntries` | `SlashCommandModelTests` verts |
| TEST-001 | `Tests/RoadieDaemonTests/SettingsServiceTests.swift:82` | nouveau test `reloadRunsOnlyAfterAnActualWrite` | 1 rechargement après `set`, aucun après refus, 1 après `reset`, aucun après `reset` sans effet |
| TEST-002 | `Tests/RoadieDaemonTests/SettingsViewModelTests.swift:75` | assertion préalable : au moins une section avec une entrée en lecture seule | test vert |
| TEST-003 | `Tests/RoadieDaemonTests/SettingsServiceTests.swift:324` | refus testés : `a\rb`, `a\u{1B}b`, `#ＡＢＣＤＥＦ` | tests verts |

Ouverts (raison de non-correction) :

| ID | Fichier:ligne | Constat | Raison |
|----|---------------|---------|--------|
| PERF-001 | `Sources/RoadieDaemon/SettingsViewModel.swift:103` | Chaque réglage visible reparcourt tout le fichier (`readLiteral`, ~2 ms selon le commentaire du code). La catégorie Rail (75 réglages et plus) coûte environ 0,15 s à chaque prise de focus et à chaque changement du fichier. | Le compromis est documenté et n est borné (179), mais le chemin est interactif. La correction demande une nouvelle API de parcours unique dans `ConfigFileEditor`, avec les mêmes règles de refus. Ce n'est pas une correction non ambiguë. Mesure avant/après requise (constitution XXII). |
| TEST-004 | `Tests/RoadieDaemonTests/SlashCommandRunnerTests.swift:96` | Pas de test d'effet pour `/send`, `/desktop`, `/split` et `/stage send`. Pour `/max` et `/balance`, seul le succès est vérifié. | Ajout de tests d'effet avec le faux fournisseur : travail de test, hors correction directe. |
| TEST-005 | `Tests/RoadieDaemonTests/CommandBoxSessionTests.swift:24` | `TargetSearchSession.handleCommand` et `execute` ne sont pas testés. | Il faut d'abord extraire une fonction pure. Petite restructuration à décider. |
| TEST-006 | `Tests/RoadieDaemonTests/SettingsServiceTests.swift:476` | Assertion tautologique sur `SettingsService.shared`. | Supprimer ou remplacer un test est un choix de l'auteur. |
| TEST-007 | `Tests/RoadieDaemonTests/SettingsServiceTests.swift:220` | Attendu construit avec `readLiteral`. | Il faut réécrire 20 lignes attendues en dur. |
| TEST-008 | `Tests/RoadieDaemonTests/SettingsCatalogTests.swift:35` | L'attendu recopie la correspondance des alias. | Il faut une table littérale. |
| TEST-009 | `Sources/RoadieDaemon/SettingsWindowController.swift:36` | La surveillance du fichier et du dossier (FR-018) n'est pas testée. | Il faut un test asynchrone sur des événements du système de fichiers. |
| MIN-003 | `Tests/RoadieDaemonTests/SettingsCatalogTests.swift:23` | Assertion arithmétiquement redondante. | Reste un choix de l'auteur du test. |
| MIN-004 | `Sources/RoadieDaemon/ConfigFileEditor.swift:113` | `countArrayTables` est public et ne sert qu'aux tests. | Il faut passer `ConfigFileEditorTests` en `@testable import`. Changement d'API à valider. |

## Contre-audit (Phase 2bis)

Aucun constat CRITICAL ou HIGH : aucun verdict `counter_audit` requis. Les candidats écartés sont les suivants :
- « Le mode 0644 dépend du umask » (proposé par le sous-agent tests) est **réfuté**. `SettingsService.swift:238` pose `0o644` explicitement quand le fichier est créé.
- « `.labelCharacter` est du code mort en mode commande » est **réfuté**. Ce cas est atteignable quand une frappe Maj + lettre est décodée avec l'ancien `keyMode`, avant que `render()` ait basculé le mode. Le traitement `type(value.uppercased())` est donc utile.
- Le lien symbolique cassé et le nom du fichier candidat sont **théoriques**. Une attaque exige l'écriture dans le dossier de configuration de l'utilisateur. Aucune frontière de privilège n'est franchie.

## Quick Wins

| ID | Description | Effort | Impact | Fichier |
|----|-------------|--------|--------|---------|
| MIN-003 | Supprimer l'assertion redondante | XS | faible | `Tests/RoadieDaemonTests/SettingsCatalogTests.swift` |
| TEST-006 | Remplacer par une assertion d'identité | XS | faible | `Tests/RoadieDaemonTests/SettingsServiceTests.swift` |
| TEST-008 | Table littérale des alias | XS | faible | `Tests/RoadieDaemonTests/SettingsCatalogTests.swift` |

## Complexité algorithmique (module 04, Article XVIII)

Périmètre vérifié :
- double boucle ;
- recherche linéaire en boucle ;
- N+1 et entrées-sorties répétées ;
- tri répété ;
- concaténation en boucle ;
- récursion ;
- copies en cascade ;
- annotations des fonctions publiques.

Un seul anti-pattern actif : **PERF-001**. Chaque réglage visible déclenche une recherche linéaire sur le fichier entier, donc O(v·L) au lieu de O(L + v). Le compromis est documenté dans le code, mais il touche un chemin interactif.

Points vérifiés sans constat :
- Le filtre de recherche `SettingsCatalog.search` est en O(n·m), avec n ≤ 179. Les textes sont normalisés une seule fois (`searchTexts`).
- Les `suggestions` à chaque frappe sont en O(n·m) avec n ≤ 179. Le coût reste de l'ordre de la microseconde.
- `find(id:)` est en O(n), mais n'est pas appelé dans une boucle.
- `SettingsService.write` fait un nombre constant de parcours O(L) par tentative, avec deux tentatives au plus.
- `unknownSetting` (distance d'édition) ne s'exécute que lors d'une erreur.
- Toutes les fonctions publiques du périmètre ont une annotation de complexité.

## Minimalisme & Frugalité (axe OBLIGATOIRE - Article XIX)

La checklist du module 12 a été exécutée. Six points sont corrigés : 2 calculs ou constantes en double, 3 duplications de logique et 1 extension de couleur redondante. Le diff de production est de +15/−23 lignes sur `Sources/`, soit 8 lignes nettes retirées (dont 2 lignes de commentaire ajoutées). Deux points restent ouverts :
- MIN-003, l'assertion redondante ;
- MIN-004, le passe-plat public utilisé seulement par les tests.

Aucune feature non demandée et aucune dépendance ajoutée. `ConfigFileEditor` n'a qu'un consommateur réel, ce qui est assumé et justifié dans `reuse-audit.md` (FR-024, testabilité sans entrées-sorties). Les wrappers publics `RoadieConfigLoader.ineffectiveKeys()` et `editDistance` exposent une table privée existante, ce qui évite une seconde implémentation. C'est acceptable.

Potentiel minimalisme : ~5 lignes suppressibles à comportement constant (restant après corrections ; 8 lignes nettes déjà retirées au cycle 1)

## Vertus LLM & Responsabilité Future (axe OBLIGATOIRE - Article XX)

Le changement réduit la charge cognitive future. Les règles de l'éditeur TOML, de l'écriture atomique et du décodage des touches sont expliquées au point d'usage. Chaque refus a un cas de test. Les complexités sont annotées.

Le volume reste justifié : environ 3 000 lignes de sources pour 21 commandes, 179 réglages et une fenêtre. Les catalogues sont des données déclaratives.

Les abstractions répondent à des besoins réels. `SlashCommandModel` et `SearchBarLayout` sont purs et testables. `CommandBoxFollowUp` encode un ordre critique (R2) et a un test.

Le code peut être expliqué et assumé par son auteur. Les compromis sont écrits dans le code : fenêtre résiduelle avant `rename`, diagnostic synchrone et coût de `readLiteral`.

Motifs LLM relevés :
- tests partiellement décoratifs (TEST-006, TEST-007, TEST-008, MIN-003) ;
- aucun empilement de couches (layercake) ;
- aucune régénération opaque.

## Findings supprimés par la baseline

Aucun (pas de baseline).

## Points positifs

- Écriture du fichier robuste et testée : non-UTF-8 laissé intact, fichier de départ invalide refusé, lien et mode conservés, aucun candidat résiduel (`Tests/RoadieDaemonTests/SettingsServiceTests.swift:363-442`).
- Tests de dérive du catalogue contre le validateur et les bornes du chargeur (`Tests/RoadieDaemonTests/SettingsCatalogTests.swift`).
- Journal conforme à FR-029, sans valeur ni saisie brute.
- État du tap clavier protégé par `OSAllocatedUnfairLock` ; watchers arrêtés à la fermeture ; fenêtre réutilisée (`isReleasedWhenClosed = false`), sans fuite.

## Tests lancés

- Référence : `./scripts/test --scratch-path /tmp/roadie-build-023-base` donne 1057 tests dans 102 suites, tous réussis.
- Ciblés après corrections : `./scripts/test --scratch-path /tmp/roadie-build-023-base --filter "SettingsServiceTests|SettingsViewModelTests|SlashCommandRunnerTests|SlashCommandModelTests|SlashCommandCatalogTests"` donne 108 tests, tous réussis.
- Suite complète après corrections, même commande sans filtre : 1058 tests dans 102 suites, tous réussis. Aucun nouvel avertissement de compilation sur les fichiers du périmètre.

## Roadmap de remédiation

1. **Court terme** : PERF-001 (mesurer, puis parcours unique), TEST-004, TEST-005.
2. **Moyen terme** : TEST-006, TEST-007, TEST-008, TEST-009.
3. **Long terme** : MIN-003, MIN-004.
