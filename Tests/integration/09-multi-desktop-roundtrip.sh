#!/usr/bin/env bash
# T125b — Test de fidélité 100 cycles round-trip A↔B (SC-002).
# Crée 2 stages avec 3 fenêtres chacun sur desktop A, bascule 100 fois A↔B,
# vérifie à chaque retour que les frames sont à ±2px et que le stage actif est identique.
set -euo pipefail

CYCLES=${CYCLES:-100}
TOLERANCE=${TOLERANCE:-2}

echo "[09] roundtrip $CYCLES cycles, tolérance ±${TOLERANCE}px"
echo "    Pré-requis : daemon roadied + 2 desktops macOS + 3 fenêtres tilées sur desktop A"
echo "    À compléter : capture frames AVANT, switch loop, capture APRÈS, comparaison"
echo "    Squelette pour Phase 7 polish, completion manuelle nécessaire"
exit 0
