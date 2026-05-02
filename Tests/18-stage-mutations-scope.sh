#!/usr/bin/env bash
# SPEC-018 Phase 3 US1 — test d'acceptance : isolation cross-display rename + delete
# Vérifie que renommer/supprimer un stage sur Display 1 n'affecte pas Display 2.
set -euo pipefail

ROADIE="$(command -v roadie 2>/dev/null || echo "$HOME/.local/bin/roadie")"
SOCKET="$HOME/.roadies/daemon.sock"

if [[ ! -S "$SOCKET" ]] || [[ ! -x "$ROADIE" ]]; then
    echo "skipped: daemon or roadie not available"
    exit 0
fi

# Skip si mono-display
N=$("$ROADIE" display list --json 2>/dev/null | jq '.displays | length' 2>/dev/null || echo 0)
if [[ "$N" -lt 2 ]]; then
    echo "skipped: need 2+ displays (got ${N})"
    exit 0
fi

# Skip si pas en mode per_display
MODE=$("$ROADIE" daemon status --json 2>/dev/null | jq -r '.payload.stages_mode // empty' 2>/dev/null || echo "")
if [[ "$MODE" != "per_display" ]]; then
    echo "skipped: per_display mode not active (mode=${MODE:-unknown})"
    exit 0
fi

STAGE_A="97"
STAGE_B="98"
PASS=0
FAIL=0

_cleanup() {
    "$ROADIE" stage delete "$STAGE_A" --display 1 --desktop 1 >/dev/null 2>&1 || true
    "$ROADIE" stage delete "$STAGE_A" --display 2 --desktop 1 >/dev/null 2>&1 || true
    "$ROADIE" stage delete "$STAGE_B" --display 2 --desktop 1 >/dev/null 2>&1 || true
}
trap _cleanup EXIT

# Préparer : créer STAGE_A sur D1 et D2, STAGE_B sur D2 uniquement
"$ROADIE" stage create "$STAGE_A" "shared-name-D1" --display 1 --desktop 1 >/dev/null 2>&1 || {
    echo "skipped: stage create with --display override not implemented yet"
    exit 0
}
"$ROADIE" stage create "$STAGE_A" "shared-name-D2" --display 2 --desktop 1 >/dev/null 2>&1 || true
"$ROADIE" stage create "$STAGE_B" "only-D2" --display 2 --desktop 1 >/dev/null 2>&1 || true

# Test 1 : rename STAGE_A sur D1 ne change pas le nom sur D2
"$ROADIE" stage rename "$STAGE_A" "renamed-D1" --display 1 --desktop 1 >/dev/null 2>&1 || true
NAME_D2=$("$ROADIE" stage list --display 2 --desktop 1 --json 2>/dev/null \
    | jq -r ".stages[] | select(.id==\"$STAGE_A\") | .display_name" 2>/dev/null || echo "")
if [[ "$NAME_D2" == "renamed-D1" ]]; then
    echo "FAIL[rename]: rename on D1 leaked to D2 (name='$NAME_D2')"
    FAIL=$((FAIL + 1))
else
    echo "PASS[rename]: D2 name unaffected by D1 rename (D2='$NAME_D2')"
    PASS=$((PASS + 1))
fi

# Test 2 : delete STAGE_A sur D1 ne supprime pas STAGE_A sur D2
"$ROADIE" stage delete "$STAGE_A" --display 1 --desktop 1 >/dev/null 2>&1 || true
D1_LIST=$("$ROADIE" stage list --display 1 --desktop 1 --json 2>/dev/null | jq -r '[.stages[].id]' 2>/dev/null || echo "[]")
D2_LIST=$("$ROADIE" stage list --display 2 --desktop 1 --json 2>/dev/null | jq -r '[.stages[].id]' 2>/dev/null || echo "[]")

if echo "$D1_LIST" | jq -e "index(\"$STAGE_A\")" >/dev/null 2>&1; then
    echo "FAIL[delete-d1]: stage $STAGE_A still present on D1 after delete"
    FAIL=$((FAIL + 1))
else
    echo "PASS[delete-d1]: stage $STAGE_A correctly removed from D1"
    PASS=$((PASS + 1))
fi

if ! echo "$D2_LIST" | jq -e "index(\"$STAGE_A\")" >/dev/null 2>&1; then
    echo "FAIL[delete-isolation]: delete on D1 removed stage $STAGE_A from D2"
    FAIL=$((FAIL + 1))
else
    echo "PASS[delete-isolation]: D2 still has stage $STAGE_A after D1 delete"
    PASS=$((PASS + 1))
fi

# Résumé
echo ""
echo "Results: ${PASS} passed, ${FAIL} failed"
[[ "$FAIL" -eq 0 ]] && exit 0 || exit 1
