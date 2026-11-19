# Ostrich Implementation Contracts (v1)

**Status:** frozen for parallel implementation (2026-11-19).
**Owner:** WS0 (core-kernel). Any change to this file needs a PR and an explicit
note in the workstream handoff.

These contracts exist so 10+ subagents can implement different parts of the shell
at the same time without breaking each other. Code against this document, not
against assumptions.

---

## 0. Ground rules

1. Ostrich is QML-only in v1. **No C++/CMake plugin.** Effects that would need one
   (morphing blobs, GPU visualisers) are deferred; Canvas/ShaderEffect fallbacks
   are acceptable.
2. Internal imports are **relative directory imports**:
   `import "../../services"`, `import "../../components"`.
   Do **not** use `qs.services` / `qs.components`; they resolve in Quickshell but
   not in `qmllint`, which would blind our CI.
3. Every singleton is a file with `pragma Singleton`, `import Quickshell`, and a
   `Singleton { }` root.
4. UI never constructs a service. Import the singleton and bind to it.
5. No hardcoded colors, absolute paths, usernames, monitor names, or fonts.
   Use `Theme`, `Paths`, `Config`.
6. Every user-visible string is wrapped in `qsTr()`.
7. All external processes use `Process.command` as an argument list (never a
   single string with a shell unless `["sh", "-c", ...]` is genuinely required).
8. Do not copy code, assets, strings, or design files from the reference shell
   (GPL-3.0). Ostrich is MIT; this must stay clean-room.

---

## 1. Repository layout and ownership

```
shell/                          # Quickshell config root (run: qs -p shell)
├── shell.qml                   # ShellRoot; module wiring                  [WS0]
├── services/                   # singletons                               [split, see §4]
├── components/                 # UI kit primitives                        [WS1]
├── utils/                      # pure QML helpers (no singletons)         [WS1]
└── modules/
    ├── background/             # wallpaper layer, desktop clock           [WS2]
    ├── bar/                    # PanelWindow bar + widgets                [WS3]
    ├── notifications/          # popups + history                         [WS4]
    ├── osd/                    # volume/brightness/media OSD              [WS4]
    ├── controlcenter/          # quick settings popup                    [WS5]
    ├── launcher/               # apps/calc/actions/prefixes               [WS6]
    ├── dock/                   # pinned + running apps                   [WS6]
    ├── session/                # power menu                              [WS7]
    ├── lock/                   # WlSessionLock + PAM                     [WS7]
    ├── settings/               # full settings app                       [WS8]
    ├── overview/               # workspace overview / window info         [WS9]
    └── utilities/              # clipboard, screenshot, recorder, emoji   [WS9]

cli/                            # Python package `ostrich`                 [WS2]
├── pyproject.toml
├── src/ostrich/
│   ├── __main__.py, cli.py
│   ├── scheme.py               # material palette generation
│   ├── wallpaper.py            # swww/hyprpaper adapters
│   ├── templates.py            # render + apply app themes
│   ├── auto.py                 # light/dark scheduler
│   ├── paths.py
│   └── data/
│       ├── schemes/            # static schemes (JSON)
│       ├── templates/          # app templates
│       └── manifest.json       # template targets
└── tests/                      # pytest

config/
├── default.json                # default shell config                   [WS0]
├── hypr/ostrich.conf           # keybinds / exec-once snippet           [WS10]
└── examples/                   # annotated example configs              [WS11]

rice/                           # terminal/desktop rice                   [WS10]
├── foot/foot.ini
├── fish/{config.fish,functions/}
├── starship.toml
├── btop/
└── fastfetch/

themes/schemes/                 # curated static palettes (optional)     [WS2]
tests/                          # QML tests + mocks                      [WS1/WS11]
docs/                           # this plan, contracts, guides
```

Shared files (`shell/shell.qml`, `services/Paths.qml`, `services/Config.qml`,
`services/Theme.qml`, `components/*`, `docs/CONTRACTS.md`) are **owned by WS0 or
WS1** and must not be edited by other workstreams. Request a contract change
instead.

---

## 2. Runtime paths

| Purpose | Path | Env override |
| --- | --- | --- |
| Config | `${XDG_CONFIG_HOME:-~/.config}/ostrich/config.json` | `OSTRICH_CONFIG_DIR` |
| State (scheme, wallpaper) | `${XDG_STATE_HOME:-~/.local/state}/ostrich/` | `OSTRICH_STATE_DIR` |
| Data (generated) | `${XDG_DATA_HOME:-~/.local/share}/ostrich/` | `OSTRICH_DATA_DIR` |
| Cache | `${XDG_CACHE_HOME:-~/.cache}/ostrich/` | `OSTRICH_CACHE_DIR` |
| Wallpapers | `Config.paths.wallpaperDir` (default `~/Pictures/Wallpapers`) | `OSTRICH_WALLPAPERS_DIR` |
| Recordings | `Config.paths.recordingsDir` (default `~/Videos/Recordings`) | `OSTRICH_RECORDINGS_DIR` |
| Scheme file | `$STATE/scheme.json` | — |
| Wallpaper pointer | `$STATE/wallpaper/path.txt` | — |
| UI state | `$STATE/state.json` | — |

The CLI and shell must agree on these paths. The shell watches the state files;
the CLI writes them atomically (temp file + rename).

---

## 3. Entry point and modules

`shell/shell.qml` is a `ShellRoot` that instantiates, in this order:

```
Background, Bar, Notifications, Osd, Launcher, Dock,
ControlCenter, Session, Overview, Settings, Utilities, Lock
```

Each module is an `Item` (or window type) with this minimum API:

| Module | File | Required API |
| --- | --- | --- |
| Background | `modules/background/Background.qml` | — (layer shell) |
| Bar | `modules/bar/Bar.qml` | `toggle()` |
| Notifications | `modules/notifications/Notifications.qml` | `open()`, `close()` |
| Osd | `modules/osd/Osd.qml` | `show(kind, value)`, `close()` |
| Launcher | `modules/launcher/Launcher.qml` | `open(mode)`, `close()`, `toggle()` |
| Dock | `modules/dock/Dock.qml` | `toggle()` |
| ControlCenter | `modules/controlcenter/ControlCenter.qml` | `open()`, `close()`, `toggle()` |
| Session | `modules/session/Session.qml` | `open()`, `close()` |
| Overview | `modules/overview/Overview.qml` | `open()`, `close()`, `toggle()` |
| Settings | `modules/settings/Settings.qml` | `open(page)`, `close()` |
| Utilities | `modules/utilities/Utilities.qml` | `open(kind)`, `close()` |
| Lock | `modules/lock/Lock.qml` | `lock()`, `unlock()` |

Rules:

- Modules own their `IpcHandler`s (see §8). `shell.qml` stays a thin composition
  root so parallel work never conflicts there.
- Per-monitor UI uses `Variants { model: Quickshell.screens }`; never hardcode a
  screen. A module may be global (lock, settings) or per-screen (bar, dock).
- WS0 provides placeholder files for all modules that render nothing, so the
  shell boots before the modules exist.

---

## 4. Shared singletons

All files are under `shell/services/`. Property/function signatures are the
contract; additional internal helpers are allowed.

```qml
// Paths.qml
readonly property string home, config, state, data, cache, pictures, videos,
                         wallsdir, recordingsdir
function absolute(path: string): string
function shortenHome(path: string): string
```

```qml
// Config.qml
readonly property var data            // merged defaults + user config
readonly property bool ready
function value(path: string, fallback): var     // dot path: "bar.height"
function set(path: string, value): void         // persists atomically
function reload(): void
function reset(path: string): void
function forScreen(screen): var                 // merged per-monitor view
signal changed(string path)
```

```qml
// State.qml  (persistent UI state, debounced writes of $STATE/state.json)
function get(key: string, fallback): var
function set(key: string, value): void
signal changed(string key)
```

```qml
// Theme.qml  (watches $STATE/scheme.json)
readonly property var colours         // map: token -> "#rrggbb"
readonly property string name, flavour, variant
readonly property string mode         // "dark" | "light"
readonly property bool isLight
readonly property string source       // wallpaper path or "static"
readonly property var schemes         // [{name, flavours:[...]}] from `ostrich scheme list --json`
readonly property bool reducedMotion  // from config appearance.reducedMotion
readonly property real fontScale      // from config appearance.fontScale
function c(token: string): color
function setMode(mode: string): void  // "dark" | "light" | "auto"
function toggleMode(): void
function setScheme(name: string, flavour: string): void
function reload(): void
signal changed
```

```qml
// Wallpaper.qml  (watches $STATE/wallpaper/path.txt)
readonly property string current
readonly property var list            // [{path, name, category}]
function set(path: string): void       // calls `ostrich wallpaper set`
function random(): void
function preview(path: string): void
function cancelPreview(): void
signal changed
```

```qml
// Time.qml  (SystemClock; no polling timers)
readonly property date date
readonly property int hours, minutes, seconds
readonly property string timeStr, dateStr
function format(fmt: string): string
```

```qml
// Battery.qml
readonly property bool available, charging, plugged
readonly property real percent        // 0..100
readonly property int minutesRemaining
readonly property string state, health
signal low, critical
```

```qml
// Audio.qml
readonly property var sink            // {id, name, description, volume, muted}
readonly property var source
readonly property var sinks, sources  // lists of the same shape
readonly property var streams         // [{id, name, volume, muted}]
function setVolume(v: real): void     // 0..1
function toggleMute(): void
function setDefaultSink(id: string): void
function setStreamVolume(id: string, v: real): void
```

```qml
// Bluetooth.qml
readonly property bool available, enabled, scanning
readonly property var devices         // [{address,name,connected,paired,battery}]
function toggle(): void
function scan(): void
function pair(address: string): void
function connect(address: string): void
function disconnect(address: string): void
function forget(address: string): void
```

```qml
// Network.qml
readonly property bool available, enabled, wifiEnabled
readonly property string connectivity, ssid
readonly property int signal
readonly property var networks        // [{ssid,strength,secured,active}]
function toggleWifi(): void
function scan(): void
function connect(ssid: string, password: string): void
function disconnect(): void
```

```qml
// Media.qml
readonly property var players         // [{id,name}]
readonly property var active          // {title,artist,album,artUrl,playing,position,length,canSeek}
function play(): void
function pause(): void
function toggle(): void
function next(): void
function previous(): void
function seek(position: real): void
```

```qml
// Tray.qml
readonly property var items           // [{id,icon,title,tooltip,hasMenu}]
function activate(id: string, button: int): void
function openMenu(id: string, parentWindow: var, x: int, y: int): void
function scroll(id: string, delta: int): void
```

```qml
// Notifications.qml  (owns org.freedesktop.Notifications)
readonly property var list            // newest first
readonly property bool dnd
readonly property int unread
function toggleDnd(): void
function clear(): void
function dismiss(id: var): void
function invokeAction(id: var, action: string): void
signal received
```

```qml
// Power.qml
readonly property var profiles
readonly property string profile
function setProfile(name: string): void
function lock(): void
function logout(): void
function suspend(): void
function hibernate(): void
function reboot(): void
function shutdown(): void
function firmware(): void
```

```qml
// Workspaces.qml  (Hyprland adapter; available=false elsewhere)
readonly property bool available
readonly property var list            // [{id,name,occupied,active,urgent}]
readonly property int activeId
readonly property string focusedMonitor
readonly property var windows         // [{id,title,class,workspace}]
function switchTo(id: int): void
function moveWindow(id: int, workspace: int): void
```

```qml
// Brightness.qml
readonly property bool available
readonly property real value          // 0..1
function set(v: real): void
function increase(step: real): void
function decrease(step: real): void
```

```qml
// Weather.qml
readonly property bool enabled
readonly property string location
readonly property var current         // {temp,code,description,icon}
readonly property var forecast        // [{day,min,max,code}]
function refresh(): void
```

```qml
// Idle.qml
readonly property bool inhibited, locked
readonly property int idleMs
function inhibit(reason: string): void
function uninhibit(): void
function lock(): void
function dpms(on: bool): void
```

```qml
// Clipboard.qml
readonly property var entries         // [{id,text,image,time}]
function copy(id: var): void
function remove(id: var): void
function clear(): void
```

```qml
// Recorder.qml
readonly property bool recording
readonly property string path
function start(mode: string): void    // "screen" | "region"
function stop(): void
```

```qml
// Toast.qml  (generic transient notifications for the shell itself)
function show(message: string, kind: string): void  // kind: info|warn|error|success
```

WS1 ships **interface-complete stubs** for every singleton above. WS2/WS4/WS5/WS7/WS9
replace only their owned files with real implementations, keeping the signatures.

---

## 5. Config schema v1

`config/default.json` is the source of defaults. Unknown keys are preserved and
reported as warnings; missing keys fall back to defaults. `version` gates
migrations.

```json
{
  "version": 1,
  "modules": {
    "bar": true,
    "notifications": true,
    "osd": true,
    "dock": true,
    "launcher": true,
    "controlCenter": true,
    "overview": true,
    "utilities": true,
    "lock": true
  },
  "paths": {
    "wallpaperDir": "~/Pictures/Wallpapers",
    "recordingsDir": "~/Videos/Recordings"
  },
  "appearance": { "fontScale": 1.0, "reducedMotion": false },
  "background": { "mode": "layer", "crossfadeMs": 250, "clock": false },
  "theme": {
    "scheme": "dynamic",
    "variant": "tonalspot",
    "mode": "auto",
    "apps": {
      "gtk": true, "qt": true, "foot": true, "fish": true, "btop": true,
      "starship": true, "fastfetch": true, "micro": false, "fuzzel": true,
      "zed": false, "vscode": false, "firefox": false,
      "spicetify": false, "discord": false
    },
    "auto": { "lightAt": "07:00", "darkAt": "19:00" },
    "transparency": { "enabled": true, "base": 0.85, "layers": 0.9 }
  },
  "bar": {
    "position": "top",
    "height": 32,
    "autoHide": false,
    "clock": { "format": "HH:mm" },
    "battery": { "showPercent": false },
    "tray": { "hiddenItems": [] },
    "widgets": {
      "left": ["workspaces"],
      "center": ["clock"],
      "right": ["tray", "network", "battery", "volume", "power"]
    }
  },
  "launcher": {
    "fuzzy": true,
    "maxResults": 8,
    "closeOnLaunch": true,
    "files": { "enabled": false, "roots": ["~"] },
    "prefixes": {
      "calc": "=", "actions": ">", "emoji": ":", "files": "~",
      "windows": "@", "wallpapers": "#", "schemes": "%"
    }
  },
  "dock": {
    "enabled": true, "position": "bottom", "autoHide": true,
    "iconSize": 40, "pinned": []
  },
  "overview": { "previews": false },
  "notifications": {
    "dnd": false, "timeoutMs": 5000, "position": "top-right",
    "history": true, "maxVisible": 3, "centerWidth": 380
  },
  "osd": { "position": "bottom", "timeoutMs": 1500 },
  "clipboard": {
    "images": true, "persist": true, "closeOnCopy": true, "denylist": []
  },
  "recorder": { "audio": false, "directory": "" },
  "dashboard": { "icsPath": "", "mounts": ["/"] },
  "utilities": { "panelWidth": 720 },
  "lock": { "blur": true, "media": false, "clock24h": true },
  "services": {
    "battery": { "low": 15, "critical": 5 },
    "weather": { "enabled": false, "provider": "open-meteo", "location": "auto", "units": "metric" },
    "brightness": { "step": 0.05 },
    "idle": { "lockAfter": 300, "dpmsAfter": 600, "suspendAfter": 0, "lockBeforeSuspend": true }
  },
  "apps": { "terminal": "foot", "fileManager": "thunar", "browser": "firefox" },
  "monitors": {
    "DP-1": { "bar": { "height": 40 }, "modules": { "dock": false } }
  }
}
```

Rules:

- `Config.value` accepts dot paths; arrays are replaced, objects are deep-merged.
- `monitors.<name>` is deep-merged over the top-level config by `Config.forScreen`.
- Writes are atomic; file permissions `0600`.
- Config is reloaded on external change (watch the file) and emitted via
  `changed(path)`.
- A new key lands in this block and `config/default.json` in the same contract
  PR. The settings schema (WS8) must cover every leaf key here.

---

## 6. `scheme.json`

Written by the CLI, watched by `Theme.qml`.

```json
{
  "version": 1,
  "name": "dynamic",
  "flavour": "default",
  "mode": "dark",
  "variant": "tonalspot",
  "source": "/home/user/Pictures/Wallpapers/example.jpg",
  "generatedAt": "2026-11-19T18:00:00Z",
  "colours": {
    "primary": "#a6c8ff",
    "onPrimary": "#00315c",
    "surface": "#101418",
    "onSurface": "#e1e2e8",
    "term0": "#101418"
  }
}
```

- `colours` values always include `#`.
- `mode` is `dark` or `light`.
- `name` is `dynamic` for wallpaper-derived palettes or a static scheme name.
- Omitted tokens are filled from a built-in fallback palette by `Theme.qml`.

Token set (all required):

`primary`, `onPrimary`, `primaryContainer`, `onPrimaryContainer`,
`secondary`, `onSecondary`, `secondaryContainer`, `onSecondaryContainer`,
`tertiary`, `onTertiary`, `tertiaryContainer`, `onTertiaryContainer`,
`error`, `onError`, `errorContainer`, `onErrorContainer`,
`background`, `onBackground`, `surface`, `onSurface`,
`surfaceDim`, `surfaceBright`, `surfaceContainerLowest`, `surfaceContainerLow`,
`surfaceContainer`, `surfaceContainerHigh`, `surfaceContainerHighest`,
`surfaceVariant`, `onSurfaceVariant`, `outline`, `outlineVariant`,
`shadow`, `scrim`, `inverseSurface`, `inverseOnSurface`, `inversePrimary`,
`term0`..`term15`.

---

## 7. IPC

Every module registers an `IpcHandler` with the exact target below.

| Target | Functions |
| --- | --- |
| `bar` | `toggle()`, `show()`, `hide()` |
| `launcher` | `toggle()`, `open(mode)`, `close()` |
| `dock` | `toggle()`, `show()`, `hide()` |
| `notifications` | `toggleDnd()`, `dnd(bool)`, `clear()`, `open()`, `close()` |
| `osd` | `show(kind, value)`, `close()` |
| `controlcenter` | `toggle()`, `open()`, `close()` |
| `overview` | `toggle()`, `open()`, `close()` |
| `settings` | `open(page)`, `close()` |
| `theme` | `setMode(mode)`, `toggleMode()`, `reload()` |
| `wallpaper` | `get()`, `set(path)`, `random()`, `list()` |
| `media` | `playPause()`, `next()`, `previous()` |
| `power` | `lock()`, `suspend()`, `reboot()`, `shutdown()`, `logout()`, `profile(name)` |
| `lock` | `lock()`, `unlock()` (unlock requires PAM success; the IPC call only requests it) |
| `clipboard` | `open()`, `clear()` |
| `screenshot` | `region()`, `full()` |
| `recorder` | `start(mode)`, `stop()` |

CLI wrapper: `ostrich ipc <target> <function> [args...]` → `qs ipc call`.

---

## 8. CLI contract

Entry point: `ostrich`. Python ≥ 3.12. Runtime deps: `Pillow`,
`materialyoucolor` (+ optional `pytest`, `ruff` for dev).

```
ostrich wallpaper set <path> [--no-smart] [--no-apply]
ostrich wallpaper random
ostrich wallpaper get
ostrich wallpaper list [--json]
ostrich scheme set [--name N] [--flavour F] [--mode dark|light|auto]
                   [--variant V] [--dynamic] [--random] [--no-apply]
ostrich scheme get [--json]
ostrich scheme auto --enable|--disable [--light-at HH:MM] [--dark-at HH:MM]
ostrich theme apply [--dry-run] [--only ID]
ostrich ipc <target> <function> [args...]
ostrich doctor [--json]
```

Behavior:

- All app-theme writes are atomic, back up the previous file as `<target>.bak`,
  and respect `theme.apps.<id>`.
- `--dry-run` prints planned writes (path + template id) and exits 0.
- `theme apply` is idempotent (render, compare, write only on change).
- No command requires root. No command writes outside XDG dirs unless the
  template target explicitly points elsewhere (user config).
- Exit codes: `0` success, `1` usage, `2` invalid config/scheme, `3` missing
  environment (no wallpaper tool, no image), `4` template apply failure.
- `--json` output is stable and documented; `doctor` reports missing optional
  dependencies without failing.

---

## 9. App theme templates

Location: `cli/src/ostrich/data/templates/`. Placeholders use `{{ token }}` and
are replaced with the `scheme.json` value verbatim (`#rrggbb`). Extra
placeholders: `{{ mode }}`, `{{ scheme_name }}`, `{{ flavour }}`, `{{ variant }}`,
`{{ wallpaper }}`, `{{ token_raw }}` (no `#`).

`cli/src/ostrich/data/manifest.json`:

```json
{
  "version": 1,
  "targets": [
    {
      "id": "gtk",
      "template": "gtk.css",
      "target": "~/.config/gtk-4.0/gtk.css",
      "enabledKey": "theme.apps.gtk",
      "modes": ["dark", "light"],
      "reload": [["sh", "-c", "gsettings set org.gnome.desktop.interface color-scheme prefer-dark"]]
    },
    {
      "id": "foot",
      "template": "foot.ini",
      "target": "~/.config/foot/ostrich.ini",
      "enabledKey": "theme.apps.foot",
      "reload": []
    }
  ]
}
```

Rules:

- `reload` is a list of argv arrays; never a shell string for user-provided data.
- Targets containing `~` expand against `$HOME`.
- Missing parent directories are created.
- A template that fails to render is reported and skipped; other targets still
  apply.

---

## 10. UI kit (`shell/components/`)

WS1 ships these primitives with stable APIs; everyone else uses them.

| Component | Required API |
| --- | --- |
| `Button.qml` | `text`, `icon`, `enabled`, `accent`, `onClicked` |
| `IconButton.qml` | `icon`, `size`, `enabled`, `tooltip`, `onClicked` |
| `Slider.qml` | `value` (0..1), `orientation`, `enabled`, `onMoved(real)` |
| `Switch.qml` | `checked`, `enabled`, `onToggled(bool)` |
| `TextField.qml` | `text`, `placeholder`, `onAccepted`, `onTextChanged` |
| `Popup.qml` | `visible`, `anchorItem`, `anchorEdges`, `onClosed` |
| `Tooltip.qml` | `text`, `anchorItem`, `visible` |
| `Menu.qml` / `MenuItem.qml` | `items`, `open(x,y)`, `onTriggered(item)` |
| `ScrollView.qml` | default content property, `contentHeight` |
| `ProgressRing.qml` | `value` (0..1), `thickness` |
| `ProgressBar.qml` | `value` (0..1), `orientation` |
| `Surface.qml` | `radius`, `elevation`, default content |
| `Icon.qml` | `name`, `size`, `color` |
| `Spinner.qml` | `running`, `size` |
| `Separator.qml` | `orientation` |
| `Chip.qml` | `text`, `icon`, `checked`, `onToggled(bool)` |
| `ListRow.qml` | `title`, `subtitle`, `icon`, `trailing`, `selected`, `onActivated` |
| `EmptyState.qml` | `icon`, `title`, `description` |

Sizing uses `implicitWidth`/`implicitHeight`. Colors come from `Theme.c(token)`.
No component may read `Config` directly except layout primitives that document it.

---

## 11. Tests

QML tests: `tests/**/tst_*.qml`, run with `qmltestrunner` (headless).
Python tests: `cli/tests/test_*.py`, run with `pytest`.

Rules:

- Test logic and state machines, not pixel rendering.
- Mock services live in `tests/mocks/`; tests must not require Hyprland, PipeWire,
  BlueZ, NetworkManager, or a real screen.
- Every service gets a test for its pure mapping/parsing logic.
- Every bug fix gets a regression test.
- `make check` must pass; CI is the authority.

Mock contract (WS1): `tests/mocks/MockAudio.qml`, `MockBattery.qml`,
`MockWorkspaces.qml`, `MockNotifications.qml`, each exposing the same properties
as the real singleton so UI can be tested against them.

---

## 12. Definition of done (every workstream)

1. Files exist only under the owned paths (or a contract-change PR was approved).
2. `make check` passes locally; `make smoke` passes if Quickshell is installed.
3. New behavior has tests; new config keys are in `config/default.json` and this
   document.
4. No GPL code/assets/strings copied; no secrets, no hardcoded paths/colors.
5. PR to `dev` with the handoff report (see prompts) and screenshots for UI.
6. Docs updated (`docs/`, `PRD.md` if scope changed, `CHANGELOG.md` Unreleased).
