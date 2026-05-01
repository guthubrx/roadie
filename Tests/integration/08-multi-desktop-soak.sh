#!/usr/bin/env bash
# Soak test multi-desktop + robustesse SIGTERM (T125 + T124).
#
# Phase 1 (T125) : 50+ transitions sur 1h via osascript, asserte 0 crash.
# Phase 2 (T124) : SIGTERM le daemon en plein switch, redémarre, vérifie
#                  qu'aucun fichier .toml.tmp n'est laissé (atomicité préservée).
#
# Pré-requis : 2+ desktops macOS, daemon roadied lancé avec multi_desktop.enabled=true.
# Couvre SC-009 partiellement (24h = à compléter manuellement).

set -euo pipefail

DURATION_SEC=${DURATION_SEC:-3600}   # 1h par défaut
INTERVAL_SEC=${INTERVAL_SEC:-60}     # ≥ 60 transitions pour 1h

PASS=0
FAIL=0
assert() {
    local name="$1"; local cond="$2"
    if eval "$cond"; then echo "  ✓ $name"; PASS=$((PASS+1));
    else echo "  ✗ $name (cond: $cond)"; FAIL=$((FAIL+1)); fi
}

# --- Phase 1 : soak ---
echo "[08] T125 — soak : $DURATION_SEC sec, switch toutes les $INTERVAL_SEC sec"

if ! pgrep -x roadied > /dev/null; then
    echo "  SKIP : daemon roadied non lancé"
    exit 0
fi

START=$(date +%s)
END=$((START + DURATION_SEC))
COUNT=0
while [ $(date +%s) -lt $END ]; do
    if ! pgrep -x roadied > /dev/null; then
        echo "[08] FAIL : roadied a crashé après $COUNT switches"
        exit 1
    fi
    osascript -e 'tell application "System Events" to key code 124 using control down' || true
    COUNT=$((COUNT + 1))
    sleep "$INTERVAL_SEC"
done
assert "daemon vivant après $COUNT switches" "pgrep -x roadied > /dev/null"

# --- Phase 2 : SIGTERM atomicité (T124) ---
echo "[08] T124 — SIGTERM en plein switch + assertion zéro .tmp"

DESKTOPS_DIR="$HOME/.config/roadies/desktops"

# Trigger un switch puis SIGTERM rapide (< 100 ms après).
# L'idée : intercepter le moment où le daemon écrit le state d'un desktop.
osascript -e 'tell application "System Events" to key code 124 using control down' &
sleep 0.05
DAEMON_PID=$(pgrep -x roadied | head -1)
if [ -n "$DAEMON_PID" ]; then
    kill -TERM "$DAEMON_PID" 2>/dev/null || true
    # Attendre la mort
    for _ in 1 2 3 4 5; do
        if ! kill -0 "$DAEMON_PID" 2>/dev/null; then break; fi
        sleep 0.2
    done
fi

# Vérifier qu'aucun .tmp ne traîne
TMP_LEFTOVER=$(find "$DESKTOPS_DIR" -name '*.tmp' 2>/dev/null | wc -l | tr -d ' ')
assert "aucun fichier .tmp résiduel après SIGTERM" "[ \"$TMP_LEFTOVER\" = \"0\" ]"

# Optionnel : redémarrer le daemon et vérifier qu'il boot sans crash.
# (Décommenter si tu as un mécanisme de relance auto type launchctl)
# launchctl kickstart -k gui/$UID/local.roadies.daemon
# sleep 1
# assert "daemon reboot OK" "pgrep -x roadied > /dev/null"

# --- Bilan ---
echo ""
echo "[08] Bilan : $PASS passed, $FAIL failed (soak: $COUNT switches)"
[ "$FAIL" -eq 0 ]
