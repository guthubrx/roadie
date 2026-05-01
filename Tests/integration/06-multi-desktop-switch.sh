#!/usr/bin/env bash
# Test d'intégration multi-desktop V2 — bascule via Mission Control (T048 + T076 + T091).
#
# Pré-requis :
# - 2+ desktops macOS configurés via Mission Control natif (F3 → bouton "+")
# - daemon roadied lancé avec multi_desktop.enabled=true
# - binaire roadie installé dans PATH
# - jq installé (Homebrew : brew install jq)
# - Réglages Système > Clavier > Raccourcis > Mission Control : "Switch to Desktop N" activés
#
# Couvre :
# - SC-001 latence transition < 200 ms
# - FR-009..FR-013 commandes desktop CLI
# - FR-014..FR-016 events --follow stream

set -euo pipefail

PASS=0
FAIL=0

assert() {
    local name="$1"; local cond="$2"
    if eval "$cond"; then echo "  ✓ $name"; PASS=$((PASS+1));
    else echo "  ✗ $name (cond: $cond)"; FAIL=$((FAIL+1)); fi
}

# --- T048 : transition latence ---
echo "[06] T048 — bascule + latence"

if ! command -v roadie >/dev/null 2>&1; then
    echo "  SKIP : binaire roadie non installé"
    exit 0
fi
if ! pgrep -x roadied >/dev/null; then
    echo "  SKIP : daemon roadied non lancé"
    exit 0
fi

INITIAL_UUID=$(roadie desktop current --json 2>/dev/null | jq -r '.uuid // empty')
if [ -z "$INITIAL_UUID" ]; then
    echo "  SKIP : multi_desktop disabled ou pas de current desktop"
    exit 0
fi
echo "  current uuid avant = $INITIAL_UUID"

# Switch via Ctrl+→ (keycode 124 right arrow)
T0=$(python3 -c 'import time; print(int(time.time()*1000))')
osascript -e 'tell application "System Events" to key code 124 using control down'
sleep 0.4   # laisser macOS faire la transition Mission Control
NEW_UUID=$(roadie desktop current --json 2>/dev/null | jq -r '.uuid // empty')
T1=$(python3 -c 'import time; print(int(time.time()*1000))')
LATENCY=$((T1 - T0 - 400))   # retire la pause de 400 ms

assert "uuid changé" "[ \"$NEW_UUID\" != \"$INITIAL_UUID\" ] && [ -n \"$NEW_UUID\" ]"
assert "latence_ms < 250 (avec marge sleep)" "[ $LATENCY -lt 250 ]"
echo "    latence mesurée : ${LATENCY} ms"

# Switch retour
osascript -e 'tell application "System Events" to key code 123 using control down'
sleep 0.4

# --- T076 : CLI desktop list/focus/label ---
echo "[06] T076 — CLI desktop list/focus/label"

# desktop list --json doit avoir current_uuid + desktops[]
LIST_JSON=$(roadie desktop list --json)
assert "list --json a current_uuid" "echo '$LIST_JSON' | jq -e '.current_uuid' >/dev/null"
assert "list --json a desktops[]" "echo '$LIST_JSON' | jq -e '.desktops | length > 0' >/dev/null"

# desktop focus next change current_uuid
PREV_CUR=$(roadie desktop current --json | jq -r '.uuid')
roadie desktop focus next >/dev/null
sleep 0.4
NEW_CUR=$(roadie desktop current --json | jq -r '.uuid')
assert "focus next change uuid" "[ \"$PREV_CUR\" != \"$NEW_CUR\" ]"

# desktop label "_test_audit_" puis focus _test_audit_
TEST_LABEL="_test_audit_$$"
roadie desktop label "$TEST_LABEL" >/dev/null
sleep 0.1
# Bascule ailleurs
roadie desktop focus next >/dev/null
sleep 0.4
# Retour via le label
roadie desktop focus "$TEST_LABEL" >/dev/null
sleep 0.4
LABEL_CUR=$(roadie desktop current --json | jq -r '.uuid')
assert "focus <label> revient bien sur $TEST_LABEL" "[ \"$LABEL_CUR\" = \"$NEW_CUR\" ]"
# Retire le label de test
roadie desktop label "" >/dev/null

# --- T091 : events --follow stream ---
echo "[06] T091 — events --follow"

EVT_LOG="/tmp/roadies-events-$$.log"
roadie events --follow --filter desktop_changed > "$EVT_LOG" &
EVT_PID=$!
sleep 0.3   # laisser le subscribe s'établir

# 5 switches
for _ in 1 2 3 4 5; do
    osascript -e 'tell application "System Events" to key code 124 using control down'
    sleep 0.3
done

# Stop le stream
kill "$EVT_PID" 2>/dev/null || true
wait "$EVT_PID" 2>/dev/null || true

EVT_COUNT=$(grep -c '"event":"desktop_changed"' "$EVT_LOG" 2>/dev/null || echo 0)
assert "5 events desktop_changed reçus (got $EVT_COUNT)" "[ \"$EVT_COUNT\" -ge 5 ]"
rm -f "$EVT_LOG"

# --- Bilan ---
echo ""
echo "[06] Bilan : $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
