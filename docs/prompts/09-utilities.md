# WS9 — Utilities

**Branch:** `feat/ws9-utilities` · **Worktree:** `../ostrich-ws9`
**Wave:** 3 · **Depends on:** WS1, WS3 merged · **Blocks:** nothing
**Owns:** `shell/modules/utilities/`, `shell/services/{Clipboard,Recorder}.qml`

---

## Mission

Ship the small tools that make a shell feel complete: clipboard history with
images and pinning, screenshot with a real region picker, screen recording,
emoji picker, the shell's toast renderer, idle inhibit / game mode, and a compact
dashboard (calendar, media, system stats, weather). All of them are
keyboard-reachable through the `utilities` module and IPC.

Read `CONTRACTS.md` §3, §4, §7, §10. Look up `WlrLayershell`, `ScreencopyView`,
`Mpris`, `SystemClock` before coding.

---

## 1. Utilities host (`modules/utilities/`)

```
Utilities.qml          # module root: open(kind)/close(), IPC, page router
UtilitiesPanel.qml     # shared overlay/panel shell
cards/
├── ClipboardCard.qml
├── EmojiCard.qml
├── RecorderCard.qml
├── DashboardCard.qml
├── IdleInhibitCard.qml
└── GameModeCard.qml
AreaPicker.qml
ToastHost.qml
```

- `Utilities.open(kind)` accepts `clipboard|emoji|record|dashboard|inhibit|game|calendar`;
  unknown kind opens the dashboard.
- Overlay: `WlrLayershell` on the focused screen, `WlrLayer.Overlay`,
  `keyboardFocus: Exclusive` while open (search fields need it), scrim click and
  Escape close. Panel ~720×520, centred, resizable only if it stays usable.
- Only one card loaded at a time (`LazyLoader`), state preserved per card in
  `State` (e.g. last query) but not scroll positions.
- IPC `clipboard`: `open()`, `clear()`. IPC `screenshot`: `region()`, `full()`.
  IPC `recorder`: `start(mode)`, `stop()`. (`utilities` itself has no IPC target
  in the contract — do not add one.)

---

## 2. `services/Clipboard.qml` (real)

- `entries`: `[{ id, text, image, time, pinned, kind }]`, newest first, capped at
  200 (pinned items exempt from eviction).
- Watch the Wayland clipboard with a long-running
  `Process { command: ["wl-paste", "--watch", "sh", "-c", "wl-paste --no-newline || true"] }`
  (the `sh -c` is required by `--watch`; it receives no user input, document it).
  Each completed line/chunk is a candidate; debounce 100 ms.
- Text only by default; image support behind `clipboard.images` config:
  on a watch event, if `wl-paste --list-types` includes `image/png`, save the
  image to `$CACHE/clipboard/<id>.png` and store the path (entries store paths,
  not bytes).
- Privacy: skip when the focused window class matches a denylist
  (`keepassxc`, `bitwarden`, `1password`, `gnome-keyring`, …) or when the
  selection advertises `x-kde-passwordManagerHint`; never log content.
- Persistence: `$STATE/clipboard.json` for text and pinned entries (paths for
  images), debounced 1 s, atomic. Load on start, drop entries whose image file is
  gone.
- API: `copy(id)` (sets `Quickshell.clipboardText` for text or `wl-copy` with
  image argv), `remove(id)`, `clear()` (keeps pinned unless `clear(true)`),
  `pin(id, bool)` (extra), `search(query)` is UI-side.
- Selecting an entry must not immediately re-add it as a new entry (guard by
  ignoring the next watch event with the same content/id).
- Clear on logout only if `clipboard.persist` is false.

---

## 3. `services/Recorder.qml` (real)

- `recording`, `path`, `elapsed` (seconds, updated only while recording by a 1 s
  timer), `mode` (`screen|region`), `start(mode)`, `stop()`, `toggle()`.
- Backend: `wf-recorder` if present; region mode takes a geometry string
  (`-g "x,y wxh"`), screen mode records the focused output
  (`-o <output>` from Hyprland monitor name when available).
- Output: `Paths.recordingsdir + "/Ostrich-YYYYMMDD-HHMMSS.mp4"`; create the dir.
- Start: refuse if already recording, check the binary once (`command -v` via
  `Process` or `Quickshell.env` + PATH scan), emit `failed(reason)` (extra).
- Stop: send `SIGINT` (`Process.signal(2)`) for a clean MP4, wait ≤ 5 s, then
  report path. Never leave a zombie.
- Optional audio (`recorder.audio`, default off) adds `--audio` with the default
  sink monitor; document the requirement.
- On completion: `Toast.show("Recording saved …", "success")` and a notification
  if WS4 is present (feature-detect).

---

## 4. Cards

### Clipboard

- Search field filters text live (fuzzy or substring; substring is fine here),
  image entries show thumbnails (`Image` with `sourceSize`).
- Row actions: Enter copies and closes (config `clipboard.closeOnCopy`),
  Delete removes, Ctrl+P pins, Ctrl+Shift+Delete clears all with confirmation.
- Keyboard: Up/Down/PageUp/PageDown, Home/End, no mouse required.
- Pinned section first, then recents grouped by day.
- Empty state with the exact `wl-clipboard` install hint.

### Emoji picker

- Data source order: `/usr/share/unicode/emoji/emoji-test.txt`, then
  `$XDG_DATA_HOME/ostrich/emojis.txt`, then a bundled fallback list
  (`modules/utilities/data/emojis.json`, ≥ 300 common entries with names and
  groups, authored for Ostrich).
- Search by name/keyword, category tabs Recent / Smileys / People / Nature /
  Food / Travel / Objects / Symbols / Flags, recents in `State` (cap 40).
- Enter copies the emoji; Shift+Enter inserts into the previously focused window?
  (Not possible reliably on Wayland — document that it copies only.)
- Virtualised grid; no 3000-item `Repeater` at once.

### Recorder

- Start/stop button, elapsed time, mode selector, output directory (opens in file
  manager via `Qt.openUrlExternally`), last recordings list (5 newest, from the
  recordings dir).
- Shows the exact error when `wf-recorder` is missing.

### Dashboard

- Calendar: month grid from `Time`, today highlighted, week numbers, arrow
  navigation, optional ICS read-only events from `dashboard.icsPath` (parse
  `DTSTART`/`SUMMARY` for the visible month; tolerate malformed files).
- Media: compact now-playing with transport (reuse `Media` service; no seek).
- Performance: CPU (`/proc/stat` delta), memory (`/proc/meminfo`), disk
  (`df -h` argv for the configured mounts), temperature (`sensors -j` if
  installed). Sample every 2 s **only while the dashboard is visible**.
- Weather: reuse `Weather.current`/`forecast` (no network code here).
- Battery + uptime row.
- No charts library; simple bars/sparklines with `Canvas` or rectangles.

### Idle inhibit / Game mode

- Toggle `Idle.inhibit("user request")` / `uninhibit()`; show current inhibitors
  from `Idle` if exposed.
- Game mode: enable idle inhibit, DND (`Notifications.toggleDnd` if present),
  and an optional `gamemode` process (`gamemoderun` is per-app; here just set the
  shell flags and document the scope). Off restores previous DND state.

### Toasts

- `ToastHost.qml` renders `Toast.items` as stacked cards bottom-right on the
  focused screen, `WlrLayer.Overlay`, never focusable, auto-dismiss handled by
  the service, hover pauses dismissal (add `pause(id)`/`resume(id)` to the Toast
  service via a contract PR).
- Kinds: info/warn/error/success with icon + accent colour; max 3 visible.

---

## 5. Screenshot and area picker

- `AreaPicker.qml`: full-screen overlay per screen, dimmed background, drag a
  rectangle, live dimensions, Enter confirms, Escape cancels, arrow keys nudge
  the last selection by 1 px (Shift = 10 px).
- On confirm: capture with `grim -g "<x>,<y> <w>x<h>" <tmp.png>` (argv), copy to
  clipboard (`wl-copy` reading the file via stdin or `wl-copy < file` with
  redirection — use a `Process` with `stdin` file if supported, else
  `wl-copy` + `write` from the loaded bytes), save to
  `$PICTURES/Screenshots/Screenshot-<timestamp>.png`, toast the path, optional
  notification.
- `full()` captures the focused monitor (`grim -o <output>`), `region()` opens
  the picker, `window()` (extra) captures the focused toplevel via
  `ScreencopyView` if available, otherwise reports unsupported.
- Multi-monitor: the picker spans all screens with one overlay per screen and a
  shared selection state (absolute coordinates), or restrict to the focused
  screen and document it — pick one and be consistent.
- Never block the GUI thread while writing/copying; show a spinner toast.

---

## 6. Config keys

Add via contract PR:

```json
"clipboard": { "images": true, "persist": true, "closeOnCopy": true, "denylist": [] },
"recorder": { "audio": false, "directory": "" },
"dashboard": { "icsPath": "", "mounts": ["/"] },
"utilities": { "panelWidth": 720 }
```

Defaults only in `config/default.json`.

---

## 7. Tests

- `tests/tst_clipboard.qml`: dedupe on re-copy, cap 200 with pinned exemption,
  privacy denylist, persistence round-trip, image path pruning.
- `tests/tst_recorder.qml`: start guard, argv construction, stop signal sequence,
  failure signal, elapsed timer only while recording (mock process).
- `tests/tst_emoji.qml`: parser for `emoji-test.txt`, fallback list loads, recent
  cap, search matching.
- `tests/tst_dashboard.qml`: `/proc/stat` delta math, memory parse, ICS month
  filter, malformed ICS tolerated.
- `tests/tst_area_picker.qml`: drag→rect math, keyboard nudge, cancel, absolute
  coordinates across two mock screens.
- No real `grim`/`wf-recorder`/`wl-paste` in tests; mock the process layer.

---

## 8. Constraints

- Clipboard content is sensitive: no logging, no crash dumps, no network.
- Every external tool call: argv list, timeout, missing-binary path.
- Region geometry must be validated (positive width/height, within screen
  bounds) before being passed to `grim`.
- Do not edit shared services or other modules; `Clipboard.qml` and
  `Recorder.qml` are yours.
- No image annotation, OCR, or cloud features (post-v1).

---

## 9. Acceptance checklist

- [ ] Copy text in any app → appears in history; Enter copies it back.
- [ ] Images work when enabled; password-manager copies are ignored.
- [ ] Region screenshot: drag, confirm, file saved, clipboard set, toast shown.
- [ ] Full screenshot works on the focused monitor.
- [ ] Recording starts/stops cleanly, file plays, no zombie process.
- [ ] Emoji search + recents work offline.
- [ ] Dashboard stats update only while visible; ICS errors don't break it.
- [ ] Inhibit and game mode toggle shell behaviour; state is visible in the bar.
- [ ] Toasts stack, pause on hover, never steal focus.
- [ ] `make check` green; screenshots/recording of each card.

---

## 10. Handoff report

`docs/SUBAGENT_PLAN.md` §9 plus: clipboard entry schema, privacy denylist
handling, tool dependencies, capture coordinate model, and contract amendments
(`Toast.pause`, `Clipboard.pin`, `Recorder.failed`).
