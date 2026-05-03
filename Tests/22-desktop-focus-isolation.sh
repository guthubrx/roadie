#!/usr/bin/env bash
# SPEC-022 T050 — Acceptance test: desktop.focus isolation per display.
# Vérifie que `roadie desktop focus 5 --display 1` ne change pas le desktop courant
# du display 2 (non-régression SPEC-013).
#
# Prérequis : 2 displays connectés, daemon roadied tournant, roadie CLI disponible.
# Usage     : ./Tests/22-desktop-focus-isolation.sh
# Résultat  : EXIT 0 si le desktop du display 2 est inchangé.
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
# 1. Vérifier 2 displays disponibles
# -------------------------------------------------------------------
DISPLAY_COUNT=$("$ROADIE" display list --json 2>/dev/null | python3 -c "import sys,json; d=json.load(sys.stdin); print(len(d.get('displays',[])))" 2>/dev/null || echo 0)
if [[ "$DISPLAY_COUNT" -lt 2 ]]; then
    log_skip "Moins de 2 displays détectés ($DISPLAY_COUNT) — test non exécutable."
    exit 0
fi

# -------------------------------------------------------------------
# 2. Lire le desktop courant du display 2 avant focus
# -------------------------------------------------------------------
BEFORE_D2=$("$ROADIE" desktop current --display 2 2>/dev/null | tr -d '[:space:]' || echo '')

if [[ -z "$BEFORE_D2" ]]; then
    log_skip "Impossible de lire le desktop courant du display 2."
    exit 0
fi

# -------------------------------------------------------------------
# 3. Focus desktop 5 sur display 1 (avec cursor sur display 1)
# -------------------------------------------------------------------
"$ROADIE" desktop focus 5 --display 1 2>/dev/null || true
sleep 0.3

# -------------------------------------------------------------------
# 4. Vérifier que le desktop du display 2 n'a pas changé
# -------------------------------------------------------------------
AFTER_D2=$("$ROADIE" desktop current --display 2 2>/dev/null | tr -d '[:space:]' || echo '')

if [[ "$BEFORE_D2" == "$AFTER_D2" ]]; then
    log_pass "SC-005: Desktop display 2 inchangé après focus display 1 (était $BEFORE_D2, est $AFTER_D2)."
else
    log_fail "SC-005: Desktop display 2 a changé: avant=$BEFORE_D2, après=$AFTER_D2."
fi

# -------------------------------------------------------------------
# 5. Vérifier que le display 1 est bien sur desktop 5
# -------------------------------------------------------------------
AFTER_D1=$("$ROADIE" desktop current --display 1 2>/dev/null | tr -d '[:space:]' || echo '')
if [[ "$AFTER_D1" == "5" ]]; then
    log_pass "Display 1 est sur desktop 5 après focus."
else
    log_fail "Display 1 attendu desktop 5, obtenu '${AFTER_D1}'."
fi

# -------------------------------------------------------------------
# 6. Résultat
# -------------------------------------------------------------------
echo ""
echo "PASS: $PASS  FAIL: $FAIL"
[[ "$FAIL" -eq 0 ]] && exit 0 || exit 1
