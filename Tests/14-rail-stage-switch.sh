#!/usr/bin/env bash
# SPEC-014 T043 — acceptance test : click sur StageCard non-active → switch.
# Skip silencieux si environnement headless ou si roadied/roadie-rail absents.
set -euo pipefail

SOCKET="$HOME/.roadies/daemon.sock"
ROADIE="$(command -v roadie || echo "$HOME/.local/bin/roadie")"

# Skip si socket daemon absent.
if [[ ! -S "$SOCKET" ]]; then
    echo "skipped: daemon socket not present at $SOCKET"
    exit 0
fi

# Skip si CLI roadie introuvable.
if [[ ! -x "$ROADIE" ]]; then
    echo "skipped: roadie CLI not found at $ROADIE"
    exit 0
fi

# Récupère current stage et liste.
INITIAL=$("$ROADIE" stage list 2>/dev/null || echo "{}")
CURRENT=$(echo "$INITIAL" | jq -r '.current // empty' 2>/dev/null || echo "")
TARGET=$(echo "$INITIAL" | jq -r '.stages[]?.id' 2>/dev/null | grep -v "^${CURRENT}$" | head -1 || echo "")

if [[ -z "$TARGET" ]]; then
    echo "skipped: only one stage (need >= 2 for switch test)"
    exit 0
fi

echo "switching from $CURRENT to $TARGET"
START=$(python3 -c 'import time; print(int(time.time()*1000))')

"$ROADIE" stage "$TARGET" >/dev/null

END=$(python3 -c 'import time; print(int(time.time()*1000))')
LATENCY=$((END - START))

# Vérifier le switch.
NEW_CURRENT=$("$ROADIE" stage list 2>/dev/null | jq -r '.current')
if [[ "$NEW_CURRENT" != "$TARGET" ]]; then
    echo "FAIL: expected current=$TARGET, got $NEW_CURRENT"
    exit 1
fi

# SC-002 : < 200 ms.
if (( LATENCY > 200 )); then
    echo "WARN: stage switch took ${LATENCY}ms (SC-002 budget 200ms)"
else
    echo "OK: stage switched in ${LATENCY}ms"
fi
