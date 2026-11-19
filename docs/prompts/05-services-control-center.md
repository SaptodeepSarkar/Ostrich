# WS5 — System services and control center

**Branch:** `feat/ws5-services` · **Worktree:** `../ostrich-ws5`
**Wave:** 3 · **Depends on:** WS1, WS3 merged · **Blocks:** WS8
**Owns:** `shell/modules/controlcenter/`, `shell/services/{Audio,Bluetooth,Network,Media,Tray,Brightness,Weather}.qml`

---

## Mission

Turn the service stubs into real, reactive adapters over Quickshell's system
services, and build the control center: one popup where a user can toggle
Wi-Fi/Bluetooth/DND, change volume/mic/brightness, pick a network, connect a
Bluetooth device, control media, and see battery/power state.

Ownership note: `Power.qml` (profiles, lock/suspend/reboot) is **WS7's**. Call it
if present, feature-detect if not; do not edit it. `Notifications.qml` is WS4's.

Read `CONTRACTS.md` §4, §5, §7, §10 and look up every Quickshell type before
using it (`Pipewire`, `PwNode`, `PwNodeAudio`, `Bluetooth`, `Networking`,
`WifiNetwork`, `Mpris`, `SystemTray`, `PowerProfiles`).

---

## 1. Services

All services keep the exact contract signature, add `available` where the
contract has it, degrade silently, and log once at startup.

### `Audio.qml`

- Use the `Pipewire` singleton. Bind default sink/source nodes with
  `PwObjectTracker` inside the service (required for `audio.volume` to be valid).
- `sink`/`source` adapters: `{ id, name, description, volume, muted, isDefault }`.
- `sinks`/`sources`: every non-stream node of the matching direction; hide
  `isStream` nodes.
- `streams`: `isStream && audio` playback nodes → `{ id, name, appName, volume, muted }`,
  name from `properties["application.name"]` fallback to `description`.
- `setVolume(v)`: clamp 0..1, write `sink.audio.volume`; keep the last non-zero
  value so `toggleMute` + unmute can restore it if the backend reports 0.
- `setStreamVolume(id, v)`, `toggleMute()`, `toggleStreamMute(id)` (extra),
  `setDefaultSink(id)` via `Pipewire.preferredDefaultAudioSink` (look up the node
  by id), same for source.
- Mic mute helper `toggleSourceMute()` (extra) for the control center.
- No `pactl`/`wpctl`; no polling; react to the object model.

### `Bluetooth.qml`

- `Bluetooth.defaultAdapter` for `enabled`, `discovering`, `available`.
- `devices`: union of adapter devices, mapped to
  `{ address, name, connected, paired, trusted, battery, icon, state }`.
- `toggle()` sets `adapter.enabled`; `scan()` sets `discovering` true for 20 s
  then false (single `Timer`, not polling); `pair/connect/disconnect/forget`
  call the corresponding device methods.
- Surface pairing errors: listen to device `state` changes and emit
  `error(address, message)` (extra signal) for the UI toast.
- Hide when no adapter.

### `Network.qml`

- `Networking.wifiEnabled`, `connectivity` → `"none"|"limited"|"portal"|"full"|"unknown"`.
- `devices` → Wi-Fi devices; `networks` from `WifiNetwork` entries:
  `{ ssid, strength, secured, active, known }`.
- `ssid` = connected network name; `signal` = 0..100 from `signalStrength`.
- `scan()` sets the device's scanning on for 15 s (timer), `connect(ssid, psk)`
  → `connectWithPsk` when a psk is given, else `connect()`; `disconnect()` on the
  active network.
- `toggleWifi()` writes `Networking.wifiEnabled`.
- Listen to `connectionFailed(reason)` and expose
  `lastError` (extra) for the UI (wrong password vs. no secrets).
- Wired-only machines: `available` true, `wifiEnabled` false, empty network list.

### `Media.qml`

- `Mpris.players` → `players` `[{ id, name, identity, playing }]`.
- `active`: chosen by `State.get("media.active", "")`, else the first playing
  player, else the first; falls back gracefully when a player disappears.
- Adapter: `{ title, artist, album, artUrl, playing, position, length, canSeek,
  canGoNext, canGoPrevious, playerId }`.
- `play/pause/toggle/next/previous/seek(position)` forward to the active player,
  guarded by `canControl`/`canSeek`; never throw when the player is gone.
- Do **not** run a position timer; the UI reads `position` and extrapolates
  locally while playing, or refreshes when the popup opens.

### `Tray.qml`

- `SystemTray.items` → `{ id, icon, title, tooltip, hasMenu, onlyMenu }`.
- `activate(id, button)`: 1 = `activate()`, 2 = `secondaryActivate()`,
  3 = open menu, scroll handled by `scroll(id, delta)`.
- `openMenu(id, parentWindow, x, y)` calls
  `item.display(parentWindow, x, y)`; the bar passes its window object. The
  contract already includes `parentWindow` (kept in sync with
  `docs/CONTRACTS.md` §4).
- `icon` is already an image source or icon name; document which.

### `Brightness.qml`

- Prefer `Brightness` from `Quickshell.Services.UPower`? Check what exists
  (`UPower` exposes display device brightness on some systems). If unavailable,
  fall back to `brightnessctl -m` through `Process` (argv, parse `%`), read on
  start and after each write, debounce writes 80 ms.
- `available: false` when no backlight and no `brightnessctl`.
- `set(v)` clamps 0.01..1, `increase/decrease(step)` use the same path.
- Never block: writes are async; optimistic property update, reconcile from the
  next read.

### `Weather.qml`

- Open-Meteo (`https://api.open-meteo.com/v1/forecast`) via `XMLHttpRequest` or
  `Process` + `curl`? Use `XMLHttpRequest` (pure QML, async, no extra process).
- Location: `services.weather.location` = `"auto"` (IP-based endpoint
  `https://ipapi.co/json/` or Open-Meteo geocoding with a configured city),
  or `"lat,lon"`.
- Cache in `$CACHE/weather.json` for 15 min; refresh on open and every 30 min
  only when `enabled`; no polling when disabled.
- Adapter: `current { temp, code, description, icon }`, `forecast` 5 days.
- Map WMO codes → description + icon name (own table, not copied).
- Offline: `enabled` stays true, `current` keeps last cache, `lastError` set.

---

## 2. Control center

```
modules/controlcenter/
├── ControlCenter.qml      # module root: scrim + drawer, open/close/toggle, IPC
├── Header.qml             # avatar/host/time, settings + power buttons
├── ToggleGrid.qml         # Wi-Fi, Bluetooth, DND, night light (hidden), idle inhibit
├── Sliders.qml            # volume, mic, brightness
├── MediaCard.qml
├── BatteryCard.qml
├── NetworkList.qml
├── WifiDialog.qml
├── BluetoothList.qml
├── ProfileSelector.qml
└── Footer.qml
```

Behaviour:

- `WlrLayershell` overlay scrim (click closes) + right-side panel, full height,
  width ~380, `exclusiveZone: 0`, `focusable: true` only while open,
  `WlrLayer.Overlay`, per focused screen (not every screen — document it).
- Open/close animation: slide 200 ms + fade; instant with reduced motion.
- Escape closes; focus returns to the previously focused window (layer shell
  handles it; verify).
- `open()`, `close()`, `toggle()`, `IpcHandler { target: "controlcenter" }`.
- Toggles reflect real state and are disabled (not hidden) when unavailable,
  with a tooltip explaining why.
- Sliders: drag updates optimistically and debounces service writes (volume
  60 ms, brightness 80 ms); wheel works; icons mute/unmute on click.
- Network list: sorted connected → known → by signal; lock icon for secured;
  click known → connect, unknown → `WifiDialog`; wrong password shows inline
  error and keeps the dialog open; "Rescan" button with spinner.
- Wi-Fi password field: `echoMode: TextInput.Password`, never logged, cleared on
  close, not persisted by us.
- Bluetooth list: connected first, battery percent when available, pair/connect
  spinner from `state`, forget with confirmation, error toast on failure.
- Media card: art, title/artist, transport buttons, seek slider only when
  `canSeek`; hidden when no player.
- Battery: percent, state, time remaining, health; click opens the bar's battery
  popout if available, else shows details inline.
- Power profile selector: segmented control from `Power.profiles`; hidden when
  `Power.profiles` is empty.
- Footer: "Settings" (`Settings.open("appearance")` if present), "Lock"
  (`Power.lock()`), "Power" (`Session.open()` if present, else `Power` menu).
- Every dependency on WS3/WS7/WS8 is feature-detected via `LazyLoader`/`typeof`
  guards — the control center must work when only WS1+WS5 are merged.

---

## 3. Config keys

Existing: `apps.*`, `services.weather.*`, `monitors.<name>.modules.controlCenter`.
Add via contract PR if needed: `controlcenter.width`, `controlcenter.toggles`
(order/visibility list), `services.weather.units`.

Read keys through `Config.value`, never hardcode defaults in two places.

---

## 4. Tests

- `tests/tst_audio_mapping.qml`: node → adapter mapping, stream filtering, volume
  clamp, mute restore. Use a fake node object with the same shape (no PipeWire
  daemon).
- `tests/tst_network_mapping.qml`: connectivity enum mapping, sorting, secured
  flags, error text mapping.
- `tests/tst_media_selection.qml`: active-player selection, disappearance,
  canSeek guards.
- `tests/tst_controlcenter.qml`: toggle disabled states, Wi-Fi dialog validation
  (empty password, wrong password signal), open/close state machine.
- Pure mapping logic must live in small JS helpers or `QtObject` functions so it
  can be tested without D-Bus.

---

## 5. Constraints

- No `nmcli`, `bluetoothctl`, `pactl`, `playerctl` unless a type genuinely does
  not exist; if you must, argv only, timeout, failure UI.
- Never log passwords, PSKs, or SSIDs at info level.
- No focus stealing from the control center scrim beyond its own lifetime.
- Do not edit bar/notifications/lock modules or shared services.

---

## 6. Acceptance checklist

- [ ] Volume slider changes the real sink; mute survives a shell reload.
- [ ] Per-app stream volume works for a playing app.
- [ ] Wi-Fi scan, connect with password, wrong-password error, disconnect.
- [ ] Bluetooth toggle, scan, pair, connect, forget, battery shown.
- [ ] Media controls work with at least one MPRIS player; card hides with none.
- [ ] Brightness works on a laptop backlight; hidden on desktop.
- [ ] Tray menu opens at the widget (with the amended contract).
- [ ] Weather caches and degrades offline.
- [ ] Control center opens/closes by IPC, Escape, and scrim click.
- [ ] `make check` green; screenshots of every section, dark/light.

---

## 7. Handoff report

`docs/SUBAGENT_PLAN.md` §9 plus: extra signals/properties added, contract
amendments (tray menu), permission/polkit needs, and a table of
"capability → Quickshell type → fallback".
