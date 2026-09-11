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

echo "==> Installing libs to $LIB_DIR"
mkdir -p "$LIB_DIR"
install -m 0644 "$here"/lib/*.sh "$LIB_DIR/"

echo "==> Installing scripts to $BIN_DIR"
mkdir -p "$BIN_DIR"
install -m 0755 "$here/bin/focusguard-tick"    "$BIN_DIR/focusguard-tick"
install -m 0755 "$here/bin/focusguard-capture" "$BIN_DIR/focusguard-capture"
install -m 0755 "$here/bin/break-start"         "$BIN_DIR/break-start"
install -m 0755 "$here/bin/focusguard-status"   "$BIN_DIR/focusguard-status"

echo "==> Installing systemd user units to $UNIT_DIR"
mkdir -p "$UNIT_DIR"
install -m 0644 "$here/systemd/focusguard.service" "$UNIT_DIR/focusguard.service"
install -m 0644 "$here/systemd/focusguard.timer"   "$UNIT_DIR/focusguard.timer"

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

echo "==> Enabling timer"
systemctl --user daemon-reload
# Make the desktop session env (dbus/wayland) available to the service.
systemctl --user import-environment DISPLAY WAYLAND_DISPLAY XDG_RUNTIME_DIR DBUS_SESSION_BUS_ADDRESS 2>/dev/null || true
systemctl --user enable --now focusguard.timer

echo
echo "Installed. Timer status:"
systemctl --user --no-pager status focusguard.timer | sed -n '1,4p' || true
echo
echo "Make sure $BIN_DIR is on your PATH so 'break-start' works everywhere."
echo "Check state any time with:  focusguard-status"
echo "Test a scan now with:       systemctl --user start focusguard.service"
echo "Try/compare capture with:   focusguard-capture --compare --latest"
