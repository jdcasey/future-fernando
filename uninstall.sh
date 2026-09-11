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
# uninstall.sh — remove focusguard. Config and state are left in place unless
# you pass --purge.

set -euo pipefail

BIN_DIR="$HOME/.local/bin"
LIB_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/focusguard"
UNIT_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
CONF_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/focusguard"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/focusguard"

echo "==> Disabling timer"
systemctl --user disable --now focusguard.timer 2>/dev/null || true

echo "==> Removing units, scripts, and libs"
rm -f "$UNIT_DIR/focusguard.timer" "$UNIT_DIR/focusguard.service"
rm -f "$BIN_DIR/focusguard-tick" "$BIN_DIR/focusguard-capture" \
      "$BIN_DIR/break-start" "$BIN_DIR/break-done" "$BIN_DIR/focusguard-status"
rm -rf "$LIB_DIR"
systemctl --user daemon-reload

if [ "${1:-}" = "--purge" ]; then
  echo "==> Purging config and state"
  rm -rf "$CONF_DIR" "$STATE_DIR"
else
  echo "Left config ($CONF_DIR) and state ($STATE_DIR) in place. Use --purge to remove them."
fi

echo "Done."
