# Ostrich — Product Requirements Document

| Field | Value |
| --- | --- |
| Product | Ostrich — QML / Quickshell desktop shell ("rice") |
| Version | 0.1.0 (draft) |
| Status | Scoping — no implementation yet |
| Platform | Arch Linux, Wayland, Qt 6 / Quickshell |
| Primary compositor | Hyprland (Niri/Sway as secondary targets) |
| Related docs | [AGENTS.md](AGENTS.md), [README.md](README.md), [docs/CONTRACTS.md](docs/CONTRACTS.md), [docs/DESIGN.md](docs/DESIGN.md), [docs/SUBAGENT_PLAN.md](docs/SUBAGENT_PLAN.md) |

---

## 1. Vision

Ostrich is a fast, cohesive, keyboard-first desktop shell for Arch Linux built
with QML and [Quickshell](https://quickshell.org/). It replaces the ad-hoc mix of
bars, launchers, notification daemons, and widget scripts common in Wayland
"rices" with one integrated, themeable shell that behaves consistently across
monitors and stores all of its state in a documented configuration format.

Ostrich also ships the two surfaces that bracket a session — a **greetd login
screen** and a **lock screen** — so login, unlock, and the shell share one visual
language: the glossy, inflated "Pebble" material defined in
[docs/DESIGN.md](docs/DESIGN.md). The target aesthetic is a bubbly 3D glass pebble
floating on a black canvas, with a single palette accent, not flat Material.

Success means a user can install Ostrich on a fresh Arch + Hyprland system, get a
complete desktop (bar, launcher, notifications, media/volume/battery controls,
wallpaper and theme management, power menu), and theme every part — including
GTK/Qt/terminal/browser applications — from one place, without editing files by
hand.

### Goals

1. One process tree (Quickshell) provides the whole desktop shell.
2. Every visual element is driven by theme tokens; light/dark and wallpaper
   palettes propagate to both shell and applications.
3. Configuration is declarative, validated, and reloadable without logging out.
4. Keyboard-first: every panel, popup, and action is reachable by shortcut.
5. Low overhead: the shell must feel instant and stay out of the way.
6. One visual identity: login, lock, shell, and settings share the "Pebble"
   material, tokens, and components; no surface looks bolted on.

### Non-goals

- A full desktop environment (no file manager, terminal, text editor, or office
  suite).
- A compositor. Ostrich targets existing Wayland compositors and never takes over
  window management beyond optional helpers.
- Distribution-agnostic packaging in v1. Arch Linux first.

---

## 2. Target environment

| Item | Requirement |
| --- | --- |
| OS | Arch Linux (rolling), systemd |
| Session | Wayland |
| Compositor | Hyprland (primary), Niri and Sway (best effort) |
| Runtime | Quickshell (latest stable; minimum version pinned in `docs/`) |
| Toolkit | Qt 6.8+ (Arch currently ships 6.12) |
| Audio | PipeWire + WirePlumber |
| Bluetooth | BlueZ (`bluetoothd`) |
| Network | NetworkManager |
| Power | UPower + `power-profiles-daemon` |
| Login (optional) | `greetd` + `cage` running the Ostrich greeter |
| Wallpaper | `swww` or `hyprpaper` (adapter) |
| Fonts/Icons | configurable; sensible defaults shipped |
| GPU | Any Wayland-capable GPU; effects degrade gracefully |

### Personas

- **P1 — The ricing enthusiast**: wants deep theming, per-app color schemes, and
  a shell that looks intentional on every monitor.
- **P2 — The keyboard-driven developer**: lives in the launcher, workspace
  switcher, clipboard, and window controls; rarely touches a mouse.
- **P3 — The laptop user**: needs battery, brightness, power profiles, lid/idle
  behavior, and a reliable lock screen.
- **P4 — The newcomer**: expects a working default configuration and a settings
  app instead of hand-editing QML.

---

## 3. Architecture

```
┌──────────────────────────── Quickshell process ────────────────────────────┐
│  ShellRoot (shell/shell.qml)                                               │
│                                                                            │
│  ┌────────────── UI layer ──────────────┐   ┌────── Services layer ──────┐ │
│  │ Bar · Dock · Launcher · Notifications│   │ Pipewire  Bluetooth  UPower│ │
│  │ OSD · Control Center · Settings      │◄──│ Networking Mpris  Tray     │ │
│  │ Lock · Power · Overview · Popups     │   │ Hyprland  Notifications    │ │
│  └──────────────────────────────────────┘   │ PowerProfiles  Time/Date   │ │
│                    ▲                        └────────────────────────────┘ │
│                    │                                  ▲                    │
│  ┌─────────────────┴──────────────────┐   ┌───────────┴──────────────────┐ │
│  │ Theme engine + design tokens       │   │ Config store (JSON/QML)      │ │
│  │ palette, typography, spacing,      │   │ validated, hot-reloadable    │ │
│  │ icon set, per-app templates        │   └──────────────────────────────┘ │
│  └────────────────────────────────────┘                                    │
│                                                                            │
│  IPC (qs ipc) · logging · diagnostics · state persistence                  │
└────────────────────────────────────────────────────────────────────────────┘

Before login (optional, separate process tree):
greetd (root) → cage (Wayland) → Quickshell greeter config (user `greeter`)
                                 → Quickshell.Services.Greetd → user session
```

The greeter is intentionally **not** part of the shell process tree: it must run
before the user session exists and must never depend on user services. It shares
only QML components and the palette format with the shell. See `CONTRACTS.md`
§3.1 and `DESIGN.md` §7.

Design rules:

- **Single source of truth**: services own state; UI binds to it. No duplicated
  polling.
- **Compositor adapter layer**: Hyprland IPC is the reference implementation;
  other compositors implement the same interface or degrade with a clear notice.
- **Config over code**: user preferences live in versioned config files, not in
  QML edits.
- **Theme tokens over literals**: components consume semantic tokens
  (`surface`, `onSurface`, `accent`, `warning`, ...), never raw hex values.

---

## 4. Component catalog

Priority: **P0** = required for a usable v1, **P1** = expected for v1, **P2** =
post-v1. IDs are stable references for issues, commits, and tests.

### 4.1 Core

| ID | Component | Priority | Requirements |
| --- | --- | --- | --- |
| CORE-01 | Shell runtime | P0 | Single `ShellRoot` entry point; survives QML reload without killing persistent state; clean shutdown; single-instance guard (`qs -n` semantics). |
| CORE-02 | Configuration system | P0 | Declarative config with schema/defaults/migration; validation with actionable errors; hot reload; per-host overrides; documented in `docs/`. |
| CORE-03 | IPC and scripting API | P0 | `IpcHandler` targets for launcher, panels, theme, OSD, media, power; documented command surface usable from keybinds and scripts. |
| CORE-04 | Multi-monitor and scaling | P0 | Per-monitor instances via `Variants`; independent bars/workspaces; fractional scaling; survives monitor hotplug; remembers per-monitor settings. |
| CORE-05 | Diagnostics and logging | P1 | Structured logs (`qs log`), debug overlay, config dump, version/environment report, redaction of sensitive values. |
| CORE-06 | Packaging and install | P1 | Arch package (PKGBUILD), install/uninstall scripts, default config bootstrap, dependency checks at startup. |

### 4.2 Bar and status widgets

| ID | Component | Priority | Requirements |
| --- | --- | --- | --- |
| BAR-01 | Status bar | P0 | `PanelWindow` per monitor; configurable edge, height, margins, exclusive zone, auto-hide; left/center/right widget slots; click-through regions correct; default is a floating glass pill inset 8–12 px from the edge, with a non-floating option. |
| BAR-02 | Workspace indicator | P0 | Live workspaces from compositor IPC; active/occupied/empty states; click to switch; scroll to cycle; numeric and icon modes; per-monitor mapping. |
| BAR-03 | Clock / time service | P0 | Localized time and date; configurable format/timezone; calendar popup; no busy polling (timer aligned to minute boundaries). |
| BAR-04 | Battery service | P0 | UPower-backed charge, state, time-to-empty/full, health; laptop-only visibility; low/critical thresholds with OSD and notification hooks. |
| BAR-05 | System statistics | P1 | CPU, memory, disk, temperature, GPU (where available); low-overhead sampling; configurable widgets and intervals. |
| BAR-06 | Network indicator | P0 | NetworkManager state, Wi-Fi SSID/signal, wired, VPN; click opens control center network panel. |
| BAR-07 | System tray | P0 | `SystemTray` items with icon, tooltip, DBusMenu; overflow menu; left/right/middle click handling. |
| BAR-08 | Media widget | P1 | MPRIS now-playing, album art, play/pause/next/previous, seek; hides when no player; per-player selection. |
| BAR-09 | Weather widget | P2 | Provider-agnostic (e.g. Open-Meteo); cached, rate-limited; units and location from config; graceful offline state. |
| BAR-10 | Custom widget API | P2 | Users can add QML widgets via config without forking; documented interface and lifecycle. |

### 4.3 Launcher, dock, and window UX

| ID | Component | Priority | Requirements |
| --- | --- | --- | --- |
| LAUNCH-01 | Application launcher | P0 | Fuzzy search over desktop entries; icons; keyboard navigation; Enter to launch; recent/frequent ranking; per-monitor placement. |
| LAUNCH-02 | Launcher actions | P1 | Calculator, unit conversion, web search, file search (optional index), clipboard history, emoji picker; prefix modes (for example `=` math, `>` commands). |
| LAUNCH-03 | Window switcher | P1 | List/cycle open windows; fuzzy match; focus and close actions; compositor IPC backed. |
| DOCK-01 | Dock | P1 | Pinned + running apps; running/active indicators; click to focus/minimize; middle-click new instance; autohide with reveal zone; per-monitor opt-in; drag reorder. |
| OVERVIEW-01 | Workspace overview / exposé | P2 | Grid of workspaces with live window previews (`ScreencopyView`); drag windows between workspaces; keyboard navigable. |
| WM-01 | Window management helpers | P1 | Move window to workspace/monitor, resize presets, toggle floating/fullscreen, close, pin; exposed via IPC and keybinds. |

### 4.4 Notifications and OSD

| ID | Component | Priority | Requirements |
| --- | --- | --- | --- |
| NOTIF-01 | Notification daemon | P0 | Implement `org.freedesktop.Notifications` via `NotificationServer`; actions, urgency, images, app name/icon, timeout handling, replaces_id. |
| NOTIF-02 | Notification popups | P0 | Stacked, per-monitor, configurable position; timers pause on hover; click actions; swipe/close; never steal focus. |
| NOTIF-03 | Notification center | P1 | History with persistence, grouping by app, search, clear, Do Not Disturb, per-app rules; unread indicator in bar. |
| OSD-01 | On-screen display | P0 | Volume, microphone, brightness, media, caps/num lock, workspace change; coalesced updates; non-focusable overlay; per-monitor. |

### 4.5 Control center and system controls

| ID | Component | Priority | Requirements |
| --- | --- | --- | --- |
| CC-01 | Control center | P0 | Single popup with toggles (Wi-Fi, Bluetooth, DND, night light, power profile), sliders (volume, brightness), media, battery, and shortcuts to settings. |
| AUDIO-01 | Audio control | P0 | PipeWire default sink/source, volume, mute, per-application streams, device switching, microphone mute; WirePlumber integration; no `pactl` parsing if a service exists. |
| AUDIO-02 | Audio extras | P2 | Per-app routing, EQ/effects (if available), output profiles, test tones. |
| BT-01 | Bluetooth control | P0 | Adapter power, scan, pair, connect/disconnect, forget, trust; device battery where exposed; error surfacing (pairing failures, missing firmware). |
| NET-01 | Network control | P1 | Wi-Fi scan/connect (password prompt), wired, VPN state, airplane-mode style toggles; NetworkManager secrets flow via agent/portal. |
| PWR-01 | Power menu | P0 | Lock, logout, suspend, hibernate, reboot, shutdown, UEFI firmware; confirmation for destructive actions; polkit-aware; works with no mouse. |
| PWR-02 | Power profiles | P1 | `power-profiles-daemon` switching (power-saver/balanced/performance) with bar/control-center indicator. |
| IDLE-01 | Idle and lid behavior | P1 | IdleMonitor-driven DPMS/lock/suspend; lid and dock events; inhibitors; configurable timeouts per power state. |

### 4.6 Sessions and security

| ID | Component | Priority | Requirements |
| --- | --- | --- | --- |
| LOCK-01 | Lock screen | P1 | `WlSessionLock` surface per monitor; PAM authentication; Aurora "Pebble" scene shared with the greeter; clock, media, battery; failure feedback and rate limiting; unlock always recoverable. |
| GREET-01 | greetd greeter | P1 | Separate Quickshell config run by greetd as the `greeter` user inside `cage`; user picker, password, session selection from `/usr/share/wayland-sessions`; greetd authentication and launch; shared palette fallback; optional, explicitly installed power actions; recoverable via VT switch and config backup. |
| POLKIT-01 | Polkit agent | P1 | Desktop polkit agent for privileged actions (mount, package install, power); password prompt UI integrated with the lock/session style. |
| SEC-01 | Secret handling | P0 | Never log passwords/tokens; Wi-Fi and Bluetooth secrets go through the proper agents; config excludes credentials. |

### 4.7 Wallpaper, theme, and appearance

| ID | Component | Priority | Requirements |
| --- | --- | --- | --- |
| WALL-01 | Wallpaper manager | P0 | Set static/animated wallpapers via `swww`/`hyprpaper` adapter; per-monitor and per-workspace; transitions; shuffle/rotate; cache; restore on login. |
| WALL-02 | Wallpaper browser | P1 | Browse directories, preview grid, favorites, random pick, crop/fit mode. |
| THEME-01 | Theme engine | P0 | Semantic design tokens (surface, on-surface, accent, success/warning/error, radius, spacing, typography, elevation); light/dark variants; runtime switching without restart. |
| THEME-02 | Palette generation | P0 | Generate a Material-style palette from the wallpaper (quantized dominant colors) and/or hand-picked base color; contrast validation; fallback palette. |
| THEME-03 | Auto theme switch | P0 | Switch light/dark by schedule (sunrise/sunset or fixed times), by manual toggle, and by app-specific rules; atomic switch with no flash of wrong theme. |
| THEME-04 | Pebble design system | P0 | Shared material tokens (radius, tint, rim, specular, glow, shadow, press/hover) exposed via `Metrics`; `Pebble`/`Bubble`/`PebbleButton`/`GlowRing`/`DotMatrixText`/`Specular` components; `pebbleQuality` low/medium/high with software fallback; reduced-motion and high-contrast variants; documented in `docs/DESIGN.md`; every shell surface uses it. |
| APP-01 | Application theming | P0 | Apply the active theme to GTK 3/4, Qt (Kvantum/Qt platform theme), terminals (kitty/alacritty/foot/wezterm), browsers (Firefox/Chromium via native theming or extensions), editors (VS Code), and common apps (Discord/Spotify via client themes) where supported. |
| APP-02 | Theme templates | P1 | Per-application template files rendered from tokens; reload signal/hook per app; dry-run and diff preview; backups before overwrite. |
| APP-03 | Icon/cursor/font manager | P2 | Browse and apply icon themes, cursors, and fonts across GTK/Qt and shell. |

### 4.8 Settings application

| ID | Component | Priority | Requirements |
| --- | --- | --- | --- |
| SET-01 | Settings app | P0 | Full-window or large popup; sections for Appearance, Bar, Launcher/Dock, Notifications, Input/Keybinds, Services, Power, About; Pebble material controls with a live material preview (`pebbleQuality`, `pebbleTint`); live preview; search; validation; reset-to-default; export/import config. |
| SET-02 | Keybind editor | P1 | View and edit shell keybinds; conflict detection; apply to compositor config or shell IPC as appropriate; show current bindings. |
| SET-03 | About and updates | P2 | Version, Quickshell/Qt versions, environment report, update check, link to logs and docs. |

### 4.9 Tooling and rice

| ID | Component | Priority | Requirements |
| --- | --- | --- | --- |
| CLI-01 | `ostrich` CLI | P0 | Python entry point for wallpaper, palette, template, auto-theme, IPC, and diagnostics commands; stable `--json` output; documented exit codes; no root; atomic writes with backups. |
| TERM-01 | Terminal and desktop rice | P1 | foot + fish + starship prompt, btop, fastfetch, micro, and a Hyprland snippet, all driven by the generated colour tokens; install/reload scripts with `--dry-run` and backups. |

### 4.10 Utilities

| ID | Component | Priority | Requirements |
| --- | --- | --- | --- |
| CLIP-01 | Clipboard manager | P1 | History with text/image previews, pinning, search, clear; wl-clipboard/portal integration; privacy controls (ignore sensitive apps). |
| SHOT-01 | Screenshot and recording | P1 | Region/window/monitor capture (`grim`/`slurp`), annotation (optional), clipboard/save, screen recording (`wf-recorder`); notifications on completion. |
| CAL-01 | Calendar and events | P2 | Month view, week numbers, event integration (CalDAV/ICS read-only), timezone display. |
| EMOTE-01 | Emoji and symbol picker | P2 | Search, categories, recently used, copy/type insertion. |
| SYS-01 | System actions | P1 | Volume/brightness/media key handling, caps/num lock OSD, monitor layout helpers, notification of hardware changes. |

### 4.11 Cross-cutting

| ID | Requirement | Priority | Notes |
| --- | --- | --- | --- |
| A11Y-01 | Accessibility | P1 | Keyboard-only operation, focus rings, screen-reader labels where toolkit permits, reduced motion, high contrast, scalable text; greeter and lock follow the same rules. |
| I18N-01 | Localization | P1 | All strings via `qsTr`; translation files; locale-aware dates/numbers; RTL-safe layouts. |
| PERF-01 | Performance | P0 | See targets below; no blocking IO on the GUI thread; no polling faster than needed. |
| SEC-02 | Sandboxing/least privilege | P1 | No running as root; privileged operations via polkit; validate all external input; avoid shell interpolation. |
| DOC-01 | Documentation | P1 | Install guide, configuration reference, theming guide, keybind reference, troubleshooting, component API docs. |
| TEST-01 | Test coverage | P0 | Qt Quick Test suites for logic/components; CI gates per `AGENTS.md`. |

---

## 5. Service and data matrix

| Domain | Source of truth | Fallback | Notes |
| --- | --- | --- | --- |
| Workspaces, windows, focus | Hyprland IPC (`Hyprland`, `ToplevelManager`) | i3 IPC for Sway | Adapter interface; clear "unsupported" state elsewhere. |
| Time/date | System clock + timezone | — | Timer aligned to minute changes; no per-second polling unless a widget needs it. |
| Battery | UPower (`UPower`) | `/sys/class/power_supply` read-only | Show health and time estimates. |
| Power profiles | `power-profiles-daemon` (`PowerProfiles`) | none | Hide when unavailable. |
| Audio | PipeWire/WirePlumber (`Pipewire`) | — | Per-node volume/mute; device profiles. |
| Bluetooth | BlueZ (`Bluetooth`) | `bluetoothctl` (last resort) | Pairing errors must surface. |
| Network | NetworkManager (`Networking`) | — | Secrets via agent/portal. |
| Media | MPRIS (`Mpris`) | — | Multiple players, choose active. |
| Tray | StatusNotifier/DBusMenu (`SystemTray`) | — | Overflow handling. |
| Notifications | `NotificationServer` | — | Must own the notification name on the bus. |
| Wallpaper | `swww` / `hyprpaper` | static layer-shell image | Adapter selected from config. |
| Clipboard | `wl-clipboard` / portal | — | Privacy filter. |
| Screen capture | `grim`/`slurp`/`wf-recorder` | xdg-desktop-portal | Portal preferred where available. |
| Lock/auth | PAM (`PamContext`) | — | Never log credentials. |
| Greeter auth/session | greetd (`Quickshell.Services.Greetd`) | — | Separate config under `cage`; never reads user state. |
| Privileged actions | polkit (`PolkitAgent`) | — | Integrated agent UI. |

---

## 6. Non-functional requirements

### Performance

| Metric | Target |
| --- | --- |
| Shell cold start | < 700 ms to usable bar on a modern laptop |
| Idle CPU | < 1% of one core on average |
| Idle memory (RSS) | < 200 MB for shell + bar on two monitors |
| Interaction latency | < 50 ms from key press to visible response for launcher/popups |
| Animation | 60 fps target, never below 30 fps; honor reduced-motion |
| Material budget | ≤ 12 `Specular` shaders per screen at `pebbleQuality: high`; ≤ 50 ms added to first paint; `low`/`medium` must render with no shader |
| Polling | No timer faster than 1 Hz unless the feature requires it; battery/network event-driven |

### Reliability

- A failing widget must not take down the shell; isolate errors and show a
  diagnostic state.
- Reload must preserve user-visible state (open popups may close, but config,
  theme, and session state must survive).
- Every external command must have a timeout and a failure path.

### Security

- No secrets in config, logs, or crash output.
- No `sh -c` with interpolated untrusted strings; use argument lists.
- Validate paths, URLs, and desktop-entry commands before execution.
- Polkit/PAM prompts must never be spoofable by other clients.

### Accessibility

- Full keyboard navigation with visible focus.
- Configurable font scale and contrast.
- Respect `prefers-reduced-motion` equivalent from config.
- Screen-reader metadata where Qt exposes it.

### Configuration and compatibility

- Config schema is versioned; migrations run automatically with a backup.
- Breaking config/theme/IPC changes require a MAJOR version bump (see
  `AGENTS.md`).
- Minimum Quickshell and Qt versions are checked at startup with a clear error.

---

## 7. Milestones

| Milestone | Scope | Exit criteria |
| --- | --- | --- |
| **M0 — Scaffold** (current) | Repo, branches, CI, release flow, PRD, AGENTS | CI green; branch protection active; PRD approved. |
| **M1 — Core shell** | CORE-01..04, BAR-01..04, BAR-06..07, OSD-01, NOTIF-01/02, WALL-01, THEME-01 | A usable daily-driver bar with notifications, battery, workspaces, volume OSD. |
| **M2 — Input and windows** | LAUNCH-01/02, DOCK-01, WM-01, NOTIF-03, CLIP-01, SHOT-01 | Launcher, dock, notification center, clipboard and screenshots work. |
| **M3 — System and theming** | CC-01, AUDIO-01, BT-01, NET-01, PWR-01/02, IDLE-01, THEME-02/03/04, APP-01/02, SET-01 | Control center, full theme propagation to apps, auto light/dark, Pebble material across the shell, settings app. |
| **M4 — Session and polish** | LOCK-01, GREET-01, POLKIT-01, OVERVIEW-01, BAR-05/08, SET-02, a11y, i18n, packaging | Lock screen, optional greetd login, overview, performance targets met, installable package. |

Each milestone ships through the release flow in `AGENTS.md`: `dev` -> `test` ->
`main`, with the version bumped per milestone release.

The concrete task breakdown, workstream ownership, wave order, and per-agent
prompts live in [docs/SUBAGENT_PLAN.md](docs/SUBAGENT_PLAN.md) and
[docs/prompts/](docs/prompts/). Contracts between workstreams are frozen in
[docs/CONTRACTS.md](docs/CONTRACTS.md).

---

## 8. Acceptance criteria for v1

A v1 release is accepted when:

1. A fresh Arch + Hyprland install can run Ostrich from the package with default
   config and no manual QML edits.
2. Bar, launcher, notifications, control center, power menu, wallpaper, and theme
   switching work on a multi-monitor setup.
3. Light/dark switching updates the shell and at least GTK, Qt, terminal, and
   browser themes without a restart.
4. Battery, audio, Bluetooth, network, media, and workspace data update live and
   degrade gracefully when a service is missing.
5. Lock screen authenticates via PAM and always unlocks; the optional greetd
   greeter logs in, launches a session, and shares the lock's visual language.
6. Every surface follows the Pebble design system; `pebbleQuality: low` renders
   the full shell without shaders.
6. The performance targets in section 6 are met on the reference machine.
7. CI is green on `test`, the release PR to `main` merges with all required
   checks, and `v1.0.0` is tagged and published automatically.
8. Documentation covers install, configuration, theming, keybinds, and
   troubleshooting.

---

## 9. Out of scope for v1

- Compositor features (tiling logic, window rules) beyond helpers.
- A general-purpose display manager: Ostrich ships an optional greetd **greeter**,
  not a multi-DE login manager, and it is installed explicitly.
- Mobile or touch-first layouts.
- Non-Arch packaging (deb, rpm, Flatpak) — post-v1.
- Cloud sync of settings or themes.
- AI assistants, widgets with accounts, or telemetry of any kind.

---

## 10. Risks and mitigations

| Risk | Impact | Mitigation |
| --- | --- | --- |
| Quickshell API churn | Build breaks after updates | Pin a tested Quickshell version; adapter layer; opt-in smoke job catches load failures. |
| Compositor differences | Features only work on Hyprland | Define a compositor interface; feature-detect and show explicit unsupported states. |
| Per-app theming fragility | Apps change config formats | Template system with backups, dry-run/diff, and documented best-effort support. |
| Wallpaper palette quality | Poor contrast/readability | Contrast validation, fallback palettes, manual accent override. |
| Shader cost on weak GPUs | Jank or battery drain | `pebbleQuality` low/medium/high, shader cap per screen, gradient fallback, software-render test. |
| greetd misconfiguration locks the user out | Unbootable desktop | Package-owned drop-in, timestamped backup, `--apply` gate, documented VT-switch and restore path. |
| Performance regressions | Shell feels sluggish | Budgets in CI where measurable; profiling checklist in PR template. |
| Secret leakage in logs | Security issue | Redaction rules, secret scan in CI, no credential storage in config. |

---

## 11. Open questions

1. Which Quickshell version becomes the supported minimum for v1?
2. Is Niri a first-class target for v1 or best-effort?
3. Should the settings app be a separate process or part of the shell process?
4. Which wallpaper backend is the default: `swww` or `hyprpaper`?
5. Do we ship an opinionated default theme or a neutral base?
6. How much per-app theming is contractual vs. best-effort (Discord/Spotify are
   unofficial clients)?
7. Packaging: AUR only, or also an official Arch package once stable?
