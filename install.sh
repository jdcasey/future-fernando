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
# install.sh — install Fern for the current user (no root needed).

set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

BIN_DIR="$HOME/.local/bin"
LIB_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/fftf/lib"
DATA_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/fftf/data"
UNIT_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
CONF_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/fftf"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/fftf"
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

# Retire units and binaries from the pre-Fern layout (focusguard / fg-* / winddown
# / windup) so a re-install or rename migration doesn't leave stale duplicates
# running or on the PATH.
echo "==> Retiring pre-Fern units and scripts (if present)"
systemctl --user disable --now focusguard.timer winddown.timer windup.timer 2>/dev/null || true
rm -f "$UNIT_DIR/focusguard.service" "$UNIT_DIR/focusguard.timer" \
      "$UNIT_DIR/winddown.service" "$UNIT_DIR/winddown.timer" \
      "$UNIT_DIR/windup.service" "$UNIT_DIR/windup.timer"
rm -f "$BIN_DIR/fg-tick" "$BIN_DIR/fg-capture" "$BIN_DIR/fg-afk" \
      "$BIN_DIR/fg-status" "$BIN_DIR/fg-pause" "$BIN_DIR/fg-unpause" \
      "$BIN_DIR/winddown" "$BIN_DIR/windup" "$BIN_DIR/wd-save-progress-hook"
# even older names from before the fg-* prefix
rm -f "$BIN_DIR/focusguard-tick" "$BIN_DIR/focusguard-capture" \
      "$BIN_DIR/focusguard-status" "$BIN_DIR/afk" \
      "$BIN_DIR/break-start" "$BIN_DIR/break-done"

echo "==> Installing libs to $LIB_DIR"
mkdir -p "$LIB_DIR"
install -m 0644 "$here"/lib/*.sh "$LIB_DIR/"

echo "==> Installing data to $DATA_DIR"
mkdir -p "$DATA_DIR"
install -m 0644 "$here"/data/grounding.txt "$DATA_DIR/grounding.txt"

echo "==> Installing scripts to $BIN_DIR"
mkdir -p "$BIN_DIR"
for cmd in fftf-tick fftf-capture fftf-afk fftf-status fftf-pause fftf-unpause fftf-winddown fftf-windup; do
  install -m 0755 "$here/bin/$cmd" "$BIN_DIR/$cmd"
done
# Example winddown save-progress hook, installed to a space-free path so it's easy
# to reference from fftf-winddown.env (point FFTF_SAVE_PROGRESS_CMD at it).
install -m 0755 "$here/contrib/save-progress-hook.sh" "$BIN_DIR/fftf-save-progress-hook"

echo "==> Installing systemd user units to $UNIT_DIR"
mkdir -p "$UNIT_DIR"
for u in fftf.service fftf.timer \
         fftf-winddown.service fftf-winddown.timer fftf-windup.service fftf-windup.timer; do
  install -m 0644 "$here/systemd/$u" "$UNIT_DIR/$u"
done

echo "==> Config"
mkdir -p "$CONF_DIR"
if [ -f "$CONF_DIR/fftf.conf" ]; then
  echo "    keeping existing $CONF_DIR/fftf.conf"
else
  install -m 0644 "$here/config/fftf.conf.example" "$CONF_DIR/fftf.conf"
  # Bake in the resolved claude path so the systemd env doesn't have to find it.
  [ -n "$claude_bin" ] && printf '\nFFTF_CLAUDE_BIN="%s"\n' "$claude_bin" >> "$CONF_DIR/fftf.conf"
  # If claude is absent but ollama is present, default to the local backend.
  if [ -z "$claude_bin" ] && command -v ollama >/dev/null 2>&1; then
    printf 'FFTF_LLM_BACKEND="ollama"\n' >> "$CONF_DIR/fftf.conf"
    echo "    (no claude found -> defaulting capture backend to ollama)"
  fi
  echo "    wrote $CONF_DIR/fftf.conf"
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
systemctl --user enable --now fftf.timer fftf-winddown.timer fftf-windup.timer

echo
echo "Installed. Timers:"
systemctl --user list-timers fftf.timer fftf-winddown.timer fftf-windup.timer --no-pager 2>/dev/null | sed -n '1,4p' || true
echo
echo "Make sure $BIN_DIR is on your PATH so 'fftf-afk' works everywhere."
echo "Check state any time with:  fftf-status       (add --log to see detections)"
echo "Step away / can't break:    fftf-afk  /  fftf-pause"
echo "Test a scan now with:       systemctl --user start fftf.service"
echo "Try/compare capture with:   fftf-capture --compare --latest"
echo "Test winddown now (fast):   FFTF_INTERVAL_MIN=1 FFTF_NAG_SEC=20 fftf-winddown --now"
echo "To wire save-progress, see: contrib/save-progress-hook.sh + docs/winddown-design.md"
