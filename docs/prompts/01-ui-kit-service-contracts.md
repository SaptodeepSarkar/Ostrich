# WS1 — UI kit + service contracts

**Branch:** `feat/ws1-ui-kit` · **Worktree:** `../ostrich-ws1`
**Wave:** 1 · **Depends on:** WS0 merged · **Blocks:** WS3–WS9
**Owns:** `shell/components/`, `shell/utils/`, `shell/services/*.qml` (stubs),
`tests/mocks/`

---

## Mission

Give every other workstream a complete, themed, keyboard-usable component kit and
a complete set of service singletons whose signatures match `CONTRACTS.md` §4 —
even where the backend is not wired yet. Nothing in the shell should need to
invent a button, a popup, a slider, or a service shape after this PR.

If WS0's services are real (`Paths`, `Config`, `State`, `Theme`, `Wallpaper`,
`Time`, `Toast`), do **not** modify them. You own the remaining files only.

---

## 1. UI kit (`shell/components/`)

Every component:

- is theme-token driven: colours via `Theme.c("…")`, radii/spacing via
  `Theme.metric("radius")`-style helpers you add to `utils/Metrics.qml`
  (values also exposed as `Theme` aliases if WS0 allows; otherwise keep them in
  `Metrics`),
- uses `implicitWidth`/`implicitHeight`, works inside layouts,
- exposes `enabled`, `focus` where interactive, and `Accessible.name`/`role`
  where Qt supports it,
- animates with `Behavior` on colour/opacity only, honours
  `Theme.reducedMotion` (WS0 adds the property; if missing, add it via a
  contract PR),
- has no `Config` reads,
- ships with a short doc comment.

Required files and APIs (see `CONTRACTS.md` §10):

| File | Extra requirements |
| --- | --- |
| `Button.qml` | `text`, `icon`, `enabled`, `accent`, `onClicked`; hover/press/focus states; `variant` (`filled`/`tonal`/`text`) |
| `IconButton.qml` | `icon`, `size` (default 20), `enabled`, `tooltip`, `onClicked`; square hit area ≥ 28 px |
| `Icon.qml` | `name`, `size`, `color`; wraps `IconImage`; falls back to a placeholder glyph when the icon is missing |
| `Slider.qml` | `value` 0..1, `orientation`, `enabled`, `onMoved(real)`; drag + wheel + arrow keys; step from `stepSize` |
| `Switch.qml` | `checked`, `enabled`, `onToggled(bool)`; Space/Enter toggles |
| `TextField.qml` | `text`, `placeholder`, `onAccepted`, `onTextChanged`; selection, paste, clear button optional |
| `Popup.qml` | `visible`, `anchorItem`, `anchorEdges`, `onClosed`; `PopupWindow` with `anchor.adjustment: PopupAdjustment.All`, `grabFocus` prop, close on Escape/click-outside |
| `Tooltip.qml` | `text`, `anchorItem`, `visible`; delay 400 ms, no focus |
| `Menu.qml` | `items` (`[{label, icon, enabled, separator, action}]`), `open(x, y)`, `close()`, `onTriggered(item)`, keyboard navigation |
| `MenuItem.qml` | row renderer used by `Menu.qml` |
| `ScrollView.qml` | Flickable + visible scrollbar; default content property; `contentHeight` |
| `ProgressRing.qml` | `value` 0..1, `thickness`, `indeterminate` |
| `ProgressBar.qml` | linear, same value semantics |
| `Surface.qml` | `radius`, `elevation`, default content; the only component allowed to hardcode elevation → shadow mapping |
| `Spinner.qml` | `running`, `size`; Canvas or rotating arc |
| `Separator.qml` | horizontal/vertical |
| `Chip.qml` | compact toggle/filter chip (`checked`, `text`, `icon`) |
| `ListRow.qml` | `title`, `subtitle`, `icon`, `trailing`, `selected`, `onActivated` — used by launcher, settings, clipboard |
| `EmptyState.qml` | `icon`, `title`, `description` |

Naming collisions: `Button`, `Slider`, `Switch`, `TextField`, `Menu`,
`ScrollView` shadow QtQuick.Controls types. Inside these files import Controls
qualified (`import QtQuick.Controls as Controls`) or avoid it entirely by using
QtQuick primitives. Document the rule in `shell/components/README.md`.

Also add `shell/components/qmldir` listing every component (directory listing, no
`module` line) so `qmllint -I shell` resolves them predictably.

**Demo page:** `shell/components/KitDemo.qml` — a `FloatingWindow` (not started
by default) showing every component in dark and light. It is the visual
regression target for reviewers. Gate it behind `OSTRICH_KIT_DEMO=1` in
`shell.qml` via a one-line `LazyLoader` added by WS0's owner — request that
change in the PR instead of editing `shell.qml` yourself.

---

## 2. Utils (`shell/utils/`)

Pure QML/JS, no singletons, no I/O:

| File | API |
| --- | --- |
| `Fuzzy.qml` | `score(query, text): real`, `filter(query, items, key): list`; stable, case/diacritic-insensitive, initials bonus |
| `Format.qml` | `bytes(n)`, `percent(v, digits)`, `duration(seconds)`, `relativeTime(date)`, `truncate(s, n)` |
| `Strings.qml` | `capitalize`, `titleCase`, `initials`, `stripMarkup`, `safeHtml` |
| `Icons.qml` | `forApp(desktopEntry)`, `forCategory(name)`, `fallback(name)`; wraps `Quickshell.iconPath` |
| `Metrics.qml` | `radius`, `spacing`, `padding`, `fontScale`, `iconSize` — reads `Config` for scale; the only util allowed to read config |
| `Colors.qml` | `alpha(color, a)`, `mix(a, b, t)`, `luminance(color)`, `contrast(a, b)`, `onColor(background)` |
| `Anim.qml` | `fast`, `normal`, `slow`, `easing`; zero durations when reduced motion is on |
| `qmlutils.js` | optional shared JS helpers used by the QML files above |

Rules: deterministic, no `Math.random()` in pure functions, no locale-dependent
output except through `Qt.locale()`.

---

## 3. Service stubs

Create every singleton from `CONTRACTS.md` §4 that WS0 did not create, with the
exact properties/functions/signals. Stubs must be **honest**:

- `available: false` (and `enabled: false` where relevant) when there is no
  backend;
- empty lists, `0`, `""` defaults — never fake device data;
- one `console.info("[ostrich:<svc>] stub active")` per singleton, not per read;
- functions are no-ops that log at debug level and return a sensible value
  (`false`/`0`/`undefined`), never throw.

Files: `Battery.qml`, `Audio.qml`, `Bluetooth.qml`, `Network.qml`, `Media.qml`,
`Tray.qml`, `Notifications.qml`, `Power.qml`, `Workspaces.qml`,
`Brightness.qml`, `Weather.qml`, `Idle.qml`, `Clipboard.qml`, `Recorder.qml`.

Each file must carry a header comment:

```qml
// STUB — owned by WS<N>. See docs/prompts/<file>. Replace this file wholesale;
// keep the signatures from docs/CONTRACTS.md §4.
```

Add all of them to `shell/services/qmldir`.

### 3.1 Reference implementation for one stub

`Notifications.qml` stub (WS4 replaces it):

```qml
pragma Singleton
import Quickshell
import QtQuick

Singleton {
    id: root
    readonly property var list: []
    readonly property bool dnd: false
    readonly property int unread: 0
    signal received

    function toggleDnd(): void {}
    function clear(): void {}
    function dismiss(id): void {}
    function invokeAction(id, action): void {}
}
```

### 3.2 Behaviour that is safe to implement now

- `Battery`: thresholds from `Config.value("services.battery.low", 15)` and
  `critical`; emit `low`/`critical` only from a future real implementation —
  stub emits nothing.
- `Workspaces`: `available: false` unless `Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE")`
  is set; still return `[]`.
- `Tray`: `items: []`, `activate`/`openMenu` no-ops.
- `Brightness`: `available: false`, `value: 0`.

Do not add D-Bus, `Process`, or polling to stubs.

---

## 4. Test mocks (`tests/mocks/`)

Provide mock singletons with the same public shape for headless UI tests:

- `MockAudio.qml`, `MockBattery.qml`, `MockWorkspaces.qml`,
  `MockNotifications.qml`, `MockMedia.qml`, `MockNetwork.qml`,
  `MockTheme.qml`.

They expose settable properties with realistic sample data and are used by
`tests/tst_*.qml`. Document how to swap them (component under test takes the
service as a property or the test sets `Theme.colours` directly). Do not modify
production files to make mocks work.

Add `tests/mocks/qmldir` listing them.

---

## 5. Tests

- `tests/tst_fuzzy.qml`: ordering, initials, empty query, unicode, no match.
- `tests/tst_format.qml`: bytes/percent/duration/relative time boundaries.
- `tests/tst_colors.qml`: alpha/mix/contrast/`onColor` accessibility
  (contrast ≥ 4.5 for text tokens against their containers where the pair is
  defined).
- `tests/tst_components.qml`: instantiate every component offscreen, set each
  property, emit each signal; assert `implicitWidth > 0`.
- Keep tests deterministic (no timers > 50 ms, no animations asserted).

`make test` must pass; add files only under `tests/`.

---

## 6. Constraints

- No feature UI, no module directories, no `shell.qml` edits.
- No new config keys without a contract PR (add them to `config/default.json`
  only if the contract already lists them).
- Do not import `Quickshell.Services.*` in the UI kit.
- `Theme.c()` is the only colour source. No `"#fff"`, no `Qt.rgba` literals in
  feature components.
- Keyboard and focus behavior is part of the API, not a later polish task.

---

## 7. Acceptance checklist

- [ ] Every component in §1 exists with the documented API and renders offscreen.
- [ ] `KitDemo.qml` shows every component without errors in dark and light.
- [ ] All 14 stubs exist, are listed in `qmldir`, and log exactly once.
- [ ] `qmllint` resolves `Theme.*`, `Config.*`, and every component from any
      module directory.
- [ ] `tests/mocks/*` match the real signatures (diff the property lists).
- [ ] `make check` green.
- [ ] Screenshot of `KitDemo` in both modes attached to the PR.

---

## 8. Handoff report

Use `docs/SUBAGENT_PLAN.md` §9. Additionally list:

- any component API you had to extend (and the contract PR),
- the exact stub file → owning workstream table,
- how mocks are selected in tests,
- the keyboard/focus matrix (Tab order expectations).
