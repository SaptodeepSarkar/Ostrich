# WS0 — Core kernel

**Branch:** `feat/ws0-core-kernel` · **Worktree:** `../ostrich-ws0`
**Wave:** 0 (blocking) · **Depends on:** nothing · **Blocks:** everything
**Prompt owner:** core architect. This prompt is the source of truth for the
foundation layer.

---

## Mission

Make `qs -p shell` boot into a working, empty shell: configuration loads, theme
tokens resolve, state persists, wallpapers and time are observable, every future
module has a placeholder slot, and the public IPC surface exists. No feature UI
in this workstream — only the kernel that the other 12 workstreams build on.

Read `AGENTS.md`, `PRD.md`, `docs/CONTRACTS.md` (all of it), `docs/DESIGN.md`
for the tokens your placeholders must expose, then implement.

---

## 1. Deliverables

### 1.1 Entry point

`shell/shell.qml` — a `ShellRoot` that:

- Instantiates, in the contract order: `Background`, `Bar`, `Notifications`,
  `Osd`, `Launcher`, `Dock`, `ControlCenter`, `Session`, `Overview`, `Settings`,
  `Utilities`, `Lock`.
- Uses `LazyLoader` for heavy/rarely-used modules (`Settings`, `Lock`,
  `Overview`, `Utilities`) with `active` bound to a small `Modules` state, so the
  cold start stays under budget. Keep the loader wrappers in `shell.qml` only.
- Adds `//@ pragma DefaultEnv QS_NO_RELOAD_POPUP=1`, `QS_DROP_EXPENSIVE_FONTS=1`,
  `QSG_RENDER_LOOP=threaded` at the top (values may be tuned later).
- Contains **no** layout, colours, or widget logic.
- Registers a `Scope` with startup diagnostics: `Quickshell.shellDir`,
  Quickshell/Qt versions, config path, scheme path — logged once at INFO.

Also create `shell/manifest.conf` with `ostrich = .` so `qs -c ostrich` works
when the directory is on the config path, and document `qs -p shell` in
`docs/install.md` (new file, minimal).

### 1.2 Placeholder modules (must exist, must render nothing)

Create one file per module, each importing `Quickshell` + `QtQuick`, rooted at an
`Item` and exposing the API from `CONTRACTS.md` §3 as no-ops:

```
modules/background/Background.qml
modules/bar/Bar.qml
modules/notifications/Notifications.qml
modules/osd/Osd.qml
modules/launcher/Launcher.qml
modules/dock/Dock.qml
modules/controlcenter/ControlCenter.qml
modules/session/Session.qml
modules/overview/Overview.qml
modules/settings/Settings.qml
modules/utilities/Utilities.qml
modules/lock/Lock.qml
```

Each placeholder must:

- implement every required function from the table (empty body, `console.debug`
  is fine, no crash if called),
- register its `IpcHandler` target from `CONTRACTS.md` §7 (so IPC can be tested
  before the real module lands),
- return a `bool`/`void` exactly as documented.

The owning workstream later replaces the whole file, keeping the API.

### 1.3 Services

Implement these for real (the rest are WS1 stubs):

#### `shell/services/Paths.qml`

- All properties from `CONTRACTS.md` §4.
- Resolve XDG dirs with env overrides:
  `OSTRICH_CONFIG_DIR`, `OSTRICH_STATE_DIR`, `OSTRICH_DATA_DIR`,
  `OSTRICH_CACHE_DIR`, `OSTRICH_WALLPAPERS_DIR`, `OSTRICH_RECORDINGS_DIR`.
- Defaults: `~/.config/ostrich`, `~/.local/state/ostrich`,
  `~/.local/share/ostrich`, `~/.cache/ostrich`,
  `~/Pictures/Wallpapers`, `~/Videos/Recordings`.
- `absolute()` expands `~`; `shortenHome()` replaces the home prefix.
- Never create directories at property-evaluation time; provide
  `ensureDir(path)` used by writers.

#### `shell/services/Config.qml`

- Loads defaults, merges user config, exposes the contract API
  (`data`, `ready`, `value(path, fallback)`, `set`, `reload`, `reset`,
  `forScreen`, `changed`).
- Defaults resolution order:
  1. `$OSTRICH_DEFAULTS_FILE`
  2. `Quickshell.shellDir + "/../config/default.json"`
  3. `/usr/share/ostrich/config/default.json`
  4. a small embedded fallback object (`version`, module flags, `theme.mode`).
- User config: `Paths.config + "/config.json"`. Missing file = defaults, no
  error. Malformed JSON = defaults + `Toast` warning + log line with the parse
  error, shell keeps running.
- Deep merge (objects recursive, arrays replaced). `value()` accepts dot paths.
- `set()` writes atomically via `FileView.setText()` (atomic by default), mode
  `0600` where possible, debounced 150 ms.
- Watch the file (`FileView.watchChanges`) and re-emit `changed(path)`; on
  external change reload without clobbering unsaved debounce.
- `set()` must reject unknown top-level sections (log + `Toast`), preserving
  unknown keys in memory.
- Emit `warnings` list (readonly property) with `unknown key` / `parse error`
  entries for the settings app and `ostrich doctor`.

#### `shell/services/State.qml`

- Persistent UI state at `Paths.state + "/state.json"`.
- `get(key, fallback)`, `set(key, value)`, `changed(key)`.
- Debounced atomic writes (500 ms), flush on shell shutdown if cheap
  (`Component.onDestruction`).
- Never stores secrets; documented as non-authoritative cache.

#### `shell/services/Theme.qml`

- Watches `Paths.state + "/scheme.json"` via `FileView` + `JsonAdapter`.
- Exposes every property/function from `CONTRACTS.md` §4 (`colours`, `name`,
  `flavour`, `variant`, `mode`, `isLight`, `source`, `schemes`, `reducedMotion`,
  `fontScale`, `c()`, `setMode`, `toggleMode`, `setScheme`, `reload`, `changed`).
- `schemes` is loaded from `ostrich scheme list --json` on startup (async,
  fallback `[{ name: "dynamic", flavours: ["default"] }]`); it never blocks boot.
- `reducedMotion` and `fontScale` come from `Config.value("appearance.…")`.
- Fills every missing token from a **complete embedded fallback palette**
  (dark and light), including `term0..term15`. Invalid values (no `#`, wrong
  length) fall back per token and log once.
- `setMode(mode)`:
  - `dark`/`light` → call `ostrich scheme set --mode <mode>` (the CLI owns
    persistence), then rely on the watcher; optimistically update mode after
    200 ms if the file did not change, and surface a `Toast` on failure.
  - `auto` → call `ostrich scheme auto --enable`, persist
    `theme.mode = "auto"` through `Config.set`.
- `toggleMode()` flips dark/light unless mode is `auto`, in which case it sets
  the opposite of the current resolved mode and disables auto (documented).
- Uses `Process` with argv lists only; no shell strings.
- Registers IpcHandler target `theme`.

#### `shell/services/Wallpaper.qml`

- Watches `Paths.state + "/wallpaper/path.txt"` (plain text path, trailing
  newline tolerated).
- `current`, `list` (from `ostrich wallpaper list --json`, refreshed on request
  and on directory change), `set(path)`, `random()`, `preview(path)`,
  `cancelPreview()`, `changed`.
- `list` entries: `{ path, name, category }`; degrade to `[]` if the CLI is
  missing.
- Commands: `ostrich wallpaper set|random|get|list` — argv lists, 10 s timeout,
  capture stderr into the log on failure.
- Registers IpcHandler target `wallpaper` with `get`, `set`, `random`, `list`.

#### `shell/services/Time.qml`

- Built on `SystemClock` from `Quickshell` (`precision: SystemClock.Minutes`;
  add a `Seconds` clock only if a consumer requests it).
- Properties from the contract; `format(fmt)` uses `Qt.formatDateTime`.
- Locale-aware (`Qt.locale()`), no timers.

#### `shell/services/Toast.qml`

- Minimal in-shell transient message queue used by the kernel for errors.
- `show(message, kind)` with `kind` in `info|warn|error|success`.
- Data property `items` (newest first, auto-expire after 4 s) consumed later by
  WS4/WS9 UI. No visual components here — WS4 renders them.
- Must be safe to call before any window exists.

#### `shell/services/qmldir`

Create it explicitly so `qmllint` can see singleton members:

```
singleton Paths 1.0 Paths.qml
singleton Config 1.0 Config.qml
...
```

List every singleton from `CONTRACTS.md` §4, including the WS1 stubs. WS1 keeps
this file in sync when it adds files. No `module` line (directory listing only).

### 1.4 Default config

`config/default.json` exactly as `CONTRACTS.md` §5, pretty-printed, 2-space
indent, trailing newline. Add a `_comment`-free schema (comments belong in
`docs/configuration.md`).

### 1.5 Tests

- `tests/tst_config.qml`: defaults merge, dot-path get/set, array replacement,
  unknown-key warning, malformed JSON fallback.
- `tests/tst_theme.qml`: token fallback, invalid colour handling,
  `c("missing")` returns a valid colour, mode toggling math.
- `tests/tst_paths.qml`: env overrides, `~` expansion, `shortenHome`.
- Mock the filesystem: generate temp dirs under `QTemporaryDir`; never touch the
  real `$HOME`.
- Tests must run headless (`QT_QPA_PLATFORM=offscreen`), no Quickshell daemon
  required beyond the QML types.

If the existing `scripts/ci/test.sh` cannot discover these yet, extend it
minimally (it is a CI script — keep the change surgical and explain it in the
PR).

### 1.6 Docs

- `docs/install.md`: dependencies, `qs -p shell`, `ostrich` install, first-run
  bootstrap, environment variables from §1.3.
- `docs/architecture.md`: process model, service ownership, data flow
  (CLI → `scheme.json`/`path.txt` → singletons → UI), reload behavior.
- `docs/configuration.md`: schema table generated/derived from
  `config/default.json`, precedence, per-monitor merge.
- Update `docs/README.md` index (status: available).
- `CHANGELOG.md` Unreleased entries.

---

## 2. Constraints

- No C++/CMake. No `qs.*` imports. Relative imports only.
- No `Qt.labs.*` unless unavoidable and documented.
- No polling: use `SystemClock`, `FileView.watchChanges`, `Process`, signals.
- Logging via `console.info/warn/error` with a `[ostrich:<area>]` prefix.
- Fail soft: a missing CLI, missing file, or broken JSON must never crash the
  shell.
- Keep `shell.qml` under ~120 lines.

---

## 3. Acceptance checklist

- [ ] `qs -p shell` starts on Hyprland with no QML errors and an empty desktop.
- [ ] `qs ipc show` lists every target from `CONTRACTS.md` §7.
- [ ] `qs ipc call theme setMode light` changes the shell's `Theme.mode` (or
      reports a clear error if the CLI is absent).
- [ ] Editing `~/.config/ostrich/config.json` updates `Config.data` live.
- [ ] Writing a valid `scheme.json` updates `Theme.colours` live.
- [ ] Writing `$STATE/wallpaper/path.txt` updates `Wallpaper.current`.
- [ ] Deleting the config/state files leaves the shell running with defaults.
- [ ] `make check` passes; `make smoke` passes (or is documented as skipped).
- [ ] `qmllint` has no *errors*; singleton member access resolves via `qmldir`.
- [ ] Cold start measured once (`qs log` timestamps) and recorded in the PR.

---

## 4. Handoff report

Use `docs/SUBAGENT_PLAN.md` §9. Include:

- exact defaults-resolution order you implemented,
- every IPC target + signature,
- every env var,
- the fallback palette (file/line),
- anything WS1 must know (e.g. `Toast.items` shape, `Config.warnings`).

Do not start WS1 work in this branch. Stop after WS0 is green.
