# ADR-006 — Gap analysis fonctionnel vs yabai

🇫🇷 **Français** · 🇬🇧 [English](ADR-006-yabai-feature-gap-analysis.md)

**Date** : 2026-05-02
**Status** : Working draft (interne, gitignored)
**Auteur** : analyse comparative à partir de l'inventaire `CommandRouter.swift` + CLI `Sources/roadie/main.swift` au 2026-05-02 vs documentation yabai (commands reference, configuration, signals, rules) à la même date.
**Portée** : aide à la priorisation des prochaines specs. **Non versionné** (gitignored) — document de travail évolutif, pas un engagement public.

## Contexte

Roadie revendique explicitement (cf. README §"Why this project") une dette intellectuelle totale envers yabai et une intention minimaliste — pas de course à la parité. Cependant, l'objectif "make this my daily driver" implique de combler les gaps qui frottent au quotidien.

Cet ADR inventorie froidement, par catégorie, les fonctionnalités yabai non couvertes (ou partiellement) par roadie, et propose une priorisation. Il ne décide rien — il sert de base à `/speckit.specify` pour les SPEC à venir.

## Inventaire de l'existant roadie (au 2026-05-02)

Commandes daemon (`CommandRouter.swift`) :

```
windows.list, daemon.{status,reload}
focus, move, warp, resize, balance, rebuild
window.{close, toggle.floating, toggle.fullscreen, toggle.native-fullscreen,
        display, desktop, stick, pin, thumbnail}
tiler.{list, set}, tree.dump, tiling.reserve
stage.{list, create, delete, assign, switch}, rail.{toggle, status}
desktop.{list, current, focus, back, label}
display.{list, current, focus}
fx.{status, reload}
```

Specs en cours non implémentées :
- SPEC-014 stage-rail (UI rail latéral)
- SPEC-015 mouse-modifier (Ctrl+drag move/resize → équivalent yabai `mouse_modifier`/`mouse_action1`/`mouse_action2`)

## Gap analysis structuré

### A. Gaps majeurs (impact daily driver élevé)

| # | Fonctionnalité yabai | État roadie | Effort estimé | Priorité |
|---|---|---|---|---|
| A1 | **Système de règles** (`yabai -m rule --add app="X" manage=off opacity=0.8 sticky=on space=N grid=...`) | Seul `tiling.reserve` (manuel). Pas d'API déclarative match-on-app/title. | L (4-6 sessions) | **P1** |
| A2 | **Signals/handlers** (`yabai -m signal --add event=window_created action="..."`) | EventBus interne présent, **aucune exposition utilisateur**. Pas de mapping event → script shell. | M (2-3 sessions) | **P1** |
| A3 | **Mode stack local** (empilement dans un nœud) : `--toggle split`, `--insert stack`, `--focus stack.next/prev`, `layout=stack` | Absent. Roadie a BSP + master-stack global uniquement. | L (4-6 sessions, touche LayoutEngine) | **P2** |
| A4 | **Insertion directionnelle** (`--insert north|south|east|west|stack`) — pré-décide où la prochaine fenêtre va se splitter | Absent. | S (1-2 sessions) | **P2** |
| A5 | **`--swap`** (échange 2 fenêtres sans toucher au tree) | Absent (`move`/`warp` modifient l'arbre). | S (1 session) | **P1** |
| A6 | **`focus_follows_mouse` / `mouse_follows_focus`** | Absent. SPEC-015 traite `mouse_modifier` mais pas ces deux flags. | S (1-2 sessions) | **P1** |

### B. Gaps moyens (confort utilisateur)

| # | Fonctionnalité yabai | État roadie | Effort | Priorité |
|---|---|---|---|---|
| B1 | **Mission Control / Show Desktop** : `--space --toggle mission-control`, `--toggle show-desktop`, `--toggle expose` | Absent. | S | P3 |
| B2 | **Padding/gaps dynamiques** : `--space --padding abs:t:b:l:r`, `--space --gap abs:N`, `--toggle padding/gap` | Statique uniquement (config TOML `gaps_outer`/`gaps_inner`). | S | P2 |
| B3 | **Transformations de space** : `--rotate 90/180/270`, `--mirror x-axis|y-axis`, `--balance` per-space | `balance` global uniquement. Rotate/mirror absents. | M | P3 |
| B4 | **Spaces dynamiques** : `--space --create / --destroy / --move / --display N` | Nombre fixe en config (`count=10`). | M (changement modèle desktop) | P3 |
| B5 | **Déplacements/redimensionnements absolus** : `--window --move abs:x:y`, `--resize abs:w:h`, `--grid R:C:r:c:w:h`, `--ratio abs:N` | Seulement `resize` directionnel par delta. Pas d'absolu, pas de grille. | M | P3 |
| B6 | **Layers et z-order** : `--toggle topmost`, `--layer above|below|normal`, `--raise`, `--lower`, `--sub-layer` | `pin` ≠ `topmost` yabai. Layers absents. | M (touche WindowActivator) | P3 |
| B7 | **Minimize/deminimize** | Absent (on cache via offscreen/stage, jamais via AXMinimized). | S | P3 |

### C. Petits gaps / quality of life

| # | Fonctionnalité yabai | État roadie | Effort |
|---|---|---|---|
| C1 | `--toggle pip` (Picture-in-Picture) | Absent | S |
| C2 | `--toggle zoom-parent` (zoom local sur sous-arbre, distinct du fullscreen) | Absent | S |
| C3 | `--query` JSON avec sélecteurs riches (`--windows --window`, `--space --space N`, filtres) | `windows.list` flat, pas de sélecteur. | M |
| C4 | `--toggle border` / `--toggle shadow` per-window | Global uniquement. | S |
| C5 | Config globales : `window_placement first_child|second_child`, `auto_balance`, `window_zoom_persist`, `split_ratio`, `split_type` defaults | Partiellement (split_ratio implicite). | S |

### D. Gaps connus mais bloqués plateforme (NE PAS spec)

| # | Fonctionnalité | État | Raison du blocage |
|---|---|---|---|
| D1 | Animations Bézier (durée, courbe par event) | Module SPEC-007 livré, runtime KO | ADR-005 (osax Tahoe) |
| D2 | Opacity active/normal global | Module SPEC-006 livré, runtime KO | ADR-005 |
| D3 | Shadowless | Module SPEC-005 livré, runtime KO | ADR-005 |
| D4 | Blur derrière fenêtre transparente | Module SPEC-009 livré, runtime KO | ADR-005 |
| D5 | Inter-app click-to-raise 100% fiable | Limitation acceptée (cf. README) | SIP off + osax requis (refus de principe) |

→ Ces points sont **hors scope tant que la voie osax reste fermée**. Toute relance dépendrait soit d'un retournement Apple sur les scripting additions (improbable), soit d'un pivot architectural (CGS via process injection AMFI-bypass — refus de principe constitutionnel).

## Décision (orientation, pas engagement)

**Choix utilisateur du 2026-05-02** : la **catégorie A complète** (A1→A6) sera traitée dans une **SPEC-016 unique** « yabai-parity tier-1 ». Justification utilisateur : grouper les 6 gaps majeurs dans une seule unité de travail pour avoir un palier "daily driver" cohérent plutôt qu'une succession de petites specs.

**Découpage attendu en user stories au sein de SPEC-016** :

- **US1 (P1, MVP)** — A5 `swap` + A6 `focus_follows_mouse`/`mouse_follows_focus` (petit scope, débloque tout de suite)
- **US2 (P1)** — A1 système de règles déclaratif (`[[rules]]` dans `roadies.toml`, match app/title → `manage`/`sticky`/`space`/`display`/`float`/`grid`)
- **US3 (P1)** — A2 signals utilisateur (mapping event EventBus → commande shell via `[[signals]]` TOML)
- **US4 (P2)** — A4 insertion directionnelle (`--insert north|south|east|west|stack`)
- **US5 (P2)** — A3 stack mode local (touche LayoutEngine — possible scope-out vers SPEC-017 si l'effort dépasse l'enveloppe)

**Specs ultérieures (hors A)** :

1. **SPEC-017** : B2 — padding/gaps dynamiques par space (si pas absorbé par A).
2. **SPEC-018** : B5 — déplacements/redimensionnements absolus + grille NxM.
3. **SPEC-019** : B6 — layers et z-order (topmost, raise/lower, sub-layer).
4. Plus tard (P3) : B1, B3, B4, B7, C1-C5 selon usage réel.

**Garde-fou scope** : si à l'analyse Phase 2 (plan), la catégorie A complète dépasse 8 sessions équivalent-effort, scope-out US5 (A3 stack mode) vers SPEC-017 dédiée. Justification : A3 est seul à toucher la structure de l'arbre BSP, c'est un risque de régression à isoler.

## Conséquences

**Positives** :
- Document de référence pour `/speckit.specify` — chaque future SPEC peut citer son numéro de gap.
- Évite le "feature creep ad hoc" en présentant le panorama complet.
- Force à constater honnêtement ce qui est bloqué plateforme (D) vs ce qui est juste pas codé (A/B/C).

**Négatives** :
- Risque de devenir une "todo list" qui pousse à courir après yabai → **contrarié** par le caractère gitignored et le flag explicite "non engagement public".
- Risque d'obsolescence rapide si yabai évolue ou si Apple débloque osax → mettre à jour à chaque revue trimestrielle.

**Neutralité préservée** :
- Le README continue de dire "pas de prétention de matcher yabai".
- Cet ADR n'est **pas** un roadmap public — il est gitignored précisément pour ça.

## Révision

À reprendre :
- Après chaque session yabai upstream majeure (regarder leurs issues récentes).
- À chaque release macOS majeure (impact osax, AX, CGS).
- Trimestriellement minimum.

## Liens

- README §"What roadie does today"
- ADR-001 (AX-only, no SkyLight write)
- ADR-005 (osax bloqué Tahoe 26)
- yabai commands reference : `man yabai` / `https://github.com/koekeishiya/yabai/wiki`
- AeroSpace commands : `https://nikitabobko.github.io/AeroSpace/commands`
