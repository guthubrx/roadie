#!/usr/bin/env bash
# Test d'intégration SPEC-004 — Loaded : daemon avec modules + osax actifs.
#
# Pré-requis :
#   - SIP partial off (csrutil enable --without fs --without nvram)
#   - roadied.osax installé dans /Library/ScriptingAdditions/ et chargé dans Dock
#   - dylibs FX déposés dans ~/.local/lib/roadie/

set -euo pipefail

PASS=0
FAIL=0
assert() {
    local name="$1"; local cond="$2"
    if eval "$cond"; then echo "  ✓ $name"; PASS=$((PASS+1));
    else echo "  ✗ $name (cond: $cond)"; FAIL=$((FAIL+1)); fi
}

if ! command -v roadie >/dev/null 2>&1; then
    echo "  SKIP : binaire roadie non installé"
    exit 0
fi
if ! pgrep -x roadied >/dev/null; then
    echo "  SKIP : daemon roadied non lancé"
    exit 0
fi

echo "[12] SPEC-004 loaded — modules + osax"

# 1) osax doit être présente et chargée par Dock.
assert "/Library/ScriptingAdditions/roadied.osax existe" \
    "[ -d /Library/ScriptingAdditions/roadied.osax ]"
assert "socket osax /var/tmp/roadied-osax.sock existe" \
    "[ -S /var/tmp/roadied-osax.sock ]"

# 2) Heartbeat noop : envoyer une ligne JSON sur la socket et lire la réponse.
if command -v nc >/dev/null 2>&1 && [ -S /var/tmp/roadied-osax.sock ]; then
    REPLY=$(echo '{"cmd":"noop"}' | nc -U -w 2 /var/tmp/roadied-osax.sock | head -1)
    assert "osax noop répond OK (reply='$REPLY')" \
        "echo '$REPLY' | grep -q '\"ok\"'"
fi

# 3) fx status doit lister au moins un module si dylibs déposés.
STATUS=$(roadie fx status 2>/dev/null)
DYLIB_COUNT=$(ls "$HOME/.local/lib/roadie/"*.dylib 2>/dev/null | wc -l | tr -d ' ')
if [ "$DYLIB_COUNT" -gt 0 ]; then
    assert "fx status liste au moins un module" \
        "echo '$STATUS' | grep -q '\"name\"'"
fi

# 4) sip dans status reflète l'état réel.
SIP=$(echo "$STATUS" | python3 -c 'import json,sys; print(json.load(sys.stdin)["sip"])' 2>/dev/null || echo "unknown")
echo "  ℹ SIP state reporté par daemon : $SIP"

echo ""
echo "[12] Bilan : $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
