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

- [x] **Pluggable and REQUIRED** via `FERN_SAVE_PROGRESS_CMD` (run with
      `FERN_ANSWERS_FILE` exported), or an executable at `FERN_SAVE_PROGRESS_HOOK`
      (default `~/.local/bin/ff-save-progress-hook`). This tool ships no hook — how
      a day's answers get persisted is personal — so each user wires their own.
- [x] **begin/wrap refuse to run without a hook.** The interview only earns its
      interruption if the answers can be saved, so both scripts preflight for a
      hook and fail fast (stderr + critical notify) if none is configured. The
      old "answers saved to the day file, save-progress skipped" fallback is gone.
- [x] **Contract:** the hook receives `FERN_ANSWERS_FILE` — the day file, a
      markdown document of the interview Q/A. What it does with that is entirely
      up to the hook (write a journal, call an API, run an agent). For unattended
      systemd runs: wrap long-running hooks in `timeout` (the interview backstop
      doesn't cover step 4) and use absolute paths (user services don't inherit
      your interactive `PATH`). Test by hand before trusting it to the timer.
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
