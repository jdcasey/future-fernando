#!/usr/bin/env bash
# Re-enable the TrackPoint: remove the udev rule installed by fix.sh and reload.
# A dock/USB-less fallback to the nub works again after this (reboot if it does
# not come back live).
set -euo pipefail

RULE=/etc/udev/rules.d/99-disable-trackpoint.rules

if [ "$(id -u)" -ne 0 ]; then
  exec sudo -- "$0" "$@"
fi

if [ -f "$RULE" ]; then
  rm -f "$RULE"
  echo "removed $RULE"
else
  echo "$RULE not present — nothing to undo."
fi

udevadm control --reload-rules
udevadm trigger --subsystem-match=input

echo "rules reloaded. The TrackPoint is re-enabled (reboot if it stays inactive)."
