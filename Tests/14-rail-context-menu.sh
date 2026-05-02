#!/usr/bin/env bash
# SPEC-014 T075 — acceptance test : menu contextuel rename/add/delete via IPC.
set -euo pipefail

ROADIE="$(command -v roadie || echo "$HOME/.local/bin/roadie")"
SOCKET="$HOME/.roadies/daemon.sock"

if [[ ! -S "$SOCKET" ]] || [[ ! -x "$ROADIE" ]]; then
    echo "skipped: daemon or roadie not available"
    exit 0
fi

# Crée stage de test "test", renomme, supprime.
TEST_ID="test"
NEW_NAME="Renamed-Stage"

# Création (lazy via assign — ou stage.create direct).
echo "[1/3] create stage $TEST_ID"
echo "{\"cmd\":\"stage.create\",\"args\":{\"stage_id\":\"$TEST_ID\",\"display_name\":\"Initial\"}}" | nc -U "$SOCKET" -w 2 | jq -r '.status' | grep -q ok

# Rename via IPC stage.rename.
echo "[2/3] rename stage $TEST_ID → $NEW_NAME"
RENAME_RESP=$(echo "{\"cmd\":\"stage.rename\",\"args\":{\"stage_id\":\"$TEST_ID\",\"new_name\":\"$NEW_NAME\"}}" | nc -U "$SOCKET" -w 2)
RENAMED=$(echo "$RENAME_RESP" | jq -r '.data.new_name // empty')
if [[ "$RENAMED" != "$NEW_NAME" ]]; then
    echo "FAIL: rename response: $RENAME_RESP"
    exit 1
fi
echo "  OK"

# Vérifie que stage.list reflète le nouveau nom.
ACTUAL=$("$ROADIE" stage list 2>/dev/null | jq -r ".stages[] | select(.id==\"$TEST_ID\") | .display_name")
if [[ "$ACTUAL" != "$NEW_NAME" ]]; then
    echo "FAIL: stage.list shows \"$ACTUAL\" instead of \"$NEW_NAME\""
    exit 1
fi
echo "  OK list confirms"

# Cleanup : delete.
echo "[3/3] delete stage $TEST_ID"
"$ROADIE" stage delete "$TEST_ID" >/dev/null
GONE=$("$ROADIE" stage list 2>/dev/null | jq -r ".stages[] | select(.id==\"$TEST_ID\") | .id")
if [[ -n "$GONE" ]]; then
    echo "FAIL: stage $TEST_ID still exists after delete"
    exit 1
fi
echo "  OK"

echo "ALL PASS"
