# ADR-009 — Fusion mono-binaire : roadied + roadie-rail dans un seul process

**Statut** : Accepté
**Date** : 2026-05-04
**Spec** : SPEC-024

## Contexte

Jusqu'à V1, roadie était distribué en **deux exécutables séparés** :

- `roadied` — daemon lancé par launchd, propriétaire du tiling, des stages, des desktops virtuels, du serveur IPC sur socket Unix `~/.roadies/daemon.sock`.
- `roadie-rail` — application `.accessory` SwiftUI séparée qui dessine le panneau rail, se connecte au daemon via socket Unix pour lire le state (`stage.list`, `windows.list`, `window.thumbnail`) et souscrire aux events (sous-process `roadie events --follow` parsé en JSON-lines depuis stdout).

Sur la durée de V1 (SPEC-014, 018, 021, 022), cette frontière 2-process a accumulé des frictions :

| Problème | Fréquence |
|----------|-----------|
| Drift de state entre `state.stagesByDisplay` du rail et `stagesV2` du daemon (désync silencieuse, observable seulement quand l'utilisateur clique un stage périmé) | Récurrent — au moins 6 commits sur 4 SPECs |
| Deux grants TCC par catégorie (Accessibility sur roadied, Screen Recording sur roadied + rail mentionné par erreur dans le README) | Friction permanente en dev (chaque codesign casse les grants) |
| Deux bundles `.app` à déployer, signer, maintenir (Info.plist, version) | Surcoût opérationnel |
| Deux PID lockfiles, deux LaunchAgents | Surcoût opérationnel |
| Round-trip PNG base64 sur socket Unix (~250 kB / 2 s × N fenêtres) | Bande passante + latence continue |
| Helpers `decodeBool/Int/String` pour absorber les divergences de sérialisation JSON (NSNumber vs Bool vs Int) | Dette technique |
| Quand le daemon crashe, le rail freeze sur timeout IPC, restart manuel | Récurrent en dev |

Aucun WM macOS mature ne sépare le panneau et le tiling en deux processes :

- **yabai** : binaire daemon unique. Les panneaux (sketchybar) sont des projets tiers, pas dans yabai.
- **AeroSpace** : binaire mono-process unique, `NSApplication` activation policy `.accessory` + thread tiling.

Le design 2-process de roadie était un héritage du moment où le rail avait été prototypé comme expérience séparée ; au fil du temps il a cessé de justifier son coût.

## Décision

Fusionner `roadie-rail` dans `roadied` en un binaire mono-process unique. On garde :

- Le binaire CLI `roadie` séparé (il reste un client Unix-socket utilisé par BTT, SketchyBar, scripts shell).
- Le serveur Unix-socket dans le process daemon (utilisé par le CLI et tout consommateur externe).
- La séparation logique des modules Swift (`RoadieCore`, `RoadieTiler`, `RoadieStagePlugin`, `RoadieDesktops`, `RoadieRail`) — seule la fusion runtime change.

Architecture interne :

- `RoadieRail` devient un `target` (library) au lieu d'`executableTarget`, lié statiquement à `roadied`.
- Un nouveau `Sources/roadied/RailIntegration.swift` (~25 LOC) crée un `RailController` après la fin du `bootstrap()` du daemon, stocké en propriété forte `daemon.railController`.
- `RailController.init(handler:)` accepte un `CommandHandler` (le protocole que `Daemon` implémente déjà pour le serveur Unix socket). Le rail ne crée plus de `RailIPCClient` ; il crée un `RailDaemonProxy` qui appelle `handler.handle(request)` directement in-process. L'API `send(command:args:)` est compatible byte-pour-byte avec le client V1, donc les call-sites du `RailController` ne changent pas.
- Un nouveau `EventStreamInProcess` subscribe à `EventBus.shared.subscribe()` (le même bus actor-isolé qui alimente déjà le canal public `events --follow` côté serveur socket) et dispatche les `DesktopEvent` vers la méthode existante `handleEvent(name:payload:)`.

## Trade-offs

### Ce qu'on gagne

- **Une seule grant TCC par catégorie** (Accessibility + Screen Recording sur `roadied.app` uniquement). README corrigé : le rail n'a besoin d'aucune grant.
- **Un seul codesign par build** (~50% plus rapide sur le cycle install-dev).
- **Un seul LaunchAgent** (`com.roadie.roadie`).
- **Zéro drift IPC** : le rail lit le state via appels de méthode directs, pas de sérialisation JSON, pas de mismatch silencieux.
- **Récupération co-jointe sur crash** : launchd respawn un seul process, rail et tiling reviennent ensemble.
- **−171 LOC effectives Swift** mesurées (cible était −150).

### Ce qu'on perd

- **Isolation crash niveau OS** : une exception SwiftUI dans le rail tue tout le process (tiling inclus). Mitigé par le fait qu'aucun crash rail n'a été observé historiquement (`~/Library/Logs/DiagnosticReports/roadied-*.ips` ne contient aucune trace attribuée au rail dans la vie du projet). Et `ThrottleInterval=30` de launchd assure une récupération en ~30 s.
- **Pas d'upgrade indépendant du rail** : rail et tiling shippent comme un seul binaire. Acceptable : ce projet est pour un daily-driving personnel, pas un déploiement multi-tenant.

## Pourquoi pas les alternatives

| Alternative | Pourquoi rejetée |
|-------------|------------------|
| Garder V1 2-process, optimiser l'IPC (XPC mach-named au lieu de socket Unix) | Ne résout qu'un symptôme (IPC perf). Garde tous les autres coûts (TCC, codesign, LaunchAgent, drift). Même complexité dev. |
| Un process mais UI dans une `XCApp` extension séparée | Les app extensions macOS sont sandboxées ; impossible d'héberger le rail SwiftUI avec ses overlays `NSPanel` et le polling souris global. Mauvais outil. |
| Déplacer la logique tiling dans le process rail, tuer le daemon | Forcerait l'utilisateur à lancer le rail manuellement, défaisant l'auto-start launchd. Et le rail est GUI-bound ; le tiling doit tourner même sans rail visible. |

## Conséquences

- Le contrat CLI public (`roadie stage *`, `roadie desktop *`, `roadie display *`, `roadie window *`, `roadie events --follow`, `roadie daemon *`, `roadie fx *`) est **inchangé**. `contracts/ipc-public-frozen.md` de SPEC-024 formalise ça.
- `daemon.status` expose `arch_version: 2` et `rail_inprocess: true` pour que les consommateurs tiers puissent détecter V2 vs V1.
- La migration V1 → V2 est automatique : `install-dev.sh` détecte et supprime `~/Applications/roadie-rail.app`, kill tout process rail en marche, supprime `~/.local/bin/roadie-rail`, lance `tccutil reset` sur les entrées TCC orphelines (`com.roadie.roadie-rail`).
- L'utilisateur doit re-toggler les grants TCC pour `roadied.app` (Accessibility + Screen Recording) à l'upgrade V1→V2 parce que le hash de codesign change. Documenté dans `quickstart.md`.

## Sources

- yabai source code (github.com/koekeishiya/yabai) : pattern binaire unique.
- AeroSpace source code (github.com/nikitabobko/AeroSpace) : NSApplication `.accessory` mono-process.
- Apple TN3127 "Apple silicon and TCC" : le designated requirement est préservé entre rebuilds quand on signe avec la même identité.
