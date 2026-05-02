#!/usr/bin/env bash
# Compile et bundle `roadied.osax` (scripting addition macOS).
#
# Sortie : osax/build/roadied.osax/ (bundle complet, signé ad-hoc).
# Installable via scripts/install-fx.sh.

set -euo pipefail

# Force PATH propre (anaconda ld shadow Xcode ld sinon).
export PATH="/usr/bin:/bin:/usr/sbin:/sbin:/Applications/Xcode.app/Contents/Developer/usr/bin"

OSAX_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$OSAX_DIR/build"
BUNDLE="$BUILD_DIR/roadied.osax"
CONTENTS="$BUNDLE/Contents"
MACOS_DIR="$CONTENTS/MacOS"
RESOURCES_DIR="$CONTENTS/Resources"

rm -rf "$BUILD_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

# Compilation : Objective-C++ + Cocoa + framework privé SkyLight pour les CGS.
# Target `arm64e` (Pointer Authentication Codes) impératif sur Apple Silicon :
# Dock est compilé en arm64e, et même avec SIP fully disabled + boot-arg
# `-arm64e_preview_abi`, dyld refuse silencieusement de charger une dylib
# arm64 (non-e) dans un process arm64e. Réfs : yabai issue #1766, SpecterOps
# blog "ARM64 dylib injection on macOS" (2025-08-21).
clang++ \
    -bundle \
    -fobjc-arc \
    -fmodules \
    -std=c++17 \
    -target arm64e-apple-macos14 \
    -mmacosx-version-min=14.0 \
    -F /System/Library/PrivateFrameworks \
    -framework Foundation \
    -framework AppKit \
    -framework CoreGraphics \
    -framework SkyLight \
    -I "$OSAX_DIR" \
    -o "$MACOS_DIR/roadied" \
    "$OSAX_DIR/main.mm" \
    "$OSAX_DIR/osax_socket.mm" \
    "$OSAX_DIR/osax_handlers.mm"

# Métadonnées du bundle.
cp "$OSAX_DIR/Info.plist" "$CONTENTS/Info.plist"
cp "$OSAX_DIR/roadied.sdef" "$RESOURCES_DIR/roadied.sdef"

# Signature ad-hoc SANS hardened runtime. `--options runtime` (hardened
# runtime) bloque le chargement par Dock pour les scripting additions tiers
# non-Apple-signed. Sur macOS récent (14+), le scripting addition doit avoir
# un runtime non-hardened pour être chargé via `osascript ... load scripting
# additions`.
codesign --force --sign - "$BUNDLE"

echo ""
echo "✓ Built: $BUNDLE"
echo ""
echo "Pour installer :"
echo "  sudo cp -R \"$BUNDLE\" /Library/ScriptingAdditions/"
echo "  osascript -e 'tell application \"Dock\" to load scripting additions'"
echo ""
echo "Ou utilise le script : scripts/install-fx.sh"
