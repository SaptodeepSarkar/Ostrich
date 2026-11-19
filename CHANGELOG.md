# Changelog

All notable changes to Ostrich are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- `docs/CONTRACTS.md`: frozen v1 interfaces for runtime paths, QML singletons,
  config schema, `scheme.json`, IPC targets, CLI commands, and app templates.
- `docs/DESIGN.md`: the "Pebble" visual language — materials, design tokens,
  component kit, motion, accessibility, the shared greeter/lock "Aurora" scene,
  and shader performance rules.
- `docs/reference/style/`: three user-supplied target photos (glossy inflated
  3D clock on black) filed with provenance notes; reference only, never shipped.
- `docs/SUBAGENT_PLAN.md`: 13 workstreams, dependency waves, ownership rules,
  merge protocol, and a reference-feature map for the caelestia/glyph-rice study.
- `docs/prompts/`: self-contained implementation prompts for WS0–WS12 plus
  `LAUNCH.md` orchestration guide.
- `docs/prompts/12-greetd-greeter.md`: dedicated greetd greeter workstream
  (`cage` + Quickshell, session parsing, power/polkit, shared login surface).
- `PRD.md`: `CLI-01` (`ostrich` CLI), `TERM-01` (terminal/desktop rice),
  `THEME-04` (Pebble design system), and `GREET-01` (greetd greeter) components;
  `BAR-01`, `LOCK-01`, and `SET-01` updated for the new material.
- `AGENTS.md`: source layout extended with `cli/`, `rice/`, `packaging/`,
  `greeter/`, `docs/reference/`, and the packaged-template split.

### Changed

- `docs/CONTRACTS.md`: `ShaderEffect` restricted to `Specular.qml`, Pebble
  components and tokens added to the UI kit, greeter runtime/config/scheme
  resolution added, `appearance.pebble*` and `bar.floating` config keys added,
  design compliance added to the definition of done.
- `docs/README.md`: index now lists the contracts, design rules, reference
  photos, plan, and prompt pack.

## [0.1.0] - 2026-11-19

### Added

- Repository bootstrap: branch model (`dev`, `test`, `main`), branch protection,
  CI quality gates, release automation, and rolling `dev` releases.
- `AGENTS.md` describing the GitHub and release workflow for agents.
- `PRD.md` describing the shell components and product requirements.
