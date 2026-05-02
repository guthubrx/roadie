#!/usr/bin/env bash
# SPEC-014 T055 — acceptance test : drag-drop wid vers stage cible via IPC.
# Skip si daemon down. La partie GUI drag est testée manuellement.
set -euo pipefail

ROADIE="$(command -v roadie || echo "$HOME/.local/bin/roadie")"
SOCKET="$HOME/.roadies/daemon.sock"

if [[ ! -S "$SOCKET" ]] || [[ ! -x "$ROADIE" ]]; then
    echo "skipped: daemon or roadie not available"
    exit 0
fi

# Récupérer une wid existante.
WID=$("$ROADIE" windows list 2>/dev/null | jq -r '.windows[0].id // empty')
if [[ -z "$WID" ]]; then
    echo "skipped: no windows tracked"
    exit 0
fi

# Stage cible : crée stage "99" pour ce test (lazy stage creation).
TARGET="99"

echo "assigning wid=$WID to stage=$TARGET via IPC"
START=$(python3 -c 'import time; print(int(time.time()*1000))')

# Test directement via socket (le rail enverra le même format).
RESPONSE=$(echo "{\"cmd\":\"stage.assign\",\"args\":{\"stage_id\":\"$TARGET\",\"wid\":\"$WID\"}}" | nc -U "$SOCKET" -w 2)

END=$(python3 -c 'import time; print(int(time.time()*1000))')
LATENCY=$((END - START))

OK=$(echo "$RESPONSE" | jq -r '.status // empty')
if [[ "$OK" != "ok" ]]; then
    echo "FAIL: stage.assign response=$RESPONSE"
    exit 1
fi

# SC-003 : < 300 ms.
if (( LATENCY > 300 )); then
    echo "WARN: drag-drop latency ${LATENCY}ms (SC-003 budget 300ms)"
else
    echo "OK: stage.assign succeeded in ${LATENCY}ms"
fi

# Cleanup : supprimer le stage de test.
"$ROADIE" stage delete "$TARGET" >/dev/null 2>&1 || true
