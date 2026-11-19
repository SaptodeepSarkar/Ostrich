# Ostrich Subagent Implementation Plan

**Status:** active (2026-11-19) · **Scope:** v1 shell + CLI + rice
**Contracts:** [CONTRACTS.md](CONTRACTS.md) is frozen; read it before any prompt.
**Prompts:** [prompts/LAUNCH.md](prompts/LAUNCH.md) and `prompts/00..11-*.md`.

This document splits the whole Ostrich build into 12 workstreams that can be
executed by separate agents, mostly in parallel, without stepping on each other.
It also records what the reference shell (caelestia) does so we reimplement the
*capabilities* — not the UI, code, assets, or strings.

---

## 1. How to use this plan

1. Read [CONTRACTS.md](CONTRACTS.md). It defines paths, singletons, config,
   IPC targets, CLI commands, and the UI kit. Do not invent alternatives.
2. Pick the next unblocked workstream from §6 (waves).
3. Give the agent exactly one prompt file from `docs/prompts/`.
4. The agent works in its own worktree on `feat/wsN-<slug>`, opens a PR into
   `dev`, and reports in the format from §9.
5. A human (or the integrator agent) merges in the order from §5.3. Contract
   changes go through a separate PR before the dependent work continues.
6. After the last wave, WS11 runs the full QA + release pass.

One workstream = one agent = one branch = one PR. Never two agents in one
directory.

---

## 2. Decoded reference: what caelestia actually is

We studied the four reference repositories (read-only, GPL-3.0):

| Repo | What it contributes |
| --- | --- |
| `caelestia-dots/shell` | QML shell, C++ plugin (blobs, config, image analysis), services, modules, daemons |
| `caelestia-dots/cli` | Python CLI: `materialyoucolor` + Pillow palette generation, `scheme.json`, template rendering, IPC wrappers |
| `caelestia-dots/caelestia` | Dotfiles/rice: Hyprland, foot, fish, fastfetch, btop, micro, thunar |
| `caelestia-dots/lib` / `plugins` | Shared C++ library and plugin manifests |

### 2.1 Capability inventory (what we must match or consciously defer)

**Shell surface**

- Bars per monitor with workspaces, active window, clock, tray, power, status
  icons (battery/Bluetooth/lock), popouts anchored to bar widgets.
- Launcher with app search, calculator, actions, and prefix modes.
- Dock (auto-hide, pinned + running).
- Notification daemon + popups + history sidebar + DND + grouping/actions.
- OSD for volume, brightness, media, keyboard layout, lock keys.
- Session/power menu, lock screen with PAM, idle/DPMS handling.
- Dashboard (calendar, media, performance, weather), sidebars/drawers, area
  picker for screenshots, window info, overview-ish window list.
- Settings UI ("nexus") generated from the config schema, per-monitor config.
- Utilities: clipboard history, screenshot, screen recording, emoji picker,
  toasts, idle inhibitor, game mode.
- Global shortcuts + IPC for every panel and action.

**Theme pipeline**

- Material 3 palette from wallpaper (`materialyoucolor`), multiple variants,
  dark/light, transparency/luminance adjustment.
- One state file (`scheme.json`) consumed by the shell.
- Template rendering into GTK, Qt, foot/kitty/alacritty, fish, btop, starship,
  fastfetch, fuzzel, Zed/VS Code, Discord, Spicetify, browser themes.
- Static curated schemes (Catppuccin, Dracula, Everforest, Gruvbox, Nord…).
- Auto light/dark by time, manual toggle, random scheme.

**Rice**

- foot terminal config, fish prompt/functions, fastfetch, btop, micro, starship,
  Thunar, Hyprland colour + keybind snippets — all colour-token driven.

**Deliberately deferred (documented, not silently dropped)**

| Deferred | Why | Fallback |
| --- | --- | --- |
| C++ plugin (morphing blob shapes) | v1 is QML-only, no CMake | Plain rounded rectangles, optional `ShaderEffect` later |
| GPU audio visualiser | Needs plugin-quality FFT | Static/level-meter bars, behind a config flag |
| Live wallpaper video | swww-only feature | Static image + per-workspace images |
| Screencopy window previews | Fragile across compositors | Window title list, `ScreencopyView` behind a feature flag |
| Nix/Home-Manager modules | Post-v1 packaging | — |

### 2.2 What must NOT be copied

The reference is **GPL-3.0**, Ostrich is **MIT**. Therefore:

- No copied QML, Python, C++, shaders, config text, icons, or images.
- No copied user-visible strings, names, or layout structure that is
  recognisably the same composition.
- Behaviour may be reimplemented independently; the public Quickshell/Qt APIs and
  the Material 3 / freedesktop specifications are fair game.
- If an agent is unsure, it must ask instead of "adapting" reference code.

---

## 3. Ostrich v1 architecture (target)

```
qs -p shell  (or `ostrich shell start`)
│
├── shell/shell.qml                  ShellRoot: module composition + single instance
├── shell/services/                  Singletons only, no visuals
├── shell/components/                UI kit, theme-token driven
├── shell/utils/                     Pure QML helpers (formatting, fuzzy, icons)
└── shell/modules/                   One directory per surface
        background bar notifications osd controlcenter launcher dock
        session lock settings overview utilities

ostrich (Python CLI, separate process)
├── theme/scheme generation (wallpaper → M3 palette → scheme.json)
├── wallpaper backend adapters (swww/hyprpaper/static)
├── template rendering into user configs
├── auto light/dark scheduler
└── IPC wrapper around `qs ipc`
```

Rules already frozen in `CONTRACTS.md`: relative QML imports, singletons via
`pragma Singleton` + `Singleton {}`, services never constructed by UI, atomic
state writes, no hardcoded colours/paths, `qsTr` everywhere, argv-only
processes.

---

## 4. Workstreams

| WS | Name | Owns | Wave | Hard dependency | Prompt |
| --- | --- | --- | --- | --- | --- |
| WS0 | Core kernel | `shell/shell.qml`, `shell/services/{Paths,Config,State,Theme,Wallpaper,Time,Toast}.qml`, `config/default.json`, placeholder modules | 0 | — | `00-core-kernel.md` |
| WS1 | UI kit + service stubs | `shell/components/`, `shell/utils/`, all remaining `services/*.qml` stubs, `tests/mocks/` | 1 | WS0 | `01-ui-kit-service-contracts.md` |
| WS2 | Theme & wallpaper CLI + background | `cli/`, `shell/modules/background/`, `themes/README.md` | 1 | WS0 (contracts only) | `02-theme-cli.md` |
| WS10 | Terminal rice | `rice/`, `config/hypr/`, `scripts/rice/`, `cli/src/ostrich/data/templates/rice/` | 1 | WS2 (token names only) | `10-terminal-rice.md` |
| WS3 | Bar & widgets | `shell/modules/bar/` | 2 | WS0, WS1 | `03-bar-widgets.md` |
| WS4 | Notifications & OSD | `shell/modules/{notifications,osd}/`, real `services/Notifications.qml` | 2 | WS1 | `04-notifications-osd.md` |
| WS6 | Launcher & dock | `shell/modules/{launcher,dock,overview}/` | 2 | WS1 | `06-launcher-dock.md` |
| WS7 | Session & lock | `shell/modules/{session,lock}/`, real `services/{Power,Idle,Battery}.qml` | 2 | WS1 | `07-session-lock.md` |
| WS5 | Services & control center | `shell/modules/controlcenter/`, real `Audio/Bluetooth/Network/Media/Tray/Brightness/Weather` services | 3 | WS1, WS3 (popup host pattern) | `05-services-control-center.md` |
| WS9 | Utilities | `shell/modules/utilities/`, real `Clipboard/Recorder` services, area picker | 3 | WS1, WS3 | `09-utilities.md` |
| WS8 | Settings app | `shell/modules/settings/` | 4 | WS0, WS1, WS5 (needs every config key) | `08-settings-app.md` |
| WS11 | QA, docs, release | `tests/`, `docs/`, packaging, `Makefile` targets | 5 | all | `11-qa-release.md` |

Why this split:

- WS0 + WS1 produce the only shared files; everything else is directory-local.
- WS2 is Python and touches no QML singleton that others edit, so it can start
  immediately next to WS0.
- WS10 only writes rice/config templates and consumes the token names from
  `scheme.json`, so it runs early while the CLI is being written.
- WS3/WS4/WS6/WS7 have disjoint module directories. They all need the UI kit,
  hence wave 2.
- WS5 and WS9 are the heaviest service integrations; they build on the popup
  pattern proven by WS3/WS4.
- WS8 reads the whole config and every service, so it goes last before QA.

---

## 5. Execution model

### 5.1 Worktrees and branches

```bash
# from a clean dev checkout
git switch dev && git pull --ff-only origin dev
git worktree add ../ostrich-ws3 -b feat/ws3-bar dev
cd ../ostrich-ws3
# run the agent here, with docs/prompts/03-bar-widgets.md
```

Naming: branch `feat/wsN-<slug>`, worktree `../ostrich-wsN`.
Multiple agents may run at once, but only across different workstreams.

### 5.2 Commits

Conventional Commits, one logical change each. Scope = workstream:

```
feat(bar): add workspace and clock widgets
feat(cli): render foot theme from scheme.json
fix(notifications): pause timeout on hover
docs(contracts): add tray activate signature
test(theme): cover palette contrast fallback
```

Reference the PRD ID in the body (`BAR-01`, `THEME-02`, …). Do not bump
`VERSION`; only release PRs do that.

### 5.3 Merge order and conflict rules

1. `docs/contracts` (WS0 preamble) lands first — this PR.
2. WS0 → then WS1 and WS2 in parallel → WS10 after WS2's token list is merged
   (templates only; it can start earlier if it keeps to CONTRACTS §6).
3. Wave 2 PRs merge in this order to minimise rebases:
   `WS4` (notifications) → `WS3` (bar) → `WS7` (session) → `WS6` (launcher/dock).
4. Wave 3: `WS5` → `WS9`.
5. Wave 4: `WS8`.
6. Wave 5: `WS11`.

Rules:

- Each agent merges latest `origin/dev` into its branch before opening the PR and
  again before merging if `dev` moved.
- Conflicts inside an owned directory are resolved by that owner.
- A conflict in a shared file (`shell.qml`, `components/`, `services/Paths|Config|
  State|Theme`) is resolved by WS0/WS1's owner; other agents must not "fix" it.
- Contract changes: open a `docs(contracts): …` PR first, get it merged, then
  rebase. Never change a signature inside a feature PR.
- `dev` requires green `CI Success`. Use merge commits (repo policy).
- A broken module must never block the shell: WS0 placeholders stay until the
  real module replaces them in the same PR.

### 5.4 Integration checkpoints

| Checkpoint | After | Gate |
| --- | --- | --- |
| C0 | WS0 | `qs -p shell` boots to an empty desktop with all modules as no-ops; `make check` green |
| C1 | WS1 + WS2 | UI kit demo page renders; `ostrich scheme get` works; `Theme` singleton applies `scheme.json` |
| C2 | WS3 + WS4 | Daily-driver bar + notifications + OSD on two monitors |
| C3 | WS6 + WS7 | Launcher, dock, power menu, lock/unlock round-trip |
| C4 | WS5 + WS9 | Control center, clipboard, screenshot, recorder |
| C5 | WS8 | Settings edits every config key live |
| C6 | WS11 | Full QA matrix, docs, package, release PR |

---

## 6. Wave schedule

```
Wave 0   WS0 ──────────────────────────────────────────────► C0
Wave 1        ├─ WS1 (UI kit + stubs) ─────► C1
              ├─ WS2 (CLI + background) ───► C1
              └─ WS10 (rice) ──────────────► C1 (templates)
Wave 2        ├─ WS4 (notifications/OSD) ──┐
              ├─ WS3 (bar) ────────────────┼► C2/C3
              ├─ WS7 (session/lock) ───────┤
              └─ WS6 (launcher/dock) ──────┘
Wave 3        ├─ WS5 (services/CC) ────────► C4
              └─ WS9 (utilities) ──────────┘
Wave 4        └─ WS8 (settings) ───────────► C5
Wave 5        └─ WS11 (QA/release) ────────► C6
```

Maximum concurrency: 4 agents (wave 2). WS0 and WS1 must not overlap with edits
to the same files, so WS1 starts only after WS0's PR merges.

---

## 7. Feature mapping (reference → Ostrich)

Use this table to check that nothing important was dropped. "Ostrich WS" is who
builds it; "PRD" is the acceptance anchor.

### 7.1 Shell

| Caelsetia capability | Ostrich WS | PRD | Notes |
| --- | --- | --- | --- |
| `shell.qml` + Config plugin + per-monitor overrides | WS0 | CORE-01/02/04 | Config in pure QML + JSON, no C++ |
| `Screens`/`ShellState` per-screen state | WS0 | CORE-04 | `Variants` + `State` singleton |
| `Colours` palette + transparency | WS0 (consumer) / WS2 (producer) | THEME-01/02 | `Theme.qml` reads `scheme.json` |
| Wallpaper service + `Wallpapers` list | WS0 service / WS2 CLI | WALL-01/02 | swww/hyprpaper adapter in Python |
| Bar + popouts + tray + workspaces + active window | WS3 | BAR-01..08 | Own layout, own widgets |
| Notification daemon, popups, history sidebar | WS4 | NOTIF-01..03 | `NotificationServer`, own history store |
| OSD (volume/brightness/media/kb layout) | WS4 | OSD-01 | Coalesced, non-focusable |
| Launcher (apps, calc, actions, prefixes) | WS6 | LAUNCH-01/02 | Fuzzy scorer in `utils/` |
| Window switcher / window info | WS6 | LAUNCH-03, OVERVIEW-01 | Toplevel list first, previews optional |
| Dock | WS6 | DOCK-01 | Pinned + running |
| Session/power menu | WS7 | PWR-01 | Confirmation for destructive actions |
| Lock screen + PAM | WS7 | LOCK-01 | `WlSessionLock`, always recoverable |
| Idle monitors / DPMS / inhibitors | WS7 | IDLE-01 | `IdleMonitor` + daemon |
| Control center toggles/sliders | WS5 | CC-01 | Popup from bar |
| Audio/Bluetooth/network/media/power-profile services | WS5 | AUDIO-01, BT-01, NET-01, PWR-02 | Quickshell singletons first |
| Weather | WS5 | BAR-09 | Open-Meteo, cached |
| Settings UI ("nexus") | WS8 | SET-01/02 | Generated from config schema |
| Clipboard history | WS9 | CLIP-01 | Text + image, pinning, privacy |
| Screenshot / area picker / recorder | WS9 | SHOT-01 | grim/slurp/wf-recorder + portal fallback |
| Emoji picker, toasts, idle inhibit, game mode | WS9 | EMOTE-01, SYS-01 | Utilities panel |
| Dashboard (calendar/media/perf/weather) | WS9 | CAL-01, BAR-05/08 | Compact dashboard page, not a copy |
| Global shortcuts + IPC | WS0 (skeleton) + each module | CORE-03 | `IpcHandler` per target |
| Hyprland helpers (move/resize/close) | WS3/WS9 | WM-01 | `Hyprland.dispatch` |

### 7.2 Theme pipeline

| Reference | Ostrich WS | PRD | Notes |
| --- | --- | --- | --- |
| `caelestia scheme set --name/--flavour/--mode/--variant/--random` | WS2 | THEME-02/03 | Same *capability*, new CLI surface |
| `materialyoucolor` palette + Pillow extraction | WS2 | THEME-02 | Same libraries, independent code |
| `scheme.json` state file | WS2 (write) / WS0 (read) | THEME-01 | Contract §6, adds `version`/`source` |
| `theme apply` template engine | WS2 | APP-01/02 | Manifest + `{{ token }}` placeholders |
| Static scheme library | WS2 | THEME-02 | JSON schemes we author ourselves |
| Auto light/dark by time | WS2 | THEME-03 | `ostrich scheme auto` + systemd user timer |
| Wallpaper set/random/list + smart crop | WS2 | WALL-01 | Backend adapters |
| Toggle light/dark from bar | WS3 | THEME-03 | Calls `Theme.toggleMode()` → IPC |
| Per-app enabling (`theme.apps.*`) | WS0 config / WS2 | APP-01 | Already in contract |
| Icon/cursor/font switching | WS11 (P2) | APP-03 | Post-v1 |

### 7.3 Rice

| Reference | Ostrich WS | Notes |
| --- | --- | --- |
| foot config | WS10 | `rice/foot/foot.ini` + generated include |
| fish config/functions | WS10 | Prompt, aliases, `zoxide`/`eza` integration |
| fastfetch, btop, micro | WS10 | Token-driven templates |
| starship | WS10 | Palette-mapped |
| Thunar / GTK bookmarks | WS10 | Colours + sane defaults |
| Hyprland colours, keybinds snippet | WS10 | `config/hypr/ostrich.conf`, no full compositor config takeover |
| Terminal live reload | WS10 | foot `SIGUSR1`/server reload, fish `fish_prompt` reread |

---

## 8. Shared-file ownership

| File / dir | Owner | Others may |
| --- | --- | --- |
| `docs/CONTRACTS.md` | WS0 | propose changes via PR |
| `shell/shell.qml` | WS0 | not edit |
| `shell/services/Paths.qml`, `Config.qml`, `State.qml`, `Theme.qml` | WS0 | read only |
| `shell/services/*.qml` stubs | WS1 | owning WS replaces its own file |
| `shell/components/`, `shell/utils/` | WS1 | use, request additions |
| `config/default.json` | WS0 | add keys via contract PR |
| `cli/` (except `data/templates/rice/`) | WS2 | not edit |
| `cli/src/ostrich/data/templates/rice/` | WS10 | not edit |
| `rice/`, `config/hypr/`, `scripts/rice/` | WS10 | not edit |
| `tests/mocks/` | WS1 | add module-specific mocks |
| `VERSION`, `CHANGELOG.md` release section | WS11 | Unreleased entries allowed |

When an agent needs a new component prop or service field, it must:

1. Add a `docs(contracts)` PR with the exact signature and rationale.
2. Wait for merge (or get the integrator's explicit go-ahead).
3. Then use it.

This is the only rule that prevents 10 parallel agents from producing an
unmergeable tree.

---

## 9. Handoff report (required from every agent)

Every PR body and final agent message must use this template:

```markdown
## WS<N> — <name>

### Delivered
- files/dirs added or changed (bullet list)

### Contract compliance
- singletons used: ...
- IPC targets registered: ...
- config keys added: ...

### Verification
- `make check`: pass/fail + output summary
- `make smoke`: pass/skipped (reason)
- new tests: paths + what they cover
- manual checks: what was clicked/typed, on which compositor

### Deviations / follow-ups
- anything not done, with the reason and the workstream that should own it

### Screenshots / recording
- required for any visual change
```

---

## 10. Definition of done (per workstream)

1. Only owned paths touched (or contract PR merged).
2. `make check` green locally with `PATH="$HOME/.local/bin:$PATH"`.
3. `make smoke` green if Quickshell is installed; otherwise stated.
4. Behaviour is reactive: no polling faster than needed, no blocking calls.
5. All strings `qsTr`, all colours from tokens, all paths from `Paths`.
6. New config keys present in `config/default.json` + `CONTRACTS.md`.
7. Tests for parsing/mapping/state logic; UI at least loads headless.
8. No GPL code/assets/strings; no secrets; no absolute paths.
9. Docs updated (`docs/`, PRD if scope changed, `CHANGELOG.md` Unreleased).
10. PR into `dev`, CI green, handoff report complete.

---

## 11. Risk register

| Risk | Wave | Mitigation |
| --- | --- | --- |
| Quickshell API drift (v0.x) | all | Pin version in `docs/install.md`; lookup types before use; `make smoke` |
| Contract churn stalls parallel work | 1–3 | Freeze now; changes only via dedicated PR; WS0/WS1 quick turnaround |
| Merge conflicts in `shell.qml` | all | Thin composition root; modules self-register via their own files |
| Service singleton churn (PipeWire/BlueZ) | 3 | Read-only adapters + stubs; degrade with `available=false` |
| Lock screen bricks the session | 2 | Always render an unlock path; test `locked=false` before quit; PAM failure backoff |
| Palette contrast fails on dark wallpapers | 1 | Contrast validation + fallback palette (THEME-02 acceptance) |
| Template writes clobber user configs | 1 | Atomic writes, `.bak` backups, `--dry-run`, `theme.apps.*` gates |
| Per-app theming breaks on app updates | 1 | Manifest-driven, best-effort, `ostrich doctor` reports drift |
| Wayland-only features on non-Hyprland | 2–3 | `available` flags, explicit unsupported UI, adapter interface |
| Two agents editing a stub service | 2–3 | One owner per file, listed in §8 and in each prompt |
| Performance regressions | 5 | Budgets from PRD §6 measured in WS11; no per-frame JS |

---

## 12. Prompt index

| File | Workstream |
| --- | --- |
| `prompts/LAUNCH.md` | Orchestration: worktrees, sequencing, review |
| `prompts/00-core-kernel.md` | WS0 core kernel |
| `prompts/01-ui-kit-service-contracts.md` | WS1 UI kit + service stubs |
| `prompts/02-theme-cli.md` | WS2 theme/wallpaper CLI + background |
| `prompts/03-bar-widgets.md` | WS3 bar and widgets |
| `prompts/04-notifications-osd.md` | WS4 notifications + OSD |
| `prompts/05-services-control-center.md` | WS5 services + control center |
| `prompts/06-launcher-dock.md` | WS6 launcher, dock, overview |
| `prompts/07-session-lock.md` | WS7 session, lock, idle |
| `prompts/08-settings-app.md` | WS8 settings app |
| `prompts/09-utilities.md` | WS9 utilities |
| `prompts/10-terminal-rice.md` | WS10 terminal/desktop rice |
| `prompts/11-qa-release.md` | WS11 QA, docs, release |

Each prompt is self-contained: an agent with no prior context can execute it by
reading the prompt plus `AGENTS.md`, `PRD.md`, and `CONTRACTS.md`.

---

## 13. Milestone mapping (PRD → plan)

| PRD milestone | Workstreams | Checkpoint |
| --- | --- | --- |
| M0 Scaffold | done | — |
| M1 Core shell | WS0, WS1, WS2, WS3, WS4 | C2 |
| M2 Input and windows | WS6, WS9 (clipboard/shot) | C3/C4 |
| M3 System and theming | WS2, WS5, WS8, WS10 | C4/C5 |
| M4 Session and polish | WS7, WS11 | C6 |

`VERSION` goes to `0.2.0` when C2 lands, `0.3.0` at C4, `1.0.0` at C6 (release
PRs only, per `AGENTS.md`).
