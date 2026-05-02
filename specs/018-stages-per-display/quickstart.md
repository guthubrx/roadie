# Quickstart — SPEC-018 Stages-per-display

**Status**: Draft
**Last updated**: 2026-05-02

## Public visé

Utilisateur multi-display de roadie qui veut isoler ses stages par écran. Les utilisateurs mono-display peuvent ignorer cette spec : le mode `global` (default V1) reste inchangé.

## Prérequis

- Daemon `roadied` v1.x avec SPEC-018 livré
- Au moins 2 écrans physiques connectés (sinon le scopage perd son intérêt)
- SPEC-013 multi-desktop activé : `[desktops] enabled = true`

## Activation

### 1. Activer le mode `per_display` dans la config

Éditer `~/.config/roadies/roadies.toml` :

```toml
[desktops]
enabled = true
mode = "per_display"   # default V1 = "global"
count = 4
```

### 2. Redémarrer le daemon

```bash
roadie daemon reload
# ou si reload ne couvre pas le mode switch :
launchctl unload ~/Library/LaunchAgents/local.roadies.daemon.plist
launchctl load   ~/Library/LaunchAgents/local.roadies.daemon.plist
```

### 3. Migration automatique au premier boot

Au premier démarrage en mode `per_display`, le daemon migre automatiquement les stages V1 existantes :

```
[INFO] migration_v1_to_v2: detected 5 flat stages, migrating to per_display layout
[INFO] migration_v1_to_v2: backup created at ~/.config/roadies/stages.v1.bak
[INFO] migration_v1_to_v2: completed in 23ms, target_display=37D8832A-...
```

Vérifier dans le flux events :

```bash
roadie events --follow --types migration_v1_to_v2
```

Vérifier le résultat sur disque :

```bash
ls -la ~/.config/roadies/stages/
# avant : 1.toml, 2.toml, 3.toml, ...
# après : 37D8832A-2D66-4A47-9B5E-39DA5CF2D85F/   (le UUID du primary display)
#         + stages.v1.bak/

ls -la ~/.config/roadies/stages/37D8832A-*/1/
# 1.toml, 2.toml, 3.toml, ...
```

## Test isolation cross-display

```bash
# Curseur sur Display 1 (souris sur écran principal)
roadie stage assign 2     # créée stage 2 dans (D1, desktop 1)
roadie stage list         # → contient stage 1 + stage 2

# Bouger souris sur Display 2 (changement physique, pas de raccourci spécial)
roadie stage list         # → contient SEULEMENT stage 1 (la stage 2 vit sur D1)

# Créer une stage 2 distincte sur D2
roadie stage assign 2     # créée stage 2 dans (D2, desktop 1)
roadie stage list         # → contient stage 1 + stage 2 (mais ≠ celle de D1)

# Override explicite pour scripts
roadie stage list --display 1 --desktop 1   # voir les stages de D1 sans bouger
roadie stage list --display 2 --desktop 1   # voir les stages de D2 sans bouger
```

## Rail UI compat (SPEC-014)

Le rail UI bénéficie automatiquement du scopage — chaque panel rail (un par écran) reçoit les stages de son scope `(displayUUID, desktopID)`. Aucune intervention requise.

```bash
roadie rail toggle    # lance le rail (si pas déjà actif)
# Survoler edge gauche de Display 1 → liste stages de (D1, current_desktop_D1)
# Survoler edge gauche de Display 2 → liste stages de (D2, current_desktop_D2)
```

## Override CLI pour scripts

Pour scripts qui ne veulent pas dépendre du pointeur (BTT, SketchyBar, automations) :

```bash
roadie stage list --display 1 --desktop 2
roadie stage assign 5 --display 2 --desktop 1
roadie stage rename 3 "Comm" --display 1 --desktop 1
```

Sélecteur display accepté :
- Index 1-N (ordre `roadie display list`)
- UUID natif (string Apple type "37D8832A-...")

## Recovery V1

Si la migration a échoué ou si l'utilisateur veut revenir à V1 (mode `global`) :

```bash
# 1. Stopper le daemon
launchctl unload ~/Library/LaunchAgents/local.roadies.daemon.plist

# 2. Restaurer le backup V1
mv ~/.config/roadies/stages ~/.config/roadies/stages.v2.broken
mv ~/.config/roadies/stages.v1.bak ~/.config/roadies/stages

# 3. Repasser en mode global
sed -i '' 's/mode = "per_display"/mode = "global"/' ~/.config/roadies/roadies.toml

# 4. Relancer
launchctl load ~/Library/LaunchAgents/local.roadies.daemon.plist
roadie stage list   # = comportement V1 retrouvé
```

## Hot-switch de mode (avec précaution)

Switcher de `global` à `per_display` (ou inverse) à chaud nécessite un redémarrage du daemon. La doc officielle recommande :

```bash
# Recommandé : full restart
launchctl unload ~/Library/LaunchAgents/local.roadies.daemon.plist
# (modifier roadies.toml)
launchctl load   ~/Library/LaunchAgents/local.roadies.daemon.plist

# Quick & dirty (best effort, peut nécessiter recovery manuelle)
roadie daemon reload
```

⚠️ **Limitation V1** : si vous passez de `per_display` à `global`, l'arborescence nested `<UUID>/<desktopID>/` reste sur disque mais n'est PAS lue. Vous devrez manuellement déplacer les fichiers TOML si vous voulez retrouver vos stages en mode global. Une SPEC future couvrira l'auto-flatten.

## Debug

### Inspecter le scope inféré

```bash
roadie stage list --json | jq '.payload.scope'
# {
#   "display_uuid": "37D8832A-...",
#   "display_index": 1,
#   "desktop_id": 1,
#   "inferred_from": "cursor"
# }
```

`inferred_from` peut être `"cursor"` (priorité 1), `"frontmost"` (priorité 2), `"primary"` (fallback), ou `"override"` (`--display`/`--desktop` passés).

### Statut migration

```bash
roadie daemon status --json | jq '.payload.migration_pending'
# false (migration faite ou non requise)
# true  (migration tentée mais a échoué — investiguer ~/.config/roadies/stages.v1.bak)
```

### Liste des scopes existants

```bash
find ~/.config/roadies/stages -name "*.toml" | head -20
# /Users/moi/.config/roadies/stages/37D8832A-.../1/1.toml
# /Users/moi/.config/roadies/stages/37D8832A-.../1/2.toml
# /Users/moi/.config/roadies/stages/9F22B3D1-.../1/1.toml
# ...
```

## Désinstallation / désactivation

Repasser en mode `global` (cf "Recovery V1") suffit. Aucune désinstallation spécifique.

Les stages "orphelines" d'écrans débranchés peuvent être nettoyées manuellement :

```bash
# Lister les UUID disque vs UUID actuels
ls ~/.config/roadies/stages/                 # tous les UUID jamais vus
roadie display list --json | jq -r '.displays[].uuid'  # UUIDs branchés actuellement

# Supprimer les UUID orphelins (à vos risques)
rm -rf ~/.config/roadies/stages/<UUID-débranché>/
```
