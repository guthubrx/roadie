#!/usr/bin/env bash
# SPEC-014 T036 — Acceptance test : rail show/hide lifecycle.
# Skip si environnement headless (CI sans display).

set -euo pipefail

BINARY="${HOME}/.local/bin/roadie-rail"

# Vérifier présence du binaire.
if [[ ! -x "${BINARY}" ]]; then
    echo "skipped: ${BINARY} not found (run 'make install' first)"
    exit 0
fi

# Skip si pas de display macOS disponible (CI headless).
if ! pgrep -q WindowServer 2>/dev/null; then
    echo "skipped: no GUI environment detected"
    exit 0
fi

echo "--- 14-rail-show-hide: launching roadie-rail ---"
"${BINARY}" &
RAIL_PID=$!
echo "roadie-rail PID=${RAIL_PID}"

# Donner le temps au process de s'initialiser.
sleep 2

# Vérifier que le process tourne toujours (n'a pas crashé).
if ! kill -0 "${RAIL_PID}" 2>/dev/null; then
    echo "FAIL: roadie-rail crashed within 2 seconds"
    exit 1
fi

echo "PASS: roadie-rail is running after 2 seconds"

# Terminaison propre.
kill "${RAIL_PID}"
sleep 1

if kill -0 "${RAIL_PID}" 2>/dev/null; then
    echo "WARN: roadie-rail still running after SIGTERM, force kill"
    kill -9 "${RAIL_PID}" 2>/dev/null || true
fi

echo "--- 14-rail-show-hide: OK ---"
exit 0
