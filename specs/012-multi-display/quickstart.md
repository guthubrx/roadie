# Quickstart — Roadie Multi-Display

**Spec** : SPEC-012 | **Date** : 2026-05-02

## Pour l'utilisateur (test rapide)

### 1. Pré-requis

- macOS 14+ (testé Sonoma, Sequoia, Tahoe 26)
- Au moins 2 écrans connectés pour profiter du multi-display
- SPEC-011 multi-desktop fonctionnel (déjà validé en main)

### 2. Vérifier que roadie voit les écrans

```bash
~/.local/bin/roadie display list
```

Sortie attendue (1 écran) :
```
INDEX  ID  NAME                     FRAME           IS_MAIN  IS_ACTIVE  WINDOWS
1      1   Built-in Retina Display  0,0 2048x1280   *        *          5
```

Sortie attendue (2 écrans) :
```
INDEX  ID         NAME                     FRAME                  IS_MAIN  IS_ACTIVE  WINDOWS
1      1          Built-in Retina Display  0,0 2048x1280          *                   3
2      724592257  DELL U2723QE             -298,1280 3840x2160              *          2
```

### 3. Tiling indépendant par écran

Ouvre 2 fenêtres iTerm sur l'écran 1, 2 fenêtres Firefox sur l'écran 2. Les fenêtres iTerm doivent se tiler ensemble sur l'écran 1 sans toucher aux Firefox sur l'écran 2.

Si une fenêtre Firefox apparait sur l'écran 1 ou inversement, vérifier que son centre est bien dans le visibleFrame du bon écran.

### 4. Déplacer une fenêtre vers un autre écran

Frontmost une fenêtre, puis :

```bash
~/.local/bin/roadie window display 2
```

→ La fenêtre doit physiquement bouger vers l'écran 2 et être tilée selon la stratégie de l'écran 2.

Pour revenir :

```bash
~/.local/bin/roadie window display 1
```

### 5. Per-display config (optionnel)

Dans `~/.config/roadies/roadies.toml`, ajouter :

```toml
[[displays]]
match_index = 2                   # ou match_uuid = "AB123456-..."
default_strategy = "master_stack"
gaps_outer = 16
gaps_inner = 8
```

Recharger :

```bash
~/.local/bin/roadie daemon reload
```

L'écran 2 utilise désormais master-stack. L'écran 1 conserve la stratégie globale.

### 6. Branchement / débranchement

Débrancher le 2e écran. Toutes les fenêtres qui y étaient sont migrées vers le primary screen, leur frame ajustée. Aucune fenêtre n'est laissée hors-écran.

Rebrancher le 2e écran. Les fenêtres restent sur le primary (mapping perdu). Tu peux les redéplacer manuellement avec `roadie window display 2`.

### 7. Stream events display

Pour SketchyBar (ou autre subscriber) :

```bash
~/.local/bin/roadie events --follow --types display_changed,display_configuration_changed
```

Tu vois en temps réel les changements d'écran actif et les branch/débranch.

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
swift test --filter DisplayRegistryTests
swift test --filter MultiDisplayPersistenceTests
```

### Vérification SC-007 (0 SkyLight dans DisplayRegistry)

```bash
bash Tests/StaticChecks/no-cgs.sh
```

### Test perf manuel (SC-002)

Avec une fenêtre tilée :

```bash
time ~/.local/bin/roadie window display 2
# real    0m0.080s    ← cible < 200 ms p95
```

### Mock NSScreen pour tests unitaires

`DisplayRegistry` accepte un `DisplayProvider` injecté. En test :

```swift
let mockProvider = MockDisplayProvider(displays: [
    .mock(id: 1, frame: CGRect(0, 0, 2048, 1280), isMain: true),
    .mock(id: 2, frame: CGRect(2048, 0, 3840, 2160), isMain: false)
])
let registry = DisplayRegistry(provider: mockProvider)
```

Permet de tester toutes les transitions sans hardware.

---

## Migration depuis SPEC-011 (mono-écran → multi-écran)

Si tu es déjà sur SPEC-011 mono-écran, l'upgrade vers SPEC-012 est transparent :

1. Build + déploie comme d'habitude (`./scripts/restart.sh`)
2. `roadie display list` → 1 ligne, comportement identique à SPEC-011
3. Branche un 2e écran : `display_configuration_changed` event émis, l'écran 2 apparait dans `display list`, son arbre de tiling s'initialise vide
4. Les fenêtres existantes restent sur le primary, comme avant. Tu déplaces manuellement vers l'écran 2 avec `roadie window display 2`.

Au prochain reboot avec écran 2 connecté, les fenêtres déplacées restent sur leur écran d'origine grâce au `display_uuid` persisté.

## Troubleshooting

### Une fenêtre n'apparaît sur aucun écran (totalement offscreen)

```bash
~/.local/bin/roadie windows list | awk '$5 ~ /-3/ { print }'
```

Forcer le déplacement vers l'écran courant :

```bash
~/.local/bin/roadie window display main
```

### Display introuvable au boot pour une fenêtre persistée

Logs daemon :
```
{"level":"warn","msg":"window persisted display not connected, fallback to primary",
 "wid":"12345","display_uuid":"AB123..."}
```

Comportement : la fenêtre est attachée au primary à la place. Comportement conservatif.

### Le tiling ne se met pas à jour quand je branche un 2e écran

Vérifier les logs :
```bash
tail -20 /tmp/roadied.log | grep display
```

Tu devrais voir `display_configuration_changed` event à chaque change. Si absent, l'observer NSNotification n'est pas attaché — bug à diagnostiquer.
