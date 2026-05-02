#!/usr/bin/env bash
# scripts/install-fx.sh — installe la famille SIP-off opt-in :
#   1. Compile et dépose `roadied.osax` dans /Library/ScriptingAdditions/
#   2. Recharge les scripting additions de Dock pour activer l'osax
#   3. Compile les `.dylib` modules et les copie dans ~/.local/lib/roadie/
#
# Pré-requis :
#   - SIP partial off : csrutil enable --without fs --without nvram
#   - Permissions sudo (pour /Library/ScriptingAdditions/)
#
# Désinstallation : scripts/uninstall-fx.sh

set -euo pipefail

export PATH="/usr/bin:/bin:/usr/sbin:/sbin:/Applications/Xcode.app/Contents/Developer/usr/bin"

REPO="$(cd "$(dirname "$0")/.." && pwd)"
DYLIB_DIR="$HOME/.local/lib/roadie"
OSAX_SRC="$REPO/osax/build/roadied.osax"
OSAX_DST="/Library/ScriptingAdditions/roadied.osax"

# Vérification SIP
SIP_STATE=$(csrutil status 2>/dev/null || echo "unknown")
if echo "$SIP_STATE" | grep -qi "filesystem protections: disabled"; then
    echo "✓ SIP partial off (filesystem) — OK pour scripting addition"
elif echo "$SIP_STATE" | grep -qi "system integrity protection status: disabled"; then
    echo "✓ SIP fully disabled — OK"
else
    echo "✗ SIP entièrement actif"
    echo "  Pour autoriser les scripting additions, depuis Recovery Mode :"
    echo "    csrutil enable --without fs --without nvram"
    echo ""
    echo "  L'install va continuer mais Dock ne chargera pas l'osax."
fi

# Étape 1 : compile osax si pas fait
echo ""
echo "→ Build osax bundle"
if [ ! -d "$OSAX_SRC" ]; then
    bash "$REPO/osax/build.sh"
else
    echo "  (déjà compilé : $OSAX_SRC)"
fi

# Étape 2 : compile les dylibs
echo ""
echo "→ Build dylibs des modules FX"
cd "$REPO"
swift build --configuration release 2>&1 | tail -3

# Étape 3 : install osax. Utilise `osascript do shell script with
# administrator privileges` qui ouvre une popup macOS native demandant le mot
# de passe — fonctionne quand stdin n'est pas un TTY (cas de make install-fx).
echo ""
echo "→ Install osax dans /Library/ScriptingAdditions/"
echo "  (popup macOS va demander le mot de passe administrateur)"
INSTALL_CMD="rm -rf '$OSAX_DST' && cp -R '$OSAX_SRC' '$OSAX_DST' && chown -R root:wheel '$OSAX_DST'"
osascript -e "do shell script \"$INSTALL_CMD\" with administrator privileges" \
    >/dev/null 2>&1 || {
        echo "  ⚠ popup admin échouée — fallback sudo manuel :"
        echo "    sudo cp -R '$OSAX_SRC' '$OSAX_DST'"
        echo "    sudo chown -R root:wheel '$OSAX_DST'"
        exit 1
    }
echo "  ✓ osax installée"

# Étape 4 : copie dylibs
echo ""
echo "→ Install dylibs dans $DYLIB_DIR"
mkdir -p "$DYLIB_DIR"
for lib in libRoadieFXCore libRoadieShadowless libRoadieOpacity libRoadieAnimations libRoadieBorders libRoadieBlur libRoadieCrossDesktop; do
    src="$REPO/.build/release/$lib.dylib"
    if [ -f "$src" ]; then
        cp "$src" "$DYLIB_DIR/"
        echo "  ✓ $lib.dylib"
    else
        echo "  ⚠ $lib.dylib introuvable (non compilé ?)"
    fi
done

# Étape 5 : force-load scripting additions dans Dock
echo ""
echo "→ Reload Dock scripting additions"
osascript -e 'tell application "Dock" to load scripting additions' 2>/dev/null || \
    echo "  (osascript a échoué — relance Dock manuellement : killall Dock)"

# Étape 6 : restart daemon roadied (si présent)
echo ""
echo "→ Restart roadied"
if pgrep -x roadied >/dev/null; then
    killall roadied 2>/dev/null
    sleep 0.5
fi

if [ -x "$HOME/.local/bin/roadied" ]; then
    nohup "$HOME/.local/bin/roadied" --daemon \
        >> "$HOME/.local/state/roadies/daemon.log" 2>&1 &
    disown
    echo "  ✓ roadied relancé"
else
    echo "  ⚠ ~/.local/bin/roadied absent — utilise 'make install-app' d'abord"
fi

echo ""
echo "✓ Install terminé."
echo ""
echo "Vérifie l'état :"
echo "  roadie fx status"
echo ""
echo "Logs daemon :"
echo "  tail -f ~/.local/state/roadies/daemon.log"
