# Brief commun aux agents d'implémentation (SPEC-017)

Dépôt : `/path/to/roadie` (Swift 6, macOS 14+, gestionnaire de fenêtres tiling « Roadie »). Branche `017-reactive-tiling`.

## À lire avant de coder

- `specs/017-reactive-tiling/spec.md` (exigences FR-xxx)
- `specs/017-reactive-tiling/data-model.md` et `contracts/layout-events.md`
- `specs/017-reactive-tiling/plan.md` (lots, interfaces fixées)
- `specs/017-reactive-tiling/research.md` (décisions techniques R1 à R15, avec les interfaces fixées de plan.md)
- `specs/017-reactive-tiling/tasks.md` (tes tâches, par ID)
- `specs/017-reactive-tiling/contracts/` si ton lot est concerné

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

- Minimalisme (constitution Article XIX) : la plus petite correction qui satisfait l'exigence ; pas de wrapper ni d'option non demandés ; réutiliser l'existant (`BSPTree`, `fileModificationStamp`, `UserInputActivity`, `LayoutTolerance`, `StageStore.mutate`, `WrittenFrameRegistry`).
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

## Spécifique à la SPEC-017

- Le but est la réactivité et le comportement de yabai : un événement, une passe, l'arbre fait foi, aucune relecture de géométrie pour recalculer la disposition (sauf geste manuel reconnu à la souris).
- Supprime le code devenu mort dans tes fichiers (FR-018) et dis combien de lignes tu as retirées.
- Les tests `mutableBsp` de tes fichiers de tests : réécris-les pour l'arbre s'ils protègent un comportement encore voulu, sinon retire-les en donnant la raison dans ton rapport.
- Ne casse pas `masterStack`, `bsp` et `float` : une protection partagée devient conditionnelle au mode, elle n'est pas supprimée.
