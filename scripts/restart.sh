#!/usr/bin/env bash
# scripts/restart.sh — rebuild + redeploy + relance de roadied (rail intégré).
#
# Usage :
#   ./scripts/restart.sh                    # debug, build incrémental
#   ./scripts/restart.sh --release          # release optimisé
#   ./scripts/restart.sh --no-build         # skip build, redeploy le .build/debug existant
#   ./scripts/restart.sh --zombie           # debug + NSZombieEnabled (chasse over-release)
#
# Build (mutex) :
#   --debug      (défaut, build rapide)
#   --release    (build optimisé)
#   --no-build   (skip build, redeploy + relance les .build/ existants)

set -euo pipefail

# Force PATH propre (anaconda ld shadow Xcode ld sinon).
export PATH="/usr/bin:/bin:/usr/sbin:/sbin:/Applications/Xcode.app/Contents/Developer/usr/bin"

REPO="$(cd "$(dirname "$0")/.." && pwd)"
APP_BIN="$HOME/Applications/roadied.app/Contents/MacOS/roadied"
CLI_BIN="$HOME/.local/bin/roadie"
LOG="/tmp/roadied.log"

SWIFT_CONFIG="debug"
BUILD_DIR=".build/debug"
SKIP_BUILD=0
ZOMBIE=0  # NSZombie + Malloc instrumentation : off par défaut, --zombie pour réactiver.

usage() {
    cat <<EOF >&2
usage: $0 [BUILD_CONFIG] [--zombie]

BUILD_CONFIG (mutex) :
  --debug        (défaut)
  --release
  --no-build

DEBUG :
  --zombie       active NSZombieEnabled + MallocStackLogging + MallocScribble
                 (overhead mémoire 2-3x, perf -10/-20%). Pour traquer un over-release.

Exemples :
  $0                          # rebuild + restart, debug
  $0 --release                # release
  $0 --no-build               # skip build
  $0 --zombie                 # debug + instrumentation NSZombie
EOF
}

for arg in "$@"; do
    case "$arg" in
        --release)  SWIFT_CONFIG="release"; BUILD_DIR=".build/release"; SKIP_BUILD=0 ;;
        --no-build) SWIFT_CONFIG="";        BUILD_DIR=".build/debug";   SKIP_BUILD=1 ;;
        --debug|debug|"") SWIFT_CONFIG="debug"; BUILD_DIR=".build/debug"; SKIP_BUILD=0 ;;
        --zombie)   ZOMBIE=1 ;;
        --help|-h)  usage; exit 0 ;;
        # Compat ancienne syntaxe : --daemon / --rail / --all sont silencieusement
        # ignorés (le rail est désormais intégré au binaire roadied unique).
        --daemon|--rail|--all) ;;
        *) echo "✗ flag inconnu : $arg" >&2; usage; exit 2 ;;
    esac
done

echo "→ config : ${SWIFT_CONFIG:-no-build}"
echo ""

cd "$REPO"

# ============================================================================
# Étape 1 : build.
# ============================================================================
if [ "$SKIP_BUILD" -eq 0 ]; then
    echo "→ swift build --product roadied (${SWIFT_CONFIG})"
    swift build --product roadied --configuration "$SWIFT_CONFIG" 2>&1 | tail -5
    echo ""
    echo "→ swift build --product roadie (${SWIFT_CONFIG})"
    swift build --product roadie --configuration "$SWIFT_CONFIG" 2>&1 | tail -3
    echo ""
fi

# Vérifier que les binaires nécessaires existent.
NEW_DAEMON="$REPO/$BUILD_DIR/roadied"
NEW_CLI="$REPO/$BUILD_DIR/roadie"
if [ ! -x "$NEW_DAEMON" ] || [ ! -x "$NEW_CLI" ]; then
    echo "✗ binaire manquant : $NEW_DAEMON ou $NEW_CLI" >&2
    echo "  relance sans --no-build" >&2
    exit 1
fi

# ============================================================================
# Étape 2 : stop. `pkill -x roadied` matche le NOM du process (basename de
# l'exec), pas les args ni le path — capture donc les daemons lancés d'ailleurs
# (ex. ~/.local/bin/roadied d'une session précédente). Le ciblage par args
# (`-f "roadied --daemon"`) ratait ces zombies → 2 daemons en parallèle =
# AX events doublés + layout race condition.
# ============================================================================
echo "→ stop roadied en cours"
# Cleanup résidu V1 (silencieux si absent).
pkill -f "roadie-rail" 2>/dev/null || true

if pgrep -x roadied >/dev/null 2>&1; then
    N=$(pgrep -x roadied | wc -l | tr -d ' ')
    [ "$N" -gt 1 ] && echo "  ⚠ $N daemons détectés, kill all"
    pkill -x roadied || true
    for _ in 1 2 3 4 5; do
        if ! pgrep -x roadied >/dev/null 2>&1; then break; fi
        sleep 0.3
    done
    if pgrep -x roadied >/dev/null 2>&1; then
        echo "  ne s'est pas arrêté, force kill"
        pkill -9 -x roadied || true
        sleep 0.5
    fi
    echo "  ✓ stoppé"
else
    echo "  (aucune instance en cours)"
fi

# ============================================================================
# Étape 3 : deploy + codesign.
# Re-codesign après cp : macOS Tahoe (codeSigningMonitor=2) invalide la signature
# embarquée quand le binaire est copié → SIGKILL "Code Signature Invalid".
# ============================================================================
echo ""
echo "→ deploy roadied → $APP_BIN"
mkdir -p "$(dirname "$APP_BIN")"
cp "$NEW_DAEMON" "$APP_BIN"
codesign --force --sign - "$APP_BIN" 2>&1 | grep -v "replacing existing signature" || true
echo "  ✓ $(ls -la "$APP_BIN" | awk '{print $5, $6, $7, $8}')"

echo "→ deploy roadie  → $CLI_BIN"
mkdir -p "$(dirname "$CLI_BIN")"
cp "$NEW_CLI" "$CLI_BIN"
codesign --force --sign - "$CLI_BIN" 2>&1 | grep -v "replacing existing signature" || true
echo "  ✓ $(ls -la "$CLI_BIN" | awk '{print $5, $6, $7, $8}')"

# ============================================================================
# Étape 4 : avertir si la config a une section legacy.
# ============================================================================
if grep -q '^\[multi_desktop\]' "$HOME/.config/roadies/roadies.toml" 2>/dev/null; then
    echo ""
    echo "⚠  ~/.config/roadies/roadies.toml contient encore [multi_desktop] (SPEC-003 deprecated)."
    echo "   Remplace par [desktops] enabled=true (cf. SPEC-011 quickstart)."
fi

# ============================================================================
# Étape 5 : start.
# Instrumentation crash SIGSEGV pool drain (objc_release dans autoreleasePoolPop).
# Off par défaut depuis la fix `0c41ff1` (autoreleasepool dans SCKCaptureService).
# Réactiver via --zombie si un nouveau crash NSWindow release apparaît.
# ============================================================================
echo ""
if [ "$ZOMBIE" -eq 1 ]; then
    echo "→ start (NSZombie ON)"
    nohup env \
        NSZombieEnabled=YES \
        MallocStackLogging=1 \
        MallocStackLoggingNoCompact=1 \
        MallocScribble=1 \
        NSAutoreleaseFreedObjectCheckEnabled=YES \
        "$APP_BIN" --daemon > "$LOG" 2>&1 &
else
    echo "→ start"
    nohup "$APP_BIN" --daemon > "$LOG" 2>&1 &
fi
DAEMON_PID=$!
disown "$DAEMON_PID" 2>/dev/null || true

sleep 0.5
if kill -0 "$DAEMON_PID" 2>/dev/null; then
    echo "  ✓ up, PID=$DAEMON_PID"
    echo "  log : tail -f $LOG"
else
    echo "✗ a quitté immédiatement, voir $LOG :" >&2
    tail -20 "$LOG" >&2
    exit 1
fi

# ============================================================================
# Étape 6 : sanity check.
# ============================================================================
echo ""
echo "→ sanity check : roadie desktop list"
sleep 0.5
"$CLI_BIN" desktop list 2>&1 | head -10 || echo "  (commande indisponible — config peut être [desktops] enabled=false)"

echo ""
echo "✓ restart terminé"
