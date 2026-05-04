# Feature Specification: Stabilization sprint — boot robustness + BUG-001 fix

**Feature Branch**: `025-stabilization-boot-robustness`
**Created**: 2026-05-04
**Status**: Implemented (mergée sur main, audit grade A-, soak 24h en cours avant tag v0.2.0-stabilization)
**Dependencies**: SPEC-002, SPEC-014, SPEC-018, SPEC-021, SPEC-022, SPEC-024, BUG-001
**Input**: User description: "Stabilization sprint qui regroupe : (Vague 0) désactiver `empty_click_hide_active` par défaut + GC legacy. (Vague 1) Boot robustness : validation `saved_frame` au restore, audit auto au boot, health metric, tests E2E minimaux. (Vague 2) BUG-001 fix réel — `HideStrategyImpl.show()` avec fallback safe + investigation tree leaf manquant. (Vague 3) Commande `roadie heal` + doc troubleshooting README. Zéro nouvelle feature visible utilisateur. Focus exclusif sur la robustesse runtime du daily-driving."

## Contexte et motivation

Sur les 14 derniers jours, roadie a livré 6 SPECs majeures (014, 018, 021, 022, 023, 024) plus plusieurs micro-features (empty-click hide active, recheck-tcc, etc.). Cette vélocité a accumulé des bugs de stabilité dans le runtime que l'utilisateur découvre en daily-driving :

- **BUG-001** documenté : `stage.hide_active` (commit 914b98e) écrit des `saved_frame.y = -2117` dans le state TOML. Au boot, le daemon restore aveuglément ces frames offscreen → fenêtres invisibles, restent coincées même après `stage.switch`.
- **Wids zombies** dans `memberWindows` : les fenêtres fermées ne sont pas systématiquement purgées. Au boot, le tree contient des leafs morts → drift `widToScope` vs `memberWindows` (5 wids zombies observées en une session aujourd'hui).
- **Pollution `~/.config/roadies/stages/`** : plus de 90 fichiers `.legacy.*` accumulés (un par save sur les 5 derniers jours). Aucune GC en place.
- **Audit ownership manuel** : SPEC-024 a livré `daemon audit --fix` qui purge + rebuild. Mais le fix n'est pas appelé automatiquement au boot — l'utilisateur doit le savoir et le déclencher quand quelque chose va mal.
- **Aucun feedback** quand l'état est corrompu : si 30 % des fenêtres ont des frames offscreen au boot, le daemon ne logue rien d'observable. L'utilisateur découvre le problème quand il ne voit plus ses fenêtres.

L'avis franc partagé en début de session : **le produit n'est pas prêt pour daily-driving** parce que la robustesse runtime n'a pas été investie au niveau des features. Cette spec acte un sprint de stabilisation **sans aucune nouvelle feature visible utilisateur**, focalisé exclusivement sur la suppression des classes de drift connues.

## User Scenarios & Testing *(mandatory)*

### User Story 1 — Daily-driving sans fenêtres coincées offscreen (Priority: P1)

**En tant qu'**utilisateur quotidien de roadie,
**je veux** que les fenêtres ne se retrouvent JAMAIS coincées hors écran après un rebuild ou un restart du daemon,
**afin de** ne pas perdre 5 minutes à chaque incident pour récupérer mes fenêtres via des CLI manuelles.

**Why this priority** : c'est le bug N°1 du daily-driving aujourd'hui (BUG-001 + cas dérivés). Tant qu'il n'est pas réglé, l'utilisateur ne peut pas faire confiance à roadie comme WM principal.

**Independent Test** : peut être validé en injectant artificiellement des `saved_frame.y = -9999` dans un fichier TOML stage, puis en restartant le daemon, et en vérifiant que les fenêtres concernées atterrissent dans la zone visible d'un display connu (≠ Y=-9999).

**Acceptance Scenarios** :

1. **Given** un fichier `~/.config/roadies/stages/<uuid>/<desktop>/<stage>.toml` contenant `[members.saved_frame] y = -2117`, **When** le daemon redémarre via launchd, **Then** la fenêtre concernée est repositionnée dans la zone visible d'un display connu (frame Y ∈ AX-coords d'un display réellement connecté).
2. **Given** un cycle complet "ouvrir fenêtre → `stage.hide_active` → `stage.switch <other>` → `stage.switch <original>`", **When** l'utilisateur revient sur la stage initiale, **Then** la fenêtre apparaît visible dans son slot tile (pas Y=-2117).
3. **Given** 10 rebuilds + redéploiements consécutifs sur 1h sans aucune action utilisateur entre, **When** on liste les fenêtres après chaque restart, **Then** zéro fenêtre n'a jamais une frame offscreen.

---

### User Story 2 — Auto-cicatrisation au boot (Priority: P1)

**En tant qu'**utilisateur,
**je veux** que le daemon répare automatiquement son état au démarrage si des incohérences sont détectées,
**afin de** ne pas avoir à mémoriser et lancer `roadie daemon audit --fix` chaque fois qu'un truc déraille.

**Why this priority** : SPEC-024 a livré le fix `audit --fix` mais il faut que l'utilisateur le sache et le déclenche. Le boot est précisément le moment où la majorité des drifts apparaissent (load TOML pollué, wids zombies de la session précédente, etc.). Auto-fix au boot = solution silencieuse pour la majorité des cas.

**Independent Test** : peut être validé en injectant 5 wids inexistantes dans `memberWindows` d'un TOML, restart du daemon, et vérification que `roadie daemon audit` retourne `count: 0` (sans avoir fait `--fix` manuellement).

**Acceptance Scenarios** :

1. **Given** un état persisté contenant 5 wids zombies (ex : ouvertes hier, processus tués depuis), **When** le daemon démarre, **Then** dans les 2 premières secondes du bootstrap, `purgeOrphanWindows()` + `rebuildWidToScopeIndex()` ont été appelés et `auditOwnership()` retourne `[]`.
2. **Given** un drift `widToScope` vs `memberWindows`, **When** le daemon boot, **Then** la log contient `"msg": "boot_audit_autofixed"` avec compteurs `violations_before` et `purged_orphans`.
3. **Given** un boot sans aucun drift à corriger, **When** le daemon démarre, **Then** la log contient `"msg": "boot_audit_clean"`. Pas d'overhead user-visible.

---

### User Story 3 — Visibilité de la santé du state (Priority: P2)

**En tant qu'**utilisateur ou mainteneur,
**je veux** être alerté quand le state du daemon devient suspect (ex : > 30 % des fenêtres avec frames offscreen au restore),
**afin de** détecter un problème AVANT qu'il devienne bloquant pour la session.

**Why this priority** : sans signal, l'utilisateur découvre les bugs en frustration. Un health metric simple au boot (et un endpoint `daemon.health`) permettent au moins de poser un diagnostic objectif.

**Independent Test** : injecter 5 fenêtres dans un stage TOML avec 4 frames offscreen (Y=-9999), restart, vérifier que la log contient un warning explicite avec les pourcentages.

**Acceptance Scenarios** :

1. **Given** un state où ≥ 30 % des fenêtres ont une frame offscreen au moment du restore, **When** le daemon démarre, **Then** un log warn `"msg": "state_health_degraded"` avec `pct_offscreen` est émis + une notification `terminal-notifier` invite à `roadie heal`.
2. **Given** une commande `roadie daemon health`, **When** l'utilisateur l'exécute, **Then** le retour JSON contient : nb total fenêtres, nb offscreen, nb wids tilées sans stage, nb wids dans memberWindows mais absentes du registry. Verdict global : `healthy | degraded | corrupted`.

---

### User Story 4 — `roadie heal` : commande de réparation rapide (Priority: P2)

**En tant qu'**utilisateur quotidien,
**je veux** une commande unique qui orchestre toutes les réparations connues,
**afin de** récupérer un état sain en 1 commande quand quelque chose va mal sans devoir mémoriser 4 étapes.

**Why this priority** : `daemon audit --fix` corrige les drifts mais pas les frames offscreen. Le workaround "stage assign cycle" qu'on utilise n'est pas découvrable. Une commande consolidée = UX simplifiée et procédure mémorisable.

**Independent Test** : créer artificiellement les 3 problèmes connus (drift widToScope, frame offscreen, wid zombie), lancer `roadie heal`, vérifier que le state est entièrement sain ensuite.

**Acceptance Scenarios** :

1. **Given** un état corrompu mixte (drift + offscreen + zombies), **When** l'utilisateur tape `roadie heal`, **Then** la commande affiche un récap `"X drifts fixed, Y wids restored to visible, Z zombies purged"` et exit 0.
2. **Given** un état déjà sain, **When** `roadie heal`, **Then** retour `"already healthy"` et exit 0 (idempotent).
3. **Given** un README "Troubleshooting", **When** un nouveau utilisateur lit la section, **Then** la première recommandation est `roadie heal`, suivie de la procédure manuelle si insuffisante.

---

### User Story 5 — `empty_click_hide_active = false` par défaut (Priority: P1)

**En tant qu'**utilisateur découvrant roadie,
**je veux** que le rail ne hide PAS mes fenêtres par accident sur un clic vide,
**afin de** ne pas perdre des fenêtres en faisant simplement un déclic à côté d'une thumbnail.

**Why this priority** : la feature `stage.hide_active` (commit 914b98e) a été livrée comme "Apple Stage Manager pattern". En pratique, elle est la cause N°1 de fenêtres coincées offscreen quand BUG-001 frappe. Désactivation par défaut = stop the bleeding immédiat.

**Independent Test** : sur une installation fresh, vérifier qu'un clic vide sur le rail ne masque AUCUNE fenêtre. L'utilisateur peut ré-activer via `[fx.rail].empty_click_hide_active = true` s'il le souhaite explicitement.

**Acceptance Scenarios** :

1. **Given** une installation fresh avec config par défaut, **When** l'utilisateur clique sur la zone vide du rail, **Then** aucune fenêtre n'est hidden — comportement no-op.
2. **Given** un utilisateur power-user qui veut le pattern Apple, **When** il met `[fx.rail] empty_click_hide_active = true` dans son TOML, **Then** le comportement existant est restauré.
3. **Given** un utilisateur upgradant, **When** il pull la nouvelle version, **Then** son comportement effectif change si pas de valeur explicite dans son TOML — documenté dans le README.

---

### User Story 7 — Diagnostic bundle pour bug report (Priority: P2)

**En tant qu'**utilisateur (et a fortiori des futurs utilisateurs tiers),
**je veux** une commande qui produit un bundle structuré contenant tout ce qu'un mainteneur a besoin pour diagnostiquer un problème,
**afin de** ne pas avoir à fournir manuellement des extraits de logs, l'état de mes fichiers, mes display infos, etc.

**Why this priority** : aujourd'hui, l'utilisateur (= mainteneur unique) a tout le contexte sous la main. Mais à mesure que d'autres testent le produit, le pipeline "j'ai un bug → je le signale" doit pouvoir produire un artefact reproductible sans aller-retour. La commande `roadie diag` matérialise ça.

**Independent Test** : exécuter `roadie diag`, vérifier que le tarball produit contient au minimum : daemon.log tail, roadies.toml, stages/*.toml, output `daemon status/health/audit`, `windows list`, system-info (macOS version, codesign daemon, launchctl status).

**Acceptance Scenarios** :

1. **Given** un daemon up et un état runtime sain, **When** l'utilisateur tape `roadie diag`, **Then** un fichier `~/Desktop/roadie-diag-YYYYMMDD-HHMMSS.tar.gz` est créé en < 5 s, contenant ≥ 7 fichiers (logs, config, stages, status, health, audit, system-info).
2. **Given** la commande `roadie diag --out /tmp/x.tar.gz`, **When** exécutée, **Then** le bundle est créé au chemin spécifié.
3. **Given** un bundle créé, **When** un mainteneur le décompresse via `tar -xzf`, **Then** il peut reconstituer un diagnostic sans accéder à la machine source.

---

### User Story 6 — Hygiène disque (Priority: P3)

**En tant qu'**utilisateur,
**je veux** que les fichiers `.legacy.*` soient garbage-collectés automatiquement,
**afin de** ne pas accumuler des centaines de fichiers obsolètes dans `~/.config/roadies/stages/`.

**Why this priority** : nice-to-have. Pas bloquant pour le daily-driving mais devient gênant à moyen terme (90+ fichiers actuels, ralentit `ls`, complique le debug).

**Independent Test** : créer 100 fichiers `.legacy.*` avec des mtimes étalés sur 14 jours. Lancer le daemon. Vérifier que les > 7 jours sont supprimés silencieusement, et que les < 7 jours restent.

**Acceptance Scenarios** :

1. **Given** 100 fichiers `.legacy.*` dont 60 ont mtime > 7 jours, **When** le daemon save un stage (déclenche le GC), **Then** les 60 vieux sont supprimés, les 40 récents restent.
2. **Given** un install-dev fresh, **When** `install-dev.sh` tourne, **Then** une étape de cleanup `.legacy.*` > 7 jours est exécutée.

---

### Edge Cases

- **`saved_frame.y = -2117` validée comme légitime** : si l'utilisateur a un display dont la zone AX inclut Y=-2117 (LG au-dessus du Built-in), le seuil de validation doit le respecter. Solution : valider via "appartenance à un display connu via `displayRegistry`", pas via Y absolu.
- **Toutes les fenêtres en frame offscreen au boot** (cas extrême : 100 % corruption) : le daemon log un fatal warn + active un mode "safe restore" qui ignore les saved_frame et laisse le tree calculer fresh.
- **`empty_click_hide_active` config user explicite à `true`** : respecté, pas overridé par le changement de default.
- **`roadie heal` sur daemon down** : retourne erreur claire + code retour 3.
- **Crash mid-`auto-fix` au boot** : fallback graceful (log error, continuer le bootstrap). Mieux vaut un daemon up avec drift que pas de daemon.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001** : Le système DOIT, au load des fichiers stage TOML, valider chaque `saved_frame` via le `displayRegistry` (frame contenue dans au moins un display connu, ou `expectedFrame` mise à `.zero`). Toute frame invalide est mise à `.zero` (déclenche un repositioning par le tree au prochain `applyLayout`).
- **FR-002** : Le système DOIT appeler `purgeOrphanWindows()` puis `rebuildWidToScopeIndex()` automatiquement à la fin de `Daemon.bootstrap()`, après `loadFromDisk` mais avant le premier `applyLayout`.
- **FR-003** : Le système DOIT logger l'état de santé du state au boot via un message JSON-lines `boot_state_health` contenant : `total_wids`, `wids_offscreen_at_restore`, `wids_zombies_purged`, `widToScope_drifts_fixed`.
- **FR-004** : Le système DOIT exposer une commande IPC `daemon.health` retournant un JSON avec `verdict: "healthy" | "degraded" | "corrupted"` + détails (compteurs identiques à FR-003).
- **FR-005** : Le système DOIT exposer une commande CLI `roadie heal` qui orchestre, dans l'ordre : `purgeOrphanWindows` + `rebuildWidToScopeIndex` + `applyLayout` forcé sur tous les displays + `windowDesktopReconciler.runIntegrityCheck(autoFix: true)`. Idempotent.
- **FR-006** : Le système DOIT changer la valeur par défaut de `[fx.rail].empty_click_hide_active` de `true` à `false`. Les utilisateurs existants avec valeur explicite dans leur TOML restent inchangés.
- **FR-007** : Le système DOIT, au moment de `HideStrategyImpl.show()`, fallback sur le centre du primary display visible si `state.expectedFrame == .zero` ET `state.frame` est offscreen (= en dehors de tous les displays connus). Garantit qu'une fenêtre `show()` réapparait toujours quelque part de visible.
- **FR-008** : Le système DOIT investiguer pourquoi `setLeafVisible(wid, true)` retournait apparemment `false` pour les wids problématiques de BUG-001 (tree leaf manquant). Soit corriger l'insertion manquante, soit documenter le cas avec une trace clair `"msg": "setLeafVisible_no_leaf_found", "wid": ...`.
- **FR-009** : Le système DOIT, à chaque `saveStage` (StageManager), supprimer les fichiers `.legacy.*` du même stage path dont mtime > 7 jours. Idempotent et silencieux.
- **FR-010** : Le système DOIT, dans `install-dev.sh`, ajouter une étape de cleanup `.legacy.*` > 7 jours.
- **FR-011** : La commande IPC publique existante reste **strictement** inchangée. `daemon.health` et `daemon.heal` sont des AJOUTS additifs.
- **FR-012** : Le système DOIT mettre à jour le README (EN + FR) avec une section "Troubleshooting" qui documente : `roadie heal`, BUG-001 workaround, où regarder les logs.
- **FR-013** : Le système DOIT inclure 3 tests d'acceptation shell dans `Tests/` :
  - `25-boot-with-corrupted-saved-frame.sh`
  - `25-boot-with-zombie-wids.sh`
  - `25-heal-command.sh`
- **FR-016** : Le système DOIT fournir une commande CLI `roadie diag [--out <path>]` qui crée un tarball gzippé contenant : 200 dernières lignes `daemon.log`, `roadies.toml`, snapshots `stages/*.toml` (sans `.legacy.*`), outputs courants de `daemon status/health/audit/windows list/display list/stage list`, et infos système (sw_vers, uname, codesign daemon, launchctl status). Path par défaut : `~/Desktop/roadie-diag-YYYYMMDD-HHMMSS.tar.gz`.
- **FR-017** : Le système DOIT logger via `Logger.shared` (JSON-lines structuré existant) les events critiques suivants avec contexte exploitable :
  - `boot_state_health` (FR-003)
  - `boot_audit_autofixed` / `boot_audit_clean` (FR-002)
  - `loadFromDisk_validated` (FR-001)
  - `daemon_heal` (FR-005)
  - `legacy_gc_done` (FR-009)
  - `setLeafVisible_no_leaf_found` (FR-008)
  - `hide_strategy_show_fallback_center` (FR-007)
  - `hide_strategy_show_no_element` (FR-007)
- **FR-014** : Aucune nouvelle feature utilisateur n'est introduite.
- **FR-015** : Le delta LOC effectif global doit rester ≤ +200 LOC (cible : +120 LOC).

### Key Entities

- **`saved_frame` validation** : nouvelle logique de validation à `loadFromDisk` qui consulte `displayRegistry`. Méthode `Stage.validateMembers(against: DisplayRegistry)`.
- **`BootStateHealth`** : structure `{ totalWids, offscreenAtRestore, zombiesPurged, driftsFixed, verdict }` dans RoadieCore. Sérialisable JSON.
- **`roadie heal`** : nouvelle sous-commande CLI client + handler IPC `daemon.heal`.

### Out of Scope

- Pas de nouveau renderer rail
- Pas de modification du contrat IPC public existant
- Pas de refactor TCC (recheck-tcc.sh suffit)
- Pas de fix multi-display avancé
- Pas d'optimisation perf
- Pas de migration V2 → V3

### Assumptions

- **Article 0 minimalisme strict** : pas de réécriture de modules. ~120 LOC ajoutées au total.
- **Aucune dépendance externe nouvelle**.
- **Pas de breaking change** sur CLI/IPC public/configs TOML utilisateur.
- L'utilisateur accepte le changement de default `empty_click_hide_active` (motivé par BUG-001).

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001** : Sur 10 rebuilds + redéploiements consécutifs (1 heure de daily dev), zéro fenêtre ne se retrouve coincée offscreen. Mesuré via script `scripts/bench-stability.sh`.
- **SC-002** : Le boot du daemon log systématiquement un message `boot_state_health` avec verdict explicite, observable dans `~/.local/state/roadies/daemon.log` ≤ 2s après le start.
- **SC-003** : `roadie heal` ramène un état corrompu artificiellement (drift + offscreen + zombies) à un état sain en ≤ 3s.
- **SC-004** : Sur une session de 1h de daily-driving (ouverture/fermeture de 30+ fenêtres, 5 stages, 2 displays), `daemon.health` retourne `verdict: healthy` à tout instant.
- **SC-005** : Le nombre de fichiers `.legacy.*` ne dépasse jamais 14 sur une période d'observation de 7 jours.
- **SC-006** : Le delta LOC effectif global vs HEAD pré-SPEC-025 est ≤ +200 LOC (cible : +120 LOC).
- **SC-007** : Tous les tests d'acceptation `Tests/25-*.sh` passent (3 tests).
- **SC-008** : 0 régression sur les tests existants.
- **SC-009** : Après 7 jours de daily-driving sur la branche main post-merge, aucun incident de fenêtre coincée offscreen, ni recours à `roadie heal` plus de 1 fois.

## Notes pour la phase de planification

- Implémentation en 4 vagues (cf. `tasks.md`) : Quick wins → Boot robustness → BUG-001 fix → `heal` + docs.
- Aucune sous-vague ne doit dépasser 0,5 jour de travail.
- Le fix réel BUG-001 (FR-007 + FR-008) est le seul point techniquement risqué — investigation profonde du tree leaf vs memberWindows. Time-box strict : 3h. Au-delà → fallback option A (revert `empty-click hide active`) et déposer FR-007/FR-008 dans une SPEC future.
- **Critère d'arrêt du sprint** : tous les tests E2E passent + 24h de daily-driving sans incident → merge `main`.
