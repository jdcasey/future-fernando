# Copyright 2026 John Casey
# Licensed under the Apache License, Version 2.0. See LICENSE.
# shellcheck shell=bash
#
# ff-llm.sh — pluggable LLM gateway. This is the reusable seam: any Fern
# support that needs a completion calls ff_llm_complete and gets the same
# hosted-or-local choice for free. Depends on ff-common.sh being sourced first.
#
#   ff_llm_complete "<prompt>" [format]   -> completion text on stdout (0 ok)
#         format: ""     free-form text
#                 "json" ask the backend for a JSON object (ollama uses native
#                        structured output; claude is instructed in-prompt)
#   ff_llm_check                          -> 0 if the active backend is usable
#   ff_llm_describe                       -> one-line "backend:model" summary

ff_llm_describe() {
  case "$FERN_LLM_BACKEND" in
    claude) printf 'claude:%s\n' "${FERN_LLM_MODEL:-$FERN_CLAUDE_MODEL}" ;;
    ollama) printf 'ollama:%s\n' "${FERN_LLM_MODEL:-$FERN_OLLAMA_MODEL}" ;;
    *)      printf 'unknown:%s\n' "$FERN_LLM_BACKEND" ;;
  esac
}

ff_llm_check() {
  case "$FERN_LLM_BACKEND" in
    claude)
      command -v "$FERN_CLAUDE_BIN" >/dev/null 2>&1 && return 0
      echo "ff-llm: claude CLI '$FERN_CLAUDE_BIN' not found on PATH" >&2; return 1 ;;
    ollama)
      curl -s --max-time 3 "$FERN_OLLAMA_URL/api/tags" >/dev/null 2>&1 && return 0
      echo "ff-llm: ollama not reachable at $FERN_OLLAMA_URL (is 'ollama serve' running?)" >&2
      return 1 ;;
    *)
      echo "ff-llm: unknown backend '$FERN_LLM_BACKEND'" >&2; return 1 ;;
  esac
}

ff_llm_complete() {
  local prompt="$1" format="${2:-}"
  case "$FERN_LLM_BACKEND" in
    claude) _fg_llm_claude "$prompt" "$format" ;;
    ollama) _fg_llm_ollama "$prompt" "$format" ;;
    *) echo "ff-llm: unknown backend '$FERN_LLM_BACKEND'" >&2; return 3 ;;
  esac
}

_fg_llm_claude() {
  local prompt="$1" model="${FERN_LLM_MODEL:-$FERN_CLAUDE_MODEL}"
  # Run from the scratch dir so any transcript it writes lands out of the way;
  # stdin from /dev/null avoids the CLI's stdin wait.
  ( cd "$FERN_STATE_DIR/work" 2>/dev/null || cd /tmp || exit 1
    timeout "$FERN_CAPTURE_TIMEOUT" "$FERN_CLAUDE_BIN" -p "$prompt" \
      --model "$model" </dev/null 2>/dev/null )
}

_fg_llm_ollama() {
  local prompt="$1" format="$2" model="${FERN_LLM_MODEL:-$FERN_OLLAMA_MODEL}"
  local payload resp err
  payload=$(jq -n \
    --arg m "$model" --arg p "$prompt" \
    --argjson ctx "$FERN_OLLAMA_NUM_CTX" \
    --arg ka "$FERN_OLLAMA_KEEP_ALIVE" \
    --arg f "$format" \
    '{model:$m, prompt:$p, stream:false, keep_alive:$ka, options:{num_ctx:$ctx}}
     + (if $f=="json" then {format:"json"} else {} end)')
  resp=$(curl -s --max-time "$FERN_CAPTURE_TIMEOUT" \
          "$FERN_OLLAMA_URL/api/generate" -d "$payload" 2>/dev/null) || return 1
  [ -z "$resp" ] && return 1
  err=$(printf '%s' "$resp" | jq -r '.error // empty' 2>/dev/null)
  if [ -n "$err" ]; then echo "ff-llm ollama: $err" >&2; return 1; fi
  printf '%s' "$resp" | jq -r '.response // empty' 2>/dev/null
}
