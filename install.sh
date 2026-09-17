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
LIB_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/ff/lib"
DATA_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/ff/data"
UNIT_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
CONF_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/ff"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/ff"
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
# zenity drives the wrap interview popups; the break guard doesn't need it.
if ! command -v zenity >/dev/null 2>&1; then
  echo "    NOTE: zenity not found — the wrap end-of-day interview can't prompt."
  echo "          Break guard/capture are unaffected. Install zenity to use wrap."
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

# Retire the fftf-* prefix layout (the immediately prior naming) so the ff-*
# rename doesn't leave stale duplicates running or on the PATH. Config and state
# migrate separately (see below); only units, scripts, and libs are removed here.
echo "==> Retiring fftf-* units and scripts (if present)"
systemctl --user disable --now fftf.timer fftf-winddown.timer fftf-windup.timer 2>/dev/null || true
rm -f "$UNIT_DIR/fftf.service" "$UNIT_DIR/fftf.timer" \
      "$UNIT_DIR/fftf-winddown.service" "$UNIT_DIR/fftf-winddown.timer" \
      "$UNIT_DIR/fftf-windup.service" "$UNIT_DIR/fftf-windup.timer"
rm -f "$BIN_DIR/fftf-tick" "$BIN_DIR/fftf-capture" "$BIN_DIR/fftf-afk" \
      "$BIN_DIR/fftf-status" "$BIN_DIR/fftf-pause" "$BIN_DIR/fftf-unpause" \
      "$BIN_DIR/fftf-winddown" "$BIN_DIR/fftf-windup" "$BIN_DIR/fftf-save-progress-hook"
rm -rf "${XDG_DATA_HOME:-$HOME/.local/share}/fftf"

# Retire the ff-winddown/ff-windup names (renamed to ff-wrap/ff-begin) so the
# rename doesn't leave the old timers firing alongside the new ones. Their shared
# config migrates separately (below); only units and scripts are removed here.
echo "==> Retiring ff-winddown/ff-windup units and scripts (if present)"
systemctl --user disable --now ff-winddown.timer ff-windup.timer 2>/dev/null || true
rm -f "$UNIT_DIR/ff-winddown.service" "$UNIT_DIR/ff-winddown.timer" \
      "$UNIT_DIR/ff-windup.service" "$UNIT_DIR/ff-windup.timer"
rm -f "$BIN_DIR/ff-winddown" "$BIN_DIR/ff-windup"

# One-time config/state migration from the fftf-* layout to ff-*. Preserves the
# user's settings and capture baseline; rewrites FFTF_ vars to FERN_ in the config.
OLD_CONF_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/fftf"
OLD_STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/fftf"
if [ -f "$OLD_CONF_DIR/fftf.conf" ] && [ ! -f "$CONF_DIR/ff.conf" ]; then
  echo "==> Migrating config $OLD_CONF_DIR/fftf.conf -> $CONF_DIR/ff.conf"
  mkdir -p "$CONF_DIR"
  sed 's/FFTF_/FERN_/g; s/fftf/ff/g' "$OLD_CONF_DIR/fftf.conf" > "$CONF_DIR/ff.conf"
fi
if [ -f "$OLD_CONF_DIR/fftf-winddown.env" ] && [ ! -f "$CONF_DIR/ff-workday.env" ]; then
  echo "==> Migrating $OLD_CONF_DIR/fftf-winddown.env -> $CONF_DIR/ff-workday.env"
  mkdir -p "$CONF_DIR"
  sed 's/FFTF_/FERN_/g; s/fftf/ff/g; s/FERN_WINDUP_/FERN_BEGIN_/g' "$OLD_CONF_DIR/fftf-winddown.env" > "$CONF_DIR/ff-workday.env"
fi
rm -rf "$OLD_CONF_DIR"
# Migrate the ff-winddown.env name (pre begin/wrap rename) -> ff-workday.env, and
# rewrite the renamed FERN_WINDUP_* vars to FERN_BEGIN_*.
if [ -f "$CONF_DIR/ff-winddown.env" ] && [ ! -f "$CONF_DIR/ff-workday.env" ]; then
  echo "==> Migrating $CONF_DIR/ff-winddown.env -> $CONF_DIR/ff-workday.env"
  sed 's/FERN_WINDUP_/FERN_BEGIN_/g' "$CONF_DIR/ff-winddown.env" > "$CONF_DIR/ff-workday.env"
  rm -f "$CONF_DIR/ff-winddown.env"
fi
if [ -d "$OLD_STATE_DIR" ] && [ ! -d "$STATE_DIR" ]; then
  echo "==> Migrating state $OLD_STATE_DIR -> $STATE_DIR"
  mv "$OLD_STATE_DIR" "$STATE_DIR"
fi

echo "==> Installing libs to $LIB_DIR"
mkdir -p "$LIB_DIR"
install -m 0644 "$here"/lib/*.sh "$LIB_DIR/"

echo "==> Installing data to $DATA_DIR"
mkdir -p "$DATA_DIR"
install -m 0644 "$here"/data/grounding.txt "$DATA_DIR/grounding.txt"

echo "==> Installing scripts to $BIN_DIR"
mkdir -p "$BIN_DIR"
for cmd in ff-tick ff-capture ff-afk ff-status ff-pause ff-unpause ff-wrap ff-begin; do
  install -m 0755 "$here/bin/$cmd" "$BIN_DIR/$cmd"
done
# Example wrap save-progress hook, installed to a space-free path so it's easy
# to reference from ff-workday.env (point FERN_SAVE_PROGRESS_CMD at it).
install -m 0755 "$here/contrib/save-progress-hook.sh" "$BIN_DIR/ff-save-progress-hook"

echo "==> Installing systemd user units to $UNIT_DIR"
mkdir -p "$UNIT_DIR"
for u in ff.service ff.timer \
         ff-wrap.service ff-wrap.timer ff-begin.service ff-begin.timer; do
  install -m 0644 "$here/systemd/$u" "$UNIT_DIR/$u"
done

echo "==> Config"
mkdir -p "$CONF_DIR"
if [ -f "$CONF_DIR/ff.conf" ]; then
  echo "    keeping existing $CONF_DIR/ff.conf"
else
  install -m 0644 "$here/config/ff.conf.example" "$CONF_DIR/ff.conf"
  # Bake in the resolved claude path so the systemd env doesn't have to find it.
  [ -n "$claude_bin" ] && printf '\nFERN_CLAUDE_BIN="%s"\n' "$claude_bin" >> "$CONF_DIR/ff.conf"
  # If claude is absent but ollama is present, default to the local backend.
  if [ -z "$claude_bin" ] && command -v ollama >/dev/null 2>&1; then
    printf 'FERN_LLM_BACKEND="ollama"\n' >> "$CONF_DIR/ff.conf"
    echo "    (no claude found -> defaulting capture backend to ollama)"
  fi
  echo "    wrote $CONF_DIR/ff.conf"
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
systemctl --user enable --now ff.timer ff-wrap.timer ff-begin.timer

echo
echo "Installed. Timers:"
systemctl --user list-timers ff.timer ff-wrap.timer ff-begin.timer --no-pager 2>/dev/null | sed -n '1,4p' || true
echo
echo "Make sure $BIN_DIR is on your PATH so 'ff-afk' works everywhere."
echo "Check state any time with:  ff-status       (add --log to see detections)"
echo "Step away / can't break:    ff-afk  /  ff-pause"
echo "Test a scan now with:       systemctl --user start ff.service"
echo "Try/compare capture with:   ff-capture --compare --latest"
echo "Test wrap now (fast):       FERN_INTERVAL_MIN=1 FERN_NAG_SEC=20 ff-wrap --now"
echo "To wire save-progress, see: contrib/save-progress-hook.sh + docs/wrap-design.md"
