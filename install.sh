#!/usr/bin/env bash
# Copyright 2026 John Casey
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
# install.sh — install focusguard for the current user (no root needed).

set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

BIN_DIR="$HOME/.local/bin"
LIB_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/focusguard/lib"
DATA_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/focusguard/data"
UNIT_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
CONF_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/focusguard"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/focusguard"
PROJECTS_DIR="$HOME/.claude/projects"

echo "==> Checking dependencies"
missing=()
for c in find sort jq curl notify-send canberra-gtk-play gdbus systemctl flock; do
  command -v "$c" >/dev/null 2>&1 || missing+=("$c")
done
claude_bin="$(command -v claude || true)"
# claude is only required for the default (hosted) capture backend.
if [ -z "$claude_bin" ] && ! command -v ollama >/dev/null 2>&1; then
  missing+=("claude or ollama (need at least one capture backend)")
fi
if [ "${#missing[@]}" -gt 0 ]; then
  echo "ERROR: missing required commands: ${missing[*]}" >&2
  echo "Install them and re-run. (On Fedora: libnotify, libcanberra-gtk3, jq, glib2, curl)" >&2
  exit 1
fi
[ -n "$claude_bin" ] && echo "    claude: $claude_bin"
command -v ollama >/dev/null 2>&1 && echo "    ollama: $(command -v ollama)"
# pactl is optional: only the audio-in/audio-out presence signals need it. The
# default presence profile uses it for meeting detection, so warn if absent.
if ! command -v pactl >/dev/null 2>&1; then
  echo "    NOTE: pactl not found — audio presence (mic/speaker) signals will be inert."
  echo "          Break guard still works on desktop idle. Install pipewire-utils/pulseaudio-utils to enable them."
fi
# zenity drives the winddown interview popups; the break guard doesn't need it.
if ! command -v zenity >/dev/null 2>&1; then
  echo "    NOTE: zenity not found — the winddown end-of-day interview can't prompt."
  echo "          Break guard/capture are unaffected. Install zenity to use winddown."
fi

echo "==> Installing libs to $LIB_DIR"
mkdir -p "$LIB_DIR"
install -m 0644 "$here"/lib/*.sh "$LIB_DIR/"

echo "==> Installing data to $DATA_DIR"
mkdir -p "$DATA_DIR"
install -m 0644 "$here"/data/grounding.txt "$DATA_DIR/grounding.txt"

echo "==> Installing scripts to $BIN_DIR"
mkdir -p "$BIN_DIR"
for cmd in fg-tick fg-capture fg-afk fg-status fg-pause fg-unpause winddown windup; do
  install -m 0755 "$here/bin/$cmd" "$BIN_DIR/$cmd"
done
# Example winddown save-progress hook, installed to a space-free path so it's easy
# to reference from winddown.env (point WD_SAVE_PROGRESS_CMD at it).
install -m 0755 "$here/contrib/save-progress-hook.sh" "$BIN_DIR/wd-save-progress-hook"
# Remove binaries from earlier releases that used un-prefixed / focusguard-* names,
# so a re-install doesn't leave stale duplicates on the PATH.
rm -f "$BIN_DIR/focusguard-tick" "$BIN_DIR/focusguard-capture" \
      "$BIN_DIR/focusguard-status" "$BIN_DIR/afk" \
      "$BIN_DIR/break-start" "$BIN_DIR/break-done"

echo "==> Installing systemd user units to $UNIT_DIR"
mkdir -p "$UNIT_DIR"
for u in focusguard.service focusguard.timer \
         winddown.service winddown.timer windup.service windup.timer; do
  install -m 0644 "$here/systemd/$u" "$UNIT_DIR/$u"
done

echo "==> Config"
mkdir -p "$CONF_DIR"
if [ -f "$CONF_DIR/focusguard.conf" ]; then
  echo "    keeping existing $CONF_DIR/focusguard.conf"
else
  install -m 0644 "$here/config/focusguard.conf.example" "$CONF_DIR/focusguard.conf"
  # Bake in the resolved claude path so the systemd env doesn't have to find it.
  [ -n "$claude_bin" ] && printf '\nFG_CLAUDE_BIN="%s"\n' "$claude_bin" >> "$CONF_DIR/focusguard.conf"
  # If claude is absent but ollama is present, default to the local backend.
  if [ -z "$claude_bin" ] && command -v ollama >/dev/null 2>&1; then
    printf 'FG_LLM_BACKEND="ollama"\n' >> "$CONF_DIR/focusguard.conf"
    echo "    (no claude found -> defaulting capture backend to ollama)"
  fi
  echo "    wrote $CONF_DIR/focusguard.conf"
fi

echo "==> Seeding capture baseline (existing sessions won't be back-captured)"
mkdir -p "$STATE_DIR/captured" "$STATE_DIR/work"
if [ -d "$PROJECTS_DIR" ]; then
  while read -r m file; do
    sid="$(basename "$file" .jsonl)"
    printf '%s\n' "${m%.*}" > "$STATE_DIR/captured/$sid"
  done < <(find "$PROJECTS_DIR" -mindepth 2 -maxdepth 2 -name '*.jsonl' \
             -printf '%T@ %p\n' 2>/dev/null)
fi

echo "==> Enabling timers"
systemctl --user daemon-reload
# Make the desktop session env (dbus/wayland) available to the services.
systemctl --user import-environment DISPLAY WAYLAND_DISPLAY XDG_RUNTIME_DIR DBUS_SESSION_BUS_ADDRESS 2>/dev/null || true
systemctl --user enable --now focusguard.timer winddown.timer windup.timer

echo
echo "Installed. Timers:"
systemctl --user list-timers focusguard.timer winddown.timer windup.timer --no-pager 2>/dev/null | sed -n '1,4p' || true
echo
echo "Make sure $BIN_DIR is on your PATH so 'fg-afk' works everywhere."
echo "Check state any time with:  fg-status         (add --log to see detections)"
echo "Step away / can't break:    fg-afk  /  fg-pause"
echo "Test a scan now with:       systemctl --user start focusguard.service"
echo "Try/compare capture with:   fg-capture --compare --latest"
echo "Test winddown now (fast):   WD_INTERVAL_MIN=1 WD_NAG_SEC=20 winddown --now"
echo "To wire save-progress, see: contrib/save-progress-hook.sh + docs/winddown-design.md"
