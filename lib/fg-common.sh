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

# Overridable (mainly for tests); defaults to the XDG state location.
: "${FG_STATE_DIR:=${XDG_STATE_HOME:-$HOME/.local/state}/focusguard}"
FG_CONFIG_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/focusguard/focusguard.conf"

# ---- defaults (only fill if unset) ------------------------------------------
: "${FG_PROJECTS_DIR:=$HOME/.claude/projects}"

# feature switches
: "${FG_BREAK_ENABLED:=1}"
: "${FG_CAPTURE_ENABLED:=1}"

# break guard (seconds)
: "${FG_BREAK_INTERVAL:=3600}"
: "${FG_ACTIVITY_GAP:=600}"
# grace window after `fg-afk`: the nag goes quiet, but the break is only
# *credited* (clock reset) by a real >=FG_ACTIVITY_GAP quiet gap. Keep working
# through the grace and the nag returns — silence requires actually stepping away.
: "${FG_BREAK_GRACE:=300}"
# Presence signal(s) for the break-guard clock. Signals STACK: the clock treats
# you as present if ANY enabled signal says so, so "away" is the smallest gap
# across them. Value is either a named profile or a comma-list of signals.
#   Profiles:
#     default = idle,audio-in   (recommended shipped default; fixes meetings)
#     minimal = idle            (idle only; meeting-blind, least ambient sensing)
#     off     = <none>          (no ambient sensing at all; rely on fg-afk/fg-pause)
#   Back-compat aliases: auto (idle, else typed fallback), idle, typed.
#   Signals (compose freely, e.g. "idle,audio-in,audio-out"):
#     idle      = seconds since real desktop input (GNOME/Mutter IdleMonitor).
#     audio-in  = mic in use (an app is capturing) — strong "in a call" signal.
#     audio-out = speaker in use (an app is playing) — catches muted-listening and
#                 recording playback; noisier (music/video), so opt-in.
#     typed     = legacy: seconds since your last typed Claude prompt.
#   Audio signals read only that a stream EXISTS, never its content; nothing leaves
#   the machine. See "What focusguard observes" in the README.
: "${FG_PRESENCE:=auto}"
# how many of today's most-recently-active sessions to inspect for a real
# human-typed prompt when computing the break-guard clock (typed/auto-fallback).
: "${FG_HUMAN_SCAN_N:=5}"
# pause guard (fg-pause / fg-unpause): silence the nag when you CAN'T break, without
# crediting one. The stretch clock keeps running, so you come back overdue.
: "${FG_PAUSE_DEFAULT:=1800}"   # default pause length if none given (30m)
: "${FG_PAUSE_MAX:=7200}"       # hard cap so a fat-fingered pause can't disable all day (2h)
# tool to read audio-device presence (PipeWire/PulseAudio). Existence check only.
: "${FG_PACTL_BIN:=pactl}"
# rolling detection log: one line per tick recording what each signal read and the
# decision taken, for diagnosing break-guard behavior. Daily files, auto-pruned.
: "${FG_LOG_ENABLED:=1}"
: "${FG_LOG_RETAIN_DAYS:=3}"

# break delivery
: "${FG_NOTIFY_STACK:=0}"
: "${FG_SOUND_ENABLED:=1}"
# grounding suggestion: attach one randomly-chosen practice to each break nag.
: "${FG_GROUNDING_ENABLED:=1}"
: "${FG_GROUNDING_FILE:=}"       # empty = the installed data/grounding.txt

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
# LLM calls (which would otherwise loop). Used by fg-capture.sh / fg-tick.
# shellcheck disable=SC2034  # consumed in other sourced files, not this one
FG_SENTINEL="FOCUSGUARD_CAPTURE_DISTILL_V1"

# ---- config file overrides defaults -----------------------------------------
# shellcheck source=/dev/null
[ -f "$FG_CONFIG_FILE" ] && . "$FG_CONFIG_FILE"

# ---- ensure working dirs exist ----------------------------------------------
FG_LOG_DIR="$FG_STATE_DIR/log"
mkdir -p "$FG_STATE_DIR" "$FG_STATE_DIR/captured" "$FG_STATE_DIR/work" \
         "$FG_LOG_DIR" 2>/dev/null || true

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

# True if an application is CAPTURING audio (mic in use) — a strong "in a call"
# signal. Reads only that a record stream EXISTS via PipeWire/PulseAudio, never
# its content, and never touches the network. Returns 1 if pactl is unavailable
# or nothing is recording.
fg_audio_in_active() {
  command -v "$FG_PACTL_BIN" >/dev/null 2>&1 || return 1
  "$FG_PACTL_BIN" list short source-outputs 2>/dev/null | grep -q '[^[:space:]]'
}

# True if an application is PLAYING audio (speaker in use). Catches incoming
# meeting audio while your mic is muted, and recording playback. Noisier than
# mic (music, videos), so it is opt-in. Existence check only, never content.
fg_audio_out_active() {
  command -v "$FG_PACTL_BIN" >/dev/null 2>&1 || return 1
  "$FG_PACTL_BIN" list short sink-inputs 2>/dev/null | grep -q '[^[:space:]]'
}

# Resolve FG_PRESENCE (profile name or comma-list) into a space-separated signal
# list. Empty = "off" (no ambient sensing). 'auto' is handled specially by the
# caller (idle with typed FALLBACK, not an OR), so it is not expanded here.
fg_presence_signals() {
  case "$FG_PRESENCE" in
    default) printf 'idle audio-in\n' ;;
    minimal|idle) printf 'idle\n' ;;
    typed)   printf 'typed\n' ;;
    off|none) printf '\n' ;;
    auto)    printf 'auto\n' ;;
    *)       printf '%s\n' "$FG_PRESENCE" | tr ',' ' ' ;;
  esac
}

# Seconds since you were last "present" for break-guard purposes. Presence beats
# typing: watching an agent counts as work, and only real physical absence
# credits a break. Signals STACK — the result is the SMALLEST away-gap across all
# enabled signals, so any one of them reporting "present now" (e.g. mic live in a
# meeting) holds the clock. On total signal failure it degrades to "present" (0)
# rather than faking a break, so a broken sensor errs toward nagging you, never
# toward silently suppressing reminders.
fg_break_away_seconds() {
  local sigs s val best="" now last
  now=$(date +%s)

  # auto: idle if the monitor answers, else the legacy typed signal (FALLBACK,
  # not an OR — preserves the original 'auto' semantics).
  if [ "$FG_PRESENCE" = auto ]; then
    if val=$(fg_idle_seconds); then printf '%s\n' "$val"; return 0; fi
    last=$(fg_last_human_activity); [ -z "$last" ] && last=0
    printf '%s\n' "$(( now - last ))"; return 0
  fi

  sigs=$(fg_presence_signals)
  # off / empty: no ambient sensing. Report present (0); breaks are credited only
  # by fg-afk actually being followed by a real gap — the guard runs on elapsed time.
  [ -z "${sigs// }" ] && { printf '0\n'; return 0; }

  # shellcheck disable=SC2086  # deliberate word-split of the signal list
  for s in $sigs; do
    val=""
    case "$s" in
      idle)      val=$(fg_idle_seconds) || val="" ;;
      audio-in)  fg_audio_in_active  && val=0 ;;   # present now; absent = no vote
      audio-out) fg_audio_out_active && val=0 ;;   # present now; absent = no vote
      typed)     last=$(fg_last_human_activity); [ -z "$last" ] && last=0
                 val=$(( now - last )) ;;
    esac
    [ -n "$val" ] || continue
    { [ -z "$best" ] || [ "$val" -lt "$best" ]; } && best="$val"
  done
  # No signal produced a reading -> degrade to present, never fake a break.
  [ -z "$best" ] && best=0
  printf '%s\n' "$best"
}

# Append one detection record to today's rolling log and prune old days. Callers
# pass key=value fields; we prepend an ISO-8601 timestamp. This log is the
# audit/diagnostic trail — local only, existence/decision facts, no content.
fg_log_detection() {
  [ "$FG_LOG_ENABLED" = 1 ] || return 0
  local f="$FG_LOG_DIR/fg-$(date +%Y%m%d).log"
  printf '%s %s\n' "$(date --iso-8601=seconds)" "$*" >> "$f" 2>/dev/null || true
  find "$FG_LOG_DIR" -name 'fg-*.log' -mtime "+$FG_LOG_RETAIN_DAYS" -delete 2>/dev/null || true
}

# Pick ONE grounding/break practice at random from the data file, as a single
# "Name — instructions" line. Prints nothing (returns 1) when disabled, the file
# is missing, or it holds no usable lines — callers just omit the suggestion.
fg_grounding_suggestion() {
  [ "$FG_GROUNDING_ENABLED" = 1 ] || return 1
  local file="$FG_GROUNDING_FILE" d line
  if [ -z "$file" ]; then
    d=$(fg_lib_dir 2>/dev/null) || return 1
    file="$d/../data/grounding.txt"
  fi
  [ -f "$file" ] || return 1
  line=$(grep -vE '^[[:space:]]*(#|$)' "$file" 2>/dev/null | shuf -n1 2>/dev/null)
  [ -n "$line" ] || return 1
  printf '%s\n' "$line"
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
