# Analyse par axe - diff 048 (commit ab9b28e9, readonly)

## Sécurité
Aucun point d'entrée réseau, aucune authentification, aucun secret dans le diff. Fichiers lus locaux
à l'utilisateur ; permission Screen Recording vérifiée avant capture (inchangé). Script
`mesure-repos.py` : listes d'arguments sans shell, écrit dans `/tmp/roadie-048-<étiquette>-sample.txt`
(outil manuel, hors produit). Semgrep : 1 règle Swift seulement.

## Logique et données
Invariants 1-7 de `contexte.md`. F2/F4 réfutés (`constats.md`). Cas limites relus : `max(0, cap)`,
`age >= 0`, absence 5 s, capture nil, écran masqué (signature `hidden=` au réaffichage).

## Concurrence
`observation` et `quietReuseCap` sous `NSLock`. Lecteurs, ordonnanceur et `RailThumbnailStore` sur
MainActor ; un seul lot de capture (`inFlight`, `defer`). Ordonnancement : événement pendant une
acquisition détachée -> génération +1 -> publication avec l'ancienne génération -> pas de réutilisation
silencieuse au-delà de 150 ms. Non couvert par un test dédié.

## Complexité et performance
| Fonction | Complexité | Borne |
|---|---|---|
| `recentSnapshot`, `noteObservationChange`, `enableQuietReuse` | O(1) | - |
| `needsEnumeration` + `Set(shareableWindows.keys)` | O(k + n) | k <= budget ; n réduit par `prune` |
| `liveFrames` | O(w) | w = fenêtres du relevé |
| `refreshThumbnails` | O(c x m) | cartes x membres d'un écran |
| `updateThumbnails` | O(m) | membres d'une carte |
| `recordingStatus` | O(1) + `kill(pid, 0)` | - |
| `JSONPersistence.read` inchangé | O(1) syscalls | - |
Aucune boucle imbriquée sur la même collection, aucun N+1. Annotations de complexité présentes.
Mesures avant/après de la session relues (`mesures/*.json`), non rejouées.

## Tests
Tests 048 sur le vrai `SnapshotService`, le vrai `TickScheduler`, de vraies vues. Manques : événement
pendant l'acquisition, intégration `renderPanels` -> `refreshThumbnails`, redémarrage du rail (F1),
chemins d'échec de capture. Le test de carte exige un écran. Pas de linter dans le projet.

## Architecture
Deux API publiques sur `SnapshotService`, rappel injecté dans `TickScheduler` avec défaut sans effet,
câblage dans la racine de composition. Aucune dépendance de module, aucun cycle (lecture des imports).
Risque d'assemblage : une composition qui active la réutilisation sans brancher le rappel garderait des
relevés jusqu'à 2 s ; lien documenté (ADR 015), non testé.

## Minimalisme et frugalité
Checklist : lignes supprimables ~2 (`@discardableResult` et retour `Bool` de `updateThumbnails`,
utilisés par un seul test) ; aucun helper sans règle ; aucun état dérivé redondant ; aucune abstraction
prématurée ; aucune dépendance ; aucun changement hors périmètre. Méthode : relecture ligne à ligne du
diff source, tests exclus.

## Vertus LLM et responsabilité future
Charge cognitive réduite : une règle (génération + plafond = filet) écrite dans l'ADR 015 avec ses
conséquences négatives. Invariants explicables. Volume justifié par une mesure avant/après. La session
antérieure avait confirmé à tort F2/F4 faute d'avoir suivi `JSONPersistence.read` ; `validation.md`
documente la réfutation. Traçabilité : `.gitignore` exclut désormais `audits/**/runs/` et
`audits/**/configs/` ; la session d'audit versée ne peut donc pas être revalidée depuis Git seul
(preuves `runs/*/run.json` absentes d'un clone). Cet audit n'est pas indépendant.

## Observabilité
Aucun journal ajouté ; aucune donnée sensible. Réessais bornés (5 s, intervalle de capture). Manque :
compteur des réutilisations silencieuses et des énumérations SCK (recommandation INFO).
