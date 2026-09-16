# Fernando from the Future

*Fern* — an insistent but well-meaning assistant that manages your *future* stress.

[![security](https://github.com/jdcasey/future-fernando/actions/workflows/security.yml/badge.svg)](https://github.com/jdcasey/future-fernando/actions/workflows/security.yml)

Supports for long, hyperfocused sessions with [Claude Code](https://claude.com/claude-code),
built for AuDHD / ADHD working styles — all fully automatic, so none of them is
something you have to remember to do:

1. **Persistent break guard.** After ~60 minutes of *continuous* work at the keyboard it
   starts an escalating, sticky desktop reminder to take a break. It is deliberately hard
   to ignore, and it can't be silenced without actually stepping away: a real ≥10-minute
   absence from the keyboard credits the break and resets the clock on its own. Running `fftf-afk`
   hushes the nag immediately, but only buys a short grace window — if you keep working
   through it instead of leaving, the nag comes back. When you genuinely *can't* break (a
   long meeting, an incident), `fftf-pause` silences it for a bounded window without crediting
   a break, so you come back still owing one.
2. **Automatic answer capture.** When a session goes idle because you walked away or got
   pulled to another tab, Fern distills the last question and its answer into a
   `QUESTION-*.md` file in that project — so you can find "what did I ask and what was the
   answer?" later without re-reading a transcript. No manual step; nothing to trigger.
3. **End-of-day winddown & morning windup.** Bookends for the working day: a weekday
   afternoon sequence that walks you out of deep focus with a short interview and saves the
   day's progress, and a morning nudge that resurfaces where you meant to start. See
   **[End-of-day winddown & morning windup](#end-of-day-winddown--morning-windup)** below.

## The daily loop

The point is that there is almost nothing to do. After a one-time `./install.sh`, a
background timer does the watching; you just work.

1. **Work normally** in Claude Code. Nothing to start, arm, or check in.
2. **When the break nag fires** (~60 min of continuous typing), you have two honest
   options — both reset the clock:
   - Just walk away. A real ≥10-min quiet gap credits the break on its own.
   - Run `fftf-afk` first if the banner is blaring and you want it to hush while you get up,
     *then* actually leave. `fftf-afk` only buys a short grace window; it does **not** count
     as a break, so keeping working through it brings the nag back. (You never *have* to
     run `fftf-afk` — walking away is enough.)
   - If you truly can't step away yet, `fftf-pause [30m]` hushes it for a bounded window
     **without** crediting a break — the clock keeps running, so you're nagged again when
     the pause ends. It auto-expires (capped at 2h); `fftf-unpause` ends it early.
3. **When you get pulled away mid-thread**, do nothing. Fern notices the session
   went idle and writes a `QUESTION-*.md` into that project's `.temp/`. Come back later
   and read it to recover "what did I ask, what was the answer?" without re-reading the
   transcript.
4. **Check in any time** with `fftf-status` to see where you are in the current
   stretch and how long until the next reminder. `fftf-status --log` shows the rolling
   detection log — what each presence signal read on every tick — for when the guard
   behaves in a way you want to diagnose.

That's the whole loop: work → get nudged to break → step away → find your captured
answers waiting. The rest of this README is detail on how each piece works and how to
tune it.

## How it works

The two jobs read different signals, each chosen to answer a different question:

- **Break guard — desktop presence (stackable signals).** The question is "are you
  *present*?", not "are you typing to Claude?". Long autonomous agent runs and reading a diff
  are real work but generate few keystrokes, so a typed-prompt signal would mistake them for a
  break; conversely a background agent bumping a transcript's mtime while you're away would
  look like engagement. The base signal is **desktop idle time** — seconds since your last
  real keyboard/mouse input — from GNOME/Mutter's `IdleMonitor`. Because meetings are engaged
  work with no keyboard input, you can **stack** additional presence signals so a meeting
  isn't mistaken for a break: `audio-in` (your mic is live) and `audio-out` (audio is playing —
  incoming meeting audio while muted, or a recording you're reviewing). Signals compose via
  `FFTF_PRESENCE` (e.g. `idle,audio-in,audio-out`); you're "present" if **any** enabled signal
  says so. See **Presence signals** below.
- **Capture — a single session going stale.** Claude Code writes a transcript
  (`~/.claude/projects/<slug>/<uuid>.jsonl`) per session and bumps its mtime on every
  interaction. When one session's own mtime has been idle for a few minutes, you left it
  mid-thread; that triggers capture for that session.

A `systemd` user timer runs one scan (`fftf-tick`) every ~2 minutes. No daemon, no
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
**GNOME** (Wayland or X); on any other desktop `FFTF_PRESENCE=auto` falls back to the legacy
typed-prompt signal. A portable presence backend for other desktops is tracked in
[`TODO.md`](TODO.md).

### Presence signals

Set `FFTF_PRESENCE` to a profile name or a comma-list of signals. They **stack** — you're
present if any enabled one says so, so a live mic in a meeting holds the clock even with no
keystrokes.

| Value | Meaning |
|-------|---------|
| `default` | `idle,audio-in` — recommended; fixes the meeting blind-spot |
| `minimal` | `idle` only — meeting-blind, least ambient sensing |
| `off` | no ambient sensing at all; rely on `fftf-afk` / `fftf-pause` |
| `auto` | back-compat: idle if available, else typed |
| *list* | e.g. `idle,audio-in,audio-out` — compose your own |

Signals: `idle` (desktop input), `audio-in` (mic in use), `audio-out` (speaker in use;
noisier — enable only if you don't casually play audio through speakers), `typed` (legacy).
Audio signals are **additive** — combine with `idle` for the away baseline. They need
`pactl` (PipeWire/PulseAudio).

> **Pointer drift:** on some hardware (e.g. a ThinkPad TrackPoint) phantom pointer events
> keep the idle counter pinned low, so a real absence never reaches `FFTF_ACTIVITY_GAP` and
> breaks are never auto-credited (you get nagged even after stepping away). The fix is at
> the OS level — reduce TrackPoint sensitivity / enable palm-and-drift rejection. Use
> `fftf-status --log` to confirm the pattern (idle staying low across a known absence).
> If you don't use the TrackPoint at all, `cookbook/thinkpad-trackpoint-drift/` has a
> ready fix/test/undo (disables just the nub via a udev rule).

### Break guard details

- Continuous activity is measured from the enabled presence signals, ignoring absences
  shorter than `FFTF_ACTIVITY_GAP` (10 min).
- At `FFTF_BREAK_INTERVAL` (60 min) it fires a `critical`-urgency notification (sticky on
  GNOME) plus a sound, and **escalates** each unacknowledged re-fire — harsher sound, more
  repeats, updated banner text.
- A genuine ≥`FFTF_ACTIVITY_GAP` absence (you actually stepped away, or the computer
  suspended/slept) is the only thing that *credits* the break and resets the clock.
- `fftf-afk` hushes the nag now and opens a `FFTF_BREAK_GRACE` (5 min) grace window so you can
  leave without the banner blaring — but it does **not** reset the clock. If no real quiet
  gap follows, the nag returns when grace expires.
- `fftf-pause [DURATION]` is for when you **can't** step away (a meeting you can't leave, an
  incident). It silences the nag for the window but does **not** credit a break — the stretch
  clock keeps running, so you return overdue and get nagged as soon as it expires. It
  auto-expires (default 30 min, capped at `FFTF_PAUSE_MAX` = 2h) so a forgotten pause can't
  disable the guard all day; `fftf-unpause` ends it early.
- Clicking/dismissing the banner does nothing by design (a glance-and-swat is exactly the
  failure this guards against).
- Each nag also carries one **grounding suggestion** picked at random (breathing, 5-4-3-2-1,
  and similar), under a "leave the room / look away from the screen" lead-in — a concrete
  thing to do with the break, not just a command to take one. Edit the list at
  `data/grounding.txt` (installed to `<data>/fftf/data/grounding.txt`) to add your own;
  turn it off with `FFTF_GROUNDING_ENABLED=0` or point `FFTF_GROUNDING_FILE` at your own file.

### Rolling detection log

Every tick appends one line to `<state>/log/fftf-YYYYMMDD.log` recording what each presence
signal read and the decision taken (`active`, `paused`, `grace`, `credit-break`, `nag:N`).
It's the audit and diagnostic trail — view it with `fftf-status --log`. Daily files, retained
`FFTF_LOG_RETAIN_DAYS` (3) days. Like everything else, it stays on your machine and records
only presence facts and decisions, never any content.

### Answer capture details

- On idle transition, Fern asks an LLM (see **Capture backends** below) to distill the
  recent user/assistant turns and writes `QUESTION-<slug>-<date>.md` containing the question,
  a concise answer/conclusion, and light context. Trivial tails are skipped.
- Only the **last real exchange** is fed to the model — the most recent human-typed prompt
  and the assistant text that followed it. That is the highest-signal, smallest input
  (which also keeps a local model fast). Sessions with **no** human-typed prompt — command
  or automation runs (e.g. `/save-progress`) and Fern's own background LLM calls —
  aren't a "what did I ask?" and are skipped without spending a model call.
- Output goes to each session's own `<project>/.temp/` by default (override with
  `FFTF_CAPTURE_DIR` to funnel everything into one folder).
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
- **Auditable.** `fftf-status` shows exactly which signals are enabled and what each reads;
  `fftf-status --log` shows the full per-tick record. Nothing is hidden.
- **Opt out at any granularity.** Disable individual signals via `FFTF_PRESENCE`, drop to
  `minimal` (idle only), or `off` for no ambient sensing at all (then use `fftf-afk`/`fftf-pause`).
  `audio-out` is opt-in precisely because speaker monitoring is the most surveillance-adjacent
  signal. Answer capture is separately disableable with `FFTF_CAPTURE_ENABLED=0`.

## Capture backends

The distillation is the only part that uses a model, and it is pluggable via
`FFTF_LLM_BACKEND`:

- **`claude`** (default) — the hosted Claude Code CLI. Fast, best quality; each capture is a
  small API call, so it has a (small) cost and needs network.
- **`ollama`** — a local model over Ollama. Fully offline, zero cost, and **nothing leaves
  your machine** — which matters, since capture files distill your session content. Quality is
  lower than a hosted model; on a CPU-only box use a small model (`llama3.2:3b`, `gemma2:2b`).
  Because capture runs *after* you walk away, its latency is not in your way.

Switch by setting `FFTF_LLM_BACKEND` in the config, and pick the model with `FFTF_CLAUDE_MODEL` /
`FFTF_OLLAMA_MODEL` (or `FFTF_LLM_MODEL` to override whichever is active). The backend is a shared
gateway (`lib/fftf-llm.sh`) that future Fern features can reuse.

**Compare quality directly** on a real session before you commit to one:

```sh
fftf-capture --compare --latest        # run BOTH backends, print side by side + timings
fftf-capture --dry-run --backend ollama --model llama3.2:3b --latest
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

Then set these in `~/.config/fftf/fftf.conf`:

```sh
FFTF_LLM_BACKEND="ollama"     # switch capture from hosted claude to the local model
FFTF_CAPTURE_TIMEOUT=180      # per-capture budget. A 3B model on CPU distills a typical
                            # session in 20-55s; a rare max-length answer can approach
                            # ~140s. 180 leaves headroom. (On a GPU host, seconds.)
FFTF_CAPTURE_PER_TICK=1       # only one slow local capture per tick, so two can't blow
                            # the service's 300s TimeoutStartSec
```

`FFTF_LLM_BACKEND` and `FFTF_CAPTURE_TIMEOUT` are the two that matter most for local use:
the first does the switch, the second keeps slow-but-valid captures from being killed
mid-generation. To change models, set `FFTF_OLLAMA_MODEL` (e.g. `llama3.1:8b`).

## End-of-day winddown & morning windup

Two day-shape bookends, each on its own weekday `systemd` timer. Where the break guard and
capture run every couple of minutes, these fire once a day. (Incubating — see
[`docs/winddown-design.md`](docs/winddown-design.md) for rationale and open decisions.)

**winddown** (Mon–Fri, 3:15pm) gradually pulls you out of deep focus so you're mentally
done by ~4:00. It poses three interview questions, each as a **zenity popup** that
re-shows every ~2 min until you answer (the nag), spaced ~10 min apart:

1. What did you get done today?
2. What's most important to start with tomorrow? (a reminder to check your calendar)
3. Any special items for today's summary?

After the last answer it runs the **save-progress hook**, then a final "you're all done"
notification. Answers accumulate in `<state>/YYYY-MM-DD.md`, each tagged with a
stable `<!-- wd:KEY -->` marker so other tools can extract a specific answer.

**windup** (Mon–Fri, 9am) reads your **previous working day's** file and resurfaces the
"what to start with tomorrow" answer (a zenity popup + notification) so you begin pointed
the right way. One-shot; it just reads the keyed marker.

To avoid popups all evening on a day you walk away, winddown hard-stops `FFTF_HARD_STOP_MIN`
minutes after it starts (default 120). Nothing is saved if it backstops mid-interview.

### winddown/windup configuration

Set these for the timers in `~/.config/fftf/fftf-winddown.env` (`KEY=value`, one per line,
no shell quoting; read by both units):

| Var | Default | Meaning |
|-----|---------|---------|
| `FFTF_START` | `15:15` | Clock time the sequence anchors to |
| `FFTF_INTERVAL_MIN` | `10` | Minutes between question slots |
| `FFTF_NAG_SEC` | `120` | Re-show the popup this often until answered |
| `FFTF_HARD_STOP_MIN` | `120` | Safety backstop after start |
| `FFTF_SOUND_ENABLED` | `1` | Play chimes |
| `FFTF_SAVE_PROGRESS_CMD` | *(empty)* | Step-4 hook; run with `FFTF_ANSWERS_FILE` exported |
| `FFTF_GOODNIGHT_CMD` | *(empty)* | Step-5 hook; empty = one-shot "good evening" notify |
| `FFTF_WINDUP_KEY` | `tomorrow` | Which winddown answer windup resurfaces |
| `FFTF_WINDUP_DIALOG` | `1` | windup shows a zenity popup (plus notification) |

Test the flow immediately (no waiting for 3:15): `FFTF_INTERVAL_MIN=1 FFTF_NAG_SEC=20 fftf-winddown --now`.

### save-progress hook

The save step is pluggable via `FFTF_SAVE_PROGRESS_CMD`. `install.sh` installs a starter hook
to `~/.local/bin/fftf-save-progress-hook` (source: [`contrib/save-progress-hook.sh`](contrib/save-progress-hook.sh))
that runs a Claude Code skill headlessly with the interview answers as context; point
`FFTF_SAVE_PROGRESS_CMD` at it. Two gotchas for systemd runs: wrap it in `timeout` (the
interview backstop doesn't cover the save step), and set `FFTF_CLAUDE_BIN` to the absolute
`claude` path (user services don't inherit your PATH). Test by hand before trusting it to
the timer.

**Diagnosis.** Every save-progress run is logged: full stdout+stderr to
`<state>/log/save-progress-YYYY-MM-DD.log`, a `wd:save_result` line (exit + log
path) in the day file, a `critical` notification on failure that evening, and windup
surfaces the previous day's result each morning — so a headless run you can't watch live is
reviewable after the fact.

The `FFTF_GOODNIGHT_CMD` seam (step 5) is where a presence-aware persistent clock-off nag
would compose in; unset, step 5 is a single notification.

## Requirements

- Linux with a `systemd` user instance and a desktop notification daemon (developed on
  Fedora + GNOME/Wayland).
- At least one capture backend: `claude` (Claude Code CLI) on your `PATH`, **or**
  [`ollama`](https://ollama.com) with a pulled model.
- `jq`, `curl`, `libnotify` (`notify-send`), `libcanberra-gtk3` (`canberra-gtk-play`),
  `glib2` (`gdbus`), and `flock`.
- Optional: `pactl` (PipeWire/PulseAudio) for the `audio-in` / `audio-out` presence signals.
  Without it the break guard still works on desktop idle; the audio signals are simply inert.
- Optional: `zenity` for the winddown end-of-day interview popups. Without it the break
  guard and capture are unaffected; only winddown can't prompt.

## Install

```sh
./install.sh
```

It installs the scripts to `~/.local/bin`, the units to `~/.config/systemd/user`, writes a
config to `~/.config/fftf/fftf.conf`, seeds a capture baseline (so your existing
sessions are **not** back-captured), and enables the timers (break-guard tick plus the
winddown/windup day-shape bookends).

Make sure `~/.local/bin` is on your `PATH` so `fftf-afk` works from any terminal.

## Usage

```sh
fftf-status                                 # where am I in the current stretch?
fftf-status --log                           # rolling detection log (diagnose the guard)
fftf-afk                                     # I'm stepping away — hush the nag now
fftf-pause 30m                               # I can't break yet — hush without crediting one
fftf-unpause                                 # end a pause early
fftf-capture --compare --latest             # try capture backends on a real session
systemctl --user start fftf.service # run one scan right now
journalctl --user -u fftf.service   # service logs
```

## Configuration

Edit `~/.config/fftf/fftf.conf`. Every knob (timings, enable/disable each
feature, capture model, notification stacking, output location) is documented in
[`config/fftf.conf.example`](config/fftf.conf.example).

## Uninstall

```sh
./uninstall.sh            # remove; keep config + state
./uninstall.sh --purge    # remove everything
```

## Caveats

- **Privacy:** capture files distill session content into `<project>/.temp/`. Keep `.temp/`
  in your `.gitignore` and treat those files as you would the session itself, or else set `FFTF_CAPTURE_DIR`.
- **Cost:** each capture is a small headless model call. It's rate-limited
  (`FFTF_CAPTURE_PER_TICK`) and deduplicated, but it is not free.
- **Desktop-bound:** notifications need the graphical session's D-Bus. Sessions run over
  SSH or in containers on another filesystem won't be seen.
- Capture quality depends on the model reading a truncated transcript tail; walking away
  mid-generation may yield a partial answer (it's marked as possibly incomplete).

## License

Apache License 2.0 — see [LICENSE](LICENSE) and [NOTICE](NOTICE). Set the copyright holder
before publishing.
