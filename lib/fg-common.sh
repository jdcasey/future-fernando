# Copyright 2026 John Casey
# Licensed under the Apache License, Version 2.0. See LICENSE.
# shellcheck shell=bash
#
# fg-common.sh — shared paths, defaults, and config loading.
# Source this FIRST from any focusguard script. Not executable on its own.
#
# Precedence: built-in defaults  <  config file  <  variables set by the
# caller AFTER sourcing (e.g. CLI --flags). The config file therefore wins
# over the environment; use --flags (or set the var after sourcing) for
# one-off overrides.

FG_STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/focusguard"
FG_CONFIG_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/focusguard/focusguard.conf"

# ---- defaults (only fill if unset) ------------------------------------------
: "${FG_PROJECTS_DIR:=$HOME/.claude/projects}"

# feature switches
: "${FG_BREAK_ENABLED:=1}"
: "${FG_CAPTURE_ENABLED:=1}"

# break guard (seconds)
: "${FG_BREAK_INTERVAL:=3600}"
: "${FG_ACTIVITY_GAP:=600}"
# grace window after `afk`: the nag goes quiet, but the break is only
# *credited* (clock reset) by a real >=FG_ACTIVITY_GAP quiet gap. Keep working
# through the grace and the nag returns — silence requires actually stepping away.
: "${FG_BREAK_GRACE:=300}"
# Presence signal for the break-guard clock: auto | idle | typed.
#   idle  = seconds since real desktop input (GNOME/Mutter) — watching an agent
#           counts as work; only leaving the keyboard credits a break.
#   typed = legacy: seconds since your last typed Claude prompt.
#   auto  = idle if the desktop idle monitor answers, else fall back to typed.
: "${FG_PRESENCE:=auto}"
# how many of today's most-recently-active sessions to inspect for a real
# human-typed prompt when computing the break-guard clock (typed/auto-fallback).
: "${FG_HUMAN_SCAN_N:=5}"

# break delivery
: "${FG_NOTIFY_STACK:=0}"
: "${FG_SOUND_ENABLED:=1}"

# capture
: "${FG_CAPTURE_IDLE:=480}"
: "${FG_CAPTURE_MAX_AGE:=86400}"
: "${FG_CAPTURE_PER_TICK:=2}"
: "${FG_CAPTURE_TIMEOUT:=120}"
: "${FG_CAPTURE_TAIL_BYTES:=12000}"
: "${FG_CAPTURE_DIR:=}"

# LLM backend (shared by every LLM-using support, not just capture)
: "${FG_LLM_BACKEND:=claude}"          # claude | ollama
: "${FG_LLM_MODEL:=}"                   # optional: override whichever backend's model
: "${FG_CLAUDE_BIN:=claude}"
: "${FG_CLAUDE_MODEL:=claude-haiku-4-5-20251001}"
: "${FG_OLLAMA_URL:=http://localhost:11434}"
: "${FG_OLLAMA_MODEL:=llama3.2:3b}"
: "${FG_OLLAMA_NUM_CTX:=8192}"
: "${FG_OLLAMA_KEEP_ALIVE:=5m}"

# Sentinel embedded in distiller prompts so capture never re-captures its own
# LLM calls (which would otherwise loop). Used by fg-capture.sh / focusguard-tick.
# shellcheck disable=SC2034  # consumed in other sourced files, not this one
FG_SENTINEL="FOCUSGUARD_CAPTURE_DISTILL_V1"

# ---- config file overrides defaults -----------------------------------------
# shellcheck source=/dev/null
[ -f "$FG_CONFIG_FILE" ] && . "$FG_CONFIG_FILE"

# ---- ensure working dirs exist ----------------------------------------------
mkdir -p "$FG_STATE_DIR" "$FG_STATE_DIR/captured" "$FG_STATE_DIR/work" 2>/dev/null || true

# Latest HUMAN activity time (epoch seconds) — the break-guard clock.
# Uses typed prompts, not file mtime, so autonomous agent work does NOT look
# like you're engaged (which would nag you to break during a real pause).
# Two-stage for cheapness: (1) mtime-sort today's session transcripts, take the
# N most recent; (2) in just those, read the last human-typed prompt timestamp
# (promptSource=="typed"). Returns the max, or 0 if none (-> treated as idle).
fg_last_human_activity() {
  local best=0 f ts epoch today work_slug
  today=$(date +%F)
  # Claude maps a cwd to a project-dir slug by replacing '/' and '.' with '-'.
  # Our headless capture calls run under $FG_STATE_DIR/work and create scratch
  # transcripts (no typed prompts) that would otherwise waste scan slots.
  work_slug=$(printf '%s' "$FG_STATE_DIR/work" | sed 's/[/.]/-/g')
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    # last typed-prompt line only (grep is cheap; jq parses just one line)
    ts=$(grep '"promptSource":"typed"' "$f" 2>/dev/null | tail -1 \
           | jq -r '.timestamp // empty' 2>/dev/null)
    [ -n "$ts" ] || continue
    epoch=$(date -d "$ts" +%s 2>/dev/null) || continue
    [ "$epoch" -gt "$best" ] && best="$epoch"
  done < <(find "$FG_PROJECTS_DIR" -mindepth 2 -maxdepth 2 -name '*.jsonl' \
             -newermt "$today 00:00:00" -printf '%T@ %p\n' 2>/dev/null \
             | grep -v "/$work_slug/" \
             | sort -rn | head -n "$FG_HUMAN_SCAN_N" | cut -d' ' -f2-)
  printf '%s\n' "$best"
}

# Seconds since the last real desktop input (keyboard/mouse), via GNOME/Mutter's
# IdleMonitor on the session bus. This is a PRESENCE signal: it stays low while
# you read a diff or watch an agent run, and only climbs once you actually leave
# the keyboard. Prints the idle seconds, or nothing (returns 1) when the monitor
# is unavailable (non-GNOME, no session bus, headless) so callers can fall back.
fg_idle_seconds() {
  local out ms
  out=$(gdbus call --session \
          --dest org.gnome.Mutter.IdleMonitor \
          --object-path /org/gnome/Mutter/IdleMonitor/Core \
          --method org.gnome.Mutter.IdleMonitor.GetIdletime 2>/dev/null) || return 1
  ms=${out##*uint64 }; ms=${ms%%[!0-9]*}     # (uint64 29144,) -> 29144
  [ -n "$ms" ] || return 1
  printf '%s\n' "$(( ms / 1000 ))"
}

# Seconds since you were last "present" for break-guard purposes. Presence beats
# typing: watching an agent counts as work, and only real physical absence
# credits a break. Honors FG_PRESENCE (idle | typed | auto). On idle-monitor
# failure it degrades to "present" (0) rather than faking a break, so a broken
# monitor errs toward nagging you, never toward silently suppressing reminders.
fg_break_away_seconds() {
  local idle last
  if [ "$FG_PRESENCE" != typed ]; then
    if idle=$(fg_idle_seconds); then printf '%s\n' "$idle"; return 0; fi
    [ "$FG_PRESENCE" = idle ] && { printf '0\n'; return 0; }   # explicit idle: fail present
  fi
  last=$(fg_last_human_activity); [ -z "$last" ] && last=0     # typed, or auto fallback
  printf '%s\n' "$(( $(date +%s) - last ))"
}

# Resolve the focusguard lib dir (used by bin scripts to find siblings).
# Honors $FG_LIB, then the installed location, then a repo-relative path.
fg_lib_dir() {
  if [ -n "${FG_LIB:-}" ] && [ -f "$FG_LIB/fg-common.sh" ]; then
    printf '%s\n' "$FG_LIB"; return 0
  fi
  local installed="${XDG_DATA_HOME:-$HOME/.local/share}/focusguard/lib"
  if [ -f "$installed/fg-common.sh" ]; then printf '%s\n' "$installed"; return 0; fi
  return 1
}
