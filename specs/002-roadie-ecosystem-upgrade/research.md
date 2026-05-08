# Research: Roadie Ecosystem Upgrade

## Sources locales consultées

- `Sources/RoadieDaemon/EventLog.swift` : journal JSONL existant et modèle `RoadieEvent`.
- `Sources/roadie/main.swift` : commandes CLI existantes (`windows list --json`, `state`, `tree`, `events tail`, etc.).
- `Sources/RoadieCore/Config.swift` : configuration TOML existante et tables actuellement non supportées.
- `Sources/RoadieDaemon/StageStore.swift` : persistance des desktops/stages.
- `Sources/RoadieDaemon/LayoutIntentStore.swift` : persistance des intentions de layout.
- `Sources/RoadieStages/RoadieState.swift` : modèle runtime display/desktop/stage/window.

## Décision 1: contrat événementiel versionné

**Decision**: garder le journal append-only `~/.roadies/events.jsonl`, mais stabiliser l'enveloppe événementielle avec `schemaVersion`, `id`, `timestamp`, `type`, `scope`, `subject`, `correlationId`, `cause`, `payload` et `schema`.

**Rationale**: le journal actuel est simple et déjà intégré. Le problème n'est pas le support de stockage, mais l'absence de contrat exploitable par une barre, un script ou un outil de debug.

**Alternatives considered**:

- Remplacer immédiatement par un socket IPC : plus puissant, mais augmente le risque et le nombre de composants avant même d'avoir stabilisé le vocabulaire.
- Garder `[String:String] details` : insuffisant pour les payloads structurés, les migrations et la compatibilité.

## Décision 2: abonnement CLI par suivi du journal en tranche 1

**Decision**: exposer `roadie events subscribe` comme commande longue qui suit le journal et peut émettre un snapshot initial. La commande doit rester compatible avec une future implémentation socket.

**Rationale**: c'est suffisant pour SketchyBar, scripts shell et dashboards locaux. Cela évite d'introduire un serveur supplémentaire tant que la demande principale est l'observabilité.

**Alternatives considered**:

- Socket bidirectionnel immédiat : utile à terme, mais plus risqué pour une première tranche.
- Hooks shell uniquement : déjà proche de l'existant et trop coûteux par événement.

## Décision 3: state API CLI stable avant refonte IPC

**Decision**: ajouter une famille de lectures stables (`roadie query ...` ou aliases documentés) au-dessus des snapshots existants au lieu de remplacer `state`/`tree`.

**Rationale**: les commandes actuelles servent déjà au debug. Les intégrations externes ont besoin d'un format plus ciblé, pas d'une rupture.

**Alternatives considered**:

- Un seul dump global : simple, mais force chaque intégration à réimplémenter des filtres.
- Répliquer l'API Hyprland complète : hors scope macOS et trop large pour Roadie.

## Décision 4: moteur de règles TOML, priorité stable, validation forte

**Decision**: introduire `[[rules]]` avec blocs `match` et `action`, priorité explicite, `enabled`, et commande de validation qui explique les erreurs sans appliquer les règles.

**Rationale**: Roadie a déjà un fichier de configuration TOML. Les règles doivent être lisibles, versionnées dans Git et testables sans lancer le daemon.

**Alternatives considered**:

- DSL custom type yabai/hyprland : puissant, mais augmente le coût d'apprentissage.
- Scripts shell par fenêtre : flexible, mais dangereux et difficile à diagnostiquer.

## Décision 5: groupes comme conteneurs Roadie, pas comme fonctionnalité macOS

**Decision**: modéliser les groupes dans l'état Roadie : un groupe occupe un slot de layout, contient plusieurs fenêtres membres, expose un membre actif et produit des événements dédiés.

**Rationale**: cela reproduit les stacks/tabs utiles de yabai/Hyprland sans dépendre de Spaces natifs ou d'API privées.

**Alternatives considered**:

- Utiliser les tabs natives macOS : comportement dépendant des apps, peu contrôlable par AX.
- Déplacer les fenêtres inactives dans un autre desktop/stage : casse la sémantique de groupe et complique le focus.

## Décision 6: pas de hotkey daemon ni plugin runtime dans cette feature

**Decision**: Roadie reste BTT-friendly et CLI-first. Les modes de binding/submaps ne sont pas implémentés dans cette tranche ; les plugins runtime restent hors scope.

**Rationale**: ce sont deux surfaces à fort coût de maintenance et de sécurité. Le vrai manque bloquant est l'écosystème observable, pas la capture clavier.

**Alternatives considered**:

- Recréer un mini-skhd : dette importante pour peu de valeur si BTT reste le front.
- Plugins dynamiques : problèmes de signature/notarization, surface d'attaque et API interne instable.
