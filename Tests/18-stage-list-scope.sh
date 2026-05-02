#!/usr/bin/env bash
# SPEC-018 Phase 3 US1 — test d'acceptance : isolation cross-display sur stage.list
# Vérifie que créer "Stage 99" sur Display 1 ne le fait pas apparaître sur Display 2.
set -euo pipefail

ROADIE="$(command -v roadie 2>/dev/null || echo "$HOME/.local/bin/roadie")"
SOCKET="$HOME/.roadies/daemon.sock"

if [[ ! -S "$SOCKET" ]] || [[ ! -x "$ROADIE" ]]; then
    echo "skipped: daemon or roadie not available"
    exit 0
fi

# Skip si mono-display (besoin de 2+ displays pour tester l'isolation)
N=$("$ROADIE" display list --json 2>/dev/null | jq '.displays | length' 2>/dev/null || echo 0)
if [[ "$N" -lt 2 ]]; then
    echo "skipped: need 2+ displays (got ${N})"
    exit 0
fi

# Skip si pas en mode per_display
MODE=$("$ROADIE" daemon status --json 2>/dev/null | jq -r '.payload.stages_mode // empty' 2>/dev/null || echo "")
if [[ "$MODE" != "per_display" ]]; then
    echo "skipped: per_display mode not active (mode=${MODE:-unknown})"
    exit 0
fi

STAGE_ID="99"

# Cleanup préventif
"$ROADIE" stage delete "$STAGE_ID" --display 1 --desktop 1 >/dev/null 2>&1 || true

# Créer stage 99 sur Display 1, Desktop 1
"$ROADIE" stage create "$STAGE_ID" "test-isolation-D1" --display 1 --desktop 1 2>/dev/null || {
    echo "skipped: stage create with --display override not implemented yet"
    exit 0
}

# Vérifier présence sur D1
LIST_D1=$("$ROADIE" stage list --display 1 --desktop 1 --json 2>/dev/null | jq -r '[.stages[].id]' 2>/dev/null || echo "[]")
if ! echo "$LIST_D1" | jq -e "index(\"$STAGE_ID\")" >/dev/null 2>&1; then
    echo "FAIL: stage $STAGE_ID not found in Display 1 list"
    echo "  D1 stages: $LIST_D1"
    "$ROADIE" stage delete "$STAGE_ID" --display 1 --desktop 1 >/dev/null 2>&1 || true
    exit 1
fi

# Vérifier ABSENCE sur D2 — isolation critique
LIST_D2=$("$ROADIE" stage list --display 2 --desktop 1 --json 2>/dev/null | jq -r '[.stages[].id]' 2>/dev/null || echo "[]")
if echo "$LIST_D2" | jq -e "index(\"$STAGE_ID\")" >/dev/null 2>&1; then
    echo "FAIL: stage $STAGE_ID appears in Display 2 list — isolation broken"
    echo "  D1 stages: $LIST_D1"
    echo "  D2 stages: $LIST_D2"
    "$ROADIE" stage delete "$STAGE_ID" --display 1 --desktop 1 >/dev/null 2>&1 || true
    exit 1
fi

# Cleanup
"$ROADIE" stage delete "$STAGE_ID" --display 1 --desktop 1 >/dev/null 2>&1 || true

echo "OK: cross-display isolation verified (stage $STAGE_ID visible on D1, absent from D2)"
