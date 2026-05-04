# Quickstart — SPEC-025 Troubleshooting & Heal

## Quand utiliser `roadie heal`

Symptômes :
- Une fenêtre est invisible alors qu'elle apparaît dans `roadie windows list`
- Le rail compte plus de thumbnails que de fenêtres visibles à l'écran
- `roadie daemon audit` retourne `count > 0`
- Après un rebuild + restart, certaines fenêtres ne sont pas tilées

## Workflow standard

```bash
# 1. Diagnostiquer
roadie daemon health
# → verdict: healthy | degraded | corrupted

# 2. Si pas healthy : auto-fix
roadie heal
# → "X drifts fixed, Y wids restored, Z zombies purged (185 ms)"

# 3. Vérifier
roadie daemon health
# → verdict: healthy
```

## Si `roadie heal` ne suffit pas

```bash
# Option 1 : restart daemon (relance le bootstrap auto-fix)
launchctl bootout "gui/$(id -u)/com.roadie.roadie"
launchctl bootstrap "gui/$(id -u)" ~/Library/LaunchAgents/com.roadie.roadie.plist

# Option 2 : reset chirurgical des stages (en dernier recours)
# WARNING : perd les noms personnalisés de stages
cp -R ~/.config/roadies/stages ~/.config/roadies/stages.backup-$(date +%Y%m%d-%H%M%S)
rm ~/.config/roadies/stages/*/1/[0-9]*.toml
# puis restart daemon (option 1)
```

## Logs utiles

```bash
# 50 dernières lignes (warns/errors récents)
tail -50 ~/.local/state/roadies/daemon.log | grep -E 'warn|error'

# Suivi temps réel des events
roadie events --follow

# État santé au boot (cherche "boot_state_health")
grep "boot_state_health" ~/.local/state/roadies/daemon.log | tail -3
```

## Tests de non-régression

Si tu modifies du code, lance avant push :

```bash
./scripts/test-ipc-contract-frozen.sh    # SPEC-024 contract IPC public
bash Tests/25-boot-with-corrupted-saved-frame.sh
bash Tests/25-boot-with-zombie-wids.sh
bash Tests/25-heal-command.sh
```
