# WS6 — Launcher, dock, overview

**Branch:** `feat/ws6-launcher-dock` · **Worktree:** `../ostrich-ws6`
**Wave:** 2 · **Depends on:** WS0 + WS1 merged · **Blocks:** nothing
**Owns:** `shell/modules/{launcher,dock,overview}/`

---

## Mission

Build the keyboard-first entry points: a launcher that finds apps, does math,
converts units, searches the web/files, and triggers shell actions; a dock with
pinned and running apps; and an overview for workspaces and windows. These are
the surfaces a keyboard user lives in — latency, focus, and key handling matter
more than animation.

Read `CONTRACTS.md` §3, §4, §7, §10. Look up `DesktopEntries`, `DesktopEntry`,
`Hyprland`, `HyprlandWorkspace`, `HyprlandToplevel`, `ToplevelManager`,
`ScreencopyView`, `GlobalShortcut` before coding.

---

## 1. Launcher (`modules/launcher/`)

```
Launcher.qml             # module root: overlay window, open/close/toggle, IPC
LauncherContent.qml      # search field + results + preview
SearchField.qml
ResultList.qml
ResultRow.qml
providers/
├── Provider.qml          # base: id, prefix, priority, query(text) -> [{...}]
├── AppsProvider.qml
├── CalcProvider.qml
├── UnitsProvider.qml
├── ActionsProvider.qml
├── FilesProvider.qml
├── WindowsProvider.qml
├── WallpapersProvider.qml
└── SchemesProvider.qml
Calc.js                   # tokenizer + shunting-yard evaluator
Units.js                  # conversion table
```

Behaviour:

- Full-screen `WlrLayershell` overlay per focused screen:
  `WlrLayer.Overlay`, `keyboardFocus: WlrKeyboardFocus.Exclusive` while open,
  `exclusiveZone: 0`, transparent scrim (click closes), panel centred at ~20%
  from top, max width 640.
- Open animation 120 ms fade/scale; close instantly on Escape; reduced motion
  removes the scale.
- Focus the search field on open; typing filters live (debounced 16 ms max, not
  a timer per keystroke if avoidable — use a 30 ms `Timer` restart).
- Results: grouped by provider, max `launcher.maxResults` (default 8), stable
  ranking (provider priority, then score, then name).
- Keyboard: Up/Down move, PageUp/PageDown jump 5, Enter executes, Tab completes a
  prefix, Escape closes, Ctrl+1..9 executes result N, Ctrl+Enter opens the
  containing folder for apps? (skip if no folder), Right arrow shows actions
  (e.g. "Launch", "Open in terminal", "Pin to dock") — keep the action menu
  small and keyboard reachable.
- Preview pane (right or below): app icon, name, comment, generic name,
  categories, executable summary. No web images.
- Empty query: recent (from `State`, cap 20) then pinned, then all apps alphabetically.
- Launch: `DesktopEntry.execute()`, record in recents, close by default
  (`launcher.closeOnLaunch` config).

### Prefix modes

From `launcher.prefixes` config plus defaults:

| Prefix | Provider | Example |
| --- | --- | --- |
| `=` | Calc | `= 2*(3+4)` |
| `>` | Actions | `> lock`, `> settings`, `> theme dark` |
| `:` | Emoji (WS9 hook) | `: tada` |
| `~` | Files | `~ report` |
| `@` | Windows | `@ firefox` |
| `#` | Wallpapers | `# mountain` |
| `%` | Schemes | `% graphite` |

Unknown prefix falls back to normal search. Providers must be registered in one
list (`providers/Provider.qml` registry) so adding one is a single file.

### Calculator (`Calc.js`)

- Tokenizer + shunting-yard; operators `+ - * / % ^`, unary minus, parentheses,
  functions `sqrt sin cos tan log ln abs round floor ceil`, constants `pi e`.
- **Never use `eval`/`Function`.** Reject unknown tokens with an inline error.
- Result formatting: integers without `.0`, floats to 6 significant digits,
  thousands separators in the preview only.
- `2+2` (no prefix) should still show a calc result *below* app results, but not
  steal Enter from an exact app match.

### Units (`Units.js`)

- Length, mass, temperature, data, time, speed; syntax `10 km to mi`,
  `70f to c`, `5 GiB to MB`. Table-driven, integers and floats, case-insensitive
  aliases. Unknown unit → no result (not an error).

### Files provider

- Disabled by default (`launcher.files.enabled`), requires `fd` or `find`.
- Async `Process` with a 300 ms debounce, 2 s timeout, max 20 results, roots from
  config (default `$HOME`), never follows symlinks outside roots.
- Show path with the home prefix shortened; Enter opens with
  `Qt.openUrlExternally("file://…")`.

### Windows provider

- `Workspaces.windows` (WS1 stub returns `[]`) or `Hyprland.toplevels`.
- Results `{ title, class, workspace }`; Enter focuses the window via
  `Hyprland.dispatch("focuswindow address:<addr>")` when available; otherwise
  no-op with a toast.

### Wallpapers / schemes providers

- Wallpapers: `Wallpaper.list`, filter by name, Enter `Wallpaper.set(path)`,
  Ctrl+Enter `Wallpaper.preview(path)`.
- Schemes: static names from `ostrich scheme list`? Avoid CLI here; read
  `Theme.name` + a small list exposed by `Theme` (request a
  `Theme.schemes` contract addition) or read `themes` from config. If absent,
  only `dark`/`light`/`auto` actions.

### Actions provider

Static list wired to existing APIs: lock, logout, suspend, reboot, shutdown,
settings, control center, notifications center, screenshot, record, clipboard,
theme dark/light/toggle, reload shell (`Quickshell.reload()`), open config
folder. Each has an icon and a `run()` that feature-detects the owning module.

### IPC

`IpcHandler { target: "launcher" }` — `toggle()`, `open(mode)`, `close()`.
`mode` = provider id or `""`; unknown mode opens all.

---

## 2. Dock (`modules/dock/`)

```
Dock.qml              # PanelWindow per monitor, autohide, IPC
DockItem.qml
DockSeparator.qml
PinnedModel.qml
RunningModel.qml
```

- `PanelWindow` per screen (only screens where `dock.enabled` and not disabled by
  `Config.forScreen(screen).modules.dock === false`), anchored bottom (config
  `dock.position`: bottom/top/left/right; support bottom + left/right
  orientations, top optional).
- `exclusiveZone`: icon size + padding when visible; `0` when auto-hidden.
- Auto-hide: hidden by translating the window margin; reveal zone 2 px along the
  edge, 250 ms show delay, 400 ms hide delay after leaving; never hides while a
  menu/popup is open.
- Pinned apps from `Config.value("dock.pinned", [])` (desktop ids). Running apps
  from `DesktopEntries` matching `Workspaces.windows` classes, plus unmatched
  windows with a generic icon.
- Item states: pinned, running, active (focused window's class), urgent.
- Click: not running → launch pinned; running single window → focus; multiple
  windows → cycle or show a small menu listing titles; middle → new instance
  (`entry.execute()` regardless), right → context menu (pin/unpin, close all,
  new instance).
- Drag reorder pinned items; drop writes `Config.set("dock.pinned", ids)`.
- Launcher integration: click on the far-left "apps" button opens the launcher.
- Tooltips with app name + window count; keyboard: dock is not focusable, but
  items get `Accessible.name`.
- Apps with `StartupWMClass` must match correctly — use `DesktopEntry` fields and
  a small class→id map in `RunningModel.qml`.
- IPC `dock`: `toggle()`, `show()`, `hide()`.

---

## 3. Overview (`modules/overview/`)

```
Overview.qml          # overlay window, open/close/toggle, IPC
WorkspaceGrid.qml
WorkspaceCard.qml
WindowCard.qml
WindowPreview.qml     # optional ScreencopyView, feature-flagged
```

- Full-screen overlay on the focused screen, `WlrLayer.Overlay`,
  `keyboardFocus: Exclusive` while open, scrim click closes, Escape closes.
- Grid of `Workspaces.list` (Hyprland), active workspace highlighted, window count
  per workspace (from `Workspaces.windows` once it exposes workspace; otherwise
  count via `Hyprland.toplevels`).
- Window cards: icon + title + class, grouped per workspace when data allows;
  click focuses (`focuswindow`), middle closes (`closewindow`), drag to another
  workspace card dispatches `movetoworkspacesilent`.
- Keyboard: arrows navigate, Enter focuses, `1..9` switches workspace, `Escape`
  closes.
- Previews (`ScreencopyView`) behind `overview.previews` config, default off;
  they must never block opening the overview. If the type misbehaves on the
  compositor, the feature flag turns the whole card back to text.
- IPC `overview`: `toggle()`, `open()`, `close()`.

---

## 4. Config keys

Existing: `launcher.{fuzzy,maxResults,prefixes}`, `dock.{enabled,position,autoHide,pinned}`,
`modules.{launcher,dock,overview}`.
Add via contract PR: `launcher.files.enabled`, `launcher.closeOnLaunch`,
`launcher.width`, `dock.iconSize`, `dock.magnify`, `overview.previews`.

Read through `Config.value`; defaults live in `config/default.json` only.

---

## 5. Tests

- `tests/tst_calc.qml` (or `.js` unit tests run from QML): precedence,
  parentheses, unary minus, functions, invalid input, no `eval`.
- `tests/tst_units.qml`: every unit pair round-trips within tolerance;
  temperature is affine, not multiplicative.
- `tests/tst_fuzzy_rank.qml`: exact match beats prefix beats substring; app
  ranking stability with equal scores.
- `tests/tst_launcher_state.qml`: prefix parsing, empty query recents order,
  max results, keyboard selection wrap-around.
- `tests/tst_dock_model.qml`: pin/unpin persistence, running/pinned merge,
  duplicate suppression, class→desktop-id matching.
- `tests/tst_overview_nav.qml`: grid navigation math, workspace switch dispatch
  arguments (mock dispatch).
- No real compositor required.

---

## 6. Constraints

- No `eval`, no `Function`, no remote scripts.
- No per-keystroke process spawns; debounce and cap concurrency (1 search at a
  time, cancel by `Process.signal`/restart).
- Never steal focus while closed; never leave keyboard grabbed after close or
  reload (test a reload while the launcher is open).
- Launching uses `DesktopEntry.execute()`; never build a shell command from a
  `.desktop` `Exec` line yourself.
- Do not edit shared services/components or other modules.

---

## 7. Acceptance checklist

- [ ] Launcher opens in < 50 ms perceived, filters as you type, launches apps.
- [ ] `= 2*(3+4)` → 14; `sqrt(2)`; invalid input shows an inline error.
- [ ] `10 km to mi`, `70f to c` give correct values.
- [ ] Prefixes from config work and unknown prefixes fall back to apps.
- [ ] Dock: pin/unpin persists, running indicators correct, autohide both edges.
- [ ] Overview: navigate, focus a window, move a window between workspaces.
- [ ] All three modules close on Escape and on reload without leaving a grab.
- [ ] `make check` green; recording of launcher + dock + overview.

---

## 8. Handoff report

`docs/SUBAGENT_PLAN.md` §9 plus: provider registry API, ranking formula, keyboard
map, config keys, and the exact `Hyprland.dispatch` strings used (with the
non-Hyprland fallback).
