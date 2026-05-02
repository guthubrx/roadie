# Research — SPEC-018 Stages-per-display

**Status**: Done
**Last updated**: 2026-05-02

## Vue d'ensemble

La description utilisateur d'origine est très détaillée et l'archi cible est explicite : indexation par tuple `(displayUUID, desktopID, stageID)`, résolution implicite par curseur, migration silencieuse, compat ascendante stricte. Aucun NEEDS CLARIFICATION résiduel après la rédaction de spec.md. La phase Research consolide les choix techniques et les sources externes consultées.

## Sources techniques consultées

| Source | Lecture pour | Lien |
|---|---|---|
| yabai source `query.c` | Pattern selector "display under cursor" | https://github.com/koekeishiya/yabai |
| AeroSpace docs `list-workspaces --monitor mouse` | Pattern de scope par écran | https://nikitabobko.github.io/AeroSpace/ |
| Apple docs `CGDisplayCreateUUIDFromDisplayID` | API publique stable, déjà utilisée par SPEC-012 | https://developer.apple.com/documentation/coregraphics/1454603-cgdisplaycreateuuidfromdisplayid |
| Apple docs `Hashable` synthèse Swift 5+ | Conformance auto pour structs avec props Hashable | https://developer.apple.com/documentation/swift/hashable |
| SPEC-012 `Display.swift`, `DisplayRegistry.swift` | Réutilisation `displayUUID` et `displayContaining(point:)` | `Sources/RoadieCore/Display*.swift` |
| SPEC-013 `DesktopRegistry.swift` | Réutilisation `currentID(for: CGDirectDisplayID)` | `Sources/RoadieDesktops/DesktopRegistry.swift` |

## Décisions principales

### R-001 : Indexation par tuple `StageScope`

**Décision** : `struct StageScope: Hashable, Sendable, Codable` avec `displayUUID: String`, `desktopID: Int`, `stageID: StageID`. Dict `[StageScope: Stage]` pour O(1) lookup.

**Rationale** : Hashable synthétisé par le compilateur, type-safe, lisibilité. Aucun overhead vs sous-dicts imbriqués.

**Alternatives évaluées** :
- `[String: [Int: [StageID: Stage]]]` (3 dicts imbriqués) → verbose, rebuild dur
- `Stage` avec `var scope: StageScope` interne → duplication d'état

### R-002 : Résolution implicite curseur → frontmost → primary

**Décision** : `Daemon.currentStageScope()` priorité descendante : (1) `NSEvent.mouseLocation` → display, (2) frontmost frame center → display, (3) primary `CGMainDisplayID()`.

**Rationale** : Pattern yabai/AeroSpace prouvé en prod. Pas d'Input Monitoring permission. Latence négligeable (lookup hash).

**Alternatives évaluées** :
- Toujours frontmost (priorité 1) → moins prédictible si focus ≠ visible
- Toujours primary → casse multi-display

### R-003 : Persistance arborescence nested

**Décision** : `~/.config/roadies/stages/<displayUUID>/<desktopID>/<stageID>.toml` en mode `per_display`. Flat `~/.config/roadies/stages/<stageID>.toml` en mode `global`.

**Rationale** : Arborescence reflète le scope, backup naturel par display, stages orphelines préservées.

**Alternatives évaluées** :
- Fichier unique `stages.toml` avec arrays imbriqués → atomicité plus dure
- Index numérique 1-N de display → instable cross-reboot

### R-004 : Migration V1 → V2 idempotente

**Décision** :
1. Détection au boot V2 : `stages/*.toml` flat existe ET `stages.v1.bak/` n'existe pas
2. Backup `cp -r stages/ stages.v1.bak/`
3. Pour chaque `<id>.toml` : déplacer vers `stages/<mainDisplayUUID>/1/<id>.toml`
4. Émettre event `migration_v1_to_v2` (count, backup_path, target_uuid)
5. Sur erreur disque : flag `migration_pending: true`, fallback flat, daemon démarre quand même

**Rationale** : Idempotent (test backup empêche re-run). Recovery manuelle facile (`mv stages.v1.bak/ stages/`).

### R-005 : Override CLI `--display` `--desktop`

**Décision** : Args optionnels acceptés sur toutes les commandes `stage.*`. Sélecteur display = index 1-N (`roadie display list` order) ou UUID natif. Daemon résout via `DisplayRegistry`.

**Rationale** : Indispensable pour scripts BTT/SketchyBar qui ne dépendent pas du pointeur.

### R-006 : Compat ascendante mode `global`

**Décision** : Si `[desktops] mode = "global"`, tuple interne sentinelle `(emptyUUID, 0, stageID)`, persistance flat, aucune migration. Comportement strictement identique à SPEC-002.

**Rationale** : Zéro régression pour utilisateurs mono-display. Opt-in conscient pour `per_display`.

## Red flags identifiés

| Red flag | Sévérité | Mitigation |
|---|---|---|
| Migration corrompt données | Élevé | Backup `stages.v1.bak/` automatique, flag `migration_pending` si fail, fallback gracieux |
| Race condition résolution scope | Moyen | Fallback chain curseur → frontmost → primary, jamais bloquant |
| Confusion utilisateur ("où est ma stage ?") | Moyen | `stage.list` retourne `display_uuid`, `display_index`, `desktop_id`, `scope_inferred_from` pour transparence |
| Hot-switch mode chaotique | Bas | Documentation "redémarrer le daemon", best effort, pas d'auto-flatten/auto-nest |

## Validation

- ✅ Pattern yabai éprouvé en production multi-display depuis 8+ ans
- ✅ AeroSpace utilise pattern identique avec satisfaction utilisateur (>3000 stars GitHub)
- ✅ `CGDisplayCreateUUIDFromDisplayID` API publique stable depuis macOS 10.0
- ✅ Aucune permission supplémentaire requise (lecture curseur OK avec Accessibility)
- ✅ Compat ascendante garantie via mode `global` (default V1)

## Conclusion

Tous les NEEDS CLARIFICATION sont résolus. La spec et l'archi sont prêtes pour Phase 1 (Design & Contracts).
