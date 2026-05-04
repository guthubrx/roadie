# Quickstart — SPEC-024 Migration mono-binaire (V1 → V2)

**Phase 1** | Date : 2026-05-04 | Branche : `024-monobinary-merge`

Ce document décrit la procédure de migration utilisateur (V1 → V2) et la checklist de tests post-migration.

---

## 1. Migration (utilisateur)

### Pré-requis

- roadie V1 actuellement installé et fonctionnel.
- `swift`, `codesign`, `launchctl`, `terminal-notifier` disponibles.
- Certificat self-signed `roadied-cert` dans le keychain.

### Procédure

```bash
# 1. Récupérer le code V2
cd ~/Nextcloud/10.Scripts/39.roadies
git fetch && git checkout 024-monobinary-merge

# 2. Lancer le script d'install (modifié pour gérer la migration)
./scripts/install-dev.sh
```

Ce que fait le script :

```text
==> stop running instances
   - bootout LaunchAgent com.roadie.roadie
   - pkill roadie-rail (toujours présent V1)
   - pkill roadie events (clients connectés au socket)

==> migration V1 → V2 (NOUVEAU)
   - bootout LaunchAgent com.roadie.roadie-rail (s'il existait)
   - rm -rf ~/Applications/roadie-rail.app
   - rm ~/.roadies/rail.pid (lockfile orphelin)
   - tccutil reset ScreenCapture com.roadie.roadie-rail (cleanup TCC orphelin)

==> install binaries
   - cp .build/debug/roadied → ~/Applications/roadied.app/Contents/MacOS/roadied
   - cp .build/debug/roadie  → ~/.local/bin/roadie
   - codesign -fs roadied-cert sur les deux

==> bootstrap launchd
   - launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.roadie.roadie.plist

==> done
```

### Au premier lancement

Le nouveau binaire `roadied` aura besoin de **deux grants TCC** que l'utilisateur doit accorder :

1. **Accessibility** (probablement déjà accordée à `roadied.app` V1, peut être préservée selon designated requirement).
2. **Screen Recording** (la grant V1 sur `roadied.app` peut être préservée ; la grant V1 sur `roadie-rail.app` devient orpheline et le script l'a nettoyée).

Si un toggle est demandé : Réglages Système → Confidentialité → Accessibilité ET Enregistrement d'écran → cocher `roadied.app`.

### Après migration

Vérifier que tout fonctionne :

```bash
roadie daemon status --json | jq .
# Doit retourner notamment : "arch_version": 2, "ok": true

roadie stage list
# Doit lister les stages comme avant

# Hover le bord gauche de l'écran → le rail doit apparaître

# Valider les 13 raccourcis BTT (changement de stage, focus next, etc.)
```

---

## 2. Tests de migration (checklist exhaustive)

### A. Compatibilité ascendante CLI (FR-008, SC-004)

Exécuter chaque commande, comparer la sortie textuelle/JSON à un snapshot V1 :

- [ ] `roadie stage list` (texte + `--json`)
- [ ] `roadie stage switch 2`
- [ ] `roadie stage assign 1` (sur fenêtre frontmost)
- [ ] `roadie stage create "Test"` puis `roadie stage delete <id>`
- [ ] `roadie stage rename 1 "Main"`
- [ ] `roadie desktop list`
- [ ] `roadie desktop current`
- [ ] `roadie desktop focus 2`
- [ ] `roadie desktop label 2 "comm"`
- [ ] `roadie display list`
- [ ] `roadie display current`
- [ ] `roadie display focus next`
- [ ] `roadie window display 2` (si multi-display)
- [ ] `roadie events --follow` (déclencher un changement → event JSON arrive)
- [ ] `roadie daemon status --json` (vérifier `arch_version: 2`)
- [ ] `roadie daemon reload`
- [ ] `roadie fx status`

### B. Raccourcis BTT (FR-008, SC-004)

Lister les 13 raccourcis BTT existants (cf. dossier `bettertouchtool/` ou config utilisateur) et les exécuter un par un. Comportement identique à V1.

- [ ] ⌥1 / ⌥2 / ... → switch stage
- [ ] ⌥+ / ⌥- → focus prev/next stage
- [ ] ⌥W → close current window
- [ ] (lister tous les autres)

### C. Plugin SketchyBar (FR-008, SC-004)

- [ ] `sketchybar` lancé avec config roadie : panneau apparaît sur menu bar
- [ ] Switch de stage → panneau se met à jour en < 200 ms
- [ ] Switch de desktop → panneau se met à jour
- [ ] Click sur stage → switch via roadie

### D. Rail UI (FR-018, US3)

- [ ] Rail apparaît sur edge gauche au hover (si `persistence_ms` > 0 ou -1)
- [ ] Rail apparaît immédiatement au boot (si `persistence_ms = 0`, always-visible)
- [ ] Thumbnails affichées correctement (pas de fallback icônes si Screen Recording OK)
- [ ] Drag-drop d'une fenêtre vers un stage : assigne correctement
- [ ] Click-drop sur un stage : switch
- [ ] Menu contextuel (right-click) : rename, delete, add focused
- [ ] Halo de stage active : visible et coloré correctement
- [ ] Renderers : tester parallax-45, stacked-previews, mosaic, hero-preview, icons-only via toggle config
- [ ] Multi-display : 1 panel par écran, indépendants

### E. Cohérence rail/tiling (US3, SC-003)

Test stress :

- [ ] Ouvrir 20 fenêtres rapidement → rail montre toutes (avec délai capture thumbnails)
- [ ] Drag-drop fenêtre entre 5 stages en < 2 s → rail toujours cohérent
- [ ] Switch desktop pendant drag : pas de fenêtre fantôme
- [ ] Crash daemon simulé (`pkill -9 roadied`) → respawn launchd ≤ 30 s → rail reapparaît immédiatement avec état corrigé

### F. Performance (SC-006, SC-007)

Mesures (script bench à créer) :

- [ ] Latence p95 hover edge → rail visible : ≤ 100 ms (sur 100 itérations)
- [ ] Boot process → rail visible (mode always-visible) : ≤ 3 s
- [ ] Mémoire peak avec 10 fenêtres + thumbnails actives : ≤ baseline V1 + 5 %

### G. Permissions TCC (US1, SC-001, SC-008)

- [ ] Réglages Système → Accessibilité : 1 entrée "roadied" (pas 2)
- [ ] Réglages Système → Enregistrement d'écran : 1 entrée "roadied" (pas 2, et pas "roadie-rail")
- [ ] Aucune entrée "roadie-rail" résiduelle

### H. Cycle dev (US2, SC-002)

- [ ] `swift build` : 1 binaire `roadied` produit (+ `roadie` CLI), pas de `roadie-rail`
- [ ] `./scripts/install-dev.sh` : 1 codesign sur `roadied`, 1 sur `roadie`, pas de troisième
- [ ] Temps total `swift build && install-dev.sh` : ≤ 75 % du temps V1 sur 5 itérations

### I. LOC (FR-013, SC-005)

```bash
find Sources -name '*.swift' -exec grep -vE '^\s*$|^\s*//' {} + | wc -l
```

- [ ] Delta vs HEAD pré-migration : ≤ −150 LOC (cible) ou ≤ +50 LOC (plafond strict)

### J. Désinstallation propre (FR-017)

- [ ] `./scripts/uninstall.sh` retire :
  - [ ] `~/Applications/roadied.app`
  - [ ] `~/Applications/roadie-rail.app` (si héritage V1)
  - [ ] `~/.local/bin/roadied`, `roadie`
  - [ ] LaunchAgents `com.roadie.roadie` et éventuel `com.roadie.roadie-rail`
- [ ] Process roadie tués proprement (pas de zombies)

---

## 3. Rollback (en cas de problème)

```bash
# Revert au commit pré-migration (à identifier dans git log)
git checkout <pre-migration-sha>

# Rebuild + install
./scripts/install-dev.sh
```

Le rollback est sans risque pour les données utilisateur (config TOML, stages persistés, etc.) car aucun schéma n'a été modifié par cette migration.

---

## 4. Critères de succès "go-live"

La migration peut être considérée réussie si **tous** les éléments suivants sont vrais :

- [✓] Toutes les sections A à I de la checklist passent (J non bloquant pour le go-live initial).
- [✓] Pas de régression sur les tests d'acceptation manuelle SPEC-002, 014, 018, 022.
- [✓] Audit `/audit` sur SPEC-024 retourne grade ≥ A-.
- [✓] Aucun crash daemon dans les 24 h suivant le déploiement (sur la machine dev personnelle de l'auteur, qui est aussi l'utilisateur final).

Si ces critères ne sont pas tous remplis, **rollback** vers la dernière version V1 stable + ouverture d'un ticket dédié pour traiter la régression avant nouveau déploiement.
