# Brief commun des agents - Session 022 (corrections de l'audit v14)

## Où travailler

- Dossier de travail UNIQUE : `/Users/moi/Nextcloud/10.Scripts/39.roadie/.worktrees/022-audit-remediation`.
  Ne jamais aller dans `/Users/moi/Nextcloud/10.Scripts/39.roadie` (dépôt principal).
- D'autres agents modifient d'autres fichiers EN MÊME TEMPS dans ce dossier.

## Ta mission

Corriger les constats de ton lot (voir ta consigne et `specs/022-audit-remediation/plan.md`).
Détail de chaque constat (description, preuve, scénario, correction proposée) :
- `audits/2026-10-13/full-codebase-01/cycle-1/aggregated-findings.json` (champ `findings`, par `id`) ;
- `audits/2026-10-13/full-codebase-01/scoring.md` (section du même id).

Pour chaque constat :
1. **Vérifier d'abord** en lisant le code. L'audit peut se tromper. Si le constat est faux, ne rien
   changer et le rejeter avec une preuve (chemin, ligne, raisonnement).
2. **Test d'abord** : écrire un test qui échoue avant la correction (fiabilité) ou qui fige le résultat
   actuel (performance, non-régression). Impossible (frontière système : AX, CGEvent, écran réel) :
   le dire et tester la partie pure extraite.
3. **Corriger** avec le plus petit changement juste. Style du code voisin, commentaires en français,
   pas de refonte hors constat (Article XIX). Aucune mention d'IA nulle part.
4. **Performance** (constats PERF) : résultats identiques ; commentaire de complexité avant/après
   (`// O(n)`), Article XVIII. Mesurer si possible (benchmark temporaire, n représentatif) et donner
   les chiffres avant/après dans ton rapport ; ne pas laisser d'assertion de durée fragile dans les tests.

## Fichiers

- Tu ne modifies QUE les fichiers de ton lot, plus tes nouveaux fichiers de test.
- Nouveaux tests : un fichier par lot, `Tests/<Cible>Tests/Audit022Lot<X>Tests.swift`
  (cibles : RoadieDaemonTests, RoadieTilerTests, RoadieStagesTests, RoadieAXTests). Exception : un lot
  propriétaire d'un fichier de test existant le modifie directement.
- Un correctif exige un fichier d'un autre lot : n'y touche pas. Fais le reste, et signale précisément
  le besoin (fichier, changement) dans ton rapport.
- Erreur de compilation dans un fichier qui n'est pas à toi : un autre agent est en train de l'éditer.
  Attends 1-2 minutes et relance ; ne le corrige pas.

## Compiler et tester

- Toujours avec TON dossier de build : `--scratch-path /tmp/roadie-build-022-<lot en minuscule>`.
  - itération : `swift test --scratch-path /tmp/roadie-build-022-x --filter Audit022LotX`
  - fin : `swift build --scratch-path ...` puis `swift test --scratch-path ...` (suite complète).
- Avant de finir : suite complète verte, ou échecs expliqués comme venant d'un autre lot en cours.

## Interdits

- Pas de `git commit`, `git stash`, `git checkout`, `git reset`, `git add`. L'orchestrateur commite.
- Pas de `make install`, `make restart`, pas d'arrêt de processus (roadied, Firefox, rien).
- Pas de nouvelle dépendance.

## Rapport final (court, en français)

Pour chaque constat : `corrigé` ou `rejeté` (+ preuve), fichiers modifiés, tests ajoutés (noms),
mesures avant/après s'il y a lieu, ce qui n'a pas pu être vérifié, besoins sur des fichiers d'autres
lots. Puis : résultat de la suite complète (nombre de tests, échecs éventuels et leur cause).
