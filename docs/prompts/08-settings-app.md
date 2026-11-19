# WS8 — Settings application

**Branch:** `feat/ws8-settings` · **Worktree:** `../ostrich-ws8`
**Wave:** 4 · **Depends on:** WS0, WS1, WS5 merged (needs every config key + service) ·
**Blocks:** WS11 release
**Owns:** `shell/modules/settings/`

---

## Mission

Replace hand-editing `config.json` with a real settings app: every supported key
is reachable from the UI, changes apply live, invalid values are impossible or
explained, and per-monitor overrides are editable without guessing JSON. This is
the difference between a rice and a product.

Read `CONTRACTS.md` §4 (Config API) and §5 (schema), `docs/DESIGN.md` §4
(settings layout: `Bubble` sidebar + `solid` content cards on the canvas, no
nested cards deeper than two levels), plus the final `config/default.json` after
WS0–WS7 merged.

---

## 1. Structure

```
modules/settings/
├── Settings.qml            # FloatingWindow host, open(page)/close(), IPC
├── SettingsSidebar.qml
├── SettingsPage.qml        # base: title, description, search anchor
├── SettingsSearch.qml
├── SettingsRow.qml         # label + description + control slot
├── controls/
│   ├── TextSetting.qml
│   ├── NumberSetting.qml
│   ├── BoolSetting.qml
│   ├── SelectSetting.qml
│   ├── SliderSetting.qml
│   ├── ColorSetting.qml      # theme token preview + accent override
│   ├── ListSetting.qml       # string lists (widget order, pinned apps)
│   ├── MonitorSetting.qml    # per-monitor override editor
│   └── JsonSetting.qml       # advanced raw editor with validation
├── pages/
│   ├── AppearancePage.qml
│   ├── BarPage.qml
│   ├── LauncherPage.qml
│   ├── DockPage.qml
│   ├── NotificationsPage.qml
│   ├── ServicesPage.qml
│   ├── PowerPage.qml
│   ├── ShortcutsPage.qml
│   ├── MonitorsPage.qml
│   ├── BackupPage.qml
│   └── AboutPage.qml
└── schema/
    ├── Schema.qml            # ordered list of settings metadata
    ├── AppearanceSchema.qml
    └── ...
```

---

## 2. Host window

- `FloatingWindow` (normal toplevel), default 900×640, minimum 720×520,
  title "Ostrich Settings", remembers size/position in `State`.
- `Settings.qml` API: `open(page)`, `close()`, `toggle()`;
  `IpcHandler { target: "settings" }` with `open(page)`, `close()`.
- Single instance: opening while open switches page and raises the window
  (`startSystemMove` is not needed; just `visible = true`).
- Centred on the focused screen on first open; not per-monitor.
- Escape closes; Ctrl+W closes; Ctrl+F focuses search; Ctrl+Z reverts the last
  change (see §5).
- Close on compositor close request; no unsaved-changes dialog because every
  change is applied immediately (except the raw JSON editor).

---

## 3. Schema-driven UI

`schema/Schema.qml` exposes an ordered model:

```qml
[
  { page: "appearance", section: "Theme", path: "theme.scheme",
    label: qsTr("Color scheme"), description: qsTr("Dynamic follows the wallpaper."),
    type: "select", options: ["dynamic", "ostrich", "graphite", "moss", "sand"],
    requiresRestart: false },
  { page: "bar", section: "Layout", path: "bar.height",
    label: qsTr("Height"), type: "number", min: 24, max: 64, step: 1 },
  ...
]
```

Rules:

- One entry per user-facing key in `config/default.json`; keys deliberately
  hidden (internal/experimental) are listed in `Schema.hiddenKeys` with a reason.
- The About page asserts coverage at runtime: a dev-only warning lists config
  keys that have no schema entry (compare flattened `Config.data` with schema
  paths). This is the safety net that stops settings from drifting.
- Controls read `Config.value(path)` and write `Config.set(path, value)`.
- Validation lives with the control type (`number` min/max/step, `select`
  options, `list` item non-empty, colour `#rrggbb`), not in each page.
- `requiresRestart` shows a small "applies on reload" note; nothing in v1 should
  actually require a restart (if it does, say so and explain).
- Per-monitor: `MonitorsPage` lists `Quickshell.screens` by name and edits
  `monitors.<name>.<path>` via `Config.set`; an override row shows the inherited
  value as placeholder and a reset button.
- Search filters every page by label, description, and config path; results jump
  to the page and highlight the row. Empty search restores the current page.
- Keyboard: Ctrl+F search, Tab through controls, Space toggles switches,
  arrow keys change selects/sliders, no focus traps.

---

## 4. Pages (minimum content)

| Page | Must include |
| --- | --- |
| Appearance | scheme (dynamic/static), variant, mode (dark/light/auto), light/dark times, transparency base/layers, reduced motion, high contrast, font scale, **Pebble material: `pebbleQuality` (low/medium/high) and `pebbleTint` (0..0.2) with a live preview card** |
| Bar | position, height, **floating pebble toggle**, margins, auto-hide, widget slots (reorderable lists), clock format, **clock style (text/dots)**, battery percent, tray hidden items |
| Launcher | fuzzy toggle, max results, prefix map editor, file search enable/roots, close on launch |
| Dock | enabled, position, auto-hide, icon size, pinned apps (drag list), per-monitor enable |
| Notifications | DND, timeout, position, history enable, max visible, clear history button |
| Services | audio default device, weather enable/location/units, brightness step, battery thresholds, idle timeouts (lock/DPMS/suspend) |
| Power | profile selector, lock-before-suspend, session actions with confirmation |
| Shortcuts | read `hyprctl binds -j` (async, fallback to "unavailable"), list Ostrich IPC commands from a static table, edit custom binds (see §5) |
| Monitors | per-monitor overrides for bar height/position, dock enable, background |
| Backup | export config to `$STATE/exports/config-<timestamp>.json`, import from path field with validation, reset section/all |
| About | version (`VERSION`), Quickshell/Qt versions, scheme source, config path, log path, `ostrich doctor` output (async, copyable), links |

---

## 5. Behaviour details

- **Live apply**: every write goes through `Config.set`, which debounces; the
  shell reacts through `Config.changed`.
- **Undo**: keep an in-memory stack of the last 20 `{path, old, new}`; Ctrl+Z
  reverts. Cleared on close.
- **Reset**: per-row reset (delete key → `Config.reset(path)`), per-section
  "Reset section", and "Reset everything" with confirmation. Reset removes the
  key from the user file; it does not write the default value.
- **Export/import**: export writes atomically, import validates JSON and the
  `version` field, shows a diff summary (keys added/changed), and applies only
  after confirmation. Never import files from untrusted paths silently.
- **Raw JSON editor** (`JsonSetting`): shows the effective config with
  `JSON.stringify(…, null, 2)`, validates on Apply, refuses to write invalid
  JSON, and warns about unknown keys. This is the escape hatch, not the main UI.
- **Shortcuts page**: parse Hyprland binds asynchronously (`hyprctl binds -j`,
  1 s timeout); show key → dispatcher. Custom binds are stored in
  `$CONFIG/keybinds.conf` (one `bind = MODS, KEY, exec, ostrich ipc call …` per
  line, validated against a key/modifier allowlist). WS10's Hyprland snippet will
  `source` that file; coordinate in the handoff, do not edit `config/hypr/`.
- **No secrets**: Wi-Fi passwords, PAM input, and tokens never appear in the
  settings UI or exports.
- **Search + schema coverage** must work with the monitor-override paths too.

---

## 6. Tests

- `tests/tst_schema_coverage.qml`: every leaf key in `config/default.json` is
  covered by `Schema` or `hiddenKeys`; every schema path exists in defaults.
- `tests/tst_settings_controls.qml`: number min/max/step clamping, select
  options, colour validation, list add/remove/reorder, reset removes the key.
- `tests/tst_settings_search.qml`: search matches label/path/description, empty
  query restores the page, no duplicate results.
- `tests/tst_monitor_override.qml`: inherited vs overridden values, reset
  removes only `monitors.<name>` path.
- `tests/tst_settings_io.qml`: export/import round-trip, invalid JSON rejected,
  unknown keys preserved but warned, version mismatch refused.
- UI tests run offscreen; no real `hyprctl` (mock the process output).

---

## 7. Constraints

- Do not edit `config/default.json` directly except to add a key that already
  exists in `CONTRACTS.md`; schema changes go through a contract PR.
- Do not edit other modules; call their APIs with feature detection.
- No file dialogs that depend on GTK/portal; use path fields + export location.
- No `eval`; JSON parse/stringify only.
- Every string `qsTr`, every colour `Theme.c`, every path `Paths`.
- UI uses the shared kit (`Pebble`, `Bubble`, `PebbleButton`, `ListRow`, controls)
  and follows `docs/DESIGN.md`; do not write a settings-specific button, card,
  shadow, or shader.
- The material preview must render at the selected `pebbleQuality` without
  touching the global setting until the user commits it.

---

## 8. Acceptance checklist

- [ ] Every page opens, searches, and writes live; no restart needed.
- [ ] Bar height/position changes are visible immediately on the bar.
- [ ] Theme scheme/mode change updates shell and (via CLI) app themes.
- [ ] Per-monitor override changes only that monitor and can be reset.
- [ ] Export/import round-trips; invalid import is refused with a reason.
- [ ] Reset all returns to defaults and the UI reflects it without reopening.
- [ ] Schema coverage test passes (no unlisted user-facing keys).
- [ ] `make check` green; screenshots of every page in dark and light.
- [ ] Appearance page changes `pebbleQuality`/`pebbleTint` live and the preview
      matches the rest of the shell; settings surface follows `DESIGN.md`.

---

## 9. Handoff report

`docs/SUBAGENT_PLAN.md` §9 plus: schema coverage count, list of hidden keys with
reasons, keybind file format, and any config key that still needs a contract
amend.
