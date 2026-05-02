#!/bin/sh
# Détecte tout import ou usage runtime de SkyLight/CGS/SLS dans les modules
# qui ne doivent pas en avoir : RoadieDesktops + fichiers Display* SPEC-012.
# Exclut les lignes de commentaires (// ou /* */) qui mentionnent ces termes
# dans la doc.
#
# Périmètre SPEC-011 : Sources/RoadieDesktops/
# Périmètre SPEC-012 : Sources/RoadieCore/Display.swift
#                      Sources/RoadieCore/DisplayRegistry.swift
#                      Sources/RoadieCore/DisplayProvider.swift
PERIMETER="Sources/RoadieDesktops/ Sources/RoadieCore/Display.swift Sources/RoadieCore/DisplayRegistry.swift Sources/RoadieCore/DisplayProvider.swift"
hits=""
for f in $(git ls-files $PERIMETER 2>/dev/null); do
    if grep -vE '^\s*(//|\*|/\*)' "$f" 2>/dev/null | grep -qE 'CGS|SLS|SkyLight'; then
        hits="$hits$f\n"
    fi
done
if [ -n "$hits" ]; then
  echo "ERROR : SkyLight/CGS leak in restricted modules :"
  printf "$hits"
  exit 1
fi
exit 0
