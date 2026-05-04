#!/usr/bin/env bash
# Tests/25-bug001-cycle-hide-switch.sh
# SPEC-025 T074 — test automatisé du scénario BUG-001 :
#   1. Capture l'état actuel des fenêtres tilées
#   2. Force `stage.hide_active` (déplace les fenêtres offscreen via HideStrategy.corner)
#   3. Switch stage A → autre stage
#   4. Switch back vers la stage A
#   5. Vérifier que les fenêtres précédemment hidden ont retrouvé une frame
#      visible (= dans un display connu, Y < primary_height + LG_height)
#
# Si T072 (FR-007 fallback safe) marche, toutes les fenêtres réapparaissent.
# Sinon, ce test FAIL → BUG-001 réapparaît, déclencher SPEC-026 ciblée.

set -uo pipefail
export LC_NUMERIC=C

if ! pgrep -lf roadied >/dev/null 2>&1; then
    echo "FAIL: daemon roadied pas en marche"
    exit 1
fi

CLI=~/.local/bin/roadie

# ===========================================================================
# Setup : identifier la stage active actuelle et les wids tilées
# ===========================================================================
CURRENT_STAGE=$($CLI stage list 2>&1 | awk '/^Current stage:/ {print $3}')
if [ -z "$CURRENT_STAGE" ]; then
    echo "SKIP: stage actuelle introuvable"
    exit 0
fi

# Compter les wids tilées sur la stage active courante.
TILED_BEFORE=$($CLI windows list 2>&1 | grep -cE 'tiled stage='"$CURRENT_STAGE")
if [ "$TILED_BEFORE" -lt 1 ]; then
    echo "SKIP: pas assez de fenêtres tilées sur stage $CURRENT_STAGE pour tester (besoin ≥ 1)"
    exit 0
fi

echo "==> Setup OK : stage active = $CURRENT_STAGE, $TILED_BEFORE fenêtre(s) tilée(s)"

# ===========================================================================
# Étape 1 : déclencher hide_active via IPC
# ===========================================================================
echo "==> Étape 1 : stage.hide_active sur stage $CURRENT_STAGE"
HIDE_RESPONSE=$(echo '{"version":"roadie/1","command":"stage.hide_active"}' | nc -U ~/.roadies/daemon.sock 2>&1)
HIDDEN_COUNT=$(echo "$HIDE_RESPONSE" | python3 -c "
import sys, json
try:
    d = json.loads(sys.stdin.read())
    p = d.get('payload', {})
    print(p.get('hidden_count', 0))
except Exception:
    print(0)
")
echo "    fenêtres hidden : $HIDDEN_COUNT"
sleep 1

# ===========================================================================
# Étape 2 : switch vers une autre stage (créée si besoin)
# ===========================================================================
OTHER_STAGE=$([ "$CURRENT_STAGE" = "1" ] && echo "2" || echo "1")
echo "==> Étape 2 : switch stage $CURRENT_STAGE → $OTHER_STAGE"
$CLI stage "$OTHER_STAGE" >/dev/null 2>&1
sleep 1

# ===========================================================================
# Étape 3 : switch back vers la stage initiale
# ===========================================================================
echo "==> Étape 3 : switch stage $OTHER_STAGE → $CURRENT_STAGE (back)"
$CLI stage "$CURRENT_STAGE" >/dev/null 2>&1
sleep 2  # laisser applyLayout + HideStrategy.show le temps de tourner

# ===========================================================================
# Étape 4 : vérifier que les fenêtres ont retrouvé des frames visibles
# ===========================================================================
echo "==> Étape 4 : vérification frames visibles"
$CLI windows list 2>&1 | grep "stage=$CURRENT_STAGE" > /tmp/test25-windows.txt

OFFSCREEN_AFTER=0
while IFS= read -r line; do
    # extrait le Y du frame "X,Y WxH"
    y=$(echo "$line" | grep -oE '[-]?[0-9]+,[-]?[0-9]+' | head -1 | cut -d, -f2)
    if [ -n "$y" ]; then
        # heuristique : Y < -3000 ou Y > 5000 = clairement offscreen
        if [ "$y" -lt -3000 ] 2>/dev/null || [ "$y" -gt 5000 ] 2>/dev/null; then
            OFFSCREEN_AFTER=$((OFFSCREEN_AFTER + 1))
            echo "  FAIL OFFSCREEN: $line"
        fi
    fi
done < /tmp/test25-windows.txt
rm -f /tmp/test25-windows.txt

# ===========================================================================
# Verdict
# ===========================================================================
if [ "$OFFSCREEN_AFTER" -eq 0 ]; then
    echo "PASS: BUG-001 fix FR-007 holds — aucune fenêtre coincée offscreen après cycle"
    exit 0
else
    echo "FAIL: $OFFSCREEN_AFTER fenêtre(s) coincée(s) offscreen après cycle hide+switch"
    echo "      → BUG-001 réapparaît malgré FR-007. Déclencher SPEC-026 ciblée."
    echo "      → Examiner ~/.local/state/roadies/daemon.log pour les events :"
    echo "         - hide_strategy_show_fallback_center"
    echo "         - setLeafVisible_no_leaf_found"
    exit 1
fi
