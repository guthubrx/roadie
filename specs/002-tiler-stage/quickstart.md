# Quickstart — roadies (tiler + stage manager)

**Feature** : 002-tiler-stage | **Phase** : 1 | **Date** : 2026-05-01

Guide install + premier usage. Cible : utilisateur déjà à l'aise en terminal et avec yabai/AeroSpace. Lecture intégrale : 10 minutes.

---

## Prérequis

- macOS 14 (Sonoma) ou ultérieur. Testé sur Sequoia (15) et Tahoe (26).
- Xcode CommandLine Tools : `xcode-select --install`
- Quitter yabai et AeroSpace s'ils tournent : `brew services stop koekeishiya/formulae/yabai` et `osascript -e 'quit app "AeroSpace"'`

---

## 1. Build

```bash
cd /Users/moi/Nextcloud/10.Scripts/39.roadies/.worktrees/002-tiler-stage
swift build -c release
```

Produit deux binaires dans `.build/release/` :
- `roadied` — daemon
- `roadie` — CLI client

Vérification :
```bash
ls -la .build/release/roadie* | head
```

---

## 2. Installation

```bash
make install
```

Copie les deux binaires dans `~/.local/bin/`. Vérifier que c'est dans ton PATH :
```bash
which roadie roadied
```

Si non trouvés :
```bash
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.zshrc
source ~/.zshrc
```

---

## 3. Permission Accessibility

⚠️ **Critique** : le daemon a besoin d'Accessibility pour observer et manipuler les fenêtres. Comme appris de SPEC-001 (Sequoia/Tahoe TCC), un binaire CLI brut peut être refusé silencieusement par le panneau Réglages Système. **`make install` produit donc un bundle `.app`** :

```
~/Applications/roadied.app/
└── Contents/
    ├── MacOS/roadied
    └── Info.plist
```

Procédure d'autorisation :

1. Ouvrir **Réglages Système → Confidentialité et sécurité → Accessibilité**
2. Cliquer **+**
3. Cmd+Maj+G → coller `~/Applications/roadied.app`
4. Cliquer Ouvrir
5. **Activer l'interrupteur** à côté de `roadied`

Premier lancement :
```bash
roadied --daemon
```

Si "permission Accessibility manquante" → revérifier l'étape 5.
Si exit 0 → daemon en cours d'arrière-plan.

---

## 4. Vérifier l'état

```bash
roadie daemon status
```

Sortie attendue (exemple) :
```
roadied 0.1.0 — running for 0:00:23
tiled windows: 4
tiler strategy: bsp
stage_manager: disabled
```

```bash
roadie windows list
```

Liste les fenêtres actuelles avec leur position et état.

---

## 5. Usage de base — tiling auto

Avec le daemon en route, ouvrez 3 nouvelles fenêtres Terminal (Cmd+N depuis Terminal). Vous verrez le BSP automatique :

- 1ère : plein écran
- 2ème : split 50/50 horizontal
- 3ème : la moitié de la 2ème est divisée verticalement

Navigation au clavier (à câbler à des hotkeys, voir §7) :

```bash
roadie focus left
roadie focus right
roadie focus up
roadie focus down

roadie move left      # déplace la fenêtre focalisée
roadie resize right 50    # +50 px à droite
```

---

## 6. Activer le stage manager

Édite `~/.config/roadies/roadies.toml` :

```toml
[stage_manager]
enabled = true
hide_strategy = "corner"

[[stage_manager.workspaces.list]]
id = "dev"
display_name = "Development"

[[stage_manager.workspaces.list]]
id = "comm"
display_name = "Communication"
```

Recharge :
```bash
roadie daemon reload
```

Configurer tes stages :

1. Cliquer sur Terminal pour le mettre au premier plan
2. `roadie stage assign dev`
3. Cliquer sur ton navigateur
4. `roadie stage assign comm`
5. Bascule : `roadie stage dev` puis `roadie stage comm`

---

## 7. Câbler des hotkeys

Le daemon n'inclut pas de gestion de hotkeys (principe Unix). Tu choisis ton outil. Exemples :

### Karabiner-Elements

`~/.config/karabiner/karabiner.json`, ajouter une rule :

```json
{
  "description": "roadie shortcuts (hyper)",
  "manipulators": [
    {
      "type": "basic",
      "from": { "key_code": "h", "modifiers": { "mandatory": ["left_shift", "left_command", "left_control", "left_option"] } },
      "to": [{ "shell_command": "/Users/moi/.local/bin/roadie focus left" }]
    },
    {
      "type": "basic",
      "from": { "key_code": "j", "modifiers": { "mandatory": ["left_shift", "left_command", "left_control", "left_option"] } },
      "to": [{ "shell_command": "/Users/moi/.local/bin/roadie focus down" }]
    }
    /* idem k=up, l=right, etc. */
  ]
}
```

⚠️ Sur Sequoia+, Karabiner peut avoir le même problème de TCC qu'avec stage. Voir §3.

### BetterTouchTool

Crée des raccourcis "Execute Shell Script" avec les commandes `/Users/moi/.local/bin/roadie focus left` etc.

### skhd

`~/.config/skhd/skhdrc` :

```
hyper - h : roadie focus left
hyper - j : roadie focus down
hyper - k : roadie focus up
hyper - l : roadie focus right
hyper - 1 : roadie stage dev
hyper - 2 : roadie stage comm
```

---

## 8. Lancer au démarrage

Pour que `roadied` se lance à chaque login, créer un LaunchAgent :

`~/Library/LaunchAgents/com.local.roadies.plist` :

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>com.local.roadies</string>
  <key>ProgramArguments</key>
  <array>
    <string>/Users/moi/Applications/roadied.app/Contents/MacOS/roadied</string>
  </array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>StandardOutPath</key>
  <string>/tmp/roadied.out</string>
  <key>StandardErrorPath</key>
  <string>/tmp/roadied.err</string>
</dict>
</plist>
```

Charger :
```bash
launchctl load ~/Library/LaunchAgents/com.local.roadies.plist
```

---

## 9. Désinstallation

```bash
launchctl unload ~/Library/LaunchAgents/com.local.roadies.plist 2>/dev/null
rm -rf ~/Applications/roadied.app
rm ~/.local/bin/roadie ~/.local/bin/roadied
rm -rf ~/.config/roadies ~/.roadies ~/.local/state/roadies
rm ~/Library/LaunchAgents/com.local.roadies.plist
```

Et retirer `roadied` des autorisations Accessibility dans Réglages Système.

---

## 10. Dépannage

### Le daemon ne démarre pas

```bash
roadied --daemon 2>&1 | head -20
```

Lit la première erreur. Habituellement permission Accessibility ou socket déjà existant.

### Les fenêtres ne se tilent pas

Vérifier :
1. Daemon en cours : `pgrep -lf roadied`
2. Permission Accessibility ON
3. App pas dans `[exclusions.floating_bundles]`
4. App pas en plein écran natif (kAXFullScreen)

```bash
roadie windows list
```

Te dit l'état de chaque fenêtre.

### Click-to-focus ne marche pas sur une app

Reporter le bundle ID dans une issue. Le daemon log les events AX :
```bash
tail -f ~/.local/state/roadies/daemon.log | grep focus
```

### Le daemon consomme trop de CPU

Probablement un AXObserver qui boucle. Voir logs :
```bash
tail -100 ~/.local/state/roadies/daemon.log
```

### Conflit avec yabai/AeroSpace

Quitter complètement les autres tilers avant `roadied`. Pas de cohabitation possible (chacun veut être l'autorité finale sur les frames).

---

## Validation rapide

Pour vérifier que l'install fonctionne en 30 secondes :

```bash
# 1. Daemon up ?
roadie daemon status || { echo "FAIL: daemon down"; exit 1; }

# 2. Liste de fenêtres ?
roadie windows list | head -3 || { echo "FAIL: cannot list"; exit 1; }

# 3. Tiling reactif ? (ouvrir Terminal nouveau, vérifier qu'il apparaît dans windows list)
osascript -e 'tell app "Terminal" to do script ""'
sleep 1
roadie windows list | grep -q Terminal || { echo "FAIL: new window not detected"; exit 1; }

echo "OK : install fonctionnelle"
```

Si tout passe : tu es prêt.
