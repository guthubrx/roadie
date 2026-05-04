#!/usr/bin/env bash
# bench-dev-cycle.sh — chronomètre N itérations de `swift build && install-dev.sh`
# pour mesurer le SC-002 de SPEC-024 (cycle dev V2 ≥ 25% plus court que V1).
#
# Usage : ./scripts/bench-dev-cycle.sh [N]   # default N=5
# Output : durations en seconde + moyenne, médiane, p95.

set -euo pipefail
export LC_NUMERIC=C

N=${1:-5}
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

export PATH="/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin:$PATH"

declare -a DURATIONS
echo "==> bench dev cycle ($N itérations)"

for i in $(seq 1 "$N"); do
  echo "  iter $i..."
  start=$(date +%s.%N)

  # 1. swift build (incrémental, no-clean — match flot dev usuel)
  swift build >/dev/null 2>&1

  # 2. install-dev.sh --no-build (cp + codesign + bootstrap)
  ./scripts/install-dev.sh --no-build >/dev/null 2>&1

  # 3. attendre que le daemon réponde (= cycle dev terminé pour le user)
  for _ in $(seq 1 30); do
    if timeout 1 ~/.local/bin/roadie daemon status >/dev/null 2>&1; then break; fi
    sleep 0.2
  done

  end=$(date +%s.%N)
  d=$(echo "$end - $start" | bc -l)
  DURATIONS+=("$d")
  printf "    %.2fs\n" "$d"
done

echo "==> stats (s)"
printf '%s\n' "${DURATIONS[@]}" | sort -n > /tmp/bench-dev.tmp
total=$(printf '%s\n' "${DURATIONS[@]}" | paste -sd+ - | bc -l)
mean=$(echo "scale=2; $total / $N" | bc -l)
median=$(awk -v n="$N" 'NR == int((n+1)/2) {print}' /tmp/bench-dev.tmp)
p95_idx=$(echo "scale=0; ($N * 95 + 99) / 100" | bc)
p95=$(sed -n "${p95_idx}p" /tmp/bench-dev.tmp)
rm -f /tmp/bench-dev.tmp

printf "  mean   : %.2fs\n" "$mean"
printf "  median : %.2fs\n" "$median"
printf "  p95    : %.2fs\n" "$p95"
echo
echo "Sauvegarder ce résultat dans specs/024-monobinary-merge/bench-dev-cycle.log si baseline."
