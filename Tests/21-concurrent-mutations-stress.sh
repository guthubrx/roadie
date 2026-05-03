#!/usr/bin/env bash
# SPEC-021 T065 — Stress test mutations concurrentes.
# Déclenche 100 transitions stage/desktop en < 5s, puis vérifie que
# `roadie daemon audit` retourne 0 violation.
#
# Prérequis : daemon roadied tournant, mode per_display activé, ≥ 2 stages existants.
# Usage     : ./Tests/21-concurrent-mutations-stress.sh
# Résultat  : EXIT 0 si audit healthy après stress, sinon liste les violations.

set -euo pipefail

ROADIE="${ROADIE:-roadie}"
N="${N:-100}"

if ! command -v "$ROADIE" >/dev/null; then
    echo "SKIP: $ROADIE binaire introuvable. Lance ./scripts/install-dev.sh d'abord."
    exit 0
fi

# Vérifier que le daemon répond.
if ! "$ROADIE" daemon status >/dev/null 2>&1; then
    echo "SKIP: daemon roadied pas en cours d'exécution."
    exit 0
fi

echo "Stress test : $N transitions stage 1↔2 en < 5s..."
START=$SECONDS
for i in $(seq 1 "$N"); do
    if (( i % 2 == 0 )); then
        "$ROADIE" stage 1 >/dev/null 2>&1 || true
    else
        "$ROADIE" stage 2 >/dev/null 2>&1 || true
    fi
done
ELAPSED=$((SECONDS - START))
echo "Done in ${ELAPSED}s ($((N / (ELAPSED + 1))) ops/s)"

# Audit ownership : vérifier 0 violation.
AUDIT_JSON=$("$ROADIE" daemon audit 2>&1 || true)
if echo "$AUDIT_JSON" | grep -q '"healthy":\s*true\|"count":\s*0'; then
    echo "PASS: ownership invariants healthy after stress"
    exit 0
else
    echo "FAIL: violations détectées :"
    echo "$AUDIT_JSON"
    exit 1
fi
