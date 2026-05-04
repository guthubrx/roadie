#!/usr/bin/env bash
# install-dev.sh — workflow dev pour roadie (V2 mono-binaire, SPEC-024).
#
# - Build (swift build) si pas explicitement skipped
# - Cleanup l'ancien rail séparé (roadie-rail.app) si présent (migration V1→V2)
# - Copie roadied dans ~/Applications/roadied.app/Contents/MacOS/ (chemin stable connu de TCC)
# - Copie roadie (CLI) dans ~/.local/bin/
# - Re-signe avec roadied-cert pour préserver les grants TCC entre rebuilds
# - Restart launchd. Plus de second process : le rail est intégré au daemon.
#
# Convention : la grant Accessibility est ancrée à la signature `roadied-cert`,
# tant que les binaires sont resignés avec ce même cert, la perm persiste.
#
# Usage :
#   ./scripts/install-dev.sh           # build + install + restart
#   ./scripts/install-dev.sh --no-build # skip swift build (utile si binaire deja a jour)

set -euo pipefail

CERT="${ROADIE_CERT:-roadied-cert}"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_BUNDLE="$HOME/Applications/roadied.app"
APP_BIN="$APP_BUNDLE/Contents/MacOS/roadied"
# SPEC-024 — fusion mono-binaire : plus de roadie-rail séparé. Les chemins
# RAIL_* ci-dessous sont conservés UNIQUEMENT pour la migration V1→V2
# (cleanup de l'ancien bundle si présent sur la machine).
RAIL_BUNDLE_OLD="$HOME/Applications/roadie-rail.app"
RAIL_BIN_OLD="$HOME/.local/bin/roadie-rail"
CLI_BIN="$HOME/.local/bin/roadie"

# PATH override pour eviter ld shadow par anaconda (cf MEMORY.md projet).
export PATH="/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin:$PATH"

# Pre-requis : check des dependances. Liste exhaustive pour qu'un dev fresh
# checkout sache exactement ce qu'il manque.
MISSING=()
check_dep() {
    local cmd="$1" hint="$2"
    command -v "$cmd" >/dev/null || MISSING+=("  - $cmd : $hint")
}
check_dep swift              "Xcode Command Line Tools (xcode-select --install)"
check_dep codesign           "Xcode Command Line Tools (xcode-select --install)"
check_dep launchctl          "macOS natif"
check_dep terminal-notifier  "brew install terminal-notifier (notification quand TCC drop)"
# SketchyBar deps optionnelles : seulement check si user veut le panneau barre.
if [[ "${ROADIE_WITH_SKETCHYBAR:-1}" = "1" ]]; then
    check_dep sketchybar     "brew install FelixKratz/formulae/sketchybar (panneau desktops x stages)"
    check_dep jq             "brew install jq (parsing JSON dans le bridge SketchyBar)"
fi

if [ ${#MISSING[@]} -gt 0 ]; then
    echo "ERROR: dependances manquantes :"
    printf '%s\n' "${MISSING[@]}"
    echo
    echo "Installe-les puis relance. Si tu n'utilises pas SketchyBar :"
    echo "    ROADIE_WITH_SKETCHYBAR=0 ./scripts/install-dev.sh"
    exit 1
fi

# Cert codesigning : verifier qu'il existe dans le keychain (cf ADR-008).
if ! security find-certificate -c "$CERT" >/dev/null 2>&1; then
    echo "ERROR: certificat codesign '$CERT' introuvable dans login keychain."
    echo
    echo "Cree-le une fois via Keychain Access :"
    echo "    Menu > Certificate Assistant > Create a Certificate..."
    echo "    Name           : $CERT"
    echo "    Identity Type  : Self Signed Root"
    echo "    Certificate Type : Code Signing"
    echo
    echo "Puis relance ce script. Cf docs/decisions/ADR-008-signing-distribution-strategy.md."
    exit 1
fi

if [[ "${1:-}" != "--no-build" ]]; then
  echo "==> swift build (release-debug, host arch)"
  cd "$REPO_ROOT"
  swift build
fi

BUILD_DIR="$REPO_ROOT/.build/debug"
[[ -x "$BUILD_DIR/roadied" ]] || { echo "missing $BUILD_DIR/roadied"; exit 1; }
[[ -x "$BUILD_DIR/roadie" ]]  || { echo "missing $BUILD_DIR/roadie"; exit 1; }

echo "==> stop running instances"
launchctl bootout "gui/$(id -u)/com.roadie.roadie" 2>/dev/null || true
pkill -f roadie-rail 2>/dev/null || true
pkill -f "roadie events" 2>/dev/null || true
sleep 1

# SPEC-024 — Migration V1→V2 : nettoyer l'ancien rail séparé s'il existe.
# Idempotent : sans effet si on est déjà en V2 ou en fresh install.
echo "==> migration V1→V2 (cleanup ancien rail séparé si présent)"
launchctl bootout "gui/$(id -u)/com.roadie.roadie-rail" 2>/dev/null || true
[[ -d "$RAIL_BUNDLE_OLD" ]] && rm -rf "$RAIL_BUNDLE_OLD" && echo "    removed $RAIL_BUNDLE_OLD"
[[ -L "$RAIL_BIN_OLD" || -f "$RAIL_BIN_OLD" ]] && rm -f "$RAIL_BIN_OLD" && echo "    removed $RAIL_BIN_OLD"
[[ -f "$HOME/.roadies/rail.pid" ]] && rm -f "$HOME/.roadies/rail.pid"
# tccutil reset (best-effort) sur l'ancien bundle id pour nettoyer les grants
# orphelines dans Réglages Système.
tccutil reset Accessibility com.roadie.roadie-rail >/dev/null 2>&1 || true
tccutil reset ScreenCapture com.roadie.roadie-rail >/dev/null 2>&1 || true

# SPEC-025 T002 — GC fichiers .legacy.* > 7 jours dans ~/.config/roadies/stages/.
# Ces fichiers sont créés par StageManager.saveStage à chaque écriture comme
# backup de l'ancienne version. Sans GC, ils s'accumulent indéfiniment (90+
# fichiers observés en quelques jours de dev).
echo "==> GC .legacy.* > 7 jours"
find "$HOME/.config/roadies/stages" -name "*.legacy.*" -type f -mtime +7 -delete 2>/dev/null || true

echo "==> install binaries (mono-binaire)"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$HOME/.local/bin"
cp "$BUILD_DIR/roadied" "$APP_BIN"
cp "$BUILD_DIR/roadie"  "$CLI_BIN"

# Symlink dev pour que `cp .build/debug/roadied ~/.local/bin/` continue a marcher.
ln -sf "$APP_BIN" "$HOME/.local/bin/roadied"

echo "==> codesign with $CERT (preserve TCC grants)"
codesign -fs "$CERT" "$APP_BIN" 2>&1 | tail -1
codesign -fs "$CERT" "$CLI_BIN" 2>&1 | tail -1

# Info.plist minimal pour que le bundle soit reconnu comme une .app par TCC.
INFO_PLIST="$APP_BUNDLE/Contents/Info.plist"
if [[ ! -f "$INFO_PLIST" ]]; then
  cat > "$INFO_PLIST" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>roadied</string>
    <key>CFBundleIdentifier</key>
    <string>com.roadie.roadied</string>
    <key>CFBundleName</key>
    <string>roadied</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1.0</string>
    <key>LSUIElement</key>
    <true/>
</dict>
</plist>
EOF
fi

echo "==> restart daemon via launchd (rail intégré, plus de second process)"
launchctl bootstrap "gui/$(id -u)" "$HOME/Library/LaunchAgents/com.roadie.roadie.plist"
sleep 4

echo
echo "==> status"
launchctl list | grep roadie || true
pgrep -lf roadied | head -1 || true

# Diagnostic TCC post-deploy. Si le hash binaire a changé depuis le dernier
# toggle TCC, le script alerte et explique quoi faire. Non-bloquant.
echo
"$REPO_ROOT/scripts/recheck-tcc.sh" || true

echo
echo "Done."
