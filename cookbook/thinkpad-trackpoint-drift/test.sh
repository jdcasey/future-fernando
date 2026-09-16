#!/usr/bin/env bash
# Functional test: with your hands OFF the keyboard and mouse, GNOME's idle
# counter should climb steadily. If it stays pinned near zero, phantom input
# (TrackPoint drift) is still resetting it — the fix has not taken (reboot), or
# a different device is drifting (see README.md).
#
# No sudo needed — this only reads the session idle counter.
set -euo pipefail

SAMPLES=5
INTERVAL=4   # seconds between samples

idle_ms() {
  gdbus call --session \
    --dest org.gnome.Mutter.IdleMonitor \
    --object-path /org/gnome/Mutter/IdleMonitor/Core \
    --method org.gnome.Mutter.IdleMonitor.GetIdletime \
    | grep -oE '[0-9]+' | head -n1
}

if ! command -v gdbus >/dev/null; then
  echo "gdbus not found — this test needs GNOME/Mutter on the session bus." >&2
  exit 2
fi

echo ">>> Take your hands off the keyboard and mouse now."
echo ">>> Sampling idle time for ~$(( SAMPLES * INTERVAL ))s ..."
echo

first=""; last=""
for i in $(seq 1 "$SAMPLES"); do
  v=$(idle_ms 2>/dev/null || echo "")
  if [ -z "$v" ]; then
    echo "  sample $i: <no reading>"
  else
    printf '  sample %d: idle = %5d ms\n' "$i" "$v"
    [ -z "$first" ] && first="$v"
    last="$v"
  fi
  [ "$i" -lt "$SAMPLES" ] && sleep "$INTERVAL"
done

echo
if [ -z "$first" ] || [ -z "$last" ]; then
  echo "INCONCLUSIVE: could not read the idle counter."
  exit 2
fi

# Expect idle to grow by roughly the elapsed time if nothing is drifting.
# Allow generous slack; a healthy climb is the whole point.
grew=$(( last - first ))
threshold=$(( (SAMPLES - 1) * INTERVAL * 1000 / 2 ))   # half of ideal growth

if [ "$grew" -ge "$threshold" ]; then
  echo "PASS: idle climbed ${grew} ms over the window — no drift detected."
  exit 0
else
  echo "FAIL: idle only moved ${grew} ms — it is being reset."
  echo "  - If you did NOT touch input: the fix has not taken. Reboot, retest."
  echo "  - If still failing after reboot: another device may be drifting"
  echo "    (e.g. the touchpad). See README.md."
  exit 1
fi
