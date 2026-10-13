# Audit de Code - Roadie, spec 020-cef-web-hints

**Date** : 2026-10-13 05:27 UTC
**Mode** : fix (sans commit) | grid: all | scope_mode: diff (base main, merge-base `1bdd65e`)
**Périmètre** : `Sources/RoadieDaemon/AppTargetQueryService.swift`, `Tests/RoadieDaemonTests/AppTargetQueryServiceTests.swift`, `Tests/RoadieDaemonTests/TargetHintServiceTests.swift`
**Durée** : ~20 min
**Score global** : A (99,6/100)
**Coverage** : 100 %
**Cycles** : cycle-1 (audit + correction, 98,4/100), cycle-scoring (lecture seule, 99,6/100)

## Tendance (vs session précédente du même scope)

Première session pour ce scope (spec 020). Entre cycle-1 et cycle-scoring : PERF-001 corrigé, 3 findings persistants (1 MEDIUM, 2 LOW), 0 nouveau. Pour comparaison, la session 018 sur le même fichier finissait à A (99,7).

## Résumé exécutif

| Domaine | Note | CRIT | HIGH | MED | LOW |
|---|---|---|---|---|---|
| Sécurité | A | 0 | 0 | 0 | 0 |
| Complexité | A | 0 | 0 (1 corrigé) | 0 | 0 |
| Performance | A | 0 | 0 | 0 | 0 |
| Fiabilité | A | 0 | 0 | 0 | 0 |
| Qualité | A | 0 | 0 | 1 | 0 |
| Tests | A | 0 | 0 | 0 | 0 |
| Duplication | A | 0 | 0 | 0 | 0 |
| Minimalisme | A | 0 | 0 | 0 | 1 |
| Observabilité | A | 0 | 0 | 0 | 1 |
| LLM / UX | N/A | - | - | - | - |

Aucun finding CRITICAL ou HIGH ouvert. Release non bloquée.

Complexité algorithmique : un anti-pattern détecté puis corrigé (PERF-001, recherche linéaire répétée dans une boucle). Après correction, périmètre vérifié, aucun anti-pattern restant. Parcours documenté O(n + m + p + u × d) ; `leavesKeptUnderCandidates` O(f) ; `rejectedRoleSummary` O(k log k), k rôles distincts. Les huit anti-patterns du module 04 ont été vérifiés : pas de double boucle sur la même collection, pas de N+1 (un appel AX `isFocusSettable` par élément de zone web non candidat, coût mesuré et accepté dans research.md), pas de tri répété (un tri final), pas de concaténation en boucle (`joined`), pas d'I/O en boucle, pas de récursion, pas de copie en cascade.

## Findings par sévérité

### HIGH (1, corrigé)
- PERF-001 - `Sources/RoadieDaemon/AppTargetQueryService.swift:177` (avant correction) - `focusableLeaves` appelait `unexplored.contains { $0.hasPrefix(path + ".") }` pour chaque chemin en attente : O(p × u). La pile restante après un arrêt `timeout` ou `limit` n'est pas bornée par construction (une liste web de plusieurs centaines d'enfants y reste entière), et aucune borne n'était écrite. Corrigé : les ancêtres stricts de chaque chemin resté dans la pile sont ajoutés une fois au `Set` `containers` (d ≤ `max_depth`), puis le filtre de `pending` est en O(1) par élément. Comportement identique : les segments de chemin sont des entiers, donc « `u` commence par `p.` » équivaut à « `p` est un ancêtre strict de `u` ». Contre-audit : CONFIRMÉ. Impact pratique faible : le coût reste dominé par les appels AX (~0,17 ms par élément mesuré).

### MEDIUM (1, ouvert)
- QUAL-001 - `AppTargetQueryService.swift:326` - `scan()` passe de 53 à 99 lignes (seuil du module 05 : 50). Le post-traitement des feuilles (lignes 409-422 : `focusableLeaves`, `leavesKeptUnderCandidates`, ajustement de `rejectedRoles`) n'est testable qu'à travers AX. Piste : l'extraire en fonction statique pure qui retourne les indices retenus.

### LOW (2, ouverts)
- OBS-001 - `AppTargetQueryService.swift:417` - en arrêt `limit`, les cibles historiques remplissent exactement `max_targets`. `targets(from:)` les garde d'abord et coupe à `max_targets`, donc aucune feuille n'est affichée. Les feuilles sont pourtant ajoutées à `pass.candidates`, comptées dans `focusableAdded` et retirées de `rejectedRoles`. Mesure trompeuse et travail inutile, seulement dans ce cas. THEORETICAL : aucune mesure ne montre le cas (Bluejay 7 cibles historiques, T3 Code `focusableAdded=0`).
- MIN-001 - `AppTargetQueryService.swift:47` - défauts `focusableAdded: Int = 0, rejectedRoles: String = ""` jamais utilisés (deux appels, `AppTargetQueryService.swift:286-288` et `TargetHintServiceTests.swift:142-146`, passent les deux valeurs). Un futur appel pourrait oublier ces champs sans erreur.

## Détail des findings

Voir `cycle-1/aggregated-findings.json` (PERF-001 au statut `fixed`) et `cycle-scoring/aggregated-findings.json` (état final).

## Quick Wins

| ID | Description | Effort | Impact | Fichier |
|---|---|---|---|---|
| PERF-001 | Ancêtres de la pile indexés dans un Set (appliqué) | XS | HIGH (conformité Art. XVIII) | AppTargetQueryService.swift:170-185 |
| OBS-001 | Pas de sélection de feuilles en arrêt `limit` | XS | LOW | AppTargetQueryService.swift:409 |
| MIN-001 | Retirer deux valeurs par défaut | XS | LOW | AppTargetQueryService.swift:47 |

## Dépendances vulnérables

Aucune dépendance ajoutée ou modifiée par le diff.

## Sécurité

Pas de finding. Le diff ne crée ni entrée réseau ni configuration. Il lit un attribut AX de plus (`AXFocused` modifiable) sur l'application au premier plan, comme les lectures existantes. `rejectedRoles` ne journalise que des noms de rôles et des compteurs, ni titre ni valeur. Les noms de rôles viennent de l'application tierce ; leur longueur n'est pas bornée, mais l'événement JSON les échappe et le journal est déjà borné par rotation (spec 018). Aucun texte utilisateur dans les tests.

## Minimalisme & Frugalité

Checklists 1 à 6 du module 12 exécutées sur le diff.
- Lignes suppressibles : MIN-001 (0 ligne, deux valeurs par défaut). L'ajustement `rejectedRoles[...] -= 1` puis `filter { $0.value > 0 }` pourrait être remplacé par un comptage après sélection ; même nombre de lignes, non signalé.
- Abstractions : `keepsFocusableLeaf` n'a qu'un appel de production, mais il est la règle documentée de `data-model.md` et il est testé seul : justification écrite, pas de finding. `isFocusableLeaf` est nécessaire au filtre de `targets(from:)`. Le paramètre `limit` de `rejectedRoleSummary` ne varie que dans les tests ; coût nul, non signalé. Pas de wrapper passthrough.
- État dérivé : `retainedAncestor` est porté par la pile parce qu'il ne se recalcule pas sans l'arbre. Pas d'état redondant.
- Features non demandées : aucune. Chaque ajout correspond à FR-002, FR-003, FR-005. Aucune clé de configuration (FR-006).
- Dépendances : aucune.

Potentiel minimalisme : ~0 lignes suppressibles à comportement constant

## Vertus LLM & Responsabilité Future

- Charge cognitive future : légèrement augmentée dans `scan()` (QUAL-001), réduite ailleurs. Les règles sont des fonctions pures nommées, avec le POURQUOI au site (délégation des clics par SolidJS, mesure Bluejay, conteneur `AXGroup` avec `AXPress`).
- Volume justifié : +216/-19 lignes dont ~70 de tests. Le reste couvre FR-002 à FR-005, sans option spéculative. Les essais rejetés (élagage hors fenêtre, `pruned=0`) ont été retirés et documentés dans research.md.
- Abstractions : elles servent un besoin réel ; aucune couche sans règle.
- Assumabilité : oui. Les invariants (préordre, marqueurs `path.?`, priorité des cibles historiques) sont écrits au site, dans data-model.md et dans research.md. Les choix s'appuient sur des mesures datées (implementation.md, T009).
- Zones non comprises : aucune. Limite connue et écrite : heuristique sur l'arbre parcouru (alias boost, collisions `CFHash`).
- Patterns LLM : pas de layercake, pas de tests décoratifs. Les tests vérifient des comportements (feuilles retenues, cibles finales, contenu de l'événement), pas des mocks. Pas de régénération opaque.
- Incident de session : un bloc jetable `FORENSIC-020c` (écriture dans `/tmp` à chaque élément de zone web de Bluejay) a été ajouté puis retiré par un autre agent pendant l'audit. Il est absent de l'état final. À surveiller avant commit : `grep -n FORENSIC Sources/RoadieDaemon/AppTargetQueryService.swift` doit rester vide.

## Findings supprimés par la baseline

Aucun (baseline absente). Objections déjà traitées dans `specs/020-cef-web-hints/adversarial-review-codex.md` non re-signalées.

## Points positifs

- Règles de décision extraites en fonctions statiques pures et testées sans AX : `keepsFocusableLeaf`, `focusableLeaves`, `leavesKeptUnderCandidates`, `rejectedRoleSummary` (AppTargetQueryService.swift:159-207, AppTargetQueryServiceTests.swift:110-175).
- Hors zone web, aucun appel AX en plus : `isFocusSettable` n'est évalué que si l'élément est dans une zone web et n'est pas déjà candidat (AppTargetQueryService.swift:367).
- Événement `targets.app_scan` sans texte utilisateur.

## Corrections appliquées

| ID | Fichier | Modification | Tests |
|---|---|---|---|
| PERF-001 | `Sources/RoadieDaemon/AppTargetQueryService.swift` | `focusableLeaves` : ancêtres des chemins de `unexplored` ajoutés à `containers` ; filtre `pending` en O(1) ; commentaires de complexité de `focusableLeaves` et `scan` mis à jour | `./scripts/test` : 833 tests, 90 suites, exit 0 (avant et après) |
| PERF-001 (vérification) | `Tests/RoadieDaemonTests/AppTargetQueryServiceTests.swift` | une expectation : descendant profond resté dans la pile, et `0.10.0` n'est pas sous `0.1` | idem, exit 0 |

Aucun commit (consigne de l'appelant). `plan.md` (Constitution Check XVIII) annonce « règle des feuilles O(f) » : la valeur réelle est O(m + p + u × d), hors périmètre de code, à corriger dans la spec.

## Roadmap de remédiation

1. **Immédiat** : rien de bloquant.
2. **Court terme** : OBS-001, à trancher (sortir avant la sélection des feuilles en arrêt `limit`, ou documenter que `focusableAdded` compte des candidats).
3. **Moyen terme** : QUAL-001, MIN-001.
4. **Long terme** : rien.
