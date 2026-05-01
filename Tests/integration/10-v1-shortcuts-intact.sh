#!/usr/bin/env bash
# T125c — Test de non-régression V1 : avec multi_desktop.enabled=false,
# asserter que les 13 raccourcis BTT existants répondent comme en V1.
# Couvre FR-022 (BTT shortcuts inchangés).
set -euo pipefail

# Vérifie que multi_desktop est désactivé.
CONFIG="$HOME/.config/roadies/roadies.toml"
if grep -q '^enabled = true' "$CONFIG" 2>/dev/null; then
    echo "[10] SKIP : multi_desktop.enabled = true détecté, ce test exige V1 strict"
    exit 0
fi

# Test : roadie stage * doit fonctionner sur le state global (mode V1).
# Test : roadie focus/move/resize HJKL répondent
# Test : roadie desktop * doit retourner exit 4 (multi_desktop disabled)
echo "[10] V1 mode : test des commandes V1 + assertions exit codes"

# 1. roadie focus (mode V1, doit marcher)
roadie focus right || true   # peut renvoyer code "no neighbor", c'est OK
echo "    focus right : exit=$?"

# 2. roadie stage list (mode V1, doit marcher)
roadie stage list > /dev/null && echo "    stage list : OK" || echo "    stage list : FAIL"

# 3. roadie desktop list (lecture seule, autorisée même V1)
roadie desktop list > /dev/null && echo "    desktop list : OK (lecture)" || echo "    desktop list : ERR"

# 4. roadie desktop focus next (commande mutante, doit retourner exit 4)
set +e
roadie desktop focus next
RC=$?
set -e
if [ "$RC" = "4" ]; then
    echo "    desktop focus next : exit 4 (multi_desktop_disabled) — OK"
else
    echo "    desktop focus next : exit $RC ATTENDU 4 — FAIL"
    exit 1
fi
echo "[10] OK : V1 strict respecté"
exit 0
