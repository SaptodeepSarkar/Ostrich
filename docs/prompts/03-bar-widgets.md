# WS3 — Bar and status widgets

**Branch:** `feat/ws3-bar` · **Worktree:** `../ostrich-ws3`
**Wave:** 2 · **Depends on:** WS0 + WS1 merged · **Blocks:** WS5/WS8 (popup host)
**Owns:** `shell/modules/bar/` only

---

## Mission

Build the always-on desktop bar: per-monitor `PanelWindow`, three configurable
widget slots, the standard status widgets, a popout host for click-activated
details, and the `bar` IPC target. This is the shell's primary surface — it must
be correct on one and two monitors, at 100% and 150% scale, without flicker or
focus stealing.

Read `CONTRACTS.md` §3, §4, §5, §7, §10, `docs/DESIGN.md` (especially §4
layout, §2 materials), and the WS1 component list. The bar is a **floating glass
pill**, not an edge-to-edge strip: 8–12 px from the screen edge, radius =
height/2, `Pebble` material `glass`, widget clusters separated by air instead of
divider lines.

---

## 1. Structure

```
shell/modules/bar/
├── Bar.qml                 # PanelWindow per screen, slot layout, IPC
├── BarContent.qml          # shared visual container
├── WidgetSlot.qml          # left/center/right layout + spacing rules
├── WidgetRegistry.qml      # name -> Component map from config
├── PopoutHost.qml          # one anchored popup at a time per bar
├── widgets/
│   ├── Workspaces.qml
│   ├── ActiveWindow.qml
│   ├── Clock.qml
│   ├── Tray.qml
│   ├── Battery.qml
│   ├── Network.qml
│   ├── Volume.qml
│   ├── Media.qml
│   ├── Power.qml
│   ├── StatusIcons.qml      # bluetooth, dnd, lock, recording, idle-inhibit
│   └── Spacer.qml
└── popouts/
    ├── ClockPopout.qml      # calendar + timezones
    ├── BatteryPopout.qml
    ├── NetworkPopout.qml
    ├── VolumePopout.qml
    ├── MediaPopout.qml
    ├── TrayMenu.qml
    └── SystemPopout.qml     # power/profile shortcuts (links to WS7 menu)
```

`Bar.qml` root must be an `Item` with the contract API `toggle()`, plus internal
per-screen windows. `shell.qml` instantiates it once (global), the module creates
one `PanelWindow` per `Quickshell.screens` via `Variants`.

---

## 2. Layout requirements

- Position from `Config.value("bar.position", "top")` — `top` or `bottom`;
  per-monitor override via `Config.forScreen(screen).bar.position`.
- Height from config (default 32), margins configurable, `exclusiveZone: height`
  when not auto-hiding, `0` when hidden.
- Floating mode (`bar.floating`, default `true`): inset the bar 8–12 px from
  every anchored edge, use `Metrics.radiusPill`, and give it the `Pebble`
  `glass` material. Non-floating mode is a plain full-width strip with square
  corners for users who prefer it.
- Individual widgets are `Bubble`s inside the pill, not flat icons: 4–6 px gaps,
  no separators, hover lift from `Metrics.hoverLift`.
- Widgets from `bar.widgets.left|center|right` arrays; unknown names are skipped
  with one warning (not a crash) and surfaced in `Config.warnings`.
- Center slot stays visually centred regardless of left/right widths (use
  `Item` anchors at 50% width or a 3-column grid with equal stretch).
- Overflow: right slot hides the lowest-priority widgets when the content width
  exceeds available width (priority table in `WidgetRegistry.qml`), with a
  `+N` chip opening a `Menu`. Never squash widgets into overlap.
- Text uses `Theme` font tokens and `Metrics.fontScale`; no fixed pixel font
  sizes below `fontScale` handling.
- All colours from `Theme.c(...)`; the bar background opacity comes from
  `theme.transparency` config. The pill's tint/glow comes from `Metrics`, never
  a literal.
- Keyboard focus: bar is **not** focusable; popouts are `grabFocus` only while
  open. Escape closes.
- Clicks: left = primary action, right = context popout, middle = secondary
  action (tray). Scroll on volume/brightness widgets adjusts by 2% steps and
  triggers the OSD through `Osd.show(...)` if available (guarded — WS4 may not
  be merged yet; use a `Connections`-free `typeof`-safe call or a signal the
  shell routes later).

---

## 3. Widget behaviour

| Widget | Requirements |
| --- | --- |
| `Workspaces` | Bind to `Workspaces.list`; active/occupied/urgent styles; click switches; wheel cycles; hides entirely when `available` is false; per-monitor filtering when the service provides a monitor field, otherwise show all |
| `ActiveWindow` | Focused window title + app icon via `Workspaces.windows`; truncate with `Format.truncate`; hidden when empty; click toggles overview (guard if WS6 not merged) |
| `Clock` | `Time.timeStr`/`dateStr`, configurable format (`bar.clock.format`), click opens `ClockPopout` with a month grid and today highlight; second-precision only if the format contains seconds; `bar.clock.style` is `text` (default) or `dots` (`DotMatrixText`, 26–32 px dot size) — only one dot-matrix element may be visible per screen, so hide the background clock's dot variant when this is on |
| `Tray` | `Tray.items`; icon buttons; left = `activate(id, 1)`, right = `openMenu(id, window, x, y)` anchored at the item, middle = `activate(id, 2)`; overflow into `+N` menu; empty → widget hides |
| `Battery` | `Battery.available`; icon by percent/charging; percent text optional (`bar.battery.showPercent`); low/critical colour; click opens `BatteryPopout` with health/time/state; hidden on desktops |
| `Network` | `Network.available`; Wi-Fi signal icon / wired / offline; click opens `NetworkPopout` (WS5 fills the panel, WS3 ships a read-only summary) |
| `Volume` | `Audio.sink.volume`, `muted`; icon by level; click opens `VolumePopout` (slider + mute); wheel adjusts and calls `Osd` |
| `Media` | `Media.active`; hidden when no player; title/artist marquee-free truncation; click opens `MediaPopout`; no per-second position polling unless the popout is open |
| `Power` | `Power` menu trigger (WS7 owns the menu; WS3 calls `Session.open()` if available, else shows a `Menu` with lock/logout/reboot/shutdown calling `Power.*`) |
| `StatusIcons` | Bluetooth on/off, DND (`Notifications.dnd`), recording (`Recorder.recording`), idle inhibit (`Idle.inhibited`), lock state; each hidden when irrelevant; no placeholder icons |

Every widget exposes `implicitWidth` and a `tooltip` string. No widget reads
`Config` directly except through `WidgetRegistry` (pass config down as
properties) — keeps widgets testable.

---

## 4. Popouts

- Use `components/Popup.qml`. Anchored to the clicked widget, `anchorEdges`
  computed from bar position (top bar → popup below, bottom bar → above).
- One popout open per bar at a time; opening another closes the previous.
- `PopupAdjustment.All` so they never leave the screen.
- Content is lazy (`LazyLoader`) and only loads while visible.
- Popouts do not steal keyboard focus unless they contain a text field
  (tray menu, volume is fine without).
- Close on Escape, outside click, and screen change.
- Deep controls (Wi-Fi list, Bluetooth pairing, media seek) belong to WS5; WS3's
  popouts show the summary and a "Open control center" button that calls
  `ControlCenter.open()` if it exists (feature-detect, no hard dependency).

---

## 5. IPC and config

- `IpcHandler { target: "bar" }` with `toggle()`, `show()`, `hide()`.
  - `toggle()` hides all bars for the current session (persisted in
    `State.set("bar.hidden", …)`), `show()`/`hide()` explicit.
  - Functions must work before windows exist (guard `null`).
- Config keys used (already in contract): `bar.position`, `bar.height`,
  `bar.floating`, `bar.autoHide` (add via contract PR if truly needed),
  `bar.widgets.{left,center,right}`, `bar.clock.format`, `bar.clock.style`,
  `bar.battery.showPercent`, `bar.tray.hiddenItems`, `monitors.<name>.bar.*`.
- Adding a widget name = one `WidgetRegistry` entry + one file; document it in
  `shell/modules/bar/README.md`.

---

## 6. Behaviour details that reviewers will check

- Monitor hotplug: `Variants` model already handles it; no stale windows.
- Bar on the focused monitor has no special styling (keep it uniform).
- `exclusiveZone` updates when auto-hide toggles, without leaving gaps.
- With every service stub active (wave 2), the bar renders only Clock and Power
  and logs no errors.
- No `Component.onCompleted` chains that reorder widgets; layout is declarative.
- No per-frame bindings on `Time.seconds` in hidden widgets.

---

## 7. Tests

- `tests/tst_bar_layout.qml`: slot parsing (missing/unknown names), overflow
  priority, centre alignment math (pure helpers extracted to
  `BarLayout.js`/`.qml`), per-monitor merge via `Config.forScreen` mock.
- `tests/tst_bar_widgets.qml`: each widget instantiates offscreen with mock
  services, `implicitWidth > 0`, hides when `available: false`.
- Keep service mocks from WS1; add `MockTray` there if missing (test-only).

---

## 8. Constraints

- Do not edit `shell/shell.qml`, services, components, or other modules.
- Do not implement the control center or session menu — call their modules if
  present, hide the entry point otherwise.
- Do not add a second bar implementation behind a config flag; one code path.
- No `ShaderEffect` written by this workstream. Use `Pebble`/`Specular` from the
  UI kit for glass, rim, and glow; if the material needs a new parameter, request
  it in `components/` via a contract PR.
- No per-frame blur or animation of shadow/brightness.

---

## 9. Acceptance checklist

- [ ] One and two monitors, top and bottom, 100% and 150% scale.
- [ ] Floating glass pill renders with rim/specular at `quality: high` and with
      gradients at `quality: low`; no gap or exclusive-zone artifacts.
- [ ] Slots render exactly the configured widgets; unknown names warn once.
- [ ] Clock popup calendar is correct for the current month/locale.
- [ ] Tray menu opens at the icon and closes on outside click.
- [ ] Wheel on volume changes volume and shows OSD when WS4 is present.
- [ ] `qs ipc call bar toggle` hides/shows without leaving an exclusive zone.
- [ ] `make check` green; screenshots (both monitors, light/dark) attached.

---

## 10. Handoff report

`docs/SUBAGENT_PLAN.md` §9 plus: widget priority table, config keys consumed,
popout routing map, and the list of calls into other modules with their guards.
