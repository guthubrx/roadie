# Constitution Projet 002-tiler-stage

**Version** : 1.2.0 | **Créé** : 2026-05-01 | **Dernier amendement** : 2026-05-01 (Phase 9 — principe I' architecture pluggable validé empiriquement par TilerRegistry, MouseRaiser, PeriodicScanner) | **Pour** : SPEC-002 et au-delà

Cette constitution complète celle de SPEC-001 (`constitution.md`) en adaptant les principes pour l'échelle du tiler+stage manager (~2 500 LOC, multi-fichier, daemon).

**Inclusion par référence** : `@~/.speckit/constitution.md` + `@.specify/memory/constitution.md` (SPEC-001)

---

## Principes adaptés

### A'. Suckless en esprit, multi-fichier en pratique
Le scope du daemon (~2 500 LOC) rend le mono-fichier ingérable. Adaptation : **chaque fichier Swift < 200 lignes effectives**, **chaque module < 800 LOC total**. Si un fichier dépasse, le découper. Si un module dépasse, justifier dans plan.md.

### B'. Dépendances minimisées, pas zéro
Pour SPEC-001 zéro dépendance était possible. Pour SPEC-002, **TOMLKit** est accepté pour parser la config (à internaliser en V2 si scope reste raisonnable). Toute autre dépendance externe DOIT être justifiée explicitement dans `plan.md` Complexity Tracking. Pas de framework "au cas où".

### C'. Identifiants stables (inchangé)
`CGWindowID` reste la clé primaire. `_AXUIElementGetWindow` (privé stable depuis 10.7) autorisé. **`SLS*`/SkyLight et scripting addition Dock interdits** (FR-005).

### D'. Fail loud, log structuré (renforcé)
- Stderr : erreurs utilisateur immédiates
- Logger JSON-lines : événements daemon (`~/.local/state/roadies/daemon.log`)
- Pas de `print()` dans le code (sauf bootstrap pré-Logger)
- Pas de `try!` (sauf bootstrap)
- Pas de `// todo` non tracé : chaque TODO fait référence à un suivi (`// TODO(SPEC-003): ...`)

### E'. Format texte plat pour l'humain
- Config : TOML (lisible vi)
- État stages : TOML
- Protocol socket : JSON-lines (machine-friendly mais grep-able)
- Logs : JSON-lines

### F'. CLI minimaliste mais expressive
SPEC-001 = 4 commandes. SPEC-002 a besoin de plus (focus, move, resize, tiler set, stage *). Adaptation : **commandes en namespace** (`roadie <object> <verb>`) pour rester structuré. Pas plus de 12 commandes top-level en V1.

### G'. Mode Minimalisme LOC explicite (cf. principe G constitution.md)

Pour SPEC-002 spécifiquement :

- **Cible** : 2 000 LOC effectives Swift (sans commentaires ni blanches), répartis ~Core 700 + Tiler 900 + StagePlugin 400 + binaires 400.
- **Plafond strict** : 4 000 LOC effectives. Atteint ou approché → refactor avant nouvelle feature.
- **Mesure de référence** :
  ```bash
  find Sources -name '*.swift' -exec grep -vE '^\s*$|^\s*//' {} + | wc -l
  ```

Toute évolution V1.x qui pousserait au-dessus de 4 000 LOC sans suppression équivalente DOIT déclencher un ADR justifiant le coût.

V1 actuel : 2 014 LOC ✓ (marge 50 % avant plafond).

### H'. Test-pyramid réaliste
- **Unitaire** : tout le code pur (Tiler, Tree, parsing). XCTest. Doit tourner sans display.
- **Intégration** : daemon + CLI ensemble, scripts shell. Nécessite session graphique.
- **Acceptation manuelle** : click-to-focus sur 10 apps, documenté en `docs/manual-acceptance/`.
- Pas de CI macOS prévue (impossible en GHA sans display + AX).

### I'. Architecture pluggable obligatoire
- **Tiler** : protocole Swift, ≥ 2 implémentations en V1 (BSP + Master-Stack).
- **StagePlugin** : module séparé du Tiler, désactivable via flag de build et config.
- **HideStrategy** : enum + impl séparées (corner / minimize / hybrid).
- L'ajout d'une nouvelle implémentation NE DOIT PAS exiger de modification du Core.

---

## Gates Constitution Projet (vérifiées par `/speckit.plan` et `/speckit.analyze`)

- [ ] Aucun fichier Swift > 200 LOC effectives (sauf justifié explicitement)
- [ ] Aucune dépendance externe non justifiée dans plan.md
- [ ] CGWindowID utilisé partout, jamais `(bundleID, title)` comme clé primaire
- [ ] FR-005 respecté : aucun usage SkyLight/SLS/scripting addition
- [ ] Tiler protocol respecté (au moins 2 implementations en V1)
- [ ] StagePlugin réellement séparé (compile sans Stage si flag off)
- [ ] Logger structuré utilisé partout, jamais `print()`
- [ ] Tests unitaires existants pour code pur (Tiler, Tree, Config)
- [ ] **LOC effectives < 4 000 plafond strict** (cible 2 000) — principe G' / G constitution.md
- [ ] **Audit `/audit` mesure et rapporte le LOC effectif** dans `scoring.md`

---

## Articulation avec SPEC-001

SPEC-001 (`stage` mono-fichier) reste **livré** et autonome. Les apprentissages incorporés ici :

- Codesign ad-hoc + bundle `.app` obligatoire pour TCC Sequoia/Tahoe → reproduit dans Makefile
- `_AXUIElementGetWindow` réutilisé tel quel (validé en prod sur SPEC-001)
- Format texte plat éditable conservé (TOML au lieu de TAB-séparé, mais même esprit)
- Fail loud sur stderr conservé

Le projet `roadies` (SPEC-002) est un **successeur**, pas un remplacement de `stage`. Les utilisateurs qui veulent du minimaliste pur restent sur SPEC-001 ; ceux qui veulent un tiler complet passent sur SPEC-002.
