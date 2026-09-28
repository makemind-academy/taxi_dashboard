#!/bin/bash
# taxi-dashboard — one meter, driver's and passenger's screens, verified in AppPlayer.
set -euo pipefail
cd "$(dirname "$0")"
echo "   [build] vehicle_bus (C)"
( cd vehicle_bus && cc -O2 -o vehicle_bus vehicle_bus.c -lm )
echo "   [analyze] dashboard_server"
( cd dashboard_server && dart pub get >/dev/null && dart analyze | tail -1 )
echo "   [player] one trip, both screens"
rm -f captures/*.png
python3 verify.py
COUNT=$(ls captures/*.png | wc -l | tr -d ' ')
[ "$COUNT" -eq 8 ] || { echo "   expected 8 captures, got $COUNT"; exit 1; }
