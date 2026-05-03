#!/usr/bin/env bash
# SPEC-023 — Helpers couleurs : conversion hex + parsing TOML stage_overrides.

ROADIES_TOML="${ROADIES_TOML:-$HOME/.config/roadies/roadies.toml}"

# Convertit "#RRGGBB" ou "#RRGGBBAA" en "0xAARRGGBB" (format SketchyBar).
hex_to_sketchybar() {
    local hex="${1#\#}"
    case ${#hex} in
        6) printf "0xff%s\n" "$hex" ;;
        8) printf "0x%s%s\n" "${hex:6:2}" "${hex:0:6}" ;;
        *) printf "0xff7f7f7f\n" ;;  # fallback gris
    esac
}

# Récupère la couleur active d'un stage depuis [[fx.rail.preview.stage_overrides]].
# Fallback sur la couleur active globale [fx.rail.preview].border_color, sinon vert système.
get_stage_color_active() {
    local sid="$1"
    local found
    found=$(awk -v sid="$sid" '
        /^\[\[fx\.rail\.preview\.stage_overrides\]\]/ { in_block = 1; cur = ""; col = ""; next }
        in_block && /^stage_id/ { gsub(/[ "]/, "", $3); cur = $3; next }
        in_block && /^active_color/ {
            gsub(/[ "]/, "", $3); col = $3
            if (cur == sid) { print col; exit }
        }
        /^\[/ && !/^\[\[fx\.rail\.preview\.stage_overrides\]\]/ { in_block = 0 }
    ' "$ROADIES_TOML" 2>/dev/null)
    if [ -z "$found" ]; then
        # fallback global border_color
        found=$(awk '
            /^\[fx\.rail\.preview\]/ { in_block = 1; next }
            in_block && /^border_color\s*=/ { gsub(/[ "]/, "", $3); print $3; exit }
            /^\[/ && !/^\[fx\.rail\.preview\]/ { in_block = 0 }
        ' "$ROADIES_TOML" 2>/dev/null)
    fi
    [ -z "$found" ] && found="#34C759"  # vert système Apple par défaut
    hex_to_sketchybar "$found"
}

# Couleur inactive : [fx.rail.preview].border_color_inactive, sinon gris.
get_stage_color_inactive() {
    local found
    found=$(awk '
        /^\[fx\.rail\.preview\]/ { in_block = 1; next }
        in_block && /^border_color_inactive\s*=/ { gsub(/[ "]/, "", $3); print $3; exit }
        /^\[/ && !/^\[fx\.rail\.preview\]/ { in_block = 0 }
    ' "$ROADIES_TOML" 2>/dev/null)
    [ -z "$found" ] && found="#7F7F7F33"
    hex_to_sketchybar "$found"
}
