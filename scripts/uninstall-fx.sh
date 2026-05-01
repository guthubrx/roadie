#!/usr/bin/env bash
# scripts/uninstall-fx.sh — retire complètement la famille SIP-off opt-in.
# Le daemon roadied core reste fonctionnel (vanilla SPEC-001+002+003).

set -euo pipefail

DYLIB_DIR="$HOME/.local/lib/roadie"
OSAX_DST="/Library/ScriptingAdditions/roadied.osax"

echo "→ Stop roadied"
if pgrep -x roadied >/dev/null; then
    killall roadied 2>/dev/null
    sleep 0.5
fi

echo ""
echo "→ Retire osax de /Library/ScriptingAdditions/ (sudo requis)"
if [ -d "$OSAX_DST" ]; then
    sudo rm -rf "$OSAX_DST"
    echo "  ✓ Supprimé"
else
    echo "  (déjà absent)"
fi

echo ""
echo "→ Force unload osax dans Dock (relance Dock)"
killall Dock 2>/dev/null || true
sleep 0.5

echo ""
echo "→ Retire dylibs de $DYLIB_DIR"
if [ -d "$DYLIB_DIR" ]; then
    rm -f "$DYLIB_DIR"/*.dylib
    echo "  ✓ Dylibs supprimés"
fi

echo ""
echo "→ Restart roadied (vanilla)"
if [ -x "$HOME/.local/bin/roadied" ]; then
    nohup "$HOME/.local/bin/roadied" --daemon \
        >> "$HOME/.local/state/roadies/daemon.log" 2>&1 &
    disown
    echo "  ✓ Daemon relancé en mode vanilla"
fi

echo ""
echo "✓ Uninstall terminé."
echo ""
echo "Vérifie l'état :"
echo "  roadie fx status        # doit afficher modules: []"
echo "  ls $DYLIB_DIR           # doit être vide"
echo "  ls $OSAX_DST            # doit être absent"
