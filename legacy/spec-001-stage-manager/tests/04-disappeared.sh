#!/usr/bin/env bash
# tests/04-disappeared.sh — tolerance aux fenetres disparues (US3).
# Couvre : FR-006, US3 acceptance scenarios 1 et 2.
# Utilise STAGE_TEST_MARKER pour cibler uniquement les fenetres du test.

set -e
source "$(dirname "$0")/helpers.sh"
require_binary
setup_stage_dir

echo ">>> Scenario 1 : 2 refs vivantes + 1 ref morte → bascule prune la morte"

open_terminal
"$STAGE_BIN" assign 1
open_terminal
"$STAGE_BIN" assign 1

assert_file_lines "$STAGE_DIR/1" 2

# Injecter une ligne morte (CGWindowID inexistant).
printf '99999\tcom.fictif.app\t999999999\n' >> "$STAGE_DIR/1"
assert_file_lines "$STAGE_DIR/1" 3

OUT_ERR=$("$STAGE_BIN" 1 2>&1 >/dev/null || true)

if ! echo "$OUT_ERR" | grep -q "999999999.*pruned"; then
	echo "ASSERT FAIL: pas de message de prune pour la ref morte" >&2
	echo "$OUT_ERR" >&2
	exit 1
fi

assert_file_lines "$STAGE_DIR/1" 2
if grep -q "999999999" "$STAGE_DIR/1"; then
	echo "ASSERT FAIL: ligne morte toujours presente apres prune" >&2
	cat "$STAGE_DIR/1" >&2
	exit 1
fi
echo "    OK : ref morte prunee, 2 vivantes preservees"

echo ">>> Scenario 2 : stage entierement mort → fichier vide apres bascule"

cat > "$STAGE_DIR/2" <<EOF
88888	com.fictif.un	888888881
77777	com.fictif.deux	777777772
EOF

OUT_ERR=$("$STAGE_BIN" 2 2>&1 >/dev/null || true)
prune_count=$(echo "$OUT_ERR" | grep -c "no longer exists, pruned" || true)
if [ "$prune_count" -lt 2 ]; then
	echo "ASSERT FAIL: $prune_count messages de prune, attendu au moins 2" >&2
	echo "$OUT_ERR" >&2
	exit 1
fi

assert_file_empty_or_absent "$STAGE_DIR/2"
assert_file_contains "$STAGE_DIR/current" "2"
echo "    OK : stage 2 vide apres prune, current=2"

echo "TEST 04-disappeared : SUCCES"
