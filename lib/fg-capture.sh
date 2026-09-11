# Copyright 2026 John Casey
# Licensed under the Apache License, Version 2.0. See LICENSE.
#
# fg-capture.sh — turn an idle session transcript into a QUESTION-*.md digest.
# Depends on fg-common.sh and fg-llm.sh being sourced first.
#
# Uses a JSON contract with the model (robust across small local models and
# hosted ones), then assembles the markdown here.

# Last recorded cwd in a transcript (real path, incl. spaces).
fg_transcript_cwd() {
  grep -o '"cwd":"[^"]*"' "$1" 2>/dev/null | tail -1 | sed 's/.*"cwd":"//; s/"$//'
}

# Recent USER/ASSISTANT text only (no tools, no thinking), last N bytes.
# Fallback path for transcripts without prompt-source markers.
fg_extract_tail() {
  jq -r '
    select(.type=="user" or .type=="assistant") |
    if .type=="user" then
      (.message.content) as $c |
      (if ($c|type)=="string" then $c
       elif ($c|type)=="array" then ($c|map(select(.type=="text")|.text)|join("\n"))
       else "" end) as $t |
      (if ($t|length)>0 then "USER: " + $t else empty end)
    else
      (.message.content // []) as $c |
      (if ($c|type)=="array" then ($c|map(select(.type=="text")|.text)|join("\n"))
       else ($c|tostring) end) as $t |
      (if ($t|length)>0 then "ASSISTANT: " + $t else empty end)
    end
  ' "$1" 2>/dev/null | tail -c "$FG_CAPTURE_TAIL_BYTES"
}

# Just the last real exchange: the last human-typed prompt (promptSource=="typed")
# and every assistant text block after it. This is the highest-signal, smallest
# input we can feed the model — on CPU the input dominates cost, so isolating one
# exchange both speeds distillation and sharpens quality. Empty if no typed prompt
# is found (older transcripts) so the caller can fall back to fg_extract_tail.
fg_extract_exchange() {
  jq -rs '
    . as $all
    | ([range(0; ($all|length)) | select($all[.].promptSource=="typed")] | last) as $i
    | if $i == null then empty
      else
        $all[$i:]
        | map(
            if (.type=="user" and .promptSource=="typed") then
              (.message.content) as $c
              | (if ($c|type)=="string" then $c
                 elif ($c|type)=="array" then ($c|map(select(.type=="text")|.text)|join("\n"))
                 else "" end) as $t
              | (if ($t|length)>0 then "USER: " + $t else empty end)
            elif .type=="assistant" then
              (.message.content // []) as $c
              | (if ($c|type)=="array" then ($c|map(select(.type=="text")|.text)|join("\n"))
                 else ($c|tostring) end) as $t
              | (if ($t|length)>0 then "ASSISTANT: " + $t else empty end)
            else empty end
          )
        | join("\n")
      end
  ' "$1" 2>/dev/null | tail -c "$FG_CAPTURE_TAIL_BYTES"
}

# NOTE: capture requires a real human-typed exchange (fg_extract_exchange). Sessions
# with no typed prompt are command/automation runs (e.g. /save-progress) or our own
# background LLM scratch sessions — not "I asked something and walked away" — so they
# are skipped rather than distilled, which also avoids spending model calls on them.
# fg_extract_tail remains as a lower-level helper (not used by the capture path).

fg_distill_prompt() {
  local tail_text="$1"
  cat <<EOF
[$FG_SENTINEL] You are given the tail of a Claude Code session transcript.
Identify the single most recent SUBSTANTIVE question or task the user was pursuing
and the answer or conclusion reached.

Respond with ONLY one JSON object and nothing else (no markdown fences, no prose):
{
  "skip": <true if the tail is trivial / has no question worth saving, else false>,
  "slug": "<= 6-word kebab-case identifier",
  "question": "the user's question or task, quoted or tightly paraphrased",
  "answer": "concise summary of the resolution; if it looks cut off, end with '(possibly incomplete)'",
  "context": "short notes: key files, commands, or decisions (may use '- ' bullets)"
}
If skip is true the other fields may be empty strings.

TRANSCRIPT TAIL:
$tail_text
EOF
}

# Pull the first {...} JSON object out of possibly-messy model output.
fg_extract_json() {
  local raw="$1" json
  json=$(printf '%s' "$raw" | sed -n '/{/,/}/p')
  [ -z "$json" ] && json="$raw"
  printf '%s' "$json" | jq -e . >/dev/null 2>&1 || return 1
  printf '%s' "$json"
}

# Distill a transcript to a clean JSON object on stdout.
# return: 0 ok | 2 empty/too-short tail | 1 llm or parse error
fg_distill() {
  local file="$1" tail_text prompt raw json
  tail_text=$(fg_extract_exchange "$file")
  [ -z "$tail_text" ] && return 2   # no human-typed exchange -> skip (not a Q&A session)
  prompt=$(fg_distill_prompt "$tail_text")
  raw=$(fg_llm_complete "$prompt" json) || return 1
  [ -z "$raw" ] && return 1
  json=$(fg_extract_json "$raw") || return 1
  printf '%s' "$json"
}

# Render a distilled JSON object to markdown on stdout.
# return: 0 rendered | 2 model said skip
fg_render_markdown() {
  local json="$1" skip
  skip=$(printf '%s' "$json" | jq -r '.skip // false' 2>/dev/null)
  [ "$skip" = "true" ] && return 2
  printf '%s' "$json" | jq -r '
    "# Question\n" + (.question // "") +
    "\n\n## Answer / Conclusion\n" + (.answer // "") +
    "\n\n## Context\n" + (.context // "")'
  printf -- '- Captured: %s\n' "$(date '+%Y-%m-%d %H:%M')"
}

fg_slug() {
  printf '%s' "$1" | jq -r '.slug // "session"' 2>/dev/null \
    | tr '[:upper:] ' '[:lower:]-' | tr -cd 'a-z0-9-' | cut -c1-50
}

# Full capture: distill -> render -> write file under the session's project.
# return: 0 wrote a file | 2 skipped/trivial | 1 error
fg_capture_session() {
  local file="$1" cwd outdir json md slug ts outfile rc
  cwd=$(fg_transcript_cwd "$file"); [ -z "$cwd" ] && return 1
  [ -d "$cwd" ] || return 1
  if [ -n "$FG_CAPTURE_DIR" ]; then outdir="$FG_CAPTURE_DIR"; else outdir="$cwd/.temp"; fi
  mkdir -p "$outdir" 2>/dev/null || return 1

  json=$(fg_distill "$file"); rc=$?
  [ "$rc" -eq 2 ] && return 2
  [ "$rc" -ne 0 ] && return 1

  md=$(fg_render_markdown "$json"); rc=$?
  [ "$rc" -eq 2 ] && return 2

  slug=$(fg_slug "$json"); [ -z "$slug" ] && slug="session"
  ts=$(date +%Y%m%d)
  outfile="$outdir/QUESTION-${slug}-${ts}.md"
  [ -e "$outfile" ] && outfile="$outdir/QUESTION-${slug}-${ts}-$(date +%H%M%S).md"
  printf '%s\n' "$md" > "$outfile" || return 1
  return 0
}
