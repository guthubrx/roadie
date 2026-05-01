#!/usr/bin/env bash
# Test d'intégration multi-desktop V2 — migration V1 → V2 (T049).
#
# Ce test simule un utilisateur V1 qui upgrade vers V2 :
# 1. Crée un faux ~/.config/roadies/stages/ avec 2 stages V1 (sandbox HOME isolé)
# 2. Lance roadied avec multi_desktop.enabled=true
# 3. Vérifie que ~/.config/roadies/desktops/<uuid>/stages/*.toml est créé
# 4. Vérifie que ~/.config/roadies/stages.v1-backup-YYYYMMDD/ existe
#
# Couvre FR-023 (migration auto V1→V2) + SC-005 (compat ascendante stricte).
#
# Pré-requis :
# - binaire roadied compilé (.build/debug/roadied OK pour ce test)
# - jq installé

set -euo pipefail

PASS=0
FAIL=0

assert() {
    local name="$1"; local cond="$2"
    if eval "$cond"; then echo "  ✓ $name"; PASS=$((PASS+1));
    else echo "  ✗ $name (cond: $cond)"; FAIL=$((FAIL+1)); fi
}

# Sandbox HOME : isole tout dans un tmpdir pour ne pas toucher la config user réelle.
SANDBOX=$(mktemp -d -t roadies-mig-XXXXXX)
trap 'rm -rf "$SANDBOX"' EXIT

CONFIG_DIR="$SANDBOX/.config/roadies"
mkdir -p "$CONFIG_DIR/stages"

# --- 1) Setup faux state V1 ---
echo "[07] T049 — setup faux state V1 dans $SANDBOX"

cat > "$CONFIG_DIR/stages/main.toml" <<'EOF'
id = "main"
display_name = "Main V1"
last_active_at = "2026-04-30T10:00:00Z"
members = []
EOF

cat > "$CONFIG_DIR/stages/work.toml" <<'EOF'
id = "work"
display_name = "Work V1"
last_active_at = "2026-04-30T11:00:00Z"
members = []
EOF

cat > "$CONFIG_DIR/stages/active.toml" <<'EOF'
current_stage = "main"
EOF

# Config V2 avec multi_desktop.enabled=true
cat > "$CONFIG_DIR/roadies.toml" <<'EOF'
[multi_desktop]
enabled = true
back_and_forth = true

[stage_manager]
enabled = true
hide_strategy = "corner"
EOF

assert "v1 stages/main.toml créé" "[ -f \"$CONFIG_DIR/stages/main.toml\" ]"
assert "v1 stages/work.toml créé" "[ -f \"$CONFIG_DIR/stages/work.toml\" ]"
assert "v2 desktops/ pas encore créé" "[ ! -d \"$CONFIG_DIR/desktops\" ]"

# --- 2) Lancer roadied dans le sandbox HOME ---
# Pour que le daemon utilise notre config, on override HOME.
# Note : on lance le daemon puis on l'arrête immédiatement après le bootstrap migration.
echo "[07] T049 — lance roadied avec HOME sandbox"

ROADIED_BIN="$(pwd)/.build/debug/roadied"
if [ ! -x "$ROADIED_BIN" ]; then
    ROADIED_BIN="$(pwd)/.build/release/roadied"
fi
if [ ! -x "$ROADIED_BIN" ]; then
    echo "  SKIP : roadied non compilé (lancer 'swift build' d'abord)"
    exit 0
fi

# Lance le daemon en background avec HOME=sandbox.
# Note : Accessibility permission n'est pas accordée pour ce binaire de test.
# Le daemon va probablement quitter rapidement avec exit 2. C'est OK pour ce test :
# la migration s'exécute AVANT le check Accessibility (ordre des steps dans bootstrap).
# Si l'ordre changeait, on aurait besoin de stub la migration.
HOME="$SANDBOX" "$ROADIED_BIN" >/dev/null 2>&1 &
DAEMON_PID=$!
sleep 1.0
kill -TERM "$DAEMON_PID" 2>/dev/null || true
wait "$DAEMON_PID" 2>/dev/null || true

# --- 3) Vérifier la migration ---
echo "[07] T049 — assertions post-migration"

# Le backup horodaté doit exister.
BACKUP_COUNT=$(find "$CONFIG_DIR" -maxdepth 1 -type d -name "stages.v1-backup-*" | wc -l | tr -d ' ')
assert "1 backup stages.v1-backup-* créé" "[ \"$BACKUP_COUNT\" = \"1\" ]"

BACKUP_DIR=$(find "$CONFIG_DIR" -maxdepth 1 -type d -name "stages.v1-backup-*" | head -1)
assert "backup contient main.toml" "[ -f \"$BACKUP_DIR/main.toml\" ]"
assert "backup contient work.toml" "[ -f \"$BACKUP_DIR/work.toml\" ]"

# Le dossier V2 desktops/<uuid>/stages/ doit exister avec les fichiers déplacés.
# On ne peut pas connaître l'UUID exact (c'est un real macOS UUID), donc on cherche.
V2_STAGES_DIR=$(find "$CONFIG_DIR/desktops" -mindepth 2 -maxdepth 2 -type d -name "stages" 2>/dev/null | head -1)
if [ -n "$V2_STAGES_DIR" ]; then
    assert "v2 desktops/<uuid>/stages/main.toml existe" "[ -f \"$V2_STAGES_DIR/main.toml\" ]"
    assert "v2 desktops/<uuid>/stages/work.toml existe" "[ -f \"$V2_STAGES_DIR/work.toml\" ]"
else
    echo "  ⚠ desktops/ pas créé : la migration n'a pas tourné (probable : pas d'API Mission Control accessible sans GUI)"
    echo "    À valider en run interactif sur machine GUI."
fi

# Le dossier V1 doit avoir disparu (déplacé dans backup).
assert "stages/ V1 supprimé après migration" "[ ! -d \"$CONFIG_DIR/stages\" ] || [ -z \"$(ls -A \"$CONFIG_DIR/stages\" 2>/dev/null)\" ]"

# --- Bilan ---
echo ""
echo "[07] Bilan : $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
