# Research — SPEC-024 Migration mono-binaire

**Phase 0** | Date : 2026-05-04 | Branche : `024-monobinary-merge`

Ce document consolide les choix techniques fait lors de la planification, avec rationale et alternatives évaluées. Le spec est exempt de marqueurs `[NEEDS CLARIFICATION]` ; la recherche a porté sur les patterns techniques précis à employer.

---

## R1. Mécanisme d'EventBus in-process

### Décision

**Réutiliser `DesktopEventBus` existant** dans `Sources/RoadieDesktops/EventBus.swift` (actor Swift, AsyncStream-based) en l'adaptant pour porter aussi les events stages/windows/displays. Le module RoadieRail subscribe via `AsyncStream` sur le même bus que celui qui est déjà publié vers le serveur IPC public (`events --follow`).

### Rationale

- **Article 0 minimalisme** : l'EventBus existe déjà, est testé en production depuis SPEC-011, supporte plusieurs subscribers, gère proprement le cycle de vie via `onTermination`.
- **Article B' dépendances** : aucune nouvelle dépendance (Combine évité car projet déjà aligné sur `actor` + `AsyncStream` Swift 5.9).
- **Sérialisation** : zero-copy. Le `DesktopChangeEvent` est un `struct Sendable` directement consommable. Pas de JSON ni base64. Les thumbnails restent dans un cache mémoire (`ThumbnailCache` existant côté daemon) accessible directement par le rail.
- **Cohérence** : un seul lieu où les events sont publiés (le bus). Le serveur IPC public devient un simple subscriber du bus qui sérialise vers JSON-lines pour les clients externes (CLI, SketchyBar). Le rail interne devient un autre subscriber du même bus mais consomme les structures Swift directement.

### Alternatives considérées

| Alternative | Pourquoi rejetée |
|-------------|------------------|
| Combine `PassthroughSubject` + `Publisher` | Ajoute une dépendance conceptuelle Combine alors que le projet est aligné sur `actor` + `AsyncStream`. Mélanger les paradigmes ferait du bruit. |
| `NotificationCenter` | Pas type-safe, repose sur clés `String`, casse le contrat strict des events. |
| Écrire un nouveau `RoadieEventBus` from-scratch | Duplication. L'existant suffit. Si périmètre des events à porter dépasse `DesktopChangeEvent`, étendre le struct existant ou ajouter un `enum RoadieEvent` au-dessus. |
| Re-utiliser le serveur IPC en local (rail subscribe via socket) | Garde la latence/sérialisation. C'est précisément ce qu'on veut éliminer. |

### Conséquences pour l'implémentation

- Étendre `DesktopChangeEvent` (ou créer un wrapper `RoadieEvent` qui inclut `DesktopChangeEvent`) pour porter aussi : `stage_changed`, `window_assigned/unassigned/created/destroyed/focused`, `display_configuration_changed`, `thumbnail_updated`. La majorité de ces events EXISTE déjà avec un schéma JSON-lines stable côté serveur IPC ; il s'agit de capturer leur source Swift en amont du serializer JSON et de la pousser au bus interne.
- Le rail consomme via `for await event in bus.subscribe() { ... handleEvent(...) }`.
- Le serializer JSON pour clients externes consomme via le même pattern, transforme en JSON-line.

---

## R2. Lifecycle SwiftUI dans NSApplication.accessory + initialisation tardive

### Décision

Le binaire `roadied` reste `NSApplication.shared.setActivationPolicy(.accessory)` au démarrage (déjà en place). La construction des `NSPanel` rail (via `RailController`) est différée au callback `applicationDidFinishLaunching`-équivalent (déjà appelé par `NSApp.run()` après bootstrap async). Cela respecte le contrat AppKit : aucun `NSPanel` ne peut être créé avant que l'`NSApplication` soit pleinement initialisée.

### Rationale

- C'est exactement le pattern actuel de `roadie-rail` (cf. `Sources/RoadieRail/AppDelegate.swift:applicationDidFinishLaunching` qui crée le `RailController`). Il est connu pour fonctionner sur macOS Sonoma et Tahoe.
- Le daemon actuel a déjà `let app = NSApplication.shared; app.setActivationPolicy(.accessory); app.run()` à la fin de `Sources/roadied/main.swift`. La ligne `DispatchQueue.main.async { Task { @MainActor in bootstrap() } }` ordonnance le bootstrap après le démarrage de la run loop. On ajoute la création du RailController à la fin du bootstrap.

### Alternatives considérées

| Alternative | Pourquoi rejetée |
|-------------|------------------|
| Créer le RailController au tout début (avant `app.run()`) | Apple recommande explicitement de ne pas créer de NSWindow/NSPanel avant `applicationDidFinishLaunching`. Risque de comportements indéterminés sur les screen layouts multi-display. |
| Utiliser `NSApplicationDelegate` formel | Surcouche inutile. Le pattern `Task { @MainActor }` au boot suffit, c'est ce qu'utilise le daemon actuel. |

### Conséquences pour l'implémentation

- Ajouter, à la fin de `Daemon.bootstrap()` (ou via un hook après `roadied ready`), l'instanciation : `let rail = RailController(eventBus: self.bus, thumbnailCache: self.thumbnailCache); rail.start()`.
- Le `RailController` doit être stocké dans une propriété forte du `Daemon` (sinon ARC le déalloue immédiatement, comme l'actuel `AppState.daemon`).

---

## R3. Activation policy `.accessory` vs. `.regular`

### Décision

Garder `.accessory` (= LSUIElement true). Ne pas devenir `.regular`.

### Rationale

- `.accessory` = pas dans le Dock, pas dans le sélecteur d'apps (Cmd-Tab), pas de menu bar par défaut. C'est exactement le comportement attendu d'un WM en arrière-plan.
- TCC sur Tahoe accepte parfaitement les apps `.accessory` pour Accessibility. Pour Screen Recording, la grant dépend du designated requirement de la signature (lié au cert ad-hoc `roadied-cert`), pas du type d'activation.
- Préserve le comportement actuel des deux binaires (le daemon est `.accessory`, le rail aussi).

### Alternatives considérées

| Alternative | Pourquoi rejetée |
|-------------|------------------|
| `.regular` (app standard avec Dock) | Pollue le Dock pour 0 bénéfice. L'utilisateur n'interagit jamais avec roadie via le Dock. |
| `.prohibited` | Ne permet pas de créer de NSWindow/NSPanel — incompatible avec le rail UI. |

---

## R4. Compatibilité ascendante du serveur IPC public

### Décision

Le serveur IPC sur `~/.roadies/daemon.sock` reste identique en V2 : mêmes commandes, même schéma JSON, mêmes events publiés en mode `events --follow`. Le rail consomme désormais le bus interne en parallèle (zéro dépendance entre les deux chemins).

### Rationale

- FR-007 / FR-008 / SC-004 imposent la stabilité absolue de cette interface.
- 13 raccourcis BTT, plugin SketchyBar, scripts shell utilisateurs et `roadie events --follow` dépendent de ce contrat.
- Aucun avantage technique à le casser (son implémentation côté daemon est déjà mince ~600 LOC dans `RoadieCore/Server.swift`).

### Alternatives considérées

| Alternative | Pourquoi rejetée |
|-------------|------------------|
| Migrer vers XPC mach-named | Plus standard macOS, mais incompatible avec les clients shell `nc -U`. Casserait BTT/SketchyBar. |
| Migrer vers JSON-RPC over HTTP | Sur-engineering pour ce besoin local. |
| Profiter de la migration pour nettoyer l'API socket | Sortirait du scope strict de cette spec. À traiter en SPEC dédiée si besoin émerge. |

---

## R5. Suppression des helpers `decodeBool/Int/String` côté rail

### Décision

Ces helpers (cf. `Sources/RoadieRail/RailController.swift` lignes ~880-920) ont été ajoutés pour absorber le cast tolérant des payloads JSON décodés via `AnyCodable`. En accès in-process direct, les structures Swift sont consommées avec leurs types statiques garantis. Les helpers deviennent inutiles → suppression.

### Rationale

- Ces helpers existent **uniquement** parce que le rail recevait du JSON désérialisé d'un serializer côté daemon qui pouvait représenter un Bool comme NSNumber, Int, ou String selon le bridging. En accès in-process, on a un `struct Stage { var isActive: Bool }` directement.
- ~30 LOC à supprimer.

### Alternatives considérées

| Alternative | Pourquoi rejetée |
|-------------|------------------|
| Garder les helpers "au cas où" | Article 0 minimalisme. Code mort = dette. |
| Les déplacer dans RoadieCore pour une utilisation future | Article 0 minimalisme. Pas de besoin actuel. |

---

## R6. Stratégie de test après migration

### Décision

- **Tests unitaires** : la majorité des tests existants (Tiler, Tree, Config, parsers TOML) reste valide sans modification car ils testent des modules internes intacts.
- **Tests d'intégration** : les tests SPEC-014/018/019/022 qui simulaient un IPC client/serveur deviennent partiellement obsolètes. Adaptation : remplacer les appels IPC par des appels in-process directs au RailController et à ses méthodes `handleEvent(...)`. Compteur attendu : 5-10 tests à adapter.
- **Tests d'acceptation manuelle** : checklist post-migration (cf. quickstart.md) pour valider les 13 raccourcis BTT, plugin SketchyBar, et user stories US1-US5.
- **Test de bench latence** : nouveau script `tests/bench/rail-latency.swift` qui mesure le hover→visible p95 sur 100 itérations (SC-006).

### Rationale

Pyramide de tests respectée (art H' constitution-002). Les ajouts (test bench) sont minimes et ciblés sur le critère SC-006.

---

## R7. Pas d'isolation crash entre tiling et rail (trade-off explicite)

### Décision

En migrant vers un seul process, on perd l'isolation OS-level "crash du rail ne tue pas le tiling". Ce trade-off est accepté.

### Rationale

- En pratique, le rail SwiftUI (~2 700 LOC) ne crashe quasiment jamais. Aucun crash log SwiftUI dans les diagnostic reports historiques.
- Les vrais crashs proviennent du daemon (AX issues, CGS, gestion des fenêtres tierces). Ces crashs prennent déjà tout le tiling avec eux V1, donc l'isolation rail/daemon n'apportait rien dans ce sens.
- Bénéfice net : −150 LOC, −1 binaire à signer, −1 grant TCC. Coût net : risque théorique d'un crash UI. **Bénéfice clairement supérieur**.
- Si un crash UI survenait, launchd respawnerait l'ensemble en ≤ 30 s (via `ThrottleInterval=30` existant).

### Alternatives considérées

| Alternative | Pourquoi rejetée |
|-------------|------------------|
| Garder 2 processes pour l'isolation | Inverse du sujet de cette spec. |
| Sandboxer le module rail dans un thread dédié avec exception handler | Sur-engineering. Pas de problème observé en pratique. |

---

## R8. Gestion du PID lockfile

### Décision

L'actuel `~/.roadies/rail.pid` (PID lockfile du rail séparé) disparaît. L'ancien fichier devient orphelin et est nettoyé automatiquement au démarrage du process unifié (best-effort `try? FileManager.removeItem`).

Le PID lockfile du daemon (`~/.roadies/daemon.pid` si existant) reste, géré par launchd qui empêche le double-launch via le `Label` du LaunchAgent.

### Rationale

- launchd garantit l'unicité d'instance par `Label` plist (`com.roadie.roadie`). Pas besoin de lockfile applicatif.
- Le lockfile rail V1 servait à empêcher deux instances de rail tournant en parallèle ; n'existe plus.

---

## R9. Migration utilisateur en place (V1 → V2)

### Décision

Le script `install-dev.sh` (modifié dans cette spec) détecte automatiquement à chaque lancement la présence des artefacts V1 et les nettoie :

1. Stop tout process `roadie-rail` (pkill).
2. Bootout l'éventuel LaunchAgent `com.roadie.roadie-rail` (s'il existait).
3. Supprime le bundle `~/Applications/roadie-rail.app`.
4. Supprime le fichier `~/.roadies/rail.pid`.
5. Supprime l'entrée TCC orpheline (best-effort `tccutil reset` sur `com.roadie.roadie-rail`).
6. Déploie + signe `~/Applications/roadied.app` (le nouveau process unifié).
7. Bootstrap le LaunchAgent `com.roadie.roadie` (inchangé).
8. Au premier démarrage : prompts TCC sur la nouvelle signature unifiée (Accessibility + Screen Recording).

### Rationale

- Migration zéro-friction utilisateur sauf 2 toggles TCC (acceptable et documenté).
- Pas de migration de données (les `.toml`, `stages.v1.bak`, etc., restent à leur place).
- Idempotent : relancer `install-dev.sh` plusieurs fois donne toujours le même état stable.

---

## R10. Thumbnails : accès direct au cache mémoire

### Décision

Le `ThumbnailCache` (déjà présent côté daemon dans `RoadieCore/ScreenCapture/`) devient accessible directement depuis le module RoadieRail. La `ThumbnailFetcher` côté rail est refactorée : au lieu d'envoyer une requête `window.thumbnail` via socket, elle appelle directement `cache.fetchOrCapture(wid:)` qui retourne soit la dernière entrée cachée, soit déclenche une capture lazy synchrone.

### Rationale

- Élimine la sérialisation base64 (250 kB / 2 s × N fenêtres = ~1 MB/s économisé).
- Élimine la latence socket round-trip (~5-10 ms par requête).
- Élimine les `thumbnailFetcher: ipc error timeout` observés dans les logs aujourd'hui.
- Le cache reste owned par le daemon (logique de capture inchangée).

### Alternatives considérées

| Alternative | Pourquoi rejetée |
|-------------|------------------|
| Garder le ThumbnailFetcher actuel mais sur un actor Swift au lieu d'un socket | Plus de LOC pour le même résultat. L'accès direct au cache (avec verrou si nécessaire) est plus simple. |
| Pousser les thumbnails au rail via le bus events | Le bus diffuse à tous les subscribers. Diffuser un PNG 50-300 kB à chaque capture est wasteful. Lazy fetch reste plus efficace. |

---

## Sources externes consultées

- Apple — "App Extensions and Sandbox Considerations" (`developer.apple.com/documentation/sandboxing`) : confirme `.accessory` compatible avec NSPanel + global event monitor.
- Apple — TN3127 "Apple silicon and TCC" : confirme que la grant TCC est liée au designated requirement (cert leaf hash + identifier), donc préservée par re-signing avec le même cert ad-hoc.
- yabai source code (github.com/koekeishiya/yabai) : confirme le pattern mono-binaire pour les WM macOS.
- AeroSpace source code (github.com/nikitabobko/AeroSpace) : confirme NSApplication unique avec activation policy `.accessory` + thread tiling pour ce type de produit.

---

## Synthèse des décisions

| Sujet | Décision | Impact LOC |
|-------|----------|------------|
| EventBus | Réutiliser `DesktopEventBus`, étendre les events portés | ~+30 LOC |
| Lifecycle SwiftUI | `applicationDidFinishLaunching`-équivalent dans bootstrap | ~+20 LOC |
| Activation policy | `.accessory` inchangée | 0 |
| IPC public | Inchangé (FR-007) | 0 |
| Helpers tolérants | Suppression complète | ~−30 LOC |
| Tests | Adaptation 5-10 tests intégration, +1 bench | (hors LOC src) |
| Isolation crash | Trade-off accepté, pas de mitigation | 0 |
| PID lockfile rail | Suppression | ~−30 LOC |
| Migration user | Script install-dev.sh étendu | (bash, hors LOC Swift) |
| Thumbnails | Accès direct au cache, suppression IPC | ~−80 LOC |
| **Total estimé** | | **~−90 LOC nettes** Swift à ce niveau de granularité |

À cela s'ajoutent les suppressions plus larges identifiées dans le plan (RailIPCClient ~150, EventStream ~80, main.swift rail ~10, AppDelegate ~30, RailConfig.load() dupliqué ~50). **Bilan global attendu : −350 LOC nettes**, en confort sous la cible (−150).

→ Aucune `[NEEDS CLARIFICATION]` restante. Phase 1 peut démarrer.
