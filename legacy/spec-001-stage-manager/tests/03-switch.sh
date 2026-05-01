#!/usr/bin/env bash
# tests/03-switch.sh — bascule (US1).
# Couvre : FR-001, FR-006, FR-009, FR-010, FR-012,
#          edge cases multi-fenetre / stage vide.
#
# Suit la fenetre cible par STAGE_TEST_MARKER pour eviter toute confusion
# avec les fenetres utilisateur (audit finding F1, fix v1.1).

set -e
source "$(dirname "$0")/helpers.sh"
require_binary
setup_stage_dir

echo ">>> Setup : ouvrir 2 fenetres Terminal marquees et les assigner aux stages 1 et 2"
open_terminal
"$STAGE_BIN" assign 1
assert_file_lines "$STAGE_DIR/1" 1

open_terminal
"$STAGE_BIN" assign 2
assert_file_lines "$STAGE_DIR/2" 1
assert_file_lines "$STAGE_DIR/1" 1

initial_test_windows=$(count_test_windows | tr -d ' ')
echo "    Setup OK : $initial_test_windows fenetres test ouvertes"

echo ">>> Scenario 1 : stage 1 → exactement 1 fenetre test minimisee (celle assignee a stage 2)"
"$STAGE_BIN" 1
sleep 0.5
min_count=$(count_test_minimized | tr -d ' ')
if [ "$min_count" != "1" ]; then
	echo "ASSERT FAIL: $min_count fenetres test minimisees, attendu 1" >&2
	exit 1
fi
assert_file_contains "$STAGE_DIR/current" "1"
echo "    OK : 1 fenetre test minimisee, current=1"

echo ">>> Scenario 2 : stage 2 → bascule symetrique"
"$STAGE_BIN" 2
sleep 0.5
min_count=$(count_test_minimized | tr -d ' ')
if [ "$min_count" != "1" ]; then
	echo "ASSERT FAIL: bascule inverse — $min_count test min, attendu 1" >&2
	exit 1
fi
assert_file_contains "$STAGE_DIR/current" "2"
echo "    OK : bascule symetrique"

echo ">>> Scenario 3 : invariant CGWindowID apres 4 bascules (FR-012 indirect)"
# Capture les CGWindowID des fenetres test avant les bascules.
before_ids=$(cat "$STAGE_DIR/1" "$STAGE_DIR/2" 2>/dev/null | awk -F$'\t' '{print $3}' | sort -n)

"$STAGE_BIN" 1 ; sleep 0.4
"$STAGE_BIN" 2 ; sleep 0.4
"$STAGE_BIN" 1 ; sleep 0.4
"$STAGE_BIN" 2 ; sleep 0.4

after_ids=$(cat "$STAGE_DIR/1" "$STAGE_DIR/2" 2>/dev/null | awk -F$'\t' '{print $3}' | sort -n)

if [ "$before_ids" != "$after_ids" ]; then
	echo "ASSERT FAIL: les CGWindowID des stages ont change apres 4 bascules" >&2
	echo "avant: $before_ids" >&2
	echo "apres: $after_ids" >&2
	exit 1
fi

# Verifier aussi que toutes les fenetres test sont toujours en vie.
final_test_windows=$(count_test_windows | tr -d ' ')
if [ "$final_test_windows" != "$initial_test_windows" ]; then
	echo "ASSERT FAIL: $final_test_windows fenetres test apres bascules, attendu $initial_test_windows" >&2
	exit 1
fi

echo "    OK : CGWindowID stables, fenetres preservees"

echo ">>> Scenario 4 : stage vide — vider stage 1, basculer dessus"
echo -n "" > "$STAGE_DIR/1"
"$STAGE_BIN" 1
sleep 0.5

# Apres scenario 3 : etat stage 2, donc fenetre stage 2 visible, fenetre stage 1 visible.
# Apres ce scenario : stage 1 vide → la fenetre stage 2 est minimisee → 1 test min,
# l'autre (qui etait stage 1 mais retiree) reste dans son etat actuel (visible).
# Donc 1 fenetre test minimisee (celle de stage 2), 1 test visible (orpheline).
min_count=$(count_test_minimized | tr -d ' ')
if [ "$min_count" -lt 1 ]; then
	echo "ASSERT FAIL: stage vide — au moins la fenetre du stage 2 doit etre minimisee ($min_count)" >&2
	exit 1
fi
assert_file_contains "$STAGE_DIR/current" "1"
echo "    OK : stage vide gere proprement"

echo "TEST 03-switch : SUCCES"
