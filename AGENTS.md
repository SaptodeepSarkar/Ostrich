# AGENTS.md

Instructions for AI agents (and humans) working in the Ostrich repository.
Read this file before touching git, branches, versions, or the GitHub settings.

---

## 1. Golden rules

1. **Work on `dev`.** Every feature, fix, refactor, and docs change is committed
   and pushed to `dev` first.
2. **Never push directly to `test` or `main`.** Both are protected and accept
   changes only through pull requests.
3. **Never force-push a shared branch.** `dev`, `test`, and `main` reject it.
   Use `git revert` for mistakes that are already pushed.
4. **Never bypass branch protection** (`gh pr merge --admin`, admin overrides, or
   temporarily disabling protection) without explicit human approval.
5. **Only release PRs bump `VERSION`.** Do not bump the version for a normal
   feature or fix.
6. **Run `make check` before every push.** CI runs the same scripts.
7. **Do not modify CI, branch protection, or repository settings** unless the
   task explicitly asks for it.
8. **`PRD.md` is the source of truth for scope.** Update it in the same PR that
   changes scope.

---

## 2. Project summary

Ostrich is a QML / [Quickshell](https://quickshell.org/) desktop shell ("rice")
for Arch Linux on Wayland (Hyprland is the primary compositor). It is currently
at the scaffolding stage: branches, CI, release automation, and documentation
exist; shell components do not.

Planned source layout (create directories only when code lands):

| Path | Contents |
| --- | --- |
| `shell/` | Quickshell entry point (`shell/shell.qml`), services, components, modules. |
| `cli/` | Python `ostrich` CLI: wallpaper, palette, templates, auto-theme, IPC, doctor. |
| `config/` | Default configuration, keybinds, compositor snippets, examples. |
| `rice/` | Terminal/desktop rice configs (foot, fish, starship, btop, fastfetch, micro). |
| `themes/` | Generated palettes and theme notes; packaged templates live in `cli/`. |
| `packaging/` | PKGBUILD, desktop entry, systemd user units, installers. |
| `scripts/` | Runtime helper scripts (not CI scripts). |
| `scripts/ci/` | CI and quality-gate scripts (owned by maintainers). |
| `tests/` | Qt Quick Test suites (`tests/**/tst_*.qml`) and mocks. |
| `docs/` | Long-form documentation, contracts, and subagent prompts. |
| `PRD.md` | Product requirements and component catalog. |
| `VERSION` | Single source of truth for the version. |
| `CHANGELOG.md` | Keep a Changelog history. |

---

## 3. Branch model

| Branch | Role | Who writes to it | Protection |
| --- | --- | --- | --- |
| `dev` | Integration / working branch. Rolling prereleases are published from it. | Agents and maintainers push directly. | No force-push, no deletion. |
| `test` | Release candidate. The full CI suite is authoritative here. | Only `dev -> test` pull requests. Bot may fast-forward `main` back into it. | Required checks, no force-push, no deletion. |
| `main` | Released code only. Every merge is tagged `vX.Y.Z`. | Only `test -> main` pull requests. | Required checks, up-to-date branch, conversation resolution, no force-push, no deletion. |

### Promotion flow

```
feature commits ──push──> dev ──PR──> test ──PR──> main ──tag──> vX.Y.Z
                            │           │            │
                            │           │            └─ Release workflow publishes GitHub Release
                            │           └─ CI must be green before merge
                            └─ Rolling workflow refreshes the `rolling` prerelease
```

Only these pull request directions are allowed by CI:

- `dev` -> `test`
- `test` -> `main`

A PR in any other direction into `test` or `main` fails the `validate` job.

Short-lived feature branches are optional. If you use one, cut it from `dev`,
open the PR against `dev`, and delete the branch after merge.

---

## 4. Versioning

- Format: **SemVer** `MAJOR.MINOR.PATCH`, stored in `VERSION` as a single line
  with a trailing newline. No leading `v` in the file; tags use `vX.Y.Z`.
- `MAJOR`: breaking changes to configuration, theming tokens, or IPC.
- `MINOR`: new components, services, or user-visible features.
- `PATCH`: fixes, performance work, documentation.
- `CHANGELOG.md` follows [Keep a Changelog](https://keepachangelog.com/): add an
  entry under `## [Unreleased]` while working, and move it into
  `## [X.Y.Z] - YYYY-MM-DD` in the release commit.
- There is exactly **one** version bump per release PR.

---

## 5. Release runbook

The release commit is the only commit that changes `VERSION`.

```bash
# 1. Start from an up-to-date dev
git switch dev
git pull --ff-only origin dev

# 2. Prepare the release commit
#    - bump VERSION (for example 1.1.0 -> 1.2.0)
#    - rename the Unreleased CHANGELOG section to [1.2.0] - YYYY-MM-DD
make check

git add VERSION CHANGELOG.md
git commit -m "chore(release): 1.2.0"
git push origin dev

# 3. Promote to test (CI runs the full suite on the version)
gh pr create --base test --head dev \
  --title "release: 1.2.0" \
  --body "Promote 1.2.0 to test. Full CI required before merge."

# 4. After every required check is green on the PR
gh pr merge --merge

# 5. Promote to main (only after test is green)
gh pr create --base main --head test \
  --title "release: 1.2.0" \
  --body "Release 1.2.0. test CI is green."

# 6. After every required check is green on the PR
gh pr merge --merge
```

Automation that follows:

1. `Release` workflow runs on the new `main` commit, tags `v1.2.0`, and creates a
   GitHub Release using the `CHANGELOG.md` section.
2. `Sync main into test` merges `main` back into `test` so the next release PR is
   based on released code.
3. Before the next release, merge `test` into `dev` to pick up the sync merge:
   `git switch dev && git merge --no-edit origin/test && git push origin dev`.

Never move or reuse a published tag. If a release is wrong, ship a new PATCH.

---

## 6. CI checks

Workflow: `.github/workflows/ci.yml`. It runs on pushes to `dev`, `test`, and
`main`, and on pull requests targeting `test` and `main`.

| Check | What it does | Local command |
| --- | --- | --- |
| `validate` | Required files, `VERSION` SemVer format, `CHANGELOG` entry. | `make validate` |
| `validate` (PR only) | Enforces `dev -> test` / `test -> main`, version bump, changelog entry. | `BASE_BRANCH=test HEAD_BRANCH=dev BASE_SHA=<sha> bash scripts/ci/branch-flow.sh` |
| `lint` | `qmllint`, `shellcheck`, optional `qmlformat` diff. | `make lint` |
| `qml-compile` | Parses every QML file, type-checks Quickshell-independent files. | `make compile` |
| `test` | Qt Quick Test suites in `tests/**/tst_*.qml`. | `make test` |
| `review` | Whitespace, EOF newlines, conflict markers, large files, secrets. | `make review` |
| `CI Success` | Aggregates the required jobs; this is the check branch protection requires. | `make check` |
| `smoke` | Opt-in: builds Quickshell and launches the shell headless. | `make smoke` |

Notes:

- `smoke` only runs when the repository variable
  `ENABLE_QUICKSHELL_SMOKE=true` is set (AUR builds are slow). Keep it opt-in
  until packaging exists.
- `FORMAT_STRICT=1` (repository variable or local env) turns formatting drift into
  a failure and enables the `qmlformat` diff in `lint`.
- CI runs inside an `archlinux:base-devel` container so tool behavior matches the
  target distribution. QML tools may live in `/usr/lib/qt6/bin`; use `qt_bin`
  from `scripts/ci/lib.sh` instead of hardcoding paths.

---

## 7. Branch protection (what "protected" means)

- `main`: pull request required, all checks in the table above required, branch
  must be up to date, conversations resolved, no force-push, no deletion,
  protections apply to admins.
- `test`: pull requests require all checks; direct pushes by the sync bot are
  allowed; no force-push, no deletion.
- `dev`: no PR requirement; no force-push, no deletion.

Re-apply the settings (idempotent):

```bash
make protect
# or: scripts/setup-branch-protection.sh owner/repo
```

Inspect the current settings:

```bash
gh api repos/{owner}/{repo}/branches/main/protection
gh api repos/{owner}/{repo}/branches/test/protection
gh api repos/{owner}/{repo}/branches/dev/protection
```

---

## 8. Commit and PR conventions

Use Conventional Commits:

| Type | Use |
| --- | --- |
| `feat` | New component or user-visible behavior |
| `fix` | Bug fix |
| `refactor` | Internal change without behavior change |
| `perf` | Performance improvement |
| `docs` | Documentation only |
| `test` | Tests only |
| `ci` | Workflows and tooling |
| `chore` | Maintenance, including `chore(release): X.Y.Z` |

Rules:

- One logical concern per commit; keep the diff reviewable.
- Reference the PRD component ID in the commit body when relevant
  (for example `CMP-LAUNCHER`).
- Pull requests must explain what changed, why, and how it was verified.
- Behavior changes need tests; visual changes need a screenshot or recording.
- Do not mix refactors with features.
- Do not commit generated files (`*.qmlc`, build output, caches).

---

## 9. Development rules for agents

- Read `PRD.md` before implementing a component. If the requirement is missing
  or contradictory, update the PRD or ask, do not invent scope silently.
- Prefer Quickshell's built-in services (`Pipewire`, `Bluetooth`, `UPower`,
  `Networking`, `Mpris`, `Notifications`, `SystemTray`, `Hyprland`) over shelling
  out to external tools. Use `Process` only when no service exists.
- Keep UI code reactive: drive views from properties/services, do not poll in
  bindings.
- Never block the GUI thread with synchronous process calls.
- All user-visible strings must be translatable (`qsTr`) once the shell exists.
- No hardcoded absolute paths, usernames, colors, or monitor names. Use theme
  tokens and config values.
- Tests belong in `tests/` and must run headless (`QT_QPA_PLATFORM=offscreen`).
- Performance budget: see `PRD.md` section "Non-functional requirements". Do not
  merge known regressions.

---

## 10. Troubleshooting

| Symptom | Cause / fix |
| --- | --- |
| `VERSION was not bumped` | Add a version bump and a matching CHANGELOG section in the release PR. |
| `only 'dev' may be merged into 'test'` | Open the PR from `dev`; never from a feature branch. |
| `Branch is out of date` | Merge the target into your source, e.g. `git switch dev && git merge --no-edit origin/test`. |
| `CI Success` never appears | A required job was skipped or the workflow did not trigger; push a new commit. |
| Tag `vX.Y.Z` exists but the release is wrong | Do not move the tag; ship the next PATCH version. |
| Bot sync conflict on `test` | Resolve manually on a branch and PR into `test`, then re-run sync. |
| `qmllint` cannot find `Quickshell` | Expected outside the smoke job; set `QUICKSHELL_IMPORT_PATH` or run `make smoke` with Quickshell installed. |

---

## 11. Repository settings applied at bootstrap

- Default branch: `main`.
- Merge strategy: merge commits only (no squash, no rebase); permanent branches
  are never auto-deleted.
- Auto-merge and "update branch" enabled.
- Dependabot updates GitHub Actions weekly, targeting `dev`.
- CODEOWNERS: every file is owned by the maintainer listed in
  `.github/CODEOWNERS`.
