# ThinkPad TrackPoint drift breaks break-crediting

## The problem

Fern's break guard decides "you've stepped away" from GNOME's idle counter
(`org.gnome.Mutter.IdleMonitor.GetIdletime`) — seconds since the last input.
On many ThinkPads the built-in **TrackPoint** (the red nub) emits phantom pointer
events when idle ("drift"). Each phantom event resets the idle counter, so a real
absence often never reaches `FERN_ACTIVITY_GAP`. Result: no break is ever credited
and Fern nags you even after you've walked away.

The drift is **bursty**, not constant — a hands-off sample can show idle pinned
under 3 s while it should be climbing. Fern's rolling detection log
(`ff-status --log`) exposes it: look for `idle=` staying low across ticks where you
know you were away.

## The fix

If you **don't use** the TrackPoint (e.g. you use an external mouse), the clean fix
is to tell libinput to ignore it. It then emits no events, the idle counter climbs
correctly, and Fern needs no changes.

The rule matches only devices with `ID_INPUT_POINTINGSTICK=1` — that is the nub and
nothing else. Your external mouse, touchpad, and keyboards are untouched.

## Scripts

Run from this directory. `fix.sh` and `undo.sh` re-exec themselves with `sudo`
(they write under `/etc/udev/rules.d`). `test.sh` needs no privileges.

| Script     | What it does |
|------------|--------------|
| `fix.sh`   | Installs `/etc/udev/rules.d/99-disable-trackpoint.rules`, then reloads and re-triggers udev. Disables the TrackPoint. |
| `test.sh`  | Samples the idle counter for ~20 s. **Take your hands off input while it runs.** PASS = idle climbed (drift gone); FAIL = still being reset. |
| `undo.sh`  | Removes the rule and reloads udev, re-enabling the TrackPoint. |

Typical use:

```
./fix.sh
./test.sh      # hands off the keyboard/mouse
```

If `test.sh` FAILs immediately after `fix.sh`, the live device wasn't detached in
place — **reboot and re-run `test.sh`**. The rule is correct; some i8042 devices
only detach on a fresh boot.

## Caveats

- This disables the nub **everywhere**, including a dock/travel setup where you'd
  otherwise fall back to it. Run `undo.sh` if you need it back.
- If `test.sh` still FAILs after a reboot, the TrackPoint may not be your only
  drift source — the **touchpad** can also emit ghost input. That needs a
  different rule (matched by device name, since the touchpad is not a pointing
  stick); this cookbook entry does not cover it.
