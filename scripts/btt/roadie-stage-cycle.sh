#!/usr/bin/env bash
# Cycle entre les stages du scope courant (display, desktop) actif.
# Usage : roadie-stage-cycle.sh {next|prev}
#
# `roadie stage next/prev` n'existe pas nativement (interprété comme un stage_id),
# donc on liste les stages et on calcule le voisin.

set -u

ROADIE="${ROADIE_BIN:-$HOME/.local/bin/roadie}"
DIR="${1:-next}"

# Récupérer la liste des stages du scope courant + l'actif.
# Format `roadie stage list` : "Current stage: N\n* N (name) — K window(s)\n  M (name) — K window(s)"
RAW=$("$ROADIE" stage list 2>/dev/null) || exit 1

# Extraire current stage id.
CURRENT=$(echo "$RAW" | awk '/^Current stage:/ { print $3; exit }')

# Extraire la liste ordonnée des ids (toutes les lignes commençant par * ou espaces+digit).
IDS=$(echo "$RAW" | awk '/^[[:space:]]*\*?[[:space:]]*[0-9]+/ { for (i=1; i<=NF; i++) if ($i ~ /^[0-9]+$/) { print $i; break } }')

# Si pas de stages ou un seul, no-op silencieux.
COUNT=$(echo "$IDS" | grep -c .)
[ "$COUNT" -lt 2 ] && exit 0

# Calculer le voisin avec wrap-around.
TARGET=$(echo "$IDS" | awk -v cur="$CURRENT" -v dir="$DIR" '
    { ids[NR] = $1 }
    END {
        n = NR
        for (i = 1; i <= n; i++) {
            if (ids[i] == cur) {
                if (dir == "next") {
                    print (i == n) ? ids[1] : ids[i + 1]
                } else {
                    print (i == 1) ? ids[n] : ids[i - 1]
                }
                exit
            }
        }
        # Current pas trouvé : tomber sur le premier.
        print ids[1]
    }
')

[ -z "$TARGET" ] && exit 0
"$ROADIE" stage "$TARGET" >/dev/null 2>&1
