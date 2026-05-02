#!/bin/sh
hits=$(git ls-files Sources/RoadieDesktops/ 2>/dev/null | xargs grep -lE 'CGS|SLS|SkyLight' 2>/dev/null)
if [ -n "$hits" ]; then
  echo "ERROR : SkyLight/CGS leak in RoadieDesktops :"
  echo "$hits"
  exit 1
fi
exit 0
