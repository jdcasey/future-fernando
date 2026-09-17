# wrap — end-of-day extraction sequence

**Status: design draft, folded into Fern.** Now lives in the Fern repo
(shared install/uninstall, one README). Commands and config are named `ff-begin`/`ff-wrap`
with a shared `ff-workday.env`; shared *code* helpers (notify/chime) are still to be unified.

## Goal

Gradually pull me out of deep-focus work so I'm mentally done by **4:00pm** on
weekdays. The sequence starts at **3:15pm** to leave buffer for the final
`/save-progress` run. Each stage notifies me so I *notice* the transition; the
interview stages require a typed response and **nag every 2 min until I answer**.

## Sequence

1. **interview** — "It's almost time to be done today. What did you get done?"
2. **interview (multi-line)** — "What's most important to start with tomorrow? Check
   your calendar." Full detail; bullet lists welcome (this zenity's `--text-info` has no
   label, so the question is seeded into the editable box and stripped back off the reply).
3. **interview** — "In one line: the 1–2 things to start with first." The short version
   `begin` resurfaces (keeps the morning notification brief, full detail stays in the file).
4. **interview** — "Are there any special items that should be included in today's
   summary?"
5. **run-skill** — `/save-progress`, incorporating the interview answers (esp. the
   special items).
6. **notify** — "You're all done! Have a good evening!"

## Timing model

- **Trigger:** systemd user timer, `Mon..Fri 15:15`.
- **Question rhythm:** ~10 min apart → 3:15 / 3:25 / 3:35 / 3:45, so `/save-progress`
  fires ~3:55. The extra (short) question lengthens the run rather than starting it
  earlier — save-progress finishes with time to spare, so the later end is accepted.
- **Nag:** within a question's window, re-prompt every 2 min until answered.

## Architecture sketch (draft — pending decisions)

- **Runner:** a single long-lived process started at 3:15 (lives ~45 min). Per
  question it shows a response prompt, blocks for input with a 2-min timeout (the
  timeout *is* the nag — re-show on expiry), then sleeps to the next slot. After
  the last answer it invokes `/save-progress`, then the final notify.
  - *Alt:* Fern-style 2-min tick + on-disk state (survives logout/suspend,
    but more moving parts). Chosen model depends on the "no-reply" decision below.
- **Responses:** accumulate in `<state>/YYYY-MM-DD.md`, one Q/A block
  each, so `/save-progress` can consume them and so there's a daily record.

## Decisions (2026-09-15)

- [x] Response mechanism: **zenity popup** (free-text; re-shows as the nag).
- [x] Early-answer pacing: **hold the 10-min rhythm** (don't advance before a slot).
- [x] No-reply: **keep nagging until answered** — plus a hard backstop
      (`FERN_HARD_STOP_MIN`, default 180) so a walked-away day doesn't pop dialogs
      all evening. NB: hold-rhythm + keep-nagging means the schedule can slip past
      4pm if answers are slow; accepted.
- [x] ~~Standalone project~~ **Folded into Fern** (2026-09-16); no shared *code*
      yet (own notify/chime helpers, own `FERN_*` config) — that unification is deferred.
- [x] "Check your calendar" is a *reminder*, not a calendar integration.
- [x] Language: **bash** for now (Python still open; more of a candidate here).

## save-progress step (step 4)

- [x] **Pluggable** via `FERN_SAVE_PROGRESS_CMD` (run with `FERN_ANSWERS_FILE`
      exported) — keeps the tool reusable; each user wires their own.
- [x] **My case:** run the `team-awareness:save-progress` skill headlessly via
      `claude`, cwd = the personal-notes project dir (so `.temp`/MCP resolve),
      with the interview Q&A supplied as context, MCP tools available, and **no
      interactive prompts**. Must complete unattended.
- [x] **Invocation confirmed** (claude 2.1.272): `-p` DOES run plugin skills —
      pass `/team-awareness:save-progress` as the prompt. Non-interactive flags:
      `--permission-mode dontAsk --permission-prompts none --allowedTools Skill`,
      with `</dev/null`. `.mcp.json` + CLAUDE.md auto-load from cwd in `-p` mode.
      Do NOT use `--dangerously-skip-permissions`. Context: inline in the prompt.
      Starter hook: `contrib/save-progress-hook.sh`.
- [ ] **Iterate:** under `dontAsk`, any tool NOT in `--allowedTools` is denied,
      so the skill's MCP tools need adding once we learn their names (discover via
      `claude -p "list your MCP tools" --output-format json`). Test by hand first.
      User's stance: try/iterate rather than perfect upfront.
- [x] **Diagnosis wired:** step-4 output+exit go to
      `<state>/log/save-progress-DATE.log`; a `wd:save_result` marker
      lands in the day file; failure -> critical notify that evening.

## Good-evening (step 5) — composition

Decision pending, but the plan: keep the "have a good evening" as a **pluggable
hook** (`FERN_GOODNIGHT_CMD`, already wired; default = one-shot notify). The
recommended composition is a NEW Fern feature (`ff-goodnight`) that provides
a **presence-aware, escalating, sticky clock-off nag** — because Fern already
owns presence detection + escalation + acknowledgment, and a "you should be logged
off" nag is the inverse of its break nag, and it should STOP once you actually
leave the keyboard (which wrap can't detect on its own). wrap's step 5
would just trigger it. If Fern isn't installed, the plain notify is the
fallback. Not built yet — awaiting go-ahead.

## begin (morning bookend)

`bin/ff-begin` + a Mon–Fri 09:00 timer: reads the most recent prior day file, pulls
the short `<!-- wd:top -->` answer (falling back to `<!-- wd:tomorrow -->` for older
files), and shows it ("Start here (from <day>): …") as a zenity info popup +
notification. One-shot by design. Relies on the keyed markers wrap writes. On each run
it also grooms the day-files directory, pruning files older than `FERN_DAY_RETAIN_DAYS`
(default 7; the read happens first, so the resurfaced note is never at risk).
