# Quickstart — Multi-desktop V2

**Date** : 2026-05-01

Procédure pour activer et valider la conscience multi-desktop sur une installation roadie V1 existante.

## Pré-requis

- Roadie V1 installé et fonctionnel (voir `specs/002-tiler-stage/quickstart.md`)
- Au moins 2 desktops macOS configurés via Mission Control natif (Réglages Système > Bureau & Dock > Mission Control si nécessaire d'en ajouter)
- macOS 14 (Sonoma) min, recommandé 15 (Sequoia) ou 26 (Tahoe)

## Installation V2 par-dessus V1

V2 ne casse pas V1. La mise à jour suit le flow standard :

```bash
cd <repo-root>/.worktrees/003-multi-desktop
make install-app
```

Le bundle `~/Applications/roadied.app` est remplacé. Les permissions Accessibility et Input Monitoring sont conservées (mêmes bundle ID `local.roadies.daemon`).

## Activation

V2 est **désactivé par défaut**. Pour l'activer, éditer `~/.config/roadies/roadies.toml` :

```toml
[multi_desktop]
enabled = true
back_and_forth = true
```

Puis recharger : `roadie daemon reload` (ou redémarrer via le raccourci BTT ⌘⌃R).

**Note migration** : au premier boot V2 avec `enabled = true`, roadie détecte la présence des fichiers V1 (`~/.config/roadies/stages/*.toml`), les déplace vers `~/.config/roadies/desktops/<current-desktop-uuid>.toml` et crée un backup horodaté `~/.config/roadies/stages.v1-backup-YYYYMMDD/`. Aucune intervention requise.

## Validation premier run

### Test 1 — Détection du desktop courant

```bash
roadie desktop current --json
```

Doit retourner un JSON avec `uuid`, `index`, `current_stage_id` correspondant au desktop sur lequel tu es. L'`uuid` doit être stable (relancer 3 fois la commande, même UUID).

### Test 2 — List des desktops

Crée 2 desktops via Mission Control natif (F3 → bouton "+"). Puis :

```bash
roadie desktop list
```

Sortie attendue : tableau avec 2 lignes (ou plus selon ton setup), `current` marqué `*` sur le desktop actif.

### Test 3 — Switch via roadie

```bash
roadie desktop focus next
```

macOS doit basculer vers le desktop suivant. `roadie desktop current` doit refléter le nouveau desktop.

### Test 4 — Stages séparés par desktop

Sur **desktop 1** :
```bash
roadie stage create alpha "Alpha"
roadie stage create beta "Beta"
roadie stage assign alpha   # assigne la fenêtre frontmost
```

Bascule sur **desktop 2** via Mission Control (Ctrl+→) :
```bash
roadie stage list
```

Attendu : aucun des stages "alpha" / "beta" n'apparaît. Le desktop 2 a son propre set de stages (ou est vide au premier accès).

Retour sur **desktop 1** :
```bash
roadie stage list
```

Attendu : "alpha" et "beta" réapparaissent intacts. Le stage actif au moment du départ est restauré.

### Test 5 — Stream d'événements

Dans un terminal :
```bash
roadie events --follow
```

Dans un autre terminal, bascule via Mission Control :
```bash
roadie desktop focus next
```

Attendu : une ligne JSON `{"event": "desktop_changed", ...}` apparaît dans le terminal events. De même pour `stage_changed` si tu fais `roadie stage 2`.

### Test 6 — Compat V1 stricte (kill switch)

Désactive la V2 :
```toml
[multi_desktop]
enabled = false
```

`roadie daemon reload`. Les commandes `roadie desktop *` retournent erreur (exit 4). Les commandes `roadie stage *` continuent à fonctionner sur un état global (comportement V1).

## Raccourcis BTT recommandés (V2 additionnels)

À ajouter au folder Roadie via la skill `bettertouch` (méthode AppleScript `add_new_trigger`) :

| Raccourci | Commande |
|---|---|
| ⌃⌥1 | `roadie desktop focus 1` |
| ⌃⌥2 | `roadie desktop focus 2` |
| ⌃⌥3 | `roadie desktop focus 3` |
| ⌃⌥← | `roadie desktop focus prev` |
| ⌃⌥→ | `roadie desktop focus next` |
| ⌃⌥B | `roadie desktop back` |

(Les ⌥1/⌥2 stage switch V1 restent inchangés.)

## Troubleshooting

### `desktop list` retourne 1 seul desktop

Vérifie que tu en as bien plusieurs configurés via Mission Control (F3). Roadie ne crée jamais de desktop, il ne fait qu'observer ceux que macOS expose.

### Switch ne met pas à jour `roadie stage list`

Vérifie `multi_desktop.enabled = true` dans la config. Si oui, regarde les logs `~/.local/state/roadies/daemon.log` :
```bash
tail -50 ~/.local/state/roadies/daemon.log | grep desktop
```
Tu dois voir des lignes `desktop_changed` à chaque transition.

### Migration V1 a échoué

Le backup est dans `~/.config/roadies/stages.v1-backup-YYYYMMDD/`. Pour rollback :
```bash
mv ~/.config/roadies/stages.v1-backup-YYYYMMDD ~/.config/roadies/stages
rm -rf ~/.config/roadies/desktops
# puis désactiver multi_desktop dans la config
```

### Perte d'event sur transition rapide

V2 ne coalesce pas, mais en cas de bursts > 100 events/sec (improbable user normal), des events peuvent être skippés. Vérifie via `roadie events --follow | wc -l` vs nombre attendu de transitions.
