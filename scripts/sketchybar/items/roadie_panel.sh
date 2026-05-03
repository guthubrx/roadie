#!/usr/bin/env bash
# SPEC-023 — Init du panneau SketchyBar desktops × stages.
# Sourced depuis sketchybarrc. Crée l'event + un item trigger sink invisible
# qui exécute le handler à chaque trigger roadie_state_changed.

# Event custom (idempotent — sketchybar ignore si déjà déclaré).
sketchybar --add event roadie_state_changed

# Item invisible "sink" qui exécute le handler à chaque trigger.
# drawing=off → pas affiché dans la barre. Largeur 0 → n'occupe pas d'espace.
# Le `script` est appelé sur chaque event auquel l'item est subscribed.
sketchybar --add item roadie.sink left \
           --set roadie.sink drawing=off \
                              updates=on \
                              script="$PLUGIN_DIR/roadie_panel.sh" \
           --subscribe roadie.sink roadie_state_changed system_woke

# Render initial via trigger.
sketchybar --trigger roadie_state_changed
