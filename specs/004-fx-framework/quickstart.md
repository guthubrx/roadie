# Quickstart — Framework SIP-off opt-in (SPEC-004)

**Date** : 2026-05-01

Procédure pour installer et valider le framework FX sur une machine déjà équipée de roadie SPEC-002/003.

## Pré-requis

- Roadie installé et fonctionnel (SPEC-001/002/003)
- macOS 14 (Sonoma) min, recommandé 15 (Sequoia) ou 26 (Tahoe)
- **SIP partiellement désactivé** :
  ```bash
  csrutil status
  # Doit afficher au moins "Filesystem Protections: disabled"
  # Sinon, depuis Recovery Mode :
  # csrutil enable --without fs --without debug --without nvram
  ```

## Compilation et installation

V2 ne casse pas V1. La famille FX est strictement opt-in.

```bash
cd /Users/moi/Nextcloud/10.Scripts/39.roadies/.worktrees/004-fx-framework
make build-fx       # compile RoadieFXCore.dylib + module stub + osax bundle
sudo make install-fx # dépose osax dans /Library/ScriptingAdditions/
```

Le `Makefile` cible `install-fx` exécute le script `scripts/install-fx.sh` qui :

1. `cp -R osax /Library/ScriptingAdditions/roadied.osax`
2. `osascript -e 'tell application "Dock" to load scripting additions'`
3. `mkdir -p ~/.local/lib/roadie/`
4. `cp .build/release/libRoadieFXCore.dylib ~/.local/lib/roadie/`
5. `cp .build/release/libRoadieFXStub.dylib ~/.local/lib/roadie/` (uniquement pour valider end-to-end ; à retirer en prod)

## Validation premier run

### Test 1 — Détection osax côté daemon

```bash
roadie daemon reload   # ou redémarre via BTT ⌘⌃R
tail -20 ~/.local/state/roadies/daemon.log
```

Attendu :
```
INFO  fx_loader: SIP partial detected (filesystem off)
INFO  fx_loader: scanning ~/.local/lib/roadie/*.dylib
INFO  fx_loader: loaded RoadieFXStub v0.1
INFO  osax_bridge: connecting /var/tmp/roadied-osax.sock
INFO  osax_bridge: connected (UID match)
INFO  fx_loader: 1 module ready
```

### Test 2 — Status CLI

```bash
roadie fx status
```

Attendu :
```json
{
  "sip": "disabled-fs",
  "osax": "healthy",
  "modules": [
    {
      "name": "stub",
      "version": "0.1.0",
      "loaded_at": "2026-05-01T13:42:51Z"
    }
  ]
}
```

### Test 3 — Round-trip noop

Le module stub envoie un `noop` toutes les 5 secondes (juste pour la démo). Vérifier dans les logs :

```bash
tail -f ~/.local/state/roadies/daemon.log | grep noop
```

Attendu : entrées `osax_bridge: noop ack 12ms` toutes les 5 s.

### Test 4 — Comportement vanilla strict

Désinstaller temporairement la `.osax` :

```bash
sudo rm -rf /Library/ScriptingAdditions/roadied.osax
osascript -e 'tell application "Dock" to load scripting additions'  # force unload
roadie daemon reload
```

Attendu :
- `roadie fx status` : `{"sip": "disabled-fs", "osax": "absent", "modules": [...]}`
- Le module stub continue à exister mais ses `OSAXBridge.send` log warnings
- Aucun crash, daemon stable
- TOUS les tests SPEC-002 et SPEC-003 passent à l'identique

### Test 5 — Vanilla complet

Retirer aussi les dylibs :

```bash
rm -rf ~/.local/lib/roadie/*.dylib
roadie daemon reload
roadie fx status
# Attendu : {"modules": []}
```

À ce stade : machine = SPEC-003 vanilla strict.

## Vérification ABI / sécurité

### Test SC-007 — daemon clean

```bash
nm /Users/moi/.local/bin/roadied | grep -E 'CGSSetWindowAlpha|CGSSetWindowShadow|CGSSetWindowBlur|CGSSetWindowTransform|CGSAddWindowsToSpaces' | wc -l
```

Doit retourner **0**. Si > 0 → le daemon a été contaminé par un linkage statique illicite, c'est un bug bloquant.

### Test sécurité socket

```bash
ls -la /var/tmp/roadied-osax.sock
# Doit afficher mode 0600 et owner = ton uid (pas root)
```

```bash
# Test UID mismatch (depuis un autre user) :
sudo -u nobody nc -U /var/tmp/roadied-osax.sock
# Doit fermer immédiatement, log critical côté osax
```

## Désinstallation propre

```bash
sudo make uninstall-fx
```

Le script `scripts/uninstall-fx.sh` exécute :

1. `pkill -x roadied` (stop daemon proprement, déclenche `shutdown` modules)
2. `sudo rm -rf /Library/ScriptingAdditions/roadied.osax`
3. `osascript -e 'tell application "Dock" to load scripting additions'` (force unload osax)
4. `rm -f ~/.local/lib/roadie/*.dylib`
5. `roadied --daemon &` (relance vanilla)

Vérification :
```bash
find /Library/ScriptingAdditions ~/.local/lib/roadie -name 'roadied*' -o -name '*.dylib' 2>/dev/null
# Doit retourner vide
```

## Troubleshooting

### `osax not loaded` malgré install OK

Cause probable : Dock n'a pas reload les scripting additions. Force :
```bash
osascript -e 'tell application "Dock" to load scripting additions'
killall Dock   # macOS relance Dock automatiquement
roadie daemon reload
```

### `dlopen` échoue avec "code signature invalid"

Cause : signature ad-hoc du dylib incompatible avec celle du daemon.
Fix : recompiler le dylib avec la même identité (ad-hoc systématique) :
```bash
codesign --force --sign - --options runtime ~/.local/lib/roadie/*.dylib
```

### `permission_denied` au accept

Cause : UID mismatch. Vérifier :
```bash
echo "UID daemon : $(stat -f '%u' /Users/moi/.local/bin/roadied)"
echo "UID osax owner : $(stat -f '%u' /var/tmp/roadied-osax.sock)"
# Doivent être identiques (= ton uid utilisateur)
```

### Module crash au boot

Le daemon catch et continue avec les autres modules. Vérifier :
```bash
tail -50 ~/.local/state/roadies/daemon.log | grep -E 'fx_loader.*error'
```

L'erreur indique le module fautif. Retire son dylib + `roadie daemon reload` pour repartir clean.

## SIP fully on (test edge case)

Si tu veux tester le comportement vanilla sans toucher SIP :
```bash
# Dans config roadies.toml
[fx]
disable_loading = true   # SPEC-004 ajoute ce flag de safe-mode
```

Le daemon skip totalement le scan dylib. `roadie fx status` retourne `{"modules": [], "reason": "loading disabled in config"}`.
