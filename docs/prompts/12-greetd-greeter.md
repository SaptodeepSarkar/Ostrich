# WS12 — greetd greeter and shared login surface

**Branch:** `feat/ws12-greeter` · **Worktree:** `../ostrich-ws12`
**Wave:** 3 · **Depends on:** WS0, WS1 merged; WS7 merged (lock screen) ·
**Blocks:** WS11 packaging
**Owns:** `greeter/`, `shell/components/login/` (greeter extensions),
`packaging/greetd/`, `scripts/greeter/`

---

## Mission

Build the login experience Ostrich boots into: a **separate Quickshell config**
that greetd runs as the `greeter` user, inside a minimal compositor, before any
user session exists. It must authenticate through greetd, let the user choose a
Wayland session, and hand off to that session without leaving a black screen.

The greeter and the lock screen must look and behave like **one object waking
up**: same "Aurora" scene, same `Pebble` material, same `LoginSurface`. WS7 owns
the lock module; you own the shared login components and the greeter.

Read before coding, in this order:

1. `docs/CONTRACTS.md` — §1 layout, §3.1 greeter, §5.1 greeter config, §6
   `scheme.json` resolution, §10 UI kit.
2. `docs/DESIGN.md` — §7 "Greeter and lock (shared Aurora scene)", §2 materials,
   §6 motion, §9 shader budget.
3. `docs/prompts/07-session-lock.md` — what the lock already built and what it
   expects from `components/login/`.

Look up `Quickshell.Services.Greetd`, `GreetdState`, `PanelWindow`,
`WlrLayershell`, `WlrKeyboardFocus`, `WlrLayer`, `ExclusionMode`, `Quickshell.screens`,
`DesktopEntries` / `DesktopEntry`, `Process`, `FileView` before coding. Do not
guess method names — the Greetd API is small and exact.

---

## 1. Runtime architecture (do not improvise this)

greetd cannot display QML by itself. It launches a command on a VT; that command
must start a Wayland compositor, and Quickshell runs inside it.

```
greetd (root, /dev/tty1)
  └─ cage -s -- qs -p /usr/share/ostrich/greeter      (user: greeter)
       ├─ Wayland surface(s), mirrored per output
       └─ Quickshell config: greeter/shell.qml
            └─ Quickshell.Services.Greetd → authenticate → launch session
```

- `cage` is the compositor: no session, no wallpaper daemon, no WM. `-s` allows
  VT switching, which is the escape hatch if the greeter breaks. Do not use a
  full sway/Hyprland for the greeter.
- The `greeter` user is supplied by the `greetd` package. Verify it exists
  (`getent passwd greeter`) instead of creating it. It needs access to the DRM
  device and input devices; check membership of `video`/`render`/`input` and
  **report** what is missing in the install output rather than silently editing
  groups.
- Quickshell must be the packaged system build, launched by absolute path if
  needed (`/usr/bin/qs`). Never run the greeter as root.

### 1.1 `packaging/greetd/config.toml`

Ship as a drop-in snippet plus an installer that:

1. backs up `/etc/greetd/config.toml` to `/etc/greetd/config.toml.bak.<timestamp>`
   (once; never overwrite an existing backup),
2. writes/updates the Ostrich block idempotently (marker comments),
3. validates with `greetd --check-config` if that flag exists in the installed
   version, otherwise with `cage -s -- true` and a TOML parse of our own file,
4. never restarts greetd without an explicit `--apply` flag.

Target content:

```toml
# >>> ostrich greeter >>>
[terminal]
vt = 1

[default_session]
command = "cage -s -- /usr/bin/qs -p /usr/share/ostrich/greeter"
user = "greeter"
# <<< ostrich greeter <<<
```

- Merge with the existing file; do not clobber an existing `[default_session]`
  without `--force`. Print the previous command so the user can roll back.
- `scripts/greeter/uninstall.sh` restores the backup and prints how to re-enable
  the previous greeter.
- Document the "locked out" recovery path in `docs/install.md`: `Ctrl+Alt+F2`,
  log in as root, restore the backup, `systemctl restart greetd`.

### 1.2 Install layout

| Source | Installed path |
| --- | --- |
| `greeter/` | `/usr/share/ostrich/greeter/` |
| `shell/components/` | `/usr/share/ostrich/shell/components/` (greeter imports peers) |
| `greeter/theme.json` | `/usr/share/ostrich/greeter/theme.json` |
| `greeter/config.json` | `/usr/share/ostrich/greeter/config.json` (root-owned, read-only) |
| `packaging/greetd/config.toml` | merged into `/etc/greetd/config.toml` |

Runtime QML imports stay relative (`../shell/components`), so the installed tree
must preserve `ostrich/shell/components` next to `ostrich/greeter`. A tiny
`scripts/greeter/relocate.sh` (or install-time copy) may duplicate the shared
components; document whichever approach you choose.

`greeter/` must not depend on `shell/shell.qml`, `shell/modules/`, `Config.qml`,
`State.qml`, or any user-session service. Allowed imports: `Theme`, `Paths`,
`Time`, the Pebble components, `components/login/*`, and `Greetd`.

---

## 2. Palette resolution

The greeter runs before any user session, so it cannot read `$STATE/scheme.json`
of the logged-in user. Resolution order (already in `CONTRACTS.md` §6):

1. `$OSTRICH_SCHEME_FILE` if set and readable,
2. `/usr/share/ostrich/greeter/theme.json`,
3. built-in fallback palette in `Theme.qml`/`greeter/theme.json`.

- `greeter/theme.json` is a full `scheme.json` document (contract §6). Ship a
  tasteful dark default (near-black surface, one accent) and leave a comment in
  the installer explaining how the user can regenerate it from their wallpaper.
- The greeter never writes outside its own `$HOME` and XDG dirs. It must not
  read `~/.local/state/ostrich` of another user.
- Provide `ostrich greeter theme --from <image>`? No — out of scope. Just make
  the file replaceable by packaging.

---

## 3. greetd state machine

`Greetd` is a singleton with `state`, `user`, `available`, and the signals
`authMessage(message, error, responseRequired, echoResponse)`,
`authFailure(message)`, `readyToLaunch()`, `launched()`, `error(message)`.

Implement a `GreeterState.qml` (in `greeter/`) that maps this to UI state:

| `Greetd.state` | UI |
| --- | --- |
| `Inactive` | user/session picker, password field disabled until a user is chosen |
| `Authenticating` | password field busy, submit disabled, input cleared after respond |
| `ReadyToLaunch` | "Signing in…" then `launch()`; block further input |
| `Launching` | hold the scene, disable everything, show a progress pebble |
| `Launched` | Quickshell exits automatically; do not call `Qt.quit()` yourself |

Flow:

1. User picked → `Greetd.createSession(user)`. If `showUsers` is false, take the
   typed username, validate it is a non-empty local name, then create.
2. `authMessage` with `responseRequired: true` → show the prompt text and a
   password field (`echoResponse` decides masked vs clear). Submit →
   `Greetd.respond(text)`. Never store the text; clear it immediately.
3. `authMessage` with `responseRequired: false` → show as a transient hint
   (e.g. "Password:"), no input.
4. `authFailure(message)` → shake, show the message, return to `Inactive`,
   re-focus the password field, clear it, apply the backoff from §7.
5. `readyToLaunch()` → choose the selected session, `Greetd.launch(argv, env)`.
6. `error(message)` → show a non-destructive banner; if greetd is unavailable,
   show "Authentication unavailable" and keep retry/reboot controls visible.
7. Cancel button / Escape while authenticating → `Greetd.cancelSession()`,
   return to `Inactive`, clear the field.

```qml
// shape only; implementation is yours
Connections {
    target: Greetd
    function onAuthMessage(message, error, responseRequired, echoResponse) { … }
    function onAuthFailure(message) { … }
    function onReadyToLaunch() { launchSelectedSession() }
}
```

Do not call `createSession` twice for the same user; guard with a state check.
Do not call `respond` when `responseRequired` is false.

---

## 4. Session discovery

Parse desktop entries without starting processes during normal use:

- Directories, in order: `/usr/share/wayland-sessions`, `/usr/local/share/wayland-sessions`,
  `~/.local/share/wayland-sessions` (of the greeter user; usually empty).
- Use `DesktopEntry`/`DesktopEntries` if it exposes `Exec`, `Name`, `Comment`,
  `DesktopNames`, `Hidden`, `NoDisplay`. Otherwise read files with `FileView` and
  parse `[Desktop Entry]` key/value lines; do not shell out to `grep`.
- Ignore `Hidden=true` and `NoDisplay=true` unless it is the configured default.
- Deduplicate by desktop file id (filename), not by `Name`.
- Parse `Exec` yourself: honour single/double quotes and backslash escapes, drop
  field codes (`%f %F %u %U %i %c %k`); result is an **argv list**. Never hand a
  string to a shell. Strip a leading `env VAR=value` into the env list instead of
  keeping it in the argv.
- Default selection: `greeter/config.json` `defaultSession` matched against the
  desktop id or `Name` (case-insensitive); otherwise first entry; otherwise a
  disabled state with an explanation.
- Empty session list: show the error state, keep reboot/poweroff available, and
  log a clear message (journal) — never crash.

Session environment passed to `launch()`:

```
XDG_SESSION_TYPE=wayland
XDG_SESSION_DESKTOP=<desktop id>
XDG_CURRENT_DESKTOP=<DesktopNames, colon-separated>   // omit if absent
```

greetd fills the identity variables (`HOME`, `USER`, `SHELL`, `PATH`,
`XDG_RUNTIME_DIR`) for the target user. **Verify this against the installed
greetd** and, if `PATH` is missing in the launched session, add a minimal
`PATH=/usr/local/bin:/usr/bin` and document it. Never forward the greeter's
`HOME`, tokens, or full environment.

Remember: greetd may start a shell script; many `.desktop` `Exec` lines start
with `Hyprland` or `start-hyprland`. Do not append extra flags.

---

## 5. UI — the Aurora scene

Composition and rules are in `docs/DESIGN.md` §7. Build it from the shared kit;
do not write one-off gradients or shaders.

```
greeter/
├── shell.qml               # ShellRoot + one greeter window per screen
├── Greeter.qml             # scene composition
├── GreeterState.qml        # greetd state machine + session model
├── GreeterClock.qml        # giant pebble clock (DotMatrixText option)
├── PowerBar.qml            # power pebbles, caps/num indicators, hostname
├── SessionModel.qml        # desktop-entry parsing (pure JS/QML, testable)
└── config.json / theme.json
```

`shell/components/login/` (you own the greeter extensions):

```
LoginSurface.qml    # mode: lock|greeter, user, message, error, busy, onSubmit(text)
UserBubble.qml      # user, avatar, selected, onClicked
SessionDial.qml     # sessions, currentIndex, onSelected(index)
```

- If WS7 shipped `LoginSurface` inside `modules/lock/`, extract it into
  `components/login/LoginSurface.qml` with the contract API and refactor the lock
  to import it. That refactor is a **contract-compatible move**: keep the lock's
  public behavior identical, run its tests, and mention it in the handoff.
- Reuse `Pebble`, `Bubble`, `PebbleButton`, `GlowRing`, `DotMatrixText`,
  `Specular`. One accent per screen: the clock pebble or the selected session
  tick, never both.
- `Specular` quality comes from `greeter/config.json` `pebbleQuality` and must
  degrade to `low` when the compositor has no GPU (software rendering under
  `cage` in a VM). Test with `LIBGL_ALWAYS_SOFTWARE=1`.
- Staged reveal on start: backdrop → clock → session dial → user bubble →
  password pill, 400 ms total, offset 60 ms per group. `reducedMotion` (from
  `greeter/config.json` or the system `gtk-enable-animations`/env) skips it.

Window setup:

```qml
PanelWindow {
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    focusable: true
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "ostrich-greeter"
    color: "transparent"
}
```

One window per `Quickshell.screens` entry via `Variants`. `cage` mirrors
outputs, so all windows show the same state; the *primary* (first) window owns
keyboard focus. Clicking any window focuses it and forwards input to the shared
state.

Keyboard:

- Password field focused as soon as a user is selected; Enter submits, Escape
  clears then cancels the session.
- Tab/Shift+Tab cycle user bubble → password → session dial → power.
- `Super`/`Ctrl` are not required; the greeter must be fully operable by
  keyboard and by pointer.
- Caps Lock and Num Lock indicators update live and never steal focus.

---

## 6. Power actions and polkit

- Show reboot / poweroff / suspend only when `powerActions` is true **and** the
  action is permitted. Probe once at startup with `systemctl can-poweroff`-style
  checks if available, or attempt and report failure; never show a button that
  always fails.
- The greeter user normally cannot power off without a polkit rule. Ship an
  **optional** rule in `packaging/greetd/49-ostrich-greeter.rules` that allows
  `org.freedesktop.login1.power-off`, `reboot`, and `suspend` for
  `user == "greeter"` and `active`/`session` as appropriate. The installer asks
  before installing it (or requires `--allow-power`); uninstalling removes it.
- Commands always go through `Process` with an argv list and a timeout:
  `systemctl poweroff`, `systemctl reboot`, `systemctl suspend`. Confirm
  destructive actions with a 3 s second-activation state, like the session menu
  in WS7.
- Never run a command that needs a password prompt: there is no polkit agent in
  the greeter. If a call fails, show the stderr line in the hint area and keep
  the greeter usable.
- After a successful power action, greetd/cage will exit with the VT. Leave the
  screen in a readable "Powering off…" state rather than a blank window.

---

## 7. Failure, safety, and recovery

- **Wrong password:** shake 3×4 px, turn the rim `error` for 300 ms, show
  `authFailure.message`, clear the field, backoff 1 s → 2 s → 4 s → 8 s (cap),
  reset on success or after 30 s of no attempts.
- **greetd unavailable** (`Greetd.available == false`): show a static banner
  "greetd is not running — start it with `systemctl start greetd`", keep power
  controls, do not spin forever.
- **Session launch fails:** greetd sends `authFailure`/`error`; return to the
  scene with the message. Never leave a modal that cannot be dismissed.
- **Greeter crashes / qs dies:** cage exits, greetd restarts the greeter
  (greetd's supervisor). Confirm that the packaged TOML relies on greetd's
  restart rather than a shell loop. Document the expected behavior.
- **VT switch:** `cage -s` allows `Ctrl+Alt+F<n>`; the greeter must not grab
  the keyboard exclusively in a way that blocks VT switching (layer-shell
  `keyboardFocus` is fine; do not use a raw input grab).
- **Multi-monitor / hotplug:** listen to `Quickshell.screens`; add/remove
  windows reactively. No stale password fields on disconnected screens.
- **Time:** use `Time`/`SystemClock` so the clock stays live; do not implement a
  second timer.
- **Logging:** `console.warn` only for state transitions and errors; never log
  usernames with passwords, never log `respond()` payloads, never log the full
  environment.
- **Security:** no network access, no shell, no reading other users' files, no
  writing outside the greeter's XDG dirs. The greeter must not import
  `Hyprland`, `Pipewire`, `Mpris`, `Notifications`, or `SystemTray`.

---

## 8. Lock-screen unification

Coordinate with WS7 through the contract, not by editing `modules/lock/`:

- `LoginSurface` supports `mode: "lock" | "greeter"`. Lock mode hides the session
  dial and user picker and shows battery/media; greeter mode shows the dial.
- Both modes share the same password pill, error line, shake, backoff, and
  reduced-motion behavior. If the lock's backoff differs, document the
  difference rather than duplicating code.
- The lock keeps `PamContext`; the greeter uses `Greetd`. The surface only emits
  `onSubmit(text)` and renders `message`/`error`/`busy`; it never authenticates.
- Add a screenshot comparison to the PR: greeter vs lock, same monitor, same
  palette, to prove they read as one family.

---

## 9. Tests

Pure-QML tests under `tests/` (headless, `QT_QPA_PLATFORM=offscreen`):

- `tests/tst_session_model.qml`
  - parse `Name`/`Exec`/`DesktopNames`, quoted paths, field-code stripping;
  - `Hidden`/`NoDisplay` filtering, dedupe, default selection fallback;
  - empty directory → empty model, no exception;
  - `env VAR=value` prefix moved to env (if you support it).
- `tests/tst_greeter_state.qml`
  - Inactive → Authenticating on user pick; double-pick guarded;
  - `authMessage` with/without `responseRequired`; masked vs echo;
  - `authFailure` clears password, increments backoff, resets on success;
  - `readyToLaunch` builds the correct argv/env for a fake session;
  - `error` keeps the UI recoverable; `cancelSession` resets.
- `tests/tst_login_surface.qml`
  - lock vs greeter mode visibility; `onSubmit` emits once per activation;
  - error/message/busy states; reduced motion sets durations to 0.
- Mock `Greetd` as a `QtObject` with the real signal signatures. Never talk to
  the real socket in tests, never call `cage`.
- Add a headless smoke entry to the WS11 matrix: `qs -p greeter` starts and
  renders the scene with a stub `Greetd` (no greetd socket), then exits on
  timeout. Gate it behind `make greeter-smoke` so CI without cage can skip it.

---

## 10. Config keys

`greeter/config.json` (contract §5.1), read-only at runtime:

```json
{
  "version": 1,
  "clock24h": true,
  "showUsers": true,
  "defaultSession": "hyprland",
  "powerActions": true,
  "background": "aurora",
  "pebbleQuality": "high"
}
```

- Unknown keys are ignored; unknown `background` falls back to `aurora`.
- `showUsers: false` shows a username field instead of user bubbles.
- Do not add shell config keys here and do not read `config/default.json`.

---

## 11. Constraints

- Do not edit `shell/shell.qml`, `shell/modules/**`, `shell/services/{Config,
  State,Paths,Theme}.qml`, or `config/default.json`. `RuntimePaths`/`Paths`
  may need a `greeterConfig` helper — request it via a contract PR.
- Do not copy code, assets, fonts, icons, or strings from `glyph-rice` or
  caelestia. The radial dial and dot-matrix motifs are reimplemented from the
  design brief, with Ostrich's own geometry and tokens.
- Do not ship a second greeter theme format; reuse `scheme.json`.
- Do not depend on `swww`, Hyprland, a polkit agent, or a network at login time.
- Do not leave the greeter in a state where the only exit is a hard reboot:
  every error path offers retry, VT-switch instructions, and power actions when
  available.

---

## 12. Acceptance checklist

- [ ] `cage -s -- qs -p greeter` starts the login scene on a clean VT with the
      packaged greeter user and no Hyprland running.
- [ ] Correct password authenticates in < 2 s and starts the selected session;
      the screen never flashes white/transparent during the handoff.
- [ ] Wrong password shakes, shows greetd's message, clears the field, backs off,
      and never locks the user out.
- [ ] Session list comes from `*.desktop`, honours `defaultSession`, and survives
      an empty directory with a readable message.
- [ ] Only the configured palette is used; greeter does not read another user's
      state; `theme.json` fallback works with no `$STATE`.
- [ ] Power buttons appear only when permitted; polkit rule is opt-in and
      uninstalled cleanly.
- [ ] Lock and greeter visibly share `LoginSurface`, `Pebble`, and motion; lock
      tests still pass after the extraction.
- [ ] Soft-render path (`LIBGL_ALWAYS_SOFTWARE=1`, `pebbleQuality: "low"`)
      renders the full scene without shaders.
- [ ] `make check` green; `make greeter-smoke` green or explicitly skipped with a
      reason; screenshots of the greeter on 1 and 2 monitors.
- [ ] `docs/install.md` documents install, rollback, VT escape, and the polkit
      rule.

---

## 13. Handoff report

Use `docs/SUBAGENT_PLAN.md` §9, plus:

- exact greetd TOML written and how to restore the backup;
- the `Exec` parsing rules you implemented (and what you do with `env` prefixes);
- the environment list passed to `launch()` and why;
- which parts of `components/login/` you extracted from WS7 and the lock tests
  you re-ran;
- polkit rule contents and installer flag;
- known limitations (GPU-less output, session edge cases, greetd version).
