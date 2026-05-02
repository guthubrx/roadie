# Quickstart — SPEC-014 Stage Rail UI

**Status**: Draft
**Last updated**: 2026-05-02
**Audience**: utilisateur final qui veut activer le rail visuel sur sa machine.

## Prérequis

- macOS 14+ (Sonoma, Sequoia, Tahoe).
- `roadied` installé et tournant (cf SPEC-002 quickstart).
- Permission Accessibility accordée à `roadied.app`.
- Au moins SPEC-002 (Stage Manager) opérationnel sur ta machine.

## 1. Build

```bash
cd <repo-root>
make build-rail
```

Cela compile `roadie-rail` (universal binary x86_64 + arm64) et le bundle `.app` correspondant dans `.build/release/`.

## 2. Install

```bash
make install-rail
```

Cela copie le binaire dans `~/.local/bin/roadie-rail` et le bundle dans `~/Applications/roadie-rail.app`.

## 3. Permission Screen Recording (recommandée)

Pour bénéficier des **vraies vignettes** des fenêtres dans le rail (au lieu d'icônes d'app statiques), accorde la permission Screen Recording **au daemon** `roadied`, pas au rail :

1. Ouvre Réglages Système → Confidentialité et sécurité → Enregistrement de l'écran.
2. Clique sur le `+` et ajoute `~/Applications/roadied.app`.
3. Coche la case correspondante.
4. Redémarre `roadied` : `killall roadied && roadied --daemon &`.

**Si tu refuses** : le rail fonctionne quand même, mais affiche les icônes d'app à la place des vignettes. Aucune autre dégradation.

> Note : c'est bien le **daemon** qui demande cette permission, pas le rail. Le rail lui-même n'a aucune permission système à autoriser.

## 4. Configuration TOML

Édite `~/.config/roadies/roadies.toml` et ajoute la section :

```toml
[fx.rail]
enabled = true
reclaim_horizontal_space = false      # mets à true pour que les fenêtres se rétrécissent quand le rail est visible
wallpaper_click_to_stage = true       # active le geste "click bureau → nouvelle stage"
panel_width = 408
edge_width = 8
fade_duration_ms = 200
```

Recharge la config sans redémarrer le daemon :

```bash
roadie daemon reload
```

## 5. Lancement

### Lancement manuel (recommandé pour découverte)

```bash
roadie-rail &
```

Le rail démarre, se met en veille (invisible), et n'apparaît que quand tu approches la souris du bord gauche d'un écran.

### Toggle via CLI

```bash
roadie rail toggle    # démarre ou arrête le rail
roadie rail status    # voir s'il tourne
```

### LaunchAgent (au login automatique)

Crée `~/Library/LaunchAgents/local.roadies.rail.plist` :

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>local.roadies.rail</string>
  <key>ProgramArguments</key>
  <array>
    <!-- Remplace USERNAME par ton username (plist macOS n'expand pas ~ ni $HOME) -->
    <string>/Users/USERNAME/.local/bin/roadie-rail</string>
  </array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key>
  <dict>
    <key>SuccessfulExit</key><false/>
  </dict>
  <key>StandardOutPath</key><string>/tmp/roadie-rail.out</string>
  <key>StandardErrorPath</key><string>/tmp/roadie-rail.err</string>
</dict>
</plist>
```

Charge :

```bash
launchctl load ~/Library/LaunchAgents/local.roadies.rail.plist
```

Décharge :

```bash
launchctl unload ~/Library/LaunchAgents/local.roadies.rail.plist
```

## 6. Première utilisation

### a) Faire apparaître le rail

Approche le pointeur souris du **bord gauche de ton écran** (les 8 premiers pixels). Le rail apparaît en fade-in 200 ms avec la liste des stages du desktop courant.

### b) Basculer entre stages

Clique sur une carte de stage non-active. Tu bascules. La carte devient surlignée.

### c) Déplacer une fenêtre entre stages

Clique-glisse une vignette de fenêtre depuis sa carte d'origine vers la carte d'une autre stage. Relâche → la fenêtre est migrée.

### d) Le geste central : click sur le wallpaper

1. Aie au moins 1 fenêtre tilée visible sur ton desktop courant.
2. Clique sur le **bureau** (zone du wallpaper, hors de toute fenêtre).
3. Toutes tes fenêtres tilées sont **rangées dans une nouvelle stage** qui apparaît dans le rail.
4. Ton desktop devient vide. Tu peux ouvrir une nouvelle app pour bâtir une nouvelle collection.
5. Pour revenir à ta collection précédente, clique sur sa carte dans le rail.

C'est le comportement Stage Manager natif d'Apple, transposé au tiling roadie.

### e) Renommer / supprimer une stage

Clic-droit sur une carte → menu contextuel : "Rename stage…" / "Add focused window" / "Delete stage".

## 7. Désinstallation

```bash
make uninstall-rail
```

Cela retire `~/.local/bin/roadie-rail` et `~/Applications/roadie-rail.app`. Le daemon `roadied` continue de fonctionner identiquement à l'état pré-014.

Si tu avais ajouté un LaunchAgent, retire-le aussi :

```bash
launchctl unload ~/Library/LaunchAgents/local.roadies.rail.plist
rm ~/Library/LaunchAgents/local.roadies.rail.plist
```

## 8. Troubleshooting

| Symptôme | Cause probable | Solution |
|---|---|---|
| Rail n'apparaît pas au hover | Daemon down | `pgrep roadied` ; relancer si besoin |
| Rail affiche "daemon offline" | Socket non joignable | `ls -l ~/.roadies/daemon.sock` ; permissions ? |
| Vignettes blanches / vides | Screen Recording non accordée | Ajouter `roadied.app` dans Réglages Système |
| Click bureau ne fait rien | `wallpaper_click_to_stage = false` ou rail non lancé | Vérifier `roadie rail status` |
| Hot corner Mission Control intercepté | Rare — edge sensor en conflit | Augmenter `edge_width` ou désactiver hot corners temporairement |
| Multi-display : un rail manque | `[desktops] mode = "global"` et écran secondaire | Passer en `mode = "per_display"` (cf SPEC-013) |
| CPU rail élevé | Polling trop agressif | Augmenter `mouse_poll_interval_ms` à 120 ou 160 |

## 9. Tests fumants (acceptance)

Si tu veux vérifier que tout marche end-to-end après installation :

```bash
cd <repo-root>
bash tests/14-rail-show-hide.sh        # hover edge → fade-in/out
bash tests/14-rail-stage-switch.sh     # click card → switch stage
bash tests/14-rail-drag-drop.sh        # drag chip entre cards → move window
bash tests/14-wallpaper-click.sh       # click bureau → nouvelle stage
bash tests/14-no-regression-spec-002.sh  # SPEC-002 toujours OK avec le rail
```
