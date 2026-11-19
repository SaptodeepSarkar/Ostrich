# Changelog

All notable changes to Ostrich are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- `docs/CONTRACTS.md`: frozen v1 interfaces for runtime paths, QML singletons,
  config schema, `scheme.json`, IPC targets, CLI commands, and app templates.
- `docs/SUBAGENT_PLAN.md`: 12 workstreams, dependency waves, ownership rules,
  merge protocol, and a reference-feature map for the caelestia shell study.
- `docs/prompts/`: self-contained implementation prompts for WS0–WS11 plus
  `LAUNCH.md` orchestration guide.
- `PRD.md`: `CLI-01` (`ostrich` CLI) and `TERM-01` (terminal/desktop rice)
  components and a link to the implementation plan.
- `AGENTS.md`: source layout extended with `cli/`, `rice/`, `packaging/` and
  the packaged-template split.

### Changed

- `docs/README.md`: index now lists the contracts, plan, and prompt pack.

## [0.1.0] - 2026-11-19

### Added

- Repository bootstrap: branch model (`dev`, `test`, `main`), branch protection,
  CI quality gates, release automation, and rolling `dev` releases.
- `AGENTS.md` describing the GitHub and release workflow for agents.
- `PRD.md` describing the shell components and product requirements.
