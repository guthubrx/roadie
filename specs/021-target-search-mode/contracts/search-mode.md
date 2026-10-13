# Contrat : mode recherche

## Configuration
```toml
[experimental.target_mode]
search_hotkey = "cmd+alt+ctrl+f"   # "" désactive ; "hyper+f" équivalent
```
Validation : erreur si la chaîne n'est pas vide et ne s'analyse pas (`roadie config validate`).

## CLI
`roadie targets search [--duration N]` : ouvre la session de recherche dans le daemon (même effet que le raccourci).

## Touches pendant la session
| Touche | Effet |
|---|---|
| texte | filtre |
| Effacement | retire un caractère |
| Tab, Flèche bas, Ctrl-N | correspondance suivante |
| Maj-Tab, Flèche haut, Ctrl-P | précédente |
| Maj + label | met en avant la cible de ce label |
| Retour | action par défaut (clic pour une cible d'app) |
| Retour ×2 rapide | double-clic |
| Maj-Retour | clic droit |
| Cmd-Retour | Cmd-clic |
| `*` ou `;` | toutes les cibles |
| `?` | propriétés de la cible mise en avant |
| Échap | fermer |

## Événements
`target_mode.search_started` (count), `target_mode.finished` (inchangé), `target_mode.search_hotkey` (registered/failed, raccourci).
