#!/bin/bash
# SPEC-019 — Tests acceptance CLI rail renderer / renderers
# Précondition : daemon démarré, binaires installés.

set -euo pipefail

ROADIE="${ROADIE:-./.build/debug/roadie}"

# T1 : list contient au moins le défaut
$ROADIE rail renderers list | grep -q "stacked-previews"
echo "T1 list contient stacked-previews — OK"

# T2 : set vers icons-only réussit (US2 livré)
$ROADIE rail renderer icons-only | grep -q "current: icons-only"
echo "T2 set icons-only — OK"

# T3 : list montre maintenant icons-only comme current
$ROADIE rail renderers list | grep -q "current: icons-only"
echo "T3 current=icons-only — OK"

# T4 : set vers id inconnu retourne exit non-zéro
if $ROADIE rail renderer parallax-99 >/dev/null 2>&1; then
    echo "T4 FAIL: should have failed on unknown id"; exit 1
fi
echo "T4 unknown id rejected — OK"

# T5 : set vers défaut explicit
$ROADIE rail renderer stacked-previews >/dev/null
echo "T5 set back stacked-previews — OK"

# T6 : config TOML mise à jour
grep -q 'renderer = "stacked-previews"' ~/.config/roadies/roadies.toml
echo "T6 TOML updated — OK"

echo ""
echo "All acceptance tests PASS"
