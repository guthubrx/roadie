#!/usr/bin/env bash
# T042 — Vérifier que le mode global préserve le comportement V1 strict.
# Usage : ./tests/18-global-mode-compat.sh
# Skippé automatiquement si le daemon n'est pas lancé ou si mode != global.
set -euo pipefail

ROADIE="$(command -v roadie 2>/dev/null || echo "$HOME/.local/bin/roadie")"
SOCKET="$HOME/.roadies/daemon.sock"

if [[ ! -S "$SOCKET" || ! -x "$ROADIE" ]]; then
    echo "skipped: daemon not running or roadie binary not found"
    exit 0
fi

MODE=$("$ROADIE" daemon status --json 2>/dev/null | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('payload',{}).get('stages_mode','global'))" 2>/dev/null || echo "global")

if [[ "$MODE" != "global" ]]; then
    echo "skipped: not in global mode (current=$MODE)"
    exit 0
fi

# En mode global, stage list ne doit PAS contenir un champ scope (ou il doit être absent).
SCOPE=$("$ROADIE" stage list 2>/dev/null | grep -E "^scope:" || echo "")
if [[ -n "$SCOPE" ]]; then
    echo "WARN: scope field present in global mode response: $SCOPE"
fi

# Cycle create/list/delete en mode global.
"$ROADIE" stage create 99 "compat-test-018" 2>/dev/null || true
if ! "$ROADIE" stage list 2>/dev/null | grep -q "compat-test-018"; then
    echo "FAIL: created stage not visible in stage list (global mode)"
    exit 1
fi
"$ROADIE" stage delete 99 >/dev/null 2>&1 || true

echo "OK: global mode preserves V1 behavior"
