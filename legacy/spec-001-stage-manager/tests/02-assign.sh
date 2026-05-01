#!/usr/bin/env bash
# tests/02-assign.sh — assignation de la fenetre frontmost (US2).
# Couvre : FR-002, FR-003, FR-004, FR-005, US2 acceptance scenarios 1, 2, 3.

set -e
source "$(dirname "$0")/helpers.sh"
require_binary
setup_stage_dir

echo ">>> Scenario 1 : ouvrir Terminal au premier plan, assign 1, verifier le fichier"
open_terminal
"$STAGE_BIN" assign 1
assert_file_lines "$STAGE_DIR/1" 1
line=$(cat "$STAGE_DIR/1")
if ! echo "$line" | awk -F$'\t' '{ exit !($1 ~ /^[0-9]+$/ && $2 == "com.apple.Terminal" && $3 ~ /^[0-9]+$/) }'; then
	echo "ASSERT FAIL: format de ligne invalide : $line" >&2
	exit 1
fi
echo "    OK : ligne valide ecrite — $line"

echo ">>> Scenario 2 : re-assignation de la meme fenetre au stage 2"
"$STAGE_BIN" assign 2
assert_file_empty_or_absent "$STAGE_DIR/1"
assert_file_lines "$STAGE_DIR/2" 1
line2=$(cat "$STAGE_DIR/2")
if [ "$line" != "$line2" ]; then
	echo "ASSERT FAIL: la fenetre n'est pas la meme apres re-assign. avant=$line apres=$line2" >&2
	exit 1
fi
echo "    OK : fenetre deplacee de stage 1 vers stage 2 atomiquement"

echo ">>> Scenario 3 : robustesse face a un focus non exploitable"
before=$(cat "$STAGE_DIR/2")
osascript -e 'tell application "Finder" to activate' >/dev/null
sleep 0.4
"$STAGE_BIN" assign 1 || true
after_2=$(cat "$STAGE_DIR/2")
if [ -f "$STAGE_DIR/1" ] && [ -s "$STAGE_DIR/1" ]; then
	echo "    INFO : Finder avait une fenetre focalisee, assign reussi — etat coherent"
	if [ "$after_2" != "$before" ]; then
		echo "ASSERT FAIL: stage 2 modifie alors que c'est une assignation distincte" >&2
		exit 1
	fi
else
	echo "    INFO : pas de fenetre focalisee dans Finder, assign a refuse (FR-008)"
	if [ "$after_2" != "$before" ]; then
		echo "ASSERT FAIL: stage 2 modifie alors que l'assign a echoue" >&2
		exit 1
	fi
fi
echo "    OK : robustesse OK quel que soit le cas"

echo "TEST 02-assign : SUCCES"
