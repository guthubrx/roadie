#!/usr/bin/env bash
# scripts/restart.sh — rebuild + redeploy + relance roadied avec le binaire courant.
#
# Usage :
#   ./scripts/restart.sh                # debug build (rapide, par défaut)
#   ./scripts/restart.sh --release      # release build (binaire optimisé)
#   ./scripts/restart.sh --no-build     # skip build, redeploy + relance le binaire .build existant

set -euo pipefail

# Force PATH propre (anaconda ld shadow Xcode ld sinon).
export PATH="/usr/bin:/bin:/usr/sbin:/sbin:/Applications/Xcode.app/Contents/Developer/usr/bin"

REPO="$(cd "$(dirname "$0")/.." && pwd)"
APP_BIN="/Users/moi/Applications/roadied.app/Contents/MacOS/roadied"
CLI_BIN="$HOME/.local/bin/roadie"
LOG="/tmp/roadied.log"

CONFIG="${1:-debug}"
case "$CONFIG" in
    --release)
        SWIFT_CONFIG="release"
        BUILD_DIR=".build/release"
        SKIP_BUILD=0
        ;;
    --no-build)
        SWIFT_CONFIG=""
        BUILD_DIR=".build/debug"
        SKIP_BUILD=1
        ;;
    --debug|debug|"")
        SWIFT_CONFIG="debug"
        BUILD_DIR=".build/debug"
        SKIP_BUILD=0
        ;;
    *)
        echo "usage: $0 [--debug | --release | --no-build]" >&2
        exit 2
        ;;
esac

cd "$REPO"

# Étape 1 : build
if [ "$SKIP_BUILD" -eq 0 ]; then
    echo "→ swift build --product roadied (${SWIFT_CONFIG})"
    swift build --product roadied --configuration "$SWIFT_CONFIG" 2>&1 | tail -5
    echo ""
    echo "→ swift build --product roadie (${SWIFT_CONFIG})"
    swift build --product roadie --configuration "$SWIFT_CONFIG" 2>&1 | tail -3
    echo ""
fi

# Vérifier que les binaires existent
NEW_DAEMON="$REPO/$BUILD_DIR/roadied"
NEW_CLI="$REPO/$BUILD_DIR/roadie"
if [ ! -x "$NEW_DAEMON" ] || [ ! -x "$NEW_CLI" ]; then
    echo "✗ binaire manquant : $NEW_DAEMON ou $NEW_CLI" >&2
    echo "  relance sans --no-build" >&2
    exit 1
fi

# Étape 2 : tuer le daemon en cours
echo "→ stop daemon en cours"
if pgrep -f "roadied --daemon" >/dev/null 2>&1; then
    pkill -f "roadied --daemon" || true
    # Attendre la libération du socket
    for _ in 1 2 3 4 5; do
        if ! pgrep -f "roadied --daemon" >/dev/null 2>&1; then
            break
        fi
        sleep 0.3
    done
    if pgrep -f "roadied --daemon" >/dev/null 2>&1; then
        echo "  daemon ne s'est pas arrêté, force kill"
        pkill -9 -f "roadied --daemon" || true
        sleep 0.5
    fi
    echo "  ✓ daemon stoppé"
else
    echo "  (aucun daemon en cours)"
fi

# Étape 3 : remplacer les binaires
echo ""
echo "→ deploy roadied → $APP_BIN"
mkdir -p "$(dirname "$APP_BIN")"
cp "$NEW_DAEMON" "$APP_BIN"
echo "  ✓ $(ls -la "$APP_BIN" | awk '{print $5, $6, $7, $8}')"

echo "→ deploy roadie  → $CLI_BIN"
mkdir -p "$(dirname "$CLI_BIN")"
cp "$NEW_CLI" "$CLI_BIN"
echo "  ✓ $(ls -la "$CLI_BIN" | awk '{print $5, $6, $7, $8}')"

# Étape 4 : avertir si la config a une section legacy
if grep -q '^\[multi_desktop\]' "$HOME/.config/roadies/roadies.toml" 2>/dev/null; then
    echo ""
    echo "⚠  ~/.config/roadies/roadies.toml contient encore [multi_desktop] (SPEC-003 deprecated)."
    echo "   Remplace par [desktops] enabled=true (cf. SPEC-011 quickstart)."
fi

# Étape 5 : relancer le daemon en background, log dans /tmp/roadied.log
echo ""
echo "→ start daemon"
nohup "$APP_BIN" --daemon > "$LOG" 2>&1 &
DAEMON_PID=$!
disown "$DAEMON_PID" 2>/dev/null || true

# Vérifier que le daemon est bien up
sleep 0.5
if kill -0 "$DAEMON_PID" 2>/dev/null; then
    echo "  ✓ daemon up, PID=$DAEMON_PID"
    echo "  log : tail -f $LOG"
else
    echo "✗ daemon a quitté immédiatement, voir $LOG :" >&2
    tail -20 "$LOG" >&2
    exit 1
fi

# Étape 6 : sanity check
echo ""
echo "→ sanity check : roadie desktop list"
sleep 0.5
"$CLI_BIN" desktop list 2>&1 | head -10 || echo "  (commande indisponible — config peut être [desktops] enabled=false)"

echo ""
echo "✓ restart terminé"
