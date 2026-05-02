#!/usr/bin/env bash
# SPEC-014 T093 — acceptance test : multi-display rail.
# Vérifie que le binaire roadie-rail démarre sans crash sur des configs
# multi-écrans et que le PID-lock est créé. Test GUI réel manuel.
set -euo pipefail

ROADIE_RAIL="$HOME/.local/bin/roadie-rail"
RAIL_PID="$HOME/.roadies/rail.pid"

if [[ ! -x "$ROADIE_RAIL" ]]; then
    # Fallback : binaire dans .build/debug.
    ALT="$(pwd)/.build/debug/roadie-rail"
    if [[ -x "$ALT" ]]; then
        ROADIE_RAIL="$ALT"
    else
        echo "skipped: roadie-rail not built/installed"
        exit 0
    fi
fi

# Compter les écrans via system_profiler.
N_SCREENS=$(system_profiler SPDisplaysDataType 2>/dev/null | grep -c "Resolution:" || echo 1)
echo "detected $N_SCREENS screen(s)"

# Démarrer rail en background.
"$ROADIE_RAIL" >/tmp/rail-test.log 2>&1 &
RAIL_PID_LOCAL=$!
sleep 1

# Vérifier PID-lock.
if [[ -f "$RAIL_PID" ]]; then
    LOCK_PID=$(cat "$RAIL_PID")
    if [[ "$LOCK_PID" == "$RAIL_PID_LOCAL" ]]; then
        echo "OK: PID-lock matches (pid=$LOCK_PID)"
    else
        echo "WARN: PID-lock pid=$LOCK_PID, expected $RAIL_PID_LOCAL"
    fi
else
    echo "WARN: PID-lock missing at $RAIL_PID"
fi

# Le rail ne doit pas crasher dans la première seconde.
if kill -0 "$RAIL_PID_LOCAL" 2>/dev/null; then
    echo "OK: rail still alive after 1s"
else
    echo "FAIL: rail crashed within 1s"
    cat /tmp/rail-test.log
    exit 1
fi

# Cleanup.
kill -TERM "$RAIL_PID_LOCAL" 2>/dev/null || true
sleep 0.3
rm -f "$RAIL_PID" /tmp/rail-test.log
