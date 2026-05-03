#!/usr/bin/env bash
# scripts/restart.sh — rebuild + redeploy + relance sélectif des binaires.
#
# Usage :
#   ./scripts/restart.sh                    # défaut : --daemon (compat legacy)
#   ./scripts/restart.sh --rail             # rail seul
#   ./scripts/restart.sh --all              # daemon + cli + rail
#   ./scripts/restart.sh --all --release    # tout en release
#   ./scripts/restart.sh --rail --no-build  # rail seul, sans rebuild
#
# Cibles (additives) :
#   --daemon   daemon roadied + CLI roadie
#   --rail     binaire roadie-rail
#   --all      raccourci pour --daemon --rail
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
RAIL_BIN="$HOME/.local/bin/roadie-rail"
LOG="/tmp/roadied.log"
RAIL_LOG="/tmp/roadie-rail.log"

# Parse args : 2 axes (cibles additives + build mutex).
RESTART_DAEMON=0
RESTART_RAIL=0
SWIFT_CONFIG="debug"
BUILD_DIR=".build/debug"
SKIP_BUILD=0
SAW_TARGET=0
ZOMBIE=0  # NSZombie + Malloc instrumentation : off par défaut, --zombie pour réactiver.

usage() {
    cat <<EOF >&2
usage: $0 [TARGETS...] [BUILD_CONFIG]

TARGETS (additif, défaut = --daemon) :
  --daemon       daemon roadied + CLI roadie
  --rail         binaire roadie-rail
  --all          raccourci --daemon --rail

BUILD_CONFIG (mutex) :
  --debug        (défaut)
  --release
  --no-build

DEBUG :
  --zombie       active NSZombieEnabled + MallocStackLogging + MallocScribble
                 (overhead mémoire 2-3x, perf -10/-20%). Pour traquer un over-release.

Exemples :
  $0                          # daemon + CLI, debug, sans zombie
  $0 --rail                   # rail seul, debug
  $0 --all                    # tout, debug
  $0 --all --release          # tout, release
  $0 --rail --no-build        # rail seul, skip build
  $0 --daemon --zombie        # daemon avec instrumentation NSZombie
EOF
}

for arg in "$@"; do
    case "$arg" in
        --daemon) RESTART_DAEMON=1; SAW_TARGET=1 ;;
        --rail)   RESTART_RAIL=1;   SAW_TARGET=1 ;;
        --all)    RESTART_DAEMON=1; RESTART_RAIL=1; SAW_TARGET=1 ;;
        --release)  SWIFT_CONFIG="release"; BUILD_DIR=".build/release"; SKIP_BUILD=0 ;;
        --no-build) SWIFT_CONFIG="";        BUILD_DIR=".build/debug";   SKIP_BUILD=1 ;;
        --debug|debug|"") SWIFT_CONFIG="debug"; BUILD_DIR=".build/debug"; SKIP_BUILD=0 ;;
        --zombie)   ZOMBIE=1 ;;
        --help|-h)  usage; exit 0 ;;
        *) echo "✗ flag inconnu : $arg" >&2; usage; exit 2 ;;
    esac
done

# Default si aucun target spécifié → comportement legacy (daemon + cli).
if [ "$SAW_TARGET" -eq 0 ]; then
    RESTART_DAEMON=1
fi

# Récap au lancement.
TARGETS=""
[ "$RESTART_DAEMON" -eq 1 ] && TARGETS="$TARGETS daemon+cli"
[ "$RESTART_RAIL" -eq 1 ]   && TARGETS="$TARGETS rail"
TARGETS="${TARGETS# }"
echo "→ targets : $TARGETS  | config : ${SWIFT_CONFIG:-no-build}"
echo ""

cd "$REPO"

# ============================================================================
# Étape 1 : build (sélectif par cibles).
# ============================================================================
if [ "$SKIP_BUILD" -eq 0 ]; then
    if [ "$RESTART_DAEMON" -eq 1 ]; then
        echo "→ swift build --product roadied (${SWIFT_CONFIG})"
        swift build --product roadied --configuration "$SWIFT_CONFIG" 2>&1 | tail -5
        echo ""
        echo "→ swift build --product roadie (${SWIFT_CONFIG})"
        swift build --product roadie --configuration "$SWIFT_CONFIG" 2>&1 | tail -3
        echo ""
    fi
    if [ "$RESTART_RAIL" -eq 1 ]; then
        echo "→ swift build --product roadie-rail (${SWIFT_CONFIG})"
        swift build --product roadie-rail --configuration "$SWIFT_CONFIG" 2>&1 | tail -3
        echo ""
    fi
fi

# Vérifier que les binaires nécessaires existent.
if [ "$RESTART_DAEMON" -eq 1 ]; then
    NEW_DAEMON="$REPO/$BUILD_DIR/roadied"
    NEW_CLI="$REPO/$BUILD_DIR/roadie"
    if [ ! -x "$NEW_DAEMON" ] || [ ! -x "$NEW_CLI" ]; then
        echo "✗ binaire manquant : $NEW_DAEMON ou $NEW_CLI" >&2
        echo "  relance sans --no-build" >&2
        exit 1
    fi
fi
if [ "$RESTART_RAIL" -eq 1 ]; then
    NEW_RAIL="$REPO/$BUILD_DIR/roadie-rail"
    if [ ! -x "$NEW_RAIL" ]; then
        echo "✗ binaire manquant : $NEW_RAIL" >&2
        echo "  relance sans --no-build" >&2
        exit 1
    fi
fi

# ============================================================================
# Étape 2 : stop (rail d'abord, puis daemon — sinon le rail s'agite à reconnecter).
# ============================================================================
if [ "$RESTART_RAIL" -eq 1 ]; then
    echo "→ stop roadie-rail en cours"
    if pgrep -f "roadie-rail" >/dev/null 2>&1; then
        pkill -f "roadie-rail" || true
        for _ in 1 2 3 4 5; do
            if ! pgrep -f "roadie-rail" >/dev/null 2>&1; then break; fi
            sleep 0.2
        done
        if pgrep -f "roadie-rail" >/dev/null 2>&1; then
            pkill -9 -f "roadie-rail" || true
            sleep 0.3
        fi
        rm -f "$HOME/.roadies/rail.pid" 2>/dev/null || true
        echo "  ✓ rail stoppé"
    else
        echo "  (aucun rail en cours)"
    fi
fi

if [ "$RESTART_DAEMON" -eq 1 ]; then
    echo "→ stop daemon en cours"
    # `pkill -x roadied` matche le NOM du process (basename de l'exec), pas les
    # args ni le path — capture donc les daemons lancés d'ailleurs (ex.
    # ~/.local/bin/roadied d'une session précédente). Le ciblage par args
    # (`-f "roadied --daemon"`) ratait ces zombies → 2 daemons en parallèle =
    # AX events doublés + layout race condition.
    if pgrep -x roadied >/dev/null 2>&1; then
        N=$(pgrep -x roadied | wc -l | tr -d ' ')
        [ "$N" -gt 1 ] && echo "  ⚠ $N daemons détectés, kill all"
        pkill -x roadied || true
        for _ in 1 2 3 4 5; do
            if ! pgrep -x roadied >/dev/null 2>&1; then break; fi
            sleep 0.3
        done
        if pgrep -x roadied >/dev/null 2>&1; then
            echo "  daemon ne s'est pas arrêté, force kill"
            pkill -9 -x roadied || true
            sleep 0.5
        fi
        echo "  ✓ daemon stoppé"
    else
        echo "  (aucun daemon en cours)"
    fi
fi

# ============================================================================
# Étape 3 : deploy + codesign.
# Re-codesign après cp : macOS Tahoe (codeSigningMonitor=2) invalide la signature
# embarquée quand le binaire est copié → SIGKILL "Code Signature Invalid".
# ============================================================================
if [ "$RESTART_DAEMON" -eq 1 ]; then
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
fi

if [ "$RESTART_RAIL" -eq 1 ]; then
    echo ""
    echo "→ deploy roadie-rail → $RAIL_BIN"
    mkdir -p "$(dirname "$RAIL_BIN")"
    cp "$NEW_RAIL" "$RAIL_BIN"
    codesign --force --sign - "$RAIL_BIN" 2>&1 | grep -v "replacing existing signature" || true
    echo "  ✓ $(ls -la "$RAIL_BIN" | awk '{print $5, $6, $7, $8}')"
fi

# ============================================================================
# Étape 4 : avertir si la config a une section legacy.
# ============================================================================
if [ "$RESTART_DAEMON" -eq 1 ] && grep -q '^\[multi_desktop\]' "$HOME/.config/roadies/roadies.toml" 2>/dev/null; then
    echo ""
    echo "⚠  ~/.config/roadies/roadies.toml contient encore [multi_desktop] (SPEC-003 deprecated)."
    echo "   Remplace par [desktops] enabled=true (cf. SPEC-011 quickstart)."
fi

# ============================================================================
# Étape 5 : start (daemon d'abord — le rail dépend du socket daemon).
# ============================================================================
# Instrumentation crash SIGSEGV pool drain (objc_release dans autoreleasePoolPop).
# Off par défaut depuis la fix `0c41ff1` (autoreleasepool dans SCKCaptureService).
# Réactiver via --zombie si un nouveau crash NSWindow release apparaît.
# - NSZombieEnabled              : transforme dealloc en zombie pour intercepter le double-release
# - MallocStackLogging           : enregistre le site d'allocation
# - MallocStackLoggingNoCompact  : stacks complètes (sinon tronquées, illisibles)
# - MallocScribble               : remplit la mémoire libérée de 0x55 → crash plus tôt et plus net
# - NSAutoreleaseFreedObjectCheckEnabled : vérifie chaque release dans le pool drain
# Impact mémoire ~2-3x, perf -10 à -20%.
if [ "$RESTART_DAEMON" -eq 1 ]; then
    echo ""
    if [ "$ZOMBIE" -eq 1 ]; then
        echo "→ start daemon (NSZombie ON)"
        nohup env \
            NSZombieEnabled=YES \
            MallocStackLogging=1 \
            MallocStackLoggingNoCompact=1 \
            MallocScribble=1 \
            NSAutoreleaseFreedObjectCheckEnabled=YES \
            "$APP_BIN" --daemon > "$LOG" 2>&1 &
    else
        echo "→ start daemon"
        nohup "$APP_BIN" --daemon > "$LOG" 2>&1 &
    fi
    DAEMON_PID=$!
    disown "$DAEMON_PID" 2>/dev/null || true

    sleep 0.5
    if kill -0 "$DAEMON_PID" 2>/dev/null; then
        echo "  ✓ daemon up, PID=$DAEMON_PID"
        echo "  log : tail -f $LOG"
    else
        echo "✗ daemon a quitté immédiatement, voir $LOG :" >&2
        tail -20 "$LOG" >&2
        exit 1
    fi
fi

if [ "$RESTART_RAIL" -eq 1 ]; then
    echo ""
    echo "→ start rail"
    # Si on relance juste le rail (pas le daemon), s'assurer qu'un daemon tourne avant.
    if [ "$RESTART_DAEMON" -eq 0 ] && ! pgrep -f "roadied --daemon" >/dev/null 2>&1; then
        echo "  ⚠ aucun daemon en cours — le rail va afficher 'daemon offline'"
        echo "    relance avec --all ou démarre roadied séparément."
    fi
    nohup "$RAIL_BIN" > "$RAIL_LOG" 2>&1 &
    RAIL_PID=$!
    disown "$RAIL_PID" 2>/dev/null || true

    sleep 0.5
    if kill -0 "$RAIL_PID" 2>/dev/null; then
        echo "  ✓ rail up, PID=$RAIL_PID"
        echo "  log : tail -f $RAIL_LOG"
    else
        echo "✗ rail a quitté immédiatement, voir $RAIL_LOG :" >&2
        tail -20 "$RAIL_LOG" >&2
        exit 1
    fi
fi

# ============================================================================
# Étape 6 : sanity check (uniquement si daemon redémarré).
# ============================================================================
if [ "$RESTART_DAEMON" -eq 1 ]; then
    echo ""
    echo "→ sanity check : roadie desktop list"
    sleep 0.5
    "$CLI_BIN" desktop list 2>&1 | head -10 || echo "  (commande indisponible — config peut être [desktops] enabled=false)"
fi

echo ""
echo "✓ restart terminé"
