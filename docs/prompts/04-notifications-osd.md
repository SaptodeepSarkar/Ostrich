# WS4 — Notifications and OSD

**Branch:** `feat/ws4-notifications` · **Worktree:** `../ostrich-ws4`
**Wave:** 2 · **Depends on:** WS1 merged · **Blocks:** WS3 unread badge, WS5 DND toggle
**Owns:** `shell/modules/notifications/`, `shell/modules/osd/`,
`shell/services/Notifications.qml` (replaces the stub)

---

## Mission

Own the `org.freedesktop.Notifications` name, show non-intrusive popups, keep a
searchable history, and provide the on-screen display for volume, brightness,
media, and keyboard layout. This module must never steal focus, never block the
GUI thread, and never lose a notification because a popup was closed.

Read `CONTRACTS.md` §3, §4, §7 and the Quickshell `NotificationServer` /
`Notification` / `NotificationAction` API (look it up before coding).

---

## 1. `services/Notifications.qml` (real implementation)

Replace the stub wholesale, keep the contract signature.

- One `NotificationServer`:
  - `actionsSupported: true`, `bodyMarkupSupported: true`,
    `bodyHyperlinksSupported: true`, `imageSupported: true`,
    `inlineReplySupported: true`, `persistenceSupported: true`,
    `keepOnReload: true`.
  - `onNotification(n)`: unless DND, set `n.tracked = true` and emit `received`
    with a plain snapshot; always append to history unless `n.transient`.
- Keep a **plain-object history** (do not retain `Notification` objects — they are
  destroyed after dismissal):
  `{ id, appName, appIcon, summary, body, urgency, image, actions:[{id,text}], time, read, hasInlineReply, replyPlaceholder }`.
- History persistence: `$STATE/notifications.json`, capped at 200 entries,
  atomic writes, debounced 1 s. Load on startup; mark everything read on load.
- API:
  - `list` newest first (live + history merged, deduplicated by id),
  - `dnd` persisted in `State` (`notifications.dnd`),
  - `unread` = unread history count,
  - `toggleDnd()`, `clear()`, `dismiss(id)`, `invokeAction(id, actionId)`,
  - `dismiss` on a live notification calls `n.dismiss()`; on a history-only entry
    just removes it,
  - `invokeAction` finds the live notification, matches `action.identifier`, calls
    `action.invoke()`; unknown id is a no-op with a debug log,
  - `markAllRead()`, `sendInlineReply(id, text)` (extra, contract-compatible).
- `IpcHandler { target: "notifications" }`: `toggleDnd()`, `dnd(bool)`,
  `clear()`, `open()`, `close()`.
- Do not log notification bodies at info level (privacy). Debug logs may include
  app name and id only.
- Never call `Process` in this service.

---

## 2. Popups (`modules/notifications/`)

```
Notifications.qml        # module root: per-screen popup windows, open()/close()
NotificationPopup.qml    # one card
NotificationStack.qml    # column layout + overflow
NotificationCenter.qml   # history panel (open()/close())
NotificationCard.qml     # shared card used by popups and center
HistoryModel.qml         # filtering/grouping helpers
```

Requirements:

- One `PanelWindow` per screen (or only the focused screen — choose focused,
  document it) anchored top-right with configurable margins, `exclusionMode:
  Ignore`, `focusable: false`, `color: "transparent"`, empty mask outside cards.
- Max 3 visible popups; older ones collapse into the center; "+N more" opens the
  center.
- Card: app icon, app name, summary (bold), body (plain text, `TextFormat.PlainText`
  unless markup is safe — strip unsupported tags), image thumbnail, timestamp,
  urgency styling (low/normal/critical), action buttons (max 3), inline reply
  field when `hasInlineReply` (focus only then), close button.
- Timeout: use `expireTimeout` (default 5 s, config override), pause on hover,
  never expire `critical`; `resident` notifications stay until dismissed.
- Animations: slide+fade 150 ms; instant when reduced motion is on. Closing one
  card reflows the stack without flicker.
- Click on body invokes the default action if one exists, else opens the center.
- Never take focus; clicking an action must not activate the window under it.

### Notification center

- Opens via `Notifications.open()`, bar unread indicator, or IPC.
- Sections: Today / Earlier, grouped by app with counts; search field; DND
  toggle; "Clear all".
- Per-item: dismiss, invoke action, copy body (`Quickshell.clipboardText`).
- Keyboard: Up/Down navigate, Enter invokes default action, Delete dismisses,
  Escape closes, typing focuses search.
- Virtualised list (`ListView` with `reuseItems`) — 200 entries must scroll at
  60 fps.
- Empty state uses `EmptyState`.

---

## 3. OSD (`modules/osd/`)

```
Osd.qml          # module root, per-screen overlay, show(kind, value), close()
OsdCard.qml      # icon + label + bar/value
LockKeys.qml     # optional caps/num indicator
```

- `PanelWindow` per screen, `WlrLayershell` with `WlrLayer.Overlay` (must appear
  above fullscreen), `focusable: false`, `exclusionMode: Ignore`, transparent,
  positioned bottom-centre above the bar (configurable offset).
- Kinds: `volume`, `mic`, `brightness`, `media`, `layout`, `caps`, `num`.
  `show(kind, value)` accepts `value` as number (0..1) or string (media title,
  layout name) — document the union in the file header.
- Coalesce bursts: a 50 ms timer merges rapid updates, then render once.
- Auto-hide after 1.5 s (media: 3 s) with fade; hover pauses; any new `show()`
  restarts the timer.
- Volume/brightness: icon changes at 0/33/66, muted state, numeric percentage,
  `ProgressBar`.
- Media: title + artist + play state icon, no album art fetching.
- Keyboard layout: listen to `Hyprland.rawEvent` (`activelayout>>…`) when
  `Workspaces.available`; otherwise skip. Never poll.
- Lock keys: read `/sys/class/leds/*::capslock/brightness` only if the glob
  exists, at 500 ms; hide the feature when absent. This is the only allowed
  polling in the module and must be documented.
- `IpcHandler { target: "osd" }`: `show(kind, value)`, `close()`.

---

## 4. Config keys

Already available: `notifications.{dnd,timeoutMs,position,history}`.
Add via contract PR if needed: `osd.position`, `osd.timeoutMs`,
`notifications.maxVisible`, `notifications.centerWidth`.

---

## 5. Tests

- `tests/tst_notifications.qml`: snapshot mapping (Notification → plain object),
  dedupe by id, DND suppresses `received` but keeps history, unread counting,
  history cap 200, invalid action id no-op, clear/markAllRead.
- `tests/tst_osd.qml`: kind validation, coalescing (two shows in <50 ms render
  once), timer restart, string vs numeric value, muted icon selection.
- Use `tests/mocks/MockNotifications.qml`; for the OSD, mock `Audio`/`Brightness`
  and assert visible state transitions with a test clock (`Qt.callLater` /
  short timers, no sleeps).
- Headless only.

---

## 6. Constraints

- No `pactl`/`notify-send` subprocesses; the server is in-process.
- Never call `Quickshell.clipboardText = …` with untrusted HTML.
- No notification body in logs above debug.
- Do not edit bar, services owned by others, or `shell.qml`.
- Feature-detect WS3/WS5/WS7 dependencies; the module must work alone.

---

## 7. Acceptance checklist

- [ ] `notify-send "hello" "world"` shows one popup and appears in the center.
- [ ] Action buttons invoke the right action; inline reply works with a client
      that supports it (e.g. a test script using `gdbus`).
- [ ] DND suppresses popups but keeps history; toggle persists across restart.
- [ ] Hover pauses timeout; critical notifications do not expire.
- [ ] History survives `qs kill` + restart (file-backed, capped).
- [ ] Volume/brightness/media/layout OSDs appear above fullscreen windows and
      never take focus.
- [ ] `make check` green; screenshots of popup, center, each OSD kind.

---

## 8. Handoff report

`docs/SUBAGENT_PLAN.md` §9 plus: history file schema, snapshot field map, OSD
kind table with value types, coalescing behaviour, and anything WS3/WS5 must call
(`Notifications.open`, `Osd.show`, …).
