#!/usr/bin/env bash
# Tests/25-boot-with-zombie-wids.sh
# SPEC-025 FR-002 — vérifie que les wids zombies dans memberWindows sont
# purgées automatiquement au boot (purgeOrphanWindows + rebuildWidToScopeIndex).

set -uo pipefail

STAGES_DIR="$HOME/.config/roadies/stages"

if [ ! -d "$STAGES_DIR" ]; then
    echo "SKIP: aucun state stage à valider"
    exit 0
fi

STAGE_FILE=$(find "$STAGES_DIR" -name "*.toml" -not -name "*.legacy.*" -not -name "_active*" -not -name "active.toml" | head -1)

if [ -z "$STAGE_FILE" ]; then
    echo "SKIP: aucun fichier stage TOML trouvé"
    exit 0
fi

# Backup.
BACKUP="${STAGE_FILE}.test25-zombie-backup"
cp "$STAGE_FILE" "$BACKUP"
trap 'cp "$BACKUP" "$STAGE_FILE"; rm -f "$BACKUP"' EXIT

# Inject : remplacer le cg_window_id de premier member par 999999 (wid inexistante).
if ! grep -q 'cg_window_id' "$STAGE_FILE"; then
    echo "SKIP: stage file sans cg_window_id"
    exit 0
fi

awk '
    BEGIN { replaced = 0 }
    /cg_window_id *=/ && !replaced { print "cg_window_id = 999999"; replaced = 1; next }
    { print }
' "$STAGE_FILE" > "${STAGE_FILE}.tmp" && mv "${STAGE_FILE}.tmp" "$STAGE_FILE"

# Restart daemon.
echo "==> restart daemon avec wid zombie injectée"
launchctl bootout "gui/$(id -u)/com.roadie.roadie" 2>/dev/null || true
sleep 2
launchctl bootstrap "gui/$(id -u)" "$HOME/Library/LaunchAgents/com.roadie.roadie.plist" 2>/dev/null
sleep 5

# Vérifie qu'on a un boot_audit_autofixed avec violations_before > 0
# OU que purgeOrphanWindows a logué qq chose.
if grep -E '"msg":"boot_audit_autofixed"' "$HOME/.local/state/roadies/daemon.log" 2>/dev/null | tail -3 | grep -q .; then
    echo "PASS: auto-fix au boot a tourné (boot_audit_autofixed dans logs)"
    # Vérifie que audit ne reporte plus de violations.
    sleep 1
    AUDIT_OUT=$(timeout 3 ~/.local/bin/roadie daemon audit 2>&1)
    if echo "$AUDIT_OUT" | grep -qE 'count: 0'; then
        echo "PASS: audit retourne count: 0 après auto-fix"
        exit 0
    else
        echo "FAIL: audit reporte des violations restantes :"
        echo "$AUDIT_OUT" | head
        exit 1
    fi
else
    LAST=$(tail -3 "$HOME/.local/state/roadies/daemon.log" 2>/dev/null | grep audit || true)
    echo "FAIL: pas de log boot_audit_autofixed après injection wid zombie"
    echo "      dernier log audit : $LAST"
    exit 1
fi
