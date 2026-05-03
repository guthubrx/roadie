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

# --- Click handler -----------------------------------------------------------

if [ "${SENDER:-}" = "mouse.clicked" ]; then
    NAME="${NAME:-}"
    case "$NAME" in
        roadie.stage.*)
            # roadie.stage.<desktop>.<stage> → switch
            parts=$(echo "$NAME" | awk -F. '{print $3, $4}')
            did=$(echo "$parts" | awk '{print $1}')
            sid=$(echo "$parts" | awk '{print $2}')
            "$ROADIE" stage "$sid" --desktop "$did" >/dev/null 2>&1 &
            ;;
        roadie.add.*)
            # roadie.add.<desktop> → create stage
            did="${NAME#roadie.add.}"
            # next_id = max stage_id + 1 dans ce desktop
            next=$(roadie_stages_for "" "$did" | awk -F'|' 'BEGIN{m=0} {if ($1+0 > m) m = $1+0} END {print m+1}')
            "$ROADIE" stage create "$next" "stage $next" --desktop "$did" >/dev/null 2>&1 &
            ;;
        roadie.overflow)
            "$ROADIE" desktop focus next >/dev/null 2>&1 &
            ;;
    esac
    # Le bridge va re-trigger via les events daemon, pas besoin de re-render ici.
    exit 0
fi

# --- Re-render ---------------------------------------------------------------

# Daemon down : afficher juste un indicateur, retirer les autres items.
if ! roadie_daemon_alive; then
    sketchybar --query bar 2>/dev/null | grep -oE 'roadie\.[a-z0-9.]+' | sort -u | while read -r item; do
        sketchybar --remove "$item" 2>/dev/null
    done
    sketchybar --add item roadie.daemon_down left \
               --set roadie.daemon_down label="🔴 roadie down" \
                                         icon.padding_left=8 \
                                         label.color=0xfff7768e
    exit 0
fi

# Remove tous les items roadie.* existants (clean state).
sketchybar --query default_items 2>/dev/null | grep -oE '"roadie\.[a-z0-9.]+"' | tr -d '"' | sort -u | while read -r item; do
    sketchybar --remove "$item" 2>/dev/null
done

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

    # Stages de ce desktop
    STAGES=$(roadie_stages_for "" "$did")
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
    done

    # Bouton + (création stage)
    sketchybar --add item "roadie.add.$did" left \
               --set "roadie.add.$did" label="+" \
                                        label.padding_left=4 \
                                        label.padding_right=8 \
                                        label.color=0xff7f7f7f \
                                        click_script="$0" \
               --subscribe "roadie.add.$did" mouse.clicked
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
fi

echo "$(date '+%H:%M:%S') render OK — $SHOWN desktops shown, $OVERFLOW overflow" >> "$LOG"
