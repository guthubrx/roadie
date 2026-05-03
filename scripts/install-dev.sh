#!/usr/bin/env bash
# install-dev.sh — workflow dev pour roadie.
#
# - Build (swift build) si pas explicitement skipped
# - Copie roadied dans ~/Applications/roadied.app/Contents/MacOS/ (chemin stable connu de TCC)
# - Copie roadie + roadie-rail dans ~/.local/bin/
# - Re-signe avec roadied-cert pour préserver la grant Accessibility entre rebuilds
# - Restart launchd (daemon) + relance roadie-rail manuellement
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
RAIL_BIN="$HOME/.local/bin/roadie-rail"
CLI_BIN="$HOME/.local/bin/roadie"

# PATH override pour eviter ld shadow par anaconda (cf MEMORY.md projet).
export PATH="/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin:$PATH"

if [[ "${1:-}" != "--no-build" ]]; then
  echo "==> swift build (release-debug, host arch)"
  cd "$REPO_ROOT"
  swift build
fi

BUILD_DIR="$REPO_ROOT/.build/debug"
[[ -x "$BUILD_DIR/roadied" ]]    || { echo "missing $BUILD_DIR/roadied"; exit 1; }
[[ -x "$BUILD_DIR/roadie-rail" ]] || { echo "missing $BUILD_DIR/roadie-rail"; exit 1; }
[[ -x "$BUILD_DIR/roadie" ]]      || { echo "missing $BUILD_DIR/roadie"; exit 1; }

echo "==> stop running instances"
launchctl bootout "gui/$(id -u)/com.roadie.roadie" 2>/dev/null || true
pkill -f roadie-rail 2>/dev/null || true
pkill -f "roadie events" 2>/dev/null || true
sleep 1

echo "==> install binaries"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$HOME/.local/bin"
cp "$BUILD_DIR/roadied"     "$APP_BIN"
cp "$BUILD_DIR/roadie-rail" "$RAIL_BIN"
cp "$BUILD_DIR/roadie"      "$CLI_BIN"

# Symlink dev pour que `cp .build/debug/roadied ~/.local/bin/` continue a marcher.
ln -sf "$APP_BIN" "$HOME/.local/bin/roadied"

echo "==> codesign with $CERT (preserve TCC grants)"
codesign -fs "$CERT" "$APP_BIN"     2>&1 | tail -1
codesign -fs "$CERT" "$RAIL_BIN"    2>&1 | tail -1
codesign -fs "$CERT" "$CLI_BIN"     2>&1 | tail -1

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

echo "==> restart daemon via launchd"
launchctl bootstrap "gui/$(id -u)" "$HOME/Library/LaunchAgents/com.roadie.roadie.plist"
sleep 2

echo "==> restart roadie-rail"
("$RAIL_BIN" >/tmp/roadie-rail.log 2>&1 &)
sleep 1

echo
echo "==> status"
launchctl list | grep roadie || true
pgrep -lf roadied      | head -1 || true
pgrep -lf roadie-rail  | head -1 || true
echo
echo "Done. Si la 1ere fois apres creation du cert, donne la perm Accessibility a :"
echo "    $APP_BIN"
echo "via Reglages Systeme > Confidentialite et securite > Accessibilite."
