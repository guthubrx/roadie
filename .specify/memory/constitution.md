# Constitution — Projet 39.roadies (Stage Manager)

**Version** : 1.1.0 | **Créé** : 2026-05-01 | **Dernier amendement** : 2026-05-01 (ajout principe G)

Ce projet hérite de la constitution globale SpecKit qui définit les règles transversales (français, processus SpecKit obligatoire, circuit breaker anti-tunnel, ADR, etc.).

**Inclusion par référence** : `@~/.speckit/constitution.md`

Les principes ci-dessous sont **spécifiques** à 39.roadies et complètent (sans dupliquer) la constitution globale.

---

## Principes Projet

### A. Suckless avant tout
Toute fonctionnalité DOIT être implémentée avec le minimum de code possible. Critère mesurable : si une feature dépasse 50 lignes Swift à elle seule, c'est qu'elle est trop complexe — découper ou redesign. Mono-fichier `stage.swift` tant qu'on peut.

### B. Zéro dépendance externe
Ni SwiftPM, ni Cocoapods, ni Carthage. Uniquement les frameworks système macOS (Cocoa, ApplicationServices, CoreGraphics). Build via `swiftc` direct, pas de `Package.swift`. Si un besoin externe émerge, le résoudre par lecture du protocole/format à la main (ex: parsing JSON par regex sur un format simple plutôt qu'embarquer un decoder).

### C. Identifiants stables uniquement
Toute fenêtre doit être identifiée par `CGWindowID` (UInt32). L'utilisation de `(bundleID, title)` est interdite — les terminaux changent de titre en permanence et ça casse silencieusement. L'API privée `_AXUIElementGetWindow` est autorisée et préférée pour faire le pont AX↔CG.

### D. Fail loud, no fallback
Si une fenêtre du stage n'est plus trouvable (app quittée, CGWindowID périmé), l'outil DOIT afficher l'erreur explicitement sur stderr et la retirer du fichier de stage. Pas de retry silencieux, pas de "best effort" qui masque le problème.

### E. État sur disque = format texte plat
Pas de JSON, pas de YAML, pas de SQLite. Format imposé : un fichier par stage dans `~/.stage/<N>`, une ligne par fenêtre, séparateurs TAB. Le but : `cat`, `grep`, `awk` doivent suffire pour debug. Le code de parsing tient en 5 lignes.

### F. CLI minimaliste
4 sous-commandes maximum : `stage <N>` (switch), `stage assign <N>` (frontmost → stage N). Aucune option flag, aucun mode verbeux, aucune sortie superflue. Sortie standard utilisée uniquement pour les erreurs (sur stderr).

### G. Mode Minimalisme LOC explicite (NÉGOCIABLE par spec)

Toute spec DOIT déclarer dans son `plan.md` Technical Context une **cible LOC effectives** (sans commentaires ni blanches) et un **plafond strict** (typiquement +30 % au-dessus de la cible).

- **Cible** : ce qu'on vise raisonnablement.
- **Plafond** : si dépassé, refactor obligatoire OU justification explicite dans `Complexity Tracking` (= ADR si écart > 50 %).

Exemples par échelle :
- Outil mono-fichier suckless : cible 100, plafond 200 (cf. SPEC-001 = 190 ✓).
- Daemon multi-modules : cible 2 000, plafond 4 000 (cf. SPEC-002 = 2 014 ✓).
- Application complexe : cible et plafond négociés cas par cas.

L'audit `/audit` DOIT mesurer le LOC effectif (commande de référence : `find Sources -name '*.swift' -exec grep -vE '^\s*$|^\s*//' {} + | wc -l`) et flagger HIGH si plafond dépassé sans justification active.

**Principe sous-jacent** : chaque ligne de code est une dette future. Avant d'ajouter, demande-toi si tu peux faire pareil avec moins (refactor d'un helper, suppression de cas pathologique, simplification d'API). Le code que tu n'écris pas n'a jamais de bug.

---

## Gates de Conformité (vérifiées par `/speckit.plan`)

Avant tout passage en Phase 2 Plan, vérifier :

- [ ] Aucun `import Package` ni dépendance tierce dans le design proposé (sauf justifié dans Complexity Tracking, cf. principe B/B')
- [ ] Aucun usage de `(bundleID, title)` comme clé primaire
- [ ] Toute action sur fenêtre doit pouvoir être tracée à un `CGWindowID`
- [ ] Le binaire compilé doit faire moins de 500 KB pour les specs mono-fichier, < 5 MB pour les daemons (suckless de fait)
- [ ] **Cible et plafond LOC déclarés dans plan.md Technical Context** (principe G)

Toute violation DOIT être justifiée explicitement dans la section "Complexity Tracking" du `plan.md`, sinon STOP.
