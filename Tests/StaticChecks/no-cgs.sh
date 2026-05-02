#!/bin/sh
# Détecte tout import ou usage runtime de SkyLight/CGS/SLS dans RoadieDesktops.
# Exclut les lignes de commentaires (// ou /* */) qui mentionnent ces termes
# dans la doc.
hits=""
for f in $(git ls-files Sources/RoadieDesktops/ 2>/dev/null); do
    if grep -vE '^\s*(//|\*|/\*)' "$f" 2>/dev/null | grep -qE 'CGS|SLS|SkyLight'; then
        hits="$hits$f\n"
    fi
done
if [ -n "$hits" ]; then
  echo "ERROR : SkyLight/CGS leak in RoadieDesktops :"
  printf "$hits"
  exit 1
fi
exit 0
