# WS7 — Session, lock, idle, power, battery

**Branch:** `feat/ws7-session-lock` · **Worktree:** `../ostrich-ws7`
**Wave:** 2 · **Depends on:** WS1 merged · **Blocks:** WS5 control-center footer
**Owns:** `shell/modules/{session,lock}/`, `shell/services/{Power,Idle,Battery}.qml`

---

## Mission

Own everything between "the user presses the power button" and "the session is
locked or gone": the power menu, the lock screen with PAM, idle/DPMS handling,
power profiles, and the real battery service. Safety first: a broken lock screen
must never trap the user, and a destructive action must never fire by accident.

Look up `WlSessionLock`, `WlSessionLockSurface`, `PamContext`, `IdleMonitor`,
`IdleInhibitor`, `PowerProfiles`, `UPower`, `UPowerDevice`, `PolkitAgent` before
coding.

---

## 1. `services/Battery.qml` (real)

- `UPower.displayDevice` (aggregate) with fallback to the first battery device.
- Map to the contract: `available`, `charging`, `plugged`, `percent` (0..100),
  `minutesRemaining`, `state` (`charging|discharging|fully-charged|pending|unknown`),
  `health` (`good|fair|poor|unknown`).
- Low/critical thresholds from `Config.value("services.battery.low"|"critical")`;
  emit `low`/`critical` **once per crossing** (edge-triggered, reset on charge
  above threshold + 5%). WS3/WS5 render the OSD/toast.
- `timeToEmpty`/`timeToFull` in minutes from UPower; clamp negatives to 0.
- No polling: UPower properties are reactive. A single 60 s timer is allowed only
  to recompute `minutesRemaining` smoothing; document why.

---

## 2. `services/Power.qml` (real)

- `profiles` from `PowerProfiles`: `[{ name: "power-saver"|"balanced"|"performance", label, available }]`;
  `profile` current; `setProfile(name)` writes `PowerProfiles.profile`,
  guarded by `hasPerformanceProfile`.
- `lock()` → `Idle.lock()` (source of truth), which the lock module observes.
- `logout()` → `Hyprland.dispatch("exit")` when Hyprland is available, else
  `loginctl terminate-user $USER` (argv).
- `suspend()`/`hibernate()` → `systemctl suspend|hibernate` (argv, 10 s timeout).
- `reboot()`/`shutdown()` → `systemctl reboot|poweroff`; `firmware()` →
  `systemctl reboot --firmware-setup`.
- Every command: `Process` argv list, timeout, capture stderr, emit
  `failed(action, message)` (extra signal) so the UI can toast. Never `sh -c`.
- Privileged commands rely on polkit/logind; if they fail because no agent is
  running, surface a clear message (see §5).
- Expose `available` per action (`canSuspend`, `canHibernate`, …) using
  `systemctl can-*`? Avoid extra processes: assume true and report failure.
- IPC is owned by the session module (`target: "power"`), not the service.

---

## 3. `services/Idle.qml` (real)

- `locked` is the **single source of truth** for the lock state. The lock module
  binds `WlSessionLock.locked: Idle.locked`.
- `inhibited`, `idleMs` (last idle duration, from the monitor), `inhibit(reason)`,
  `uninhibit()`.
- Inhibit with a Wayland `IdleInhibitor` (preferred) or `systemd-inhibit` argv
  only if unavailable; `reason` is user-supplied text, never a shell argument.
- `dpms(on)` → `Hyprland.dispatch("dpms " + (on ? "on" : "off"))` when Hyprland
  is available; otherwise no-op with a warning (documented limitation).
- Timers from config (`services.idle.*`, add via contract PR):
  `lockAfter` (s), `dpmsAfter` (s), `suspendAfter` (s, 0 = off).
  Use `IdleMonitor` instances (one per timeout) rather than a polling loop;
  `respectInhibitors: true`.
- On lock timeout: `lock()`. On suspend timeout: `lock()` then `Power.suspend()`
  (config `idle.lockBeforeSuspend`, default true).

---

## 4. Session menu (`modules/session/`)

```
Session.qml        # module root: overlay + IPC, open()/close()
SessionCard.qml
SessionAction.qml
```

- Full-screen scrim + centred card on the focused screen,
  `WlrLayer.Overlay`, `keyboardFocus: Exclusive` while open, click-outside and
  Escape close.
- Actions: Lock, Logout, Suspend, Hibernate, Reboot, Shutdown, Firmware Setup.
  Hide unavailable actions (no hibernate swap, no firmware on unsupported
  systems — detect `systemctl --version` once or just attempt and report).
- Confirmation: destructive actions need a second activation (button changes to
  "Confirm reboot?" for 3 s) or hold-to-confirm. Lock/Suspend fire immediately.
- Keyboard: arrows/Tab, Enter, Escape; number shortcuts 1..7.
- Each action disables itself while running and shows a spinner; failure shows
  the stderr message in a toast and re-enables.
- IPC `power` (contract): `lock()`, `suspend()`, `reboot()`, `shutdown()`,
  `logout()`, `profile(name)`. Register here, delegate to `Power`.
- The bar's power button opens this module (`Session.open()`).

---

## 5. Polkit prompt (inside `modules/lock/`)

Optional but preferred for v1 (PRD POLKIT-01):

- One `PolkitAgent` instance in `modules/lock/PolkitPrompt.qml` (instantiated by
  `Lock.qml`, hidden when inactive) so `shell.qml` stays untouched.
- When `isActive`, show a `PopupWindow`/small `PanelWindow` with the request
  message, a password field, and cancel. Feed responses through the `AuthFlow`
  API (look it up; do not guess method names — if the API is unclear, defer and
  document, keep the rest of the workstream shippable).
- Never show polkit prompts while locked? Allow it only behind the lock surface
  (the lock screen has priority; the agent prompt must not appear above it unless
  the request originated from the lock screen).
- Never log passwords; clear the field on close.

---

## 6. Lock screen (`modules/lock/`)

```
Lock.qml              # WlSessionLock + surfaces, lock()/unlock()/IPC
LockSurface.qml       # per-screen content
LockClock.qml
LockPassword.qml
LockMedia.qml         # optional, off by default
PolkitPrompt.qml
```

- `WlSessionLock { locked: Idle.locked }` with one `WlSessionLockSurface` per
  screen via `Variants`. Never create two locks (compositor allows one).
- `Lock.qml` API: `lock()` (sets `Idle.locked = true`), `unlock()` (only after
  successful PAM), `IpcHandler { target: "lock" }` with `lock()`, `unlock()`.
- Content: wallpaper image (dimmed + `MultiEffect` blur if available; fall back to
  dim), large clock/date, user avatar (`~/.face` if present), password field,
  failure message, caps-lock hint, battery/media optional.
- PAM: `PamContext { config: "login" }`; if the config is unusable (error),
  document the fallback to `system-auth` (try once at startup, log which was
  used). `start()` on Enter, `respond(password)`, on `success` → `unlock()`.
- Failure handling: shake/flash message, 1 s → 2 s → 4 s backoff (cap 8 s),
  clear the field, keep the surface interactive. Never lock out permanently;
  never reveal whether the username exists.
- PAM unavailable/timeout (5 s): show "Authentication unavailable" + retry;
  do **not** unlock.
- On unlock: `Idle.locked = false`, clear password, reset backoff, restore focus.
- Reload safety: if the shell reloads while locked, the lock must re-assert. Test
  `qs kill` while locked on a disposable session — document the expected
  behavior (compositor fallback if the process dies mid-lock).
- Before `Qt.quit()` anywhere in the shell, `Idle.locked` must be false; the lock
  module is exempt from the quit path (it never quits while locked).
- Keyboard: password field focused on surface activation; Escape clears the
  field (does not unlock); Tab cycles media controls if shown.
- Multi-monitor: every surface locks; password input works on the focused one;
  all surfaces show the same state.

---

## 7. Config keys

Add via contract PR:

```json
"services": {
  "idle": { "lockAfter": 300, "dpmsAfter": 600, "suspendAfter": 0, "lockBeforeSuspend": true },
  "battery": { "low": 15, "critical": 5 }
},
"lock": { "blur": true, "media": false, "clock24h": true }
```

Read through `Config.value`, keep defaults only in `config/default.json`.

---

## 8. Tests

- `tests/tst_battery.qml`: percent/state mapping, charging/plugged detection,
  edge-triggered low/critical (no repeat until reset), minutes clamping.
- `tests/tst_power.qml`: profile availability, action guards, argv construction
  (mock the process runner), failure signal.
- `tests/tst_idle.qml`: timeout → lock, inhibit blocks timers, dpms dispatch
  string, lockBeforeSuspend order.
- `tests/tst_lock.qml`: unlock only on PAM success, backoff sequence, password
  cleared, Escape does not unlock, reload re-asserts.
- Mock PAM as a `QtObject` with the same signals/functions; never call real PAM.
- Headless only; no real `systemctl` calls in tests.

---

## 9. Constraints

- Never run `systemctl`/`loginctl` through a shell; argv lists, 10 s timeout.
- Never log or persist passwords.
- Never make unlock depend on the network, media, or any optional service.
- Do not edit shared modules/services; `Power.qml`, `Idle.qml`, `Battery.qml`
  are yours, the rest are not.
- Do not add a second lock implementation behind a flag.

---

## 10. Acceptance checklist

- [ ] `qs ipc call power lock` locks every monitor; correct password unlocks in
      < 1 s; wrong password backs off and stays locked.
- [ ] Killing the shell while locked has a documented, recoverable outcome.
- [ ] Power menu actions work; reboot/shutdown require confirmation; failures
      show a readable message.
- [ ] Suspend locks first (when configured) and resumes to the lock screen.
- [ ] Idle timeout locks; inhibit prevents it; DPMS off/on works on Hyprland.
- [ ] Battery percent/state/time update live; low/critical fire once.
- [ ] Power profiles switch when the daemon is present, hidden otherwise.
- [ ] `make check` green; screenshots of lock (1 and 2 monitors) and session menu.

---

## 11. Handoff report

`docs/SUBAGENT_PLAN.md` §9 plus: PAM config used and fallback, exact system
commands per action, reload/lock safety notes, idle config keys, and anything
WS5 must call (`Power.*`, `Session.open`, `Battery.*`).
