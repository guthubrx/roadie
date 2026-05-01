#!/usr/bin/env bash
# Test d'intégration SPEC-004 — Vanilla : daemon sans modules ni osax doit
# se comporter exactement comme SPEC-001+002+003.

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

echo "[11] SPEC-004 vanilla — daemon sans modules"

# fx status doit répondre, sip détecté, modules vide ou liste minimale.
STATUS=$(roadie fx status 2>/dev/null)
assert "fx status retourne du JSON" "echo '$STATUS' | grep -q '\"sip\"'"
assert "fx status contient le champ modules" "echo '$STATUS' | grep -q '\"modules\"'"

# Le daemon ne doit avoir aucun symbole CGS d'écriture linké statiquement.
DAEMON_BIN="$(command -v roadied || true)"
if [ -z "$DAEMON_BIN" ] && [ -e "$HOME/.local/bin/roadied" ]; then
    DAEMON_BIN="$(readlink -f "$HOME/.local/bin/roadied" 2>/dev/null || readlink "$HOME/.local/bin/roadied")"
fi
if [ -n "$DAEMON_BIN" ] && [ -e "$DAEMON_BIN" ]; then
    SYMBOLS=$(nm "$DAEMON_BIN" 2>/dev/null | grep -E 'CGSSetWindowAlpha|CGSSetWindowShadow|CGSSetWindowBlur|CGSSetWindowTransform|CGSAddWindowsToSpaces|CGSSetStickyWindow' | wc -l | tr -d ' ')
    assert "SC-007 : 0 symbole CGS d'écriture linké statiquement (got $SYMBOLS)" "[ \"$SYMBOLS\" = \"0\" ]"
fi

# Les commandes V1/V2 doivent toujours répondre.
assert "windows list répond" "roadie windows list >/dev/null 2>&1"
assert "stage list répond" "roadie stage list >/dev/null 2>&1"

echo ""
echo "[11] Bilan : $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
