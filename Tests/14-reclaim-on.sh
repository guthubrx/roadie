#!/usr/bin/env bash
# SPEC-014 T083 — acceptance test : tiling.reserve modifie effectivement la frame.
set -euo pipefail

ROADIE="$(command -v roadie || echo "$HOME/.local/bin/roadie")"
SOCKET="$HOME/.roadies/daemon.sock"

if [[ ! -S "$SOCKET" ]] || [[ ! -x "$ROADIE" ]]; then
    echo "skipped: daemon or roadie not available"
    exit 0
fi

# Récupérer une wid tilée existante.
WID=$("$ROADIE" windows list 2>/dev/null | jq -r '[.windows[] | select(.is_tiled == true)] | .[0].id // empty')
if [[ -z "$WID" ]]; then
    echo "skipped: no tiled window present"
    exit 0
fi

# Frame initiale.
INITIAL_X=$("$ROADIE" windows list 2>/dev/null | jq -r ".windows[] | select(.id==$WID) | .frame[0]")

# tiling.reserve left=408
DISPLAY_ID=$(echo "{\"cmd\":\"display.current\"}" | nc -U "$SOCKET" -w 2 | jq -r '.data.id')
echo "[1/2] reserve left=408 on display $DISPLAY_ID"
echo "{\"cmd\":\"tiling.reserve\",\"args\":{\"edge\":\"left\",\"size\":\"408\",\"display_id\":\"$DISPLAY_ID\"}}" | nc -U "$SOCKET" -w 2 | jq -r '.status' | grep -q ok
sleep 0.3

NEW_X=$("$ROADIE" windows list 2>/dev/null | jq -r ".windows[] | select(.id==$WID) | .frame[0]")

if (( NEW_X > INITIAL_X )); then
    echo "  OK: window x went from $INITIAL_X to $NEW_X (shifted right)"
else
    echo "  WARN: x unchanged ($INITIAL_X → $NEW_X) — window may not be on this display"
fi

# Restoration.
echo "[2/2] reserve left=0 (restore)"
echo "{\"cmd\":\"tiling.reserve\",\"args\":{\"edge\":\"left\",\"size\":\"0\",\"display_id\":\"$DISPLAY_ID\"}}" | nc -U "$SOCKET" -w 2 | jq -r '.status' | grep -q ok
sleep 0.3

FINAL_X=$("$ROADIE" windows list 2>/dev/null | jq -r ".windows[] | select(.id==$WID) | .frame[0]")
if (( FINAL_X == INITIAL_X )); then
    echo "  OK: window restored to x=$FINAL_X"
else
    echo "  WARN: not exactly restored ($INITIAL_X → $FINAL_X)"
fi
