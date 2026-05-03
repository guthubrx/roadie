#!/usr/bin/env bash
# SPEC-023 — Handler SketchyBar : re-render du panneau desktops × stages.
# Appelé sur trigger `roadie_state_changed` ou `mouse.clicked`.
#
# Stratégie : remove all `roadie.*` items, re-add tout. ~50 ms total pour ≤ 24 items.

set -u

# SketchyBar n'exporte que ITEM_DIR/PLUGIN_DIR/CONFIG_DIR. LIB_DIR est notre convention.
LIB_DIR="${LIB_DIR:-${CONFIG_DIR:-$HOME/.config/sketchybar/sketchybar}/lib}"
# shellcheck source=/dev/null
. "$LIB_DIR/colors.sh"
# shellcheck source=/dev/null
. "$LIB_DIR/state.sh"

ROADIE="${ROADIE_BIN:-$HOME/.local/bin/roadie}"
MAX_DESKTOPS=3
LOG=/tmp/roadie-sketchybar.log
ITEMS_FILE=/tmp/roadie-sketchybar-items.txt
LOCKDIR=/tmp/roadie-sketchybar.lock.d

# SPEC-023 — supprime tous les items roadie.* tracés dans ITEMS_FILE.
# `sketchybar --query default_items` ne retourne pas la liste, donc on track
# nous-mêmes les items créés. En cas de fichier corrompu, brute-force fallback.
remove_all_roadie_items() {
    # SPEC-023 — utilise UNIQUEMENT le ITEMS_FILE (track persistant).
    # Le brute-force des 100 patterns possibles saturait l'IPC SketchyBar
    # (observé : crash au clic sous burst de --remove).
    if [ -f "$ITEMS_FILE" ]; then
        # Batch SketchyBar : 1 seule commande avec multiples --remove.
        local args=()
        while IFS= read -r item; do
            [ -n "$item" ] && args+=(--remove "$item")
        done < "$ITEMS_FILE"
        if [ ${#args[@]} -gt 0 ]; then
            sketchybar "${args[@]}" 2>/dev/null
        fi
    fi
    # SPEC-023 — toujours retirer les items "alerte" même s'ils ne sont pas dans
    # le fichier (cas : daemon_down créé pendant un crash sans tracking).
    sketchybar --remove roadie.daemon_down 2>/dev/null
    sketchybar --remove roadie.empty 2>/dev/null
    : > "$ITEMS_FILE"
}

# Track un item créé (pour le re-supprimer au prochain render).
track_item() {
    echo "$1" >> "$ITEMS_FILE"
}

# --- Click handler -----------------------------------------------------------

if [ "${SENDER:-}" = "mouse.clicked" ]; then
    NAME="${NAME:-}"
    # SPEC-023 — détache complètement les commandes roadie via setsid/disown
    # pour que le click_script termine immédiatement et ne bloque pas SketchyBar.
    case "$NAME" in
        roadie.stage.*)
            parts=$(echo "$NAME" | awk -F. '{print $3, $4}')
            did=$(echo "$parts" | awk '{print $1}')
            sid=$(echo "$parts" | awk '{print $2}')
            (nohup "$ROADIE" stage "$sid" --desktop "$did" >/dev/null 2>&1 &) &
            ;;
        roadie.add.*)
            did="${NAME#roadie.add.}"
            next=$(roadie_stages_for "" "$did" | awk -F'|' 'BEGIN{m=0} {if ($1+0 > m) m = $1+0} END {print m+1}')
            (nohup "$ROADIE" stage create "$next" "stage $next" --desktop "$did" >/dev/null 2>&1 &) &
            ;;
        roadie.overflow)
            (nohup "$ROADIE" desktop focus next >/dev/null 2>&1 &) &
            ;;
    esac
    # Exit immédiat — bridge re-déclenchera le render via les events daemon.
    exit 0
fi

# --- Re-render ---------------------------------------------------------------

# SPEC-023 — lock atomique BSD-compatible (mkdir, pas flock qui est GNU only).
# Si une instance tourne déjà → skip (le render en cours capturera l'état final).
if ! mkdir "$LOCKDIR" 2>/dev/null; then
    # Stale lock cleanup : si > 5s, on suppose que l'instance précédente est morte.
    if [ -d "$LOCKDIR" ]; then
        AGE=$(($(date +%s) - $(stat -f %m "$LOCKDIR" 2>/dev/null || echo 0)))
        if [ "$AGE" -gt 5 ]; then
            rm -rf "$LOCKDIR" 2>/dev/null
            mkdir "$LOCKDIR" 2>/dev/null || exit 0
        else
            exit 0
        fi
    fi
fi
trap 'rm -rf "$LOCKDIR"' EXIT

# SPEC-023 — daemon_alive avec 1 retry court (200ms) pour éviter le faux-positif
# "down" pendant un IPC ralenti (TCC re-eval, rebuild en cours).
roadie_daemon_alive_retry() {
    if roadie_daemon_alive; then return 0; fi
    sleep 0.2
    roadie_daemon_alive
}

# Toujours nettoyer d'abord (fix bug daemon_down persistant).
remove_all_roadie_items

# Daemon down (avec retry) : afficher juste un indicateur, sortir.
if ! roadie_daemon_alive_retry; then
    sketchybar --add item roadie.daemon_down left \
               --set roadie.daemon_down label="🔴 roadie down — re-cocher Accessibilité" \
                                         icon.padding_left=8 \
                                         label.color=0xfff7768e \
                                         click_script="open 'x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility' &" \
               --subscribe roadie.daemon_down mouse.clicked
    track_item roadie.daemon_down
    exit 0
fi

# Lire les desktops récents.
DESKTOPS=$(roadie_desktops_recent "$MAX_DESKTOPS")
TOTAL=$("$ROADIE" desktop list 2>/dev/null | grep -cE '^[[:space:]]*[*]?[[:space:]]*[0-9]+')
SHOWN=$(echo "$DESKTOPS" | grep -c .)
OVERFLOW=$((TOTAL - SHOWN))

if [ -z "$DESKTOPS" ]; then
    sketchybar --add item roadie.empty left \
               --set roadie.empty label="(no desktops)" \
                                  icon.padding_left=8 \
                                  label.color=0xff7f7f7f
    exit 0
fi

ACTIVE_BG=""
INACTIVE_BG=$(get_stage_color_inactive)

# Pour chaque desktop affiché, créer header + cartes stages + bouton +.
echo "$DESKTOPS" | while IFS='|' read -r did label _ _ current; do
    [ -z "$did" ] && continue
    # Header desktop
    [ -z "$label" ] && label="Bureau $did"
    sketchybar --add item "roadie.desktop.$did" left \
               --set "roadie.desktop.$did" label="🏠 $label" \
                                            label.padding_left=10 \
                                            label.padding_right=4 \
                                            label.color=0xffffffff \
               --subscribe "roadie.desktop.$did" roadie_state_changed
    track_item "roadie.desktop.$did"

    # Stages de ce desktop. Si vide (cas où stage list ne sait pas répondre pour
    # un desktop pas courant), fallback : afficher au moins stage 1 par défaut.
    STAGES=$(roadie_stages_for "" "$did")
    [ -z "$STAGES" ] && STAGES="1|Stage 1|false|0"
    echo "$STAGES" | while IFS='|' read -r sid sname active wcount; do
        [ -z "$sid" ] && continue
        # Tronquer nom > 18 char
        [ ${#sname} -gt 18 ] && sname="${sname:0:15}…"
        suffix=""
        [ "$active" = "true" ] && suffix=" (actif)"
        bg_color="$INACTIVE_BG"
        if [ "$active" = "true" ]; then
            bg_color=$(get_stage_color_active "$sid")
        fi
        sketchybar --add item "roadie.stage.$did.$sid" left \
                   --set "roadie.stage.$did.$sid" label="$sname$suffix · $wcount" \
                                                   label.padding_left=8 \
                                                   label.padding_right=8 \
                                                   background.color="$bg_color" \
                                                   background.corner_radius=6 \
                                                   background.height=22 \
                                                   background.padding_left=2 \
                                                   background.padding_right=2 \
                                                   click_script="$0" \
                   --subscribe "roadie.stage.$did.$sid" roadie_state_changed mouse.clicked
        track_item "roadie.stage.$did.$sid"
    done

    # Bouton + (création stage)
    sketchybar --add item "roadie.add.$did" left \
               --set "roadie.add.$did" label="+" \
                                        label.padding_left=4 \
                                        label.padding_right=8 \
                                        label.color=0xff7f7f7f \
                                        click_script="$0" \
               --subscribe "roadie.add.$did" mouse.clicked
    track_item "roadie.add.$did"
done

# Item overflow (… +K) si plus de MAX_DESKTOPS desktops.
if [ "$OVERFLOW" -gt 0 ]; then
    sketchybar --add item roadie.overflow left \
               --set roadie.overflow label="… +$OVERFLOW" \
                                      label.padding_left=8 \
                                      label.padding_right=8 \
                                      label.color=0xff7f7f7f \
                                      click_script="$0" \
               --subscribe roadie.overflow mouse.clicked
    track_item roadie.overflow
fi

echo "$(date '+%H:%M:%S') render OK — $SHOWN desktops shown, $OVERFLOW overflow" >> "$LOG"
