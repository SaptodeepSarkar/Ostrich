# LAUNCH — running the Ostrich workstreams with subagents

This is the operator guide. It is **not** a coding prompt. Give each subagent one
workstream prompt (`00-…md` … `12-…md`) plus this file's "Rules for every agent"
section.

---

## 0. Preconditions

- `dev` is green in CI and up to date.
- `docs/CONTRACTS.md`, `docs/DESIGN.md`, and `docs/SUBAGENT_PLAN.md` are merged.
- Quickshell is installed locally (`qs --version`), plus `qmllint`, `qmlformat`,
  `qmltestrunner`, `shellcheck`, `python3.12+`, `pytest`.
- `PATH="$HOME/.local/bin:$PATH"` so `actionlint`/`yq`/`gh` are found.
- For WS12 only: `greetd` and `cage` installed on a disposable test machine or
  VM — never test the greeter as your only login path.

```bash
cd ~/Projects/Ostrich
git switch dev && git pull --ff-only origin dev
make check
```

---

## 1. Spawn a workstream

```bash
# one worktree + branch per workstream
git worktree add ../ostrich-ws0 -b feat/ws0-core-kernel dev
cd ../ostrich-ws0
```

Then hand the agent the prompt file, for example:

> You are the WS0 agent for the Ostrich repository at
> `/home/<user>/Projects/Ostrich/../ostrich-ws0`.
> Read `AGENTS.md`, `PRD.md`, `docs/CONTRACTS.md`, `docs/DESIGN.md`,
> `docs/SUBAGENT_PLAN.md`, then execute `docs/prompts/00-core-kernel.md` exactly.
> Work only on branch `feat/ws0-core-kernel`. Do not merge or push to `dev`
> yourself; push the branch and open a PR against `dev`.

For agents that can type into a shell, the prompt already contains the branch
name, so "push your branch and open the PR" is enough.

---

## 2. Rules for every agent (paste with every prompt)

1. **One workstream only.** Do not edit files outside your owned paths. If you
   need a change elsewhere, write it in your handoff report and, if blocking,
   propose a `docs(contracts)` PR.
2. **Read before writing.** `AGENTS.md` (git/release rules), `PRD.md` (scope),
   `docs/CONTRACTS.md` (interfaces), `docs/DESIGN.md` (the "Pebble" material),
   your prompt.
3. **No copying.** caelestia and [glyph-rice](https://github.com/Nebelung-cloud/glyph-rice)
   are GPL-3.0. Do not copy or "adapt" their QML, Python, C++, assets, fonts,
   strings, dial geometry, or layouts. Reimplement from behaviour, the design
   brief, and public specs.
4. **Relative QML imports only.** `import "../../services"`, never `qs.services`,
   so `qmllint` can resolve types in CI.
5. **Services are singletons.** UI binds to them; UI never constructs them.
6. **No hardcoded** colours, absolute paths, usernames, monitor names, fonts.
   Use `Theme.c("token")`, `Paths`, `Config`.
7. **`qsTr()` every user-visible string.**
8. **`Process.command` is an argv list.** No shell interpolation; use
   `["sh","-c", …]` only when genuinely needed.
9. **Run `make check` before pushing.** Add tests for logic you write.
10. **Design compliance.** Build UI from `Pebble`, `Bubble`, `PebbleButton`,
    `GlowRing`, `DotMatrixText`, `Specular`; no ad-hoc gradients, shadows, or
    shaders; one accent per screen; honour `reducedMotion` and `pebbleQuality`.
11. **Report** using the template in `docs/SUBAGENT_PLAN.md` §9, including
    screenshots for visual work.
12. **Do not bump `VERSION`.** Do not touch CI, branch protection, or release
    workflows.
13. **Stop and ask** if a contract is ambiguous. Guessing creates merge debt.

---

## 3. Sequencing

| Step | Spawn | Wait for | Then |
| --- | --- | --- | --- |
| 1 | WS0 | C0: shell boots empty, `make check` green, PR merged | — |
| 2 | WS1, WS2, WS10 (parallel) | C1 | — |
| 3 | WS4, WS3, WS7, WS6 (parallel) | C2/C3 | merge in that order |
| 4 | WS5, WS9, WS12 (parallel) | C4 | merge WS5, WS9, then WS12 |
| 5 | WS8 | C5 | — |
| 6 | WS11 | C6 | release PR |

Do not start a wave until every dependency's PR is merged into `dev`. Starting
early means rebasing against moving contracts, which wastes more time than it
saves.

---

## 4. Merge protocol (integrator)

For each PR:

```bash
gh pr view <n> --json state,mergeable,statusCheckRollup
git switch dev && git pull --ff-only origin dev
git merge --no-ff origin/feat/wsN-<slug>   # or use gh pr merge --merge
make check
git push origin dev
```

Checklist before merging:

- [ ] Owned paths only (`git diff --stat origin/dev...HEAD`).
- [ ] `CI Success` green.
- [ ] Handoff report complete.
- [ ] New config keys in `config/default.json` and `CONTRACTS.md`.
- [ ] No GPL-derived text/assets (spot-check strings and comments; glyph-rice
      references stay in docs, never in code).
- [ ] If UI: screenshot attached and it follows `docs/DESIGN.md` (pebble
      material, one accent, shared components).
- [ ] `make check` still green after the merge, locally.
- [ ] If UI: screenshot attached.

After merging a wave, tag the checkpoint in the plan mentally (C0…C5) and update
`docs/SUBAGENT_PLAN.md` only if the plan actually changed.

---

## 5. Conflict playbook

| Conflict | Resolution |
| --- | --- |
| `shell/shell.qml` | WS0 owner resolves; module must stay a one-line instantiation |
| `components/*` | WS1 owner resolves; feature agents request a new prop instead |
| Service stub vs real service | Owning WS replaces the file wholesale, keeping the frozen signature |
| `config/default.json` | Keep both keys; alphabetical order inside their section; contract PR owns the schema |
| `CHANGELOG.md` | Keep both bullets under Unreleased; no reordering wars |
| `docs/README.md` | Last merger resolves; index entries are one line each |

If a PR has been rebased twice and still conflicts, stop and re-scope: the
workstream is probably touching shared files it does not own.

---

## 6. Review rubric (what "good" looks like)

- Reads like the surrounding code, not like a different project.
- No dead code, no commented-out experiments, no `TODO` without an owner.
- Bindings instead of imperative updates; `Connections` for singleton signals.
- Failure states are visible (service missing, command failed, file unreadable).
- Tests fail if the logic breaks, not just "file loads".
- Performance: no per-frame JS, no 1 Hz timers that could be event-driven.
- Accessibility: keyboard reachable, focus visible, `Accessible.name` where cheap.

---

## 7. End-to-end acceptance (WS11 gate)

```bash
make check
make smoke            # if Quickshell installed
make greeter-smoke    # WS12: greeter renders headless (or skips with reason)
qs -p shell           # manual pass on Hyprland
qs -p greeter         # inside cage, on a disposable VM/VT only
ostrich doctor
ostrich scheme set --dynamic --mode dark
ostrich theme apply --dry-run
ostrich theme apply
```

Manual matrix: 1 monitor and 2 monitors, dark and light, wallpaper change,
launcher/calculator, notification with action, OSD volume, control center toggles,
lock/unlock, screenshot, clipboard, settings edit, shell reload, greeter login →
session → lock → unlock, greeter wrong-password/backoff, greeter VT escape.

---

## 8. Quick reference

- Contracts: `docs/CONTRACTS.md`
- Design language: `docs/DESIGN.md`
- Plan: `docs/SUBAGENT_PLAN.md`
- Visual references: `docs/reference/style/`
- Branch rules: `AGENTS.md`
- Scope: `PRD.md`
- Run: `qs -p shell` · greeter: `qs -p greeter` (inside cage) · logs `qs log -f` ·
  IPC `qs ipc show`
- CI locally: `make check` (`PATH="$HOME/.local/bin:$PATH"`)
