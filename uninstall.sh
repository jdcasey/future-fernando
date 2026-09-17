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
# uninstall.sh — remove Fern. Config and state are left in place unless
# you pass --purge.

set -euo pipefail

BIN_DIR="$HOME/.local/bin"
LIB_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/ff"
UNIT_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
CONF_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/ff"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/ff"

echo "==> Disabling timers"
systemctl --user disable --now ff.timer ff-wrap.timer ff-begin.timer 2>/dev/null || true
# the ff-winddown/ff-windup names (pre begin/wrap rename), the fftf-* prefix layout,
# and pre-Fern timers, in case an old install is still around
systemctl --user disable --now ff-winddown.timer ff-windup.timer 2>/dev/null || true
systemctl --user disable --now fftf.timer fftf-winddown.timer fftf-windup.timer 2>/dev/null || true
systemctl --user disable --now focusguard.timer winddown.timer windup.timer 2>/dev/null || true

echo "==> Removing units, scripts, and libs"
rm -f "$UNIT_DIR/ff.timer" "$UNIT_DIR/ff.service" \
      "$UNIT_DIR/ff-wrap.timer" "$UNIT_DIR/ff-wrap.service" \
      "$UNIT_DIR/ff-begin.timer" "$UNIT_DIR/ff-begin.service" \
      "$UNIT_DIR/ff-winddown.timer" "$UNIT_DIR/ff-winddown.service" \
      "$UNIT_DIR/ff-windup.timer" "$UNIT_DIR/ff-windup.service"
rm -f "$BIN_DIR/ff-tick" "$BIN_DIR/ff-capture" "$BIN_DIR/ff-afk" \
      "$BIN_DIR/ff-status" "$BIN_DIR/ff-pause" "$BIN_DIR/ff-unpause" \
      "$BIN_DIR/ff-wrap" "$BIN_DIR/ff-begin" "$BIN_DIR/ff-save-progress-hook" \
      "$BIN_DIR/ff-winddown" "$BIN_DIR/ff-windup"
# the fftf-* prefix layout
rm -f "$UNIT_DIR/fftf.service" "$UNIT_DIR/fftf.timer" \
      "$UNIT_DIR/fftf-winddown.service" "$UNIT_DIR/fftf-winddown.timer" \
      "$UNIT_DIR/fftf-windup.service" "$UNIT_DIR/fftf-windup.timer"
rm -f "$BIN_DIR/fftf-tick" "$BIN_DIR/fftf-capture" "$BIN_DIR/fftf-afk" \
      "$BIN_DIR/fftf-status" "$BIN_DIR/fftf-pause" "$BIN_DIR/fftf-unpause" \
      "$BIN_DIR/fftf-winddown" "$BIN_DIR/fftf-windup" "$BIN_DIR/fftf-save-progress-hook"
rm -rf "${XDG_DATA_HOME:-$HOME/.local/share}/fftf"
# pre-Fern names from earlier releases
rm -f "$UNIT_DIR/focusguard.service" "$UNIT_DIR/focusguard.timer" \
      "$UNIT_DIR/winddown.service" "$UNIT_DIR/winddown.timer" \
      "$UNIT_DIR/windup.service" "$UNIT_DIR/windup.timer"
rm -f "$BIN_DIR/fg-tick" "$BIN_DIR/fg-capture" "$BIN_DIR/fg-afk" \
      "$BIN_DIR/fg-status" "$BIN_DIR/fg-pause" "$BIN_DIR/fg-unpause" \
      "$BIN_DIR/winddown" "$BIN_DIR/windup" "$BIN_DIR/wd-save-progress-hook" \
      "$BIN_DIR/focusguard-tick" "$BIN_DIR/focusguard-capture" \
      "$BIN_DIR/afk" "$BIN_DIR/break-start" "$BIN_DIR/break-done" \
      "$BIN_DIR/focusguard-status"
rm -rf "$LIB_DIR"
systemctl --user daemon-reload

if [ "${1:-}" = "--purge" ]; then
  echo "==> Purging config and state"
  rm -rf "$CONF_DIR" "$STATE_DIR"
  # fftf-* and pre-Fern config/state locations
  rm -rf "${XDG_CONFIG_HOME:-$HOME/.config}/fftf" \
         "${XDG_STATE_HOME:-$HOME/.local/state}/fftf"
  rm -rf "${XDG_CONFIG_HOME:-$HOME/.config}/focusguard" \
         "${XDG_CONFIG_HOME:-$HOME/.config}/winddown" \
         "${XDG_STATE_HOME:-$HOME/.local/state}/focusguard" \
         "${XDG_STATE_HOME:-$HOME/.local/state}/winddown"
else
  echo "Left config ($CONF_DIR) and state ($STATE_DIR) in place. Use --purge to remove them (also clears any pre-Fern focusguard/winddown dirs)."
fi

echo "Done."
