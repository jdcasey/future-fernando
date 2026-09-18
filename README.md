# Fernando from the Future

*Fern* — an insistent but well-meaning assistant that manages your *future* stress.

[![security](https://github.com/jdcasey/future-fernando/actions/workflows/security.yml/badge.svg)](https://github.com/jdcasey/future-fernando/actions/workflows/security.yml)

Supports for long, hyperfocused sessions with [Claude Code](https://claude.com/claude-code),
built for AuDHD / ADHD working styles. Everything is **fully automatic** — none of it is
something you have to remember to do:

- **[Break guard](#break-guard)** — an escalating, hard-to-ignore reminder to step away
  after ~60 min of continuous work.
- **[Answer capture](#answer-capture)** — when you get pulled away mid-thread, Fern saves
  the last question and its answer so you can find it later.
- **[Wrap & begin](#end-of-day-wrap--morning-begin)** — weekday bookends that
  walk you out of deep focus at day's end and point you back to it in the morning.

## The daily loop

The point is that there is almost nothing to do. After a one-time `./install.sh`, a
background timer does the watching; you just work.

1. **Work normally** in Claude Code. Nothing to start, arm, or check in.
2. **When the break nag fires** (~60 min of continuous typing), you have two honest
   options — both reset the clock:
   - Just walk away. A real ≥10-min quiet gap credits the break on its own.
   - Run `ff-afk` first if the banner is blaring and you want it to hush while you get up,
     *then* actually leave. `ff-afk` only buys a short grace window; it does **not** count
     as a break, so keeping working through it brings the nag back. (You never *have* to
     run `ff-afk` — walking away is enough.)
   - If you truly can't step away yet, `ff-pause [30m]` hushes it for a bounded window
     **without** crediting a break — the clock keeps running, so you're nagged again when
     the pause ends. It auto-expires (capped at 2h); `ff-unpause` ends it early.
3. **When you get pulled away mid-thread**, do nothing. Fern notices the session
   went idle and writes a `QUESTION-*.md` into that project's `.temp/`. Come back later
   and read it to recover "what did I ask, what was the answer?" without re-reading the
   transcript.
4. **Check in any time** with `ff-status` to see where you are in the current
   stretch and how long until the next reminder. `ff-status --log` shows the rolling
   detection log — what each presence signal read on every tick — for when the guard
   behaves in a way you want to diagnose.

That's the whole loop: work → get nudged to break → step away → find your captured
answers waiting. Everything below the feature summaries is detail on how each piece works
and how to tune it.

---

# Features

## Break guard

After ~60 minutes of *continuous* work at the keyboard, Fern starts an escalating, sticky
desktop reminder to take a break. It is deliberately hard to ignore, and it can't be
silenced without actually stepping away: a real ≥10-minute absence from the keyboard
credits the break and resets the clock on its own.

- `ff-afk` hushes the nag immediately but only buys a short grace window — if you keep
  working through it instead of leaving, the nag comes back. It does **not** count as a
  break.
- `ff-pause [DURATION]` is for when you genuinely *can't* break (a long meeting, an
  incident). It silences the nag for a bounded window **without** crediting a break, so you
  come back still owing one. It auto-expires (default 30 min, capped at 2h); `ff-unpause`
  ends it early.

"Continuous work" is measured from **desktop presence**, not typed prompts — watching a
long agent run or reading a diff counts as working, and only actually leaving the keyboard
credits a break. See [How it works](#how-it-works) and [Break guard details](#break-guard-details).

## Answer capture

When a session goes idle because you walked away or got pulled to another tab, Fern
distills the last question and its answer into a `QUESTION-<slug>-<date>.md` file in that
project's `.temp/` — so you can find "what did I ask and what was the answer?" later
without re-reading a transcript. No manual step; nothing to trigger.

Only the last real human-typed exchange is captured; automation and command runs are
skipped. The distillation is done by a pluggable LLM backend (hosted `claude` by default,
or a fully-offline local `ollama`). See [Answer capture details](#answer-capture-details)
and [Capture backends](#capture-backends).

## End-of-day wrap & morning begin

Two day-shape bookends, each on its own weekday `systemd` timer. Where the break guard and
capture run every couple of minutes, these fire once a day. Both notify under the name
**Fernando**. (Incubating — see
[`docs/wrap-design.md`](docs/wrap-design.md) for rationale and open decisions.)

**wrap** (Mon–Fri, 3:15pm) gradually pulls you out of deep focus. It poses four
interview questions, each as a **zenity popup** that re-shows every ~2 min until you
answer (the nag), spaced ~10 min apart:

1. What did you get done today?
2. What's most important to start with tomorrow? (a **multi-line box** — bullet lists
   welcome; this is the full detail, saved to your day file/journal, and a reminder to
   check your calendar)
3. In one line: the 1–2 things to start with first. (the short version begin resurfaces)
4. Any special items for today's summary?

After the last answer it runs the **save-progress hook**, then a final "you're all done"
notification. Answers accumulate in `<state>/YYYY-MM-DD.md`, each tagged with a
stable `<!-- wd:KEY -->` marker so other tools can extract a specific answer. Adding the
short question lets the routine run a little longer rather than starting earlier.

**begin** (Mon–Fri, 9am) reads your **previous working day's** file and resurfaces the
short "1–2 things to start with" answer (a zenity popup + notification) so you begin
pointed the right way — keeping the notification brief while the full detail stays in the
day file. One-shot; it reads the keyed marker (falling back to the full "tomorrow" answer
for older files). Set `FERN_BEGIN_APPEND` to add a fixed footer line (e.g. a nudge to open
your journal). On each run it also grooms the day-files directory, pruning files older than
`FERN_DAY_RETAIN_DAYS`.

To avoid popups all evening on a day you walk away, wrap hard-stops `FERN_HARD_STOP_MIN`
minutes after it starts (default 120). Nothing is saved if it backstops mid-interview. Tuning,
the save-progress hook, and the full config table are in
[wrap/begin configuration](#wrapbegin-configuration).

---

# Details & tuning

## How it works

The two every-few-minutes jobs read different signals, each chosen to answer a different
question:

- **Break guard — desktop presence (stackable signals).** The question is "are you
  *present*?", not "are you typing to Claude?". Long autonomous agent runs and reading a diff
  are real work but generate few keystrokes, so a typed-prompt signal would mistake them for a
  break; conversely a background agent bumping a transcript's mtime while you're away would
  look like engagement. The base signal is **desktop idle time** — seconds since your last
  real keyboard/mouse input — from GNOME/Mutter's `IdleMonitor`. Because meetings are engaged
  work with no keyboard input, you can **stack** additional presence signals so a meeting
  isn't mistaken for a break: `audio-in` (your mic is live) and `audio-out` (audio is playing —
  incoming meeting audio while muted, or a recording you're reviewing). Signals compose via
  `FERN_PRESENCE` (e.g. `idle,audio-in,audio-out`); you're "present" if **any** enabled signal
  says so. See [Presence signals](#presence-signals) below.
- **Capture — a single session going stale.** Claude Code writes a transcript
  (`~/.claude/projects/<slug>/<uuid>.jsonl`) per session and bumps its mtime on every
  interaction. When one session's own mtime has been idle for a few minutes, you left it
  mid-thread; that triggers capture for that session.

A `systemd` user timer runs one scan (`ff-tick`) every ~2 minutes. No daemon, no
polling loop, no root.

### Why presence, not typed prompts (GNOME only, for now)

Earlier versions clocked the break guard off your last *typed Claude prompt*. That breaks
down for agent-heavy work: fire off a patch review, watch the agent grind and read diffs
for 15–25 minutes, type the next prompt — and every one of those think-gaps looks
identical to walking away, so the guard keeps crediting phantom breaks and never nags. You
can work relentlessly all day and never accumulate a continuous hour.

The fix is to clock off **desktop presence** — seconds since real keyboard/mouse input,
read from GNOME/Mutter's `IdleMonitor` over the session bus. Watching an agent counts as
work; only actually leaving the keyboard credits a break. This currently requires
**GNOME** (Wayland or X); on any other desktop `FERN_PRESENCE=auto` falls back to the legacy
typed-prompt signal. A portable presence backend for other desktops is tracked in
[`TODO.md`](TODO.md).

## Presence signals

Set `FERN_PRESENCE` to a profile name or a comma-list of signals. They **stack** — you're
present if any enabled one says so, so a live mic in a meeting holds the clock even with no
keystrokes.

| Value | Meaning |
|-------|---------|
| `default` | `idle,audio-in` — recommended; fixes the meeting blind-spot |
| `minimal` | `idle` only — meeting-blind, least ambient sensing |
| `off` | no ambient sensing at all; rely on `ff-afk` / `ff-pause` |
| `auto` | back-compat: idle if available, else typed |
| *list* | e.g. `idle,audio-in,audio-out` — compose your own |

Signals: `idle` (desktop input), `audio-in` (mic in use), `audio-out` (speaker in use;
noisier — enable only if you don't casually play audio through speakers), `typed` (legacy).
Audio signals are **additive** — combine with `idle` for the away baseline. They need
`pactl` (PipeWire/PulseAudio).

> **Pointer drift:** on some hardware (e.g. a ThinkPad TrackPoint) phantom pointer events
> keep the idle counter pinned low, so a real absence never reaches `FERN_ACTIVITY_GAP` and
> breaks are never auto-credited (you get nagged even after stepping away). The fix is at
> the OS level — reduce TrackPoint sensitivity / enable palm-and-drift rejection. Use
> `ff-status --log` to confirm the pattern (idle staying low across a known absence).
> If you don't use the TrackPoint at all, `cookbook/thinkpad-trackpoint-drift/` has a
> ready fix/test/undo (disables just the nub via a udev rule).

## Break guard details

- Continuous activity is measured from the enabled presence signals, ignoring absences
  shorter than `FERN_ACTIVITY_GAP` (10 min).
- At `FERN_BREAK_INTERVAL` (60 min) it fires a `critical`-urgency notification (sticky on
  GNOME) plus a sound, and **escalates** each unacknowledged re-fire — harsher sound, more
  repeats, updated banner text.
- A genuine ≥`FERN_ACTIVITY_GAP` absence (you actually stepped away, or the computer
  suspended/slept) is the only thing that *credits* the break and resets the clock.
- `ff-afk` hushes the nag now and opens a `FERN_BREAK_GRACE` (5 min) grace window so you can
  leave without the banner blaring — but it does **not** reset the clock. Keep working
  (presence stays live) and the nag returns when grace expires.
- **Settling:** once you've actually been idle for at least `FERN_BREAK_GRACE` but haven't yet
  reached the full `FERN_ACTIVITY_GAP`, the guard stays quiet and lets the clock run to the
  credit — it won't re-nag someone who is visibly walking away. Come back (presence returns)
  and nagging resumes; stay away and the gap credits the break. This is presence-based, so it
  applies whether or not you ran `ff-afk`.
- `ff-pause [DURATION]` is for when you **can't** step away (a meeting you can't leave, an
  incident). It silences the nag for the window but does **not** credit a break — the stretch
  clock keeps running, so you return overdue and get nagged as soon as it expires. It
  auto-expires (default 30 min, capped at `FERN_PAUSE_MAX` = 2h) so a forgotten pause can't
  disable the guard all day; `ff-unpause` ends it early.
- Clicking/dismissing the banner does nothing by design (a glance-and-swat is exactly the
  failure this guards against).
- Each nag also carries one **grounding suggestion** picked at random (breathing, 5-4-3-2-1,
  and similar), under a "leave the room / look away from the screen" lead-in — a concrete
  thing to do with the break, not just a command to take one. Edit the list at
  `data/grounding.txt` (installed to `<data>/ff/data/grounding.txt`) to add your own;
  turn it off with `FERN_GROUNDING_ENABLED=0` or point `FERN_GROUNDING_FILE` at your own file.

### Rolling detection log

Every tick appends one line to `<state>/log/ff-YYYYMMDD.log` recording what each presence
signal read, which signal is holding you present (`src=`), and the decision taken (`active`,
`paused`, `grace`, `settling`, `credit-break`, `nag:N`). `ff-status` likewise shows the
winning signal on its presence line (e.g. "via keyboard/mouse", "via mic (in a call)").
It's the audit and diagnostic trail — view it with `ff-status --log`. Daily files, retained
`FERN_LOG_RETAIN_DAYS` (3) days. Like everything else, it stays on your machine and records
only presence facts and decisions, never any content.

## Answer capture details

- On idle transition, Fern asks an LLM (see [Capture backends](#capture-backends) below) to
  distill the recent user/assistant turns and writes `QUESTION-<slug>-<session-id>.md`
  containing the question, a concise answer/conclusion, and light context. Trivial tails are
  skipped. The full session id is embedded in the file as an HTML comment for traceability.
- **One file per session.** The filename carries a short session id, and each recapture
  **supersedes** that session's prior file. A tab you leave open and that gets recaptured on
  every idle cycle collapses to a single, current digest — the latest thing you walked away
  from — instead of a pile of near-duplicates. Distinct sessions keep distinct files, so two
  different tabs parked on the same topic still produce two files. A failed or "nothing worth
  saving" recapture leaves the previous file untouched.
- Each workspace's `.temp/` is groomed on capture: `QUESTION-*.md` older than
  `FERN_CAPTURE_RETAIN_DAYS` (default 14) are pruned.
- Only the **last real exchange** is fed to the model — the most recent human-typed prompt
  and the assistant text that followed it. That is the highest-signal, smallest input
  (which also keeps a local model fast). Sessions with **no** human-typed prompt — command
  or automation runs (e.g. `/save-progress`) and Fern's own background LLM calls —
  aren't a "what did I ask?" and are skipped without spending a model call.
- Output goes to each session's own `<project>/.temp/` by default (override with
  `FERN_CAPTURE_DIR` to funnel everything into one folder).
- The raw transcript already persists everything permanently; the capture file is just the
  **findable, digested** version.

## What Fern observes, and what it deliberately doesn't

Presence detection reads some of the same channels workplace-monitoring software does, so
the boundaries are drawn deliberately. The line isn't the channel — it's **content and
exfiltration**, and Fern does neither:

- **Existence, not content.** The break guard reads only *that* input happened (idle
  seconds) and *that* an audio stream exists (`pactl`). It never inspects audio, never reads
  what you type, never identifies apps or callers.
- **Local only.** No presence signal leaves your machine. The tick is offline; the only
  network use is the optional `claude` capture backend (switch to `ollama` for fully
  offline capture — see below).
- **Auditable.** `ff-status` shows exactly which signals are enabled and what each reads;
  `ff-status --log` shows the full per-tick record. Nothing is hidden.
- **Opt out at any granularity.** Disable individual signals via `FERN_PRESENCE`, drop to
  `minimal` (idle only), or `off` for no ambient sensing at all (then use `ff-afk`/`ff-pause`).
  `audio-out` is opt-in precisely because speaker monitoring is the most surveillance-adjacent
  signal. Answer capture is separately disableable with `FERN_CAPTURE_ENABLED=0`.

## Capture backends

The distillation is the only part that uses a model, and it is pluggable via
`FERN_LLM_BACKEND`:

- **`claude`** (default) — the hosted Claude Code CLI. Fast, best quality; each capture is a
  small API call, so it has a (small) cost and needs network.
- **`ollama`** — a local model over Ollama. Fully offline, zero cost, and **nothing leaves
  your machine** — which matters, since capture files distill your session content. Quality is
  lower than a hosted model; on a CPU-only box use a small model (`llama3.2:3b`, `gemma2:2b`).
  Because capture runs *after* you walk away, its latency is not in your way.

Switch by setting `FERN_LLM_BACKEND` in the config, and pick the model with `FERN_CLAUDE_MODEL` /
`FERN_OLLAMA_MODEL` (or `FERN_LLM_MODEL` to override whichever is active). The backend is a shared
gateway (`lib/ff-llm.sh`) that future Fern features can reuse.

**Compare quality directly** on a real session before you commit to one:

```sh
ff-capture --compare --latest        # run BOTH backends, print side by side + timings
ff-capture --dry-run --backend ollama --model llama3.2:3b --latest
```

### Using the local (ollama) backend

```sh
# 1. install ollama (https://ollama.com)
(dnf search ollama && sudo dnf install -y ollama) || (curl -fsSL https://ollama.com/install.sh | sh)

# 2. start the ollama service (installer usually enables it; if not:)
sudo systemctl enable --now ollama       # system service
#   ...or run it in the foreground without root:  ollama serve

# 3. pull a small model
ollama pull llama3.2:3b

# 4. point Fern at it (see next code block)
```

Then set these in `~/.config/ff/ff.conf`:

```sh
FERN_LLM_BACKEND="ollama"     # switch capture from hosted claude to the local model
FERN_CAPTURE_TIMEOUT=180      # per-capture budget. A 3B model on CPU distills a typical
                            # session in 20-55s; a rare max-length answer can approach
                            # ~140s. 180 leaves headroom. (On a GPU host, seconds.)
FERN_CAPTURE_PER_TICK=1       # only one slow local capture per tick, so two can't blow
                            # the service's 300s TimeoutStartSec
```

`FERN_LLM_BACKEND` and `FERN_CAPTURE_TIMEOUT` are the two that matter most for local use:
the first does the switch, the second keeps slow-but-valid captures from being killed
mid-generation. To change models, set `FERN_OLLAMA_MODEL` (e.g. `llama3.1:8b`).

## wrap/begin configuration

Set these for the timers in `~/.config/ff/ff-workday.env` (`KEY=value`, one per line,
no shell quoting; read by both units):

| Var | Default | Meaning |
|-----|---------|---------|
| `FERN_START` | `15:15` | Clock time the sequence anchors to |
| `FERN_INTERVAL_MIN` | `10` | Minutes between question slots |
| `FERN_NAG_SEC` | `120` | Re-show the popup this often until answered |
| `FERN_HARD_STOP_MIN` | `120` | Safety backstop after start |
| `FERN_SOUND_ENABLED` | `1` | Play chimes |
| `FERN_SAVE_PROGRESS_CMD` | *(empty)* | Step-4 hook (**required**); a command, run with `FERN_ANSWERS_FILE` exported |
| `FERN_SAVE_PROGRESS_HOOK` | `~/.local/bin/ff-save-progress-hook` | Fallback hook path; used if `FERN_SAVE_PROGRESS_CMD` is unset and this is executable |
| `FERN_GOODNIGHT_CMD` | *(empty)* | Step-5 hook; empty = one-shot "good evening" notify |
| `FERN_BEGIN_KEY` | `top` | Which wrap answer begin resurfaces (falls back to `tomorrow`) |
| `FERN_BEGIN_DIALOG` | `1` | begin shows a zenity popup (plus notification) |
| `FERN_BEGIN_APPEND` | *(empty)* | Fixed footer line appended to the begin notification |
| `FERN_DAY_RETAIN_DAYS` | `7` | begin prunes day files older than N days (`0` = keep all) |

Test the flow immediately (no waiting for 3:15): `FERN_INTERVAL_MIN=1 FERN_NAG_SEC=20 ff-wrap --now`.

### save-progress hook (required)

The save step is a **user-supplied hook** — this tool ships none, because how you persist a
day's answers is personal (a journal app, a notes repo, a markdown file, a headless agent
run). **`begin` and `wrap` refuse to run without one**: the interview only earns its
interruption if the answers can actually be saved, so both fail fast with a notification if no
hook is wired.

Wire it one of two ways:

- Set `FERN_SAVE_PROGRESS_CMD` to a command (this takes precedence), or
- Drop an executable at `FERN_SAVE_PROGRESS_HOOK` (default `~/.local/bin/ff-save-progress-hook`).

**Contract.** The hook is invoked with `FERN_ANSWERS_FILE` exported — the path to the day
file, a markdown document of the interview Q/A (see `docs/wrap-design.md`). Do whatever you
like with it; the exit code is recorded. Two gotchas for systemd runs: wrap long-running
hooks in `timeout` (the interview backstop doesn't cover the save step), and use absolute
paths for anything you shell out to (user services don't inherit your interactive `PATH`).
Test the hook by hand before trusting it to the timer.

**Diagnosis.** Every save-progress run is logged: full stdout+stderr to
`<state>/log/save-progress-YYYY-MM-DD.log`, a `wd:save_result` line (exit + log
path) in the day file, and a `critical` notification on failure that evening — so a
headless run you can't watch live is reviewable after the fact.

The `FERN_GOODNIGHT_CMD` seam (step 5) is where a presence-aware persistent clock-off nag
would compose in; unset, step 5 is a single notification.

## Command reference

All commands install to `~/.local/bin`. `ff-tick` is run by the timer; the rest are for you.

| Command | What it does |
|---------|--------------|
| `ff-status [--log [N]]` | Snapshot of the current stretch, presence signals, and capture backend. `--log` tails today's detection log (default 40 lines). |
| `ff-afk` | "Stepping away now" — hush the nag and open a short grace window. Does **not** credit a break. |
| `ff-pause [DURATION]` | Silence the nag without crediting a break (clock keeps running). Bare number = minutes; suffixes `s`/`m`/`h`. Default 30 min, capped at 2h. |
| `ff-unpause` | End an active pause early. |
| `ff-capture [OPTS] <TARGET>` | Run capture on one session on demand. `--dry-run`, `--compare` (both backends side by side), `--backend NAME`, `--model NAME`, `--latest`; `<TARGET>` = transcript path, session uuid, or `--latest`. |
| `ff-wrap [--now]` | Run the end-of-day interview sequence. `--now` starts immediately instead of anchoring to `FERN_START`. |
| `ff-begin` | Resurface the previous working day's "start with" note. |
| `ff-tick` | **Internal** — one scan pass (break guard + capture). Run by `ff.timer` every ~2 min. |

---

# Install & operation

## Requirements

- Linux with a `systemd` user instance and a desktop notification daemon (developed on
  Fedora + GNOME/Wayland).
- At least one capture backend: `claude` (Claude Code CLI) on your `PATH`, **or**
  [`ollama`](https://ollama.com) with a pulled model.
- `jq`, `curl`, `libnotify` (`notify-send`), `libcanberra-gtk3` (`canberra-gtk-play`),
  `glib2` (`gdbus`), and `flock`.
- Optional: `pactl` (PipeWire/PulseAudio) for the `audio-in` / `audio-out` presence signals.
  Without it the break guard still works on desktop idle; the audio signals are simply inert.
- Optional: `zenity` for the wrap end-of-day interview popups. Without it the break
  guard and capture are unaffected; only wrap can't prompt.

## Install

```sh
./install.sh
```

It installs the scripts to `~/.local/bin`, the units to `~/.config/systemd/user`, writes a
config to `~/.config/ff/ff.conf`, seeds a capture baseline (so your existing
sessions are **not** back-captured), and enables the timers (break-guard tick plus the
wrap/begin day-shape bookends).

Make sure `~/.local/bin` is on your `PATH` so `ff-afk` works from any terminal.

## Usage

```sh
ff-status                                 # where am I in the current stretch?
ff-status --log                           # rolling detection log (diagnose the guard)
ff-afk                                     # I'm stepping away — hush the nag now
ff-pause 30m                               # I can't break yet — hush without crediting one
ff-unpause                                 # end a pause early
ff-capture --compare --latest             # try capture backends on a real session
systemctl --user start ff.service # run one scan right now
journalctl --user -u ff.service   # service logs
```

## Configuration

Edit `~/.config/ff/ff.conf`. Every knob (timings, enable/disable each
feature, capture model, notification stacking, output location) is documented in
[`config/ff.conf.example`](config/ff.conf.example). The wrap/begin timers read a
separate `~/.config/ff/ff-workday.env` — see
[wrap/begin configuration](#wrapbegin-configuration).

## Uninstall

```sh
./uninstall.sh            # remove; keep config + state
./uninstall.sh --purge    # remove everything
```

## Caveats

- **Privacy:** capture files distill session content into `<project>/.temp/`. Keep `.temp/`
  in your `.gitignore` and treat those files as you would the session itself, or else set `FERN_CAPTURE_DIR`.
- **Cost:** each capture is a small headless model call. It's rate-limited
  (`FERN_CAPTURE_PER_TICK`) and deduplicated, but it is not free.
- **Desktop-bound:** notifications need the graphical session's D-Bus. Sessions run over
  SSH or in containers on another filesystem won't be seen.
- Capture quality depends on the model reading a truncated transcript tail; walking away
  mid-generation may yield a partial answer (it's marked as possibly incomplete).

## License

Apache License 2.0 — see [LICENSE](LICENSE) and [NOTICE](NOTICE). Set the copyright holder
before publishing.
