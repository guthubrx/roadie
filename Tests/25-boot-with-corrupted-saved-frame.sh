#!/usr/bin/env bash
# Tests/25-boot-with-corrupted-saved-frame.sh
# SPEC-025 FR-001 — vérifie que les saved_frame offscreen persistées sont
# invalidées au boot (validateMembers). Si le test passe, le rebooter avec
# un TOML pollué Y=-9999 ne piège plus aucune fenêtre offscreen.
#
# Skip silencieux si aucun TOML stage présent.

set -uo pipefail
export LC_NUMERIC=C

STAGES_DIR="$HOME/.config/roadies/stages"

if [ ! -d "$STAGES_DIR" ]; then
    echo "SKIP: aucun state stage à valider ($STAGES_DIR absent)"
    exit 0
fi

# Trouve un fichier .toml stage non-legacy.
STAGE_FILE=$(find "$STAGES_DIR" -name "*.toml" -not -name "*.legacy.*" -not -name "_active*" -not -name "active.toml" | head -1)

if [ -z "$STAGE_FILE" ]; then
    echo "SKIP: aucun fichier stage TOML trouvé"
    exit 0
fi

# Backup du fichier original.
BACKUP="${STAGE_FILE}.test25-backup"
cp "$STAGE_FILE" "$BACKUP"
trap 'cp "$BACKUP" "$STAGE_FILE"; rm -f "$BACKUP"' EXIT

# Inject une saved_frame.y = -9999 (largement offscreen, hors plage tous displays).
# On ne sait pas si le fichier a déjà des members → check.
if ! grep -q '\[\[members\]\]' "$STAGE_FILE"; then
    echo "SKIP: stage file sans members ($STAGE_FILE)"
    exit 0
fi

# Inject : remplacer la première saved_frame par y=-9999 si elle existe.
if grep -q '\[members.saved_frame\]' "$STAGE_FILE"; then
    # Modif ciblée : remplace le premier 'y =' suivant '[members.saved_frame]'
    awk '
        BEGIN { in_sf = 0; replaced = 0 }
        /\[members\.saved_frame\]/ { in_sf = 1; print; next }
        in_sf && /^y *=/ && !replaced { print "y = -9999.0"; replaced = 1; in_sf = 0; next }
        { print }
    ' "$STAGE_FILE" > "${STAGE_FILE}.tmp" && mv "${STAGE_FILE}.tmp" "$STAGE_FILE"
fi

# Restart daemon.
echo "==> restart daemon avec TOML pollué"
launchctl bootout "gui/$(id -u)/com.roadie.roadie" 2>/dev/null || true
sleep 2
launchctl bootstrap "gui/$(id -u)" "$HOME/Library/LaunchAgents/com.roadie.roadie.plist" 2>/dev/null
sleep 5

# Vérifie que la log contient loadFromDisk_validated avec invalidated_savedFrames > 0.
if grep -E '"msg":"loadFromDisk_validated"' "$HOME/.local/state/roadies/daemon.log" 2>/dev/null | tail -1 | grep -q '"invalidated_savedFrames":"[1-9]'; then
    echo "PASS: validation au load a invalidé les saved_frame offscreen"
    exit 0
else
    LAST_LINE=$(grep -E '"msg":"loadFromDisk_validated"' "$HOME/.local/state/roadies/daemon.log" 2>/dev/null | tail -1)
    echo "FAIL: pas de log loadFromDisk_validated avec compteur > 0"
    echo "      dernier log : $LAST_LINE"
    exit 1
fi
