# Brief commun aux agents d'implémentation (SPEC-016)

Dépôt : `/path/to/roadie` (Swift 6, macOS 14+, gestionnaire de fenêtres tiling « Roadie »). Branche `016-roadie-stabilization`.

## À lire avant de coder

- `specs/016-roadie-stabilization/spec.md` (exigences FR-xxx)
- `specs/016-roadie-stabilization/review-findings.md` (constats détaillés avec fichier:ligne)
- `specs/016-roadie-stabilization/plan.md` (lots, interfaces fixées)
- `specs/016-roadie-stabilization/research.md` (décisions techniques R1 à R15)
- `specs/016-roadie-stabilization/tasks.md` (tes tâches, par ID)
- `specs/016-roadie-stabilization/contracts/` si ton lot est concerné

## Règles de travail parallèle (STRICTES)

1. **Tu ne modifies QUE les fichiers de ton lot** (liste dans ton prompt). Plusieurs agents travaillent en même temps sur d'autres fichiers du même dépôt.
2. **Ne commite pas, ne fais aucune commande git qui modifie l'index ou l'historique** (`git add`, `commit`, `stash`, `checkout`, `reset`). L'orchestrateur commite par lot. `git diff` et `git status` sont autorisés.
3. **Ne modifie pas `tasks.md`**. Indique dans ton rapport final les tâches terminées.
4. **Build et tests avec ton propre répertoire de build** pour ne pas bloquer les autres :
   - `./scripts/with-xcode swift build --scratch-path /tmp/roadie-build-<lot>`
   - `./scripts/test --scratch-path /tmp/roadie-build-<lot> --filter <TesSuites>`
   Le premier build prend environ 3 minutes.
5. Si le build échoue **dans un fichier qui n'est pas à toi**, c'est probablement un autre agent en cours d'édition : attends 2 minutes et relance (3 fois au plus), puis signale-le dans ton rapport sans toucher ce fichier.
6. Si tu as besoin d'un changement dans un fichier d'un autre lot, ne le fais pas : décris-le précisément dans ton rapport (fichier, fonction, changement).

## Règles de qualité

- Minimalisme (constitution Article XIX) : la plus petite correction qui satisfait l'exigence ; pas de wrapper ni d'option non demandés ; réutiliser l'existant (`FileLock`, `ConfigReloadService`, `HiddenWindowPlacement`, `LayoutTolerance`, `StageStore.mutate`).
- Avant de créer un fichier, un type ou un helper : chercher l'existant (`rg -n "<nom>"` et `rg -n "<concept>"`) et le dire dans le rapport.
- Commentaires en français, au niveau de densité du code existant. Annoter la complexité des fonctions publiques non triviales (`// O(n)`).
- Ne pas casser les tests existants. Si un test existant encode l'ancien comportement défectueux, l'adapter en expliquant pourquoi dans le rapport.
- Pas de `kill`, pas de lancement du daemon réel, pas de modification de `~/.roadies` ni de `~/.config`.
- Deux échecs sur la même hypothèse : observer des données réelles (test ciblé, print) avant une 3e tentative.

## Rapport final attendu (court, en français)

1. Tâches terminées (IDs) et non terminées avec la raison.
2. Fichiers modifiés ou créés (chemins absolus).
3. Tests lancés (commande exacte) et résultat.
4. Changements demandés aux autres lots (fichier, fonction, besoin).
5. Ce qui n'a pas été vérifié.
