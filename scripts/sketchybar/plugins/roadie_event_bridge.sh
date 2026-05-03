#!/usr/bin/env bash
# SPEC-023 — Bridge events roadie → SketchyBar (étendu vs version SPEC-011).
# À lancer en arrière-plan depuis sketchybarrc :
#   "$PLUGIN_DIR/roadie_event_bridge.sh" &
#
# Pour chaque event JSON-line émis par `roadie events --follow --types ...`,
# émet un trigger SketchyBar `roadie_state_changed` qui déclenche le re-render.
# Reconnect auto si daemon roadie redémarre (poll toutes les 2 s).

set -u

ROADIE="${ROADIE_BIN:-$HOME/.local/bin/roadie}"
SKETCHYBAR="${SKETCHYBAR_BIN:-/opt/homebrew/bin/sketchybar}"

# Liste des events qui changent l'état du panneau. Allow-list serveur :
# desktop_changed, stage_changed, stage_assigned, stage_created, stage_deleted,
# stage_renamed, window_created, window_destroyed, window_assigned,
# window_unassigned, config_reloaded, window_focused, thumbnail_updated.
TYPES="desktop_changed,stage_changed,stage_assigned,stage_created,stage_deleted,stage_renamed,window_created,window_destroyed,window_assigned,window_unassigned"

while true; do
    if [ ! -x "$ROADIE" ]; then
        sleep 2
        continue
    fi

    # Stream les events. À chaque ligne reçue, déclencher le re-render.
    # Pas besoin de parser le JSON : on déclenche un re-render générique qui
    # interroge l'état complet via les CLIs.
    "$ROADIE" events --follow --types "$TYPES" 2>/dev/null | \
    while IFS= read -r _line; do
        "$SKETCHYBAR" --trigger roadie_state_changed
    done

    # Reconnect après 2s si le stream meurt (daemon down, etc.).
    sleep 2
done
