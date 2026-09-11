# focusguard

Two supports for long, hyperfocused sessions with [Claude Code](https://claude.com/claude-code),
built for AuDHD / ADHD working styles — driven off a single signal so neither one is
something you have to remember to do:

1. **Persistent break guard.** After ~60 minutes of *continuous* activity it starts an
   escalating, sticky desktop reminder to take a break. It is deliberately hard to
   ignore, and it can't be silenced without actually stepping away: a real ≥10-minute
   quiet gap credits the break and resets the clock on its own. Running `break-start`
   hushes the nag immediately, but only buys a short grace window — if you keep working
   through it instead of leaving, the nag comes back.
2. **Automatic answer capture.** When a session goes idle because you walked away or got
   pulled to another tab, focusguard distills the last question and its answer into a
   `QUESTION-*.md` file in that project — so you can find "what did I ask and what was the
   answer?" later without re-reading a transcript. No manual step; nothing to trigger.

## How it works

Claude Code writes a transcript (`~/.claude/projects/<slug>/<uuid>.jsonl`) for every
session, bumps the file's mtime on every interaction, and tags genuinely human-typed
prompts (`promptSource == "typed"`). focusguard reads both, using the right signal for
each job:

- **Break guard — your last human-typed prompt.** File mtime bumps on *any* activity,
  including a background agent working autonomously while you're away — which would make
  a real break look like engagement and nag you anyway. So the guard instead reads the
  timestamp of your last *typed* prompt. It's a cheap two-stage scan: mtime-sort today's
  transcripts, take the `FG_HUMAN_SCAN_N` most recent, and read the last typed-prompt
  time from just those.
- **Capture — a single session going stale.** When one session's own mtime has been idle
  for a few minutes, you left it mid-thread; that triggers capture for that session.

A `systemd` user timer runs one scan (`focusguard-tick`) every ~2 minutes. No daemon, no
polling loop, no root.

### Break guard details

- Continuous activity is measured from your typed prompts, ignoring gaps shorter than
  `FG_ACTIVITY_GAP` (10 min).
- At `FG_BREAK_INTERVAL` (60 min) it fires a `critical`-urgency notification (sticky on
  GNOME) plus a sound, and **escalates** each unacknowledged re-fire — harsher sound, more
  repeats, updated banner text.
- A genuine ≥`FG_ACTIVITY_GAP` quiet gap (you actually stepped away, or the computer
  suspended/slept) is the only thing that *credits* the break and resets the clock.
- `break-start` hushes the nag now and opens a `FG_BREAK_GRACE` (5 min) grace window so
  you can leave without the banner blaring — but it does **not** reset the clock. If no
  real quiet gap follows, the nag returns when grace expires. Clicking/dismissing the
  banner does nothing by design (a glance-and-swat is exactly the failure this guards
  against).

### Answer capture details

- On idle transition, focusguard asks an LLM (see **Capture backends** below) to distill the
  recent user/assistant turns and writes `QUESTION-<slug>-<date>.md` containing the question,
  a concise answer/conclusion, and light context. Trivial tails are skipped.
- Only the **last real exchange** is fed to the model — the most recent human-typed prompt
  and the assistant text that followed it. That is the highest-signal, smallest input
  (which also keeps a local model fast). Sessions with **no** human-typed prompt — command
  or automation runs (e.g. `/save-progress`) and focusguard's own background LLM calls —
  aren't a "what did I ask?" and are skipped without spending a model call.
- Output goes to each session's own `<project>/.temp/` by default (override with
  `FG_CAPTURE_DIR` to funnel everything into one folder).
- The raw transcript already persists everything permanently; the capture file is just the
  **findable, digested** version.

## Capture backends

The distillation is the only part that uses a model, and it is pluggable via
`FG_LLM_BACKEND`:

- **`claude`** (default) — the hosted Claude Code CLI. Fast, best quality; each capture is a
  small API call, so it has a (small) cost and needs network.
- **`ollama`** — a local model over Ollama. Fully offline, zero cost, and **nothing leaves
  your machine** — which matters, since capture files distill your session content. Quality is
  lower than a hosted model; on a CPU-only box use a small model (`llama3.2:3b`, `gemma2:2b`).
  Because capture runs *after* you walk away, its latency is not in your way.

Switch by setting `FG_LLM_BACKEND` in the config, and pick the model with `FG_CLAUDE_MODEL` /
`FG_OLLAMA_MODEL` (or `FG_LLM_MODEL` to override whichever is active). The backend is a shared
gateway (`lib/fg-llm.sh`) that future focusguard features can reuse.

**Compare quality directly** on a real session before you commit to one:

```sh
focusguard-capture --compare --latest        # run BOTH backends, print side by side + timings
focusguard-capture --dry-run --backend ollama --model llama3.2:3b --latest
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

# 4. point focusguard at it (see next code block)
```

Then set these in `~/.config/focusguard/focusguard.conf`:

```sh
FG_LLM_BACKEND="ollama"     # switch capture from hosted claude to the local model
FG_CAPTURE_TIMEOUT=180      # per-capture budget. A 3B model on CPU distills a typical
                            # session in 20-55s; a rare max-length answer can approach
                            # ~140s. 180 leaves headroom. (On a GPU host, seconds.)
FG_CAPTURE_PER_TICK=1       # only one slow local capture per tick, so two can't blow
                            # the service's 300s TimeoutStartSec
```

`FG_LLM_BACKEND` and `FG_CAPTURE_TIMEOUT` are the two that matter most for local use:
the first does the switch, the second keeps slow-but-valid captures from being killed
mid-generation. To change models, set `FG_OLLAMA_MODEL` (e.g. `llama3.1:8b`).

## Requirements

- Linux with a `systemd` user instance and a desktop notification daemon (developed on
  Fedora + GNOME/Wayland).
- At least one capture backend: `claude` (Claude Code CLI) on your `PATH`, **or**
  [`ollama`](https://ollama.com) with a pulled model.
- `jq`, `curl`, `libnotify` (`notify-send`), `libcanberra-gtk3` (`canberra-gtk-play`),
  `glib2` (`gdbus`), and `flock`.

## Install

```sh
./install.sh
```

It installs the scripts to `~/.local/bin`, the units to `~/.config/systemd/user`, writes a
config to `~/.config/focusguard/focusguard.conf`, seeds a capture baseline (so your existing
sessions are **not** back-captured), and enables the timer.

Make sure `~/.local/bin` is on your `PATH` so `break-start` works from any terminal.

## Usage

```sh
focusguard-status                         # where am I in the current stretch?
break-start                               # I'm stepping away — hush the nag now
focusguard-capture --compare --latest     # try capture backends on a real session
systemctl --user start focusguard.service # run one scan right now
journalctl --user -u focusguard.service   # logs
```

## Configuration

Edit `~/.config/focusguard/focusguard.conf`. Every knob (timings, enable/disable each
feature, capture model, notification stacking, output location) is documented in
[`config/focusguard.conf.example`](config/focusguard.conf.example).

## Uninstall

```sh
./uninstall.sh            # remove; keep config + state
./uninstall.sh --purge    # remove everything
```

## Caveats

- **Privacy:** capture files distill session content into `<project>/.temp/`. Keep `.temp/`
  in your `.gitignore` and treat those files as you would the session itself, or else set `FG_CAPTURE_DIR`.
- **Cost:** each capture is a small headless model call. It's rate-limited
  (`FG_CAPTURE_PER_TICK`) and deduplicated, but it is not free.
- **Desktop-bound:** notifications need the graphical session's D-Bus. Sessions run over
  SSH or in containers on another filesystem won't be seen.
- Capture quality depends on the model reading a truncated transcript tail; walking away
  mid-generation may yield a partial answer (it's marked as possibly incomplete).

## License

Apache License 2.0 — see [LICENSE](LICENSE) and [NOTICE](NOTICE). Set the copyright holder
before publishing.
