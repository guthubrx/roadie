# Audit de Code - Roadie, spec 020-cef-web-hints (2e audit)

**Date** : 2026-10-13 05:48 UTC
**Mode** : fix (sans commit) | grid: all | scope_mode: diff (base main, merge-base `1bdd65e`)
**Périmètre** : `Sources/RoadieDaemon/AppTargetQueryService.swift`, `Tests/RoadieDaemonTests/AppTargetQueryServiceTests.swift`, `Tests/RoadieDaemonTests/TargetHintServiceTests.swift`
**Durée** : ~10 min
**Score global** : A (99,7/100)
**Coverage** : 100 %
**Cycles** : cycle-1 (audit + correction, 99,4/100), cycle-scoring (lecture seule, 99,7/100)

## Tendance (vs session précédente du même scope)

Session précédente : `session-2026-10-13-020-cef-web-hints-01` (A, 99,6). Le code a changé depuis (T012).

| Domaine | Précédent | Actuel | Delta findings |
|---|---|---|---|
| Global | A (99,6) | A (99,7) | 3 -> 1 ouvert |
| Qualité | A | A | QUAL-001 persistant (99 -> 109 lignes ; empreinte changée car l'extrait a changé) |
| Observabilité | A | A | OBS-001 (`73c6ca37fd72`) corrigé par T012(d), hors audit |
| Minimalisme | A | A | MIN-001 (`ef18c4ac8f7a`) persistant puis corrigé dans cette session |
| Tests | A | A | TEST-001 (`d5d0f3305e84`) nouveau, corrigé dans cette session |
| Complexité | A | A | PERF-001 (`964d3b8de24d`) reste corrigé (`focusableLeaves`, lignes 170-185) |

## Résumé exécutif

| Domaine | Note | CRIT | HIGH | MED | LOW |
|---|---|---|---|---|---|
| Sécurité | A | 0 | 0 | 0 | 0 |
| Complexité | A | 0 | 0 | 0 | 0 |
| Performance | A | 0 | 0 | 0 | 0 |
| Fiabilité | A | 0 | 0 | 0 | 0 |
| Qualité | A | 0 | 0 | 1 | 0 |
| Tests | A | 0 | 0 | 0 (1 corrigé) | 0 |
| Duplication | A | 0 | 0 | 0 | 0 |
| Minimalisme | A | 0 | 0 | 0 | 0 (1 corrigé) |
| Observabilité | A | 0 | 0 | 0 | 0 |
| LLM / UX | N/A | - | - | - | - |

Aucun finding CRITICAL ou HIGH. Pas de contre-audit Phase 2bis requis. Release non bloquée.

Complexité algorithmique : périmètre vérifié, aucun anti-pattern détecté. Les huit anti-patterns du module 04 ont été vérifiés sur le nouveau code. `CFIdentitySet.insert` fait une recherche linéaire dans un seul seau de hash : O(c) sur c collisions, annoté au site (ligne 246) et borné par mesure (12 collisions sur Bluejay). `scan` reste O(n + m + p + u × d) ; la boucle finale des feuilles est O(p) ; `duplicatesTarget`, `isHintable` et `hidesContent` sont O(1). Pas de N+1 nouveau : le cadre lu pour chaque élément de zone web (2 appels AX, ligne 403) est mesuré (parcours complet Bluejay en 463 ms) et validé. Pas de tri répété, pas de concaténation en boucle, pas de récursion, pas de copie en cascade.

## Findings par sévérité

### MEDIUM (2 : 1 ouvert, 1 corrigé)
- QUAL-001 (ouvert, persistant) - `Sources/RoadieDaemon/AppTargetQueryService.swift:356` - `scan()` passe de 99 à 109 lignes (seuil 50). Les règles élémentaires de T012 sont pures et testées, mais leur combinaison n'est testable qu'à travers AX. La condition de descente de la ligne 440 et la limite `max_targets` des feuilles (ligne 457) n'ont aucun test.
- TEST-001 (corrigé) - `Tests/RoadieDaemonTests/AppTargetQueryServiceTests.swift:186` - `identitySetUsesRealEqualityNotOnlyTheHash` ne contenait aucune paire « même hash, objets différents ». L'ancien `Set<CFHashCode>` donnait le même résultat `[true, false, true, true]`. Un retour au hash seul, donc au défaut qui retirait toute la zone de contenu Bluejay, passait le test.

### LOW (1, corrigé)
- MIN-001 (corrigé, persistant depuis la session 01) - `Sources/RoadieDaemon/AppTargetQueryService.swift:47` - défauts `focusableAdded: Int = 0, rejectedRoles: String = ""` jamais utilisés : les deux appels (`AppTargetQueryService.swift:313`, `TargetHintServiceTests.swift:142`) passent les deux valeurs.

## Détail des findings

Voir `cycle-1/aggregated-findings.json` (TEST-001 et MIN-001 au statut `fixed`) et `cycle-scoring/aggregated-findings.json` (état final).

- QUAL-001 : extraire le post-traitement (lignes 452-462) et le prédicat de descente (ligne 440) en fonctions statiques pures, puis les tester sans AX. Non appliqué : c'est un choix de structure.
- TEST-001 : preuve par mesure. Deux `CFString` de 149 caractères qui diffèrent en position 48 ont le même `CFHash` et `CFEqual` faux (CFString ne hache que le début, le milieu et la fin d'une longue chaîne). Simulation de l'ancien `Set<CFHashCode>` sur les nouvelles entrées : `[true, false, true, true, true, false]`. Le test échoue donc en cas de régression. Le test vérifie aussi l'égalité des hash, pour signaler un changement de l'algorithme CFString.

## Quick Wins

| ID | Description | Effort | Impact | Fichier |
|---|---|---|---|---|
| TEST-001 | Paire en collision dans le test de `CFIdentitySet` (appliqué) | XS | MEDIUM (protège T012(a)) | AppTargetQueryServiceTests.swift:185-201 |
| MIN-001 | Retrait de deux valeurs par défaut (appliqué) | XS | LOW | AppTargetQueryService.swift:47 |

## Dépendances vulnérables

Aucune dépendance ajoutée ou modifiée par le diff.

## Sécurité

Pas de finding. Le diff ne crée ni entrée réseau ni configuration. `CFIdentitySet` garde une référence forte à chaque élément AX lu pendant un parcours : mémoire O(n), n borné par `timeout_ms` et `max_targets`, libérée à la fin du parcours. Ces références évitent aussi qu'une adresse libérée soit réutilisée par un autre élément. `rejectedRoles` ne journalise toujours que des noms de rôles et des compteurs.

## Minimalisme & Frugalité

Checklists 1 à 6 du module 12 exécutées sur le diff.
- Lignes suppressibles : MIN-001 corrigé (0 ligne, deux valeurs par défaut). Dans `duplicatesTarget` (ligne 195), la garde `!overlap.isNull` est redondante : une intersection vide a une surface nulle, donc le test `>= 0.8 * ancestorArea` est déjà faux. C'est une condition, pas une ligne ; non signalé.
- Abstractions : `CFIdentitySet` a 3 usages réels (parcours ligne 362, `copyChildren` ligne 538, test). Il porte une règle de justesse mesurée (collisions `CFHash`), pas un wrapper passthrough. `isHintable` et `hidesContent` sont des règles nommées et testées, avec la mesure qui fixe leur seuil. `leavesKeptUnderCandidates` a été supprimé au profit de `duplicatesTarget` : le diff retire une règle au lieu d'en empiler une.
- Le seuil de 4 points existe à deux endroits (`isHintable` et `TargetOverlayPresenter.swift:878`). Le commentaire de la ligne 199 renvoie à l'autre site. Partager la fonction toucherait un fichier hors périmètre ; non signalé.
- État dérivé : `retainedFrame` est porté par la pile car il ne se recalcule pas sans l'arbre. Pas d'état redondant.
- Features non demandées : aucune. Chaque ajout de T012 répond à un constat mesuré (research.md, « Corrections après retour utilisateur »). Aucune clé de configuration.
- Dépendances : aucune.

Potentiel minimalisme : ~0 lignes suppressibles à comportement constant

## Vertus LLM & Responsabilité Future

- Charge cognitive future : stable. `scan()` grossit encore (QUAL-001). En contrepartie, la règle par comptage, difficile à raisonner (contre-revue round 4), est remplacée par une décision locale de surfaces, plus simple à expliquer.
- Volume justifié : +74 lignes depuis la session 01, dont ~30 de tests. Chaque ajout correspond à un défaut observé sur la page Abonnements (12 éléments écartés par hash, ~1 000 éléments à 1 point, barre de 4 points dans les cartes).
- Abstractions : elles servent un besoin réel et mesuré. Pas de couche sans règle.
- Assumabilité : oui. Chaque seuil a son POURQUOI au site, avec la mesure (Bluejay) et le renvoi à research.md. Les seuils sont validés par l'utilisateur.
- Patterns LLM : un test décoratif a été trouvé et corrigé (TEST-001). Il vérifiait la déduplication d'égaux, ce que l'ancien code faisait déjà, et non la collision de hash qui motivait le changement. Pas de layercake, pas de régénération opaque.
- Non vérifié par cet audit : le comportement réel sur Bluejay après correction (aucune mesure AX relancée ; le code de production n'a changé que par la signature de `AppTargetScanStats.init`).

## Findings supprimés par la baseline

Aucun (baseline absente). Objections déjà traitées dans `specs/020-cef-web-hints/adversarial-review-codex.md` et choix validés par l'utilisateur non re-signalés.

## Points positifs

- Seuil d'affichage partagé et écrit : `isHintable` (AppTargetQueryService.swift:201) reprend la garde `> 4` de `TargetOverlayPresenter.swift:878`, avec le renvoi au site.
- Règles T012 extraites en fonctions statiques pures et testées sans AX : `duplicatesTarget`, `isHintable`, `hidesContent`, `CFIdentitySet` (AppTargetQueryService.swift:191-259).
- OBS-001 de la session 01 corrigé par T012(d) : les feuilles ne s'ajoutent que sous `max_targets` (ligne 457), donc `focusableAdded` ne compte plus de feuilles sans lettre.

## Corrections appliquées

| ID | Fichier | Modification | Tests |
|---|---|---|---|
| TEST-001 | `Tests/RoadieDaemonTests/AppTargetQueryServiceTests.swift` | paire de `CFString` en collision de hash, précondition `CFHash` égaux, attendu étendu | `./scripts/test` : 836 tests, 90 suites, exit 0 |
| MIN-001 | `Sources/RoadieDaemon/AppTargetQueryService.swift` | `focusableAdded: Int, rejectedRoles: String` sans valeur par défaut | idem |

Aucun commit (consigne de l'appelant). Hors périmètre de code : `specs/020-cef-web-hints/plan.md:28` annonce toujours « règle des feuilles O(f) » ; la valeur réelle est O(m + p + u × d).

## Roadmap de remédiation

1. **Immédiat** : rien de bloquant.
2. **Court terme** : rien.
3. **Moyen terme** : QUAL-001 (extraire et tester le post-traitement et le prédicat de descente).
4. **Long terme** : rien.
