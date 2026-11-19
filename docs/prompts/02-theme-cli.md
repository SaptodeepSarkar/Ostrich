# WS2 — Theme engine, wallpaper CLI, background

**Branch:** `feat/ws2-theme-cli` · **Worktree:** `../ostrich-ws2`
**Wave:** 1 · **Depends on:** `CONTRACTS.md` only (WS0 may still be merging) ·
**Blocks:** WS8 (theme settings), WS10 (rice tokens)
**Owns:** `cli/`, `shell/modules/background/`, `themes/README.md`

---

## Mission

Build the other half of the theming pipeline: a Python CLI that extracts a
Material 3 palette from a wallpaper, writes `$STATE/scheme.json`, sets the
wallpaper through `swww`/`hyprpaper`, and renders theme files for applications —
plus the shell's background layer that displays the current wallpaper.

The shell side (`Theme.qml`, `Wallpaper.qml`) is WS0's. Code against
`CONTRACTS.md` §2, §6, §8, §9. This is the single most failure-prone part of the
product: it must be deterministic, atomic, and safe to run repeatedly.

---

## 1. CLI package

```
cli/
├── pyproject.toml
├── README.md
├── src/ostrich/
│   ├── __init__.py
│   ├── __main__.py
│   ├── cli.py            # argparse, exit codes
│   ├── paths.py          # XDG resolution, mirrors Paths.qml
│   ├── config.py         # read config.json, defaults, theme.apps gates
│   ├── scheme.py         # palette generation + scheme.json
│   ├── wallpaper.py      # backends, smart crop, state pointer
│   ├── templates.py      # manifest, render, atomic apply, backups
│   ├── auto.py           # light/dark scheduler
│   ├── ipc.py            # `qs ipc call` wrapper
│   ├── doctor.py         # environment report
│   └── data/
│       ├── schemes/*.json
│       ├── templates/*
│       └── manifest.json
└── tests/
```

- Python ≥ 3.12, deps `Pillow`, `materialyoucolor`; dev extras `pytest`, `ruff`.
- Console script `ostrich = ostrich.cli:main`.
- No root. No writes outside XDG dirs (except manifest targets the user
  configured).
- `--json` on every read command; stable keys.

### 1.1 `paths.py`

Mirror `CONTRACTS.md` §2 exactly, including env overrides. Export:

```python
config_dir, state_dir, data_dir, cache_dir, config_file, scheme_file,
wallpaper_pointer, state_file, recordings_dir
```

Add `wallpapers_dir(config)` reading `paths.wallpaperDir`.

### 1.2 `config.py`

- Load `$STATE/../config.json`? No: `config_dir / "config.json"`.
- Missing → built-in defaults (keep a small dict, the full canonical defaults
  live in `config/default.json`; `doctor` warns if they diverge).
- Dot-path getter, same semantics as `Config.value`.
- `theme.apps.<id>` gates template application; missing key = enabled only for
  the safe defaults in `CONTRACTS.md` §5.
- Never rewrite the user's config except for `theme.auto.*` keys you own, and
  only atomically.

### 1.3 `scheme.py` — palette generation

Entry points:

```python
def generate_from_image(path, variant="tonalspot", mode="dark", contrast=0) -> dict
def palette_from_seed(hex_color, variant, mode, contrast) -> dict
def load_static(name, flavour, mode) -> dict
def write_scheme(palette, meta) -> Path
```

- Use `materialyoucolor`:
  `SchemeTonalSpot` / `SchemeVibrant` / `SchemeExpressive` / `SchemeFidelity` /
  `SchemeContent` / `SchemeNeutral` / `SchemeMonochrome` / `SchemeRainbow` /
  `SchemeFruitSalad` (argb seed, `is_dark`, contrast level).
- Emit tokens via `MaterialDynamicColors.<name>.getArgb(scheme)` for the full
  token list in `CONTRACTS.md` §6, plus `term0..term15`.
- Terminal mapping (document it in `docs/theming.md`):
  `term0=surface`, `term1=error`, `term2=tertiary`, `term3=primary`,
  `term4=secondary`, `term5=primaryContainer`, `term6=tertiaryContainer`,
  `term7=onSurfaceVariant`, `term8=outline`, `term9..14` derived from the
  primary/secondary/tertiary families with a contrast adjustment, `term15=onSurface`.
  Ensure every `termN` pair used by foot/fish is readable on `term0`.
- Output dict keys are camelCase tokens with `#rrggbb` strings, `version: 1`,
  `mode`, `variant`, `name` (`dynamic` for wallpaper, else the static scheme
  name), `flavour`, `source` (absolute wallpaper path or `"static"`),
  `generatedAt` (UTC ISO-8601 seconds).
- Wallpaper extraction: open with Pillow, convert RGB, resize to ≤ 128 px,
  quantize to 8–16 colors, ignore near-black/near-white/swatch pixels, pick the
  most frequent remaining colour weighted by saturation; if the image is
  monochrome, use the mean colour. Deterministic: no random sampling.
- Contrast guard: compute WCAG contrast for `onPrimary/primary`,
  `onSurface/surface`, `onError/error`, `onSecondaryContainer/secondaryContainer`,
  `onTertiary/tertiary`. If a pair is < 4.5, nudge the foreground toward
  `#000000`/`#ffffff` in 2% steps (max 20 iterations) and record a warning.
  If still failing, fall back to the built-in palette for that mode.
- Static schemes: JSON files in `data/schemes/<name>.json`:

```json
{
  "name": "ostrich",
  "flavours": {
    "default": { "dark": { "primary": "#a6c8ff", "...": "..." }, "light": { "...": "..." } }
  }
}
```

Author at least four original schemes (`ostrich`, `graphite`, `moss`, `sand`).
Do **not** copy palette files from the reference repository. Community palettes
(Catppuccin/Nord/Gruvbox) may be added only if their licence is permissive **and**
attribution is in `docs/theming.md`; prefer original palettes.

`write_scheme` writes atomically (temp file in the same dir + `os.replace`),
mode `0644`, trailing newline.

### 1.4 `wallpaper.py`

- Backend detection: `swww` (`swww img <path> --transition-type …`), then
  `hyprpaper` (`hyprctl hyprpaper preload/wallpaper`), then `static` (only update
  the pointer, the shell background layer shows it).
- `set(path, smart=True, apply=True)`:
  - validate the file exists and is a supported image (Pillow open, close),
  - optionally run the smart-crop step (choose fit mode from aspect ratio; for
    swww pass `--resize crop`; keep it simple and documented),
  - call the backend with an argv list and a 15 s timeout,
  - write `$STATE/wallpaper/path.txt` atomically,
  - unless `--no-apply`, regenerate the dynamic scheme and apply app themes.
- `random()` picks from `wallpapers_dir` (recursive, image extensions only).
- `list()` returns `[{path, name, category}]`, `category` = first directory
  below the wallpaper root, sorted, `--json` stable.
- `get()` prints the pointer or empty string with exit 0.

### 1.5 `templates.py`

Manifest (`data/manifest.json`) exactly as `CONTRACTS.md` §9. WS10 supplies the
rice template **content** under `data/templates/rice/` (`foot.ini`,
`starship.toml`, `btop.theme`, `fastfetch.jsonc`, `micro.micro`); you own the
engine and the manifest entries, do not rewrite those files. Ship templates for
at least:

| id | target | notes |
| --- | --- | --- |
| `gtk3` | `~/.config/gtk-3.0/gtk.css` | colours + `prefer-dark` hint |
| `gtk4` | `~/.config/gtk-4.0/gtk.css` | same tokens |
| `qt6ct` | `~/.config/qt6ct/colors/ostrich.conf` | `[ColorScheme]` + palette |
| `foot` | `~/.config/foot/ostrich.ini` | `[colors]` + `[cursor]` (`templates/rice/foot.ini`) |
| `fish` | `~/.config/fish/conf.d/ostrich-theme.fish` | exported `OSTRICH_*` colour vars (`templates/rice/fish.fish`) |
| `btop` | `~/.config/btop/themes/ostrich.theme` | btop theme syntax (`templates/rice/btop.theme`) |
| `starship` | `~/.config/starship.toml` | whole file, palette section (`templates/rice/starship.toml`) |
| `fastfetch` | `~/.config/fastfetch/ostrich.jsonc` | logo colours (`templates/rice/fastfetch.jsonc`) |
| `fuzzel` | `~/.config/fuzzel/ostrich.ini` | colours + border |
| `micro` | `~/.config/micro/colorschemes/ostrich.micro` | syntax colours (`templates/rice/micro.micro`) |
| `zed` | `~/.config/zed/themes/ostrich.json` | best-effort, disabled by default |
| `vscode` | `~/.config/Code/User/settings.json` | **merge** `workbench.colorCustomizations`, never overwrite; disabled by default |

Rules:

- Placeholders: `{{ token }}`, `{{ token_raw }}`, `{{ mode }}`,
  `{{ scheme_name }}`, `{{ flavour }}`, `{{ variant }}`, `{{ wallpaper }}`.
  Unknown placeholder → warning + skip that target (never write `{{ … }}`).
- Whole-file targets are rendered and replaced atomically with `<target>.bak`
  (keep one backup, no timestamps).
- JSON targets (`vscode`) merge keys instead of replacing.
- `--dry-run` prints `would write <target> (<id>)` and exits 0 without touching
  anything (also skip reload commands).
- Idempotent: compare rendered text with the current file; skip identical writes
  and skip reload hooks.
- `reload` argv arrays run sequentially with a 5 s timeout; failures are warnings.
- Missing template file or unwritable target → warn and continue; final exit code
  is 4 only if every requested target failed.

### 1.6 `auto.py`

- `enable(light_at, dark_at)` writes `~/.config/systemd/user/ostrich-theme-auto.service`
  and `.timer` (OnCalendar twice daily plus `Persistent=true`), runs
  `systemctl --user daemon-reload` and `enable --now`.
- The service runs `ostrich scheme set --mode <resolved>` with `--no-apply`
  unless app theming is enabled.
- `disable()` stops/disables and removes the units.
- If systemd is unavailable, fall back to a `--daemon` loop (sleep until next
  boundary, no busy polling) and document it.
- `--light-at/--dark-at` persist into `config.json` under `theme.auto`.

### 1.7 `doctor.py`

`ostrich doctor [--json]` reports: Python version, CLI path, deps
(`PIL`, `materialyoucolor`), `qs` presence/version, wallpaper backend, scheme
file validity, config parse errors, template target writability, missing
optional apps. Never fails the process for missing optional tools (exit 0;
exit 2 only for a broken config/scheme).

### 1.8 `cli.py`

Commands and exit codes exactly as `CONTRACTS.md` §8. `ostrich ipc` forwards to
`qs ipc call <target> <fn> …` with an argv list. `--help` is the documentation
source of truth; keep it terse.

---

## 2. Background module

`shell/modules/background/Background.qml` (+ `Wallpaper.qml`, `Crossfade.qml` if
useful):

- One `WlrLayershell` per screen via `Variants { model: Quickshell.screens }`,
  `layer: WlrLayer.Background`, anchors on all edges, `exclusionMode: Ignore`,
  `color: "transparent"`, no keyboard focus, empty `mask` (never intercept
  clicks).
- Displays `Wallpaper.current` with `Image { fillMode: Image.PreserveAspectCrop }`
  and a 250 ms crossfade on change (two images, opacity `Behavior`; disable when
  reduced motion is on).
- Handles missing file (solid `Theme.c("surface")`), non-image, and per-monitor
  different wallpapers if `Wallpaper` exposes them later — otherwise the same
  image on every screen.
- `Config.value("background.clock", false)` renders a large clock + date and
  `Config.value("background.mode", "layer")`: `"external"` renders nothing
  (swww/hyprpaper draws), `"layer"` draws the image. **Add this config section
  via a `docs(contracts)` PR first**: `background: { mode: "layer",
  crossfadeMs: 250, clock: false }` in `config/default.json` and `CONTRACTS.md`
  §5.
- Does not own `Theme`/`Wallpaper` code; does not call `ostrich` itself.
- No polling; bind to `Wallpaper.changed`.

---

## 3. Documentation

- `docs/theming.md`: pipeline diagram, token list, variant table, terminal
  mapping, contrast rules, template authoring, how to add a scheme, how reload
  hooks work, permissions/backups.
- `docs/wallpapers.md`: backends, smart crop, per-monitor notes, state pointer.
- `cli/README.md`: install (`uv tool install .` or `pipx`), commands, exit codes.
- `themes/README.md`: explains that packaged schemes/templates live in
  `cli/src/ostrich/data/` and how to override them in `~/.config/ostrich/`.
- `CHANGELOG.md` Unreleased entries; `docs/README.md` index.

---

## 4. Tests (pytest)

- `test_paths.py`: env overrides, XDG defaults.
- `test_scheme.py`: deterministic palette from a generated 64×64 PNG fixture;
  every required token present and valid `#rrggbb`; contrast guard triggers on a
  pathological image; static scheme load; mode/variant validation; random seed
  rejection (must not use randomness).
- `test_wallpaper.py`: pointer written atomically, backend selection with mocked
  `subprocess.run`, `--no-apply` skips scheme, invalid image fails with exit 3.
- `test_templates.py`: render replaces all placeholders; unknown placeholder
  skips target; dry-run writes nothing; identical content is not rewritten;
  `.bak` created once; vscode merge preserves other keys.
- `test_auto.py`: unit files contain the expected times; disable removes them.
- `test_cli.py`: exit codes 0/1/2/3/4, `--json` shape.
- Fixtures generate images programmatically; never commit binary blobs.

---

## 5. Constraints

- Never invoke a shell for interpolation; argv lists only.
- Never log secrets (Wi-Fi keys are not your concern; still never dump config).
- Atomic writes everywhere; `os.replace` in the same filesystem.
- The CLI must work with the shell not running (`ipc` commands excepted).
- Keep runtime < 300 ms for `scheme set --dynamic` on a 4K wallpaper (resize
  before quantizing).
- Do not edit `shell/services/*`, `shell/components/*`, or `shell/shell.qml`.

---

## 6. Acceptance checklist

- [ ] `ostrich scheme set --dynamic --mode dark` from a real wallpaper writes a
      complete `scheme.json`; `Theme` in the running shell updates.
- [ ] `ostrich scheme set --name ostrich --flavour default --mode light` works.
- [ ] `ostrich wallpaper set <img>` updates the pointer and (when enabled) the
      compositor wallpaper.
- [ ] `ostrich theme apply --dry-run` writes nothing; real apply updates foot and
      GTK at minimum, with `.bak` files.
- [ ] `ostrich theme apply` twice in a row performs no writes the second time.
- [ ] `ostrich doctor` reports cleanly on a machine without optional apps.
- [ ] `Background` renders wallpaper per monitor and never captures input.
- [ ] `pytest` green; `make check` green.
- [ ] Screenshot: two monitors, dark and light, wallpaper crossfade.

---

## 7. Handoff report

Use `docs/SUBAGENT_PLAN.md` §9, plus:

- the exact `scheme.json` you emit (one sample),
- terminal mapping table,
- list of shipped templates and their targets,
- how `theme.apps.*` gating works,
- measured `scheme set --dynamic` runtime on a 4K image,
- any contract amendment PRs you opened.
