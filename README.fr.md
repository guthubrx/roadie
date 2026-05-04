<div align="center">
  <img src="docs/assets/roadie-logo.svg" alt="logo roadie" width="128" height="128">
</div>

<div align="center">

# 🚧 EN CONSTRUCTION · UNDER CONSTRUCTION 🚧

**Ce projet est en cours de construction. Attendez-vous à des changements cassants, des aspérités et des fonctionnalités incomplètes.**

**This project is a work in progress. Expect breaking changes, rough edges, and incomplete features.**

</div>

---

# roadie

🇬🇧 [English](README.md) · 🇫🇷 **Français**

> **Work in progress — projet en évolution active.** Mon objectif est d'en faire mon daily driver. Toutes les remarques sont les bienvenues — voir [Status](#status).

Un petit window manager tiling pour macOS, écrit en Swift, que je polis pour en faire mon poste de travail au quotidien.

## Pourquoi ce projet

À l'origine je n'avais pas l'intention d'écrire un window manager. Cela fait des années que [yabai](https://github.com/koekeishiya/yabai) est le support de mon poste de travail — un projet remarquable, taillé au cordeau, dont la stabilité et l'ergonomie ont marqué tous les utilisateurs de tiling sur macOS. Je continue d'y voir la référence, et la dette intellectuelle de roadie envers yabai est totale.

Le déclencheur a été simple et personnel : je n'ai jamais réussi à faire cohabiter yabai avec **Stage Manager**. Or Stage Manager fait partie intégrante de ma manière de travailler — je veux des groupes de fenêtres nommés, masquables, restaurables, en plus du tiling automatique des fenêtres visibles. Plusieurs tentatives, scripts, contournements, rien n'a tenu durablement chez moi.

Plutôt que de continuer à bricoler, j'ai fini par poser le problème à plat et écrire un petit gestionnaire de fenêtres qui réponde précisément à mon besoin :

- Tiling BSP / master-stack pour les fenêtres visibles, comme yabai.
- Un *pseudo* Stage Manager — des "stages" qui sont des groupes de fenêtres masquables au sein d'un même desktop, avec restauration parfaite du layout.
- Une awareness multi-desktop, sans dépendre des APIs SkyLight d'écriture.

**roadie n'a aucune prétention à équivaloir yabai** — la profondeur fonctionnelle, la robustesse, le polissage de yabai sont d'un autre niveau. roadie est volontairement minimaliste, écrit pour mon usage, et je le partage publiquement parce qu'il pourra peut-être servir à des gens dans la même situation que moi.

### Le pivot AeroSpace pour les desktops

Le multi-desktop a été le deuxième pivot. Sur macOS Tahoe 26, Apple a verrouillé encore davantage les APIs SkyLight d'écriture (cf [yabai #2656](https://github.com/koekeishiya/yabai/issues/2656), [ADR-005](docs/decisions/ADR-005-tahoe-26-osax-injection-blocked.md) ici). La voie scripting-addition-dans-Dock, longtemps utilisée par yabai pour gérer les Spaces natifs, est de facto bloquée pour les bundles tiers.

J'ai donc repris l'approche d'[AeroSpace](https://github.com/nikitabobko/AeroSpace) : ne pas toucher aux Spaces natifs du tout, et gérer **N desktops virtuels** entièrement côté roadie, dans un unique Mac Space natif. La bascule de desktop consiste à déplacer hors-écran les fenêtres du desktop quitté et à restaurer celles du desktop d'arrivée à leur position mémorisée. Aucun appel SkyLight d'écriture, pas de scripting addition, pas de SIP désactivé. Là encore, dette intellectuelle entière envers AeroSpace, et je tiens à le dire.

roadie est donc un assemblage humble entre un peu de yabai (le tiler, l'AX-only sans SIP) et un peu d'AeroSpace (les desktops virtuels), avec en plus la couche stages que je n'ai pas trouvée chez l'un ou l'autre. Si tu cherches un vrai window manager mature, va vers yabai ou AeroSpace selon tes besoins — ce sont d'excellents projets, taillés pour le grand public.

## Ce que roadie fait aujourd'hui

| Capacité | État | Source |
|---|---|---|
| Tiling BSP + master-stack | OK | SPEC-002 |
| Stage Manager (groupes nommés ⌥1/⌥2/...) | OK | SPEC-002 |
| Desktops virtuels (1..16, pivot AeroSpace) | OK | SPEC-011 |
| Drag-to-adapt (resize manuel propage le tree) | OK | SPEC-002 |
| Click-to-raise universel | OK (Electron/JetBrains/Cursor) | SPEC-002 |
| Bordures de fenêtre focused (overlay NSWindow) | OK | SPEC-008 |
| Effets visuels avancés (animations, blur, opacity, shadowless) | Framework présent, runtime bloqué Tahoe 26 | SPEC-004→010, ADR-005 |
| 13 raccourcis BTT prêts à l'emploi | OK | SPEC-002 |

## Limites connues

- **Click-to-raise inter-app** non garanti à 100 % : sans SIP désactivé + injection scripting addition dans Dock.app (le chemin yabai), aucun WM ne peut atteindre 100 % sur macOS récent. AeroSpace a la même limitation par design. roadie fait le choix explicite de ne pas toucher SIP, donc accepte ce plafond.
- **Effets visuels SIP-off opt-in** (animations Bézier, blur, focus dimming, shadowless) : le framework est livré et les modules `.dylib` se chargent correctement, mais Apple a bloqué silencieusement l'injection des scripting additions tierces dans Dock sur Tahoe 26 — donc l'overlay CGS n'atteint pas les fenêtres tierces. Détail : [ADR-005](docs/decisions/ADR-005-tahoe-26-osax-injection-blocked.md). Les bordures de fenêtre (overlay NSWindow natif) fonctionnent par contre, sans osax.
- **Mono-display strict** pour la V2 : multi-display reporté à V3.

## Installation (build from source)

### Dépendances

| Outil | Requis | Installation | Utilité |
|---|---|---|---|
| Xcode Command Line Tools (`swift`, `codesign`) | oui | `xcode-select --install` | build, signature |
| `terminal-notifier` | oui | `brew install terminal-notifier` | notification cliquable quand TCC drop |
| `sketchybar` | optionnel | `brew install FelixKratz/formulae/sketchybar` | panneau barre du haut desktops × stages (SPEC-023) |
| `jq` | optionnel | `brew install jq` | parsing JSON dans le bridge SketchyBar |
| Certificat code-signing self-signed `roadied-cert` | oui | Keychain Access → Certificate Assistant → Create a Certificate (Self Signed Root, Code Signing) | préserve les permissions TCC entre rebuilds (cf [ADR-008](docs/decisions/ADR-008-signing-distribution-strategy.md)) |

Si tu ne veux pas le panneau SketchyBar : `ROADIE_WITH_SKETCHYBAR=0 ./scripts/install-dev.sh`.

### Build & install

```bash
git clone https://github.com/guthubrx/roadie.git
cd roadie
./scripts/install-dev.sh        # build + sign + deploy + setup launchd
```

Le script vérifie toutes les dépendances, build, signe chaque binaire avec `roadied-cert`, déploie dans `~/Applications/roadied.app/`, configure launchd. À relancer après chaque `swift build` pour pousser le binaire frais sans perdre les grants TCC.

Ensuite dans Réglages Système → Confidentialité et sécurité :
- **Accessibilité** : ajouter `~/Applications/roadied.app` et cocher
- **Enregistrement d'écran** : ajouter `~/Applications/roadied.app` et cocher (nécessaire pour la capture des thumbnails de fenêtres)

Une fois la case cochée, fige le hash binaire courant comme baseline TCC pour que les futurs rebuilds détectent les drifts :

```bash
./scripts/recheck-tcc.sh --mark-toggled
```

### Détection de drift TCC

`install-dev.sh` exécute `scripts/recheck-tcc.sh` à la fin de chaque déploiement. Si le hash du binaire deployed diffère de la dernière baseline `--mark-toggled`, tu obtiens un avertissement clair pour re-toggler Accessibility (sinon le daemon boucle sur `permission Accessibility manquante`). Workflow :

```bash
./scripts/install-dev.sh           # deploy + auto-recheck
# → si "drift détecté" : Réglages, décoche/recoche roadied
./scripts/recheck-tcc.sh --mark-toggled   # confirme la nouvelle baseline
```

```bash
roadied --daemon &
roadie desktop list   # sanity check
```

## Configuration

Tout passe par `~/.config/roadies/roadies.toml`. Exemple minimal :

```toml
[daemon]
log_level = "info"
socket_path = "~/.roadies/daemon.sock"

[tiling]
default_strategy = "bsp"
gaps_outer = 8
gaps_inner = 6

[desktops]
enabled = true
count = 10
back_and_forth = true

[stage_manager]
enabled = true
hide_strategy = "corner"
default_stage = "1"

[fx.borders]
enabled = true
thickness = 2
corner_radius = 10
active_color = "#7AA2F7"
inactive_color = "#414868"
focused_only = true
```

> Pour éviter les conflits avec les Spaces natifs : dans Réglages Système → Bureau, désactiver « Les écrans utilisent des Spaces séparés » et n'utiliser qu'**un seul Mac Space natif**. Roadie ignore les bascules Mac Space (Ctrl+→/← natifs).

## Documentation détaillée

Le projet est développé en [SpecKit](https://github.com/sergeykish/spec-kit) — une spec par feature majeure, avec plan, recherche, ADRs, tasks et REX d'implémentation.

### Specs principales

- [SPEC-002 — Tiler + Stage Manager](specs/002-tiler-stage/spec.md) (V1)
- [SPEC-011 — Virtual Desktops AeroSpace-style](specs/011-virtual-desktops/spec.md) (V2)
- [SPEC-004 → 010 — Famille opt-in SIP-off](specs/004-fx-framework/spec.md) (animations, bordures, blur, etc.)

### Décisions architecturales

- [ADR-001 — AX per-app, pas de SkyLight write](docs/decisions/ADR-001-ax-per-app-no-skylight.fr.md)
- [ADR-002 — Tree n-aire vs BSP binaire](docs/decisions/ADR-002-tree-naire-vs-bsp-binary.fr.md)
- [ADR-003 — Hide via corner offscreen](docs/decisions/ADR-003-hide-corner-vs-minimize.fr.md)
- [ADR-004 — Modules opt-in SIP-off](docs/decisions/ADR-004-sip-off-modules.fr.md)
- [ADR-005 — Tahoe 26 osax injection bloquée](docs/decisions/ADR-005-tahoe-26-osax-injection-blocked.fr.md)

## Crédits

- **[yabai](https://github.com/koekeishiya/yabai)** par Åke Kullenberg / koekeishiya — la référence du tiling sur macOS, dix ans de production, l'inspiration de tout le pattern AX + `_AXUIElementGetWindow`. Sans yabai, roadie n'existerait pas.
- **[AeroSpace](https://github.com/nikitabobko/AeroSpace)** par Nikita Bobko — le pivot virtual-desktops sans SkyLight write, démontré en production. Approche reprise telle quelle pour SPEC-011.
- **[Hyprland](https://github.com/hyprwm/Hyprland)** — l'inspiration du langage de courbes Bézier pour les animations (SPEC-007), même si l'osax bloquée sur Tahoe 26 empêche actuellement leur application aux fenêtres tierces.

## Status

Projet **personnel** et **résolument en cours de travail**. Le code évolue beaucoup en ce moment et continuera de bouger fortement dans les prochaines semaines à mesure que je l'utilise et que je découvre les rugosités sur mon propre poste. Mon objectif est clair : **en faire mon daily driver**, le gestionnaire de fenêtres avec lequel je travaille tous les jours, et donc le polir continûment au fil de l'usage réel.

Toutes les remarques, retours, suggestions, signalements de bugs, idées d'amélioration sont **vraiment** les bienvenus — ouvre une issue sur ce repo, je suis preneur. Pas de promesse de roadmap publique ni de support garanti pour l'instant, mais le projet est ouvert au dialogue et chaque retour fait avancer ma compréhension de ce qui marche ou pas en dehors de mon environnement.

Si tu cherches dès aujourd'hui un WM mature pour ton usage quotidien, regarde [yabai](https://github.com/koekeishiya/yabai) ou [AeroSpace](https://github.com/nikitabobko/AeroSpace) en premier — tu y trouveras une base bien plus stable que ce que roadie peut offrir à ce stade.

## License

MIT — voir [LICENSE](LICENSE).
