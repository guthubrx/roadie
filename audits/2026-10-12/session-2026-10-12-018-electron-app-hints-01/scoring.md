# Audit de Code - Roadie, spec 018-electron-app-hints

**Date** : 2026-10-12 21:25 UTC
**Mode** : fix (sans commit) | grid: all | scope_mode: diff (base main)
**Périmètre** : `Sources/RoadieDaemon/AppTargetQueryService.swift`, `Sources/RoadieDaemon/TargetHintService.swift`, `Tests/RoadieDaemonTests/AppTargetQueryServiceTests.swift`, `Tests/RoadieDaemonTests/TargetHintServiceTests.swift`
**Durée** : ~20 min
**Score global** : A (99,7/100)
**Coverage** : 100 %
**Cycles** : cycle-1 (audit + correction), cycle-scoring (lecture seule)

## Tendance (vs session précédente du même scope)

Première session pour ce scope. Entre cycle-1 et cycle-scoring : PERF-001 corrigé, 4 findings LOW persistants, 0 nouveau.

## Résumé exécutif

| Domaine | Note | CRIT | HIGH | MED | LOW |
|---|---|---|---|---|---|
| Sécurité | A | 0 | 0 | 0 | 0 |
| Complexité | A | 0 | 0 (1 corrigé) | 0 | 0 |
| Performance | A | 0 | 0 | 0 | 0 |
| Fiabilité | A | 0 | 0 | 0 | 1 |
| Qualité | A | 0 | 0 | 0 | 1 |
| Tests | A | 0 | 0 | 0 | 1 |
| Duplication | A | 0 | 0 | 0 | 0 |
| Minimalisme | A | 0 | 0 | 0 | 1 |
| Observabilité | A | 0 | 0 | 0 | 0 |
| LLM / UX | N/A | - | - | - | - |

Aucun finding CRITICAL ou HIGH ouvert. Release non bloquée.

Complexité algorithmique : un anti-pattern détecté puis corrigé (PERF-001, recherche linéaire dans la boucle de parcours). Après correction, périmètre vérifié, aucun anti-pattern restant. Parcours documenté O(r × n), r ≤ 3 passes, n borné par `max_targets`, `max_depth` et l'échéance.

## Findings par sévérité

### HIGH (1, corrigé)
- PERF-001 - `Sources/RoadieDaemon/AppTargetQueryService.swift:282` - `config.includeRoles.contains(role)` sur un tableau, à chaque élément lu. Corrigé : `Set` construit une fois avant la boucle (ligne 261), comme `targets(from:)`. Contre-audit : CONFIRMÉ (tableau non borné par construction, borne non documentée). Impact pratique faible : le coût est dominé par les appels AX (~0,6 ms par élément mesuré).

### LOW (4, ouverts)
- REL-001 - `AppTargetQueryService.swift:204` - une relance peut démarrer avec un budget résiduel de quelques ms. Son résultat remplace toujours la passe précédente : en timeout, le rapport devient `partial` avec moins de cibles que la passe complète d'avant. THEORETICAL : exige des appels AX lents. Correction = choix de conception (budget minimal ou garder la meilleure passe), non appliquée.
- TEST-001 - `AppTargetQueryService.swift:255` - les compteurs (`stopReason`, `atMaxDepth`, `offscreen`) et la boucle de relance ne sont couverts que par les mesures manuelles de `implementation.md`.
- QUAL-001 - `AppTargetQueryService.swift:252` - `stopReason` et `manualAccessibility` en chaînes libres ; un `enum String` garderait le même JSON.
- MIN-001 - `Tests/RoadieDaemonTests/TargetHintServiceTests.swift:351` - extension `JSONDecoder.roadieTest` pour un seul usage (ligne 162).

## Détail des findings

Voir `cycle-1/aggregated-findings.json` (avec PERF-001, statut `fixed`) et `cycle-scoring/aggregated-findings.json` (état final).

## Quick Wins

| ID | Description | Effort | Impact | Fichier |
|---|---|---|---|---|
| PERF-001 | Set pour include_roles (appliqué) | XS | HIGH (conformité Art. XVIII) | AppTargetQueryService.swift:261-283 |
| MIN-001 | Décodeur créé sur place | XS | LOW | TargetHintServiceTests.swift:351 |

## Dépendances vulnérables

Aucune dépendance ajoutée ou modifiée par le diff.

## Sécurité

Pas de finding. L'événement `targets.app_scan` ne contient que l'identifiant de bundle et des compteurs, ni titre ni valeur d'élément. La demande `AXManualAccessibility` est soumise au boost existant (FR-001, FR-008) et limitée aux bundles Electron. Le chemin du bundle vient de `NSRunningApplication`, sans entrée utilisateur.

## Minimalisme & Frugalité

Checklists 1 à 6 du module 12 exécutées sur le diff.
- Lignes suppressibles : MIN-001 (~5 lignes de test). `visible.isNull ||` (ligne 140) est redondant, car `CGRect.isEmpty` est vrai pour un rectangle nul ; gain nul en lignes, lisibilité discutable, non signalé.
- Abstractions : `ScanPass` (privé) et `AppTargetScanStats` (public, init explicite requis car les tests importent le module sans `@testable`) servent chacun un besoin réel. Pas de wrapper passthrough.
- Features non demandées : aucune ; chaque élément correspond à FR-001 à FR-006. Aucune nouvelle clé de configuration (FR-008).
- Dépendances : aucune.

Potentiel minimalisme : ~5 lignes suppressibles à comportement constant

## Vertus LLM & Responsabilité Future

- Charge cognitive future : réduite. Le parcours est extrait dans `scan()`, et les règles de décision sont des fonctions pures nommées et testées. Les commentaires donnent le POURQUOI (issue Electron #37465, mesure du 2026-10-12).
- Volume justifié : +286/-31 lignes, dont ~95 de tests. Le reste couvre FR-001 à FR-006, sans option spéculative.
- Abstractions : elles servent un besoin réel ; aucune couche sans règle.
- Assumabilité : oui. Les invariants (échéance commune, relance seulement si parcours complet sans zone web) sont écrits au site et dans `research.md`. Les choix sont appuyés sur des mesures datées dans `implementation.md`.
- Zones non comprises : aucune détectée. Limite connue et documentée : la première session après le lancement d'une application Electron peut ne montrer que la fenêtre.
- Patterns LLM : pas de layercake, de tests décoratifs ni de régénération opaque. Les tests vérifient des comportements (point de clic dans la fenêtre, contenu de l'événement), pas des mocks.

## Findings supprimés par la baseline

Aucun (baseline absente). Objections déjà traitées dans `specs/018-electron-app-hints/adversarial-review-codex.md` non re-signalées.

## Points positifs

- Règles pures extraites et testées sans AX : `shouldRetryScan`, `visibleFrame`, `isElectronBundle`.
- Budget total borné par une échéance commune (`timeout_ms` + 300 ms) et délai AX de 0,5 s sur la demande.
- Événement de mesure sans donnée utilisateur, dans un journal déjà borné par rotation.
- Complexité du parcours documentée au site.

## Corrections appliquées

| ID | Fichier | Modification | Tests |
|---|---|---|---|
| PERF-001 | `Sources/RoadieDaemon/AppTargetQueryService.swift` | `let includedRoles = Set(config.includeRoles)` avant la boucle ; `includedRoles.contains(role)` dans la boucle | `./scripts/test` : 810 tests, 86 suites, exit 0 (avant et après) |

Aucun commit (consigne de l'appelant).

## Roadmap de remédiation

1. **Immédiat** : rien de bloquant.
2. **Court terme** : REL-001, à trancher avec une mesure `targets.app_scan` sur une application Electron lente.
3. **Moyen terme** : QUAL-001, MIN-001.
4. **Long terme** : TEST-001, si le parcours évolue encore.
