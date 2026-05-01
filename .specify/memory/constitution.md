# Constitution — Projet 39.roadies (Stage Manager)

**Version** : 1.0.0 | **Créé** : 2026-05-01

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

---

## Gates de Conformité (vérifiées par `/speckit.plan`)

Avant tout passage en Phase 2 Plan, vérifier :

- [ ] Aucun `import Package` ni dépendance tierce dans le design proposé
- [ ] Aucun usage de `(bundleID, title)` comme clé primaire
- [ ] Toute action sur fenêtre doit pouvoir être tracée à un `CGWindowID`
- [ ] Le binaire compilé doit faire moins de 500 KB (suckless de fait)

Toute violation DOIT être justifiée explicitement dans la section "Complexity Tracking" du `plan.md`, sinon STOP.
