# roadies — Tiler + Stage Manager macOS

Window manager macOS modulaire en Swift, inspiré de yabai et AeroSpace, sans nécessiter SIP désactivé.

- **Tiler pluggable** : BSP par défaut, Master-Stack disponible, architecture extensible.
- **Stage manager opt-in** : groupes nommés de fenêtres masquables avec préservation du layout.
- **Click-to-focus fiable** : différenciateur vs AeroSpace, fonctionne sur Electron/JetBrains/Cursor.
- **Sans SIP** : uniquement AX public + `_AXUIElementGetWindow` privé stable depuis 10.7.

## Documentation

### V1 — Tiler + Stage Manager (mono-desktop)

- [Quickstart V1](specs/002-tiler-stage/quickstart.md) — install + premier run en 10 minutes
- [Spécification V1](specs/002-tiler-stage/spec.md) — 4 user stories, 23 FR, 10 SC
- [Plan technique V1](specs/002-tiler-stage/plan.md) — architecture 4 modules
- [ADR](docs/decisions/) — 3 décisions architecturales
- [Implementation log + REX V1](specs/002-tiler-stage/implementation.md)

### V2 — Virtual Desktops (pattern AeroSpace)

Roadie gère **N desktops virtuels** (1..16, défaut 10) entièrement côté roadie, dans **un seul** Mac Space natif. La bascule consiste à déplacer les fenêtres du desktop quitté hors-écran et restaurer celles du desktop d'arrivée à leur position attendue. Aucun appel SkyLight pour la bascule, aucune scripting addition Dock requise, pas de SIP off requis. **Stages V1 (⌥1/⌥2) inchangés** et scopés au desktop courant. Migration V1→V2 automatique au premier boot. Opt-in via `[desktops] enabled = true` (défaut).

> ℹ️ Pour éviter les conflits avec les Mac Spaces natifs, **désactive « Les écrans utilisent des Spaces séparés »** dans Réglages Système → Bureau et utilise un seul Mac Space natif. Roadie ignore les bascules Mac Space (Ctrl+→/← natifs).

- [Spec SPEC-011 Virtual Desktops](specs/011-virtual-desktops/spec.md) — 7 user stories, 25 FR, 10 SC
- [Plan SPEC-011](specs/011-virtual-desktops/plan.md) + [research](specs/011-virtual-desktops/research.md)
- [Quickstart](specs/011-virtual-desktops/quickstart.md)
- [Contrats CLI](specs/011-virtual-desktops/contracts/cli-desktop.md) + [events stream](specs/011-virtual-desktops/contracts/events-stream.md)

> SPEC-003 (multi-desktop V2 historique, basé sur Mac Space natif via SkyLight) est [DEPRECATED](specs/003-multi-desktop/spec.md) depuis 2026-05-02 — mécanisme cassé par macOS Tahoe 26 (yabai #2656).

Nouvelles commandes V2 :
```
roadie desktop list / current / focus <selector> / label <name> / back
roadie events --follow [--types desktop_changed,stage_changed]
```

## Build minimal

```bash
PATH="/usr/bin:/usr/local/bin:/bin" swift build -c release
make install-app
# Puis Réglages Système → Accessibilité → ajouter ~/Applications/roadied.app et cocher
roadied
```

## État

V1 : daemon + CLI compilent, 32 tests unitaires PASS, runtime non validé (audit B+, voir scoring).

Validation runtime à effectuer au premier passage utilisateur — voir REX dans implementation.md.

## Limitations connues

### Click-to-raise inter-app : non garanti à 100%

Le combo `kAXRaiseAction` + `kAXMain/Focused` + `_SLPSSetFrontProcessWithOptions` (SkyLight)
+ `NSRunningApplication.activate` couvre la majorité des cas, mais certaines paires d'apps
restent intermittentes (ex : iTerm2 source, Finder cible) sur macOS Sonoma+/Sequoia/Tahoe.

Cause : Apple a serré le pattern `yieldActivation` et un bug système Tahoe documenté empêche
le bring-to-front même en clic natif (cf. [Apple Community thread](https://discussions.apple.com/thread/256162304)).
Sans SIP désactivé + injection scripting addition dans Dock.app (chemin yabai), aucun WM
ne peut atteindre 100%. **AeroSpace a la même limitation par design.**

roadies fait le choix explicite de **ne pas désactiver SIP**, donc on accepte ce plafond.
