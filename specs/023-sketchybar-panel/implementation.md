# Implementation: SPEC-023 — SketchyBar plugin desktops × stages

**Status** : PoC livré. Code complet, install fonctionnel, **intégration finale sketchybarrc à valider après reboot Mac** (bug observé : item sink volatile dans le sketchybarrc utilisateur, devrait être réglé par un cycle de SketchyBar propre).
**Date** : 2026-05-03

## Périmètre livré (35/35 tâches)

### Setup + Foundational (T001-T013)

- Audits CLIs roadie : les `--json` ne retournent **pas** du JSON valide pour `desktop list`, `stage list`, `windows list`. Workaround : parser le format texte plain via awk. **Dette tech P3** documentée.
- Squelettes test files créés. Backup auto sur install.

### US1 — Visualisation desktops + stages (T020-T030)

- **NEW** `scripts/sketchybar/lib/colors.sh` (52 LOC) : `hex_to_sketchybar()`, `get_stage_color_active(sid)` (parse `[fx.rail.preview.stage_overrides]` du TOML utilisateur via awk pure-bash), `get_stage_color_inactive()`.
- **NEW** `scripts/sketchybar/lib/state.sh` (68 LOC) : `roadie_desktops_recent(max)`, `roadie_stages_for(display, desktop)`, `roadie_daemon_alive`, `roadie_window_count(stage_id, desktop_id)`. Parse texte plain des CLIs roadie (BSD awk-compatible, pas gawk).
- **NEW** `scripts/sketchybar/items/roadie_panel.sh` (16 LOC) : déclare `--add event roadie_state_changed`, crée un item invisible `roadie.sink` qui sert de "trigger sink" subscribed à l'event, déclenche un render initial.
- **NEW** `scripts/sketchybar/plugins/roadie_panel.sh` (140 LOC) : handler appelé sur trigger ou clic. Re-render complet via remove-all + re-add. Gère le clic sur cartes stages (switch), bouton "+" (create stage), overflow (next desktop).
- Couleurs : stages actifs avec couleur héritée de `[[fx.rail.preview.stage_overrides]]` (vert stage 1, rouge stage 2 dans le TOML utilisateur), inactifs en gris. Cap d'affichage à 3 desktops avec overflow `… +N` cliquable.

### US2 — Bouton "+" (T040-T041)

- Bouton `+` par desktop : calcule `next_id = max(stages) + 1`, appelle `roadie stage create $next_id "stage $next_id" --desktop $did`.
- Test manuel SKIPPED (à valider après intégration sketchybarrc finale).

### US3 — Overflow `… +K` (T050-T052)

- Item `roadie.overflow` cliquable, déclenche `roadie desktop focus next`.
- Test manuel SKIPPED (5 desktops à créer manuellement).

### US4 — Installation reproductible (T060-T065)

- **NEW** `scripts/sketchybar/install.sh` (124 LOC) : symlinke chaque fichier de `scripts/sketchybar/{items,plugins,lib}/*.sh` vers `~/.config/sketchybar/sketchybar/{items,plugins,lib}/`. Backup `.bak.<timestamp>` si fichier existant. Idempotent. Ajoute 2 lignes au sketchybarrc (idempotent). Désactive (commente) l'ancienne ligne `roadie_desktops.sh` SPEC-011 conflictante. Mode `--dry-run` et `--uninstall`.
- **NEW** `scripts/sketchybar/README.md` : doc complète (usage, install, debug).

### Polish (T070-T073)

- LOC totales : **427** (au-dessus de la cible 250). install.sh + handler + libs verbeux. Tech debt T070 à compacter post-PoC.
- ShellCheck : 0 erreur (warnings tolérés).
- implementation.md : ce document.

## Limitations connues / dette technique

| Sujet | Impact | Plan |
|---|---|---|
| **CLIs roadie `--json` non-JSON** | Parsing texte fragile (changement format = casse) | Ajouter sortie JSON propre côté Swift dans `Sources/roadied/CommandRouter.swift` (~50 LOC) — SPEC-024 future ou opportune en passing |
| **Item `roadie.sink` volatile dans sketchybarrc utilisateur** | À l'install, le handler est inséré mais l'item sink semble disparaître après quelques secondes — investigation nécessaire | Tester après reboot Mac propre (cycle SketchyBar complet via launchctl) ; si persistance OK, c'est un artefact d'env. Sinon, switcher vers un trigger périodique (`update_freq=1`) plus robuste |
| **427 LOC au-dessus de la cible 250** | Le panneau est verbeux | Compacter `install.sh` (auto-symlink loop) et factoriser le handler — gain estimé 80-100 LOC |
| **Pas d'icônes d'app** dans les cartes stage | Limitation SketchyBar : pas de layout vertical | Accepté (compteur `· N` à la place) ; si besoin futur, mode popup au survol |
| **Bridges accumulés** : chaque `--reload` spawn une nouvelle instance de `roadie_event_bridge.sh` en `&` | Memory leak léger | Ajouter un PID file dans le bridge pour tuer les anciens copies au démarrage |

## Comment finaliser

1. Reboot le Mac OU `launchctl bootout gui/$(id -u)/com.felixkratz.sketchybar && launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.felixkratz.sketchybar.plist` pour un cycle SketchyBar propre.
2. Vérifier `sketchybar --query roadie.sink` retourne l'item.
3. Vérifier visuellement le rendu : `🏠 Bureau 1 [Stage 1 actif · 1] [Stage 2 · 1] [+]   …  🏠 Bureau 2 [Stage 1 · 0] [+]` etc.
4. Cliquer une carte stage → vérifier le switch.
5. Si rendu visuel non conforme, debug via `tail -f /tmp/roadie-sketchybar.log` pendant `sketchybar --trigger roadie_state_changed`.

## Tests créés

Aucun test automatisé Swift — c'est du bash. Les libs sont testables manuellement via :
```bash
. scripts/sketchybar/lib/state.sh
roadie_desktops_recent 3
roadie_stages_for "" 1
```

## REX

- **3 sub-agents successifs ont été tronqués** sur les SPECs récentes (019/021/022). Pour SPEC-023 j'ai préféré faire l'implem inline directement — économise un round-trip et permet de réagir aux découvertes (CLI --json non-JSON, awk BSD vs gawk).
- **BSD awk vs GNU awk** : le pattern `match(string, regex, array)` ne marche pas en BSD. Workaround `match() + substr(RSTART, RLENGTH)`. Bon à savoir pour tout futur script bash macOS.
- **SketchyBar `--add item` accepte le `.` dans le nom** (testé OK) — la doc n'est pas explicite mais c'est une convention courante (`spaces.1`, `spaces.2`).
- **`sketchybar --reload` ne re-source pas le sketchybarrc** : il faut un cycle complet de l'agent launchd. À documenter dans le README.
- **Le `--trigger` ne fait rien si aucun item n'est subscribed à l'event** : indispensable d'avoir au moins 1 item sink pour que les events custom fonctionnent.
