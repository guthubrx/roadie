# Research : Stabilisation de Roadie

Chaque décision répond à une inconnue du plan. Format : Décision, Justification, Alternatives rejetées.

## R1. Transaction sur les fichiers d'état (C1, FR-013, FR-014)

- **Décision** : ajouter à `JSONPersistence` une primitive `mutate(url:type:default:_:)` qui prend le verrou exclusif existant (`FileLock`, fichier `.lock`) pendant tout le cycle lecture, modification, écriture. `StageStore`, `LayoutIntentStore` et `RailRuntimeStateStore` exposent `mutate { inout state in ... }`. L'écriture compare les octets encodés au fichier existant et ne réécrit pas s'ils sont identiques. Les lectures simples restent sans verrou (le `rename(2)` atomique garantit un fichier complet), ce qui conserve la correction de famine documentée dans `JSONPersistence.swift`.
- **Point clé** : `SnapshotService.snapshot()` fait l'énumération Accessibility HORS verrou, puis applique la réconciliation dans `mutate` sur l'état relu sous verrou. La réconciliation est une fonction pure de (état, fenêtres vivantes), donc la recalculer sous verrou est correct et rapide.
- **Justification** : correction minimale qui ferme la perte de mises à jour sans réécrire les 48 appels `.save(` d'un coup. Les chemins chauds (snapshot, commandes de stage via le daemon, intents) passent par `mutate`.
- **Rejeté** : verrou partagé en lecture (famine déjà observée) ; base SQLite (nouvelle dépendance, migration lourde) ; numéro de version avec réessai (plus complexe sans gain réel ici).

## R2. Fichier d'état illisible (FR-015)

- **Décision** : `JSONPersistence.loadResult` distingue `.missing`, `.loaded(T)`, `.corrupt(Error)`. En cas de `.corrupt`, le fichier est copié en `<nom>.corrupt-<horodatage>`, l'erreur est émise sur stderr et dans le flux d'événements (`state.load_failed`), et le store passe en mode « écriture refusée » jusqu'au prochain chargement réussi.
- **Rejeté** : repartir d'un état vide (comportement actuel, perte de données).

## R3. Délai Accessibility et mise de côté (C2, FR-021)

- **Décision** : `AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), 0.5)` au démarrage du provider (valeur globale par défaut), et la même valeur sur chaque élément d'application créé. Un registre `AXUnresponsiveApps` (pid → date de reprise) met une application de côté 5 s après `kAXErrorCannotComplete` ou un dépassement de délai ; pendant ce temps ses fenêtres gardent leur dernier état connu. Les `Thread.sleep` de `set()` sont réduits : une seule relecture du cadre, sans sommeil sur le chemin nominal.
- **Rejeté** : déplacer toute l'énumération hors du fil principal (refonte de concurrence trop large pour cette spec ; le délai suffit pour SC-003).

## R4. Cache d'attributs (C3, FR-022)

- **Décision** : le cache ne garde que les attributs stables (rôle, sous-rôle, présence des boutons, `isResizable`). Plein écran natif, focus, principal et modal sont relus à chaque snapshot. Une fenêtre âgée de moins de 500 ms n'est pas mise en cache. `invalidateCache()` est branché sur les notifications de l'observer AX.
- **Rejeté** : TTL plus court (garde le défaut, simplement plus rare).

## R5. Plein écran et maximisé (C5, FR-001, FR-016, FR-027)

- **Décision** : plein écran = `isNativeFullscreen` (AX) OU intention de commande explicitement marquée « zoom » (`arguments["presentation"] = "fullscreen"` dans l'intent enregistré par `toggleFullscreen`). La taille seule ne compte plus. Dans `WindowPresentationStateResolver`, `maximized` exige en plus que la fenêtre ne soit pas la seule fenêtre tilée de son scope. Le plein écran natif exclut seulement son scope (`excluding:`), pas le tick entier.
- **Rejeté** : augmenter ou réduire la tolérance de 48 px (le problème est de principe, pas de valeur).

## R6. Gardes du tick (FR-002, FR-016, FR-017, FR-040)

- **Décision** : chaque garde du tick (plein écran natif, stabilisation, suppression liée à une commande) produit un ensemble de scopes exclus. Le tick continue pour les autres scopes. `lastObservedFrames` n'est mis à jour que pour les scopes traités ou exclus explicitement. Le bloc « appliquer, réparer, isoler, émettre » devient une seule fonction. `restoreFocusedActiveStageIfNeeded` renvoie `nil` si rien n'est à appliquer.

## R7. Snapshot partagé et configuration (FR-018, FR-023)

- **Décision** :
  - `ConfigReloadService` existant, étendu avec une instance partagée `ConfigReloadService.shared` (process-wide, `RoadieDaemon`), garde la dernière configuration valide, vérifie la date de modification du fichier (un `stat` par appel, sans parsing si inchangé) et journalise une seule fois une configuration invalide. Tous les `(try? RoadieConfigLoader.load()) ?? RoadieConfig()` passent par lui. `SnapshotService` lit la config via `ConfigReloadService.shared.currentConfig()` à chaque snapshot, ce qui donne le rechargement à chaud.
  - `SnapshotService` partage un snapshot récent (moins de 90 ms) entre composants du même processus via un mémo process-wide, uniquement pour les appels en lecture (bordure, focus-souris, rail).
- **Rejeté** : bus d'événements entre composants (refonte large).

## R8. Canal CLI vers daemon (FR-038)

- **Décision** : socket Unix `~/.roadies/roadied.sock`, protocole d'une ligne JSON par requête (`{"argv":[...]}`) et une réponse (`{"exitCode":0,"stdout":"...","stderr":"..."}`). La logique de dispatch de `Sources/roadie/main.swift` est déplacée dans `RoadieDaemon` (`CLICommandRouter`) qui écrit dans des tampons au lieu de `print`/`exit`. Le binaire `roadie` tente le socket (délai 2 s) puis exécute le router en local en repli. Les commandes de démarrage/arrêt du daemon et `doctor` restent locales.
- **Justification** : un seul processus écrit l'état pour les commandes ; la CLI n'a plus besoin de la permission Accessibility ni d'un scan complet par commande.
- **Rejeté** : `DistributedNotificationCenter` (pas de réponse ni de code de retour) ; XPC (exige un bundle et un service enregistré).

## R9. Instance unique, signaux, restauration (FR-019, FR-037)

- **Décision** :
  - `roadied run` et `roadied tiler` prennent un `flock(LOCK_EX|LOCK_NB)` sur `~/.roadies/roadied.lock` pour toute leur vie et écrivent `roadied.pid`. `ComponentLockFile` passe au même mécanisme.
  - Un seul registre d'arrêt gère SIGTERM, SIGINT et SIGHUP : il ramène les fenêtres masquées (frame de membre visible), marque l'arrêt propre, libère le verrou.
  - Le snapshot de restauration est écrit à chaque changement de stage et toutes les 30 s, avec la dernière frame visible de chaque membre, jamais une frame masquée.
  - `restore-watch` surveille le pid du tiler (ou de `run`) et démarre dans sa propre session (`setsid`).
  - Commande `roadie restore unhide-all`.

## R10. Saisie utilisateur (FR-009, FR-010, FR-011)

- **Décision** : le tiler saute l'application des plans tant que `NSEvent.pressedMouseButtons != 0` (observation conservée). Le focus-souris agit seulement si le curseur a bougé de plus de 2 px depuis le tick précédent et sans bouton enfoncé. Le suivi de focus par la stage ignore un focus qui arrive moins de 500 ms après la disparition d'un membre ou qui n'est pas stable sur deux snapshots.

## R11. Identité des fenêtres (C4, FR-006)

- **Décision** : `reconcileWindowIDs` ne rattache un membre manquant que si le pid du membre n'est plus vivant (application relancée) ou au premier snapshot après démarrage, et exige une distance de cadre ≤ 360 px même pour un candidat unique.

## R12. Seuils centralisés (FR-041)

- **Décision** : `Sources/RoadieCore/LayoutTolerance.swift` regroupe les tolérances (changement observé, plein écran, clamp, croissance, stabilisation, grâces). Les tolérances liées aux marges sont calculées depuis `gapsInner`/`gapsOuter`.

## R13. Navrail (FR-024 à FR-030)

- **Décision** : signature d'état visible (scopes, membres, états de présentation, config) comparée avant reconstruction ; test de survol sur les cadres gardés au dernier rebuild ; timer de redessin actif seulement pendant un fondu ; vignettes réduites à 2× la largeur d'affichage ; capture via ScreenCaptureKit (`SCScreenshotManager`, macOS 14) avec repli icône ; preflight `CGPreflightScreenCaptureAccess`. `RailController.swift` est découpé en fichiers par type.

## R14. Installation et exploitation (FR-031 à FR-036)

- **Décision** :
  - `scripts/with-xcode` utilise Xcode.app seulement s'il existe, sinon `xcode-select -p` ; `PATH` étendu.
  - `ROADIE_CODESIGN_IDENTITY` optionnel pour une signature stable ; sinon signature ad hoc avec avertissement explicite sur la perte de permission.
  - `make restart` → `launchctl kickstart -k` ; `make dev-start` pour le mode tmux ; rotation des logs (`.1`) au démarrage au lieu de les vider ; `make uninstall`.
  - `examples/roadies.toml`, `examples/skhd/skhdrc`, `examples/karabiner/roadie.json`.
  - Le daemon publie `~/.roadies/daemon-status.json` (pid, version, permissions AX et Screen Recording, validité config, horodatage) ; `roadie doctor` le lit.

## R15. API dépréciées (FR-043)

- **Décision** : remplacer `CGWindowListCreateImage` par `SCScreenshotManager.captureImage` ; remplacer `activate(options: .activateIgnoringOtherApps)` par `activate()` + `kAXFrontmostAttribute` sur l'élément application avant `AXRaise`.
