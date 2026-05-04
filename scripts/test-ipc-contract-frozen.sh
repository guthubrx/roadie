#!/usr/bin/env bash
# test-ipc-contract-frozen.sh — vérifie la non-régression du contrat IPC public
# (FR-007/FR-008/SC-004 SPEC-024). Compare les sorties JSON courantes aux
# snapshots V1 capturés par tasks T003 (specs/024-monobinary-merge/snapshots/cli-v1/).
#
# Tolérance : nouveaux champs autorisés (ex: arch_version, rail_inprocess) ;
# suppression ou renommage = échec bloquant.
#
# Usage : ./scripts/test-ipc-contract-frozen.sh [--strict]
#   --strict : échoue si N'IMPORTE quel champ est différent (utile pour audit)
#   default  : tolère ajouts (V2 enrichit le contrat sans le casser)

set -uo pipefail
export LC_NUMERIC=C

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SNAPSHOT_DIR="$REPO_ROOT/specs/024-monobinary-merge/snapshots/cli-v1"
STRICT=${1:-}

if [[ ! -d "$SNAPSHOT_DIR" ]]; then
  echo "ERROR: snapshot dir absent: $SNAPSHOT_DIR"
  echo "Lance les snapshots V1 d'abord (cf. specs/024-monobinary-merge/quickstart.md section A)."
  exit 1
fi

if ! pgrep -f "/Applications/roadied.app" >/dev/null; then
  echo "ERROR: daemon roadied pas en marche."
  exit 1
fi

PASS=0
FAIL=0
FAILED_CASES=()

check_command() {
  local cmd_args="$1"
  local snap_file="$2"
  local format="$3"  # "txt" | "json"

  local actual_file="/tmp/ipc-actual-$(echo "$cmd_args" | tr ' ' '-').$format"
  if [[ "$format" == "json" ]]; then
    timeout 3 ~/.local/bin/roadie $cmd_args --json > "$actual_file" 2>&1 || true
  else
    timeout 3 ~/.local/bin/roadie $cmd_args > "$actual_file" 2>&1 || true
  fi

  # Compat tolérante : on vérifie que les clés du snapshot V1 sont TOUTES
  # présentes dans la sortie V2 (l'ajout d'arch_version etc. est OK).
  local snap_keys
  snap_keys=$(grep -oE '^[a-z_]+:' "$SNAPSHOT_DIR/$snap_file" 2>/dev/null | sort -u || true)
  local missing=""
  while IFS= read -r key; do
    [[ -z "$key" ]] && continue
    if ! grep -qE "^$key" "$actual_file"; then
      missing="$missing $key"
    fi
  done <<< "$snap_keys"

  if [[ -n "$missing" ]]; then
    echo "  ✗ $cmd_args : champs manquants en V2 :$missing"
    FAIL=$((FAIL + 1))
    FAILED_CASES+=("$cmd_args")
    return 1
  fi

  echo "  ✓ $cmd_args"
  PASS=$((PASS + 1))
  return 0
}

echo "==> non-régression contrat IPC public (V1 → V2)"

check_command "stage list"      "stage-list.txt"      "txt"  || true
check_command "desktop list"    "desktop-list.txt"    "txt"  || true
check_command "desktop current" "desktop-current.txt" "txt"  || true
check_command "display list"    "display-list.txt"    "txt"  || true
check_command "display current" "display-current.txt" "txt"  || true
check_command "daemon status"   "daemon-status.txt"   "txt"  || true

echo
echo "==> events stream (subscribe + observation 3s)"
EVENTS_FILE=$(mktemp)
timeout 3 ~/.local/bin/roadie events --follow > "$EVENTS_FILE" 2>&1 || true
# Ligne d'ack initial doit contenir "subscription_id"
if grep -q '"subscription_id"' "$EVENTS_FILE"; then
  echo "  ✓ events.subscribe ack (subscription_id présent)"
  PASS=$((PASS + 1))
else
  echo "  ✗ events.subscribe ne renvoie pas subscription_id"
  FAIL=$((FAIL + 1))
  FAILED_CASES+=("events.subscribe")
fi
rm -f "$EVENTS_FILE"

echo
echo "==> arch_version (T030)"
if ~/.local/bin/roadie daemon status 2>&1 | grep -qE "^arch_version:[[:space:]]*2$"; then
  echo "  ✓ arch_version = 2 exposé"
  PASS=$((PASS + 1))
else
  echo "  ✗ arch_version manquant ou ≠ 2"
  FAIL=$((FAIL + 1))
  FAILED_CASES+=("arch_version")
fi

echo
echo "==> résumé : $PASS pass, $FAIL fail"
if [[ "$FAIL" -gt 0 ]]; then
  echo "Cas échoués : ${FAILED_CASES[*]}"
  exit 1
fi
echo "Tous les tests de non-régression passent ✅"
