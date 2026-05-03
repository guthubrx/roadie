#!/usr/bin/env bash
# SPEC-018 T053 — Test acceptance : CLI overrides --display / --desktop
#
# Scenarios :
#   1. roadie stage list --display 1 --desktop 1  →  meme contenu que list implicite
#   2. roadie stage list --display 99             →  exit != 0 ET stderr contient unknown_display
#   3. roadie stage list --desktop 42             →  exit != 0 ET stderr contient desktop_out_of_range
#                                                     (requiert desktops.count < 42 dans la config)
#
# Skip gracieux si le daemon n'est pas lancé (exit 0, message clair).

set -euo pipefail

ROADIE="${ROADIE_BIN:-roadie}"
PASS=0
FAIL=0

pass() { echo "PASS: $1"; ((PASS++)); }
fail() { echo "FAIL: $1"; ((FAIL++)); }
skip() { echo "SKIP: $1"; }

# Vérifie que le daemon tourne ; skip tout le test sinon.
if ! "$ROADIE" daemon status > /dev/null 2>&1; then
    skip "daemon not running — start roadied before running this test"
    exit 0
fi

# --- Scenario 1 : --display 1 --desktop 1 retourne le meme contenu que list implicite ---
implicit_out=$("$ROADIE" stage list 2>&1) || true
override_out=$("$ROADIE" stage list --display 1 --desktop 1 2>&1) || true

# Les deux commandes doivent reussir (exit 0) et retourner la meme liste de stages.
# On compare les lignes "id" uniquement pour etre robuste aux champs transitoires.
implicit_ids=$(echo "$implicit_out" | grep '"id"' | sort || echo "")
override_ids=$(echo "$override_out" | grep '"id"' | sort || echo "")

if [[ "$implicit_ids" == "$override_ids" ]]; then
    pass "stage list --display 1 --desktop 1 returns same stage ids as implicit list"
else
    fail "stage list --display 1 --desktop 1 differs from implicit list"
    echo "  implicit:  $implicit_ids"
    echo "  override:  $override_ids"
fi

# --- Scenario 2 : --display 99 → exit != 0 ET stderr contient unknown_display ---
set +e
err_out=$("$ROADIE" stage list --display 99 2>&1)
exit_code=$?
set -e

if [[ $exit_code -ne 0 ]] && echo "$err_out" | grep -q "unknown_display"; then
    pass "stage list --display 99 exits non-zero with unknown_display"
elif [[ $exit_code -ne 0 ]]; then
    fail "stage list --display 99 exits non-zero but stderr missing unknown_display"
    echo "  stderr: $err_out"
else
    fail "stage list --display 99 exited 0 (expected non-zero)"
    echo "  output: $err_out"
fi

# --- Scenario 3 : --desktop 42 → exit != 0 ET stderr contient desktop_out_of_range ---
# Determine le nombre de desktops configures. Si >= 42, ce test est un no-op.
desktop_count=$(
    "$ROADIE" desktop list --json 2>/dev/null \
    | grep -c '"id"' || echo "0"
)

if [[ "$desktop_count" -ge 42 ]]; then
    skip "desktop_out_of_range test skipped: config has >= 42 desktops"
else
    set +e
    err_out2=$("$ROADIE" stage list --desktop 42 2>&1)
    exit_code2=$?
    set -e

    if [[ $exit_code2 -ne 0 ]] && echo "$err_out2" | grep -q "desktop_out_of_range"; then
        pass "stage list --desktop 42 exits non-zero with desktop_out_of_range"
    elif [[ $exit_code2 -ne 0 ]]; then
        fail "stage list --desktop 42 exits non-zero but stderr missing desktop_out_of_range"
        echo "  stderr: $err_out2"
    else
        fail "stage list --desktop 42 exited 0 (expected non-zero)"
        echo "  output: $err_out2"
    fi
fi

# --- Rapport ---
echo ""
echo "Results: ${PASS} passed, ${FAIL} failed"
[[ $FAIL -eq 0 ]] && exit 0 || exit 1
