# WS10 — Terminal and desktop rice

**Branch:** `feat/ws10-rice` · **Worktree:** `../ostrich-ws10`
**Wave:** 1 · **Depends on:** `CONTRACTS.md` §6/§9 (token names) ·
**Blocks:** nothing (WS2 consumes the templates)
**Owns:** `rice/`, `config/hypr/`, `scripts/rice/`, and
`cli/src/ostrich/data/templates/rice/*` (template content only)

---

## Mission

Make Ostrich a *rice*, not just a bar: a terminal stack (foot + fish + starship),
fastfetch, btop, micro, a Hyprland snippet with keybinds, and the install/reload
scripts that put them in place — all driven by the same colour tokens the shell
uses. Nothing here may hardcode colours; everything reads the generated theme.

Coordinate with WS2: it owns the template **engine** and `data/manifest.json`;
you own the template **content** under `data/templates/rice/` plus the static
configs in `rice/`.

---

## 1. Colour contract

- Tokens come from `scheme.json` (`CONTRACTS.md` §6): `term0..term15`,
  `surface`, `onSurface`, `primary`, `secondary`, `tertiary`, `error`, `outline`,
  `surfaceContainer*`.
- Template placeholders: `{{ term0 }}` … `{{ term15 }}`, `{{ primary }}`,
  `{{ surface }}`, `{{ onSurface }}`, `{{ outline }}`, `{{ mode }}`,
  `{{ scheme_name }}`, `{{ wallpaper }}`. `{{ token_raw }}` is the same value
  without `#`.
- Static files in `rice/` must **include** generated files, never embed colours:

```ini
# foot.ini
include=~/.config/foot/ostrich.ini
```

- If a program cannot include another file (starship, fastfetch), the whole file
  is a rendered template under `data/templates/rice/` and the static `rice/`
  copy is documentation only.

---

## 2. foot (`rice/foot/foot.ini` + `data/templates/rice/foot.ini`)

Static `foot.ini`:

- `include=~/.config/foot/ostrich.ini` (generated colours),
- font: `JetBrainsMono Nerd Font:size=11` with a documented fallback list,
- `pad=12x12`, `dpi-aware=no` (Wayland scaling handled by the compositor),
- scrollback 10000, `selection-target=clipboard`, `underline-offset`,
  `box-drawing` sane defaults,
- `[cursor]` style/blink from config-independent defaults,
- `[key-bindings]` search/scrollback/clipboard keys (no copying from reference),
- `[colors]` **only** `alpha`/`selection` placeholders that do not fight the
  include; keep colour values out.

Template `data/templates/rice/foot.ini` (generated file `~/.config/foot/ostrich.ini`):

- `[colors]` dark/light block with `foreground={{ term7 }}`,
  `background={{ term0 }}`, `regular0..7={{ term0..7 }}`,
  `bright0..7={{ term8..15 }}`, `selection-foreground/background`, `cursor`.
- `[cursor] color={{ primary }} {{ surface }}`.
- Must be valid foot INI; no trailing placeholder.

---

## 3. fish (`rice/fish/`)

```
rice/fish/config.fish
rice/fish/conf.d/ostrich.fish
rice/fish/functions/{fish_prompt.fish,mkcd.fish,extract.fish,ports.fish,ostrich-theme-reload.fish}
rice/fish/completions/ostrich.fish
```

- `config.fish`: interactive-only guards, `starship init fish | source` when
  starship exists, `zoxide init fish` when installed, `direnv hook fish` when
  installed, PATH additions guarded by `test -d`.
- `conf.d/ostrich.fish`: sources
  `~/.config/fish/conf.d/ostrich-theme.fish` **if it exists**, exports
  `OSTRICH_THEME_MODE`, sets `fish_greeting` to a one-line fastfetch hint.
- Functions (own implementations):
  - `mkcd` — create + cd, error on empty,
  - `extract` — tar/zip/7z/xz/zst by extension, refuses unknown,
  - `ports` — listening sockets via `ss -tulpn` (argv),
  - `ostrich-theme-reload` — `source` the generated theme file and re-exec
    starship prompt in the current shell (this is the live-reload story),
  - `fish_prompt` — only used when starship is missing; simple two-line prompt
    using `set_color` with the generated `OSTRICH_*` env vars.
- Abbreviations: `gst`, `gd`, `ll`/`la` (eza when available), `..`/`...`,
  `ff` → `fastfetch --config ostrich`, `ost` → `ostrich`. No destructive aliases
  (`rm -rf`, `mkfs`) — ever.
- Completions for `ostrich` subcommands (static, matches `CONTRACTS.md` §8).

---

## 4. starship (`data/templates/rice/starship.toml`)

- `palette = "ostrich"` with a `[palettes.ostrich]` block mapping every token
  used (`primary`, `secondary`, `tertiary`, `error`, `surface`, `onSurface`,
  `outline`, `term1..term6`).
- Prompt: directory (truncated, repo-aware), git status/branch, language
  versions (node/python/rust/go, only when present), duration, time, cmd
  duration, battery (when available), host only over SSH, `$status`/`$cmd_duration`
  styling. Nerd Font symbols with ASCII fallbacks documented.
- No emoji-only segments, no network calls, no `shell` command substitution in
  segments.
- Must render inside a 100-column terminal without wrapping the first line.

---

## 5. btop, fastfetch, micro, Thunar

- `rice/btop/btop.conf` (static: `color_theme = "ostrich"`, update ms 1000,
  vim keys, rounded corners) + `data/templates/rice/btop.theme`
  (`theme[main_bg]="{{ surface }}"` etc., full btop theme variable set).
- `data/templates/rice/fastfetch.jsonc` (colours for keys/logo, modules: title,
  os, kernel, uptime, packages, shell, wm, terminal, cpu, gpu, memory, disk,
  local ip, battery; `--logo` optional). Provide `rice/fastfetch/ostrich.txt`
  with an original small ASCII ostrich (≤ 10 lines, authored by you, not copied).
- `data/templates/rice/micro.micro` (micro colourscheme) + `rice/micro/settings.json`
  (`colorscheme: "ostrich"`, `syntax: true`, `autoindent: true`).
- `rice/thunar/` optional: `uca.xml` custom actions (open terminal here,
  copy path) — no theme colours, GTK handles those.

---

## 6. Hyprland (`config/hypr/ostrich.conf`)

A snippet the user `source`s from their `hyprland.conf` — never a replacement
config:

- `env = QT_QPA_PLATFORM,wayland`, `XCURSOR_SIZE`, `HYPRCURSOR_SIZE`,
  `GDK_SCALE` note (commented), `XCURSOR_THEME` placeholder comment.
- `exec-once = ostrich shell start` (or `qs -p /usr/share/ostrich/shell -d`),
  `exec-once = ostrich wallpaper restore`.
- `source = ~/.config/hypr/ostrich-colors.conf` (generated by WS2),
  `source = ~/.config/ostrich/keybinds.conf` (WS8, optional).
- Keybinds using `global` shortcuts where Ostrich registers them, otherwise
  `exec, ostrich ipc call …`:
  launcher `SUPER, Space`; control center `SUPER, C`; notifications center
  `SUPER, N`; lock `SUPER+ALT, L`; session `SUPER+SHIFT, E`; screenshot region
  `PRINT`; full `SHIFT+PRINT`; clipboard `SUPER, V`; emoji `SUPER, period`;
  record toggle `SUPER+ALT, R`; settings `SUPER, comma`; overview `SUPER, Tab`.
- Layer rules so the shell's overlays behave: `layerrule = noanim, launcher`,
  `dimaround`, `blur` only where the shell requests it — document each rule.
- Window rules for the settings window (`float`, `size`, `center`).
- No compositor-wide colour or decoration settings; those belong to the user.

---

## 7. Scripts (`scripts/rice/`)

- `install.sh`: copies/symlinks `rice/` files into `$XDG_CONFIG_HOME` with
  `--dry-run`, `--force`, timestamped backups, and a summary; never overwrites
  without `--force`; `shellcheck` clean (`set -euo pipefail`).
- `verify.sh`: asserts every token placeholder used by the templates exists in a
  sample `scheme.json`; renders templates through `ostrich.templates` into a temp
  dir (if the CLI is importable) and fails on leftover `{{`; validates fish
  syntax (`fish -n`), foot config (`foot --check-config` when available), TOML
  (`python -c 'import tomllib…'`), JSON/JSONC (strip comments safely).
- Both scripts are runtime helpers, not CI scripts.

---

## 8. Docs

- `docs/rice.md`: what gets installed, screenshots/recordings, keybind table,
  how themes reach each app, live-reload matrix (what reloads instantly vs. on
  new shell), uninstall steps.
- `docs/terminal.md`: foot/fish/starship setup, font requirements, troubleshooting
  (missing glyphs, wrong colours after theme change).
- `config/examples/` is WS11's; do not touch.
- Update `CHANGELOG.md` Unreleased and `docs/README.md`.

---

## 9. Tests / checks

- `shellcheck` on every script.
- `fish -n` on every `.fish` file (skip with a warning if fish is absent).
- `python -c "import tomllib; tomllib.load(open('…','rb'))"` for TOML.
- `scripts/rice/verify.sh` with a fixture scheme (`rice/tests/scheme.sample.json`)
  containing every token; assert no unresolved placeholders.
- `python -m json.tool` on JSON templates (JSONC: strip `//` comments in the
  verifier).
- Manual: run foot with the generated include, start fish, run fastfetch/btop,
  open micro, `hyprctl reload` with the snippet sourced.

---

## 10. Constraints

- No copied config, prompt, logo, or keybind table from the reference repos.
- No hardcoded colours outside `data/templates/rice/` placeholders.
- No destructive shell aliases, no `sudo` inside functions, no network calls in
  prompts.
- Do not edit the template engine (`cli/src/ostrich/templates.py`), the manifest,
  or any QML. If a template needs a new placeholder, request it via a contract
  PR.
- Keep every file valid on a fresh Arch install with only the documented
  packages.

---

## 11. Acceptance checklist

- [ ] `ostrich theme apply` renders foot/fish/starship/btop/fastfetch/micro with
      no leftover placeholders.
- [ ] Theme change updates a running foot via `SIGUSR1`; fish reloads with
      `ostrich-theme-reload`; new shells get the palette automatically.
- [ ] starship prompt renders correctly in dark and light, narrow and wide.
- [ ] fastfetch logo and colours look intentional in both modes.
- [ ] `config/hypr/ostrich.conf` sourced into a test Hyprland config loads without
      errors and every bind calls an existing IPC target.
- [ ] `scripts/rice/install.sh --dry-run` lists changes and writes nothing.
- [ ] `verify.sh` green; screenshots of terminal stack in dark and light.

---

## 12. Handoff report

`docs/SUBAGENT_PLAN.md` §9 plus: the exact template IDs/paths WS2 must add to
`manifest.json`, the token list each template uses, reload hooks, and the keybind
table with IPC targets (so WS11 can test them).
