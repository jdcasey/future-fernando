# wrap — end-of-day extraction sequence

**Status: design draft, folded into Fern.** Now lives in the Fern repo
(shared install/uninstall, one README). Commands and config are named `ff-begin`/`ff-wrap`
with a shared `ff-workday.env`; shared *code* helpers (notify/chime) are still to be unified.

## Goal

Pull me out of deep-focus work so I'm mentally done by end of day on weekdays,
**without working right up to the interview**. A heads-up notification fires a lead
window ahead so I can find a stopping point *before* the interview interrupts; then the
whole interview arrives at once, with no time pressure, and the day is saved.

## Sequence

1. **heads-up notify** — "Almost time to wrap up the day. The interview opens in N min —
   start finding a stopping point." Fires `FERN_LEAD_MIN` (default 15) before the interview.
2. **interview** — the whole thing as **one dialog** (all questions at once):
   - "What did you get done today?"
   - (multi-line) "What's most important to start with tomorrow? Check your calendar."
     Full detail; bullet lists welcome.
   - "In one line: the 1–2 things to start with first." The short version `begin`
     resurfaces (keeps the morning notification brief, full detail stays in the file).
   - "Any special items that should be included in today's summary?"
3. **run-hook** — the save-progress hook, incorporating the interview answers (esp. the
   special items).
4. **nag notify** — "That's it — you're done. Wrap up and step away now." A `critical`
   (sticky) nag, not a soft sign-off.

## Timing model

- **Trigger:** systemd user timer at the heads-up time, `Mon..Fri` (public default
  `15:15`).
- **Heads-up → interview:** `FERN_LEAD_MIN` minutes (default 15). So the default timer at
  15:15 warns at 15:15 and opens the interview at 15:30.
- **No short re-show timer:** the dialog doesn't re-pop on a short timer (that was
  clobbering answers in progress) — it sits open. The only limit is an overall cap,
  `FERN_FORM_TIMEOUT_SEC` (default 1 h), passed to the dialog as the *remaining* time so a
  left-open form auto-closes exactly at the cap. Past the cap with no answer, wrap still
  runs save-progress — just **without** interview answers — so the day is saved either way.
  If the dialog is *closed* before the cap, it re-shows (the nag).

## Architecture

- **Runner:** a single process started by the timer. It waits to `FERN_START` (a no-op
  when the timer fires it on time; guards an early manual launch), sends the heads-up,
  sleeps the lead, then shows the dialog. On submit — or once `FERN_FORM_TIMEOUT_SEC`
  passes with no answer — it writes the day file, runs the save-progress hook, and fires the
  nag.
- **One dialog, many fields — two renderers, one separator.** Preferred: **`yad --form`**
  (`--columns=1 --scroll`), each question as a full-width label (`:LBL`) with a full-width
  multi-line box (`:TXT`) stacked below it — the question-line / answer-field-line layout.
  Fallback when yad is absent: **`zenity --forms`** (`--add-entry` / `--add-multiline-entry`,
  a label-left grid; multi-line forms fields need zenity ≥ 4.2). Both join fields with an
  ASCII unit separator (`\x1f`, which won't occur in typed text) and split back into answers
  aligned with the question order; multi-line answers and blank middle fields both survive.
  Two yad quirks handled on the way out: `:LBL` emits an empty output field (so answers land
  at odd indices), and `:TXT` escapes newlines/tabs to literal `\n`/`\t` (unescaped on read).
- **Responses:** accumulate in `<state>/YYYY-MM-DD.md`, one Q/A block each (written only
  after a successful submit), so the hook can consume them and there's a daily record.

## Decisions

- [x] Response mechanism: **single dialog, all questions at once** — **`yad --form`**
      preferred (full-width question label above a full-width multi-line box, stacked),
      **`zenity --forms`** as the fallback.
- [x] Lead warning: **heads-up notification `FERN_LEAD_MIN` before the interview** so I
      stop working *before* being interrupted, not at the moment of interruption.
- [x] No short re-show timer: **don't re-pop the dialog on a short timer** — that was
      clobbering in-progress typing. Re-show only if the dialog is actively *closed*.
- [x] Overall cap: **`FERN_FORM_TIMEOUT_SEC` (default 1 h)** caps the whole interview
      phase; past it, **save-progress runs without the interview answers** so a walked-away
      day is still captured, rather than saving nothing.
- [x] Final step: **a nag-style `critical` "step away now"**, not a soft sign-off.
- [x] ~~Standalone project~~ **Folded into Fern** (2026-09-16); no shared *code*
      yet (own notify/chime helpers, own `FERN_*` config) — that unification is deferred.
- [x] "Check your calendar" is a *reminder*, not a calendar integration.
- [x] Language: **bash** for now (Python still open; more of a candidate here).

## save-progress step (step 3)

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
      doesn't cover the save step) and use absolute paths (user services don't inherit
      your interactive `PATH`). Test by hand before trusting it to the timer.
- [x] **Diagnosis wired:** the save step's output+exit go to
      `<state>/log/save-progress-DATE.log`; a `wd:save_result` marker
      lands in the day file; failure -> critical notify that evening.

## Be-done nag (final step) — composition

The final step is a **pluggable hook** (`FERN_GOODNIGHT_CMD`, already wired; default =
a one-shot `critical` "step away now" nag notification). The recommended composition is a
NEW Fern feature (`ff-goodnight`) that provides a **presence-aware, escalating, sticky
clock-off nag** — because Fern already owns presence detection + escalation +
acknowledgment, and a "you should be logged off" nag is the inverse of its break nag, and
it should STOP once you actually leave the keyboard (which wrap can't detect on its own).
wrap's final step would just trigger it. If Fern isn't installed, the plain nag notify is
the fallback. Not built yet — awaiting go-ahead.

## begin (morning bookend)

`bin/ff-begin` + a Mon–Fri 09:00 timer: reads the most recent prior day file, pulls
the short `<!-- wd:top -->` answer (falling back to `<!-- wd:tomorrow -->` for older
files), and shows it ("Start here (from <day>): …") as a zenity info popup +
notification. One-shot by design. Relies on the keyed markers wrap writes. On each run
it also grooms the day-files directory, pruning files older than `FERN_DAY_RETAIN_DAYS`
(default 7; the read happens first, so the resurfaced note is never at risk).
