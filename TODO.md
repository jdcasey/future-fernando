# focusguard — TODO

## Move break detection fully off session-watching

The break guard now uses **desktop presence** (GNOME/Mutter `IdleMonitor` idle time)
as its primary signal, with the legacy typed-prompt scan (`fg_last_human_activity`)
kept only as a fallback under `FG_PRESENCE=auto` / `typed`.

Session-transcript watching is a poor proxy for "is the human at the keyboard": it
misreads long autonomous agent runs and diff-reading as breaks, and background agent
activity as engagement. Presence is the correct signal. The intent is to eventually
drop session-watching from the break path **entirely**.

- [ ] Decide whether to retire the `typed` / auto-fallback path for break detection
      once presence has proven reliable on the daily-driver box (GNOME/Wayland).
- [ ] Add a portable presence backend so `idle` isn't GNOME-only before removing the
      fallback — e.g. `loginctl` IdleHint (unreliable on Wayland today), an X path
      (`xprintidle`), and wlroots (`ext-idle-notify` / swayidle) — selected like the
      LLM backends.
- [ ] Confirm `GetIdletime` behavior across screen-lock, suspend/resume, and multiple
      seats/sessions before trusting presence as the sole signal.
- [ ] Once the above hold, remove `fg_last_human_activity` from the break-guard path
      (keep the two-stage typed-prompt scan only where it's genuinely needed).

**Do NOT** remove session-watching from **answer capture** — Job A legitimately needs
per-session transcript mtimes and typed-prompt content to detect a walked-away session
and distill its last Q/A. Presence is about *the human*; capture is about *a session*.

## Validation still open

- [ ] Confirm `GetIdletime` answers from inside the `focusguard.service` systemd user
      unit (not just an interactive shell). Existing evidence: the service already
      calls `gdbus --session` for notifications and `install.sh` imports
      `DBUS_SESSION_BUS_ADDRESS` — but verify with a real tick.
- [ ] Watch for the motionless-reading edge: sitting >10 min with zero mouse/keyboard
      input while reading will false-credit a break. Add an agent-file-activity
      tiebreaker only if this actually bites (it reintroduces the overnight-agent
      false positive, so avoid unless proven necessary).
