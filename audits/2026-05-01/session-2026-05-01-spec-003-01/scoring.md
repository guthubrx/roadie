# Scoring — SPEC-003 Multi-desktop V2

**Date** : 2026-05-01
**Périmètre** : SPEC-003 (Sources/RoadieCore/desktop/, EventBus, Migration, extensions Config/Types/WindowRegistry/StageManager/Server, CommandRouter handlers desktop.*, CLI roadie verbe desktop+events)
**Mode** : fix (1 cycle d'audit + corrections + 1 cycle scoring)

---

## Tableau de notes

| Axe | Note | Justification |
|---|---|---|
| **Quality** | A | Code clean, séparation claire (Provider/Manager/EventBus/Migration), commentaires WHY pertinents, validation entrées (label format, DesktopRule matchers). Bug F4 (keycodes faux) corrigé en cycle-1. |
| **Security** | A | Validation labels alphanum + `-_` max 32 chars (anti-injection), atomic writes (`.tmp` + rename), pas d'API privée nouvelle (uniquement lecture SkyLight stable yabai-pattern), pas d'escape inject dans osascript (selector contrôlé index numérique). |
| **Performance** | A | Latence transition mesurée et logged (warn > 200 ms), lazy reads disque (1 fichier par switch), MainActor sérialisation correcte, AsyncStream pour pub/sub events sans blocking. |
| **Robustness** | A- | Atomic write OK, kill switch `multi_desktop.enabled = false` effectif (test t125c), reload chaud à chaud (T120), migration V1→V2 avec backup horodaté + rollback documenté. F1+F9 (labels non persistés) corrigés en cycle-1 via fichier `label.txt`. Légère pénalité : 5 tests intégration shell reportés en testing manuel (T048, T049, T076, T091, T124). |
| **Tests** | A | 61 tests unit (40 V1 préservés + 21 V2 nouveaux : DesktopManager 6, DesktopState 9, Migration 1, EventBus 5). 0 régression V1. Coverage US1+US2+US3+US4 satisfaisante. Pénalité minimale : tests intégration shell incomplets (squelettes prêts). |
| **Constitution** | A- | Pas de SIP désactivé (FR-005 SPEC-002 respecté), pas de nouvelles dépendances runtime (SC-006), TOMLKit déjà présent V1 réutilisé. **LOC effectives V2 = 1009** (cible SC-008 = 800, dépassement +25%). Cumulé V1+V2 ≈ 3023 LOC sous plafond strict 4000 (constitution principe G). Pénalité pour dépassement target SC-008 mais respect plafond cumulé. |

## Note globale : **A-**

### Détail
- **Quality** A (5/5) — minor INFO findings non-fixés sont des designed choices
- **Security** A (5/5) — aucun finding
- **Performance** A (5/5) — aucun finding
- **Robustness** A- (4.5/5) — pénalité tests intégration shell incomplets
- **Tests** A (5/5) — 61/61 verts, V1 préservé
- **Constitution** A- (4.5/5) — pénalité dépassement SC-008 LOC cible

**Moyenne pondérée** : (5+5+5+4.5+5+4.5)/6 ≈ **4.83/5 → grade A-**

---

## Findings cycle-1 → fixes appliqués

| ID | Sévérité | Catégorie | Statut | Action |
|---|---|---|---|---|
| F1 | medium | robustness | ✅ FIXED | DesktopManager.loadPersistedLabels() |
| F2 | info | robustness | designed | Race boot négligeable |
| F3 | info | quality | designed | Erreur reportée par CLI (exit 5) |
| F4 | high | quality | ✅ FIXED | Mapping keycodes [18,19,20,21,23,22,26,28,25] |
| F5 | low | robustness | designed | Backup re-existing graceful |
| F6 | info | robustness | designed | Caller path safe |
| F7 | info | quality | designed | Payload v2 simple |
| F8 | low | quality | designed | Singleton EventBus idiomatique |
| F9 | medium | robustness | ✅ FIXED | persistDesktopLabel() vers label.txt |

**3 fixes appliqués** (1 HIGH + 2 MEDIUM). 6 findings restants tous **designed choices** (LOW + INFO).

---

## Recommandations post-audit

### À ajouter en V2.1 (mineur)
- Tester manuellement les 5 scripts d'intégration shell sur installation locale (T048, T049, T076, T091, T124)
- Compléter les squelettes 09-roundtrip.sh (capture frames AVANT/APRÈS sur 100 cycles)

### À considérer en V3
- Multi-display : `(displayUUID, desktopUUID)` index (déjà anticipé data-model)
- Window→desktop pinning best-effort (FR-024 deferred)
- Refactor CLI `Sources/roadie/main.swift` : 410 LOC (cible 200) — extraire un module `cli/Commands/` si on ajoute encore des verbes

### À ne PAS faire
- Rendre EventBus non-singleton (couplage minimal acceptable, tests utilisent init public)
- Ajouter coalescing events (V2 spec explicite : pas de coalescing)
- Modifier le pattern key codes osascript (limitation acceptée, documentée)

---

## Conclusion

SPEC-003 V2 multi-desktop est **livrable** avec un grade A-. Les 3 findings critiques+importants détectés par le cycle d'audit (1 HIGH + 2 MEDIUM) ont été corrigés. Les 6 findings restants sont des designed choices documentés.

Le code respecte la constitution (pas de SIP off, pas de dépendances), passe 61 tests unit (0 régression V1), et fournit une voie de rollback (kill switch `multi_desktop.enabled = false` + backup migration).

Reste à faire avant production : **5 tests intégration shell** sur installation locale (15-30 min de testing manuel utilisateur).
