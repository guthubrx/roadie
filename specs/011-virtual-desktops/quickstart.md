# Quickstart — Roadie Virtual Desktops

**Spec** : SPEC-011 | **Date** : 2026-05-02

## Pour l'utilisateur final (test rapide)

### 1. Activer la feature

`~/.config/roadies/roadies.toml` :

```toml
[desktops]
enabled = true
count = 5            # commencer avec 5 desktops
default_focus = 1
back_and_forth = true
```

### 2. Redémarrer le daemon

```bash
launchctl unload ~/Library/LaunchAgents/com.roadie.roadie.plist
launchctl load   ~/Library/LaunchAgents/com.roadie.roadie.plist
# ou simplement
killall roadied; nohup ~/.local/bin/roadied --daemon > /tmp/roadied.log 2>&1 &
```

### 3. Vérifier

```bash
roadie desktop list
# ID  LABEL  CURRENT  RECENT  WINDOWS  STAGES
# 1   (none) *                 5        1
# 2   (none)                   0        1
# ...
```

### 4. Bascule manuelle

Avec quelques fenêtres ouvertes :

```bash
roadie desktop focus 2
# Toutes les fenêtres disparaissent (déplacées offscreen)
roadie desktop focus 1
# Elles reviennent
```

### 5. Bascule via BTT (ou raccourcis system)

Configurer dans BTT (folder Roadie) :

| Raccourci AZERTY | Action shell |
|---|---|
| ⌘+& | `~/.local/bin/roadie desktop focus 1` |
| ⌘+é | `~/.local/bin/roadie desktop focus 2` |
| ⌘+" | `~/.local/bin/roadie desktop focus 3` |
| ⌘+' | `~/.local/bin/roadie desktop focus 4` |
| ⌘+( | `~/.local/bin/roadie desktop focus 5` |

Les ⌥+1, ⌥+2 (stages) restent inchangés.

### 6. Recommandation système

Réglages Système → Bureau → désactiver « Les écrans utilisent des Spaces séparés » (option α du pivot). Ça évite tout conflit potentiel entre Mac Spaces natifs et desktops virtuels roadie.

---

## Pour le développeur (dev/test)

### Build

```bash
export PATH=/usr/bin:/bin:/usr/sbin:/sbin
swift build --product roadied
swift build --product roadie
```

### Tests

```bash
swift test --filter RoadieDesktopsTests
```

Cibles :
- `DesktopRegistryTests` : load/save round-trip, parsing TOML, corruption recovery.
- `DesktopSwitcherTests` : bascule simple, idempotence, queue collapsing, range check.
- `MigrationTests` : V1 → V2 mapping, SPEC-003 archive.
- `IntegrationTests` (optionnel) : daemon en harness, socket dans `/tmp/roadied-test-<pid>.sock`.

### Test perf manuel (SC-001)

Avec 10 fenêtres ouvertes :

```bash
time roadie desktop focus 2
# real    0m0.080s    ← cible < 200 ms p95
```

### Vérification SC-005 (0 appel SkyLight pour la bascule)

```bash
git ls-files Sources/RoadieDesktops/ | xargs grep -lE 'CGS|SLS|SkyLight'
# (aucune sortie attendue)
```

### Stream events

Terminal 1 :

```bash
roadie events --follow --types desktop_changed
```

Terminal 2 :

```bash
roadie desktop focus 1
roadie desktop focus 2
roadie desktop focus 3
```

Terminal 1 affiche :

```json
{"event":"desktop_changed","from":"2","to":"1","from_label":"","to_label":"","ts":1714672389123}
{"event":"desktop_changed","from":"1","to":"2",...}
{"event":"desktop_changed","from":"2","to":"3",...}
```

---

## Migration depuis V1

Si tu utilisais déjà roadie V1 (stages dans `~/.config/roadies/stages/`) :

1. Garder la config existante (rien à faire).
2. Activer `[desktops] enabled = true` dans `roadies.toml`.
3. Redémarrer le daemon.
4. Au premier boot, tous tes stages V1 sont mappés sur le desktop 1.
5. `roadie desktop list` montre 1 desktop avec tes stages historiques.
6. ⌥+1 / ⌥+2 fonctionnent à l'identique.
7. Crée tes desktops 2..N en y assignant des fenêtres (`roadie desktop focus 2` puis ouvrir des apps là).

## Migration depuis SPEC-003 (V2 ancien deprecated)

Si tu avais activé l'ancien multi-desktop (`[multi_desktop] enabled = true`, indexé par UUID Mac Space) :

1. `[multi_desktop]` est ignoré désormais. Remplace par `[desktops]`.
2. Au premier boot V2-pivot, tes anciens dossiers `~/.config/roadies/desktops/<UUID>/` sont **archivés** dans `~/.config/roadies/desktops/.archived-spec003-<UUID>/` (récupérable manuellement).
3. La migration V1 → V2 (cf. ci-dessus) est appliquée à partir de tes stages V1.
4. Si tu n'as pas de stages V1 (utilisateur direct SPEC-003), tu démarres avec un desktop 1 vierge.

## Désactiver la feature

```toml
[desktops]
enabled = false
```

Comportement : exactement V1, aucune commande `desktop.*` disponible (exit 2 + erreur claire).

---

## Troubleshooting

### Une fenêtre est restée offscreen

```bash
roadie windows.list | grep -E 'x=-3'
# liste les fenêtres positionnées en x=-30000
```

Forcer une bascule cyclique pour réinitialiser :

```bash
for i in 1 2 3 4 5 1; do roadie desktop focus $i; sleep 0.1; done
```

### Le daemon ne voit pas la config

```bash
cat ~/.config/roadies/roadies.toml | grep -A5 '\[desktops\]'
roadie config dump  # affiche la config résolue
```

### Les events ne sont pas émis

Vérifier que le subscriber est bien connecté :

```bash
roadie events --follow > /tmp/test.jsonl &
sleep 1
roadie desktop focus 2
sleep 0.2
cat /tmp/test.jsonl
# devrait contenir 1 ligne desktop_changed
```
