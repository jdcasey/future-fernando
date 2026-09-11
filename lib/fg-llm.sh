# Copyright 2026 Focusguard contributors
# Licensed under the Apache License, Version 2.0. See LICENSE.
#
# fg-llm.sh — pluggable LLM gateway. This is the reusable seam: any focusguard
# support that needs a completion calls fg_llm_complete and gets the same
# hosted-or-local choice for free. Depends on fg-common.sh being sourced first.
#
#   fg_llm_complete "<prompt>" [format]   -> completion text on stdout (0 ok)
#         format: ""     free-form text
#                 "json" ask the backend for a JSON object (ollama uses native
#                        structured output; claude is instructed in-prompt)
#   fg_llm_check                          -> 0 if the active backend is usable
#   fg_llm_describe                       -> one-line "backend:model" summary

fg_llm_describe() {
  case "$FG_LLM_BACKEND" in
    claude) printf 'claude:%s\n' "${FG_LLM_MODEL:-$FG_CLAUDE_MODEL}" ;;
    ollama) printf 'ollama:%s\n' "${FG_LLM_MODEL:-$FG_OLLAMA_MODEL}" ;;
    *)      printf 'unknown:%s\n' "$FG_LLM_BACKEND" ;;
  esac
}

fg_llm_check() {
  case "$FG_LLM_BACKEND" in
    claude)
      command -v "$FG_CLAUDE_BIN" >/dev/null 2>&1 && return 0
      echo "fg-llm: claude CLI '$FG_CLAUDE_BIN' not found on PATH" >&2; return 1 ;;
    ollama)
      curl -s --max-time 3 "$FG_OLLAMA_URL/api/tags" >/dev/null 2>&1 && return 0
      echo "fg-llm: ollama not reachable at $FG_OLLAMA_URL (is 'ollama serve' running?)" >&2
      return 1 ;;
    *)
      echo "fg-llm: unknown backend '$FG_LLM_BACKEND'" >&2; return 1 ;;
  esac
}

fg_llm_complete() {
  local prompt="$1" format="${2:-}"
  case "$FG_LLM_BACKEND" in
    claude) _fg_llm_claude "$prompt" "$format" ;;
    ollama) _fg_llm_ollama "$prompt" "$format" ;;
    *) echo "fg-llm: unknown backend '$FG_LLM_BACKEND'" >&2; return 3 ;;
  esac
}

_fg_llm_claude() {
  local prompt="$1" model="${FG_LLM_MODEL:-$FG_CLAUDE_MODEL}"
  # Run from the scratch dir so any transcript it writes lands out of the way;
  # stdin from /dev/null avoids the CLI's stdin wait.
  ( cd "$FG_STATE_DIR/work" 2>/dev/null || cd /tmp || exit 1
    timeout "$FG_CAPTURE_TIMEOUT" "$FG_CLAUDE_BIN" -p "$prompt" \
      --model "$model" </dev/null 2>/dev/null )
}

_fg_llm_ollama() {
  local prompt="$1" format="$2" model="${FG_LLM_MODEL:-$FG_OLLAMA_MODEL}"
  local payload resp err
  payload=$(jq -n \
    --arg m "$model" --arg p "$prompt" \
    --argjson ctx "$FG_OLLAMA_NUM_CTX" \
    --arg ka "$FG_OLLAMA_KEEP_ALIVE" \
    --arg f "$format" \
    '{model:$m, prompt:$p, stream:false, keep_alive:$ka, options:{num_ctx:$ctx}}
     + (if $f=="json" then {format:"json"} else {} end)')
  resp=$(curl -s --max-time "$FG_CAPTURE_TIMEOUT" \
          "$FG_OLLAMA_URL/api/generate" -d "$payload" 2>/dev/null) || return 1
  [ -z "$resp" ] && return 1
  err=$(printf '%s' "$resp" | jq -r '.error // empty' 2>/dev/null)
  if [ -n "$err" ]; then echo "fg-llm ollama: $err" >&2; return 1; fi
  printf '%s' "$resp" | jq -r '.response // empty' 2>/dev/null
}
