#!/usr/bin/env bash
# Disable the built-in ThinkPad TrackPoint (pointing stick) so its drift stops
# pinning GNOME's idle counter. See README.md in this directory for the why.
#
# Matches ONLY devices with ID_INPUT_POINTINGSTICK=1 — the nub. Your USB mouse,
# touchpad, and keyboards are untouched. Reversible with undo.sh.
set -euo pipefail

RULE=/etc/udev/rules.d/99-disable-trackpoint.rules

if [ "$(id -u)" -ne 0 ]; then
  exec sudo -- "$0" "$@"
fi

cat > "$RULE" <<'EOF'
# Ignore the built-in TrackPoint (pointing stick) — its drift pins GNOME's idle
# counter, breaking Fern break-crediting. Unused on this machine.
# Installed by Fern cookbook/thinkpad-trackpoint-drift/fix.sh
ENV{ID_INPUT_POINTINGSTICK}=="1", ENV{LIBINPUT_IGNORE_DEVICE}="1"
EOF

echo "wrote $RULE"

udevadm control --reload-rules
udevadm trigger --subsystem-match=input

echo "rules reloaded and re-triggered."
echo "Now run test.sh (hands off the keyboard/mouse). If idle stays pinned low,"
echo "the live device wasn't detached — reboot and test again."
