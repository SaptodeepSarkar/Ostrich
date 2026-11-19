# WS11 — QA, documentation, packaging, release

**Branch:** `feat/ws11-qa-release` · **Worktree:** `../ostrich-ws11`
**Wave:** 5 · **Depends on:** WS0–WS10 merged · **Blocks:** v1.0.0
**Owns:** `tests/` (final pass), `docs/`, `packaging/`, `Makefile`, `scripts/ci/`,
`CHANGELOG.md`, `VERSION` (release commit only)

---

## Mission

Turn a collection of merged features into a shippable product: automated tests
that actually run in CI, a complete documentation set, an Arch package, measured
performance against the PRD budgets, a security/licence review, and the release
PR. You are the last line of defence — if something is broken, you either fix it
inside your owned files or send it back with a precise report.

Read `AGENTS.md` (release runbook, branch rules), `PRD.md` (§6, §8), and
`docs/SUBAGENT_PLAN.md` §10.

---

## 1. Test and CI hardening

Current CI scripts live in `scripts/ci/`. Extend them surgically:

- `scripts/ci/test.sh`: discover and run **both** QML tests
  (`tests/**/tst_*.qml` via `qmltestrunner`, `QT_QPA_PLATFORM=offscreen`) and
  Python tests (`cli/tests`, `pytest -q`). Fail if a suite directory exists but
  zero tests ran (prevents silent skips).
- `scripts/ci/lint.sh`: add `ruff check cli/src cli/tests` (or `python -m
  compileall` if ruff is unavailable in the container), keep `qmllint` and
  `shellcheck`. Add a `qmldir` coverage check: every `pragma Singleton` file in
  `shell/services/` is listed in `shell/services/qmldir`.
- `scripts/ci/validate.sh`: assert required files (`shell/shell.qml`,
  `config/default.json`, `cli/pyproject.toml`, `docs/CONTRACTS.md`), and that
  every config key in `config/default.json` is documented in
  `docs/configuration.md` (simple flattened-key grep; WS8's schema test covers
  the UI side).
- `scripts/ci/review.sh`: add a GPL-copy guard (deny "caelestia" strings and
  GPL headers in source), plus a check that no `TODO`/`FIXME` without an owner
  was added, and no binary blobs > 256 KB outside `assets/`.
- `scripts/ci/smoke.sh`: keep opt-in; if `ENABLE_QUICKSHELL_SMOKE=true`, launch
  `qs -p shell` headless for 5 s, assert no `ReferenceError`/`TypeError` in the
  log, then kill.
- Do not weaken any existing check. Do not touch branch protection.

New tests you write (only where coverage is missing):

- Config migration: `version` 0/absent → 1, unknown future version refuses with a
  clear error.
- IPC surface: every target from `CONTRACTS.md` §7 is registered by a running
  shell (parse `qs ipc show`, or a QML test asserting the handler objects).
- Theme: palette from a fixture image always satisfies the contrast pairs; a
  corrupt `scheme.json` never breaks the shell.
- Cross-module: launcher opens settings/control center/session via feature
  detection; every module closes cleanly on `Quickshell.reload()`.
- Lock: unit test the auth state machine (already WS7's) — add the reload case.

---

## 2. Documentation completion

Every guide in `docs/README.md` must be real, not "Planned":

| File | Must cover |
| --- | --- |
| `install.md` | Arch dependencies, AUR/manual install, first run, autostart, uninstall |
| `configuration.md` | Full key reference (generated from `config/default.json`), precedence, per-monitor, migrations |
| `theming.md` | Tokens, palette variants, wallpaper pipeline, app templates, reload matrix, troubleshooting |
| `keybinds.md` | Every shell keybind and IPC command, launcher prefixes, workspace/window actions |
| `architecture.md` | Process model, service ownership, data flow, reload, failure modes |
| `components.md` | UI kit API, how to add a widget/module, extension points |
| `troubleshooting.md` | Logs, `ostrich doctor`, blank bar, no theme, lock recovery, missing services |
| `rice.md` | Terminal stack, install script, live reload, uninstall |
| `CONTRIBUTING.md` (repo root) | Branch model, commits, tests, review checklist (link AGENTS) |

Rules:

- Commands are copy-pasteable and tested on a clean Arch container.
- Configuration reference is generated with a small script
  (`scripts/docs/gen-config-docs.py`) from `config/default.json` +
  `docs/config-descriptions.json` (authored by you), so it cannot drift.
- Screenshots: capture bar, launcher, control center, notifications, settings,
  lock, rice in dark and light; store under `docs/images/` (PNG, ≤ 400 KB each,
  optimised), reference from the guides.
- Every IPC command in `keybinds.md` must actually exist — verify with
  `qs ipc show` and fix the doc, not the shell, unless it is a real bug (then
  report it).

---

## 3. Packaging (`packaging/`)

- `packaging/PKGBUILD` (Arch):
  - `pkgname=ostrich-git` for `dev` and `ostrich` for releases (one PKGBUILD with
    a `pkgver()` using `VERSION` plus `git rev-list` for the git variant, or two
    files — keep it simple and documented),
  - `depends`: `quickshell`, `qt6-declarative`, `qt6-wayland`, `python`,
    `python-pillow`, `python-materialyoucolor`, `pipewire`, `wireplumber`,
    `networkmanager`, `bluez`, `upower`, `power-profiles-daemon`, `swww`
    (or `hyprpaper` as optdep), `wl-clipboard`, `grim`, `slurp`, `wf-recorder`,
    `brightnessctl`, `foot`, `fish`, `starship`, `btop`, `fastfetch`,
    `ttf-jetbrains-mono-nerd`,
  - `optdepends` for optional pieces (fuzzel, zed, micro, thunar),
  - installs to `/usr/share/ostrich/{shell,config,rice}`, CLI into
    `site-packages` or a venv-safe location, symlink `/usr/bin/ostrich`,
  - `.install` file: no automatic config overwrite; print first-run steps,
  - `check()` runs `make check` (skip smoke).
- `packaging/ostrich.desktop` + icon (`assets/ostrich.svg`, authored, MIT).
- `packaging/systemd/ostrich-shell.service` (user unit) and
  `ostrich-theme-auto.*` (owned by WS2; package them).
- `scripts/install.sh` for non-pacman installs (prefix-aware, `--dry-run`,
  backups, uninstall).

Validate with `namcap`/`shellcheck` where available; document manual steps that
cannot run in this environment.

---

## 4. Performance and reliability

Add `scripts/bench/`:

- `startup.sh`: time from `qs -p shell` launch to `reloadCompleted` (parse the
  log), 5 runs, report median. Budget: < 700 ms.
- `idle.sh`: sample `ps -o %cpu,rss` for 60 s, report average; budget < 1% CPU,
  < 200 MB RSS on two monitors (use a nested/headless compositor if available,
  otherwise document the environment).
- `interaction.sh`: measure `qs ipc call launcher toggle` → window visible via
  log timestamps; budget < 50 ms.
- Record results in `docs/performance.md` with hardware, compositor, Qt version.

Reliability pass (fix or report precisely):

- Kill each dependency (PipeWire, BlueZ, NetworkManager, UPower) and confirm the
  shell stays alive with `available: false`.
- Corrupt every state file (`config.json`, `scheme.json`, `state.json`,
  `notifications.json`, `clipboard.json`) → shell starts with defaults, logs one
  warning.
- Remove `ostrich` from PATH → shell still boots; theme/wallpaper features
  degrade with a toast.
- Reload while launcher/control center/lock open → defined behavior, no grabs.

---

## 5. Security and licence review

- `grep -ri caelestia --exclude-dir=.git .` → zero hits in source/docs (license
  attribution links are fine only if explicitly about not copying; prefer none).
- Scan for secrets, tokens, absolute `/home/<user>` paths, and `eval`/`Function`
  in QML/JS.
- Confirm no password is logged (PAM, Wi-Fi, polkit) and no config export
  contains them.
- Confirm all `Process` calls use argv lists, and every long-running process has
  a timeout/kill path.
- Confirm `LICENSE` is MIT and every asset is original or permissively licensed
  with attribution in `docs/credits.md` (create it).
- Check `pyproject.toml` dependency versions are bounded (e.g.
  `Pillow>=10,<12`, `materialyoucolor>=2,<3`) and document them.

---

## 6. Release

Only after everything above is green:

1. `VERSION` → `1.0.0` (single line, trailing newline).
2. `CHANGELOG.md`: move Unreleased into `## [1.0.0] - YYYY-MM-DD`, summarise
   every workstream, list known limitations (deferred features from
   `SUBAGENT_PLAN.md` §2).
3. `make check` + `make smoke` locally.
4. Commit `chore(release): 1.0.0` on `dev`, push.
5. PR `dev` → `test`, wait for full CI, merge.
6. PR `test` → `main`, wait for required checks, merge.
7. Confirm the release workflow tagged `v1.0.0` and published the GitHub Release
   with the changelog section.
8. Verify `Sync main into test` ran; merge `origin/test` back into `dev`.

Do not force-push, do not move tags, do not bypass protection. If a check fails,
fix forward on `dev` and repeat.

---

## 7. Acceptance checklist

- [ ] `make check` runs QML + Python tests and fails if zero tests run.
- [ ] CI green on `test` for the release commit.
- [ ] Every doc in §2 exists and matches the shipped code.
- [ ] `namcap` clean (or documented exceptions) on the PKGBUILD.
- [ ] Performance measured and within budget on the reference machine.
- [ ] Crash/degradation matrix passes.
- [ ] GPL-copy guard clean; credits complete; MIT licence intact.
- [ ] `v1.0.0` tagged and published; `test` synced back to `dev`.
- [ ] Known-limitations section lists deferred reference features with reasons.

---

## 8. Handoff report

`docs/SUBAGENT_PLAN.md` §9 plus: test counts and runtime, performance table,
package install test log, remaining known issues with severity/owner, and the
release URLs (PRs, tag, release).
