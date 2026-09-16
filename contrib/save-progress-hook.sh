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
# Example FFTF_SAVE_PROGRESS_CMD hook: run a Claude Code skill headlessly with the
# day's interview Q&A as context. This is the starting point to ITERATE on — see
# the "known rough edges" note at the bottom.
#
# winddown invokes this with FFTF_ANSWERS_FILE exported (the day's Q&A markdown).
set -uo pipefail

: "${FFTF_PROJECT_DIR:=$HOME/code/redhat/resilience/planning/personal notes}"
: "${FFTF_SKILL:=/team-awareness:save-progress}"
: "${FFTF_CLAUDE_BIN:=claude}"
# Tools the run may use. Under --permission-mode dontAsk, anything NOT listed is
# DENIED (no prompt). "Skill" lets the skill launch; add the skill's MCP tools as
# you learn their names (see rough edges below).
: "${FFTF_ALLOWED_TOOLS:=Skill}"

answers=""
if [ -n "${FFTF_ANSWERS_FILE:-}" ] && [ -f "$FFTF_ANSWERS_FILE" ]; then
  answers="$(cat "$FFTF_ANSWERS_FILE")"
fi

prompt="$FFTF_SKILL

End-of-day interview context — use these when saving progress:

${answers:-（no interview answers captured）}"

cd "$FFTF_PROJECT_DIR" || { echo "save-progress-hook: bad FFTF_PROJECT_DIR" >&2; exit 1; }

# shellcheck disable=SC2086  # FFTF_ALLOWED_TOOLS is an intentional word list
exec "$FFTF_CLAUDE_BIN" -p "$prompt" \
  --permission-mode dontAsk \
  --permission-prompts none \
  --allowedTools $FFTF_ALLOWED_TOOLS \
  </dev/null

# --- known rough edges (iterate) ---------------------------------------------
# * dontAsk DENIES any tool not in --allowedTools. If save-progress calls MCP
#   tools (the team-awareness tooling), they'll be denied until you add their
#   names to FFTF_ALLOWED_TOOLS. Discover names with:
#     claude -p "list your available MCP tools" --output-format json
#   MCP tool names look like: mcp__plugin_<plugin>_<server>__<tool>
# * The personal-notes CLAUDE.md forbids the ngit-memory MCP server in this
#   project; don't allowlist those tools here.
# * First runs: test by hand (not via systemd) so you can see denials/output.
