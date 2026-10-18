# Analyse par axe - diff 048 (révision 1)

## Sécurité et frontières de confiance

Aucun point d'entrée réseau, aucune authentification, aucun secret dans le diff. Les fichiers lus
(`recording.json`, `stages.json`, `rail.json`) et la commande `ScreenCaptureKit` restent locaux à
l'utilisateur ; la permission Screen Recording est vérifiée avant capture (`CGPreflightScreenCaptureAccess`,
inchangé). Le script `mesures/mesure-repos.py` exécute `ioreg`, `pgrep`, `ps`, `sample` avec des listes
d'arguments (pas de shell) et écrit dans `/tmp/roadie-048-<étiquette>-sample.txt` (chemin prévisible,
outil manuel mono-utilisateur, hors produit livré). Aucune frontière d'autorisation modifiée.

## Logique et données

Voir `contexte.md` (invariants 1-6) et `spec-matrice.md`. Constats F1 (corrigé), F2, F4.
Cas limites relus : plafond `quietReuseCap = max(0, cap)` ; `age >= 0` conservé ; filet borné
à 100 ms minimum (`main.swift:577`) ; ID absent mis en attente 5 s ; capture nil retire le cache ;
écran masqué : pas de rafraîchissement partiel, signature `hidden=` force le rendu au réaffichage.

## Concurrence

`observation` et `quietReuseCap` sous `NSLock`, comme `published`. Lecteurs et ordonnanceur sur
MainActor. Ordonnancement vérifié : événement AX pendant l'acquisition détachée -> génération +1 sur
MainActor -> publication avec l'ancienne génération -> pas de réutilisation silencieuse. Relevé du
tiler synchrone sur MainActor : un événement est livré après la publication, même effet.
`RailThumbnailStore` est `@MainActor` ; un seul lot à la fois (`inFlight`) ; `prune` peut intervenir
pendant un `await` : sans effet sur la correction (entrée retirée ou réécrite au lot suivant).

## Complexité et performance

| Fonction | Complexité | Borne |
|---|---|---|
| `recentSnapshot`, `noteObservationChange`, `enableQuietReuse` | O(1) | - |
| `needsEnumeration` | O(k) + construction `Set(shareableWindows.keys)` O(n) | k <= budget de capture ; n = fenêtres système juste après énumération, puis membres représentés après `prune` ; un lot à la fois |
| `liveFrames` (renderPanels) | O(w) | w = fenêtres du relevé |
| `refreshThumbnails` | O(c x m) | cartes x membres d'un écran |
| `updateThumbnails` | O(m) | membres d'une carte |
| `recordingStatus` | O(1) + `kill(pid, 0)` | - |

Aucune boucle imbriquée sur la même collection, aucune recherche linéaire répétée, aucun N+1.
Commentaires de complexité présents sur les fonctions ajoutées. Reste : I/O périodique F2 (1 s) et F4
(0,15 s, hors diff). Mesure avant/après conservée par la session 048 (XXII), non refaite ici.

## Architecture

Deux API publiques ajoutées à `SnapshotService` (`noteObservationChange`, `enableQuietReaderReuse`) ;
`TickScheduler` reçoit un rappel injecté, défaut sans effet. Pas de nouvelle dépendance de module, pas
de cycle : `roadied/main.swift` relie ordonnanceur et service, comme pour `isBlocked`. Le choix
« génération distincte de `PlacementGeneration` » est documenté (reuse-audit.md) et cohérent.

## Minimalisme et frugalité

Checklist exécutée sur le diff (430 lignes ajoutées, 35 retirées, dont 201 de tests et 48 de docs) :
- Lignes supprimables à comportement constant : `@discardableResult` et le retour `Bool` de
  `updateThumbnails` (utilisés par un seul test, ~2 lignes) ; `SnapshotService.noteObservationChange`
  est un relais vers un état privé (nécessaire, non supprimable).
- Helpers sans règle : aucun ; `recordingStatus` statique sert la testabilité (3 tests).
- État dérivé redondant : aucun ; `lastThumbnailSignatures` n'est pas dérivable de `lastRenderSignatures`.
- Abstractions prématurées : aucune. Dépendances : aucune ajoutée. Hors périmètre : aucun.
Potentiel minimalisme : ~2 lignes suppressibles à comportement constant (méthode : relecture ligne à ligne du diff source, tests exclus).

## Vertus LLM et responsabilité future

Le changement réduit la charge future : une règle unique (génération + plafond = filet), écrite dans
l'ADR 015 avec ses conséquences négatives. Les invariants sont explicables (génération lue au départ).
Volume justifié : 4 mécanismes ciblés, mesurés avant/après. Point faible : texte du plan resté sur
l'ancienne valeur (F3, corrigé) et R3 annoncée sans réserve (F2). Revue du plan et de l'implémentation
par un autre modèle (Claude Haiku) documentée dans validation.md ; cet audit n'est pas indépendant.

## Observabilité et exploitation

Aucun journal ajouté ou retiré ; aucune donnée sensible journalisée. Aucune file ou retry sans borne :
réessai d'énumération borné par `absentRetryInterval` (5 s) et par l'intervalle de capture. Manque :
aucun compteur de réutilisations silencieuses ni d'énumérations SCK ; la vérification en production
dépend de `sample` (script de mesure). Recommandation INFO, non bloquante.

## Tests

Les tests 048 exercent le produit (vrai `SnapshotService` avec fournisseur compteur, vrai `RailPanel`,
vraie `StageCardView`, vrai `TickScheduler`). Mutations rapportées par validation.md (3 échecs) non
rejouées ici. Manques : pas de test « événement pendant l'acquisition » (invariant de l'ADR 015), pas de
test d'intégration `renderPanels` -> `refreshThumbnails`, pas de test du redémarrage du rail (F1 :
validé par lecture, compilation et suite complète). Le test de carte exige un écran (`NSScreen.screens.first`).
