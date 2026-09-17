# Fern — TODO

## Known issue: pointer drift pins the idle counter (breaks never auto-credit)

**Confirmed 2026-09-15 on the ThinkPad P1 daily driver.** Phantom pointer events
(TrackPoint drift) reset GNOME's `GetIdletime` every 1–2 s *intermittently*, so a real
absence often never reaches `FERN_ACTIVITY_GAP` and no break is credited — you get nagged even
after stepping away (observed `stretch_start` frozen ~100 min with `nag_level` climbing).
A 20 s hands-off sample showed idle pinned <3 s; later it climbed to 460 s — i.e. bursty,
not a constant pin. The rolling detection log now records raw idle per tick to characterize
the burst pattern.

- **Primary fix is OS-level**, not Fern: reduce TrackPoint sensitivity / enable
  libinput palm-and-drift rejection, or disable the TrackPoint if unused. Documented in the
  README "Pointer drift" note; a ready fix/test/undo lives in
  `cookbook/thinkpad-trackpoint-drift/` (disables just the nub via `ID_INPUT_POINTINGSTICK`
  udev rule — the daily-driver's own remedy).
- [ ] Consider a Fern-side drift tolerance *only if the OS fix is insufficient*: e.g.
      require idle to hold above a floor across N consecutive ticks before trusting a low
      reading, or a "credit a break if idle exceeded the gap at any point since the last
      real input burst" heuristic. Both are fragile (can't cleanly separate drift from real
      micro-activity); prefer the OS fix. The audio signals do NOT help here — they only
      pull toward "present," never toward crediting a break.

## Known issue: audio-out can self-sustain the nag (disabled for now)

**Found 2026-09-16.** `audio-out` presence keyed on a sink-input merely *existing*, which
the permanent uncorked-but-silent `speech-dispatcher-dummy` stream pinned to "present" 24/7
— the break clock never saw an absence and nagged indefinitely. Narrowed `ff_audio_out_active`
to a sink in RUNNING state (ignores the dummy), but that exposed a deeper flaw: **the nag
itself plays a sound** (`canberra-gtk-play`, `ff-tick`), so a stray beep briefly drives a
sink RUNNING. A single-tick sample can't tell Fern's own beep from real playback, so
audio-out can read that beep as presence and keep nagging itself. Not a tight loop (beep is
~1 s, tick is ~2 min) but a real intermittent self-trigger.

**Disabled for now**: `audio-out` dropped from the daily-driver config and marked unsafe in
`ff.conf.example`. `audio-in` still covers meetings.

- [ ] Redesign before re-enabling: **debounce** RUNNING across a window that exceeds the
      longest nag beep sequence, so sporadic alarm sounds can't count — only sustained
      playback (RUNNING held across N consecutive ticks / T seconds) should. Optionally also
      exclude Fern's own sound event. Leave audio-out off until this lands.

## Possible rewrite to a real language (Python?)

Raised 2026-09-15: config/state handling and the stacking-signal logic are approaching the
complexity where bash's ergonomics (string-typed config, ad-hoc state files, no real data
structures/tests) start to cost more than the zero-dependency install buys. Open question,
not a committed plan.

- [ ] Weigh: a Python rewrite gets typed config, unit tests, and cleaner signal composition,
      but trades away the "bash + systemd, nothing to install" property and adds an interpreter
      + venv/deps to the install story (which the privacy/portability goals value).
- [ ] If pursued, keep the host shim (systemd/notify/idle) thin and put only the state
      machine + config in Python; do a feasibility pass first (mirror the cross-platform
      section's "host concerns" framing).

## wrap save target: journal vs. day file (deferred)

**Raised 2026-09-17.** `ff-begin` currently resurfaces a short answer straight from the
day file, and `FERN_BEGIN_APPEND` nudges toward the journal ("look at yesterday's journal
for more"). Open question: should begin (or the save step) treat a richer journal as the
canonical "more detail" source, and how much should the day file duplicate it?

**Deferred deliberately.** The save action is pluggable (`FERN_SAVE_PROGRESS_CMD`), and the
daily-driver wires it to Claude + Logseq — a large, personal investment we do NOT want to
bake into the tool. It is not automatic that another user has a journaling piece at all, or
that their save command produces anything beyond the day file. So begin must keep working
from the day file alone, and any journal coupling stays optional.

- [ ] Decide the contract later: does the day file stay self-sufficient (begin never needs
      the journal), or does begin gain an optional, configurable "open/summarize the journal"
      path for users who have one? Keep the day-file-only path as the floor either way.

## Calendar presence (distant optional — deferred)

A `calendar` presence signal would catch no-audio meetings (in-person, phone, muted +
deafened) that the audio signals miss. **Deferred**: for a work-from-home user with no
in-person/hallway meetings its residual value is small, and it adds a big new install hurdle
(Google OAuth) that every new user would inherit. If ever built: keep it a power-user opt-in
that syncs today's busy-intervals to a state file out-of-band, so the tick stays offline.

## Move break detection fully off session-watching

The break guard now uses **desktop presence** (GNOME/Mutter `IdleMonitor` idle time)
as its primary signal, with the legacy typed-prompt scan (`ff_last_human_activity`)
kept only as a fallback under `FERN_PRESENCE=auto` / `typed`.

Session-transcript watching is a poor proxy for "is the human at the keyboard": it
misreads long autonomous agent runs and diff-reading as breaks, and background agent
activity as engagement. Presence is the correct signal. The intent is to eventually
drop session-watching from the break path **entirely**.

- [ ] Decide whether to retire the `typed` / auto-fallback path for break detection
      once presence has proven reliable on the daily-driver box (GNOME/Wayland).
- [ ] Broaden the presence signal beyond GNOME (see **Cross-platform support** below)
      before removing the fallback.
- [ ] Confirm `GetIdletime` behavior across screen-lock, suspend/resume, and multiple
      seats/sessions before trusting presence as the sole signal.
- [ ] Once the above hold, remove `ff_last_human_activity` from the break-guard path
      (keep the two-stage typed-prompt scan only where it's genuinely needed).

**Do NOT** remove session-watching from **answer capture** — Job A legitimately needs
per-session transcript mtimes and typed-prompt content to detect a walked-away session
and distill its last Q/A. Presence is about *the human*; capture is about *a session*.

## Cross-platform support (map for a future contributor)

**Status: speculative.** Fern is bash + systemd, i.e. Linux-only today. Whether
full macOS/Windows support is worth building is an open question — this section exists to
map the shape of the work so anyone who *does* want it can judge the cost, not as a
committed plan.

The key insight: **the presence query is the easy part.** Reading "seconds since last
input" is a single, roughly-equivalent call on all three platforms, and Fern's
away → credit → nag state machine is already platform-neutral logic. The real cost is the
**host shim** around it — scheduler, notifications, and getting the poller into a context
that can actually see the interactive user's input. That's a non-trivial install-logic
tree, and it multiplies per OS.

### The four host concerns, per platform

| Concern         | Linux (have)                         | macOS                                             | Windows                                                    |
|-----------------|--------------------------------------|---------------------------------------------------|-----------------------------------------------------------|
| Idle query      | Mutter `GetIdletime` (session D-Bus) | `HIDIdleTime` via `ioreg` (ns), or CGEventSource  | `GetLastInputInfo` + `GetTickCount` (ms)                  |
| Scheduler       | systemd user timer                   | LaunchAgent (per-user)                            | Task Scheduler (at-logon, user ctx) or tray app          |
| Notifications   | `notify-send` (libnotify)            | `osascript` / UNUserNotification                  | toast (BurntToast / WinRT)                                |
| Session context | must reach the session bus           | must run in the GUI/console session               | must be OUT of Session 0 (services can't see user input) |

### Presence query notes

- **Linux, non-GNOME.** Even staying on Linux, `idle` is GNOME-only right now. Other
  backends, selected like the LLM backend: X11 (`xprintidle`), wlroots
  (`ext-idle-notify` / swayidle), KDE (KIdleTime / org.freedesktop.ScreenSaver), and
  `loginctl` IdleHint (present but unreliable on Wayland today).
- **macOS.** `ioreg -c IOHIDSystem | awk '/HIDIdleTime/ {print int($NF/1000000000); exit}'`
  → idle seconds. No Accessibility/TCC grant needed for idle time (unlike event taps).
- **Windows.** `GetLastInputInfo` via a small PowerShell P/Invoke; idle = `(GetTickCount() - dwTime)/1000`.

### The hard parts (why this may not be worth it)

- **Session-context traps differ per OS** and are the most likely source of silent
  failure: Linux (session bus reachable from the unit — solved here), macOS (must be a
  GUI-session LaunchAgent, not a LaunchDaemon), Windows (Session 0 isolation — a service
  will never see user input; must run in the user session).
- **Three notification stacks** with different urgency/stickiness/escalation semantics;
  the current escalating-sticky-critical behavior won't map cleanly.
- **Three installers.** `install.sh` assumes systemd/XDG. Real support means an installer
  per platform, or a rewrite onto one cross-platform runtime — a bigger decision than the
  idle query implies, and worth its own feasibility pass before committing.

### If someone picks this up

- [ ] Factor `ff_idle_seconds` into a selectable presence backend (mirror the LLM-backend
      pattern) — cheap, and useful for non-GNOME **Linux** even if mac/Windows never happen.
- [ ] Decide host strategy before porting: keep three native host shims, or move the whole
      tool onto one cross-platform runtime. Do a feasibility pass first.
- [ ] Only then port scheduler + notifications + installer per target OS.

## Validation

- [x] `GetIdletime` answers from inside the `ff.service` systemd user unit
      (verified via `systemd-run --user` — returned a live idle value; `install.sh`
      imports `DBUS_SESSION_BUS_ADDRESS` and the service already used `gdbus --session`).
- [ ] Confirm `GetIdletime` behavior across a real screen-lock and suspend/resume cycle
      (expected: idle keeps climbing → break credited; unobserved).
- [ ] Motionless-engagement edge: sitting >10 min with no input while reading/meeting
      would false-credit a break. The `audio-in`/`audio-out` signals now cover the *meeting*
      case (mic/speaker in use holds the clock). Pure silent reading is still uncovered; add
      a tiebreaker only if it actually bites (an agent-file-activity tiebreaker reintroduces
      the overnight-agent false positive, so avoid unless proven necessary).
- [ ] Validate `audio-in` against a real meeting (mic muted vs unmuted); confirm the stream
      persists through silence (the mic-while-muted case). `audio-out` validation is deferred
      — it's disabled pending the debounce redesign (see the audio-out known-issue section).
