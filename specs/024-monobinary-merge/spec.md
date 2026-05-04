# Feature Specification: Migration mono-binaire (fusion roadied + roadie-rail)

**Feature Branch**: `024-monobinary-merge`
**Created**: 2026-05-04
**Status**: Implemented (mergée sur main, audit grade A, daily-driver en cours)
**Dependencies**: SPEC-002 (tiler+stage), SPEC-011 (virtual desktops), SPEC-014 (rail UI), SPEC-018 (stages per display), SPEC-022 (multi-display per-stage), SPEC-023 (sketchybar plugin)
**Input**: User description: "Migration roadie de 2 binaires (roadied daemon launchd + roadie-rail .app GUI) vers 1 binaire mono-process NSApplication. Garder la séparation logique en modules Swift (RoadieCore, RoadieTiler, RoadieStagePlugin, RoadieDesktops, RoadieRail). 1 activation policy .accessory, 1 grant Accessibility, 1 grant Screen Recording, 1 process TCC, 1 launchd plist. Suppression de l'IPC Unix-socket inter-process : accès direct via EventBus/Combine in-process. Élimine les bugs récurrents : drift state rail/daemon, double signing à chaque rebuild, double TCC, désync events JSON. Préserver compat ascendante des CLIs `roadie ...` : le binaire CLI reste séparé et parle au process unifié via socket Unix existant. Nom du binaire unifié : roadied. Migration en respect strict de la constitution (Article 0 minimalisme, Article G plafond LOC)."

## Contexte et motivation

L'architecture actuelle de roadie sépare la logique en deux processes distincts :

1. **`roadied`** — daemon launchd lancé en arrière-plan, propriétaire du tiling, des stages, des desktops virtuels, du serveur IPC Unix-socket `~/.roadies/daemon.sock`.
2. **`roadie-rail`** — application `.accessory` lancée séparément (manuellement ou via launchd dérivé), affiche le rail SwiftUI sur le bord gauche de chaque écran, consomme les events du daemon via socket et reconstitue son propre `state.stages`.

Cette séparation a induit, sur les 4 dernières SPECs (014, 018, 021, 022), au moins 6 bugs documentés liés directement à la frontière inter-process :

- Désynchronisation silencieuse rail/daemon (events `display_uuid` filtrés trop strictement, SPEC-018).
- `state.stagesByDisplay` côté rail vs `stageManager.stagesV2` côté daemon : 2 états parallèles à synchroniser.
- Pertes d'événements pendant un crash daemon (rail bloque sur timeout IPC).
- Double parsing TOML (`RailConfig.load()` côté rail vs `Config` côté daemon) avec drift sémantique.
- Sérialisation thumbnails PNG en base64 sur Unix-socket (~250 kB par fenêtre × 2 s) au lieu d'accès mémoire direct.
- Helpers `decodeBool/Int/String` tolérants côté rail pour absorber les divergences AnyCodable du daemon.

L'archi 2-binaires impose également :

- **2 grants TCC** par utilisateur (Accessibility sur `roadied.app` + Screen Recording sur `roadied.app` ET `roadie-rail.app`).
- **2 codesign** à chaque rebuild dev (sinon rupture de la grant TCC).
- **2 bundles `.app`** à maintenir avec `Info.plist`, signature, désinstallation.

Aucun WM macOS moderne actif (yabai, AeroSpace) ne sépare le tiling de l'UI panneau dans deux processes distincts. Cette spec acte la migration vers un binaire mono-process unique, en préservant strictement la séparation **logique** des modules Swift et l'API CLI publique.

## User Scenarios & Testing *(mandatory)*

### User Story 1 — Installation simplifiée (Priority: P1)

**En tant qu'**utilisateur final installant roadie pour la première fois,
**je veux** activer un nombre minimal de permissions système,
**afin de** ne pas être confronté à la confusion "quelle app autoriser pour quelle fonction".

**Why this priority** : c'est le premier point de friction utilisateur. L'archi actuelle force l'utilisateur à comprendre que deux apps distinctes ont besoin chacune de Screen Recording, ce qui induit erreurs et abandon. La résolution de cette friction conditionne l'adoption.

**Independent Test** : peut être validé indépendamment en effectuant une installation fraîche (machine vierge ou TCC reset) et en mesurant le nombre d'apps présentes dans Réglages Système → Confidentialité → Accessibilité et → Enregistrement d'écran.

**Acceptance Scenarios** :

1. **Given** une machine fraîchement réinstallée sans grants TCC roadie, **When** l'utilisateur installe roadie via `install-dev.sh` puis lance le daemon, **Then** les Réglages Système exposent **une seule** entrée "roadied" sous Accessibilité et **une seule** entrée "roadied" sous Enregistrement d'écran.
2. **Given** un utilisateur ayant accordé les deux permissions à "roadied", **When** il rebuild + redéploie le binaire, **Then** les permissions restent valides sans re-toggle (préservation du designated requirement par la signature `roadied-cert`).
3. **Given** un utilisateur consultant le README, **When** il lit la section Installation, **Then** la section Accessibilité ne mentionne qu'une seule app (au lieu de deux).

---

### User Story 2 — Cycle de développement plus court (Priority: P1)

**En tant que** développeur de roadie,
**je veux** rebuild + déployer + redémarrer en une seule séquence sans gérer deux binaires en parallèle,
**afin de** réduire le temps de boucle de feedback et éliminer les classes de bugs liées à la désynchronisation des deux binaires.

**Why this priority** : le développement quotidien est aujourd'hui ralenti par : (a) re-signing de deux binaires, (b) gestion de deux PID lockfiles, (c) deux bundles `.app` à mettre à jour, (d) ordre de redémarrage critique (daemon doit être up avant rail sinon timeout IPC). Chaque session paie ce coût plusieurs fois.

**Independent Test** : peut être validé en chronométrant la séquence `swift build && deploy && restart && verify-rail-visible` avant et après migration. Ratio attendu ≥ 1,5×.

**Acceptance Scenarios** :

1. **Given** une modification d'un fichier Swift, **When** le développeur lance `./scripts/install-dev.sh`, **Then** un seul binaire est compilé, signé, déployé, et le process est redémarré (via launchd) en une étape unifiée.
2. **Given** un crash applicatif simulé, **When** launchd respawne le process, **Then** le tiling **et** le rail reviennent ensemble en moins de 3 secondes (au lieu de redémarrer deux processes séquentiellement avec gestion d'ordre).
3. **Given** une review de pull request, **When** un mainteneur lit le diff, **Then** il n'y a qu'un seul `Info.plist`, un seul `LaunchAgent`, un seul ensemble de scripts d'installation à valider.

---

### User Story 3 — Cohérence visuelle garantie (Priority: P2)

**En tant qu'**utilisateur quotidien,
**je veux** voir le rail refléter à tout instant l'état exact du tiling,
**afin de** ne pas faire de fausses manipulations basées sur un état périmé (cliquer sur un stage qui n'existe plus, dropper une fenêtre vers un stage déjà fusionné).

**Why this priority** : l'archi actuelle expose des fenêtres temporelles où l'état rail diverge de l'état daemon (timeout IPC, event manqué, mismatch display_uuid). Si l'utilisateur agit pendant ces fenêtres, le résultat surprend. Migration élimine la classe entière de ces bugs.

**Independent Test** : peut être validé en stressant le système (ouverture/fermeture rapide de 20 fenêtres, switch desktop pendant un drag-drop) et en vérifiant qu'aucune divergence visible rail/tiling n'apparaît, jamais.

**Acceptance Scenarios** :

1. **Given** un utilisateur déplaçant rapidement une fenêtre entre deux stages via drag-drop sur le rail, **When** la fenêtre traverse 5 stages en moins de 2 secondes, **Then** le rail montre la position correcte à chaque étape (pas de "fenêtre fantôme" sur stage source).
2. **Given** un crash simulé du module tiling, **When** le process redémarre, **Then** le rail re-synchronise instantanément sur le nouvel état (pas de mode "déconnecté" comme aujourd'hui où le rail reste affiché avec un état périmé).
3. **Given** un changement de desktop pendant que des thumbnails sont en cours de capture, **When** la transition s'achève, **Then** les thumbnails affichées correspondent au desktop d'arrivée (pas de mélange daemon-state vs rail-state).

---

### User Story 4 — Compatibilité ascendante stricte (Priority: P1)

**En tant qu'**utilisateur ayant configuré BTT, SketchyBar, ou des scripts personnels,
**je veux** que mes appels CLI `roadie *` continuent à fonctionner sans aucune modification,
**afin de** ne pas avoir à reconfigurer 13 raccourcis BTT et autant de scripts à chaque mise à jour majeure.

**Why this priority** : la compat ascendante des points d'extension publics (CLI, raccourcis BTT, plugin SketchyBar) est non-négociable. Une migration interne ne doit pas casser ce contrat. Sinon, l'utilisateur préfère ne pas migrer.

**Independent Test** : peut être validé en exécutant la suite complète des 13 raccourcis BTT, plus les scripts SketchyBar, plus une dizaine de commandes CLI variées, et en vérifiant que tous renvoient des codes/comportements identiques à la version pré-migration.

**Acceptance Scenarios** :

1. **Given** les 13 raccourcis BTT existants pointant vers `~/.local/bin/roadie`, **When** l'utilisateur les active après migration, **Then** le comportement observable est strictement identique (mêmes codes de retour, mêmes sorties stdout/stderr, mêmes effets sur les fenêtres).
2. **Given** un script SketchyBar abonné à `roadie events --follow`, **When** un changement de stage survient, **Then** le script reçoit le même flux JSON événementiel qu'avant (schéma identique, latence ≤ 200 ms).
3. **Given** une commande `roadie stage list --display <uuid>`, **When** l'utilisateur l'exécute, **Then** la sortie JSON ou texte est strictement identique au comportement pré-migration.

---

### User Story 5 — Performance préservée ou améliorée (Priority: P3)

**En tant qu'**utilisateur exigeant en réactivité,
**je veux** que le rail apparaisse en moins de 100 ms après hover edge, sans cold-start IPC,
**afin de** percevoir le rail comme un élément intégré et non comme un panneau "qui charge".

**Why this priority** : c'est un nice-to-have, pas un critère bloquant. La perf actuelle est déjà acceptable. Mais la migration en profite naturellement (pas de sérialisation, pas de socket round-trip), donc autant le mesurer pour ne pas régresser.

**Independent Test** : peut être validé via un script benchmark qui mesure le temps entre `hover edge` et `première frame visible du rail`, sur 100 itérations. Cible ≤ 100 ms p95.

**Acceptance Scenarios** :

1. **Given** le rail en mode `persistence_ms = -1` (fade-out immédiat), **When** l'utilisateur passe la souris sur le bord gauche, **Then** le panel apparaît en moins de 100 ms p95 (mesure interne).
2. **Given** 10 fenêtres ouvertes avec thumbnails actives, **When** le rail rafraîchit ses vignettes, **Then** la consommation mémoire peak ne dépasse pas la valeur observée pré-migration (pas de leak post-IPC-removal).

---

### Edge Cases

- **Crash interne d'un module** : si le module RoadieRail (UI SwiftUI) crashe avec un fatalError, comment isoler du module RoadieTiler pour ne pas perdre la session tiling ? Réponse de fond : SwiftUI dans un process correctement structuré ne devrait pas crasher la couche AppKit ; les exceptions Swift remontent au runloop NSApp et sont catchables. À ne pas confondre avec une isolation process : ce niveau d'isolation est volontairement abandonné comme acceptable trade-off.
- **Désinstallation propre** : que devient l'ancien binaire `roadie-rail` chez les utilisateurs migrant ? Le script de désinstall doit retirer `~/Applications/roadie-rail.app` ET son LaunchAgent (s'il en existait un), ET le PID lockfile `~/.roadies/rail.pid`.
- **Signature TCC pendant migration** : un utilisateur upgradant depuis V1 (2-binaires) verra une nouvelle entrée "roadied" remplacer les deux anciennes ; les anciennes grants ne sont **pas** transférables — l'utilisateur DOIT re-toggler la perm. Documentation de migration explicite.
- **Lancement multiple accidentel** : si l'utilisateur lance l'ancien `roadie-rail.app` après la migration, il doit échouer proprement avec un message clair "Cette app a été remplacée par roadied. Désinstaller via uninstall-fx.sh."
- **launchd config perdue** : si le `LaunchAgent` plist contient encore l'ancienne référence à `roadie-rail`, le script d'install doit la nettoyer.
- **Capture d'écran sans Screen Recording** : avec un seul process, soit la perm est accordée et toutes les fonctions marchent (tiling + thumbnails), soit elle ne l'est pas et seul le tiling marche (thumbnails dégradées en icônes). Plus de cas hybride "rail OK + capture KO".

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001** : Le système DOIT distribuer un seul binaire exécutable nommé `roadied` qui assure l'ensemble des fonctions tiling, stages, desktops virtuels, et UI rail.
- **FR-002** : Le binaire CLI nommé `roadie` (séparé) DOIT continuer à exister et à communiquer avec le process unifié via le socket Unix existant `~/.roadies/daemon.sock`. Aucun changement de chemin, de schéma, ou de comportement observable.
- **FR-003** : Le système DOIT être lancé par un seul `LaunchAgent` plist (`~/Library/LaunchAgents/com.roadie.roadie.plist`). Aucun second LaunchAgent pour le rail.
- **FR-004** : Le binaire `roadied` DOIT utiliser une activation policy d'app `.accessory` (LSUIElement) afin de ne pas apparaître dans le Dock ni dans le sélecteur d'applications.
- **FR-005** : Le système DOIT accéder au state des stages, du tiling, des desktops directement en mémoire depuis le module RoadieRail, sans sérialisation JSON ni round-trip socket.
- **FR-006** : Le module RoadieRail DOIT consommer les événements du module tiling via un mécanisme de bus in-process (Combine `Publisher` ou EventBus existant adapté). Aucun socket inter-process pour ces événements.
- **FR-007** : Le serveur IPC Unix-socket DOIT continuer à exister et à servir le binaire CLI `roadie` (et tout client externe : SketchyBar, scripts user). Schéma JSON et liste de commandes inchangés.
- **FR-008** : Toutes les commandes CLI publiques (`roadie stage *`, `roadie desktop *`, `roadie window *`, `roadie display *`, `roadie events --follow`, `roadie daemon *`, `roadie fx *`) DOIVENT continuer à fonctionner avec un comportement strictement identique à la version V1 (codes de retour, sortie textuelle, sortie JSON, événements).
- **FR-009** : La signature de code DOIT être appliquée uniquement au binaire `roadied` (et au binaire `roadie` CLI). Aucune signature séparée d'un binaire `roadie-rail`.
- **FR-010** : Une seule grant Accessibility (sur `roadied.app`) DOIT suffire pour toutes les fonctions tiling. Une seule grant Screen Recording (sur `roadied.app`) DOIT suffire pour toutes les fonctions thumbnails.
- **FR-011** : Le script `install-dev.sh` DOIT, après migration, ne déployer qu'un seul `.app` bundle (`~/Applications/roadied.app`). L'ancien `~/Applications/roadie-rail.app` DOIT être nettoyé par le script si présent (avec préservation des fichiers utilisateur si applicable).
- **FR-012** : Le système DOIT respecter la constitution Article 0 (minimalisme) : la migration ne doit pas introduire de fonctionnalité nouvelle non strictement nécessaire à la fusion. Aucun nouveau module, aucune nouvelle abstraction non justifiée.
- **FR-013** : Le système DOIT respecter la constitution Article G (plafond LOC) : la migration doit produire un solde net **négatif ou nul** en LOC effectives (suppression d'IPC client/serveur dupliqué, suppression de parseurs TOML dupliqués, suppression de structures DTO dupliquées). Cible : ≥ −150 LOC nettes.
- **FR-014** : La migration DOIT préserver l'isolation `@MainActor` actuelle pour les modules manipulant AppKit/SwiftUI (RoadieRail) et l'API actor-isolated des modules tiling où elle existe déjà.
- **FR-015** : Le système DOIT, au démarrage, vérifier les permissions Accessibility et Screen Recording dans cet ordre, et logger un état clair (granted/denied/pending) pour chacune.
- **FR-016** : Le système DOIT continuer à émettre tous les événements existants (`stage_changed`, `desktop_changed`, `window_*`, `display_configuration_changed`, etc.) via le socket Unix `roadie events --follow`, avec schéma identique. La consommation in-process par RoadieRail ne doit PAS bypasser le bus public.
- **FR-017** : Le système DOIT fournir un script de désinstallation (`scripts/uninstall.sh`) qui retire `~/Applications/roadied.app`, **et** `~/Applications/roadie-rail.app` s'il existe (héritage V1), **et** les deux LaunchAgents (le nouveau et l'ancien rail si présent).
- **FR-018** : Le rail (UI panel SwiftUI) DOIT préserver son comportement utilisateur observable identique à V1 : 1 panel par écran (ou 1 sur primary en mode global), edge-hover, fade-in/out, persistance configurable, drag-drop window, menu contextuel, tap-to-switch, halo de stage active, renderers (parallax-45, stacked-previews, mosaic, hero-preview, icons-only).
- **FR-019** : Tous les tests d'acceptation existants (matrices SPEC-014, SPEC-018, SPEC-019, SPEC-022) DOIVENT continuer à passer sans modification fonctionnelle.
- **FR-020** : Le système DOIT exposer un nouveau drapeau de statut dans `roadie daemon status --json` indiquant la version de l'architecture (`"arch_version": 2` ou similaire) afin que les outils tiers puissent détecter l'environnement V2 vs V1.

### Out of Scope (V2)

- Migration vers les SkyLight write APIs (interdit par contraintes SIP / ADR-001 / ADR-005).
- Refonte des modules internes RoadieTiler, RoadieCore, RoadieDesktops, RoadieStagePlugin (gardés intacts).
- Changement du protocole IPC sur socket Unix (schéma préservé pour CLI/SketchyBar).
- Ajout de nouvelles capacités UI (ex: nouveau renderer, nouvelle commande). Strict refacto.
- Migration vers Apple Developer ID signing.
- Suppression du binaire CLI `roadie` (gardé pour scripts shell, BTT, SketchyBar).
- Animation Bézier sur fenêtres tierces, blur, opacity (cf. plan SPEC-004→010 famille SIP-off, indépendant).

### Key Entities

- **Process unifié `roadied`** : exécutable NSApplication mono-process. Active en `.accessory`. Contient en interne tous les modules : RoadieCore, RoadieTiler, RoadieStagePlugin, RoadieDesktops, RoadieRail, ainsi que le serveur IPC Unix-socket.
- **EventBus in-process** : mécanisme de publication/souscription d'événements en mémoire (Combine ou équivalent), partagé entre le module tiling (publisher) et le module rail (subscriber). Remplace la sérialisation JSON sur socket pour la consommation interne uniquement.
- **Serveur IPC Unix-socket** : reste l'API publique du process unifié. Continue à servir CLI, SketchyBar, scripts externes. Schéma JSON et commandes identiques à V1.
- **Module RoadieRail** : devient une bibliothèque liée au binaire `roadied` au lieu d'un binaire séparé. L'`AppDelegate` actuel devient un `RailController` initialisé par le bootstrap du process unifié.

### Assumptions

- **Article 0 minimalisme** : pas de nouveau module, pas d'abstraction prématurée, pas de framework générique d'EventBus si l'existant suffit.
- **Article G LOC** : plafond projet inchangé. La migration doit produire un solde **négatif** (~ −150 à −300 LOC nettes) grâce à la suppression de RailIPCClient, du serveur IPC pour events purs, des helpers `decodeBool/Int/String` (cast direct), du parseur TOML dupliqué, des DTOs dupliqués.
- **launchd respawn semantics** : ThrottleInterval=30 actuel suffit. Pas de nouvelle stratégie KeepAlive.
- **TCC ad-hoc signing** : `roadied-cert` continue à être l'autorité unique. Le designated requirement reste basé sur `identifier "com.roadie.roadied" and certificate leaf = H"<sha1>"`.
- **SwiftUI dans un process accessory** : supporté nativement par macOS 13+. Les `NSPanel` non-activating, les overlays, les events globaux (`NSEvent.addGlobalMonitorForEvents`) fonctionnent dans ce contexte (déjà éprouvé par `roadie-rail` V1).
- **Compat ascendante CLI** : le binaire `roadie` (CLI) reste séparé et signé indépendamment. Aucun utilisateur n'a besoin de modifier ses scripts/raccourcis BTT/configs SketchyBar.
- **Migration utilisateur en place** : à la première installation V2, le script `install-dev.sh` détecte la présence d'un ancien `roadie-rail.app` et le désinstalle automatiquement. Un toggle TCC manuel est requis (la nouvelle signature unifiée n'est pas reconnue par les anciennes grants).

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001** : Après installation fraîche, l'utilisateur active **2 entrées TCC** au total (1 Accessibility + 1 Screen Recording) au lieu de **3 à 4 entrées** aujourd'hui (1 Accessibility roadied + 1 Screen Recording roadied + 1 Screen Recording roadie-rail). Réduction ≥ 33 %.
- **SC-002** : Le temps total `swift build → install-dev.sh → process-up-and-ready` mesuré sur 5 itérations consécutives décroît d'au moins 25 % par rapport à la baseline V1.
- **SC-003** : Sur une session d'utilisation de 30 minutes (drag-drop fenêtres, switch desktop, hover rail), zéro divergence visible entre l'état affiché par le rail et l'état réel du tiling. Mesuré via test scripté qui échantillonne `state.stagesByDisplay` rail vs `stageManager.stagesV2` daemon toutes les 100 ms.
- **SC-004** : 100 % des 13 raccourcis BTT existants, 100 % des commandes CLI publiques, et 100 % du plugin SketchyBar continuent à fonctionner sans modification utilisateur post-migration. Validé par checklist exhaustive.
- **SC-005** : Le solde net en LOC effectives du projet après migration est **négatif ou nul** (mesure : `find Sources -name '*.swift' -exec grep -vE '^\s*$|^\s*//' {} + | wc -l`). Cible : ≥ −150 LOC nettes par rapport à HEAD pré-migration.
- **SC-006** : Latence p95 d'apparition du rail sur hover edge ≤ 100 ms (mesurée sur 100 itérations dans un script de bench reproductible).
- **SC-007** : Le rail apparaît visuellement en moins de 3 secondes après le démarrage du process (mode `persistence_ms = 0` always-visible).
- **SC-008** : Aucune entrée "roadie-rail" dans Réglages Système → Confidentialité → Enregistrement d'écran après une installation fraîche V2 ou un upgrade V1→V2 propre.
- **SC-009** : `roadie daemon status --json` expose un champ `arch_version` permettant à un consommateur tiers de distinguer V1 de V2.

## Migration & Compatibilité

### Migration utilisateur (V1 → V2)

1. Premier lancement de `install-dev.sh` après pull du code V2 :
   - Détecte la présence d'`~/Applications/roadie-rail.app` ⇒ supprime proprement (l'ancien binaire ne fait plus partie de la distribution).
   - Détecte un éventuel ancien `LaunchAgent` du rail ⇒ bootout + delete plist.
   - Tue tout process `roadie-rail` résiduel.
   - Déploie `~/Applications/roadied.app` avec le nouveau binaire unifié.
   - Bootstrap le `LaunchAgent` `com.roadie.roadie` (déjà existant, plist inchangé).
2. Au premier démarrage du nouveau binaire, l'utilisateur voit potentiellement **deux prompts TCC** (Accessibility + Screen Recording) sur la nouvelle signature. Documenté dans le README.
3. Les anciennes grants associées à `com.roadie.roadie-rail` deviennent orphelines ; elles sont nettoyées automatiquement par macOS (ou résident dans le panel Settings sans effet ; non bloquant fonctionnellement).
4. Aucune manipulation utilisateur sur BTT, SketchyBar, scripts shell : tout reste fonctionnel à l'identique.

### Compatibilité descendante (CLI publique)

Le contrat suivant est figé et garanti par cette spec :

- Liste des commandes CLI publiques : `roadie stage * | desktop * | window * | display * | events --follow | daemon * | fx *`.
- Chemin du socket Unix : `~/.roadies/daemon.sock`.
- Schéma JSON des requests/responses : inchangé.
- Schéma JSON des events (`stage_changed`, `desktop_changed`, `window_*`, `display_configuration_changed`, etc.) : inchangé.
- Codes de retour CLI : inchangés.
- Format des fichiers persistés (stages.json, configs TOML) : inchangés.

Toute violation de ce contrat = breaking change = nécessite une nouvelle SPEC explicite.

## Notes pour la phase de planification

- L'implémentation devra s'articuler en au moins 4 user stories indépendamment livrables (US1 setup binaire, US2 rail in-process, US3 cleanup ancien rail, US4 docs+tests).
- La transition `Sources/RoadieRail/main.swift` → liaison statique au binaire `roadied` est le point central techniquement risqué (init NSApplication, run loop, lifecycle).
- Le mécanisme `EventBus` in-process devra s'appuyer sur l'existant si possible (RoadieDesktops a déjà un `EventBus` actor — vérifier s'il peut servir au rail).
- Garder un test scripté de bench latence rail (SC-006) tout au long de l'implémentation pour détecter une régression précoce.
