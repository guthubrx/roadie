# Brief commun aux agents d'implémentation (SPEC-023)

Dépôt : `/Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/023-command-box-settings` (worktree, branche `023-command-box-settings`). Swift 6, macOS 14+, gestionnaire de fenêtres « Roadie ». **Travaille uniquement dans ce dossier** (chemins absolus). Ne `cd` jamais vers `/Users/moi/Nextcloud/10.Scripts/39.roadie` (dépôt principal).

## À lire avant de coder

Dossier `specs/023-command-box-settings/` : `spec.md` (FR/SC), `plan.md`, `research.md` (décisions R1 à R11 et inventaire des réglages), `data-model.md` (types), `contracts/slash-commands.md`, `contracts/settings.md`, `tasks.md` (tes tâches par ID), `adversarial-review-codex.md` (défauts déjà relevés : ne pas les réintroduire), `reuse-audit.md` (ce qu'il faut réutiliser).

## Règles de travail parallèle (STRICTES)

1. **Tu ne modifies QUE les fichiers de ton lot** (liste dans ton prompt). D'autres agents travaillent en même temps sur d'autres fichiers du même dépôt.
2. **Ne commite pas et ne lance aucune commande git qui modifie l'index ou l'historique** (`add`, `commit`, `stash`, `checkout`, `reset`). `git diff` et `git status` sont permis. L'orchestrateur commite par lot.
3. **Ne modifie pas `tasks.md`.** Donne les IDs terminés dans ton rapport.
4. **Build et tests avec ton propre répertoire de build** : `./scripts/with-xcode swift build --scratch-path /tmp/roadie-build-023-<lot>` et `./scripts/test --scratch-path /tmp/roadie-build-023-<lot> --filter <Suite>`. Un build complet prend environ 1 minute. Copie préalable possible : `cp -R /tmp/roadie-build-023-base /tmp/roadie-build-023-<lot>` (non garanti ; sinon build complet).
5. Si le build échoue **dans un fichier qui n'est pas à toi**, c'est sans doute un autre agent en cours d'édition : attends 2 minutes et relance (3 fois au plus), puis signale-le dans ton rapport.
6. Besoin d'un changement hors de ton lot : ne le fais pas ; décris-le (fichier, fonction, changement) dans ton rapport.

## Règles de qualité

- Minimalisme (constitution XIX) : la plus petite solution qui satisfait le besoin ; pas d'option, de wrapper ni d'abstraction non demandés. Réutiliser l'existant (`rg -n "<nom>"` puis `rg -n "<concept>"` avant de créer un fichier, un type ou un helper ; le dire dans le rapport).
- Commentaires en français, à la densité du code voisin. Complexité (`// O(n)`) sur les fonctions de filtre, de recherche et d'édition.
- Tests : Swift Testing (`import Testing`, `@Suite`, `@Test`, `#expect`, `#require`), style de `Tests/RoadieDaemonTests/TargetSearchModelTests.swift` et `ConfigTests.swift`. Les tests ne lisent ni n'écrivent jamais `~/.config`, `~/.roadies`, `~/.local/state` : utiliser des dossiers temporaires.
- Ne casse aucun test existant. Si un test existant encode l'ancien comportement, adapte-le en expliquant pourquoi.
- Interdits : `kill`, lancer le daemon réel, `make install`, modifier `~/.config` ou `~/.roadies`.
- Deux échecs sur la même hypothèse : observer une donnée réelle (test ciblé, `print`) avant la 3e tentative.
- Texte affiché à l'utilisateur : français, avec tous les accents.

## Rapport final attendu (court, en français)

1. Tâches terminées (IDs) ; non terminées avec la raison.
2. Fichiers créés ou modifiés (chemins absolus).
3. Tests lancés (commande exacte) et résultat.
4. Changements demandés aux autres lots.
5. Existant réutilisé, existant cherché sans résultat, éléments créés.
6. Ce qui n'a pas été vérifié.
