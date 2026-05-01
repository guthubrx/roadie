# roadies — Tiler + Stage Manager macOS

Window manager macOS modulaire en Swift, inspiré de yabai et AeroSpace, sans nécessiter SIP désactivé.

- **Tiler pluggable** : BSP par défaut, Master-Stack disponible, architecture extensible.
- **Stage manager opt-in** : groupes nommés de fenêtres masquables avec préservation du layout.
- **Click-to-focus fiable** : différenciateur vs AeroSpace, fonctionne sur Electron/JetBrains/Cursor.
- **Sans SIP** : uniquement AX public + `_AXUIElementGetWindow` privé stable depuis 10.7.

## Documentation

- [Quickstart](specs/002-tiler-stage/quickstart.md) — install + premier run en 10 minutes
- [Spécification](specs/002-tiler-stage/spec.md) — 4 user stories, 23 FR, 10 SC
- [Plan technique](specs/002-tiler-stage/plan.md) — architecture 4 modules
- [Recherche yabai+AeroSpace](specs/002-tiler-stage/research.md) — 820 lignes
- [ADR](docs/decisions/) — 3 décisions architecturales
- [Implementation log + REX](specs/002-tiler-stage/implementation.md)

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
