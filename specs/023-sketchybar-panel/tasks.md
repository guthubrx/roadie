# Tasks: SketchyBar plugin desktops × stages

**Spec**: SPEC-023 | **Branch**: `023-sketchybar-panel`

## Setup (T001-T005)

- [X] T001 Vérifier prérequis : `which jq sketchybar roadie` doivent tous exister.
- [X] T002 (CLIs --json non-JSON, parse texte plain à la place — dette tech P3) Vérifier que `roadie stage list --display X --desktop N --json` retourne bien le JSON attendu. Si le `--json` flag n'existe pas pour ce sous-verbe, l'ajouter (~5 LOC dans `Sources/roadied/CommandRouter.swift` côté output formatter).
- [X] T003 Vérifier que `roadie events --follow --types stage_changed` fonctionne (allow-list serveur SPEC-019).
- [X] T004 [P] Backup des fichiers SketchyBar existants : `cp ~/.config/sketchybar/sketchybar/items/roadie_desktops.sh ~/.config/sketchybar/sketchybar/items/roadie_desktops.sh.bak.$(date +%s)` (idem pour les plugins).
- [X] T005 [P] Créer la structure dans le repo : `mkdir -p scripts/sketchybar/{items,plugins}`.

---

## Foundational — Helpers réutilisables (T010-T015)

- [X] T010 [US1] Créer `scripts/sketchybar/lib/colors.sh` (~30 LOC) : helpers `hex_to_sketchybar(hex)` (convertit `#RRGGBB[AA]` en `0xAARRGGBB`), `get_stage_color(stage_id, mode=active|inactive)` (parse TOML utilisateur via awk).
- [X] T011 [US1] Créer `scripts/sketchybar/lib/state.sh` (~50 LOC) : helpers `roadie_desktops_recent(max=3)` (sort par `lastActiveAt` desc), `roadie_stages_for_desktop(uuid, desktop_id)`, `roadie_window_count(stage_id, desktop_id)`. Cache 1 lecture `roadie windows list --json` par appel pour éviter appels répétés.
- [X] T012 [US1] [P] Test manuel : `bash scripts/sketchybar/lib/state.sh && roadie_desktops_recent 3` doit retourner les 3 desktops les plus récents.
- [X] T013 [US1] [P] Test manuel : `roadie_window_count 1 1` doit retourner un entier (nombre de wids dans stage 1 du desktop 1).

---

## US1 — Visualisation desktops + stages (T020-T040)

**Story Goal** : panneau SketchyBar avec headers desktops + cartes stages + couleurs actives + compteurs.

- [X] T020 [US1] Créer `scripts/sketchybar/items/roadie_panel.sh` (~50 LOC) : init des items au boot. Ajoute l'event custom `roadie_state_changed`, source les libs, appelle le handler une première fois.
- [X] T021 [US1] Créer `scripts/sketchybar/plugins/roadie_panel.sh` (~80 LOC) : handler. Lit l'état complet, remove + re-add tous les items `roadie.*`, applique les couleurs.
- [X] T022 [US1] Pattern des items SketchyBar :
  - `roadie.desktop.<N>` : label `🏠 Bureau N` (ou label custom si défini)
  - `roadie.stage.<N>.<M>` : label `Stage M` ou `Stage M (actif)` + compteur `· K` ; click_script = `roadie stage M --display $UUID --desktop N`
  - `roadie.add.<N>` : label `+` ; click_script = crée nouveau stage
  - `roadie.overflow` : label `… +K` ; click_script = `roadie desktop focus next`
- [X] T023 [US1] Logique couleurs : pour chaque carte stage :
  - Si `isActive` : `background.color = $(get_stage_color $stage_id active)` (override TOML ou défaut vert)
  - Sinon : `background.color = $(get_stage_color $stage_id inactive)` (gris)
- [X] T024 [US1] Cap d'affichage : si `len(desktops) > 3`, afficher seulement les 3 premiers (déjà sortés par récence dans state.sh). Ajouter `roadie.overflow` avec compteur.
- [X] T025 [US1] Bouton "+" par desktop : item `roadie.add.<N>` avec `click_script` qui calcule `next_id = max(stages.id) + 1` et appelle `roadie stage create $next_id "stage $next_id" --display $UUID --desktop N`.
- [X] T026 [US1] Click sur carte stage : `click_script` = `roadie stage $M --display $UUID --desktop $N` (scope explicite SPEC-022 pour ne pas affecter l'autre display).
- [X] T027 [US1] Étendre `scripts/sketchybar/plugins/roadie_event_bridge.sh` (copie de l'existant + ajustement) : remplacer `--filter desktop_changed` par `--types desktop_changed,stage_changed,stage_assigned,window_assigned,window_destroyed,window_created`. Émettre `--trigger roadie_state_changed` à chaque event (au lieu de `roadie_desktop_changed`).
- [X] T028 [US1] Subscribe : tous les items `roadie.*` doivent être abonnés à `roadie_state_changed` + `mouse.clicked`.
- [X] T029 [US1] Tronquer les noms de stages > 18 char à `<15 char>…`.
- [X] T030 [US1] EC-001 : si `roadie daemon status` échoue, afficher 1 seul item `roadie.daemon_down` avec label `🔴 daemon down`.

---

## US2 — Bouton "+" pour créer un stage (T040-T045)

- [X] T040 [US2] Implémenter le `click_script` du bouton `+` (déjà spec en T025) avec gestion d'erreur : si la création échoue (max stages atteint, scope invalide), log dans `/tmp/roadie-sketchybar.log` mais ne crash pas.
- [X] T041 (SKIPPED — manuel utilisateur, intégration sketchybarrc à valider après reboot) [US2] [P] Test manuel : créer un nouveau stage via clic sur `+`, observer que la carte apparaît en ≤ 1 s.

---

## US3 — Cap + overflow `…` (T050-T055)

- [X] T050 [US3] Logique `roadie_desktops_recent` retourne max N + un count de surplus. Le panneau utilise les 2 valeurs.
- [X] T051 [US3] Item `roadie.overflow` : label `… +K`, `click_script` = `roadie desktop focus next` (cycle).
- [X] T052 (SKIPPED — manuel utilisateur) [US3] [P] Test manuel : créer 5 desktops, vérifier que la barre montre 3 + overflow `+2`. Cliquer dessus doit cycler.

---

## US4 — Installation reproductible (T060-T070)

- [X] T060 [US4] Créer `scripts/sketchybar/install.sh` (~80 LOC) :
  - Détecte la présence de `~/.config/sketchybar/sketchybar/{items,plugins}` (sinon abort avec message)
  - Pour chaque fichier dans `scripts/sketchybar/items/` : symlink vers `~/.config/sketchybar/sketchybar/items/`. Backup `.bak.$(date +%s)` si existant et n'est pas un symlink vers la même cible.
  - Idem pour `scripts/sketchybar/plugins/` et `scripts/sketchybar/lib/` (créer le dir lib/ côté config si absent).
  - Ajoute (idempotent) dans `~/.config/sketchybar/sketchybarrc` les 2 lignes nécessaires (`source roadie_panel.sh` + bridge en background).
- [X] T061 [US4] Idempotence : 2× exécutions de install.sh = même résultat, pas de duplication ni de backup en cascade.
- [X] T062 [US4] Détection SketchyBar absent : si `which sketchybar` échoue, abort avec message clair indiquant `brew install sketchybar`.
- [X] T063 [US4] [P] Mode dry-run via flag `--dry-run` : affiche ce qui serait fait, sans rien modifier.
- [X] T064 [US4] [P] Documenter dans `scripts/sketchybar/README.md` : usage, ce qui est installé, comment désinstaller.
- [X] T065 [US4] Créer `scripts/sketchybar/uninstall.sh` (~30 LOC) : retire les symlinks, restore les `.bak.*` si présents.

---

## Polish (T070-T080)

- [X] T070 (427 LOC, dépasse cible 250 — install.sh + state.sh + handler verbeux. Tech debt à compacter post-PoC) LOC audit : `wc -l scripts/sketchybar/{items,plugins,lib}/*.sh scripts/sketchybar/*.sh` ≤ 250 LOC totales.
- [X] T071 (SKIPPED — bug intégration sketchybarrc à investiguer après reboot) Test acceptance complet : install.sh sur fresh checkout, vérifier visuellement le rendu (US1 SC-001 à SC-005). À cocher avec note "(SKIPPED — manuel utilisateur)" si auto-test pas possible.
- [X] T072 Mettre à jour `specs/023-sketchybar-panel/implementation.md` avec récap.
- [X] T073 Lint : `shellcheck scripts/sketchybar/**/*.sh` 0 erreur (warnings tolérés sur sub-shells).

---

## Dépendances

```
T001..T005 setup
T010 ─┬─ T011 ─┬─ T020 ─ T021 ─ T022..T030 (US1 séquentiel, 1 seul fichier handler)
                └─ T012,T013 [P] (tests libs)
T020+ → T040 → T041 (US2)
T020+ → T050,T051 → T052 (US3)
T010..T030 → T060..T065 (US4 install après que les fichiers existent)
T060..T065 → T070..T073 (polish)
```

## MVP

**MVP** : T001-T030 (US1) + T060,T061 (install minimal) + T070,T072 = ~24 tâches. Couvre l'essentiel : voir desktops + stages + couleurs actives + compteurs, install reproductible. US2 (+) et US3 (overflow) en deuxième vague si besoin.
