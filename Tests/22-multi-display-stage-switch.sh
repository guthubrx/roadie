#!/usr/bin/env bash
# SPEC-022 T028 — Acceptance test: multi-display stage switch isolation.
# Vérifie que switcher sur stage 3 du display 2 ne change pas les wids du display 1.
#
# Prérequis : 2 displays connectés, daemon roadied tournant, roadie CLI disponible.
# Usage     : ./Tests/22-multi-display-stage-switch.sh
# Résultat  : EXIT 0 si les bounds des wids du display 1 sont inchangées après switch.
#
# NOTE : ce test nécessite un setup 2-display physique — non exécutable en CI.
set -euo pipefail

ROADIE="${ROADIE:-roadie}"
PASS=0
FAIL=0

log_pass() { echo "PASS: $*"; PASS=$((PASS+1)); }
log_fail() { echo "FAIL: $*"; FAIL=$((FAIL+1)); }
log_skip() { echo "SKIP: $*"; }

# -------------------------------------------------------------------
# 1. Vérifier la disponibilité de 2 displays
# -------------------------------------------------------------------
DISPLAY_COUNT=$("$ROADIE" display list --json 2>/dev/null | python3 -c "import sys,json; d=json.load(sys.stdin); print(len(d.get('displays',[])))" 2>/dev/null || echo 0)
if [[ "$DISPLAY_COUNT" -lt 2 ]]; then
    log_skip "Moins de 2 displays détectés ($DISPLAY_COUNT) — test non exécutable."
    exit 0
fi

# -------------------------------------------------------------------
# 2. Capturer les bounds du display 1 avant le switch
# -------------------------------------------------------------------
BEFORE_JSON=$(python3 -c "
import subprocess, json
result = subprocess.run(['$ROADIE', 'windows', 'list', '--display', '1', '--json'],
                       capture_output=True, text=True)
data = json.loads(result.stdout) if result.returncode == 0 else {}
bounds = {str(w['wid']): w.get('frame', {}) for w in data.get('windows', [])}
print(json.dumps(bounds))
" 2>/dev/null || echo '{}')

# -------------------------------------------------------------------
# 3. Switcher sur stage 3 du display 2
# -------------------------------------------------------------------
"$ROADIE" stage 3 --display 2 2>/dev/null || true
sleep 0.3

# -------------------------------------------------------------------
# 4. Capturer les bounds du display 1 après le switch
# -------------------------------------------------------------------
AFTER_JSON=$(python3 -c "
import subprocess, json
result = subprocess.run(['$ROADIE', 'windows', 'list', '--display', '1', '--json'],
                       capture_output=True, text=True)
data = json.loads(result.stdout) if result.returncode == 0 else {}
bounds = {str(w['wid']): w.get('frame', {}) for w in data.get('windows', [])}
print(json.dumps(bounds))
" 2>/dev/null || echo '{}')

# -------------------------------------------------------------------
# 5. Comparer : aucune wid du display 1 ne doit avoir bougé
# -------------------------------------------------------------------
CHANGED=$(python3 -c "
import json, sys
before = json.loads('''$BEFORE_JSON''')
after  = json.loads('''$AFTER_JSON''')
changed = [wid for wid in before if before.get(wid) != after.get(wid)]
print(','.join(changed))
" 2>/dev/null || echo '')

if [[ -z "$CHANGED" ]]; then
    log_pass "SC-001: Aucune wid du display 1 n'a changé après switch stage 3 display 2."
else
    log_fail "SC-001: Wids display 1 ont bougé après switch display 2: $CHANGED"
fi

# -------------------------------------------------------------------
# 6. Vérifier que le stage actif du display 2 est bien 3
# -------------------------------------------------------------------
ACTIVE_D2=$("$ROADIE" stage list --display 2 --json 2>/dev/null \
    | python3 -c "import sys,json; d=json.load(sys.stdin); print(next((s['id'] for s in d.get('stages',[]) if s.get('is_active')), ''))" 2>/dev/null || echo '')
if [[ "$ACTIVE_D2" == "3" ]]; then
    log_pass "Display 2 stage actif = 3 après switch."
else
    log_fail "Display 2 stage actif attendu 3, obtenu '${ACTIVE_D2}'."
fi

# -------------------------------------------------------------------
# 7. Résultat
# -------------------------------------------------------------------
echo ""
echo "PASS: $PASS  FAIL: $FAIL"
[[ "$FAIL" -eq 0 ]] && exit 0 || exit 1
